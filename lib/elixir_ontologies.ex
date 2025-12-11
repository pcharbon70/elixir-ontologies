defmodule ElixirOntologies do
  @moduledoc """
  OWL ontologies for modeling Elixir code structure, OTP runtime patterns,
  and code evolution.

  This module provides both ontology access functions and a high-level API for
  analyzing Elixir code and generating RDF knowledge graphs.

  ## Analysis API

  Use these functions to analyze Elixir code programmatically:

  - `analyze_file/2` - Analyze a single Elixir source file
  - `analyze_project/2` - Analyze an entire Mix project
  - `update_graph/2` - Update an existing graph with incremental analysis

  See the function documentation below for detailed usage examples.

  ## Ontology Modules

  This package provides five interconnected ontology modules:

  | Module | File | Description |
  |--------|------|-------------|
  | Core | `elixir-core.ttl` | Language-agnostic AST primitives, BFO/IAO alignment |
  | Structure | `elixir-structure.ttl` | Elixir modules, functions, protocols, behaviours, macros |
  | OTP | `elixir-otp.ttl` | OTP runtime patterns, supervision, GenServer, ETS |
  | Evolution | `elixir-evolution.ttl` | PROV-O provenance, versioning, change tracking |
  | Shapes | `elixir-shapes.ttl` | SHACL validation constraints |

  ## Accessing Ontology Files

  Use `ontology_path/1` to get the path to any ontology file:

      ElixirOntologies.ontology_path("elixir-core.ttl")
      # => "/path/to/priv/ontologies/elixir-core.ttl"

  Or list all available ontologies:

      ElixirOntologies.list_ontologies()
      # => ["elixir-core.ttl", "elixir-evolution.ttl", ...]

  ## Namespaces

  | Prefix | IRI |
  |--------|-----|
  | `core:` | `https://w3id.org/elixir-code/core#` |
  | `struct:` | `https://w3id.org/elixir-code/structure#` |
  | `otp:` | `https://w3id.org/elixir-code/otp#` |
  | `evo:` | `https://w3id.org/elixir-code/evolution#` |
  | `shapes:` | `https://w3id.org/elixir-code/shapes#` |

  ## Usage with RDF Libraries

  These ontologies can be loaded with any RDF library. For example, with `rdf_ex`:

      {:ok, graph} = RDF.Turtle.read_file(ElixirOntologies.ontology_path("elixir-core.ttl"))

  Or with `grax` for mapping to Elixir structs.

  ## Learn More

  See the guides for detailed documentation on each ontology module:

  - [Core Ontology Guide](core.html)
  - [Structure Ontology Guide](structure.html)
  - [OTP Ontology Guide](otp.html)
  - [Evolution Ontology Guide](evolution.html)
  - [Shapes Guide](shapes.html)
  """

  alias ElixirOntologies.Analyzer.{FileAnalyzer, ProjectAnalyzer}
  alias ElixirOntologies.{Config, Graph}

  @ontologies_dir "priv/ontologies"

  # ===========================================================================
  # Ontology File Access
  # ===========================================================================

  @doc """
  Returns the absolute path to the ontologies directory.

  ## Example

      ElixirOntologies.ontologies_dir()
      # => "/path/to/elixir_ontologies/priv/ontologies"
  """
  @spec ontologies_dir() :: String.t()
  def ontologies_dir do
    Application.app_dir(:elixir_ontologies, @ontologies_dir)
  end

  @doc """
  Returns the absolute path to a specific ontology file.

  ## Parameters

  - `filename` - The ontology filename (e.g., `"elixir-core.ttl"`)

  ## Example

      ElixirOntologies.ontology_path("elixir-core.ttl")
      # => "/path/to/elixir_ontologies/priv/ontologies/elixir-core.ttl"

  ## Available Ontologies

  - `elixir-core.ttl` - Core AST primitives
  - `elixir-structure.ttl` - Elixir code structure
  - `elixir-otp.ttl` - OTP runtime patterns
  - `elixir-evolution.ttl` - Code evolution and provenance
  - `elixir-shapes.ttl` - SHACL validation shapes
  """
  @spec ontology_path(String.t()) :: String.t()
  def ontology_path(filename) when is_binary(filename) do
    Path.join(ontologies_dir(), filename)
  end

  @doc """
  Lists all available ontology files.

  ## Example

      ElixirOntologies.list_ontologies()
      # => ["elixir-core.ttl", "elixir-evolution.ttl", "elixir-otp.ttl",
      #     "elixir-shapes.ttl", "elixir-structure.ttl"]
  """
  @spec list_ontologies() :: [String.t()]
  def list_ontologies do
    ontologies_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ttl"))
    |> Enum.sort()
  end

  @doc """
  Reads and returns the content of an ontology file.

  ## Parameters

  - `filename` - The ontology filename (e.g., `"elixir-core.ttl"`)

  ## Example

      {:ok, content} = ElixirOntologies.read_ontology("elixir-core.ttl")
  """
  @spec read_ontology(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def read_ontology(filename) when is_binary(filename) do
    filename
    |> ontology_path()
    |> File.read()
  end

  @doc """
  Returns a map of namespace prefixes to their IRIs.

  ## Example

      ElixirOntologies.namespaces()
      # => %{
      #   core: "https://w3id.org/elixir-code/core#",
      #   struct: "https://w3id.org/elixir-code/structure#",
      #   ...
      # }
  """
  @spec namespaces() :: %{atom() => String.t()}
  def namespaces do
    %{
      core: "https://w3id.org/elixir-code/core#",
      struct: "https://w3id.org/elixir-code/structure#",
      otp: "https://w3id.org/elixir-code/otp#",
      evo: "https://w3id.org/elixir-code/evolution#",
      shapes: "https://w3id.org/elixir-code/shapes#"
    }
  end

  @doc """
  Returns the IRI for a specific namespace prefix.

  ## Parameters

  - `prefix` - The namespace prefix atom (e.g., `:core`, `:struct`)

  ## Example

      ElixirOntologies.namespace(:core)
      # => "https://w3id.org/elixir-code/core#"
  """
  @spec namespace(atom()) :: String.t() | nil
  def namespace(prefix) when is_atom(prefix) do
    Map.get(namespaces(), prefix)
  end

  # ===========================================================================
  # Analysis API
  # ===========================================================================

  @doc """
  Analyzes a single Elixir source file and returns the RDF knowledge graph.

  This function wraps `FileAnalyzer.analyze/2` with a convenient interface
  for programmatic usage.

  ## Parameters

  - `file_path` - Path to the Elixir source file (.ex or .exs)
  - `opts` - Keyword list of options (optional)

  ## Options

  - `:base_iri` - Base IRI for generated resources (default: "https://example.org/code#")
  - `:include_source_text` - Include source code in graph (default: false)
  - `:include_git_info` - Include git provenance (default: true)

  ## Returns

  - `{:ok, graph}` - Successfully analyzed file, where `graph` is a `Graph.t()` struct
  - `{:error, reason}` - Analysis failed

  ## Examples

      # Basic usage
      {:ok, graph} = ElixirOntologies.analyze_file("lib/my_module.ex")

      # With custom base IRI
      {:ok, graph} = ElixirOntologies.analyze_file(
        "lib/my_module.ex",
        base_iri: "https://myapp.org/code#"
      )

      # Include source text
      {:ok, graph} = ElixirOntologies.analyze_file(
        "lib/my_module.ex",
        include_source_text: true
      )

      # Handle errors
      case ElixirOntologies.analyze_file("lib/missing.ex") do
        {:ok, graph} -> IO.puts("Success!")
        {:error, reason} -> IO.puts("Failed: \#{inspect(reason)}")
      end
  """
  @spec analyze_file(Path.t(), keyword()) :: {:ok, Graph.t()} | {:error, term()}
  def analyze_file(file_path, opts \\ []) do
    config = build_config_from_opts(opts)

    case FileAnalyzer.analyze(file_path, config) do
      {:ok, result} -> {:ok, result.graph}
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @doc """
  Analyzes a Mix project and returns a unified RDF knowledge graph.

  This function wraps `ProjectAnalyzer.analyze/2` with a convenient interface
  for programmatic usage.

  ## Parameters

  - `project_path` - Path to project root (containing mix.exs)
  - `opts` - Keyword list of options (optional)

  ## Options

  Configuration options:
  - `:base_iri` - Base IRI for generated resources
  - `:include_source_text` - Include source code in graph (default: false)
  - `:include_git_info` - Include git provenance (default: true)

  Analysis options:
  - `:exclude_tests` - Skip test/ directories (default: true)

  ## Returns

  - `{:ok, result}` - Successfully analyzed project
  - `{:error, reason}` - Analysis failed

  The success result is a map containing:
  - `:graph` - Unified `Graph.t()` with all triples
  - `:metadata` - Map with analysis statistics (file_count, module_count, etc.)
  - `:errors` - List of `{file_path, error_reason}` tuples for failed files

  ## Examples

      # Basic usage
      {:ok, result} = ElixirOntologies.analyze_project(".")
      IO.puts("Analyzed \#{result.metadata.file_count} files")
      IO.puts("Found \#{result.metadata.module_count} modules")

      # Analyze specific project
      {:ok, result} = ElixirOntologies.analyze_project("/path/to/project")

      # Include test files
      {:ok, result} = ElixirOntologies.analyze_project(".", exclude_tests: false)

      # Check for errors
      {:ok, result} = ElixirOntologies.analyze_project(".")
      if result.metadata.error_count > 0 do
        IO.puts("Some files had errors:")
        for {file, error} <- result.errors do
          IO.puts("  \#{file}: \#{inspect(error)}")
        end
      end
  """
  @spec analyze_project(Path.t(), keyword()) ::
          {:ok, %{graph: Graph.t(), metadata: map(), errors: list()}} | {:error, term()}
  def analyze_project(project_path, opts \\ []) do
    config = build_config_from_opts(opts)

    analyzer_opts = [
      config: config,
      exclude_tests: Keyword.get(opts, :exclude_tests, true)
    ]

    case ProjectAnalyzer.analyze(project_path, analyzer_opts) do
      {:ok, result} ->
        {:ok,
         %{
           graph: result.graph,
           metadata: %{
             file_count: result.metadata[:file_count] || length(result.files),
             module_count: result.metadata[:module_count] || 0,
             error_count: length(result.errors)
           },
           errors: result.errors
         }}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  @doc """
  Updates an existing RDF knowledge graph with incremental analysis.

  Note: This function currently performs full re-analysis as state files do not
  contain complete FileAnalyzer.Result structs. Future versions may support
  true incremental updates from persisted state.

  ## Parameters

  - `graph_file` - Path to existing graph file (.ttl format)
  - `opts` - Keyword list of options (optional)

  ## Options

  Configuration options:
  - `:base_iri` - Base IRI for generated resources
  - `:include_source_text` - Include source code in graph
  - `:include_git_info` - Include git provenance

  Analysis options:
  - `:project_path` - Path to project (default: ".")
  - `:exclude_tests` - Skip test/ directories (default: true)

  ## Returns

  - `{:ok, result}` - Successfully updated graph
  - `{:error, reason}` - Update failed

  The success result is a map containing:
  - `:graph` - Updated `Graph.t()`
  - `:metadata` - Map with analysis statistics

  ## Examples

      # Basic usage
      {:ok, result} = ElixirOntologies.update_graph("project.ttl")
      IO.puts("Analyzed \#{result.metadata.file_count} files")

      # Update specific project
      {:ok, result} = ElixirOntologies.update_graph(
        "project.ttl",
        project_path: "/path/to/project"
      )

      # Save updated graph
      {:ok, result} = ElixirOntologies.update_graph("project.ttl")
      :ok = Graph.save(result.graph, "project_updated.ttl")
  """
  @spec update_graph(Path.t(), keyword()) ::
          {:ok, %{graph: Graph.t(), metadata: map()}} | {:error, term()}
  def update_graph(graph_file, opts \\ []) do
    if File.exists?(graph_file) do
      case Graph.load(graph_file) do
        {:ok, _graph} ->
          # Perform full analysis (state files don't have complete FileAnalyzer.Result)
          project_path = Keyword.get(opts, :project_path, ".")

          case analyze_project(project_path, opts) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, {:invalid_graph, reason}}
      end
    else
      {:error, :graph_not_found}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_config_from_opts(opts) do
    base_config = Config.default()

    base_config
    |> maybe_put(:base_iri, Keyword.get(opts, :base_iri))
    |> maybe_put(:include_source_text, Keyword.get(opts, :include_source_text))
    |> maybe_put(:include_git_info, Keyword.get(opts, :include_git_info))
  end

  defp maybe_put(config, _key, nil), do: config

  defp maybe_put(config, key, value) do
    Map.put(config, key, value)
  end

  defp normalize_error(:enoent), do: :file_not_found
  defp normalize_error(:not_found), do: :project_not_found
  defp normalize_error(:invalid_path), do: :project_not_found
  defp normalize_error({:file_error, :enoent}), do: :file_not_found
  defp normalize_error(other), do: other
end
