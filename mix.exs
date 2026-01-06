defmodule UkModulus.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/alexfilatov/uk_modulus"

  def project do
    [
      app: :uk_modulus,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "UkModulus",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {UkModulus.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    UK bank account modulus checking using the Vocalink algorithm.
    Validates UK sort code and account number combinations.
    """
  end

  defp package do
    [
      name: "uk_modulus",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Alex Filatov"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
