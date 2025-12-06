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
      name: "Elixir Ontologies",
      source_url: @source_url
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

      # Development and documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Static analysis
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Property-based testing
      {:stream_data, "~> 1.0", only: :test},

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
      "guides/core.md",
      "guides/structure.md",
      "guides/otp.md",
      "guides/evolution.md",
      "guides/shapes.md"
    ]
  end

  defp groups_for_extras do
    [
      "Ontology Guides": ~w(
        guides/core.md
        guides/structure.md
        guides/otp.md
        guides/evolution.md
        guides/shapes.md
      )
    ]
  end
end
