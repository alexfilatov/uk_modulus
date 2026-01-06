defmodule UkModulus.VocalinkData do
  @moduledoc """
  GenServer that manages Vocalink modulus checking data.

  The library ships with the official Vocalink data files bundled in priv/data.
  Data is loaded into ETS on startup for fast concurrent access.

  Optionally, the GenServer can check for updates from Vocalink's website
  if `:auto_update` is enabled in the application config.
  """
  use GenServer
  require Logger

  @ets_table :uk_modulus_weight_table
  @ets_substitutions :uk_modulus_substitutions

  # Official Vocalink data URLs
  @weight_url "https://www.vocalink.com/media/1plbrihn/valacdos.txt"
  @substitution_url "https://www.vocalink.com/media/tedlwtxz/scsubtab.txt"

  # Check for updates every 30 days (if auto_update is enabled)
  @update_interval_ms 30 * 24 * 60 * 60 * 1000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get weight rules for a sort code.
  Returns list of {start_sort, end_sort, algorithm, weights, exception} tuples.
  """
  def get_weight_rules(sort_code) when is_binary(sort_code) do
    sort_int = String.to_integer(sort_code)

    case :ets.lookup(@ets_table, :rules) do
      [{:rules, rules}] ->
        Enum.filter(rules, fn {start_sort, end_sort, _, _, _} ->
          sort_int >= start_sort and sort_int <= end_sort
        end)

      [] ->
        []
    end
  end

  @doc """
  Get substitution sort code for exception 5.
  """
  def get_substitution(sort_code) do
    case :ets.lookup(@ets_substitutions, sort_code) do
      [{^sort_code, substitute}] -> substitute
      [] -> sort_code
    end
  end

  @doc """
  Check if data is loaded and ready.
  """
  def ready? do
    case :ets.info(@ets_table) do
      :undefined -> false
      _ -> :ets.lookup(@ets_table, :rules) != []
    end
  end

  @doc """
  Force a refresh of the data from Vocalink's website.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Get the number of loaded weight rules.
  """
  def rule_count do
    case :ets.lookup(@ets_table, :rules) do
      [{:rules, rules}] -> length(rules)
      [] -> 0
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@ets_substitutions, [:set, :public, :named_table, read_concurrency: true])

    # Load bundled data immediately
    load_bundled_data()

    state = %{
      last_update: nil,
      update_in_progress: false
    }

    # Schedule auto-update check if enabled
    if Application.get_env(:uk_modulus, :auto_update, false) do
      schedule_update_check()
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:check_for_updates, state) do
    if state.update_in_progress do
      {:noreply, state}
    else
      Logger.info("[UkModulus] Checking for updates from Vocalink...")
      start_async_update(state)
    end
  end

  @impl true
  def handle_info({:update_complete, :ok}, state) do
    Logger.info("[UkModulus] Update complete")
    schedule_update_check()
    {:noreply, %{state | update_in_progress: false, last_update: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:update_complete, {:error, reason}}, state) do
    Logger.warning("[UkModulus] Update failed: #{inspect(reason)}")
    schedule_update_check()
    {:noreply, %{state | update_in_progress: false}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    if state.update_in_progress do
      {:noreply, state}
    else
      Logger.info("[UkModulus] Manual refresh requested")
      start_async_update(state)
    end
  end

  # --- Private Functions ---

  defp start_async_update(state) do
    parent = self()

    Task.start(fn ->
      result = download_and_load_data()
      send(parent, {:update_complete, result})
    end)

    {:noreply, %{state | update_in_progress: true}}
  end

  defp schedule_update_check do
    Process.send_after(self(), :check_for_updates, @update_interval_ms)
  end

  defp load_bundled_data do
    priv_dir = :code.priv_dir(:uk_modulus)

    weight_path =
      case priv_dir do
        {:error, _} -> "priv/data/valacdos.txt"
        dir -> Path.join([to_string(dir), "data", "valacdos.txt"])
      end

    sub_path =
      case priv_dir do
        {:error, _} -> "priv/data/scsubtab.txt"
        dir -> Path.join([to_string(dir), "data", "scsubtab.txt"])
      end

    if File.exists?(weight_path) do
      rules = parse_weight_file(File.read!(weight_path))
      :ets.insert(@ets_table, {:rules, rules})
      Logger.info("[UkModulus] Loaded #{length(rules)} weight rules from bundled data")
    else
      Logger.error("[UkModulus] Bundled weight file not found: #{weight_path}")
    end

    if File.exists?(sub_path) do
      subs = parse_substitution_file(File.read!(sub_path))

      Enum.each(subs, fn {from, to} ->
        :ets.insert(@ets_substitutions, {from, to})
      end)

      Logger.info("[UkModulus] Loaded #{length(subs)} substitution rules from bundled data")
    else
      Logger.warning("[UkModulus] Bundled substitution file not found: #{sub_path}")
    end
  end

  defp download_and_load_data do
    with {:ok, weight_data} <- http_get(@weight_url),
         {:ok, sub_data} <- http_get(@substitution_url) do
      # Parse and load weight rules
      rules = parse_weight_file(weight_data)
      :ets.insert(@ets_table, {:rules, rules})
      Logger.info("[UkModulus] Updated #{length(rules)} weight rules from Vocalink")

      # Parse and load substitution rules
      subs = parse_substitution_file(sub_data)
      :ets.delete_all_objects(@ets_substitutions)

      Enum.each(subs, fn {from, to} ->
        :ets.insert(@ets_substitutions, {from, to})
      end)

      Logger.info("[UkModulus] Updated #{length(subs)} substitution rules from Vocalink")

      :ok
    else
      {:error, reason} ->
        Logger.error("[UkModulus] Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp http_get(url) do
    case Req.get(url, retry: false, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_weight_file(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_weight_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_weight_line(line) do
    parts = String.split(line, ~r/\s+/, trim: true)

    case parts do
      [start_sort, end_sort, algo | weights] when length(weights) >= 14 ->
        algorithm =
          case String.upcase(algo) do
            "MOD10" -> :mod10
            "MOD11" -> :mod11
            "DBLAL" -> :dblal
            _ -> :mod11
          end

        weight_values =
          weights
          |> Enum.take(14)
          |> Enum.map(&String.to_integer/1)

        # Check for exception number (15th value after weights)
        exception =
          if length(weights) > 14 do
            case Integer.parse(Enum.at(weights, 14) || "") do
              {n, _} -> n
              :error -> nil
            end
          else
            nil
          end

        {String.to_integer(start_sort), String.to_integer(end_sort), algorithm, weight_values,
         exception}

      _ ->
        nil
    end
  end

  defp parse_substitution_file(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, trim: true) do
        [from, to] -> {from, to}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
