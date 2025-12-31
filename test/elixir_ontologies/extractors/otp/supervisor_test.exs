defmodule ElixirOntologies.Extractors.OTP.SupervisorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
  alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
  alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder
  alias ElixirOntologies.Extractors.OTP.Supervisor.NestedSupervisor

  # Run doctests from the Supervisor module
  doctest ElixirOntologies.Extractors.OTP.Supervisor
  doctest ElixirOntologies.Extractors.OTP.Supervisor.Strategy
  doctest ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
  doctest ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder
  doctest ElixirOntologies.Extractors.OTP.Supervisor.NestedSupervisor

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp parse_module_body(code) do
    {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
    body
  end

  defp parse_statement(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  # ===========================================================================
  # supervisor?/1 Tests
  # ===========================================================================

  describe "supervisor?/1" do
    test "returns true for use Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.supervisor?(body)
    end

    test "returns true for use DynamicSupervisor" do
      body = parse_module_body("defmodule S do use DynamicSupervisor end")
      assert SupervisorExtractor.supervisor?(body)
    end

    test "returns true for @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      assert SupervisorExtractor.supervisor?(body)
    end

    test "returns true for @behaviour DynamicSupervisor" do
      body = parse_module_body("defmodule S do @behaviour DynamicSupervisor end")
      assert SupervisorExtractor.supervisor?(body)
    end

    test "returns false for plain module" do
      body = parse_module_body("defmodule S do def foo, do: :ok end")
      refute SupervisorExtractor.supervisor?(body)
    end

    test "returns false for use GenServer" do
      body = parse_module_body("defmodule S do use GenServer end")
      refute SupervisorExtractor.supervisor?(body)
    end
  end

  # ===========================================================================
  # use_supervisor?/1 Tests
  # ===========================================================================

  describe "use_supervisor?/1" do
    test "returns true for use Supervisor" do
      ast = parse_statement("use Supervisor")
      assert SupervisorExtractor.use_supervisor?(ast)
    end

    test "returns true for use Supervisor with options" do
      ast = parse_statement("use Supervisor, strategy: :one_for_one")
      assert SupervisorExtractor.use_supervisor?(ast)
    end

    test "returns false for use DynamicSupervisor" do
      ast = parse_statement("use DynamicSupervisor")
      refute SupervisorExtractor.use_supervisor?(ast)
    end

    test "returns false for use GenServer" do
      ast = parse_statement("use GenServer")
      refute SupervisorExtractor.use_supervisor?(ast)
    end
  end

  # ===========================================================================
  # use_dynamic_supervisor?/1 Tests
  # ===========================================================================

  describe "use_dynamic_supervisor?/1" do
    test "returns true for use DynamicSupervisor" do
      ast = parse_statement("use DynamicSupervisor")
      assert SupervisorExtractor.use_dynamic_supervisor?(ast)
    end

    test "returns true for use DynamicSupervisor with options" do
      ast = parse_statement("use DynamicSupervisor, strategy: :one_for_one")
      assert SupervisorExtractor.use_dynamic_supervisor?(ast)
    end

    test "returns false for use Supervisor" do
      ast = parse_statement("use Supervisor")
      refute SupervisorExtractor.use_dynamic_supervisor?(ast)
    end
  end

  # ===========================================================================
  # behaviour_supervisor?/1 Tests
  # ===========================================================================

  describe "behaviour_supervisor?/1" do
    test "returns true for @behaviour Supervisor" do
      ast = parse_statement("@behaviour Supervisor")
      assert SupervisorExtractor.behaviour_supervisor?(ast)
    end

    test "returns false for @behaviour DynamicSupervisor" do
      ast = parse_statement("@behaviour DynamicSupervisor")
      refute SupervisorExtractor.behaviour_supervisor?(ast)
    end

    test "returns false for @behaviour GenServer" do
      ast = parse_statement("@behaviour GenServer")
      refute SupervisorExtractor.behaviour_supervisor?(ast)
    end
  end

  # ===========================================================================
  # behaviour_dynamic_supervisor?/1 Tests
  # ===========================================================================

  describe "behaviour_dynamic_supervisor?/1" do
    test "returns true for @behaviour DynamicSupervisor" do
      ast = parse_statement("@behaviour DynamicSupervisor")
      assert SupervisorExtractor.behaviour_dynamic_supervisor?(ast)
    end

    test "returns false for @behaviour Supervisor" do
      ast = parse_statement("@behaviour Supervisor")
      refute SupervisorExtractor.behaviour_dynamic_supervisor?(ast)
    end
  end

  # ===========================================================================
  # extract/2 Tests
  # ===========================================================================

  describe "extract/2" do
    test "extracts use Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :supervisor
      assert result.detection_method == :use
      assert result.use_options == []
      assert result.metadata.otp_behaviour == :supervisor
      assert result.metadata.is_dynamic == false
    end

    test "extracts use Supervisor with options" do
      body = parse_module_body("defmodule S do use Supervisor, strategy: :one_for_one end")
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :supervisor
      assert result.use_options == [strategy: :one_for_one]
      assert result.metadata.has_options == true
    end

    test "extracts use DynamicSupervisor" do
      body = parse_module_body("defmodule S do use DynamicSupervisor end")
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :dynamic_supervisor
      assert result.detection_method == :use
      assert result.metadata.is_dynamic == true
    end

    test "extracts use DynamicSupervisor with options" do
      body =
        parse_module_body(
          "defmodule S do use DynamicSupervisor, strategy: :one_for_one, max_children: 100 end"
        )

      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :dynamic_supervisor
      assert result.use_options == [strategy: :one_for_one, max_children: 100]
    end

    test "extracts @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :supervisor
      assert result.detection_method == :behaviour
      assert result.use_options == nil
    end

    test "extracts @behaviour DynamicSupervisor" do
      body = parse_module_body("defmodule S do @behaviour DynamicSupervisor end")
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :dynamic_supervisor
      assert result.detection_method == :behaviour
      assert result.metadata.is_dynamic == true
    end

    test "returns error for non-Supervisor module" do
      body = parse_module_body("defmodule S do def foo, do: :ok end")
      assert {:error, "Module does not implement Supervisor"} = SupervisorExtractor.extract(body)
    end

    test "handles nil body" do
      result = SupervisorExtractor.extract(nil)
      assert {:error, "Module does not implement Supervisor"} = result
    end
  end

  # ===========================================================================
  # extract!/2 Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns result for valid Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      result = SupervisorExtractor.extract!(body)

      assert result.supervisor_type == :supervisor
    end

    test "raises for non-Supervisor module" do
      body = parse_module_body("defmodule S do def foo, do: :ok end")

      assert_raise ArgumentError, "Module does not implement Supervisor", fn ->
        SupervisorExtractor.extract!(body)
      end
    end
  end

  # ===========================================================================
  # supervisor_type/1 Tests
  # ===========================================================================

  describe "supervisor_type/1" do
    test "returns :supervisor for use Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.supervisor_type(body) == :supervisor
    end

    test "returns :supervisor for @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      assert SupervisorExtractor.supervisor_type(body) == :supervisor
    end

    test "returns :dynamic_supervisor for use DynamicSupervisor" do
      body = parse_module_body("defmodule S do use DynamicSupervisor end")
      assert SupervisorExtractor.supervisor_type(body) == :dynamic_supervisor
    end

    test "returns :dynamic_supervisor for @behaviour DynamicSupervisor" do
      body = parse_module_body("defmodule S do @behaviour DynamicSupervisor end")
      assert SupervisorExtractor.supervisor_type(body) == :dynamic_supervisor
    end

    test "returns nil for non-Supervisor module" do
      body = parse_module_body("defmodule S do use GenServer end")
      assert SupervisorExtractor.supervisor_type(body) == nil
    end
  end

  # ===========================================================================
  # detection_method/1 Tests
  # ===========================================================================

  describe "detection_method/1" do
    test "returns :use for use Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.detection_method(body) == :use
    end

    test "returns :use for use DynamicSupervisor" do
      body = parse_module_body("defmodule S do use DynamicSupervisor end")
      assert SupervisorExtractor.detection_method(body) == :use
    end

    test "returns :behaviour for @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      assert SupervisorExtractor.detection_method(body) == :behaviour
    end

    test "returns :behaviour for @behaviour DynamicSupervisor" do
      body = parse_module_body("defmodule S do @behaviour DynamicSupervisor end")
      assert SupervisorExtractor.detection_method(body) == :behaviour
    end

    test "returns nil for non-Supervisor module" do
      body = parse_module_body("defmodule S do use GenServer end")
      assert SupervisorExtractor.detection_method(body) == nil
    end
  end

  # ===========================================================================
  # use_options/1 Tests
  # ===========================================================================

  describe "use_options/1" do
    test "returns options for use Supervisor with options" do
      body = parse_module_body("defmodule S do use Supervisor, strategy: :one_for_one end")
      assert SupervisorExtractor.use_options(body) == [strategy: :one_for_one]
    end

    test "returns empty list for use Supervisor without options" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.use_options(body) == []
    end

    test "returns options for use DynamicSupervisor with options" do
      body = parse_module_body("defmodule S do use DynamicSupervisor, max_children: 50 end")
      assert SupervisorExtractor.use_options(body) == [max_children: 50]
    end

    test "returns nil for @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      assert SupervisorExtractor.use_options(body) == nil
    end

    test "returns nil for non-Supervisor module" do
      body = parse_module_body("defmodule S do use GenServer end")
      assert SupervisorExtractor.use_options(body) == nil
    end
  end

  # ===========================================================================
  # dynamic_supervisor?/1 Tests
  # ===========================================================================

  describe "dynamic_supervisor?/1" do
    test "returns true for use DynamicSupervisor" do
      body = parse_module_body("defmodule S do use DynamicSupervisor end")
      assert SupervisorExtractor.dynamic_supervisor?(body)
    end

    test "returns true for @behaviour DynamicSupervisor" do
      body = parse_module_body("defmodule S do @behaviour DynamicSupervisor end")
      assert SupervisorExtractor.dynamic_supervisor?(body)
    end

    test "returns false for use Supervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")
      refute SupervisorExtractor.dynamic_supervisor?(body)
    end

    test "returns false for @behaviour Supervisor" do
      body = parse_module_body("defmodule S do @behaviour Supervisor end")
      refute SupervisorExtractor.dynamic_supervisor?(body)
    end
  end

  # ===========================================================================
  # otp_behaviour/0 Tests
  # ===========================================================================

  describe "otp_behaviour/0" do
    test "returns :supervisor" do
      assert SupervisorExtractor.otp_behaviour() == :supervisor
    end
  end

  # ===========================================================================
  # Real-World Patterns
  # ===========================================================================

  describe "real-world Supervisor patterns" do
    test "extracts typical Supervisor with init" do
      code = """
      defmodule MySupervisor do
        use Supervisor

        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
        end

        @impl true
        def init(_opts) do
          children = [
            {Worker, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :supervisor
      assert result.detection_method == :use
    end

    test "extracts DynamicSupervisor with custom options" do
      code = """
      defmodule MyDynamicSupervisor do
        use DynamicSupervisor, strategy: :one_for_one, max_children: 100

        def start_link(init_arg) do
          DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        @impl true
        def init(_init_arg) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, result} = SupervisorExtractor.extract(body)

      assert result.supervisor_type == :dynamic_supervisor
      assert result.use_options == [strategy: :one_for_one, max_children: 100]
    end

    test "handles Supervisor with multiple behaviours" do
      code = """
      defmodule MyApp.Application do
        use Application
        use Supervisor

        def start(_type, _args) do
          Supervisor.start_link(__MODULE__, [], name: __MODULE__)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, result} = SupervisorExtractor.extract(body)

      # Should detect Supervisor even with other uses
      assert result.supervisor_type == :supervisor
    end
  end

  # ===========================================================================
  # extract_strategy/1 Tests
  # ===========================================================================

  describe "extract_strategy/1" do
    test "extracts one_for_one strategy from Supervisor.init" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.metadata.source == :supervisor_init
    end

    test "extracts one_for_all strategy" do
      code = """
      defmodule MySup do
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
      defmodule MySup do
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

    test "extracts max_restarts and max_seconds" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.max_restarts == 10
      assert strategy.max_seconds == 60
    end

    test "extracts strategy from DynamicSupervisor.init" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.metadata.source == :dynamic_supervisor_init
    end

    test "returns error when no strategy found" do
      body = parse_module_body("defmodule S do use GenServer end")

      assert {:error, "No supervision strategy found"} =
               SupervisorExtractor.extract_strategy(body)
    end

    test "returns error for supervisor without init callback" do
      body = parse_module_body("defmodule S do use Supervisor end")

      assert {:error, "No supervision strategy found"} =
               SupervisorExtractor.extract_strategy(body)
    end
  end

  # ===========================================================================
  # extract_strategy!/1 Tests
  # ===========================================================================

  describe "extract_strategy!/1" do
    test "returns strategy for valid Supervisor" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      strategy = SupervisorExtractor.extract_strategy!(body)

      assert strategy.type == :one_for_one
    end

    test "raises when no strategy found" do
      body = parse_module_body("defmodule S do use GenServer end")

      assert_raise ArgumentError, "No supervision strategy found", fn ->
        SupervisorExtractor.extract_strategy!(body)
      end
    end
  end

  # ===========================================================================
  # strategy_type/1 Tests (for init callback)
  # ===========================================================================

  describe "strategy_type/1 (from init)" do
    test "returns :one_for_one from init" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      assert SupervisorExtractor.strategy_type(body) == :one_for_one
    end

    test "returns :one_for_all from init" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_all)
        end
      end
      """

      body = parse_module_body(code)
      assert SupervisorExtractor.strategy_type(body) == :one_for_all
    end

    test "returns nil when no init callback" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.strategy_type(body) == nil
    end
  end

  # ===========================================================================
  # Strategy Type Checks
  # ===========================================================================

  describe "one_for_one?/1" do
    test "returns true for one_for_one strategy" do
      assert SupervisorExtractor.one_for_one?(%Strategy{type: :one_for_one})
    end

    test "returns false for other strategies" do
      refute SupervisorExtractor.one_for_one?(%Strategy{type: :one_for_all})
      refute SupervisorExtractor.one_for_one?(%Strategy{type: :rest_for_one})
    end
  end

  describe "one_for_all?/1" do
    test "returns true for one_for_all strategy" do
      assert SupervisorExtractor.one_for_all?(%Strategy{type: :one_for_all})
    end

    test "returns false for other strategies" do
      refute SupervisorExtractor.one_for_all?(%Strategy{type: :one_for_one})
    end
  end

  describe "rest_for_one?/1" do
    test "returns true for rest_for_one strategy" do
      assert SupervisorExtractor.rest_for_one?(%Strategy{type: :rest_for_one})
    end

    test "returns false for other strategies" do
      refute SupervisorExtractor.rest_for_one?(%Strategy{type: :one_for_one})
    end
  end

  # ===========================================================================
  # extract_children/1 Tests
  # ===========================================================================

  describe "extract_children/1" do
    test "extracts children from children variable assignment" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {MyWorker, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      assert hd(children).module == MyWorker
    end

    test "extracts multiple children" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {Worker1, []},
            {Worker2, []},
            {Worker3, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 3
      assert Enum.map(children, & &1.module) == [Worker1, Worker2, Worker3]
    end

    test "extracts children from inline list in Supervisor.init" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([{MyWorker, []}], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      assert hd(children).module == MyWorker
    end

    test "extracts module-only child spec" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            MyWorker
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)
      assert child.module == MyWorker
      assert child.metadata.format == :module_only
    end

    test "returns empty list for non-supervisor" do
      body = parse_module_body("defmodule S do use GenServer end")
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert children == []
    end

    test "returns empty list for supervisor without init" do
      body = parse_module_body("defmodule S do use Supervisor end")
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert children == []
    end
  end

  # ===========================================================================
  # child_count/1 Tests
  # ===========================================================================

  describe "child_count/1" do
    test "returns count of children" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {Worker1, []},
            {Worker2, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      assert SupervisorExtractor.child_count(body) == 2
    end

    test "returns 0 for no children" do
      body = parse_module_body("defmodule S do use Supervisor end")
      assert SupervisorExtractor.child_count(body) == 0
    end
  end

  # ===========================================================================
  # Restart Type Checks
  # ===========================================================================

  describe "permanent?/1" do
    test "returns true for permanent restart" do
      assert SupervisorExtractor.permanent?(%ChildSpec{restart: :permanent})
    end

    test "returns false for other restart types" do
      refute SupervisorExtractor.permanent?(%ChildSpec{restart: :temporary})
      refute SupervisorExtractor.permanent?(%ChildSpec{restart: :transient})
    end
  end

  describe "temporary?/1" do
    test "returns true for temporary restart" do
      assert SupervisorExtractor.temporary?(%ChildSpec{restart: :temporary})
    end

    test "returns false for other restart types" do
      refute SupervisorExtractor.temporary?(%ChildSpec{restart: :permanent})
    end
  end

  describe "transient?/1" do
    test "returns true for transient restart" do
      assert SupervisorExtractor.transient?(%ChildSpec{restart: :transient})
    end

    test "returns false for other restart types" do
      refute SupervisorExtractor.transient?(%ChildSpec{restart: :permanent})
    end
  end

  # ===========================================================================
  # Real-World Strategy Patterns
  # ===========================================================================

  # ===========================================================================
  # Map-Based Child Spec Tests
  # ===========================================================================

  describe "map-based child spec extraction" do
    test "extracts child spec from map format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, [[]]}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)
      assert child.id == :worker
      assert child.module == MyWorker
      assert child.metadata.format == :map
    end

    test "extracts restart option from map child spec" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :temp_worker, start: {TempWorker, :start_link, []}, restart: :temporary}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)
      assert child.restart == :temporary
    end

    test "extracts type from map child spec" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :child_sup, start: {ChildSup, :start_link, []}, type: :supervisor}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)
      assert child.type == :supervisor
    end
  end

  # ===========================================================================
  # extract_children!/2 Tests
  # ===========================================================================

  describe "extract_children!/2" do
    test "returns children for valid supervisor" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{Worker, []}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      children = SupervisorExtractor.extract_children!(body)

      assert is_list(children)
      assert length(children) == 1
    end

    test "returns empty list for supervisor without init" do
      body = parse_module_body("defmodule S do use Supervisor end")
      children = SupervisorExtractor.extract_children!(body)

      assert children == []
    end
  end

  describe "real-world strategy patterns" do
    test "extracts typical Phoenix application supervisor" do
      code = """
      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.Repo,
            {Phoenix.PubSub, name: MyApp.PubSub},
            MyAppWeb.Endpoint
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """

      # This won't have init callback since it uses start_link directly
      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      # No init callback, so no children extracted this way
      assert children == []
    end

    test "extracts supervisor with init callback and children" do
      code = """
      defmodule MySupervisor do
        use Supervisor

        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
        end

        @impl true
        def init(_opts) do
          children = [
            {Registry, keys: :unique, name: MyRegistry},
            {DynamicSupervisor, name: MyDynSup, strategy: :one_for_one}
          ]

          Supervisor.init(children, strategy: :one_for_all)
        end
      end
      """

      body = parse_module_body(code)

      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_all

      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert length(children) == 2
    end

    test "extracts DynamicSupervisor init pattern" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor

        def start_link(init_arg) do
          DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        @impl true
        def init(_init_arg) do
          DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
        end
      end
      """

      body = parse_module_body(code)

      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_one
      assert strategy.metadata.source == :dynamic_supervisor_init
    end
  end

  # ===========================================================================
  # StartSpec and Enhanced ChildSpec Tests
  # ===========================================================================

  describe "StartSpec extraction" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "extracts StartSpec from tuple format child" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{MyWorker, [:arg1, :arg2]}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)

      assert %StartSpec{} = child.start
      assert child.start.module == MyWorker
      assert child.start.function == :start_link
      assert child.start.args == [[:arg1, :arg2]]
      assert child.start.metadata.inferred == true
    end

    test "extracts StartSpec from module-only format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [MyWorker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)

      assert %StartSpec{} = child.start
      assert child.start.module == MyWorker
      assert child.start.function == :start_link
      assert child.start.args == []
      assert child.start.metadata.inferred == true
    end

    test "extracts StartSpec from map format with explicit start" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, [:config]}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)

      assert %StartSpec{} = child.start
      assert child.start.module == MyWorker
      assert child.start.function == :start_link
      assert child.start.args == [:config]
    end

    test "extracts StartSpec with custom start function" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :custom_start, [:arg1, :arg2]}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.function == :custom_start
      assert child.start.args == [:arg1, :arg2]
    end
  end

  describe "modules field extraction" do
    test "modules defaults to [module] for tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{MyWorker, []}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.modules == [MyWorker]
    end

    test "modules defaults to [module] for module-only format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [MyWorker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.modules == [MyWorker]
    end

    test "modules defaults to [module] for map format without explicit modules" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, []}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.modules == [MyWorker]
    end
  end

  describe "legacy tuple format extraction" do
    test "extracts child spec from legacy 6-tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:worker_id, {MyWorker, :start_link, [:arg]}, :permanent, 5000, :worker, [MyWorker]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      assert length(children) == 1
      child = hd(children)

      assert child.id == :worker_id
      assert child.module == MyWorker
      assert child.restart == :permanent
      assert child.shutdown == 5000
      assert child.type == :worker
      assert child.modules == [MyWorker]
      assert child.metadata.format == :legacy_tuple
    end

    test "extracts StartSpec from legacy tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:my_gen, {MyGenServer, :start_link, [:init_arg]}, :transient, :infinity, :worker, [MyGenServer]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.module == MyGenServer
      assert child.start.function == :start_link
      assert child.start.args == [:init_arg]
      assert child.restart == :transient
      assert child.shutdown == :infinity
    end

    test "extracts supervisor child from legacy tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:child_sup, {ChildSupervisor, :start_link, []}, :permanent, :infinity, :supervisor, [ChildSupervisor]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.type == :supervisor
      assert child.shutdown == :infinity
    end
  end

  describe "child spec format metadata" do
    test "tuple format has correct metadata" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{Worker, [:arg]}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.metadata.format == :tuple
      assert child.metadata.has_args == true
    end

    test "module-only format has correct metadata" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [Worker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.metadata.format == :module_only
    end

    test "map format has correct metadata" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [%{id: :w, start: {W, :start_link, []}}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.metadata.format == :map
      assert child.metadata.has_start == true
    end

    test "legacy tuple format has correct metadata" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:id, {W, :start_link, []}, :permanent, 5000, :worker, [W]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.metadata.format == :legacy_tuple
    end
  end

  # ===========================================================================
  # Start Function Arity Tests
  # ===========================================================================

  describe "start_function_arity/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "returns arity from StartSpec struct" do
      spec = %StartSpec{module: MyWorker, function: :start_link, args: [:arg1, :arg2], arity: 2}
      assert SupervisorExtractor.start_function_arity(spec) == 2
    end

    test "returns 0 for empty args" do
      spec = %StartSpec{module: MyWorker, function: :start_link, args: [], arity: 0}
      assert SupervisorExtractor.start_function_arity(spec) == 0
    end

    test "calculates arity from args length when arity is default 0" do
      # When arity is the default 0 but args are present, calculate from args
      spec = %StartSpec{module: MyWorker, function: :start_link, args: [:a, :b, :c], arity: 0}
      assert SupervisorExtractor.start_function_arity(spec) == 3
    end

    test "returns nil for nil input" do
      assert SupervisorExtractor.start_function_arity(nil) == nil
    end
  end

  describe "start_function_mfa/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "returns MFA tuple from StartSpec" do
      spec = %StartSpec{module: MyWorker, function: :start_link, args: [:arg], arity: 1}
      assert SupervisorExtractor.start_function_mfa(spec) == {MyWorker, :start_link, 1}
    end

    test "returns MFA tuple with 0 arity" do
      spec = %StartSpec{module: MyWorker, function: :start_link, args: [], arity: 0}
      assert SupervisorExtractor.start_function_mfa(spec) == {MyWorker, :start_link, 0}
    end

    test "returns nil for nil input" do
      assert SupervisorExtractor.start_function_mfa(nil) == nil
    end

    test "returns nil when module is nil" do
      spec = %StartSpec{module: nil, function: :start_link, args: []}
      assert SupervisorExtractor.start_function_mfa(spec) == nil
    end
  end

  describe "child_start_mfa/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildSpec, StartSpec}

    test "returns MFA from child spec's start field" do
      child = %ChildSpec{
        id: :my_worker,
        start: %StartSpec{module: MyWorker, function: :start_link, args: [:config], arity: 1}
      }

      assert SupervisorExtractor.child_start_mfa(child) == {MyWorker, :start_link, 1}
    end

    test "returns nil when start is nil" do
      child = %ChildSpec{id: :worker, start: nil}
      assert SupervisorExtractor.child_start_mfa(child) == nil
    end
  end

  # ===========================================================================
  # Arity Extraction from Child Specs
  # ===========================================================================

  describe "arity extraction from child specs" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.StartSpec

    test "extracts arity 1 from tuple format child" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{MyWorker, [:arg1]}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.arity == 1
    end

    test "extracts arity 0 from module-only format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [MyWorker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.arity == 0
    end

    test "extracts arity from map format start tuple" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, [:arg1, :arg2]}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.arity == 2
    end

    test "extracts arity from legacy tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:id, {MyWorker, :start_link, [:a, :b, :c]}, :permanent, 5000, :worker, [MyWorker]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert child.start.arity == 3
    end

    test "child_start_mfa returns correct arity for extracted child" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :custom_start, [:config, :opts]}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert SupervisorExtractor.child_start_mfa(child) == {MyWorker, :custom_start, 2}
    end
  end

  # ===========================================================================
  # RestartStrategy Struct Tests
  # ===========================================================================

  describe "RestartStrategy struct" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.RestartStrategy

    test "has default values" do
      strategy = %RestartStrategy{}
      assert strategy.type == :permanent
      assert strategy.is_default == true
      assert strategy.metadata == %{}
    end

    test "can be created with all restart types" do
      assert %RestartStrategy{type: :permanent}.type == :permanent
      assert %RestartStrategy{type: :temporary}.type == :temporary
      assert %RestartStrategy{type: :transient}.type == :transient
    end
  end

  # ===========================================================================
  # extract_restart_strategy/1 Tests
  # ===========================================================================

  describe "extract_restart_strategy/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildSpec, RestartStrategy}

    test "extracts permanent restart from child spec" do
      spec = %ChildSpec{id: :worker, restart: :permanent, metadata: %{format: :map}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert %RestartStrategy{} = strategy
      assert strategy.type == :permanent
    end

    test "extracts temporary restart from child spec" do
      spec = %ChildSpec{id: :worker, restart: :temporary, metadata: %{format: :map}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.type == :temporary
      assert strategy.is_default == false
    end

    test "extracts transient restart from child spec" do
      spec = %ChildSpec{id: :worker, restart: :transient, metadata: %{format: :map}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.type == :transient
      assert strategy.is_default == false
    end

    test "detects default restart for module_only format" do
      spec = %ChildSpec{id: :worker, restart: :permanent, metadata: %{format: :module_only}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.type == :permanent
      assert strategy.is_default == true
    end

    test "detects explicit restart for map format" do
      spec = %ChildSpec{id: :worker, restart: :permanent, metadata: %{format: :map}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.type == :permanent
      # Map format is considered explicit even for :permanent
      assert strategy.is_default == false
    end

    test "detects explicit restart for legacy_tuple format" do
      spec = %ChildSpec{id: :worker, restart: :permanent, metadata: %{format: :legacy_tuple}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.type == :permanent
      assert strategy.is_default == false
    end

    test "includes source format in metadata" do
      spec = %ChildSpec{id: :worker, restart: :temporary, metadata: %{format: :map}}
      strategy = SupervisorExtractor.extract_restart_strategy(spec)

      assert strategy.metadata.source_format == :map
    end
  end

  # ===========================================================================
  # restart_strategy_type/1 Tests
  # ===========================================================================

  describe "restart_strategy_type/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns permanent for permanent restart" do
      assert SupervisorExtractor.restart_strategy_type(%ChildSpec{restart: :permanent}) ==
               :permanent
    end

    test "returns temporary for temporary restart" do
      assert SupervisorExtractor.restart_strategy_type(%ChildSpec{restart: :temporary}) ==
               :temporary
    end

    test "returns transient for transient restart" do
      assert SupervisorExtractor.restart_strategy_type(%ChildSpec{restart: :transient}) ==
               :transient
    end
  end

  # ===========================================================================
  # default_restart?/1 Tests
  # ===========================================================================

  describe "default_restart?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns true for module_only format with permanent restart" do
      spec = %ChildSpec{restart: :permanent, metadata: %{format: :module_only}}
      assert SupervisorExtractor.default_restart?(spec) == true
    end

    test "returns false for map format even with permanent restart" do
      spec = %ChildSpec{restart: :permanent, metadata: %{format: :map}}
      assert SupervisorExtractor.default_restart?(spec) == false
    end

    test "returns false for non-permanent restart" do
      spec = %ChildSpec{restart: :temporary, metadata: %{format: :module_only}}
      assert SupervisorExtractor.default_restart?(spec) == false
    end
  end

  # ===========================================================================
  # restart_description/1 Tests
  # ===========================================================================

  describe "restart_description/1" do
    test "returns description for permanent" do
      assert SupervisorExtractor.restart_description(:permanent) ==
               "Always restart the child process"
    end

    test "returns description for temporary" do
      assert SupervisorExtractor.restart_description(:temporary) ==
               "Never restart the child process"
    end

    test "returns description for transient" do
      assert SupervisorExtractor.restart_description(:transient) ==
               "Restart only if child exits abnormally"
    end
  end

  # ===========================================================================
  # Restart Strategy Extraction from Full Child Specs
  # ===========================================================================

  describe "restart strategy extraction from parsed child specs" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.RestartStrategy

    test "extracts restart from map format child spec" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, []}, restart: :temporary}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      strategy = SupervisorExtractor.extract_restart_strategy(child)

      assert strategy.type == :temporary
      assert strategy.is_default == false
    end

    test "extracts restart from legacy tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:id, {MyWorker, :start_link, []}, :transient, 5000, :worker, [MyWorker]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      strategy = SupervisorExtractor.extract_restart_strategy(child)

      assert strategy.type == :transient
      assert strategy.is_default == false
    end

    test "module-only format has default restart" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [MyWorker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      strategy = SupervisorExtractor.extract_restart_strategy(child)

      assert strategy.type == :permanent
      assert strategy.is_default == true
    end

    test "tuple format has default restart" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [{MyWorker, [:arg]}]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      strategy = SupervisorExtractor.extract_restart_strategy(child)

      assert strategy.type == :permanent
      assert strategy.is_default == true
    end
  end

  # ===========================================================================
  # ShutdownSpec Struct Tests
  # ===========================================================================

  describe "ShutdownSpec struct" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ShutdownSpec

    test "has default values" do
      spec = %ShutdownSpec{}
      assert spec.type == :timeout
      assert spec.value == 5000
      assert spec.is_default == true
      assert spec.metadata == %{}
    end

    test "can be created with all shutdown types" do
      assert %ShutdownSpec{type: :brutal_kill, value: nil}.type == :brutal_kill
      assert %ShutdownSpec{type: :infinity, value: nil}.type == :infinity
      assert %ShutdownSpec{type: :timeout, value: 10_000}.type == :timeout
    end
  end

  # ===========================================================================
  # extract_shutdown/1 Tests
  # ===========================================================================

  describe "extract_shutdown/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildSpec, ShutdownSpec}

    test "extracts timeout shutdown" do
      spec = %ChildSpec{id: :worker, shutdown: 5000, metadata: %{format: :map}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert %ShutdownSpec{} = shutdown
      assert shutdown.type == :timeout
      assert shutdown.value == 5000
      assert shutdown.is_default == false
    end

    test "extracts brutal_kill shutdown" do
      spec = %ChildSpec{id: :worker, shutdown: :brutal_kill, metadata: %{format: :map}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert shutdown.type == :brutal_kill
      assert shutdown.value == nil
      assert shutdown.is_default == false
    end

    test "extracts infinity shutdown" do
      spec = %ChildSpec{id: :supervisor, shutdown: :infinity, metadata: %{format: :map}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert shutdown.type == :infinity
      assert shutdown.value == nil
      assert shutdown.is_default == false
    end

    test "defaults to 5000ms timeout for workers" do
      spec = %ChildSpec{id: :worker, shutdown: nil, type: :worker, metadata: %{format: :tuple}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert shutdown.type == :timeout
      assert shutdown.value == 5000
      assert shutdown.is_default == true
    end

    test "defaults to infinity for supervisors" do
      spec = %ChildSpec{id: :sup, shutdown: nil, type: :supervisor, metadata: %{format: :map}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert shutdown.type == :infinity
      assert shutdown.value == nil
      assert shutdown.is_default == true
    end

    test "includes child type in metadata" do
      spec = %ChildSpec{id: :worker, shutdown: 5000, type: :worker, metadata: %{format: :map}}
      shutdown = SupervisorExtractor.extract_shutdown(spec)

      assert shutdown.metadata.child_type == :worker
    end
  end

  # ===========================================================================
  # shutdown_timeout/1 Tests
  # ===========================================================================

  describe "shutdown_timeout/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns timeout value" do
      spec = %ChildSpec{shutdown: 10_000}
      assert SupervisorExtractor.shutdown_timeout(spec) == 10_000
    end

    test "returns nil for infinity" do
      spec = %ChildSpec{shutdown: :infinity}
      assert SupervisorExtractor.shutdown_timeout(spec) == nil
    end

    test "returns nil for brutal_kill" do
      spec = %ChildSpec{shutdown: :brutal_kill}
      assert SupervisorExtractor.shutdown_timeout(spec) == nil
    end

    test "returns default 5000 for worker with nil shutdown" do
      spec = %ChildSpec{shutdown: nil, type: :worker}
      assert SupervisorExtractor.shutdown_timeout(spec) == 5000
    end
  end

  # ===========================================================================
  # shutdown_description/1 Tests
  # ===========================================================================

  describe "shutdown_description/1" do
    test "returns description for brutal_kill" do
      assert SupervisorExtractor.shutdown_description(:brutal_kill) == "Kill immediately"
    end

    test "returns description for infinity" do
      assert SupervisorExtractor.shutdown_description(:infinity) == "Wait indefinitely"
    end

    test "returns description for timeout" do
      assert SupervisorExtractor.shutdown_description(5000) == "Wait up to 5000ms"
      assert SupervisorExtractor.shutdown_description(10_000) == "Wait up to 10000ms"
    end
  end

  # ===========================================================================
  # Child Type Tests
  # ===========================================================================

  describe "worker?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns true for worker type" do
      assert SupervisorExtractor.worker?(%ChildSpec{type: :worker}) == true
    end

    test "returns false for supervisor type" do
      assert SupervisorExtractor.worker?(%ChildSpec{type: :supervisor}) == false
    end
  end

  describe "supervisor_child?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns true for supervisor type" do
      assert SupervisorExtractor.supervisor_child?(%ChildSpec{type: :supervisor}) == true
    end

    test "returns false for worker type" do
      assert SupervisorExtractor.supervisor_child?(%ChildSpec{type: :worker}) == false
    end
  end

  describe "child_type/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

    test "returns worker type" do
      assert SupervisorExtractor.child_type(%ChildSpec{type: :worker}) == :worker
    end

    test "returns supervisor type" do
      assert SupervisorExtractor.child_type(%ChildSpec{type: :supervisor}) == :supervisor
    end
  end

  describe "child_type_description/1" do
    test "returns description for worker" do
      assert SupervisorExtractor.child_type_description(:worker) == "Worker process"
    end

    test "returns description for supervisor" do
      assert SupervisorExtractor.child_type_description(:supervisor) == "Supervisor process"
    end
  end

  # ===========================================================================
  # Shutdown Extraction from Full Child Specs
  # ===========================================================================

  # ===========================================================================
  # Strategy Struct Enhanced Tests
  # ===========================================================================

  describe "Strategy struct enhanced fields" do
    test "has is_default_max_restarts field" do
      strategy = %Strategy{}
      assert strategy.is_default_max_restarts == true
    end

    test "has is_default_max_seconds field" do
      strategy = %Strategy{}
      assert strategy.is_default_max_seconds == true
    end

    test "can create with explicit max_restarts/max_seconds" do
      strategy = %Strategy{
        type: :one_for_all,
        max_restarts: 10,
        max_seconds: 60,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      assert strategy.max_restarts == 10
      assert strategy.max_seconds == 60
      assert strategy.is_default_max_restarts == false
      assert strategy.is_default_max_seconds == false
    end
  end

  # ===========================================================================
  # extract_supervision_strategy/1 Tests
  # ===========================================================================

  describe "extract_supervision_strategy/1" do
    test "is an alias for extract_strategy/1" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy1} = SupervisorExtractor.extract_strategy(body)
      {:ok, strategy2} = SupervisorExtractor.extract_supervision_strategy(body)

      assert strategy1.type == strategy2.type
      assert strategy1.max_restarts == strategy2.max_restarts
      assert strategy1.max_seconds == strategy2.max_seconds
    end

    test "extracts all strategy types" do
      for strategy_type <- [:one_for_one, :one_for_all, :rest_for_one] do
        code = """
        defmodule MySup do
          use Supervisor
          def init(_) do
            Supervisor.init([], strategy: #{inspect(strategy_type)})
          end
        end
        """

        body = parse_module_body(code)
        {:ok, strategy} = SupervisorExtractor.extract_supervision_strategy(body)

        assert strategy.type == strategy_type
      end
    end
  end

  # ===========================================================================
  # strategy_description/1 Tests
  # ===========================================================================

  describe "strategy_description/1" do
    test "returns description for one_for_one" do
      assert SupervisorExtractor.strategy_description(:one_for_one) ==
               "Only restart the failed child"
    end

    test "returns description for one_for_all" do
      assert SupervisorExtractor.strategy_description(:one_for_all) ==
               "Restart all children on any failure"
    end

    test "returns description for rest_for_one" do
      assert SupervisorExtractor.strategy_description(:rest_for_one) ==
               "Restart failed child and all started after it"
    end
  end

  # ===========================================================================
  # default_max_restarts?/1 and default_max_seconds?/1 Tests
  # ===========================================================================

  describe "default_max_restarts?/1" do
    test "returns true when is_default_max_restarts is true" do
      strategy = %Strategy{is_default_max_restarts: true}
      assert SupervisorExtractor.default_max_restarts?(strategy) == true
    end

    test "returns false when is_default_max_restarts is false" do
      strategy = %Strategy{max_restarts: 10, is_default_max_restarts: false}
      assert SupervisorExtractor.default_max_restarts?(strategy) == false
    end
  end

  describe "default_max_seconds?/1" do
    test "returns true when is_default_max_seconds is true" do
      strategy = %Strategy{is_default_max_seconds: true}
      assert SupervisorExtractor.default_max_seconds?(strategy) == true
    end

    test "returns false when is_default_max_seconds is false" do
      strategy = %Strategy{max_seconds: 60, is_default_max_seconds: false}
      assert SupervisorExtractor.default_max_seconds?(strategy) == false
    end
  end

  # ===========================================================================
  # effective_max_restarts/1 and effective_max_seconds/1 Tests
  # ===========================================================================

  describe "effective_max_restarts/1" do
    test "returns explicit value when set" do
      strategy = %Strategy{max_restarts: 10}
      assert SupervisorExtractor.effective_max_restarts(strategy) == 10
    end

    test "returns OTP default 3 when nil" do
      strategy = %Strategy{max_restarts: nil}
      assert SupervisorExtractor.effective_max_restarts(strategy) == 3
    end
  end

  describe "effective_max_seconds/1" do
    test "returns explicit value when set" do
      strategy = %Strategy{max_seconds: 60}
      assert SupervisorExtractor.effective_max_seconds(strategy) == 60
    end

    test "returns OTP default 5 when nil" do
      strategy = %Strategy{max_seconds: nil}
      assert SupervisorExtractor.effective_max_seconds(strategy) == 5
    end
  end

  # ===========================================================================
  # restart_intensity/1 Tests
  # ===========================================================================

  describe "restart_intensity/1" do
    test "calculates intensity from explicit values" do
      strategy = %Strategy{max_restarts: 3, max_seconds: 5}
      assert SupervisorExtractor.restart_intensity(strategy) == 0.6
    end

    test "calculates intensity using defaults" do
      strategy = %Strategy{max_restarts: nil, max_seconds: nil}
      assert SupervisorExtractor.restart_intensity(strategy) == 0.6
    end

    test "calculates intensity with custom values" do
      strategy = %Strategy{max_restarts: 10, max_seconds: 5}
      assert SupervisorExtractor.restart_intensity(strategy) == 2.0
    end

    test "calculates intensity with larger time window" do
      strategy = %Strategy{max_restarts: 3, max_seconds: 60}
      assert SupervisorExtractor.restart_intensity(strategy) == 0.05
    end
  end

  # ===========================================================================
  # Strategy Extraction with Default Detection
  # ===========================================================================

  describe "strategy extraction with default detection" do
    test "marks max_restarts as default when not specified" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_restarts == nil
      assert strategy.is_default_max_restarts == true
    end

    test "marks max_seconds as default when not specified" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_seconds == nil
      assert strategy.is_default_max_seconds == true
    end

    test "marks max_restarts as non-default when specified" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_restarts: 10)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_restarts == 10
      assert strategy.is_default_max_restarts == false
    end

    test "marks max_seconds as non-default when specified" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_seconds: 60)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_seconds == 60
      assert strategy.is_default_max_seconds == false
    end

    test "marks both as non-default when both specified" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_restarts == 10
      assert strategy.max_seconds == 60
      assert strategy.is_default_max_restarts == false
      assert strategy.is_default_max_seconds == false
    end
  end

  # ===========================================================================
  # Strategy Extraction from DynamicSupervisor
  # ===========================================================================

  describe "DynamicSupervisor strategy extraction" do
    test "extracts strategy from DynamicSupervisor.init" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_supervision_strategy(body)

      assert strategy.type == :one_for_one
      assert strategy.metadata.source == :dynamic_supervisor_init
    end

    test "extracts max_restarts from DynamicSupervisor.init" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 5)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert strategy.max_restarts == 5
      assert strategy.is_default_max_restarts == false
    end
  end

  describe "shutdown extraction from parsed child specs" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ShutdownSpec

    test "extracts shutdown from map format child spec" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :worker, start: {MyWorker, :start_link, []}, shutdown: 10000}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      shutdown = SupervisorExtractor.extract_shutdown(child)

      assert shutdown.type == :timeout
      assert shutdown.value == 10_000
      assert shutdown.is_default == false
    end

    test "extracts shutdown from legacy tuple format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {:id, {MyWorker, :start_link, []}, :permanent, :infinity, :supervisor, [MyWorker]}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      shutdown = SupervisorExtractor.extract_shutdown(child)

      assert shutdown.type == :infinity
      assert shutdown.value == nil
    end

    test "module-only format has default shutdown for worker" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [MyWorker]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      shutdown = SupervisorExtractor.extract_shutdown(child)

      assert shutdown.type == :timeout
      assert shutdown.value == 5000
      assert shutdown.is_default == true
    end

    test "extracts type: :supervisor from map format" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :child_sup, start: {ChildSup, :start_link, []}, type: :supervisor}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, children} = SupervisorExtractor.extract_children(body)

      child = hd(children)
      assert SupervisorExtractor.supervisor_child?(child)
      assert SupervisorExtractor.child_type(child) == :supervisor
    end
  end

  # ===========================================================================
  # RestartIntensity Struct Tests
  # ===========================================================================

  describe "RestartIntensity struct" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.RestartIntensity

    test "has OTP default values" do
      intensity = %RestartIntensity{}
      assert intensity.max_restarts == 3
      assert intensity.max_seconds == 5
      assert intensity.intensity == 0.6
      assert intensity.is_default_max_restarts == true
      assert intensity.is_default_max_seconds == true
    end

    test "can be created with custom values" do
      intensity = %RestartIntensity{
        max_restarts: 10,
        max_seconds: 60,
        intensity: 0.16666666666666666,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      assert intensity.max_restarts == 10
      assert intensity.max_seconds == 60
      assert_in_delta intensity.intensity, 0.167, 0.01
    end
  end

  # ===========================================================================
  # extract_restart_intensity/1 Tests
  # ===========================================================================

  describe "extract_restart_intensity/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.RestartIntensity

    test "extracts intensity from strategy with explicit values" do
      strategy = %Strategy{
        type: :one_for_one,
        max_restarts: 10,
        max_seconds: 60,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert %RestartIntensity{} = intensity
      assert intensity.max_restarts == 10
      assert intensity.max_seconds == 60
      assert_in_delta intensity.intensity, 0.167, 0.01
      assert intensity.is_default_max_restarts == false
      assert intensity.is_default_max_seconds == false
    end

    test "extracts intensity from strategy with default values" do
      strategy = %Strategy{}

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.max_restarts == 3
      assert intensity.max_seconds == 5
      assert intensity.intensity == 0.6
      assert intensity.is_default_max_restarts == true
      assert intensity.is_default_max_seconds == true
    end

    test "includes source strategy type in metadata" do
      strategy = %Strategy{type: :one_for_all}

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.metadata.source_strategy == :one_for_all
    end

    test "handles nil max_restarts and max_seconds" do
      strategy = %Strategy{max_restarts: nil, max_seconds: nil}

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.max_restarts == 3
      assert intensity.max_seconds == 5
      assert intensity.intensity == 0.6
    end
  end

  # ===========================================================================
  # restart_intensity_description/1 Tests
  # ===========================================================================

  describe "restart_intensity_description/1" do
    test "returns description for explicit values" do
      strategy = %Strategy{
        max_restarts: 3,
        max_seconds: 5,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      desc = SupervisorExtractor.restart_intensity_description(strategy)

      assert desc == "3 restarts in 5 seconds (0.6/sec)"
    end

    test "returns description with [defaults] marker for default values" do
      strategy = %Strategy{}

      desc = SupervisorExtractor.restart_intensity_description(strategy)

      assert desc == "3 restarts in 5 seconds (0.6/sec) [defaults]"
    end

    test "returns description for custom high intensity" do
      strategy = %Strategy{
        max_restarts: 100,
        max_seconds: 10,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      desc = SupervisorExtractor.restart_intensity_description(strategy)

      assert desc == "100 restarts in 10 seconds (10.0/sec)"
    end

    test "does not add defaults marker when only one is default" do
      strategy = %Strategy{
        max_restarts: 10,
        is_default_max_restarts: false,
        is_default_max_seconds: true
      }

      desc = SupervisorExtractor.restart_intensity_description(strategy)

      refute String.contains?(desc, "[defaults]")
    end
  end

  # ===========================================================================
  # high_restart_intensity?/1 Tests
  # ===========================================================================

  describe "high_restart_intensity?/1" do
    test "returns false for default intensity" do
      strategy = %Strategy{}
      refute SupervisorExtractor.high_restart_intensity?(strategy)
    end

    test "returns false for intensity at exactly 1.0" do
      strategy = %Strategy{max_restarts: 5, max_seconds: 5}
      refute SupervisorExtractor.high_restart_intensity?(strategy)
    end

    test "returns true for intensity above 1.0" do
      strategy = %Strategy{max_restarts: 10, max_seconds: 5}
      assert SupervisorExtractor.high_restart_intensity?(strategy)
    end

    test "returns true for very high intensity" do
      strategy = %Strategy{max_restarts: 100, max_seconds: 10}
      assert SupervisorExtractor.high_restart_intensity?(strategy)
    end
  end

  # ===========================================================================
  # within_default_intensity?/1 Tests
  # ===========================================================================

  describe "within_default_intensity?/1" do
    test "returns true when both defaults" do
      strategy = %Strategy{is_default_max_restarts: true, is_default_max_seconds: true}
      assert SupervisorExtractor.within_default_intensity?(strategy)
    end

    test "returns false when max_restarts is not default" do
      strategy = %Strategy{
        max_restarts: 10,
        is_default_max_restarts: false,
        is_default_max_seconds: true
      }

      refute SupervisorExtractor.within_default_intensity?(strategy)
    end

    test "returns false when max_seconds is not default" do
      strategy = %Strategy{
        max_seconds: 60,
        is_default_max_restarts: true,
        is_default_max_seconds: false
      }

      refute SupervisorExtractor.within_default_intensity?(strategy)
    end

    test "returns false when neither is default" do
      strategy = %Strategy{
        max_restarts: 10,
        max_seconds: 60,
        is_default_max_restarts: false,
        is_default_max_seconds: false
      }

      refute SupervisorExtractor.within_default_intensity?(strategy)
    end
  end

  # ===========================================================================
  # Restart Intensity from Extracted Strategies
  # ===========================================================================

  describe "restart intensity from extracted strategies" do
    test "extracts intensity from supervisor with custom restart settings" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.max_restarts == 10
      assert intensity.max_seconds == 60
      assert_in_delta intensity.intensity, 0.167, 0.01
      assert intensity.is_default_max_restarts == false
      assert intensity.is_default_max_seconds == false
    end

    test "extracts intensity from supervisor with default settings" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.max_restarts == 3
      assert intensity.max_seconds == 5
      assert intensity.intensity == 0.6
      assert intensity.is_default_max_restarts == true
      assert intensity.is_default_max_seconds == true
    end

    test "extracts intensity from DynamicSupervisor" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 5, max_seconds: 10)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      intensity = SupervisorExtractor.extract_restart_intensity(strategy)

      assert intensity.max_restarts == 5
      assert intensity.max_seconds == 10
      assert intensity.intensity == 0.5
    end

    test "correctly identifies high restart intensity in extracted strategy" do
      code = """
      defmodule AggressiveSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one, max_restarts: 100, max_seconds: 10)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)

      assert SupervisorExtractor.high_restart_intensity?(strategy)
      assert SupervisorExtractor.restart_intensity(strategy) == 10.0
    end
  end

  # ===========================================================================
  # DynamicSupervisorConfig Struct Tests
  # ===========================================================================

  describe "DynamicSupervisorConfig struct" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "has default values" do
      config = %DynamicSupervisorConfig{}
      assert config.strategy == :one_for_one
      assert config.extra_arguments == []
      assert config.max_children == :infinity
      assert config.is_dynamic == true
    end

    test "can be created with custom values" do
      config = %DynamicSupervisorConfig{
        max_children: 100,
        extra_arguments: [:config],
        max_restarts: 5,
        max_seconds: 10
      }

      assert config.max_children == 100
      assert config.extra_arguments == [:config]
      assert config.max_restarts == 5
      assert config.max_seconds == 10
    end
  end

  # ===========================================================================
  # extract_dynamic_supervisor_config/1 Tests
  # ===========================================================================

  describe "extract_dynamic_supervisor_config/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "extracts config from basic DynamicSupervisor" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert %DynamicSupervisorConfig{} = config
      assert config.strategy == :one_for_one
      assert config.is_dynamic == true
      assert config.max_children == :infinity
    end

    test "extracts max_children option" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert config.max_children == 100
      assert config.metadata.has_max_children == true
    end

    test "extracts extra_arguments option" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [:config])
        end
      end
      """

      body = parse_module_body(code)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert config.extra_arguments == [:config]
      assert config.metadata.has_extra_arguments == true
    end

    test "extracts max_restarts and max_seconds" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert config.max_restarts == 10
      assert config.max_seconds == 60
    end

    test "returns error for non-DynamicSupervisor" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      result = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert {:error, "Module is not a DynamicSupervisor"} = result
    end

    test "extracts config with all options" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(
            strategy: :one_for_one,
            max_children: 50,
            extra_arguments: [:opts],
            max_restarts: 3,
            max_seconds: 5
          )
        end
      end
      """

      body = parse_module_body(code)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)

      assert config.strategy == :one_for_one
      assert config.max_children == 50
      assert config.extra_arguments == [:opts]
      assert config.max_restarts == 3
      assert config.max_seconds == 5
      assert config.is_dynamic == true
    end
  end

  # ===========================================================================
  # extract_dynamic_supervisor_config!/1 Tests
  # ===========================================================================

  describe "extract_dynamic_supervisor_config!/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "returns config for valid DynamicSupervisor" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      config = SupervisorExtractor.extract_dynamic_supervisor_config!(body)

      assert %DynamicSupervisorConfig{} = config
    end

    test "raises for non-DynamicSupervisor" do
      body = parse_module_body("defmodule S do use Supervisor end")

      assert_raise ArgumentError, "Module is not a DynamicSupervisor", fn ->
        SupervisorExtractor.extract_dynamic_supervisor_config!(body)
      end
    end
  end

  # ===========================================================================
  # max_children/1 Tests
  # ===========================================================================

  describe "max_children/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "returns infinity by default" do
      config = %DynamicSupervisorConfig{}
      assert SupervisorExtractor.max_children(config) == :infinity
    end

    test "returns explicit value" do
      config = %DynamicSupervisorConfig{max_children: 100}
      assert SupervisorExtractor.max_children(config) == 100
    end
  end

  # ===========================================================================
  # has_extra_arguments?/1 Tests
  # ===========================================================================

  describe "has_extra_arguments?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "returns false for empty extra_arguments" do
      config = %DynamicSupervisorConfig{}
      refute SupervisorExtractor.has_extra_arguments?(config)
    end

    test "returns true for non-empty extra_arguments" do
      config = %DynamicSupervisorConfig{extra_arguments: [:config]}
      assert SupervisorExtractor.has_extra_arguments?(config)
    end

    test "returns true for multiple extra_arguments" do
      config = %DynamicSupervisorConfig{extra_arguments: [:config, :opts]}
      assert SupervisorExtractor.has_extra_arguments?(config)
    end
  end

  # ===========================================================================
  # unlimited_children?/1 Tests
  # ===========================================================================

  describe "unlimited_children?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "returns true for infinity" do
      config = %DynamicSupervisorConfig{max_children: :infinity}
      assert SupervisorExtractor.unlimited_children?(config)
    end

    test "returns false for explicit limit" do
      config = %DynamicSupervisorConfig{max_children: 100}
      refute SupervisorExtractor.unlimited_children?(config)
    end

    test "returns false for zero" do
      config = %DynamicSupervisorConfig{max_children: 0}
      refute SupervisorExtractor.unlimited_children?(config)
    end
  end

  # ===========================================================================
  # dynamic_supervisor_description/1 Tests
  # ===========================================================================

  describe "dynamic_supervisor_description/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.DynamicSupervisorConfig

    test "returns description for unlimited children" do
      config = %DynamicSupervisorConfig{max_children: :infinity}

      assert SupervisorExtractor.dynamic_supervisor_description(config) ==
               "DynamicSupervisor with unlimited children"
    end

    test "returns description for limited children" do
      config = %DynamicSupervisorConfig{max_children: 100}

      assert SupervisorExtractor.dynamic_supervisor_description(config) ==
               "DynamicSupervisor with max 100 children"
    end
  end

  # ===========================================================================
  # DynamicSupervisor Integration Tests
  # ===========================================================================

  describe "DynamicSupervisor integration" do
    test "extracts config from real-world pattern" do
      code = """
      defmodule MyApp.WorkerSupervisor do
        use DynamicSupervisor

        def start_link(init_arg) do
          DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        @impl true
        def init(_init_arg) do
          DynamicSupervisor.init(
            strategy: :one_for_one,
            max_children: 500,
            max_restarts: 100,
            max_seconds: 60
          )
        end

        def start_worker(args) do
          DynamicSupervisor.start_child(__MODULE__, {MyApp.Worker, args})
        end
      end
      """

      body = parse_module_body(code)

      # Should be detected as DynamicSupervisor
      assert SupervisorExtractor.dynamic_supervisor?(body)

      # Should extract config
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)
      assert config.max_children == 500
      assert config.max_restarts == 100
      assert config.max_seconds == 60
      assert config.is_dynamic == true
    end

    test "DynamicSupervisor with @behaviour annotation" do
      code = """
      defmodule MyDynSup do
        @behaviour DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)

      assert SupervisorExtractor.dynamic_supervisor?(body)
      {:ok, config} = SupervisorExtractor.extract_dynamic_supervisor_config(body)
      assert config.is_dynamic == true
    end
  end

  # ===========================================================================
  # ChildOrder Struct Tests
  # ===========================================================================

  describe "ChildOrder struct" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "has default values" do
      order = %ChildOrder{}
      assert order.position == 0
      assert order.child_spec == nil
      assert order.id == nil
      assert order.is_dynamic == false
      assert order.metadata == %{}
    end

    test "can be created with custom values" do
      order = %ChildOrder{
        position: 2,
        id: :my_worker,
        is_dynamic: true,
        metadata: %{total_children: 5}
      }

      assert order.position == 2
      assert order.id == :my_worker
      assert order.is_dynamic == true
      assert order.metadata.total_children == 5
    end
  end

  # ===========================================================================
  # extract_ordered_children/1 Tests
  # ===========================================================================

  describe "extract_ordered_children/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "extracts ordered children with positions" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {Worker1, []},
            {Worker2, []},
            {Worker3, []}
          ]
          Supervisor.init(children, strategy: :rest_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      assert length(ordered) == 3
      assert Enum.all?(ordered, fn o -> %ChildOrder{} = o end)

      [first, second, third] = ordered
      assert first.position == 0
      assert second.position == 1
      assert third.position == 2
    end

    test "preserves original definition order" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            %{id: :alpha, start: {A, :start_link, []}},
            %{id: :beta, start: {B, :start_link, []}},
            %{id: :gamma, start: {C, :start_link, []}}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      ids = Enum.map(ordered, & &1.id)
      assert ids == [:alpha, :beta, :gamma]
    end

    test "includes child spec in each order" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([{Worker, []}], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, [order]} = SupervisorExtractor.extract_ordered_children(body)

      assert order.child_spec != nil
      assert order.child_spec.id == Worker
    end

    test "includes metadata about position" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([{A, []}, {B, []}, {C, []}], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      [first, second, third] = ordered

      assert first.metadata.is_first == true
      assert first.metadata.is_last == false
      assert first.metadata.total_children == 3

      assert second.metadata.is_first == false
      assert second.metadata.is_last == false

      assert third.metadata.is_first == false
      assert third.metadata.is_last == true
    end

    test "marks DynamicSupervisor children as dynamic" do
      code = """
      defmodule MyDynSup do
        use DynamicSupervisor
        def init(_) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      # DynamicSupervisor has no static children, but the is_dynamic flag
      # would be set if there were any
      assert ordered == []
    end

    test "returns empty list for supervisor with no children" do
      code = """
      defmodule EmptySup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      assert ordered == []
    end
  end

  # ===========================================================================
  # extract_ordered_children!/1 Tests
  # ===========================================================================

  describe "extract_ordered_children!/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns ordered children directly" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          Supervisor.init([{Worker, []}], strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      ordered = SupervisorExtractor.extract_ordered_children!(body)

      assert [%ChildOrder{}] = ordered
    end
  end

  # ===========================================================================
  # child_at_position/2 Tests
  # ===========================================================================

  describe "child_at_position/2" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns child at specified position" do
      ordered = [
        %ChildOrder{position: 0, id: :first},
        %ChildOrder{position: 1, id: :second},
        %ChildOrder{position: 2, id: :third}
      ]

      assert SupervisorExtractor.child_at_position(ordered, 0).id == :first
      assert SupervisorExtractor.child_at_position(ordered, 1).id == :second
      assert SupervisorExtractor.child_at_position(ordered, 2).id == :third
    end

    test "returns nil for non-existent position" do
      ordered = [%ChildOrder{position: 0, id: :only}]

      assert SupervisorExtractor.child_at_position(ordered, 5) == nil
    end

    test "returns nil for empty list" do
      assert SupervisorExtractor.child_at_position([], 0) == nil
    end
  end

  # ===========================================================================
  # ordered_child_count/1 Tests
  # ===========================================================================

  describe "ordered_child_count/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns count of ordered children" do
      ordered = [
        %ChildOrder{position: 0},
        %ChildOrder{position: 1},
        %ChildOrder{position: 2}
      ]

      assert SupervisorExtractor.ordered_child_count(ordered) == 3
    end

    test "returns 0 for empty list" do
      assert SupervisorExtractor.ordered_child_count([]) == 0
    end
  end

  # ===========================================================================
  # first_child/1 and last_child/1 Tests
  # ===========================================================================

  describe "first_child/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns first child" do
      ordered = [
        %ChildOrder{position: 0, id: :first},
        %ChildOrder{position: 1, id: :second}
      ]

      assert SupervisorExtractor.first_child(ordered).id == :first
    end

    test "returns nil for empty list" do
      assert SupervisorExtractor.first_child([]) == nil
    end
  end

  describe "last_child/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns last child" do
      ordered = [
        %ChildOrder{position: 0, id: :first},
        %ChildOrder{position: 1, id: :last}
      ]

      assert SupervisorExtractor.last_child(ordered).id == :last
    end

    test "returns nil for empty list" do
      assert SupervisorExtractor.last_child([]) == nil
    end
  end

  # ===========================================================================
  # children_after/2 and children_before/2 Tests
  # ===========================================================================

  describe "children_after/2" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns children after position" do
      ordered = [
        %ChildOrder{position: 0, id: :a},
        %ChildOrder{position: 1, id: :b},
        %ChildOrder{position: 2, id: :c},
        %ChildOrder{position: 3, id: :d}
      ]

      after_b = SupervisorExtractor.children_after(ordered, 1)
      ids = Enum.map(after_b, & &1.id)

      assert ids == [:c, :d]
    end

    test "returns empty list when no children after" do
      ordered = [%ChildOrder{position: 0, id: :only}]

      assert SupervisorExtractor.children_after(ordered, 0) == []
    end

    test "returns all children when position is -1" do
      ordered = [
        %ChildOrder{position: 0, id: :a},
        %ChildOrder{position: 1, id: :b}
      ]

      after_none = SupervisorExtractor.children_after(ordered, -1)
      assert length(after_none) == 2
    end
  end

  describe "children_before/2" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns children before position" do
      ordered = [
        %ChildOrder{position: 0, id: :a},
        %ChildOrder{position: 1, id: :b},
        %ChildOrder{position: 2, id: :c}
      ]

      before_c = SupervisorExtractor.children_before(ordered, 2)
      ids = Enum.map(before_c, & &1.id)

      assert ids == [:a, :b]
    end

    test "returns empty list when no children before" do
      ordered = [%ChildOrder{position: 0, id: :first}]

      assert SupervisorExtractor.children_before(ordered, 0) == []
    end
  end

  # ===========================================================================
  # is_ordered?/1 Tests
  # ===========================================================================

  describe "is_ordered?/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns true for sequential positions" do
      ordered = [
        %ChildOrder{position: 0},
        %ChildOrder{position: 1},
        %ChildOrder{position: 2}
      ]

      assert SupervisorExtractor.is_ordered?(ordered)
    end

    test "returns true for empty list" do
      assert SupervisorExtractor.is_ordered?([])
    end

    test "returns true for single element" do
      ordered = [%ChildOrder{position: 0}]
      assert SupervisorExtractor.is_ordered?(ordered)
    end

    test "returns false for non-sequential positions" do
      ordered = [
        %ChildOrder{position: 0},
        %ChildOrder{position: 5}
      ]

      refute SupervisorExtractor.is_ordered?(ordered)
    end

    test "returns false for out of order positions" do
      ordered = [
        %ChildOrder{position: 1},
        %ChildOrder{position: 0}
      ]

      refute SupervisorExtractor.is_ordered?(ordered)
    end
  end

  # ===========================================================================
  # ordering_description/1 Tests
  # ===========================================================================

  describe "ordering_description/1" do
    alias ElixirOntologies.Extractors.OTP.Supervisor.ChildOrder

    test "returns description for children" do
      ordered = [
        %ChildOrder{position: 0, id: :worker_a},
        %ChildOrder{position: 1, id: :worker_b}
      ]

      desc = SupervisorExtractor.ordering_description(ordered)
      assert desc == "2 children in order: worker_a -> worker_b"
    end

    test "returns 'No children' for empty list" do
      assert SupervisorExtractor.ordering_description([]) == "No children"
    end

    test "handles single child" do
      ordered = [%ChildOrder{position: 0, id: :only}]

      desc = SupervisorExtractor.ordering_description(ordered)
      assert desc == "1 children in order: only"
    end
  end

  # ===========================================================================
  # Child Ordering Integration Tests
  # ===========================================================================

  describe "child ordering integration" do
    test "works with rest_for_one strategy analysis" do
      code = """
      defmodule MySup do
        use Supervisor
        def init(_) do
          children = [
            {Database, []},
            {Cache, []},
            {WebServer, []}
          ]
          Supervisor.init(children, strategy: :rest_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      # If Cache (position 1) fails, WebServer (position 2) would also restart
      cache_position = 1
      affected = SupervisorExtractor.children_after(ordered, cache_position)

      assert length(affected) == 1
      assert hd(affected).id == WebServer
    end

    test "extracts ordering from complex supervisor" do
      code = """
      defmodule ComplexSup do
        use Supervisor

        def init(_) do
          children = [
            %{id: :registry, start: {Registry, :start_link, [[keys: :unique, name: MyRegistry]]}},
            {DynamicSupervisor, name: WorkerSupervisor, strategy: :one_for_one},
            %{id: :scheduler, start: {Scheduler, :start_link, []}, restart: :transient}
          ]

          Supervisor.init(children, strategy: :one_for_all, max_restarts: 3, max_seconds: 5)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)

      assert SupervisorExtractor.ordered_child_count(ordered) == 3
      assert SupervisorExtractor.is_ordered?(ordered)

      first = SupervisorExtractor.first_child(ordered)
      last = SupervisorExtractor.last_child(ordered)

      assert first.id == :registry
      assert last.id == :scheduler
    end
  end

  # ===========================================================================
  # Nested Supervisor Detection Tests
  # ===========================================================================

  describe "NestedSupervisor struct" do
    test "has expected default values" do
      ns = %NestedSupervisor{}
      assert ns.child_spec == nil
      assert ns.module == nil
      assert ns.position == 0
      assert ns.detection_method == :explicit_type
      assert ns.is_confirmed == true
      assert ns.metadata == %{}
    end

    test "can be constructed with custom values" do
      spec = %ChildSpec{id: :sub_sup, type: :supervisor, module: MySupervisor}

      ns = %NestedSupervisor{
        child_spec: spec,
        module: MySupervisor,
        position: 2,
        detection_method: :name_heuristic,
        is_confirmed: false,
        metadata: %{reason: "test"}
      }

      assert ns.module == MySupervisor
      assert ns.position == 2
      assert ns.detection_method == :name_heuristic
      assert ns.is_confirmed == false
    end
  end

  describe "nested_supervisor?/1" do
    test "returns true for explicit type: :supervisor" do
      child = %ChildOrder{
        position: 0,
        id: :sub_sup,
        child_spec: %ChildSpec{type: :supervisor, module: MySup}
      }

      assert SupervisorExtractor.nested_supervisor?(child)
    end

    test "returns true for module name ending with Supervisor" do
      child = %ChildOrder{
        position: 0,
        id: :sub_sup,
        child_spec: %ChildSpec{type: :worker, module: MyAppSupervisor}
      }

      assert SupervisorExtractor.nested_supervisor?(child)
    end

    test "returns false for worker type with non-Supervisor module name" do
      child = %ChildOrder{
        position: 0,
        id: :worker,
        child_spec: %ChildSpec{type: :worker, module: MyWorker}
      }

      refute SupervisorExtractor.nested_supervisor?(child)
    end

    test "returns false for nil module" do
      child = %ChildOrder{
        position: 0,
        id: :worker,
        child_spec: %ChildSpec{type: :worker, module: nil}
      }

      refute SupervisorExtractor.nested_supervisor?(child)
    end

    test "returns false for missing child_spec" do
      child = %ChildOrder{position: 0, id: :worker}
      refute SupervisorExtractor.nested_supervisor?(child)
    end
  end

  describe "supervisor_module?/1" do
    test "returns true for module name ending with Supervisor" do
      assert SupervisorExtractor.supervisor_module?(MySupervisor)
      assert SupervisorExtractor.supervisor_module?(MyApp.SubSupervisor)
      assert SupervisorExtractor.supervisor_module?(MyApp.Workers.TaskSupervisor)
    end

    test "returns false for non-Supervisor module names" do
      refute SupervisorExtractor.supervisor_module?(MyWorker)
      refute SupervisorExtractor.supervisor_module?(MyApp.Server)
      refute SupervisorExtractor.supervisor_module?(MyApp.GenServer)
    end

    test "returns false for nil" do
      refute SupervisorExtractor.supervisor_module?(nil)
    end

    test "handles DynamicSupervisor pattern" do
      # DynamicSupervisor ends with Supervisor
      assert SupervisorExtractor.supervisor_module?(MyApp.DynamicSupervisor)
    end
  end

  describe "extract_nested_supervisors/1" do
    test "extracts supervisor with explicit type" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :worker,
          child_spec: %ChildSpec{id: :worker, type: :worker, module: MyWorker}
        },
        %ChildOrder{
          position: 1,
          id: :sub_sup,
          child_spec: %ChildSpec{id: :sub_sup, type: :supervisor, module: MySupervisor}
        }
      ]

      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)
      assert length(nested) == 1

      [ns] = nested
      assert ns.module == MySupervisor
      assert ns.position == 1
      assert ns.detection_method == :explicit_type
      assert ns.is_confirmed == true
    end

    test "extracts supervisor via name heuristic" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sub_sup,
          child_spec: %ChildSpec{id: :sub_sup, type: :worker, module: MyChildSupervisor}
        }
      ]

      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)
      assert length(nested) == 1

      [ns] = nested
      assert ns.module == MyChildSupervisor
      assert ns.detection_method == :name_heuristic
      assert ns.is_confirmed == false
    end

    test "returns empty list for no supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :worker1,
          child_spec: %ChildSpec{type: :worker, module: Worker1}
        },
        %ChildOrder{
          position: 1,
          id: :worker2,
          child_spec: %ChildSpec{type: :worker, module: Worker2}
        }
      ]

      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)
      assert nested == []
    end

    test "returns empty list for empty input" do
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors([])
      assert nested == []
    end

    test "extracts multiple nested supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sup1,
          child_spec: %ChildSpec{id: :sup1, type: :supervisor, module: Sup1}
        },
        %ChildOrder{
          position: 1,
          id: :worker,
          child_spec: %ChildSpec{id: :worker, type: :worker, module: MyWorker}
        },
        %ChildOrder{
          position: 2,
          id: :sup2,
          child_spec: %ChildSpec{id: :sup2, type: :supervisor, module: Sup2}
        }
      ]

      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)
      assert length(nested) == 2

      assert Enum.map(nested, & &1.module) == [Sup1, Sup2]
      assert Enum.map(nested, & &1.position) == [0, 2]
    end

    test "prioritizes explicit type over name heuristic" do
      # If type is :supervisor, detection_method should be :explicit_type
      # even if module name ends with Supervisor
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sub_sup,
          child_spec: %ChildSpec{id: :sub_sup, type: :supervisor, module: MyChildSupervisor}
        }
      ]

      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)
      [ns] = nested

      assert ns.detection_method == :explicit_type
      assert ns.is_confirmed == true
    end
  end

  describe "extract_nested_supervisors!/1" do
    test "returns result directly" do
      result = SupervisorExtractor.extract_nested_supervisors!([])
      assert result == []
    end
  end

  describe "nested_supervisor_count/1" do
    test "counts supervisors correctly" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sup,
          child_spec: %ChildSpec{type: :supervisor}
        },
        %ChildOrder{
          position: 1,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        },
        %ChildOrder{
          position: 2,
          id: :sup2,
          child_spec: %ChildSpec{type: :worker, module: SubSupervisor}
        }
      ]

      assert SupervisorExtractor.nested_supervisor_count(ordered) == 2
    end

    test "returns 0 for no supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        }
      ]

      assert SupervisorExtractor.nested_supervisor_count(ordered) == 0
    end

    test "returns 0 for empty list" do
      assert SupervisorExtractor.nested_supervisor_count([]) == 0
    end
  end

  describe "supervisor_children/1" do
    test "filters to only supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sup,
          child_spec: %ChildSpec{type: :supervisor}
        },
        %ChildOrder{
          position: 1,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        }
      ]

      result = SupervisorExtractor.supervisor_children(ordered)
      assert length(result) == 1
      assert hd(result).id == :sup
    end

    test "returns empty list when no supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        }
      ]

      assert SupervisorExtractor.supervisor_children(ordered) == []
    end
  end

  describe "worker_children/1" do
    test "filters to only workers" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sup,
          child_spec: %ChildSpec{type: :supervisor}
        },
        %ChildOrder{
          position: 1,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        }
      ]

      result = SupervisorExtractor.worker_children(ordered)
      assert length(result) == 1
      assert hd(result).id == :worker
    end

    test "excludes heuristically detected supervisors" do
      ordered = [
        %ChildOrder{
          position: 0,
          id: :sub_sup,
          child_spec: %ChildSpec{type: :worker, module: MyChildSupervisor}
        },
        %ChildOrder{
          position: 1,
          id: :worker,
          child_spec: %ChildSpec{type: :worker, module: MyWorker}
        }
      ]

      result = SupervisorExtractor.worker_children(ordered)
      assert length(result) == 1
      assert hd(result).id == :worker
    end
  end

  describe "has_nested_supervisors?/1" do
    test "returns true when supervisors exist" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :supervisor}}
      ]

      assert SupervisorExtractor.has_nested_supervisors?(ordered)
    end

    test "returns false when no supervisors" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: MyWorker}}
      ]

      refute SupervisorExtractor.has_nested_supervisors?(ordered)
    end

    test "returns false for empty list" do
      refute SupervisorExtractor.has_nested_supervisors?([])
    end
  end

  describe "supervision_depth/1" do
    test "returns 1 for flat tree" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: MyWorker}}
      ]

      assert SupervisorExtractor.supervision_depth(ordered) == 1
    end

    test "returns 2 for nested tree" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :supervisor}}
      ]

      assert SupervisorExtractor.supervision_depth(ordered) == 2
    end

    test "returns 1 for empty list" do
      assert SupervisorExtractor.supervision_depth([]) == 1
    end
  end

  describe "nested_supervisor_summary/1" do
    test "returns message for empty list" do
      assert SupervisorExtractor.nested_supervisor_summary([]) == "No nested supervisors"
    end

    test "summarizes confirmed supervisors" do
      nested = [
        %NestedSupervisor{
          module: MySup,
          detection_method: :explicit_type,
          is_confirmed: true
        }
      ]

      summary = SupervisorExtractor.nested_supervisor_summary(nested)
      assert summary =~ "1 nested supervisor"
      assert summary =~ "1 confirmed"
      assert summary =~ "MySup"
    end

    test "summarizes heuristic supervisors" do
      nested = [
        %NestedSupervisor{
          module: MyChildSupervisor,
          detection_method: :name_heuristic,
          is_confirmed: false
        }
      ]

      summary = SupervisorExtractor.nested_supervisor_summary(nested)
      assert summary =~ "1 nested supervisor"
      assert summary =~ "1 heuristic"
      assert summary =~ "MyChildSupervisor"
    end

    test "summarizes mixed detection methods" do
      nested = [
        %NestedSupervisor{module: Sup1, is_confirmed: true},
        %NestedSupervisor{module: Sup2, is_confirmed: false},
        %NestedSupervisor{module: Sup3, is_confirmed: true}
      ]

      summary = SupervisorExtractor.nested_supervisor_summary(nested)
      assert summary =~ "3 nested supervisor"
      assert summary =~ "2 confirmed"
      assert summary =~ "1 heuristic"
    end
  end

  describe "supervision_tree_description/1" do
    test "describes empty tree" do
      assert SupervisorExtractor.supervision_tree_description([]) == "Empty supervision tree"
    end

    test "describes flat tree" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: MyWorker}},
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: Worker2}}
      ]

      desc = SupervisorExtractor.supervision_tree_description(ordered)
      assert desc == "Flat tree with 2 worker(s)"
    end

    test "describes nested tree" do
      ordered = [
        %ChildOrder{child_spec: %ChildSpec{type: :supervisor}},
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: MyWorker}},
        %ChildOrder{child_spec: %ChildSpec{type: :worker, module: Worker2}}
      ]

      desc = SupervisorExtractor.supervision_tree_description(ordered)
      assert desc == "Nested tree with 1 supervisor(s) and 2 worker(s)"
    end
  end

  describe "nested_detection_method/1" do
    test "returns the detection method" do
      ns = %NestedSupervisor{detection_method: :explicit_type}
      assert SupervisorExtractor.nested_detection_method(ns) == :explicit_type

      ns = %NestedSupervisor{detection_method: :name_heuristic}
      assert SupervisorExtractor.nested_detection_method(ns) == :name_heuristic
    end
  end

  describe "detection_method_description/1" do
    test "describes explicit_type" do
      desc = SupervisorExtractor.detection_method_description(:explicit_type)
      assert desc =~ "Explicit"
      assert desc =~ ":supervisor"
    end

    test "describes name_heuristic" do
      desc = SupervisorExtractor.detection_method_description(:name_heuristic)
      assert desc =~ "Module name"
      assert desc =~ "Supervisor"
    end

    test "describes behaviour_hint" do
      desc = SupervisorExtractor.detection_method_description(:behaviour_hint)
      assert desc =~ "behaviour"
    end
  end

  describe "integration: nested supervisor detection from AST" do
    test "detects explicit nested supervisor from supervisor code" do
      code = """
      defmodule MyApp.MainSupervisor do
        use Supervisor

        def start_link(init_arg) do
          Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        def init(_init_arg) do
          children = [
            {MyApp.WorkerSupervisor, strategy: :one_for_one, type: :supervisor},
            {MyApp.Worker, []}
          ]

          Supervisor.init(children, strategy: :one_for_all)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)

      # The first child has type: :supervisor
      assert length(nested) == 1
      [ns] = nested
      assert ns.detection_method == :explicit_type
      assert ns.is_confirmed == true
      assert ns.position == 0
    end

    test "detects heuristic nested supervisor from module name" do
      code = """
      defmodule MyApp.RootSupervisor do
        use Supervisor

        def init(_) do
          children = [
            {MyApp.TaskSupervisor, []},
            {MyApp.Worker, []}
          ]

          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)

      # TaskSupervisor ends with "Supervisor" so is detected heuristically
      assert length(nested) == 1
      [ns] = nested
      assert ns.detection_method == :name_heuristic
      assert ns.is_confirmed == false
    end

    test "handles supervisor with no nested supervisors" do
      code = """
      defmodule MyApp.FlatSupervisor do
        use Supervisor

        def init(_) do
          children = [
            {MyApp.Worker1, []},
            {MyApp.Worker2, []},
            {MyApp.Server, []}
          ]

          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)

      assert nested == []
      refute SupervisorExtractor.has_nested_supervisors?(ordered)
      assert SupervisorExtractor.supervision_depth(ordered) == 1

      assert SupervisorExtractor.supervision_tree_description(ordered) ==
               "Flat tree with 3 worker(s)"
    end

    test "handles mixed explicit and heuristic detection" do
      code = """
      defmodule MyApp.MixedSupervisor do
        use Supervisor

        def init(_) do
          children = [
            %{id: :explicit_sup, start: {ExplicitSup, :start_link, []}, type: :supervisor},
            {MyApp.TaskSupervisor, []},
            {MyApp.Worker, []}
          ]

          Supervisor.init(children, strategy: :rest_for_one)
        end
      end
      """

      body = parse_module_body(code)
      {:ok, ordered} = SupervisorExtractor.extract_ordered_children(body)
      {:ok, nested} = SupervisorExtractor.extract_nested_supervisors(ordered)

      assert length(nested) == 2
      confirmed = Enum.count(nested, & &1.is_confirmed)
      heuristic = length(nested) - confirmed

      assert confirmed == 1
      assert heuristic == 1

      summary = SupervisorExtractor.nested_supervisor_summary(nested)
      assert summary =~ "2 nested supervisor"
      assert summary =~ "1 confirmed"
      assert summary =~ "1 heuristic"
    end
  end
end
