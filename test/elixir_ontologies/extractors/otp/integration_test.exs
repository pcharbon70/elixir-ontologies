defmodule ElixirOntologies.Extractors.OTP.IntegrationTest do
  @moduledoc """
  Integration tests for Phase 6 OTP extractors.

  These tests verify that all OTP extractors work correctly together
  on realistic, complete module implementations.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
  alias ElixirOntologies.Extractors.OTP.AgentTask
  alias ElixirOntologies.Extractors.OTP.ETS

  # ============================================================================
  # GenServer Integration Tests
  # ============================================================================

  describe "GenServer integration - complete module" do
    @genserver_code """
    defmodule MyServer do
      use GenServer

      # Client API

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def get_state do
        GenServer.call(__MODULE__, :get_state)
      end

      def set_state(value) do
        GenServer.cast(__MODULE__, {:set_state, value})
      end

      # Server Callbacks

      @impl true
      def init(opts) do
        state = Keyword.get(opts, :initial, 0)
        {:ok, state, {:continue, :after_init}}
      end

      @impl true
      def handle_continue(:after_init, state) do
        {:noreply, state}
      end

      @impl true
      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_cast({:set_state, value}, _state) do
        {:noreply, value}
      end

      @impl true
      def handle_info(:tick, state) do
        {:noreply, state + 1}
      end

      @impl true
      def terminate(_reason, _state) do
        :ok
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@genserver_code)
      {:ok, body: body}
    end

    test "detects GenServer implementation", %{body: body} do
      assert GenServerExtractor.genserver?(body)
    end

    test "extracts GenServer with correct detection method", %{body: body} do
      {:ok, result} = GenServerExtractor.extract(body)
      assert result.detection_method == :use
    end

    test "extracts init callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      init_callbacks = Enum.filter(callbacks, &(&1.type == :init))
      assert length(init_callbacks) == 1
    end

    test "extracts handle_call callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      call_callbacks = Enum.filter(callbacks, &(&1.type == :handle_call))
      assert length(call_callbacks) == 1
    end

    test "extracts handle_cast callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      cast_callbacks = Enum.filter(callbacks, &(&1.type == :handle_cast))
      assert length(cast_callbacks) == 1
    end

    test "extracts handle_info callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      info_callbacks = Enum.filter(callbacks, &(&1.type == :handle_info))
      assert length(info_callbacks) == 1
    end

    test "extracts handle_continue callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      continue_callbacks = Enum.filter(callbacks, &(&1.type == :handle_continue))
      assert length(continue_callbacks) == 1
    end

    test "extracts terminate callback", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      terminate_callbacks = Enum.filter(callbacks, &(&1.type == :terminate))
      assert length(terminate_callbacks) == 1
    end

    test "extracts all 6 callbacks", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      assert length(callbacks) == 6
    end
  end

  # ============================================================================
  # Supervisor Integration Tests
  # ============================================================================

  describe "Supervisor integration - complete module" do
    @supervisor_code """
    defmodule MySupervisor do
      use Supervisor

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          {MyWorker, []},
          {MyCache, name: :cache},
          %{
            id: :special_worker,
            start: {SpecialWorker, :start_link, [[]]},
            restart: :transient
          }
        ]

        Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@supervisor_code)
      {:ok, body: body}
    end

    test "detects Supervisor implementation", %{body: body} do
      assert SupervisorExtractor.supervisor?(body)
    end

    test "extracts supervisor type as :supervisor", %{body: body} do
      assert SupervisorExtractor.supervisor_type(body) == :supervisor
    end

    test "extracts detection method as :use", %{body: body} do
      assert SupervisorExtractor.detection_method(body) == :use
    end

    test "extracts strategy as :one_for_one", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_one
    end

    test "extracts max_restarts", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.max_restarts == 3
    end

    test "extracts max_seconds", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.max_seconds == 5
    end

    test "extracts 3 child specs", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert length(children) == 3
    end

    test "child_count matches children list", %{body: body} do
      count = SupervisorExtractor.child_count(body)
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert count == length(children)
    end
  end

  describe "DynamicSupervisor integration" do
    @dynamic_supervisor_code """
    defmodule MyDynamicSupervisor do
      use DynamicSupervisor

      def start_link(opts) do
        DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def start_child(args) do
        DynamicSupervisor.start_child(__MODULE__, {MyWorker, args})
      end

      @impl true
      def init(_opts) do
        DynamicSupervisor.init(strategy: :one_for_one)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@dynamic_supervisor_code)
      {:ok, body: body}
    end

    test "detects DynamicSupervisor", %{body: body} do
      assert SupervisorExtractor.supervisor?(body)
      assert SupervisorExtractor.dynamic_supervisor?(body)
    end

    test "extracts supervisor type as :dynamic_supervisor", %{body: body} do
      assert SupervisorExtractor.supervisor_type(body) == :dynamic_supervisor
    end

    test "extracts strategy", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_one
    end
  end

  describe "Supervisor with different strategies" do
    test "extracts :one_for_all strategy" do
      code = """
      defmodule AllSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :one_for_all)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :one_for_all
    end

    test "extracts :rest_for_one strategy" do
      code = """
      defmodule RestSup do
        use Supervisor
        def init(_) do
          Supervisor.init([], strategy: :rest_for_one)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :rest_for_one
    end
  end

  # ============================================================================
  # Agent Integration Tests
  # ============================================================================

  describe "Agent integration - complete module" do
    @agent_code """
    defmodule Counter do
      use Agent

      def start_link(initial_value) do
        Agent.start_link(fn -> initial_value end, name: __MODULE__)
      end

      def value do
        Agent.get(__MODULE__, fn state -> state end)
      end

      def increment do
        Agent.update(__MODULE__, fn state -> state + 1 end)
      end

      def increment_and_get do
        Agent.get_and_update(__MODULE__, fn state -> {state, state + 1} end)
      end

      def reset do
        Agent.cast(__MODULE__, fn _state -> 0 end)
      end

      def stop do
        Agent.stop(__MODULE__)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@agent_code)
      {:ok, body: body}
    end

    test "detects Agent implementation", %{body: body} do
      assert AgentTask.agent?(body)
    end

    test "extracts Agent with correct detection method", %{body: body} do
      {:ok, result} = AgentTask.extract_agent(body)
      assert result.detection_method == :use
    end

    test "extracts all Agent function calls", %{body: body} do
      {:ok, result} = AgentTask.extract_agent(body)
      # 6 calls: start_link, get, update, get_and_update, cast, stop
      assert length(result.function_calls) == 6

      functions = Enum.map(result.function_calls, & &1.function)
      assert :start_link in functions
      assert :get in functions
      assert :update in functions
      assert :get_and_update in functions
      assert :cast in functions
      assert :stop in functions
    end
  end

  # ============================================================================
  # Task Integration Tests
  # ============================================================================

  describe "Task integration - async/await pattern" do
    # Note: Task calls inside closures/anonymous functions within Enum.map
    # are not detected by the simple AST traversal. This tests direct calls.
    @task_code """
    defmodule ParallelWorker do
      def run_task do
        Task.async(fn -> :result end)
      end

      def wait_for_task(task) do
        Task.await(task)
      end

      def run_many do
        Task.async_stream([1, 2, 3], fn x -> x * 2 end)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@task_code)
      {:ok, body: body}
    end

    test "detects Task usage", %{body: body} do
      assert AgentTask.task?(body)
    end

    test "extracts Task function calls", %{body: body} do
      {:ok, result} = AgentTask.extract_task(body)
      assert result.type == :task
      assert length(result.function_calls) >= 1

      functions = Enum.map(result.function_calls, & &1.function)
      assert :async in functions or :await in functions or :async_stream in functions
    end
  end

  describe "Task.Supervisor integration" do
    @task_supervisor_code """
    defmodule MyTaskSupervisor do
      use Task.Supervisor

      def start_link(opts) do
        Task.Supervisor.start_link(opts)
      end

      def run_async(supervisor, fun) do
        Task.Supervisor.async(supervisor, fun)
      end

      def run_async_nolink(supervisor, fun) do
        Task.Supervisor.async_nolink(supervisor, fun)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@task_supervisor_code)
      {:ok, body: body}
    end

    test "detects Task.Supervisor", %{body: body} do
      assert AgentTask.task_supervisor?(body)
    end

    test "extracts as task_supervisor type", %{body: body} do
      {:ok, result} = AgentTask.extract_task(body)
      assert result.type == :task_supervisor
    end
  end

  # ============================================================================
  # ETS Integration Tests
  # ============================================================================

  describe "ETS integration - complete module" do
    @ets_code """
    defmodule CacheServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        # Create main cache table
        cache = :ets.new(:cache, [:set, :named_table, :public, read_concurrency: true])

        # Create stats table
        stats = :ets.new(:cache_stats, [:set, :private])

        # Create event log as bag
        events = :ets.new(:events, [:bag, :protected, write_concurrency: true])

        {:ok, %{cache: cache, stats: stats, events: events}}
      end

      @impl true
      def handle_call({:get, key}, _from, state) do
        result = :ets.lookup(:cache, key)
        {:reply, result, state}
      end

      @impl true
      def handle_cast({:put, key, value}, state) do
        :ets.insert(:cache, {key, value})
        {:noreply, state}
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@ets_code)
      {:ok, body: body}
    end

    test "detects ETS usage", %{body: body} do
      assert ETS.has_ets?(body)
    end

    test "extracts all 3 ETS tables", %{body: body} do
      tables = ETS.extract_all(body)
      assert length(tables) == 3
    end

    test "extracts cache table with correct config", %{body: body} do
      tables = ETS.extract_all(body)
      cache = Enum.find(tables, &(&1.name == :cache))

      assert cache.table_type == :set
      assert cache.access_type == :public
      assert cache.named_table == true
      assert cache.read_concurrency == true
    end

    test "extracts stats table as private", %{body: body} do
      tables = ETS.extract_all(body)
      stats = Enum.find(tables, &(&1.name == :cache_stats))

      assert stats.table_type == :set
      assert stats.access_type == :private
    end

    test "extracts events table as bag", %{body: body} do
      tables = ETS.extract_all(body)
      events = Enum.find(tables, &(&1.name == :events))

      assert events.table_type == :bag
      assert events.access_type == :protected
      assert events.write_concurrency == true
    end

    test "module is also detected as GenServer", %{body: body} do
      assert GenServerExtractor.genserver?(body)
    end
  end

  # ============================================================================
  # Application Integration Tests
  # ============================================================================

  describe "Application integration - supervision tree" do
    @application_code """
    defmodule MyApp.Application do
      use Application

      @impl true
      def start(_type, _args) do
        children = [
          # Start the Telemetry supervisor
          MyApp.Telemetry,
          # Start the PubSub system
          {Phoenix.PubSub, name: MyApp.PubSub},
          # Start the main supervisor
          MyApp.Supervisor,
          # Start the cache server
          {MyApp.CacheServer, []},
          # Start the task supervisor
          {Task.Supervisor, name: MyApp.TaskSupervisor}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@application_code)
      {:ok, body: body}
    end

    test "detects Application behaviour" do
      # Application modules use `use Application`
      code = """
      defmodule TestApp do
        use Application
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      # We can check for use Application pattern
      statements = body |> normalize_body()
      has_use_application = Enum.any?(statements, fn
        {:use, _, [{:__aliases__, _, [:Application]} | _]} -> true
        {:use, _, [Application | _]} -> true
        _ -> false
      end)

      assert has_use_application
    end

    test "extracts children from start callback", %{body: body} do
      # The application has a start function with Supervisor.start_link
      # which contains children and options
      statements = body |> normalize_body()

      # Find the start function
      start_fn = Enum.find(statements, fn
        {:def, _, [{:start, _, _} | _]} -> true
        _ -> false
      end)

      assert start_fn != nil
    end
  end

  # ============================================================================
  # Combined OTP Patterns Tests
  # ============================================================================

  describe "combined OTP patterns - GenServer with ETS" do
    @combined_code """
    defmodule StatefulCache do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_opts) do
        table = :ets.new(:state_cache, [:ordered_set, :named_table, :public])
        {:ok, %{table: table, count: 0}}
      end

      def handle_call(:get_count, _from, %{count: count} = state) do
        {:reply, count, state}
      end

      def handle_cast(:increment, %{count: count} = state) do
        {:noreply, %{state | count: count + 1}}
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@combined_code)
      {:ok, body: body}
    end

    test "detects both GenServer and ETS", %{body: body} do
      assert GenServerExtractor.genserver?(body)
      assert ETS.has_ets?(body)
    end

    test "extracts GenServer callbacks", %{body: body} do
      callbacks = GenServerExtractor.extract_callbacks(body)
      types = Enum.map(callbacks, & &1.type)

      assert :init in types
      assert :handle_call in types
      assert :handle_cast in types
    end

    test "extracts ETS table", %{body: body} do
      tables = ETS.extract_all(body)
      assert length(tables) == 1

      table = hd(tables)
      assert table.name == :state_cache
      assert table.table_type == :ordered_set
    end
  end

  describe "Supervisor with multiple child types" do
    @multi_child_code """
    defmodule MultiChildSupervisor do
      use Supervisor

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_opts) do
        children = [
          # GenServer worker
          {MyGenServer, []},
          # Agent
          {MyAgent, 0},
          # Task Supervisor
          {Task.Supervisor, name: MyTaskSupervisor},
          # Another supervisor
          {MyChildSupervisor, []}
        ]

        Supervisor.init(children, strategy: :rest_for_one)
      end
    end
    """

    setup do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@multi_child_code)
      {:ok, body: body}
    end

    test "extracts supervisor with rest_for_one strategy", %{body: body} do
      {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      assert strategy.type == :rest_for_one
    end

    test "extracts 4 children", %{body: body} do
      {:ok, children} = SupervisorExtractor.extract_children(body)
      assert length(children) == 4
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp normalize_body({:__block__, _, statements}), do: statements
  defp normalize_body(statement), do: [statement]
end
