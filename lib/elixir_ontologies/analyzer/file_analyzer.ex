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

      # Analyze caller-supplied project source with stable expression identities
      expression_config = Config.new(include_expressions: true)

      {:ok, result} =
        FileAnalyzer.analyze_string(source, expression_config,
          file_path: "lib/my_module.ex",
          source_kind: :project,
          expression_identity_base: "example/my-project/abc123/lib/my_module.ex"
        )

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

  - `file_path` - Analyzed filesystem path, or the repository-relative path supplied to
    contextual string analysis
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
  - `include_expressions` - Whether trusted project source may emit full expression RDF

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

  Contextual `analyze_string/3` is stricter: it validates the caller-supplied source
  context, builds sequentially, enforces expression bounds, and returns no partial
  in-memory graph when any of those stages fails. The caller remains responsible for
  deriving source classification and identity material from trustworthy inventory or
  provenance; this module validates their shape, not their truth.
  """

  alias ElixirOntologies.Analyzer.{Parser, Git, Project}
  alias ElixirOntologies.{Config, Graph, Pipeline}
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors

  require Logger

  @source_context_keys [:file_path, :source_kind, :expression_identity_base]
  @max_expression_resources 100_000
  @max_expression_triples 500_000
  @max_expression_depth 100
  @max_identity_base_bytes 2_048

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  defmodule Result do
    @moduledoc """
    Analysis result containing all extracted information and metadata.

    ## Fields

    - `file_path` - Analyzed filesystem path, or the validated repository-relative
      path supplied to contextual string analysis
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
    - `structs` - Struct definition results
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
      structs: [],
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
            structs: list(),
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
  - `config` - Configuration options (uses default configuration if not provided)

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
  @spec analyze(String.t(), Config.t()) ::
          {:ok, Result.t()} | {:error, atom() | String.t() | {:file_error, atom()}}
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
  - `config` - Configuration options (uses default configuration if not provided)

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
  Analyzes source text with explicit caller-supplied source context.

  `:file_path` and `:source_kind` are required. The path must be a normalized,
  repository-relative POSIX path no longer than 1,024 bytes: absolute paths, empty
  components, `.` or `..` components, backslashes, and NUL bytes are rejected.
  `:source_kind` must be `:project` or `:dependency`.

  `:expression_identity_base` is required when `config.include_expressions` is true
  for project source. It is otherwise optional, and must be a non-empty, NUL-free
  string no longer than 2,048 bytes when supplied. It is caller-defined stable
  identity material, conventionally repository identity + revision + relative path.
  It is SHA-256 scoped internally: identical source and identity material produce
  stable expression IRIs, while changing the material selects a disjoint expression
  namespace. It is not a displayed IRI and must not contain secrets.

  Full expressions require both `include_expressions: true` and
  `source_kind: :project`. Dependencies and the legacy `analyze_string/1` and `/2`
  entry points stay lightweight even when expression extraction is configured.

  The caller is responsible for deriving `source_kind` and identity material from
  trustworthy inventory or provenance. Validation checks shape, not truth, and this
  function performs no filesystem I/O.

  Contextual analysis succeeds only after parsing, strict sequential graph
  construction, and expression-limit validation complete. It returns no partial
  graph on failure. Stable validation errors include `:invalid_config`,
  `:invalid_source_context`, `:invalid_source_file_path`, `:invalid_source_kind`,
  and `:invalid_expression_identity_base`. Full expression analysis is bounded to
  100,000 AST/expression resources, depth 100, and 500,000 triples. Builder failures
  are wrapped in `{:expression_analysis_failed, reason}`.

  The result metadata records `:source_kind` and `:expression_complete`; its
  `file_path` is the validated repository-relative path.

  ## Example

      config = Config.new(include_expressions: true)

      FileAnalyzer.analyze_string(source, config,
        file_path: "lib/my_module.ex",
        source_kind: :project,
        expression_identity_base: "example/my-project/abc123/lib/my_module.ex"
      )
  """
  @spec analyze_string(String.t(), Config.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def analyze_string(source_code, config, source_context) when is_list(source_context) do
    with {:ok, validated_config} <- validate_config(config),
         {:ok, normalized_context} <- validate_source_context(source_context, validated_config),
         {:ok, ast} <- Parser.parse(source_code),
         :ok <- validate_expression_ast(ast, validated_config, normalized_context),
         modules <- extract_modules(ast, normalized_context, validated_config),
         {:ok, graph} <- build_graph_result(modules, normalized_context, validated_config),
         :ok <- validate_expression_graph(graph, validated_config, normalized_context) do
      {:ok,
       %Result{
         file_path: normalized_context.file_path,
         modules: modules,
         graph: graph,
         source_file: nil,
         project: nil,
         metadata: %{
           file_size: byte_size(source_code),
           module_count: length(modules),
           source_kind: normalized_context.source_kind,
           expression_complete: expression_mode?(validated_config, normalized_context)
         }
       }}
    end
  rescue
    error -> {:error, {:expression_analysis_failed, exception_reason(error)}}
  catch
    kind, reason -> {:error, {:expression_analysis_failed, {kind, reason}}}
  end

  def analyze_string(_source_code, _config, _source_context),
    do: {:error, :invalid_source_context}

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

  @doc """
  Bang variant of `analyze_string/3`.

  It accepts the same caller-supplied context and raises for every validation,
  parsing, build, or expression-limit error instead of returning an error tuple.
  """
  @spec analyze_string!(String.t(), Config.t(), keyword()) :: Result.t()
  def analyze_string!(source_code, config, source_context) do
    case analyze_string(source_code, config, source_context) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to analyze string: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Private - Configuration
  # ===========================================================================

  defp validate_config(%Config{} = config), do: {:ok, config}
  defp validate_config(_), do: {:error, :invalid_config}

  defp validate_source_context(source_context, config) do
    with true <- Keyword.keyword?(source_context),
         keys = Keyword.keys(source_context),
         true <- length(keys) == MapSet.size(MapSet.new(keys)),
         true <- Enum.all?(keys, &(&1 in @source_context_keys)),
         {:ok, file_path} <- validate_source_path(Keyword.get(source_context, :file_path)),
         {:ok, source_kind} <- validate_source_kind(Keyword.get(source_context, :source_kind)),
         {:ok, identity_base} <-
           validate_identity_base(
             Keyword.get(source_context, :expression_identity_base),
             config,
             source_kind
           ) do
      {:ok,
       %{
         git: nil,
         project: nil,
         file_path: file_path,
         source_kind: source_kind,
         expression_scope: expression_scope(identity_base)
       }}
    else
      false -> {:error, :invalid_source_context}
      {:error, _reason} = error -> error
    end
  end

  defp validate_source_path(file_path) when is_binary(file_path) do
    components = String.split(file_path, "/", trim: false)

    if file_path != "" and byte_size(file_path) <= 1_024 and
         not String.starts_with?(file_path, "/") and
         not String.contains?(file_path, ["\\", <<0>>]) and
         Enum.all?(components, &(&1 not in ["", ".", ".."])) do
      {:ok, Enum.join(components, "/")}
    else
      {:error, :invalid_source_file_path}
    end
  end

  defp validate_source_path(_file_path), do: {:error, :invalid_source_file_path}

  defp validate_source_kind(source_kind) when source_kind in [:project, :dependency],
    do: {:ok, source_kind}

  defp validate_source_kind(_source_kind), do: {:error, :invalid_source_kind}

  defp validate_identity_base(identity_base, config, :project)
       when config.include_expressions do
    validate_present_identity_base(identity_base)
  end

  defp validate_identity_base(nil, _config, _source_kind), do: {:ok, nil}

  defp validate_identity_base(identity_base, _config, _source_kind),
    do: validate_present_identity_base(identity_base)

  defp validate_present_identity_base(identity_base)
       when is_binary(identity_base) and byte_size(identity_base) > 0 and
              byte_size(identity_base) <= @max_identity_base_bytes do
    if String.contains?(identity_base, <<0>>),
      do: {:error, :invalid_expression_identity_base},
      else: {:ok, identity_base}
  end

  defp validate_present_identity_base(_identity_base),
    do: {:error, :invalid_expression_identity_base}

  defp expression_scope(nil), do: nil

  defp expression_scope(identity_base) do
    :crypto.hash(:sha256, identity_base)
    |> Base.url_encode64(padding: false)
  end

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

    relative_path =
      case git_context do
        %{relative_path: path} when is_binary(path) -> path
        _other -> file_path
      end

    %{
      git: git_context,
      project: project_context,
      file_path: relative_path,
      source_kind: if(Config.project_file?(relative_path), do: :project, else: :dependency),
      expression_scope: expression_scope(relative_path)
    }
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
  defp extract_module_content({:defmodule, _, [alias_ast, [do: body]]}, context, config) do
    module_name = extract_module_name(alias_ast)
    module_name_list = extract_module_name_list(alias_ast)

    # Run all extractors on the module body
    %ModuleAnalysis{
      name: module_name,
      module_info:
        safe_extract(fn ->
          Extractors.Module.extract({:defmodule, [], [alias_ast, [do: body]]})
        end),
      functions: extract_functions(body, module_name_list, context, config),
      types: extract_types(body),
      specs: extract_specs(body),
      protocols: extract_protocols(body),
      behaviors: extract_behaviors(body),
      structs: extract_structs(body),
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

  defp extract_functions(body, module_name_list, context, config) do
    functions =
      body
      |> find_function_nodes()
      |> Enum.map(
        &safe_extract(fn -> Extractors.Function.extract(&1, module: module_name_list) end)
      )
      |> Enum.reject(&is_nil/1)

    if expression_mode?(config, context), do: merge_function_clauses(functions), else: functions
  end

  defp merge_function_clauses(functions) do
    functions
    |> Enum.reduce({[], %{}}, fn function, {order, grouped} ->
      key = {function.name, function.arity, function.visibility, function.type}

      case Map.fetch(grouped, key) do
        :error ->
          {[key | order], Map.put(grouped, key, function)}

        {:ok, existing} ->
          merged = %{existing | clauses: existing.clauses ++ function.clauses}
          {order, Map.put(grouped, key, merged)}
      end
    end)
    |> then(fn {order, grouped} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn key ->
        function = Map.fetch!(grouped, key)

        clauses =
          function.clauses
          |> Enum.with_index(1)
          |> Enum.map(fn {clause, index} -> %{clause | order: index} end)

        %{function | clauses: clauses}
      end)
    end)
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

  defp extract_protocols(body) do
    protocol =
      body
      |> find_protocol_nodes()
      |> List.first()
      |> case do
        nil ->
          nil

        protocol_node ->
          safe_extract(fn -> Extractors.Protocol.extract(protocol_node) end)
      end

    implementations =
      body
      |> find_protocol_implementation_nodes()
      |> Enum.map(
        &safe_extract(fn ->
          Extractors.Protocol.extract_implementation(&1)
        end)
      )
      |> Enum.reject(&is_nil/1)

    %{protocol: protocol, implementations: implementations}
  end

  defp extract_behaviors(body) do
    definition =
      if Extractors.Behaviour.defines_behaviour?(body) do
        safe_extract(fn -> {:ok, Extractors.Behaviour.extract_from_body(body)} end)
      else
        nil
      end

    implementations =
      case safe_extract(fn -> {:ok, Extractors.Behaviour.extract_implementations(body)} end) do
        %{behaviours: behaviours, overridables: overridables} = implementation
        when behaviours != [] or overridables != [] ->
          [implementation]

        _ ->
          []
      end

    %{definition: definition, implementations: implementations}
  end

  defp extract_structs(body) do
    case safe_extract(fn -> Extractors.Struct.extract_from_body(body) end) do
      nil -> []
      struct -> [struct]
    end
  end

  defp extract_otp_patterns(body) do
    ets_patterns =
      safe_extract(fn -> {:ok, Extractors.OTP.ETS.extract_all(body)} end) || []

    %{
      genserver: safe_extract(fn -> Extractors.OTP.GenServer.extract(body) end),
      supervisor: safe_extract(fn -> Extractors.OTP.Supervisor.extract(body) end),
      agent: safe_extract(fn -> Extractors.OTP.Agent.extract(body) end),
      task: safe_extract(fn -> Extractors.OTP.Task.extract(body) end),
      ets: if(ets_patterns == [], do: nil, else: ets_patterns)
    }
  end

  defp extract_attributes(body) do
    body
    |> find_attribute_nodes()
    |> Enum.map(&safe_extract(fn -> Extractors.Attribute.extract(&1) end))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_macros(body) do
    safe_extract(fn -> {:ok, Extractors.Macro.extract_all(body)} end) || []
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

  # Find protocol definition nodes (defprotocol)
  defp find_protocol_nodes(body) do
    walk_ast(body, fn
      {:defprotocol, _, _} = node -> {:collect, node}
      _ -> :continue
    end)
  end

  # Find protocol implementation nodes (defimpl)
  defp find_protocol_implementation_nodes(body) do
    walk_ast(body, fn
      {:defimpl, _, _} = node -> {:collect, node}
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
    file_path = Map.get(context, :file_path)

    builder_context =
      Context.new(
        base_iri: config.base_iri,
        file_path: file_path,
        source_kind: Map.get(context, :source_kind, :auto),
        expression_scope: Map.get(context, :expression_scope),
        config: %{
          include_source_text: config.include_source_text,
          include_git_info: config.include_git_info,
          include_expressions: config.include_expressions
        }
      )

    Pipeline.build_graph_for_modules(modules, builder_context)
  end

  defp build_graph_result(modules, context, config) do
    builder_context =
      Context.new(
        base_iri: config.base_iri,
        file_path: context.file_path,
        source_kind: context.source_kind,
        expression_scope: context.expression_scope,
        config: %{
          include_source_text: config.include_source_text,
          include_git_info: config.include_git_info,
          include_expressions: config.include_expressions
        }
      )

    case Pipeline.build_graph_for_modules_result(modules, builder_context, parallel: false) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, {:expression_analysis_failed, reason}}
    end
  end

  defp validate_expression_ast(ast, config, context) do
    if expression_mode?(config, context) do
      {resource_count, depth} = ast_stats(ast)

      cond do
        resource_count > @max_expression_resources ->
          {:error,
           {:expression_resource_limit_exceeded,
            %{limit: @max_expression_resources, observed: resource_count}}}

        depth > @max_expression_depth ->
          {:error,
           {:expression_depth_limit_exceeded, %{limit: @max_expression_depth, observed: depth}}}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp validate_expression_graph(graph, config, context) do
    if expression_mode?(config, context) do
      triple_count = Graph.statement_count(graph)

      expression_resource_count =
        graph
        |> Graph.subjects()
        |> Enum.count(
          &String.contains?(to_string(&1), "expr/source/#{context.expression_scope}/")
        )

      cond do
        triple_count > @max_expression_triples ->
          {:error,
           {:expression_triple_limit_exceeded,
            %{limit: @max_expression_triples, observed: triple_count}}}

        expression_resource_count > @max_expression_resources ->
          {:error,
           {:expression_resource_limit_exceeded,
            %{limit: @max_expression_resources, observed: expression_resource_count}}}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp expression_mode?(config, %{source_kind: :project}), do: config.include_expressions
  defp expression_mode?(_config, _context), do: false

  defp ast_stats(ast), do: ast_stats(ast, 1)

  defp ast_stats(tuple, depth) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce({1, depth}, fn child, {count, max_depth} ->
      {child_count, child_depth} = ast_stats(child, depth + 1)
      {count + child_count, max(max_depth, child_depth)}
    end)
  end

  defp ast_stats(list, depth) when is_list(list) do
    Enum.reduce(list, {1, depth}, fn child, {count, max_depth} ->
      {child_count, child_depth} = ast_stats(child, depth + 1)
      {count + child_count, max(max_depth, child_depth)}
    end)
  end

  defp ast_stats(_scalar, depth), do: {1, depth}

  defp exception_reason(error),
    do: {error.__struct__, Exception.message(error)}
end
