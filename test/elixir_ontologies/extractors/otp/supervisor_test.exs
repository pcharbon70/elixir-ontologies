defmodule ElixirOntologies.Extractors.OTP.SupervisorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor

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
end
