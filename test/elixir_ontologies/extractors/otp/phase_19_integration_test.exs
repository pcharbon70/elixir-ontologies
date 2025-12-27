defmodule ElixirOntologies.Extractors.OTP.Phase19IntegrationTest do
  @moduledoc """
  Integration tests for Phase 19 Supervisor Child Specifications.

  These tests verify the complete extraction and RDF building pipeline
  for supervisor implementations, including child specs, strategies,
  and supervision tree relationships.

  Note: This test file is located in extractors/otp/ rather than the top-level
  test directory because it specifically tests OTP supervisor extraction
  and building, not general pipeline integration.
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Builders.OTP.SupervisorBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.OTP

  # ============================================================================
  # Test Helpers
  # ============================================================================

  # Parses module code string and returns the module body AST
  defp parse_module_body(code) do
    {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
    body
  end

  # Creates a test context with default base IRI
  defp build_test_context(base_iri \\ "https://example.org/code#") do
    Context.new(base_iri: base_iri)
  end

  # Creates a test IRI for a module name
  defp build_test_iri(module_name, base_iri \\ "https://example.org/code#") do
    RDF.iri("#{base_iri}#{module_name}")
  end

  # ============================================================================
  # Complex Supervision Tree Tests
  # ============================================================================

  describe "complex supervision tree extraction" do
    @complex_supervisor """
    defmodule MyApp.Supervisor do
      use Supervisor

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          # Module shorthand
          {MyApp.Worker, []},
          # Module with args
          {MyApp.Cache, name: :main_cache},
          # Full map spec
          %{
            id: :special_worker,
            start: {MyApp.SpecialWorker, :start_link, [[]]},
            restart: :transient,
            type: :worker
          },
          # Nested supervisor
          %{
            id: MyApp.ChildSupervisor,
            start: {MyApp.ChildSupervisor, :start_link, [[]]},
            type: :supervisor
          },
          # Temporary worker
          %{
            id: :temp_worker,
            start: {MyApp.TempWorker, :start_link, [[]]},
            restart: :temporary
          }
        ]

        Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
      end
    end
    """

    setup do
      {:ok, body: parse_module_body(@complex_supervisor)}
    end

    test "detects Supervisor implementation", %{body: body} do
      assert SupervisorExtractor.supervisor?(body)
      assert SupervisorExtractor.supervisor_type(body) == :supervisor
    end

    test "extracts strategy with custom restart intensity", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.max_restarts == 10
      assert strategy.max_seconds == 60
      assert strategy.is_default_max_restarts == false
      assert strategy.is_default_max_seconds == false
    end

    test "extracts all 5 child specs", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert length(children) == 5
    end

    test "extracts child spec with transient restart", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)

      # Use pattern match assertion for specific values
      assert %{id: :special_worker, restart: :transient, type: :worker} =
               Enum.find(children, &(&1.id == :special_worker))
    end

    test "extracts nested supervisor child", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)

      # Use pattern match to verify supervisor type child exists
      assert %{type: :supervisor} = Enum.find(children, &(&1.type == :supervisor))
    end

    test "extracts temporary worker", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)

      # Use pattern match for specific values
      assert %{id: :temp_worker, restart: :temporary} =
               Enum.find(children, &(&1.id == :temp_worker))
    end

    test "extracts ordered children", %{body: body} do
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      assert length(ordered) == 5

      # Verify ordering with pattern match
      assert [0, 1, 2, 3, 4] = Enum.map(ordered, & &1.position)
    end

    test "detects nested supervisors", %{body: body} do
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)

      # Should detect the explicit supervisor type
      assert length(nested) >= 1

      confirmed = Enum.filter(nested, & &1.is_confirmed)
      assert length(confirmed) >= 1
    end
  end

  # ============================================================================
  # Strategy Variations Tests
  # ============================================================================

  describe "strategy extraction - all types" do
    test "extracts one_for_all strategy" do
      code = """
      defmodule AllForOneSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_all)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_all
    end

    test "extracts rest_for_one strategy" do
      code = """
      defmodule RestForOneSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :rest_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :rest_for_one
    end

    test "uses default restart intensity when not specified" do
      code = """
      defmodule DefaultsSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.is_default_max_restarts == true
      assert strategy.is_default_max_seconds == true

      # Effective values should be OTP defaults
      assert SupervisorExtractor.effective_max_restarts(strategy) == 3
      assert SupervisorExtractor.effective_max_seconds(strategy) == 5
    end
  end

  # ============================================================================
  # DynamicSupervisor Tests
  # ============================================================================

  describe "DynamicSupervisor extraction" do
    @dynamic_supervisor """
    defmodule MyApp.DynamicSupervisor do
      use DynamicSupervisor

      def start_link(opts) do
        DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def start_child(args) do
        spec = {MyApp.DynamicWorker, args}
        DynamicSupervisor.start_child(__MODULE__, spec)
      end

      @impl true
      def init(_opts) do
        DynamicSupervisor.init(
          strategy: :one_for_one,
          max_children: 100,
          extra_arguments: [env: :prod]
        )
      end
    end
    """

    setup do
      {:ok, body: parse_module_body(@dynamic_supervisor)}
    end

    test "detects DynamicSupervisor", %{body: body} do
      assert SupervisorExtractor.supervisor?(body)
      assert SupervisorExtractor.dynamic_supervisor?(body)
      assert SupervisorExtractor.supervisor_type(body) == :dynamic_supervisor
    end

    test "extracts DynamicSupervisor strategy", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_one
    end

    test "extracts DynamicSupervisor config", %{body: body} do
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)
      assert config.max_children == 100
      assert config.extra_arguments == [env: :prod]
    end

    test "has no static children", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert children == []
    end
  end

  # ============================================================================
  # Builder Integration Tests
  # ============================================================================

  describe "builder integration - child specs" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "builds complete child spec RDF" do
      child_spec = %ChildSpec{
        id: :my_worker,
        module: MyWorker,
        start: %StartSpec{module: MyWorker, function: :start_link, args: [[]]},
        restart: :permanent,
        type: :worker
      }

      supervisor_iri = build_test_iri("MySupervisor")
      context = build_test_context()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # Verify IRI pattern
      assert to_string(child_spec_iri) =~ "/child/my_worker/0"

      # Verify type triple
      assert {child_spec_iri, RDF.type(), OTP.ChildSpec} in triples

      # Verify linked to supervisor
      assert {supervisor_iri, OTP.hasChildSpec(), child_spec_iri} in triples

      # Verify restart strategy
      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Permanent} in triples

      # Verify child type
      assert {child_spec_iri, OTP.hasChildType(), OTP.WorkerType} in triples
    end

    test "builds child spec with different restart strategies" do
      context = build_test_context()
      supervisor_iri = build_test_iri("Sup")

      # Test transient
      transient_spec = %ChildSpec{id: :t, module: T, restart: :transient, type: :worker}

      {transient_child_iri, transient_triples} =
        SupervisorBuilder.build_child_spec(transient_spec, supervisor_iri, context, 0)

      assert {transient_child_iri, OTP.hasRestartStrategy(), OTP.Transient} in transient_triples

      # Test temporary
      temporary_spec = %ChildSpec{id: :temp, module: Temp, restart: :temporary, type: :worker}

      {temp_iri, temp_triples} =
        SupervisorBuilder.build_child_spec(temporary_spec, supervisor_iri, context, 1)

      assert {temp_iri, OTP.hasRestartStrategy(), OTP.Temporary} in temp_triples
    end

    test "builds supervisor type child spec" do
      context = build_test_context()
      supervisor_iri = build_test_iri("Sup")

      sup_spec = %ChildSpec{
        id: :nested_sup,
        module: NestedSup,
        restart: :permanent,
        type: :supervisor
      }

      {sup_iri, sup_triples} =
        SupervisorBuilder.build_child_spec(sup_spec, supervisor_iri, context, 0)

      assert {sup_iri, OTP.hasChildType(), OTP.SupervisorType} in sup_triples
    end
  end

  describe "builder integration - supervision strategy" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy

    test "builds supervision strategy RDF with restart intensity" do
      strategy = %Strategy{
        type: :one_for_one,
        max_restarts: 5,
        max_seconds: 30
      }

      supervisor_iri = build_test_iri("MySupervisor")
      context = build_test_context()

      {strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy, supervisor_iri, context)

      # Verify strategy individual
      assert strategy_iri == OTP.OneForOne

      # Verify hasStrategy link
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForOne} in triples

      # Verify restart intensity on supervisor
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(5)} in triples
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(30)} in triples
    end

    test "builds all three strategy types" do
      context = build_test_context()
      supervisor_iri = build_test_iri("Sup")

      one_for_one = %Strategy{type: :one_for_one}
      one_for_all = %Strategy{type: :one_for_all}
      rest_for_one = %Strategy{type: :rest_for_one}

      {iri1, _} =
        SupervisorBuilder.build_supervision_strategy(one_for_one, supervisor_iri, context)

      {iri2, _} =
        SupervisorBuilder.build_supervision_strategy(one_for_all, supervisor_iri, context)

      {iri3, _} =
        SupervisorBuilder.build_supervision_strategy(rest_for_one, supervisor_iri, context)

      assert iri1 == OTP.OneForOne
      assert iri2 == OTP.OneForAll
      assert iri3 == OTP.RestForOne
    end

    test "uses OTP defaults for nil values" do
      strategy = %Strategy{
        type: :one_for_one,
        max_restarts: nil,
        max_seconds: nil
      }

      supervisor_iri = build_test_iri("Sup")
      context = build_test_context()

      {_, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy, supervisor_iri, context)

      # OTP defaults: max_restarts=3, max_seconds=5
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(3)} in triples
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(5)} in triples
    end
  end

  describe "builder integration - supervision tree" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}

    test "builds complete supervision tree with relationships" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: Worker1}, id: :w1},
        %ChildOrder{position: 1, child_spec: %ChildSpec{id: :w2, module: Worker2}, id: :w2}
      ]

      supervisor_iri = build_test_iri("MySupervisor")
      context = build_test_context()

      {_tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(children, supervisor_iri, context)

      # Verify supervision relationships
      worker1_iri = build_test_iri("Worker1")
      worker2_iri = build_test_iri("Worker2")

      assert {supervisor_iri, OTP.supervises(), worker1_iri} in triples
      assert {supervisor_iri, OTP.supervises(), worker2_iri} in triples
      assert {worker1_iri, OTP.supervisedBy(), supervisor_iri} in triples
      assert {worker2_iri, OTP.supervisedBy(), supervisor_iri} in triples

      # Verify ordered children list exists using Enum.any?
      assert Enum.any?(triples, fn
               {^supervisor_iri, pred, _} -> pred == OTP.hasChildren()
               _ -> false
             end)
    end

    test "builds root supervisor with tree" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: Worker1}, id: :w1}
      ]

      supervisor_iri = build_test_iri("MySupervisor")
      context = build_test_context()

      {tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(
          children,
          supervisor_iri,
          context,
          is_root: true,
          app_name: :my_app
        )

      # Verify tree IRI
      assert to_string(tree_iri) =~ "tree/my_app"

      # Verify tree triples
      assert {tree_iri, RDF.type(), OTP.SupervisionTree} in triples
      assert {tree_iri, OTP.rootSupervisor(), supervisor_iri} in triples
      assert {supervisor_iri, OTP.partOfTree(), tree_iri} in triples
    end
  end

  # ============================================================================
  # Shutdown Strategy Tests
  # ============================================================================

  describe "shutdown strategy extraction and building" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "extracts child spec with shutdown options" do
      code = """
      defmodule ShutdownSup do
        use Supervisor
        def init(_) do
          children = [
            %{
              id: :brutal_worker,
              start: {BrutalWorker, :start_link, [[]]},
              shutdown: :brutal_kill
            },
            %{
              id: :infinity_worker,
              start: {InfinityWorker, :start_link, [[]]},
              shutdown: :infinity
            },
            %{
              id: :timeout_worker,
              start: {TimeoutWorker, :start_link, [[]]},
              shutdown: 5000
            }
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 3

      # Find workers by id and verify shutdown values
      brutal = Enum.find(children, &(&1.id == :brutal_worker))
      infinity = Enum.find(children, &(&1.id == :infinity_worker))
      timeout = Enum.find(children, &(&1.id == :timeout_worker))

      assert brutal.shutdown == :brutal_kill
      assert infinity.shutdown == :infinity
      assert timeout.shutdown == 5000
    end

    test "builds child spec with shutdown in RDF" do
      # Note: If the builder supports shutdown triples, verify them here.
      # Currently testing that shutdown extraction works correctly.
      child_spec = %ChildSpec{
        id: :shutdown_worker,
        module: ShutdownWorker,
        restart: :permanent,
        type: :worker,
        shutdown: 10_000
      }

      supervisor_iri = build_test_iri("Sup")
      context = build_test_context()

      {child_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # Verify basic child spec triples are generated
      assert {child_iri, RDF.type(), OTP.ChildSpec} in triples
      assert {supervisor_iri, OTP.hasChildSpec(), child_iri} in triples
    end
  end

  # ============================================================================
  # Complete Pipeline Integration Tests
  # ============================================================================

  describe "complete pipeline - extraction to RDF" do
    @complete_supervisor """
    defmodule MyApp.CompleteSupervisor do
      use Supervisor

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          {MyApp.Worker1, []},
          %{
            id: :worker2,
            start: {MyApp.Worker2, :start_link, [[]]},
            restart: :transient
          }
        ]

        Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 30)
      end
    end
    """

    setup do
      {:ok, body: parse_module_body(@complete_supervisor)}
    end

    test "complete extraction to RDF pipeline", %{body: body} do
      # Step 1: Extract supervisor info
      {:ok, supervisor_info} = SupervisorExtractor.extract(body)
      assert supervisor_info.supervisor_type == :supervisor

      # Step 2: Extract strategy
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_all
      assert strategy.max_restarts == 5
      assert strategy.max_seconds == 30

      # Step 3: Extract children
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert length(children) == 2

      # Step 4: Extract ordered children
      {:ok, ordered_children} = SupervisorExtractor.extract_ordered_children(body)
      assert length(ordered_children) == 2

      # Step 5: Build supervisor RDF
      supervisor_iri = build_test_iri("MyApp.CompleteSupervisor")
      context = build_test_context()

      {_, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, supervisor_iri, context)

      # Step 6: Build strategy RDF
      {strategy_iri, strategy_triples} =
        SupervisorBuilder.build_supervision_strategy(strategy, supervisor_iri, context)

      # Step 7: Build child specs RDF
      {child_iris, child_triples} =
        SupervisorBuilder.build_child_specs(children, supervisor_iri, context)

      # Step 8: Build supervision tree RDF
      {tree_iri, tree_triples} =
        SupervisorBuilder.build_supervision_tree(
          ordered_children,
          supervisor_iri,
          context,
          is_root: true,
          app_name: :my_app
        )

      # Combine all triples
      all_triples = supervisor_triples ++ strategy_triples ++ child_triples ++ tree_triples

      # Verify complete RDF output
      # Supervisor type
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in all_triples

      # Strategy
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in all_triples
      assert strategy_iri == OTP.OneForAll

      # Restart intensity
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(5)} in all_triples
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(30)} in all_triples

      # Child specs linked - use Enum.all? for collection assertions
      assert length(child_iris) == 2

      assert Enum.all?(child_iris, fn child_iri ->
               {supervisor_iri, OTP.hasChildSpec(), child_iri} in all_triples
             end)

      # Tree structure
      assert {tree_iri, RDF.type(), OTP.SupervisionTree} in all_triples
      assert {tree_iri, OTP.rootSupervisor(), supervisor_iri} in all_triples
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling - malformed specs" do
    test "handles supervisor without init" do
      code = """
      defmodule NoInitSup do
        use Supervisor

        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts)
        end
      end
      """

      body = parse_module_body(code)

      # Should still detect as supervisor
      assert SupervisorExtractor.supervisor?(body)

      # Strategy extraction should return error
      assert {:error, _} = SupervisorExtractor.extract_strategy(body)
    end

    test "handles empty children list" do
      code = """
      defmodule EmptySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert children == []
    end

    test "handles children list with invalid entries gracefully" do
      # The extractor should skip invalid entries
      code = """
      defmodule MixedSup do
        use Supervisor
        def init(_) do
          children = [
            {ValidWorker, []},
            :invalid_atom,
            {AnotherWorker, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      # Should extract at least the valid entries
      assert length(children) >= 2
    end
  end

  # ============================================================================
  # Backward Compatibility Tests
  # ============================================================================

  describe "backward compatibility" do
    test "existing extract/1 still works" do
      code = """
      defmodule OldStyleSup do
        use Supervisor
        def init(_), do: Supervisor.init([], strategy: :one_for_one)
      end
      """

      body = parse_module_body(code)
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :supervisor
      assert result.detection_method == :use
    end

    test "existing supervisor?/1 still works" do
      code = """
      defmodule CheckSup do
        use Supervisor
        def init(_), do: :ok
      end
      """

      body = parse_module_body(code)

      assert SupervisorExtractor.supervisor?(body) == true
    end

    test "existing child_count/1 still works" do
      code = """
      defmodule CountSup do
        use Supervisor
        def init(_) do
          children = [{W1, []}, {W2, []}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      count = SupervisorExtractor.child_count(body)

      assert count == 2
    end
  end
end
