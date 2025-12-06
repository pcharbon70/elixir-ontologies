defmodule ElixirOntologies.Extractors.OTP.SupervisorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
  alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

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
      body = parse_module_body("defmodule S do use DynamicSupervisor, strategy: :one_for_one, max_children: 100 end")
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

      assert {:error, "No supervision strategy found"} = SupervisorExtractor.extract_strategy(body)
    end

    test "returns error for supervisor without init callback" do
      body = parse_module_body("defmodule S do use Supervisor end")

      assert {:error, "No supervision strategy found"} = SupervisorExtractor.extract_strategy(body)
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
end
