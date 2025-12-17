defmodule ElixirOntologies.Builders.OrchestratorTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.Orchestrator

  alias ElixirOntologies.Builders.{Orchestrator, Context}
  alias ElixirOntologies.Extractors.Module, as: ModuleExtractor
  alias ElixirOntologies.Extractors.Function, as: FunctionExtractor
  alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
  alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
  alias ElixirOntologies.Extractors.Struct, as: StructExtractor

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_minimal_module(opts \\ []) do
    %ModuleExtractor{
      type: Keyword.get(opts, :type, :module),
      name: Keyword.get(opts, :name, [:TestModule]),
      docstring: Keyword.get(opts, :docstring, nil),
      aliases: [],
      imports: [],
      requires: [],
      uses: [],
      functions: [],
      macros: [],
      types: [],
      location: nil,
      metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
    }
  end

  defp build_minimal_function(opts \\ []) do
    %FunctionExtractor{
      type: Keyword.get(opts, :type, :function),
      name: Keyword.get(opts, :name, :test_function),
      arity: Keyword.get(opts, :arity, 0),
      min_arity: Keyword.get(opts, :arity, 0),
      visibility: Keyword.get(opts, :visibility, :public),
      docstring: nil,
      location: nil,
      metadata: %{module: [:TestModule]}
    }
  end

  defp build_minimal_genserver(opts \\ []) do
    %GenServerExtractor{
      detection_method: Keyword.get(opts, :detection_method, :use),
      use_options: Keyword.get(opts, :use_options, []),
      location: nil,
      metadata: %{}
    }
  end

  defp build_minimal_supervisor(opts \\ []) do
    %SupervisorExtractor{
      supervisor_type: Keyword.get(opts, :supervisor_type, :supervisor),
      detection_method: Keyword.get(opts, :detection_method, :use),
      location: nil,
      metadata: %{}
    }
  end

  defp build_minimal_agent(opts \\ []) do
    %AgentExtractor{
      detection_method: Keyword.get(opts, :detection_method, :use),
      use_options: Keyword.get(opts, :use_options, []),
      function_calls: [],
      location: nil,
      metadata: %{}
    }
  end

  defp build_minimal_task(opts \\ []) do
    %TaskExtractor{
      type: Keyword.get(opts, :type, :task),
      detection_method: Keyword.get(opts, :detection_method, :function_call),
      function_calls: [],
      location: nil,
      metadata: %{}
    }
  end

  defp build_minimal_struct(opts \\ []) do
    %StructExtractor{
      fields: Keyword.get(opts, :fields, []),
      enforce_keys: [],
      derives: [],
      location: nil,
      metadata: %{}
    }
  end

  # ===========================================================================
  # Basic Building Tests
  # ===========================================================================

  describe "build_module_graph/2 - basic building" do
    test "builds graph for minimal module" do
      module_info = build_minimal_module()
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 0
    end

    test "returns error when module info is missing" do
      analysis = %{}
      context = build_test_context()

      result = Orchestrator.build_module_graph(analysis, context)

      assert result == {:error, :missing_module_info}
    end

    test "returns error when module info is nil" do
      analysis = %{module: nil}
      context = build_test_context()

      result = Orchestrator.build_module_graph(analysis, context)

      assert result == {:error, :missing_module_info}
    end

    test "builds graph with module type triple" do
      module_info = build_minimal_module(name: [:MyApp, :Users])
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      module_iri = RDF.iri("https://example.org/code#MyApp.Users")
      type_triples = RDF.Graph.get(graph, module_iri, RDF.type())

      assert type_triples != nil
    end
  end

  # ===========================================================================
  # Parallel Execution Tests
  # ===========================================================================

  describe "build_module_graph/3 - parallel execution" do
    test "builds graph with parallel: true" do
      module_info = build_minimal_module()
      function_info = build_minimal_function()
      analysis = %{module: module_info, functions: [function_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context, parallel: true)

      assert RDF.Graph.statement_count(graph) > 0
    end

    test "builds graph with parallel: false" do
      module_info = build_minimal_module()
      function_info = build_minimal_function()
      analysis = %{module: module_info, functions: [function_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context, parallel: false)

      assert RDF.Graph.statement_count(graph) > 0
    end

    test "parallel and sequential produce same result" do
      module_info = build_minimal_module()
      function_info = build_minimal_function()
      analysis = %{module: module_info, functions: [function_info]}
      context = build_test_context()

      {:ok, graph_parallel} = Orchestrator.build_module_graph(analysis, context, parallel: true)
      {:ok, graph_sequential} = Orchestrator.build_module_graph(analysis, context, parallel: false)

      assert RDF.Graph.statement_count(graph_parallel) == RDF.Graph.statement_count(graph_sequential)
    end

    test "respects timeout option" do
      module_info = build_minimal_module()
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, _graph} = Orchestrator.build_module_graph(analysis, context, timeout: 10_000)
    end
  end

  # ===========================================================================
  # Include/Exclude Options Tests
  # ===========================================================================

  describe "build_module_graph/3 - include/exclude options" do
    test "builds only included builders" do
      module_info = build_minimal_module()
      function_info = build_minimal_function()
      analysis = %{module: module_info, functions: [function_info]}
      context = build_test_context()

      {:ok, graph_all} = Orchestrator.build_module_graph(analysis, context)
      {:ok, graph_only_funcs} = Orchestrator.build_module_graph(analysis, context, include: [:functions])

      # Both should have module triples, but only_funcs should have fewer total
      assert RDF.Graph.statement_count(graph_all) >= RDF.Graph.statement_count(graph_only_funcs)
    end

    test "excludes specified builders" do
      module_info = build_minimal_module()
      function_info = build_minimal_function()
      analysis = %{module: module_info, functions: [function_info]}
      context = build_test_context()

      {:ok, graph_all} = Orchestrator.build_module_graph(analysis, context)
      {:ok, graph_no_funcs} = Orchestrator.build_module_graph(analysis, context, exclude: [:functions])

      # graph_no_funcs should have fewer triples (no function triples)
      assert RDF.Graph.statement_count(graph_all) >= RDF.Graph.statement_count(graph_no_funcs)
    end
  end

  # ===========================================================================
  # OTP Pattern Tests
  # ===========================================================================

  describe "build_module_graph/2 - OTP patterns" do
    test "builds graph with GenServer" do
      module_info = build_minimal_module()
      genserver_info = build_minimal_genserver()
      analysis = %{module: module_info, genservers: [genserver_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 1
    end

    test "builds graph with Supervisor" do
      module_info = build_minimal_module()
      supervisor_info = build_minimal_supervisor()
      analysis = %{module: module_info, supervisors: [supervisor_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 1
    end

    test "builds graph with Agent" do
      module_info = build_minimal_module()
      agent_info = build_minimal_agent()
      analysis = %{module: module_info, agents: [agent_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 1
    end

    test "builds graph with Task" do
      module_info = build_minimal_module()
      task_info = build_minimal_task()
      analysis = %{module: module_info, tasks: [task_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 1
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "build_module_graph/2 - structs" do
    test "builds graph with struct" do
      module_info = build_minimal_module()
      struct_info = build_minimal_struct()
      analysis = %{module: module_info, structs: [struct_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 1
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "builds complete graph with module and functions" do
      module_info = build_minimal_module(name: [:MyApp])
      function1 = build_minimal_function(name: :foo, arity: 0)
      function2 = build_minimal_function(name: :bar, arity: 1)
      analysis = %{module: module_info, functions: [function1, function2]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      # Should have module triples + function triples
      assert RDF.Graph.statement_count(graph) > 3
    end

    test "builds graph with multiple OTP patterns" do
      module_info = build_minimal_module()
      genserver_info = build_minimal_genserver()
      agent_info = build_minimal_agent()
      analysis = %{module: module_info, genservers: [genserver_info], agents: [agent_info]}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      # Should have module + genserver + agent triples
      assert RDF.Graph.statement_count(graph) > 3
    end

    test "handles empty optional fields gracefully" do
      module_info = build_minimal_module()
      analysis = %{
        module: module_info,
        functions: [],
        protocols: [],
        behaviours: [],
        structs: [],
        types: [],
        genservers: [],
        supervisors: [],
        agents: [],
        tasks: []
      }
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      # Should still have module triples
      assert RDF.Graph.statement_count(graph) > 0
    end

    test "handles missing optional fields gracefully" do
      module_info = build_minimal_module()
      # Only module, nothing else
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      assert RDF.Graph.statement_count(graph) > 0
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles nested module names" do
      module_info = build_minimal_module(name: [:MyApp, :Services, :UserManager])
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      module_iri = RDF.iri("https://example.org/code#MyApp.Services.UserManager")
      assert RDF.Graph.describes?(graph, module_iri)
    end

    test "handles different base IRIs" do
      module_info = build_minimal_module()
      analysis = %{module: module_info}
      context = build_test_context(base_iri: "https://different.org/app#")

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      module_iri = RDF.iri("https://different.org/app#TestModule")
      assert RDF.Graph.describes?(graph, module_iri)
    end

    test "no duplicate triples in output" do
      module_info = build_minimal_module()
      analysis = %{module: module_info}
      context = build_test_context()

      {:ok, graph} = Orchestrator.build_module_graph(analysis, context)

      # Convert graph to list of triples and check for duplicates
      triples = RDF.Graph.triples(graph) |> Enum.to_list()
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end
  end
end
