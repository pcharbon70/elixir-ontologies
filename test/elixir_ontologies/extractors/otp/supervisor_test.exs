defmodule ElixirOntologies.Extractors.OTP.SupervisorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
  alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

  # Run doctests from the Supervisor module
  doctest ElixirOntologies.Extractors.OTP.Supervisor
  doctest ElixirOntologies.Extractors.OTP.Supervisor.Strategy
  doctest ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

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
end
