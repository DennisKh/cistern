defmodule Cistern.MixProject do
  use Mix.Project

  def project do
    [
      app: :cistern,
      version: "0.1.1",
      elixir: "~> 1.17",
      description:
        "A Redix wrapper with a Poolboy-managed connection pool and typed read helpers.",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, "~> 1.0"},
      {:redix, "~> 1.3"},
      {:poolboy, "~> 1.5"},
      # test/dev
      {:excoveralls, ">= 0.0.0", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: :cistern,
      licenses: ["MIT"],
      maintainers: ["Denys Kharchuk"],
      links: %{"GitHub" => "https://github.com/DennisKh/cistern"},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # Dialyzer config. PLTs live in a dedicated dir so CI can cache them
  # independently of the churn-heavy _build directory.
  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :extra_return]
    ]
  end
end
