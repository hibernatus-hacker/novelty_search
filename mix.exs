defmodule NoveltySearch.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/novelty_search"

  def project do
    [
      app: :novelty_search,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      preferred_cli_env: [
        "test.watch": :test
      ],
      dialyzer: dialyzer(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:nx, "~> 0.6"},
      {:jason, "~> 1.4"},
      
      # Optional dependencies
      {:exla, "~> 0.6", optional: true},
      
      # Development and testing
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    A comprehensive Elixir implementation of Novelty Search, an evolutionary algorithm 
    that evolves behaviors based on their novelty rather than fitness. Includes maze 
    navigation environment, parallel processing, comprehensive analysis tools, and 
    extensible behavior characterization system.
    """
  end

  defp package do
    [
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/novelty_search"
      },
      files: ~w[
        lib
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      ]
    ]
  end

  defp docs do
    [
      main: "NoveltySearch",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/getting_started.md",
        "guides/custom_domains.md",
        "guides/performance.md"
      ],
      groups_for_extras: [
        "Guides": ~r/guides\/.?/
      ],
      groups_for_modules: [
        "Core Components": [
          NoveltySearch,
          NoveltySearch.Core,
          NoveltySearch.Behaviors
        ],
        "Environments": [
          NoveltySearch.Maze
        ],
        "Integration": [
          NoveltySearch.NEATIntegration
        ],
        "Analysis & Export": [
          NoveltySearch.Analysis,
          NoveltySearch.Serialization
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      quality: ["format", "credo --strict", "dialyzer"],
      "test.watch": ["test.watch --stale"]
    ]
  end
end