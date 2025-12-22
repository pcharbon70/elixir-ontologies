defmodule ElixirOntologies.Builders.Orchestrator do
  @moduledoc """
  Orchestrates RDF triple generation from Elixir code analysis results.

  This module coordinates all individual builders (Module, Function, Clause,
  Protocol, Behaviour, Struct, Type System, GenServer, Supervisor, Agent, Task)
  to generate complete RDF graphs from Elixir code analysis.

  ## Parallel Execution

  The orchestrator leverages parallel execution for independent builders since
  code analysis is a read-only operation. Builders are executed in phases:

  1. **Phase 1**: Module builder (single, establishes module IRI)
  2. **Phase 2**: All module-level builders in parallel (Functions, Protocols,
     Behaviours, Structs, Types, OTP patterns)
  3. **Phase 3**: Clause builders in parallel (depends on function IRIs)
  4. **Aggregation**: All triples combined into single RDF.Graph

  ## Usage

      alias ElixirOntologies.Builders.{Orchestrator, Context}

      # Analysis result from extractors
      analysis = %{
        module: module_extraction_result,
        functions: [function1, function2],
        protocols: [],
        behaviours: [],
        structs: [struct_result],
        types: [type1, type2],
        genservers: [genserver_result],
        supervisors: [],
        agents: [],
        tasks: []
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

  ## Options

  - `:parallel` - Enable/disable parallel execution (default: `true`)
  - `:timeout` - Timeout for parallel tasks in ms (default: `5000`)
  - `:include` - List of builder atoms to include (default: all)
  - `:exclude` - List of builder atoms to exclude (default: `[]`)

  ## Examples

      iex> alias ElixirOntologies.Builders.{Orchestrator, Context}
      iex> alias ElixirOntologies.Extractors.Module
      iex> module_info = %Module{
      ...>   type: :module,
      ...>   name: [:TestModule],
      ...>   docstring: nil,
      ...>   aliases: [],
      ...>   imports: [],
      ...>   requires: [],
      ...>   uses: [],
      ...>   functions: [],
      ...>   macros: [],
      ...>   types: [],
      ...>   location: nil,
      ...>   metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
      ...> }
      iex> analysis = %{module: module_info, functions: []}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {:ok, graph} = Orchestrator.build_module_graph(analysis, context)
      iex> RDF.Graph.statement_count(graph) > 0
      true
  """

  alias ElixirOntologies.Builders.{
    Context,
    ModuleBuilder,
    FunctionBuilder,
    ProtocolBuilder,
    BehaviourBuilder,
    StructBuilder,
    TypeSystemBuilder,
    CallGraphBuilder,
    ControlFlowBuilder,
    ExceptionBuilder
  }

  alias ElixirOntologies.Builders.OTP.{
    GenServerBuilder,
    SupervisorBuilder,
    AgentBuilder,
    TaskBuilder
  }

  @default_timeout 5_000
  @default_parallel true

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds a complete RDF graph from module analysis results.

  Coordinates all builders to generate triples and aggregates them into
  a single RDF.Graph. Uses parallel execution by default for optimal performance.

  ## Parameters

  - `analysis` - Map with extraction results (module, functions, etc.)
  - `context` - Builder context with base IRI and configuration

  ## Returns

  - `{:ok, graph}` - Success with the generated RDF graph
  - `{:error, reason}` - Failure with error reason

  ## Examples

      iex> alias ElixirOntologies.Builders.{Orchestrator, Context}
      iex> alias ElixirOntologies.Extractors.Module
      iex> module_info = %Module{
      ...>   type: :module,
      ...>   name: [:TestModule],
      ...>   docstring: nil,
      ...>   aliases: [],
      ...>   imports: [],
      ...>   requires: [],
      ...>   uses: [],
      ...>   functions: [],
      ...>   macros: [],
      ...>   types: [],
      ...>   location: nil,
      ...>   metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
      ...> }
      iex> analysis = %{module: module_info}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {:ok, _graph} = Orchestrator.build_module_graph(analysis, context)
  """
  @spec build_module_graph(map(), Context.t()) :: {:ok, RDF.Graph.t()} | {:error, term()}
  def build_module_graph(analysis, context) do
    build_module_graph(analysis, context, [])
  end

  @doc """
  Builds a complete RDF graph from module analysis results with options.

  See `build_module_graph/2` for details.

  ## Options

  - `:parallel` - Enable/disable parallel execution (default: `true`)
  - `:timeout` - Timeout for parallel tasks in ms (default: `5000`)
  - `:include` - List of builder atoms to include (default: all)
  - `:exclude` - List of builder atoms to exclude (default: `[]`)
  """
  @spec build_module_graph(map(), Context.t(), keyword()) ::
          {:ok, RDF.Graph.t()} | {:error, term()}
  def build_module_graph(analysis, context, opts) do
    parallel = Keyword.get(opts, :parallel, @default_parallel)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    include = Keyword.get(opts, :include, nil)
    exclude = Keyword.get(opts, :exclude, [])

    with {:ok, module_info} <- get_module_info(analysis),
         {module_iri, module_triples} <- ModuleBuilder.build(module_info, context) do
      # Build all other components (phase 2 runs in parallel)
      # Note: Phase 3 (clauses) is handled internally by FunctionBuilder
      all_triples =
        module_triples ++
          build_phase_2(analysis, module_iri, context, parallel, timeout, include, exclude)

      # Create graph from all triples
      graph =
        all_triples
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.reduce(RDF.Graph.new(), fn triple, graph ->
          RDF.Graph.add(graph, triple)
        end)

      {:ok, graph}
    end
  end

  # ===========================================================================
  # Phase 2: Module-Level Builders (parallel)
  # ===========================================================================

  defp build_phase_2(analysis, module_iri, context, parallel, timeout, include, exclude) do
    builders = [
      {:functions, &build_functions/3},
      {:protocols, &build_protocols/3},
      {:behaviours, &build_behaviours/3},
      {:structs, &build_structs/3},
      {:types, &build_types/3},
      {:genservers, &build_genservers/3},
      {:supervisors, &build_supervisors/3},
      {:agents, &build_agents/3},
      {:tasks, &build_tasks/3},
      # Phase 17: Call Graph and Control Flow
      {:calls, &build_calls/3},
      {:control_flow, &build_control_flow/3},
      {:exceptions, &build_exceptions/3}
    ]

    # Filter builders based on include/exclude
    builders = filter_builders(builders, include, exclude)

    if parallel do
      build_parallel(builders, analysis, module_iri, context, timeout)
    else
      build_sequential(builders, analysis, module_iri, context)
    end
  end

  # Note: Phase 3 (clause building) is handled internally by FunctionBuilder
  # Each function's clauses are built when the function is built

  # ===========================================================================
  # Individual Builder Functions
  # ===========================================================================

  defp build_functions(analysis, _module_iri, context) do
    functions = Map.get(analysis, :functions, [])

    Enum.flat_map(functions, fn function_info ->
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)
      # Add containment triple linking function to module
      triples
    end)
  end

  defp build_protocols(analysis, _module_iri, context) do
    protocols = Map.get(analysis, :protocols, [])

    Enum.flat_map(protocols, fn protocol_info ->
      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)
      triples
    end)
  end

  defp build_behaviours(analysis, module_iri, context) do
    behaviours = Map.get(analysis, :behaviours, [])

    Enum.flat_map(behaviours, fn behaviour_info ->
      {_behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)
      triples
    end)
  end

  defp build_structs(analysis, module_iri, context) do
    structs = Map.get(analysis, :structs, [])

    Enum.flat_map(structs, fn struct_info ->
      {_struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)
      triples
    end)
  end

  defp build_types(analysis, module_iri, context) do
    types = Map.get(analysis, :types, [])

    Enum.flat_map(types, fn type_info ->
      {_type_iri, triples} = TypeSystemBuilder.build_type_definition(type_info, module_iri, context)
      triples
    end)
  end

  defp build_genservers(analysis, module_iri, context) do
    genservers = Map.get(analysis, :genservers, [])

    Enum.flat_map(genservers, fn genserver_info ->
      {_genserver_iri, triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)
      triples
    end)
  end

  defp build_supervisors(analysis, module_iri, context) do
    supervisors = Map.get(analysis, :supervisors, [])

    Enum.flat_map(supervisors, fn supervisor_info ->
      {_supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
      triples
    end)
  end

  defp build_agents(analysis, module_iri, context) do
    agents = Map.get(analysis, :agents, [])

    Enum.flat_map(agents, fn agent_info ->
      {_agent_iri, triples} = AgentBuilder.build_agent(agent_info, module_iri, context)
      triples
    end)
  end

  defp build_tasks(analysis, module_iri, context) do
    tasks = Map.get(analysis, :tasks, [])

    Enum.flat_map(tasks, fn task_info ->
      {_task_iri, triples} = TaskBuilder.build_task(task_info, module_iri, context)
      triples
    end)
  end

  # ===========================================================================
  # Phase 17 Builders: Call Graph, Control Flow, Exceptions
  # ===========================================================================

  defp build_calls(analysis, module_iri, context) do
    calls = Map.get(analysis, :calls, [])
    containing_function = derive_containing_function(module_iri)

    calls
    |> Enum.with_index()
    |> Enum.flat_map(fn {call, index} ->
      {_call_iri, triples} =
        CallGraphBuilder.build(call, context,
          caller_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_control_flow(analysis, module_iri, context) do
    control_flow = Map.get(analysis, :control_flow, %{})
    containing_function = derive_containing_function(module_iri)

    conditionals = build_conditionals(control_flow, containing_function, context)
    cases = build_cases(control_flow, containing_function, context)
    withs = build_withs(control_flow, containing_function, context)
    # Note: receives and comprehensions are extracted but not yet built to RDF
    # (ControlFlowBuilder doesn't have build_receive or build_comprehension)

    conditionals ++ cases ++ withs
  end

  defp build_conditionals(control_flow, containing_function, context) do
    control_flow
    |> Map.get(:conditionals, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {conditional, index} ->
      {_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_cases(control_flow, containing_function, context) do
    control_flow
    |> Map.get(:cases, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {case_expr, index} ->
      {_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_withs(control_flow, containing_function, context) do
    control_flow
    |> Map.get(:withs, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {with_expr, index} ->
      {_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_exceptions(analysis, module_iri, context) do
    exceptions = Map.get(analysis, :exceptions, %{})
    containing_function = derive_containing_function(module_iri)

    tries = build_tries(exceptions, containing_function, context)
    raises = build_raises(exceptions, containing_function, context)
    throws = build_throws(exceptions, containing_function, context)
    # Note: exits are extracted but build_exit/3 not yet available
    # (will be added when review-improvements branch is merged)

    tries ++ raises ++ throws
  end

  defp build_tries(exceptions, containing_function, context) do
    exceptions
    |> Map.get(:tries, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {try_expr, index} ->
      {_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_raises(exceptions, containing_function, context) do
    exceptions
    |> Map.get(:raises, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {raise_expr, index} ->
      {_iri, triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  defp build_throws(exceptions, containing_function, context) do
    exceptions
    |> Map.get(:throws, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {throw_expr, index} ->
      {_iri, triples} =
        ExceptionBuilder.build_throw(throw_expr, context,
          containing_function: containing_function,
          index: index
        )

      triples
    end)
  end

  # Note: build_exits/3 will be added when ExceptionBuilder.build_exit/3 is available

  # Derive containing function identifier from module IRI for Phase 17 builders
  defp derive_containing_function(module_iri) do
    # Extract module name from IRI and format as function fragment
    # Module IRI is like: https://example.org/code#MyApp.Users
    # We want: MyApp.Users/module/0 (indicating module-level expressions)
    module_iri
    |> to_string()
    |> String.split("#")
    |> List.last()
    |> Kernel.<>("/module/0")
  end

  # ===========================================================================
  # Parallel Execution Helpers
  # ===========================================================================

  defp build_parallel(builders, analysis, module_iri, context, timeout) do
    builders
    |> Task.async_stream(
      fn {_key, builder_fn} ->
        builder_fn.(analysis, module_iri, context)
      end,
      timeout: timeout,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, triples} -> triples
      {:exit, _reason} -> []
    end)
  end

  defp build_sequential(builders, analysis, module_iri, context) do
    Enum.flat_map(builders, fn {_key, builder_fn} ->
      builder_fn.(analysis, module_iri, context)
    end)
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp get_module_info(%{module: module_info}) when not is_nil(module_info) do
    {:ok, module_info}
  end

  defp get_module_info(_) do
    {:error, :missing_module_info}
  end

  defp filter_builders(builders, nil, exclude) do
    Enum.reject(builders, fn {key, _fn} -> key in exclude end)
  end

  defp filter_builders(builders, include, exclude) do
    builders
    |> Enum.filter(fn {key, _fn} -> key in include end)
    |> Enum.reject(fn {key, _fn} -> key in exclude end)
  end

end
