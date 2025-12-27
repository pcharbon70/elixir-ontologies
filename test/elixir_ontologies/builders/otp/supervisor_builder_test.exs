defmodule ElixirOntologies.Builders.OTP.SupervisorBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.OTP.SupervisorBuilder

  alias ElixirOntologies.Builders.OTP.SupervisorBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.OTP.Supervisor
  alias ElixirOntologies.NS.OTP

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "TestSupervisor")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_supervisor(opts \\ []) do
    %Supervisor{
      supervisor_type: Keyword.get(opts, :supervisor_type, :supervisor),
      detection_method: Keyword.get(opts, :detection_method, :use),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_strategy(opts \\ []) do
    %Supervisor.Strategy{
      type: Keyword.get(opts, :type, :one_for_one),
      max_restarts: Keyword.get(opts, :max_restarts, 3),
      max_seconds: Keyword.get(opts, :max_seconds, 5),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Supervisor Implementation Building Tests
  # ===========================================================================

  describe "build_supervisor/3 - basic building" do
    test "builds minimal Supervisor with use detection" do
      supervisor_info =
        build_test_supervisor(supervisor_type: :supervisor, detection_method: :use)

      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify IRI (same as module IRI)
      assert supervisor_iri == module_iri
      assert to_string(supervisor_iri) == "https://example.org/code#TestSupervisor"

      # Verify type triple
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples

      # Verify implementsOTPBehaviour triple
      assert {supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour} in triples
    end

    test "builds DynamicSupervisor" do
      supervisor_info = build_test_supervisor(supervisor_type: :dynamic_supervisor)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify type triple
      assert {supervisor_iri, RDF.type(), OTP.DynamicSupervisor} in triples

      # Verify implementsOTPBehaviour triple (still SupervisorBehaviour)
      assert {supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour} in triples
    end

    test "builds Supervisor with behaviour detection" do
      supervisor_info = build_test_supervisor(detection_method: :behaviour)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify type triple
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples
    end
  end

  describe "build_supervisor/3 - IRI patterns" do
    test "Supervisor IRI is same as module IRI" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MySupervisor")

      {supervisor_iri, _triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      assert supervisor_iri == module_iri
      assert to_string(supervisor_iri) == "https://example.org/code#MySupervisor"
    end

    test "handles nested module names" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Supervisors.MainSupervisor")

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      assert supervisor_iri == module_iri
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples
    end
  end

  # ===========================================================================
  # Supervision Strategy Building Tests
  # ===========================================================================

  describe "build_strategy/3 - one_for_one strategy" do
    test "builds one_for_one strategy" do
      strategy_info = build_test_strategy(type: :one_for_one)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy IRI is predefined individual
      assert strategy_iri == OTP.OneForOne

      # Verify hasStrategy link
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in triples
    end
  end

  describe "build_strategy/3 - one_for_all strategy" do
    test "builds one_for_all strategy" do
      strategy_info = build_test_strategy(type: :one_for_all)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy IRI is predefined individual
      assert strategy_iri == OTP.OneForAll

      # Verify hasStrategy link
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in triples
    end
  end

  describe "build_strategy/3 - rest_for_one strategy" do
    test "builds rest_for_one strategy" do
      strategy_info = build_test_strategy(type: :rest_for_one)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy IRI is predefined individual
      assert strategy_iri == OTP.RestForOne

      # Verify hasStrategy link
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in triples
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "no duplicate triples in Supervisor implementation" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "no duplicate triples in strategy" do
      strategy_info = build_test_strategy()
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "Supervisor has both type and implementsOTPBehaviour" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Count relevant triples
      has_type =
        Enum.any?(triples, fn
          {^supervisor_iri, pred, OTP.Supervisor} -> pred == RDF.type()
          _ -> false
        end)

      has_behaviour =
        Enum.any?(triples, fn
          {^supervisor_iri, pred, OTP.SupervisorBehaviour} -> pred == OTP.implementsOTPBehaviour()
          _ -> false
        end)

      assert has_type
      assert has_behaviour
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "can build Supervisor with strategy" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      # Build Supervisor
      {supervisor_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy
      strategy_info = build_test_strategy(type: :one_for_one)

      {strategy_iri, strategy_triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify Supervisor implementation exists
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in supervisor_triples

      # Verify strategy link
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in strategy_triples

      # Verify strategy is predefined individual
      assert strategy_iri == OTP.OneForOne
    end

    test "can build Supervisor with multiple strategies for different children" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      # Build Supervisor
      {supervisor_iri, _supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build multiple strategies (though typically only one per supervisor)
      strategy1 = build_test_strategy(type: :one_for_one)
      strategy2 = build_test_strategy(type: :one_for_all)

      {strategy_iri1, triples1} =
        SupervisorBuilder.build_strategy(strategy1, supervisor_iri, context)

      {strategy_iri2, triples2} =
        SupervisorBuilder.build_strategy(strategy2, supervisor_iri, context)

      # Verify different strategies
      assert strategy_iri1 == OTP.OneForOne
      assert strategy_iri2 == OTP.OneForAll
      assert strategy_iri1 != strategy_iri2

      # Verify links
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri1} in triples1
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri2} in triples2
    end

    test "Supervisor in nested module" do
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Supervisors.TreeSupervisor")

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify implementation
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples

      assert to_string(supervisor_iri) ==
               "https://example.org/code#MyApp.Supervisors.TreeSupervisor"
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "DynamicSupervisor with strategy" do
      supervisor_info = build_test_supervisor(supervisor_type: :dynamic_supervisor)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy
      strategy_info = build_test_strategy(type: :one_for_one)

      {strategy_iri, strategy_triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify DynamicSupervisor type
      assert {supervisor_iri, RDF.type(), OTP.DynamicSupervisor} in supervisor_triples

      # Verify strategy link works for DynamicSupervisor
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in strategy_triples
    end

    test "strategy with custom max_restarts and max_seconds" do
      strategy_info = build_test_strategy(max_restarts: 10, max_seconds: 60)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy exists (max_restarts/max_seconds not yet captured in RDF)
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in triples
    end

    test "Supervisor with behaviour detection method" do
      supervisor_info = build_test_supervisor(detection_method: :behaviour)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify implementation (detection method doesn't affect RDF output)
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples
      assert {supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour} in triples
    end
  end

  # ===========================================================================
  # Child Spec Builder Tests
  # ===========================================================================

  describe "build_child_spec/4 - basic building" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "builds minimal child spec with id and type" do
      child_spec = %ChildSpec{
        id: :worker1,
        module: MyWorker,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # Verify IRI pattern
      assert to_string(child_spec_iri) =~ "TestSupervisor/child/worker1/0"

      # Verify type triple
      assert {child_spec_iri, RDF.type(), OTP.ChildSpec} in triples

      # Verify link to supervisor
      assert {supervisor_iri, OTP.hasChildSpec(), child_spec_iri} in triples

      # Verify child ID
      assert {child_spec_iri, OTP.childId(), RDF.literal("worker1")} in triples

      # Verify child type
      assert {child_spec_iri, OTP.hasChildType(), OTP.WorkerType} in triples

      # Verify restart strategy
      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Permanent} in triples
    end

    test "builds child spec with module as id" do
      child_spec = %ChildSpec{
        id: MyWorker,
        module: MyWorker,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # Verify child ID is the module name
      assert {child_spec_iri, OTP.childId(), RDF.literal("MyWorker")} in triples
    end

    test "builds child spec with start spec" do
      start_spec = %StartSpec{
        module: MyWorker,
        function: :start_link,
        args: [[]]
      }

      child_spec = %ChildSpec{
        id: :worker1,
        module: MyWorker,
        start: start_spec,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # Verify start module
      assert {child_spec_iri, OTP.startModule(), RDF.literal("MyWorker")} in triples

      # Verify start function
      assert {child_spec_iri, OTP.startFunction(), RDF.literal("start_link")} in triples
    end
  end

  describe "build_child_spec/4 - restart strategies" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "builds child spec with permanent restart" do
      child_spec = %ChildSpec{
        id: :worker1,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Permanent} in triples
    end

    test "builds child spec with temporary restart" do
      child_spec = %ChildSpec{
        id: :worker1,
        restart: :temporary,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Temporary} in triples
    end

    test "builds child spec with transient restart" do
      child_spec = %ChildSpec{
        id: :worker1,
        restart: :transient,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Transient} in triples
    end
  end

  describe "build_child_spec/4 - child types" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "builds child spec with worker type" do
      child_spec = %ChildSpec{
        id: :worker1,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      assert {child_spec_iri, OTP.hasChildType(), OTP.WorkerType} in triples
    end

    test "builds child spec with supervisor type" do
      child_spec = %ChildSpec{
        id: :sub_supervisor,
        restart: :permanent,
        type: :supervisor
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      assert {child_spec_iri, OTP.hasChildType(), OTP.SupervisorType} in triples
    end
  end

  describe "build_child_spec/4 - indexing" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "child specs at different positions have different IRIs" do
      child_spec = %ChildSpec{
        id: :worker,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {iri0, _} = SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)
      {iri1, _} = SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 1)
      {iri2, _} = SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 2)

      # All IRIs should be unique
      assert iri0 != iri1
      assert iri1 != iri2
      assert iri0 != iri2

      # Verify IRI patterns
      assert to_string(iri0) =~ "/child/worker/0"
      assert to_string(iri1) =~ "/child/worker/1"
      assert to_string(iri2) =~ "/child/worker/2"
    end
  end

  describe "build_child_specs/3 - multiple children" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "builds triples for multiple child specs" do
      specs = [
        %ChildSpec{id: :worker1, restart: :permanent, type: :worker},
        %ChildSpec{id: :worker2, restart: :temporary, type: :worker},
        %ChildSpec{id: :sub_sup, restart: :permanent, type: :supervisor}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {iris, triples} = SupervisorBuilder.build_child_specs(specs, supervisor_iri, context)

      # Should have 3 IRIs
      assert length(iris) == 3

      # Each IRI should have different index
      assert to_string(Enum.at(iris, 0)) =~ "/child/worker1/0"
      assert to_string(Enum.at(iris, 1)) =~ "/child/worker2/1"
      assert to_string(Enum.at(iris, 2)) =~ "/child/sub_sup/2"

      # All should have type triples
      child_spec_class = OTP.ChildSpec

      assert Enum.count(triples, fn {_, pred, obj} ->
               pred == RDF.type() and obj == child_spec_class
             end) == 3

      # Check different restart strategies
      assert {Enum.at(iris, 0), OTP.hasRestartStrategy(), OTP.Permanent} in triples
      assert {Enum.at(iris, 1), OTP.hasRestartStrategy(), OTP.Temporary} in triples

      # Check different child types
      assert {Enum.at(iris, 0), OTP.hasChildType(), OTP.WorkerType} in triples
      assert {Enum.at(iris, 2), OTP.hasChildType(), OTP.SupervisorType} in triples
    end

    test "builds empty list for no specs" do
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {iris, triples} = SupervisorBuilder.build_child_specs([], supervisor_iri, context)

      assert iris == []
      assert triples == []
    end
  end

  describe "build_child_spec/4 - triple validation" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "no duplicate triples" do
      start_spec = %StartSpec{
        module: MyWorker,
        function: :start_link,
        args: [[]]
      }

      child_spec = %ChildSpec{
        id: :worker1,
        module: MyWorker,
        start: start_spec,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "all triples have valid subjects and predicates" do
      child_spec = %ChildSpec{
        id: :worker1,
        module: MyWorker,
        restart: :permanent,
        type: :worker
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)

      # All triples should have IRI subjects
      Enum.each(triples, fn {subject, predicate, _object} ->
        assert %RDF.IRI{} = subject
        assert %RDF.IRI{} = predicate
      end)
    end
  end

  describe "integration - supervisor with child specs" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "can build complete supervisor with children" do
      # Build supervisor
      supervisor_info =
        build_test_supervisor(supervisor_type: :supervisor, detection_method: :use)

      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy
      strategy_info = build_test_strategy(type: :one_for_one)

      {_strategy_iri, strategy_triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Build child specs
      specs = [
        %ChildSpec{
          id: :worker1,
          module: Worker1,
          start: %StartSpec{module: Worker1, function: :start_link, args: [[]]},
          restart: :permanent,
          type: :worker
        },
        %ChildSpec{
          id: :worker2,
          module: Worker2,
          start: %StartSpec{module: Worker2, function: :start_link, args: [[]]},
          restart: :transient,
          type: :worker
        }
      ]

      {child_iris, child_triples} =
        SupervisorBuilder.build_child_specs(specs, supervisor_iri, context)

      # Combine all triples
      all_triples = supervisor_triples ++ strategy_triples ++ child_triples

      # Verify supervisor exists
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in all_triples

      # Verify strategy link
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForOne} in all_triples

      # Verify child specs are linked to supervisor
      Enum.each(child_iris, fn child_iri ->
        assert {supervisor_iri, OTP.hasChildSpec(), child_iri} in all_triples
      end)

      # Verify each child spec has type
      Enum.each(child_iris, fn child_iri ->
        assert {child_iri, RDF.type(), OTP.ChildSpec} in all_triples
      end)
    end
  end

  # ===========================================================================
  # Supervision Strategy Builder Tests
  # ===========================================================================

  describe "build_supervision_strategy/3 - strategy types" do
    test "builds one_for_one strategy with restart intensity" do
      strategy_info = build_test_strategy(type: :one_for_one, max_restarts: 5, max_seconds: 10)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy is predefined individual
      assert strategy_iri == OTP.OneForOne

      # Verify hasStrategy link
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForOne} in triples

      # Verify maxRestarts on supervisor
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(5)} in triples

      # Verify maxSeconds on supervisor
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(10)} in triples
    end

    test "builds one_for_all strategy" do
      strategy_info = build_test_strategy(type: :one_for_all, max_restarts: 3, max_seconds: 5)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy
      assert strategy_iri == OTP.OneForAll
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForAll} in triples
    end

    test "builds rest_for_one strategy" do
      strategy_info = build_test_strategy(type: :rest_for_one, max_restarts: 3, max_seconds: 5)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy
      assert strategy_iri == OTP.RestForOne
      assert {supervisor_iri, OTP.hasStrategy(), OTP.RestForOne} in triples
    end
  end

  describe "build_supervision_strategy/3 - restart intensity" do
    test "uses explicit max_restarts value" do
      strategy_info = build_test_strategy(max_restarts: 10, max_seconds: 5)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(10)} in triples
    end

    test "uses explicit max_seconds value" do
      strategy_info = build_test_strategy(max_restarts: 3, max_seconds: 60)
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(60)} in triples
    end

    test "uses OTP default for nil max_restarts" do
      strategy_info = %Supervisor.Strategy{
        type: :one_for_one,
        max_restarts: nil,
        max_seconds: 10
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # OTP default for max_restarts is 3
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(3)} in triples
    end

    test "uses OTP default for nil max_seconds" do
      strategy_info = %Supervisor.Strategy{
        type: :one_for_one,
        max_restarts: 10,
        max_seconds: nil
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # OTP default for max_seconds is 5
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(5)} in triples
    end

    test "uses both OTP defaults when nil" do
      strategy_info = %Supervisor.Strategy{
        type: :one_for_one,
        max_restarts: nil,
        max_seconds: nil
      }

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # OTP defaults: max_restarts=3, max_seconds=5
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(3)} in triples
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(5)} in triples
    end
  end

  describe "build_supervision_strategy/3 - triple validation" do
    test "generates exactly 3 triples" do
      strategy_info = build_test_strategy()
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # hasStrategy + maxRestarts + maxSeconds
      assert length(triples) == 3
    end

    test "no duplicate triples" do
      strategy_info = build_test_strategy()
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "all triples have supervisor as subject" do
      strategy_info = build_test_strategy()
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_strategy_iri, triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # All triples should have supervisor_iri as subject
      Enum.each(triples, fn {subject, _predicate, _object} ->
        assert subject == supervisor_iri
      end)
    end
  end

  describe "build_supervision_strategy/3 - integration" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "complete supervisor with strategy and children" do
      # Build supervisor
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy with custom restart intensity
      strategy_info =
        build_test_strategy(
          type: :one_for_all,
          max_restarts: 10,
          max_seconds: 60
        )

      {strategy_iri, strategy_triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # Build child spec
      specs = [
        %ChildSpec{
          id: :worker1,
          module: Worker1,
          start: %StartSpec{module: Worker1, function: :start_link, args: [[]]},
          restart: :permanent,
          type: :worker
        }
      ]

      {child_iris, child_triples} =
        SupervisorBuilder.build_child_specs(specs, supervisor_iri, context)

      # Combine all triples
      all_triples = supervisor_triples ++ strategy_triples ++ child_triples

      # Verify supervisor type
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in all_triples

      # Verify strategy link
      assert {supervisor_iri, OTP.hasStrategy(), strategy_iri} in all_triples
      assert strategy_iri == OTP.OneForAll

      # Verify restart intensity on supervisor
      assert {supervisor_iri, OTP.maxRestarts(), RDF.literal(10)} in all_triples
      assert {supervisor_iri, OTP.maxSeconds(), RDF.literal(60)} in all_triples

      # Verify child specs
      [child_iri] = child_iris
      assert {supervisor_iri, OTP.hasChildSpec(), child_iri} in all_triples
    end
  end

  # ===========================================================================
  # Supervision Tree Builder Tests
  # ===========================================================================

  describe "build_supervision_relationships/3" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "generates supervises triples for each child" do
      specs = [
        %ChildSpec{id: :worker1, module: Worker1},
        %ChildSpec{id: :worker2, module: Worker2}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      triples = SupervisorBuilder.build_supervision_relationships(specs, supervisor_iri, context)

      # Should have supervises triple for each child
      worker1_iri = RDF.iri("https://example.org/code#Worker1")
      worker2_iri = RDF.iri("https://example.org/code#Worker2")

      assert {supervisor_iri, OTP.supervises(), worker1_iri} in triples
      assert {supervisor_iri, OTP.supervises(), worker2_iri} in triples
    end

    test "generates supervisedBy triples (inverse)" do
      specs = [%ChildSpec{id: :worker1, module: Worker1}]
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      triples = SupervisorBuilder.build_supervision_relationships(specs, supervisor_iri, context)

      worker1_iri = RDF.iri("https://example.org/code#Worker1")
      assert {worker1_iri, OTP.supervisedBy(), supervisor_iri} in triples
    end

    test "skips children without module" do
      specs = [
        %ChildSpec{id: :worker1, module: nil},
        %ChildSpec{id: :worker2, module: Worker2}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      triples = SupervisorBuilder.build_supervision_relationships(specs, supervisor_iri, context)

      # Should only have triples for Worker2
      assert length(triples) == 2
      worker2_iri = RDF.iri("https://example.org/code#Worker2")
      assert {supervisor_iri, OTP.supervises(), worker2_iri} in triples
    end

    test "returns empty list for empty specs" do
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      triples = SupervisorBuilder.build_supervision_relationships([], supervisor_iri, context)
      assert triples == []
    end
  end

  describe "build_ordered_children/3" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}

    test "returns nil for empty list" do
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {list_iri, triples} = SupervisorBuilder.build_ordered_children([], supervisor_iri, context)

      assert list_iri == nil
      assert triples == []
    end

    test "builds rdf:List structure for ordered children" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1},
        %ChildOrder{position: 1, child_spec: %ChildSpec{id: :w2, module: W2}, id: :w2}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {list_iri, triples} =
        SupervisorBuilder.build_ordered_children(children, supervisor_iri, context)

      # List IRI should be a blank node
      assert %RDF.BlankNode{} = list_iri

      # Should have hasChildren link
      assert {supervisor_iri, OTP.hasChildren(), list_iri} in triples

      # Should have rdf:first and rdf:rest triples
      first_triples = Enum.filter(triples, fn {_, pred, _} -> pred == RDF.first() end)
      rest_triples = Enum.filter(triples, fn {_, pred, _} -> pred == RDF.rest() end)

      assert length(first_triples) == 2
      assert length(rest_triples) == 2
    end

    test "preserves child ordering by position" do
      # Deliberately out of order in list
      children = [
        %ChildOrder{position: 2, child_spec: %ChildSpec{id: :w3}, id: :w3},
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1}, id: :w1},
        %ChildOrder{position: 1, child_spec: %ChildSpec{id: :w2}, id: :w2}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {list_iri, triples} =
        SupervisorBuilder.build_ordered_children(children, supervisor_iri, context)

      # Find first element (should be w1 at position 0)
      rdf_first = RDF.first()

      first_element =
        Enum.find_value(triples, fn
          {subj, ^rdf_first, obj} when subj == list_iri -> obj
          _ -> nil
        end)

      # First element should reference child spec at position 0
      assert to_string(first_element) =~ "/child/w1/0"
    end
  end

  describe "build_root_supervisor/3" do
    test "generates tree type triple" do
      supervisor_iri = build_test_module_iri()
      tree_iri = RDF.iri("https://example.org/code#tree/my_app")
      context = build_test_context()

      triples = SupervisorBuilder.build_root_supervisor(supervisor_iri, tree_iri, context)

      assert {tree_iri, RDF.type(), OTP.SupervisionTree} in triples
    end

    test "generates rootSupervisor link" do
      supervisor_iri = build_test_module_iri()
      tree_iri = RDF.iri("https://example.org/code#tree/my_app")
      context = build_test_context()

      triples = SupervisorBuilder.build_root_supervisor(supervisor_iri, tree_iri, context)

      assert {tree_iri, OTP.rootSupervisor(), supervisor_iri} in triples
    end

    test "generates partOfTree link" do
      supervisor_iri = build_test_module_iri()
      tree_iri = RDF.iri("https://example.org/code#tree/my_app")
      context = build_test_context()

      triples = SupervisorBuilder.build_root_supervisor(supervisor_iri, tree_iri, context)

      assert {supervisor_iri, OTP.partOfTree(), tree_iri} in triples
    end

    test "generates exactly 3 triples" do
      supervisor_iri = build_test_module_iri()
      tree_iri = RDF.iri("https://example.org/code#tree/my_app")
      context = build_test_context()

      triples = SupervisorBuilder.build_root_supervisor(supervisor_iri, tree_iri, context)

      assert length(triples) == 3
    end
  end

  describe "build_supervision_tree/4" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}

    test "combines supervision relationships and ordered children" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(children, supervisor_iri, context)

      # Not a root supervisor by default
      assert tree_iri == nil

      # Should have supervision relationships
      w1_iri = RDF.iri("https://example.org/code#W1")
      assert {supervisor_iri, OTP.supervises(), w1_iri} in triples
      assert {w1_iri, OTP.supervisedBy(), supervisor_iri} in triples

      # Should have ordered children (hasChildren)
      has_children_triple =
        Enum.find(triples, fn
          {^supervisor_iri, pred, _} -> pred == OTP.hasChildren()
          _ -> false
        end)

      assert has_children_triple != nil
    end

    test "marks root supervisor with tree_iri option" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()
      tree_iri = RDF.iri("https://example.org/code#tree/my_app")

      {returned_tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(
          children,
          supervisor_iri,
          context,
          is_root: true,
          tree_iri: tree_iri
        )

      assert returned_tree_iri == tree_iri

      # Should have root supervisor triples
      assert {tree_iri, RDF.type(), OTP.SupervisionTree} in triples
      assert {tree_iri, OTP.rootSupervisor(), supervisor_iri} in triples
      assert {supervisor_iri, OTP.partOfTree(), tree_iri} in triples
    end

    test "generates tree IRI from app_name option" do
      children = [
        %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {returned_tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(
          children,
          supervisor_iri,
          context,
          is_root: true,
          app_name: :my_app
        )

      # Tree IRI should be generated from app_name
      assert to_string(returned_tree_iri) =~ "tree/my_app"

      # Should have root supervisor triples
      assert {returned_tree_iri, RDF.type(), OTP.SupervisionTree} in triples
    end

    test "handles empty children list" do
      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree([], supervisor_iri, context)

      assert tree_iri == nil
      assert triples == []
    end

    test "skips nil child_specs" do
      children = [
        %ChildOrder{position: 0, child_spec: nil, id: :w1},
        %ChildOrder{position: 1, child_spec: %ChildSpec{id: :w2, module: W2}, id: :w2}
      ]

      context = build_test_context()
      supervisor_iri = build_test_module_iri()

      {_tree_iri, triples} =
        SupervisorBuilder.build_supervision_tree(children, supervisor_iri, context)

      # Should only have supervision triples for W2
      w2_iri = RDF.iri("https://example.org/code#W2")
      assert {supervisor_iri, OTP.supervises(), w2_iri} in triples

      # Should not have supervises for nil child_spec
      supervision_triples =
        Enum.filter(triples, fn
          {^supervisor_iri, pred, _} -> pred == OTP.supervises()
          _ -> false
        end)

      assert length(supervision_triples) == 1
    end
  end

  describe "build_supervision_tree/4 - integration" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "complete supervision tree with all components" do
      # Build supervisor
      supervisor_info = build_test_supervisor()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {supervisor_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy
      strategy_info = build_test_strategy(type: :one_for_all)

      {_strategy_iri, strategy_triples} =
        SupervisorBuilder.build_supervision_strategy(strategy_info, supervisor_iri, context)

      # Build children with ordering
      children = [
        %ChildOrder{
          position: 0,
          child_spec: %ChildSpec{
            id: :worker1,
            module: Worker1,
            start: %StartSpec{module: Worker1, function: :start_link, args: [[]]},
            restart: :permanent,
            type: :worker
          },
          id: :worker1
        },
        %ChildOrder{
          position: 1,
          child_spec: %ChildSpec{
            id: :worker2,
            module: Worker2,
            start: %StartSpec{module: Worker2, function: :start_link, args: [[]]},
            restart: :temporary,
            type: :worker
          },
          id: :worker2
        }
      ]

      # Build supervision tree as root
      {tree_iri, tree_triples} =
        SupervisorBuilder.build_supervision_tree(
          children,
          supervisor_iri,
          context,
          is_root: true,
          app_name: :my_app
        )

      # Combine all triples
      all_triples = supervisor_triples ++ strategy_triples ++ tree_triples

      # Verify supervisor
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in all_triples

      # Verify strategy
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForAll} in all_triples

      # Verify supervision relationships
      worker1_iri = RDF.iri("https://example.org/code#Worker1")
      worker2_iri = RDF.iri("https://example.org/code#Worker2")
      assert {supervisor_iri, OTP.supervises(), worker1_iri} in all_triples
      assert {supervisor_iri, OTP.supervises(), worker2_iri} in all_triples
      assert {worker1_iri, OTP.supervisedBy(), supervisor_iri} in all_triples
      assert {worker2_iri, OTP.supervisedBy(), supervisor_iri} in all_triples

      # Verify tree
      assert {tree_iri, RDF.type(), OTP.SupervisionTree} in all_triples
      assert {tree_iri, OTP.rootSupervisor(), supervisor_iri} in all_triples
      assert {supervisor_iri, OTP.partOfTree(), tree_iri} in all_triples

      # Verify ordered children list exists
      has_children_triple =
        Enum.find(all_triples, fn
          {^supervisor_iri, pred, _} -> pred == OTP.hasChildren()
          _ -> false
        end)

      assert has_children_triple != nil
    end
  end
end
