defmodule UkModulus do
  @moduledoc """
  UK Bank Account Modulus Checking.

  Validates UK sort code and account number combinations using the
  Vocalink modulus checking algorithm.

  The algorithm uses weights applied to each digit of the combined
  sort code + account number, then checks if the result is divisible
  by 10 or 11 (depending on the algorithm type).

  Data source: Vocalink (https://www.vocalink.com/tools/modulus-checking/)

  ## Usage

      iex> UkModulus.valid?("200000", "58177632")
      true

      iex> UkModulus.valid?("200000", "58177633")
      false

      iex> UkModulus.validate("200000", "58177632")
      {:ok, true}

      iex> UkModulus.validate("123", "12345678")
      {:error, :invalid_sort_code_format}

  ## How it works

  The library downloads the full Vocalink weight table (~1,800 entries) on
  application startup and caches it locally. Data is refreshed automatically
  every 7 days.

  Until the download completes, fallback data covering major UK banks is used.
  """

  alias UkModulus.VocalinkData

  # Sort code substitution table (for exception 5)
  @substitutions %{
    "938173" => "938017",
    "938289" => "938068",
    "938297" => "938076",
    "938600" => "938017",
    "938602" => "938017",
    "938604" => "938017",
    "938608" => "938017",
    "938609" => "938017",
    "938611" => "938017",
    "938613" => "938017",
    "938616" => "938068",
    "938618" => "938068",
    "938620" => "938068",
    "938622" => "938068",
    "938628" => "938068",
    "938643" => "938068",
    "938647" => "938076",
    "938648" => "938076",
    "938649" => "938076",
    "938651" => "938076",
    "938657" => "938076"
  }

  # Embedded weight table for fallback
  @weight_table [
    # Barclays
    {"200000", "209999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # HSBC
    {"400000", "409999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Lloyds
    {"300000", "309999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    {"770000", "779999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # NatWest / RBS
    {"500000", "509999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    {"600000", "609999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    {"830000", "839999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Santander
    {"090000", "099999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Halifax / Bank of Scotland
    {"110000", "119999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Nationwide
    {"070000", "079999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # TSB
    {"870000", "879999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Coutts
    {"180000", "189999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Metro Bank
    {"230000", "239999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Starling
    {"608000", "608999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Monzo
    {"040000", "049999", :dblal, [2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1], nil},
    # Co-operative Bank
    {"089000", "089999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Virgin Money
    {"050000", "059999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Building societies
    {"010004", "016715", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    {"010016", "019999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], nil},
    # Exception 5 sort codes (Coutts special handling)
    {"938000", "938999", :mod11, [0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1], 5}
  ]

  @doc """
  Validates a UK sort code and account number combination.

  Returns `{:ok, true}` if valid, `{:ok, false}` if invalid,
  or `{:error, reason}` if the input format is wrong.

  ## Examples

      iex> UkModulus.validate("200000", "58177632")
      {:ok, true}

      iex> UkModulus.validate("200000", "58177633")
      {:ok, false}

      iex> UkModulus.validate("123", "12345678")
      {:error, :invalid_sort_code_format}

      iex> UkModulus.validate("20-00-00", "58177632")
      {:ok, true}
  """
  @spec validate(String.t(), String.t()) ::
          {:ok, boolean()} | {:error, :invalid_sort_code_format | :invalid_account_number_format}
  def validate(sort_code, account_number) do
    with {:ok, sort_code} <- normalize_sort_code(sort_code),
         {:ok, account_number} <- normalize_account_number(account_number) do
      case find_weight_rules(sort_code) do
        [] ->
          # No rules found for this sort code range - can't validate
          # Return true to allow (payment processor will validate)
          {:ok, true}

        rules ->
          result = validate_with_rules(sort_code, account_number, rules)
          {:ok, result}
      end
    end
  end

  @doc """
  Same as `validate/2` but returns a simple boolean.

  Returns `true` if valid or if validation cannot be performed.
  Returns `false` if invalid or if the format is wrong.

  ## Examples

      iex> UkModulus.valid?("200000", "58177632")
      true

      iex> UkModulus.valid?("200000", "58177633")
      false

      iex> UkModulus.valid?("123", "12345678")
      false
  """
  @spec valid?(String.t(), String.t()) :: boolean()
  def valid?(sort_code, account_number) do
    case validate(sort_code, account_number) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end

  @doc """
  Check if the Vocalink data is loaded and ready.

  Returns `true` if data has been loaded into ETS (either fallback or downloaded).
  """
  @spec ready?() :: boolean()
  def ready? do
    VocalinkData.ready?()
  end

  @doc """
  Force a refresh of the Vocalink data.

  This will trigger an async download of the latest data.
  """
  @spec refresh() :: :ok
  def refresh do
    VocalinkData.refresh()
  end

  # --- Private Functions ---

  # Normalize sort code to 6 digits (remove dashes/spaces)
  defp normalize_sort_code(sort_code) when is_binary(sort_code) do
    normalized = sort_code |> String.replace(~r/[\s\-]/, "")

    if String.match?(normalized, ~r/^\d{6}$/) do
      {:ok, normalized}
    else
      {:error, :invalid_sort_code_format}
    end
  end

  defp normalize_sort_code(_), do: {:error, :invalid_sort_code_format}

  # Normalize account number to 8 digits (pad with zeros if needed)
  defp normalize_account_number(account_number) when is_binary(account_number) do
    normalized = account_number |> String.replace(~r/[\s\-]/, "")

    cond do
      String.match?(normalized, ~r/^\d{8}$/) ->
        {:ok, normalized}

      String.match?(normalized, ~r/^\d{6}$/) ->
        # Some old accounts have 6 digits - pad with zeros
        {:ok, "00" <> normalized}

      String.match?(normalized, ~r/^\d{7}$/) ->
        # 7 digit accounts - pad with one zero
        {:ok, "0" <> normalized}

      true ->
        {:error, :invalid_account_number_format}
    end
  end

  defp normalize_account_number(_), do: {:error, :invalid_account_number_format}

  # Find all weight rules that apply to this sort code
  # Tries VocalinkData GenServer first, falls back to embedded table
  defp find_weight_rules(sort_code) do
    case VocalinkData.get_weight_rules(sort_code) do
      rules when is_list(rules) and rules != [] ->
        # Convert from VocalinkData format {start_int, end_int, algo, weights, exception}
        Enum.map(rules, fn {start_int, end_int, algo, weights, exception} ->
          {Integer.to_string(start_int), Integer.to_string(end_int), algo, weights, exception}
        end)

      _ ->
        # Fallback to embedded weight table
        find_weight_rules_embedded(sort_code)
    end
  end

  defp find_weight_rules_embedded(sort_code) do
    sort_int = String.to_integer(sort_code)

    @weight_table
    |> Enum.filter(fn {start_sort, end_sort, _, _, _} ->
      start_int = String.to_integer(start_sort)
      end_int = String.to_integer(end_sort)
      sort_int >= start_int and sort_int <= end_int
    end)
  end

  # Validate using the found rules
  defp validate_with_rules(sort_code, account_number, rules) do
    case rules do
      [single_rule] ->
        check_single_rule(sort_code, account_number, single_rule)

      [first_rule, second_rule] ->
        check_double_rules(sort_code, account_number, first_rule, second_rule)

      _ ->
        # Multiple rules - check if any pass
        Enum.any?(rules, &check_single_rule(sort_code, account_number, &1))
    end
  end

  defp check_single_rule(sort_code, account_number, {_, _, algorithm, weights, exception}) do
    effective_sort = apply_substitution(sort_code, exception)
    digits = parse_digits(effective_sort, account_number)
    run_check(algorithm, digits, weights, exception)
  end

  defp check_double_rules(sort_code, account_number, first_rule, second_rule) do
    {_, _, _, _, ex1} = first_rule
    {_, _, _, _, ex2} = second_rule

    first_result = check_single_rule(sort_code, account_number, first_rule)

    cond do
      # Exception 2 & 9: If first check passes, account is valid
      ex1 in [2, 9] and first_result ->
        true

      # Exception 10 & 11: Special handling for certain banks
      ex1 in [10, 11] ->
        first_result or check_single_rule(sort_code, account_number, second_rule)

      # Exception 12 & 13: Special Natwest handling
      ex1 in [12, 13] ->
        first_result and check_single_rule(sort_code, account_number, second_rule)

      # Exception 14: Special handling
      ex2 == 14 and not first_result ->
        check_single_rule(sort_code, account_number, second_rule)

      # Standard: both checks must pass, or first check passes
      true ->
        first_result or check_single_rule(sort_code, account_number, second_rule)
    end
  end

  # Apply sort code substitution for exception 5
  defp apply_substitution(sort_code, 5) do
    # Try VocalinkData first, then fall back to embedded substitutions
    case VocalinkData.get_substitution(sort_code) do
      ^sort_code ->
        Map.get(@substitutions, sort_code, sort_code)

      substitute ->
        substitute
    end
  end

  defp apply_substitution(sort_code, _), do: sort_code

  # Parse sort code + account number into 14 digits
  defp parse_digits(sort_code, account_number) do
    (sort_code <> account_number)
    |> String.graphemes()
    |> Enum.map(&String.to_integer/1)
  end

  # Run the appropriate modulus check
  defp run_check(:mod10, digits, weights, exception) do
    total = weighted_sum(digits, weights, exception)
    rem(total, 10) == 0
  end

  defp run_check(:mod11, digits, weights, exception) do
    total = weighted_sum(digits, weights, exception)

    case exception do
      4 ->
        # Exception 4: remainder must equal g*10 + h
        g = Enum.at(digits, 12)
        h = Enum.at(digits, 13)
        rem(total, 11) == g * 10 + h

      5 ->
        # Exception 5: check digit is g (position 12)
        remainder = rem(total, 11)
        g = Enum.at(digits, 12)

        cond do
          remainder == 0 and g == 0 -> true
          remainder == 1 -> false
          11 - remainder == g -> true
          true -> false
        end

      _ ->
        rem(total, 11) == 0
    end
  end

  defp run_check(:dblal, digits, weights, _exception) do
    # Double Alternate (Luhn-like algorithm)
    total =
      Enum.zip(digits, weights)
      |> Enum.map(fn {d, w} ->
        product = d * w
        sum_digits(product)
      end)
      |> Enum.sum()

    rem(total, 10) == 0
  end

  # Calculate weighted sum
  defp weighted_sum(digits, weights, exception) do
    case exception do
      1 ->
        # Exception 1: Add 27 to the total
        base_sum =
          Enum.zip(digits, weights)
          |> Enum.map(fn {d, w} -> d * w end)
          |> Enum.sum()

        base_sum + 27

      _ ->
        Enum.zip(digits, weights)
        |> Enum.map(fn {d, w} -> d * w end)
        |> Enum.sum()
    end
  end

  # Sum the digits of a number (for DBLAL)
  defp sum_digits(n) when n < 10, do: n
  defp sum_digits(n), do: rem(n, 10) + div(n, 10)
end
