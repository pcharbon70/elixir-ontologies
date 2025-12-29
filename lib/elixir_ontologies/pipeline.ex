defmodule ElixirOntologies.Pipeline do
  @moduledoc """
  End-to-end pipeline for analyzing Elixir code and generating RDF graphs.

  This module integrates the analyzer, extractors, and builders to provide
  a complete pipeline from source code to RDF knowledge graphs. It bridges
  the gap between extraction (ModuleAnalysis structs) and building (Orchestrator).

  ## Usage

      alias ElixirOntologies.Pipeline

      # Analyze a file and build RDF graph
      {:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")
      result.graph  # => %ElixirOntologies.Graph{}

      # Analyze source code string
      {:ok, result} = Pipeline.analyze_string_and_build(source_code)

      # Build graph from existing module analysis
      graph = Pipeline.build_graph_for_modules(modules, context)

  ## Parallel Execution

  The pipeline supports parallel execution at two levels:

  1. **Module-level parallelism**: Multiple modules processed concurrently
  2. **Builder-level parallelism**: Within each module, builders run concurrently

  Both are enabled by default for optimal performance.

  ## Options

  - `:parallel` - Enable/disable parallel processing (default: `true`)
  - `:timeout` - Timeout for parallel tasks in ms (default: `5000`)
  - `:include` - List of builder atoms to include (default: all)
  - `:exclude` - List of builder atoms to exclude (default: `[]`)

  ## Examples

      # Basic usage
      {:ok, result} = Pipeline.analyze_and_build("lib/my_app.ex")

      # With custom config
      config = Config.new(base_iri: "https://myapp.org/code#")
      {:ok, result} = Pipeline.analyze_and_build("lib/my_app.ex", config)

      # Disable parallel processing
      {:ok, result} = Pipeline.analyze_and_build("lib/my_app.ex", config, parallel: false)
  """

  alias ElixirOntologies.{Config, Graph}
  alias ElixirOntologies.Analyzer.FileAnalyzer
  alias ElixirOntologies.Analyzer.FileAnalyzer.ModuleAnalysis
  alias ElixirOntologies.Builders.{Orchestrator, Context}

  @default_timeout 5_000
  @default_parallel true

  # ===========================================================================
  # Public API - High-Level Functions
  # ===========================================================================

  @doc """
  Analyzes an Elixir source file and builds a complete RDF graph.

  This is the main entry point for file analysis. It combines file parsing,
  extraction, and RDF building into a single operation.

  ## Parameters

  - `file_path` - Path to the Elixir source file
  - `config` - Configuration options (default: `Config.default()`)
  - `opts` - Pipeline options (parallel, timeout, include, exclude)

  ## Returns

  - `{:ok, result}` - Success with FileAnalyzer.Result containing populated graph
  - `{:error, reason}` - Failure with error reason

  ## Examples

      {:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")
      Graph.statement_count(result.graph)  # => 42
  """
  @spec analyze_and_build(String.t(), Config.t(), keyword()) ::
          {:ok, FileAnalyzer.Result.t()} | {:error, term()}
  def analyze_and_build(file_path, config \\ Config.default(), opts \\ []) do
    with {:ok, result} <- FileAnalyzer.analyze(file_path, config) do
      context = build_context(config, result.file_path)
      graph = build_graph_for_modules(result.modules, context, opts)
      {:ok, %{result | graph: graph}}
    end
  end

  @doc """
  Analyzes Elixir source code from a string and builds a complete RDF graph.

  Same as `analyze_and_build/3` but for source code strings instead of files.

  ## Parameters

  - `source_code` - Elixir source code as a string
  - `config` - Configuration options (default: `Config.default()`)
  - `opts` - Pipeline options

  ## Returns

  - `{:ok, result}` - Success with FileAnalyzer.Result containing populated graph
  - `{:error, reason}` - Failure with error reason

  ## Examples

      source = \"\"\"
      defmodule MyModule do
        def hello, do: :world
      end
      \"\"\"

      {:ok, result} = Pipeline.analyze_string_and_build(source)
  """
  @spec analyze_string_and_build(String.t(), Config.t(), keyword()) ::
          {:ok, FileAnalyzer.Result.t()} | {:error, term()}
  def analyze_string_and_build(source_code, config \\ Config.default(), opts \\ []) do
    with {:ok, result} <- FileAnalyzer.analyze_string(source_code, config) do
      context = build_context(config, nil)
      graph = build_graph_for_modules(result.modules, context, opts)
      {:ok, %{result | graph: graph}}
    end
  end

  # ===========================================================================
  # Public API - Graph Building
  # ===========================================================================

  @doc """
  Builds an RDF graph for a list of module analysis results.

  This function converts ModuleAnalysis structs to the format expected by
  the Orchestrator and coordinates graph building for all modules.

  ## Parameters

  - `modules` - List of ModuleAnalysis structs from FileAnalyzer
  - `context` - Builder context with base IRI
  - `opts` - Pipeline options

  ## Options

  - `:parallel` - Enable parallel module processing (default: `true`)
  - `:timeout` - Timeout for parallel tasks in ms (default: `5000`)
  - `:include` - List of builder atoms to include
  - `:exclude` - List of builder atoms to exclude

  ## Returns

  An `ElixirOntologies.Graph` containing all triples for all modules.

  ## Examples

      modules = [%ModuleAnalysis{...}, %ModuleAnalysis{...}]
      context = Context.new(base_iri: "https://example.org/code#")
      graph = Pipeline.build_graph_for_modules(modules, context)
  """
  @spec build_graph_for_modules([ModuleAnalysis.t()], Context.t(), keyword()) :: Graph.t()
  def build_graph_for_modules(modules, context, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, @default_parallel)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Build graphs for each module (potentially in parallel)
    rdf_graphs =
      if parallel do
        build_modules_parallel(modules, context, timeout, opts)
      else
        build_modules_sequential(modules, context, opts)
      end

    # Merge all RDF graphs into single ElixirOntologies.Graph
    merge_graphs(rdf_graphs)
  end

  # ===========================================================================
  # Private - Module Processing
  # ===========================================================================

  defp build_modules_parallel(modules, context, timeout, opts) do
    modules
    |> Task.async_stream(
      fn module -> build_module_graph(module, context, opts) end,
      timeout: timeout,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, graph}} -> [graph]
      {:ok, {:error, _reason}} -> []
      {:exit, _reason} -> []
    end)
  end

  defp build_modules_sequential(modules, context, opts) do
    modules
    |> Enum.map(fn module -> build_module_graph(module, context, opts) end)
    |> Enum.flat_map(fn
      {:ok, graph} -> [graph]
      {:error, _reason} -> []
    end)
  end

  defp build_module_graph(module_analysis, context, opts) do
    # Convert ModuleAnalysis to Orchestrator format
    analysis = convert_module_analysis(module_analysis)

    # Update context with module name for proper IRI generation
    module_context = update_context_for_module(context, module_analysis)

    # Build the graph using Orchestrator
    Orchestrator.build_module_graph(analysis, module_context, opts)
  end

  # ===========================================================================
  # Private - Conversion
  # ===========================================================================

  @doc false
  def convert_module_analysis(%ModuleAnalysis{} = ma) do
    %{
      module: ma.module_info,
      functions: ma.functions || [],
      protocols: extract_protocols(ma.protocols),
      behaviours: extract_behaviours(ma.behaviors),
      structs: extract_structs(ma),
      types: ma.types || [],
      genservers: extract_otp_pattern(ma.otp_patterns, :genserver),
      supervisors: extract_otp_pattern(ma.otp_patterns, :supervisor),
      agents: extract_otp_pattern(ma.otp_patterns, :agent),
      tasks: extract_otp_pattern(ma.otp_patterns, :task),
      # Phase 17: Call graph and control flow
      calls: ma.calls || [],
      control_flow: ma.control_flow || %{},
      exceptions: ma.exceptions || %{}
    }
  end

  defp extract_protocols(%{protocol: nil, implementations: []}), do: []
  defp extract_protocols(%{protocol: protocol}) when not is_nil(protocol), do: [protocol]
  defp extract_protocols(_), do: []

  defp extract_behaviours(%{definition: nil, implementations: []}), do: []
  defp extract_behaviours(%{definition: definition}) when not is_nil(definition), do: [definition]
  defp extract_behaviours(_), do: []

  defp extract_structs(%ModuleAnalysis{} = _ma) do
    # Struct detection is not yet implemented in the analyzer
    # defstruct is a macro call, not an attribute, so it requires
    # separate extraction logic from the module body AST
    []
  end

  defp extract_otp_pattern(nil, _key), do: []

  defp extract_otp_pattern(otp_patterns, key) when is_map(otp_patterns) do
    case Map.get(otp_patterns, key) do
      nil -> []
      pattern when is_list(pattern) -> pattern
      pattern -> [pattern]
    end
  end

  # ===========================================================================
  # Private - Context Helpers
  # ===========================================================================

  defp build_context(config, file_path) do
    Context.new(
      base_iri: config.base_iri,
      file_path: file_path,
      config: %{
        include_source_text: config.include_source_text,
        include_git_info: config.include_git_info
      }
    )
  end

  defp update_context_for_module(context, %ModuleAnalysis{name: module_name}) do
    Context.with_metadata(context, %{current_module: module_name})
  end

  # ===========================================================================
  # Private - Graph Merging
  # ===========================================================================

  defp merge_graphs([]), do: Graph.new()

  defp merge_graphs(rdf_graphs) do
    base_graph = Graph.new()

    Enum.reduce(rdf_graphs, base_graph, fn rdf_graph, acc ->
      # rdf_graph is an RDF.Graph from Orchestrator
      Graph.merge(acc, rdf_graph)
    end)
  end
end
