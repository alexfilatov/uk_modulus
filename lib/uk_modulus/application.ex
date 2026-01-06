defmodule UkModulus.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UkModulus.VocalinkData
    ]

    opts = [strategy: :one_for_one, name: UkModulus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
