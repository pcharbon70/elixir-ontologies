defmodule ElixirOntologies.Analyzer.FileAnalyzer do
  @moduledoc """
  Analyzes a single Elixir source file and produces a complete RDF knowledge graph.

  This module orchestrates all extractors from Phases 1-7 to analyze file content,
  including modules, functions, types, protocols, behaviors, OTP patterns, and more.
  It integrates with Git and Project modules to provide repository and project context.

  ## Usage

      alias ElixirOntologies.Analyzer.FileAnalyzer
      alias ElixirOntologies.Config

      # Analyze a file with default config
      {:ok, result} = FileAnalyzer.analyze("lib/my_module.ex")

      # Access results
      result.modules          # List of analyzed modules
      result.graph            # RDF knowledge graph
      result.source_file      # Git source file info (if in repo)
      result.project          # Mix project info (if in project)

      # Analyze with custom config
      config = Config.new(include_git_info: true, base_iri: "https://example.com/")
      {:ok, result} = FileAnalyzer.analyze("lib/my_module.ex", config)

      # Bang variant (raises on error)
      result = FileAnalyzer.analyze!("lib/my_module.ex")

  ## Analysis Pipeline

  The analyzer performs the following steps:

  1. Read and parse the source file
  2. Detect Git repository and Mix project context
  3. Extract all modules from the AST
  4. For each module:
     - Extract functions, clauses, parameters, guards
     - Extract types, specs, attributes
     - Extract protocols and implementations
     - Extract behavior definitions and implementations
     - Extract OTP patterns (GenServer, Supervisor, etc.)
     - Extract macros and quotes
  5. Build unified RDF knowledge graph
  6. Add source location metadata
  7. Add Git provenance information (if available)

  ## Result Structure

  Returns a `FileAnalyzer.Result` struct containing:

  - `file_path` - Absolute path to the analyzed file
  - `modules` - List of `ModuleAnalysis` structs
  - `graph` - RDF knowledge graph with all extracted information
  - `source_file` - Git source file metadata (nil if not in repository)
  - `project` - Mix project metadata (nil if not in project)
  - `metadata` - File statistics and analysis metrics

  ## Configuration

  Respects `ElixirOntologies.Config` options:

  - `base_iri` - Base IRI for generated URIs
  - `include_git_info` - Whether to detect and include Git metadata
  - `include_source_text` - Whether to include source code in graph

  ## Error Handling

  Hard errors (returns `{:error, reason}`):
  - File not found
  - File not readable
  - Invalid Elixir syntax (parse error)
  - Invalid configuration

  Soft errors (logged but analysis continues):
  - Individual extractor failures
  - Missing Git/Project context
  - Incomplete metadata
  """

  alias ElixirOntologies.Analyzer.{Parser, Git, Project}
  alias ElixirOntologies.{Config, Graph, Pipeline}
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors

  require Logger

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  defmodule Result do
    @moduledoc """
    Analysis result containing all extracted information and metadata.

    ## Fields

    - `file_path` - Absolute path to the analyzed file
    - `modules` - List of `FileAnalyzer.ModuleAnalysis` structs
    - `graph` - RDF knowledge graph containing all triples
    - `source_file` - Git.SourceFile struct (nil if not in repository)
    - `project` - Project.Project struct (nil if not in Mix project)
    - `metadata` - Map with file statistics and analysis metrics
    """

    @enforce_keys [:file_path, :modules, :graph]
    defstruct [
      :file_path,
      :modules,
      :graph,
      :source_file,
      :project,
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            file_path: String.t(),
            modules: [ElixirOntologies.Analyzer.FileAnalyzer.ModuleAnalysis.t()],
            graph: Graph.t(),
            source_file: Git.SourceFile.t() | nil,
            project: Project.Project.t() | nil,
            metadata: map()
          }
  end

  defmodule ModuleAnalysis do
    @moduledoc """
    Analysis result for a single module within a file.

    Contains all extracted information specific to one module, including
    functions, types, protocols, behaviors, OTP patterns, and Phase 17
    call graph/control flow analysis.

    ## Fields

    - `name` - Module name as atom
    - `module_info` - Result from Module extractor
    - `functions` - List of function extraction results
    - `types` - List of type definition results
    - `specs` - List of function spec results
    - `protocols` - Protocol and implementation results
    - `behaviors` - Behavior definition and implementation results
    - `otp_patterns` - OTP pattern detection results (GenServer, Supervisor, etc.)
    - `attributes` - Module attribute results
    - `macros` - Macro definition and usage results
    - `calls` - List of function call extraction results (Phase 17)
    - `control_flow` - Map of control flow structures (Phase 17)
    - `exceptions` - Map of exception handling structures (Phase 17)
    - `metadata` - Additional analysis metadata
    """

    defstruct [
      :name,
      :module_info,
      functions: [],
      types: [],
      specs: [],
      protocols: %{},
      behaviors: %{},
      otp_patterns: %{},
      attributes: [],
      macros: [],
      calls: [],
      control_flow: %{
        conditionals: [],
        cases: [],
        withs: [],
        receives: [],
        comprehensions: []
      },
      exceptions: %{
        tries: [],
        raises: [],
        throws: [],
        exits: []
      },
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            name: atom(),
            module_info: map() | nil,
            functions: list(),
            types: list(),
            specs: list(),
            protocols: map(),
            behaviors: map(),
            otp_patterns: map(),
            attributes: list(),
            macros: list(),
            calls: list(),
            control_flow: map(),
            exceptions: map(),
            metadata: map()
          }
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Analyzes an Elixir source file and returns a complete analysis result.

  ## Parameters

  - `file_path` - Path to the Elixir source file (relative or absolute)
  - `config` - Configuration options (defaults to `Config.default/0`)

  ## Returns

  - `{:ok, result}` - Successful analysis with Result struct
  - `{:error, reason}` - Analysis failed with error reason

  ## Examples

      # Analyze a file
      {:ok, result} = FileAnalyzer.analyze("lib/my_module.ex")

      # Analyze with custom config
      config = Config.new(include_git_info: true)
      {:ok, result} = FileAnalyzer.analyze("lib/my_module.ex", config)

      # Handle errors
      case FileAnalyzer.analyze("nonexistent.ex") do
        {:ok, result} -> IO.puts("Success!")
        {:error, :file_not_found} -> IO.puts("File does not exist")
      end
  """
  @spec analyze(String.t(), Config.t()) :: {:ok, Result.t()} | {:error, atom() | String.t()}
  def analyze(file_path, config \\ Config.default()) do
    with {:ok, validated_config} <- validate_config(config),
         {:ok, parse_result} <- Parser.parse_file(file_path),
         context <- detect_context(parse_result.path, validated_config),
         modules <- extract_modules(parse_result.ast, context, validated_config),
         graph <- build_graph(modules, context, validated_config) do
      {:ok,
       %Result{
         file_path: parse_result.path,
         modules: modules,
         graph: graph,
         source_file: context.git,
         project: context.project,
         metadata: %{
           file_size: parse_result.file_metadata.size,
           modified_at: parse_result.file_metadata.mtime,
           module_count: length(modules),
           parse_time_ms: 0
         }
       }}
    end
  end

  @doc """
  Analyzes an Elixir source file, raising on error.

  Same as `analyze/2` but raises a runtime error instead of returning
  an error tuple.

  ## Examples

      result = FileAnalyzer.analyze!("lib/my_module.ex")
      # result.modules contains list of analyzed modules
  """
  @spec analyze!(String.t(), Config.t()) :: Result.t()
  def analyze!(file_path, config \\ Config.default()) do
    case analyze(file_path, config) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to analyze file: #{inspect(reason)}"
    end
  end

  @doc """
  Analyzes Elixir source code from a string.

  Useful for testing and dynamic analysis scenarios.

  ## Parameters

  - `source_code` - Elixir source code as a string
  - `config` - Configuration options (defaults to `Config.default/0`)

  ## Returns

  - `{:ok, result}` - Successful analysis with Result struct
  - `{:error, reason}` - Analysis failed with error reason

  ## Examples

      source = \"\"\"
      defmodule MyModule do
        def hello, do: :world
      end
      \"\"\"

      {:ok, result} = FileAnalyzer.analyze_string(source)
  """
  @spec analyze_string(String.t(), Config.t()) ::
          {:ok, Result.t()} | {:error, atom() | String.t()}
  def analyze_string(source_code, config \\ Config.default()) do
    with {:ok, validated_config} <- validate_config(config),
         {:ok, ast} <- Parser.parse(source_code),
         context <- %{git: nil, project: nil},
         modules <- extract_modules(ast, context, validated_config),
         graph <- build_graph(modules, context, validated_config) do
      {:ok,
       %Result{
         file_path: "<string>",
         modules: modules,
         graph: graph,
         source_file: nil,
         project: nil,
         metadata: %{
           file_size: byte_size(source_code),
           module_count: length(modules)
         }
       }}
    end
  end

  @doc """
  Analyzes Elixir source code from a string, raising on error.

  Same as `analyze_string/2` but raises a runtime error instead of returning
  an error tuple.

  ## Examples

      source = "defmodule MyModule do end"
      result = FileAnalyzer.analyze_string!(source)
  """
  @spec analyze_string!(String.t(), Config.t()) :: Result.t()
  def analyze_string!(source_code, config \\ Config.default()) do
    case analyze_string(source_code, config) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to analyze string: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Private - Configuration
  # ===========================================================================

  defp validate_config(%Config{} = config), do: {:ok, config}
  defp validate_config(_), do: {:error, :invalid_config}

  # ===========================================================================
  # Private - Context Detection
  # ===========================================================================

  defp detect_context(file_path, config) do
    git_context =
      if config.include_git_info do
        case Git.source_file(file_path) do
          {:ok, source_file} -> source_file
          {:error, _} -> nil
        end
      else
        nil
      end

    project_context =
      case Project.detect(file_path) do
        {:ok, project} -> project
        {:error, _} -> nil
      end

    %{git: git_context, project: project_context}
  end

  # ===========================================================================
  # Private - Module Extraction
  # ===========================================================================

  defp extract_modules(ast, context, config) do
    ast
    |> find_all_modules()
    |> Enum.map(&extract_module_content(&1, context, config))
  end

  # Find all defmodule nodes in the AST (including nested)
  defp find_all_modules(ast) do
    do_find_modules(ast, [])
  end

  defp do_find_modules({:defmodule, _, [_alias, [do: _body]]} = node, acc) do
    # Found a module, add it and search inside for nested modules
    {:defmodule, _, [_alias, [do: body]]} = node
    nested = do_find_modules(body, [])
    [node | nested] ++ acc
  end

  defp do_find_modules({:__block__, _, expressions}, acc) when is_list(expressions) do
    Enum.flat_map(expressions, &do_find_modules(&1, acc))
  end

  defp do_find_modules(list, acc) when is_list(list) do
    Enum.flat_map(list, &do_find_modules(&1, acc))
  end

  defp do_find_modules(_, acc), do: acc

  # Extract content from a single module
  defp extract_module_content({:defmodule, _, [alias_ast, [do: body]]}, _context, _config) do
    module_name = extract_module_name(alias_ast)
    module_name_list = extract_module_name_list(alias_ast)

    # Run all extractors on the module body
    %ModuleAnalysis{
      name: module_name,
      module_info:
        safe_extract(fn ->
          Extractors.Module.extract({:defmodule, [], [alias_ast, [do: body]]})
        end),
      functions: extract_functions(body, module_name_list),
      types: extract_types(body),
      specs: extract_specs(body),
      protocols: extract_protocols(body),
      behaviors: extract_behaviors(body),
      otp_patterns: extract_otp_patterns(body),
      attributes: extract_attributes(body),
      macros: extract_macros(body),
      # Phase 17: Call graph and control flow
      calls: extract_calls(body),
      control_flow: extract_control_flow(body),
      exceptions: extract_exceptions(body)
    }
  end

  defp extract_module_name({:__aliases__, _, name_parts}) do
    name_parts
    |> Enum.map_join(".", &to_string/1)
    |> String.to_atom()
  end

  defp extract_module_name(atom) when is_atom(atom), do: atom
  defp extract_module_name(_), do: :UnknownModule

  # Extract module name as list of atoms for Function extractor
  defp extract_module_name_list({:__aliases__, _, name_parts}) do
    name_parts
  end

  defp extract_module_name_list(atom) when is_atom(atom), do: [atom]
  defp extract_module_name_list(_), do: [:UnknownModule]

  # ===========================================================================
  # Private - Extractor Composition
  # ===========================================================================

  # Note: Extractors work on individual nodes, not module bodies
  # We walk the AST to find relevant nodes and extract from each

  defp extract_functions(body, module_name_list) do
    body
    |> find_function_nodes()
    |> Enum.map(
      &safe_extract(fn -> Extractors.Function.extract(&1, module: module_name_list) end)
    )
    |> Enum.reject(&is_nil/1)
  end

  defp extract_types(body) do
    body
    |> find_type_nodes()
    |> Enum.map(&safe_extract(fn -> Extractors.TypeDefinition.extract(&1) end))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_specs(body) do
    body
    |> find_spec_nodes()
    |> Enum.map(&safe_extract(fn -> Extractors.FunctionSpec.extract(&1) end))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_protocols(_body) do
    # For now, return empty - full implementation requires checking defprotocol/defimpl
    %{protocol: nil, implementations: []}
  end

  defp extract_behaviors(_body) do
    # For now, return empty - full implementation requires checking @behaviour
    %{definition: nil, implementations: []}
  end

  defp extract_otp_patterns(_body) do
    # For now, return empty - full implementation requires pattern matching
    %{genserver: nil, supervisor: nil, agent: nil, task: nil, ets: nil}
  end

  defp extract_attributes(body) do
    body
    |> find_attribute_nodes()
    |> Enum.map(&safe_extract(fn -> Extractors.Attribute.extract(&1) end))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_macros(_body) do
    # For now, return empty - full implementation requires finding defmacro nodes
    []
  end

  # ===========================================================================
  # Private - Phase 17 Extractors (Call Graph, Control Flow, Exceptions)
  # ===========================================================================

  defp extract_calls(body) do
    # Extract all function calls from the module body
    Extractors.Call.extract_all_calls(body)
  end

  defp extract_control_flow(body) do
    %{
      conditionals: Extractors.Conditional.extract_conditionals(body),
      cases: Extractors.CaseWith.extract_case_expressions(body),
      withs: Extractors.CaseWith.extract_with_expressions(body),
      receives: Extractors.CaseWith.extract_receive_expressions(body),
      comprehensions: Extractors.Comprehension.extract_for_loops(body)
    }
  end

  defp extract_exceptions(body) do
    %{
      tries: Extractors.Exception.extract_try_expressions(body),
      raises: Extractors.Exception.extract_raises(body),
      throws: Extractors.Exception.extract_throws(body),
      exits: Extractors.Exception.extract_exits(body)
    }
  end

  # Find function definition nodes (def, defp, defmacro, defmacrop)
  defp find_function_nodes(body) do
    walk_ast(body, fn
      {type, _, _} = node when type in [:def, :defp, :defmacro, :defmacrop] -> {:collect, node}
      _ -> :continue
    end)
  end

  # Find type definition nodes (@type, @typep, @opaque)
  defp find_type_nodes(body) do
    walk_ast(body, fn
      {:@, _, [{type, _, _}]} = node when type in [:type, :typep, :opaque] -> {:collect, node}
      _ -> :continue
    end)
  end

  # Find spec nodes (@spec, @callback)
  defp find_spec_nodes(body) do
    walk_ast(body, fn
      {:@, _, [{type, _, _}]} = node when type in [:spec, :callback] -> {:collect, node}
      _ -> :continue
    end)
  end

  # Find attribute nodes (@moduledoc, @doc, etc.)
  defp find_attribute_nodes(body) do
    walk_ast(body, fn
      {:@, _, [{attr, _, _}]} = node when is_atom(attr) -> {:collect, node}
      _ -> :continue
    end)
  end

  # Generic AST walker that collects nodes based on a predicate
  defp walk_ast(ast, fun, acc \\ [])

  defp walk_ast({:__block__, _, expressions}, fun, acc) when is_list(expressions) do
    Enum.reduce(expressions, acc, &walk_ast(&1, fun, &2))
  end

  defp walk_ast(node, fun, acc) when is_tuple(node) do
    case fun.(node) do
      {:collect, item} ->
        # Add to collection and continue walking children
        new_acc = [item | acc]

        node
        |> Tuple.to_list()
        |> Enum.reduce(new_acc, &walk_ast(&1, fun, &2))

      :continue ->
        # Just walk children
        node
        |> Tuple.to_list()
        |> Enum.reduce(acc, &walk_ast(&1, fun, &2))

      :skip ->
        acc
    end
  end

  defp walk_ast(list, fun, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk_ast(&1, fun, &2))
  end

  defp walk_ast(_, _fun, acc), do: acc

  # ===========================================================================
  # Private - Safe Extraction
  # ===========================================================================

  # Extract with error handling (returns result or nil)
  defp safe_extract(extractor_fn) do
    case extractor_fn.() do
      {:ok, result} -> result
      {:error, _} -> nil
      result -> result
    end
  rescue
    e ->
      Logger.debug("Extractor failed: #{inspect(e)}")
      nil
  end

  # ===========================================================================
  # Private - Graph Building
  # ===========================================================================

  defp build_graph(modules, context, config) do
    # Build RDF graph using the Pipeline integration
    # Use relative_path from Git.SourceFile if available
    file_path =
      case context.git do
        %{relative_path: path} -> path
        _ -> nil
      end

    builder_context =
      Context.new(
        base_iri: config.base_iri,
        file_path: file_path,
        config: %{
          include_source_text: config.include_source_text,
          include_git_info: config.include_git_info
        }
      )

    Pipeline.build_graph_for_modules(modules, builder_context)
  end
end
