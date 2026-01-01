defmodule ElixirOntologies.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/elixir-ontologies"

  def project do
    [
      app: :elixir_ontologies,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      name: "Elixir Ontologies",
      source_url: @source_url
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # RDF and knowledge graph support
      {:rdf, "~> 2.0"},
      {:sparql, "~> 0.3", optional: true},

      # Embedded triple store (optional - for persistent knowledge graph)
      {:triple_store, path: "../triple_store", optional: true},

      # HTTP client for Hex.pm API
      {:req, "~> 0.5"},
      {:castore, "~> 1.0"},

      # Development and documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Static analysis
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Property-based testing
      {:stream_data, "~> 1.0", only: :test},

      # HTTP mocking for tests
      {:bypass, "~> 2.1", only: :test},

      # Benchmarking
      {:benchee, "~> 1.3", only: :dev}
    ]
  end

  defp description do
    """
    OWL ontologies for modeling Elixir code structure, OTP runtime patterns,
    and code evolution. Designed for semantic code analysis, knowledge graphs,
    and LLM-based code understanding.
    """
  end

  defp package do
    [
      name: "elixir_ontologies",
      files: ~w(
        lib
        priv
        guides
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      assets: %{"priv/ontologies" => "ontologies"}
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      # Getting Started
      "guides/getting-started.md",
      # Ontology Concepts
      "guides/core.md",
      "guides/structure.md",
      "guides/otp.md",
      "guides/evolution.md",
      "guides/shapes.md",
      # How It Works
      "guides/architecture.md",
      "guides/pipeline.md",
      "guides/extractors.md",
      "guides/builders.md",
      "guides/iri-generation.md",
      # API Reference
      "guides/api/analysis.md",
      "guides/api/configuration.md",
      "guides/api/validation.md",
      "guides/api/namespaces.md",
      # Tools & Usage
      "guides/knowledge-graph.md",
      "guides/users/triple-store-iex.md",
      "guides/users/analyzing-code.md",
      "guides/users/evolution-tracking.md",
      "guides/users/hex-batch-analyzer.md",
      "guides/users/llm-code-generation.md",
      "guides/users/querying.md",
      "guides/users/shacl-validation.md"
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": ~w(
        guides/getting-started.md
      ),
      "Ontology Concepts": ~w(
        guides/core.md
        guides/structure.md
        guides/otp.md
        guides/evolution.md
        guides/shapes.md
      ),
      "How It Works": ~w(
        guides/architecture.md
        guides/pipeline.md
        guides/extractors.md
        guides/builders.md
        guides/iri-generation.md
      ),
      "API Reference": ~w(
        guides/api/analysis.md
        guides/api/configuration.md
        guides/api/validation.md
        guides/api/namespaces.md
      ),
      "Tools & Usage": ~w(
        guides/knowledge-graph.md
        guides/users/triple-store-iex.md
        guides/users/analyzing-code.md
        guides/users/evolution-tracking.md
        guides/users/hex-batch-analyzer.md
        guides/users/llm-code-generation.md
        guides/users/querying.md
        guides/users/shacl-validation.md
      )
    ]
  end
end
