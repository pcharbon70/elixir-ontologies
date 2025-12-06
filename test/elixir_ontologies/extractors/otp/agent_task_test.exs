defmodule ElixirOntologies.Extractors.OTP.AgentTaskTest do
  @moduledoc """
  Tests for the backward-compatible AgentTask delegation module.

  These tests verify that the AgentTask module correctly delegates to the
  new separate Agent and Task modules while maintaining backward compatibility.
  """
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.AgentTask
  alias ElixirOntologies.Extractors.OTP.AgentTask.Agent
  alias ElixirOntologies.Extractors.OTP.AgentTask.AgentCall
  alias ElixirOntologies.Extractors.OTP.AgentTask.Task
  alias ElixirOntologies.Extractors.OTP.AgentTask.TaskCall

  # Run doctests
  doctest ElixirOntologies.Extractors.OTP.AgentTask

  # ============================================================================
  # Agent Detection Tests (Delegation)
  # ============================================================================

  describe "agent?/1" do
    test "returns true for use Agent" do
      code = "defmodule Counter do use Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentTask.agent?(body)
    end

    test "returns true for @behaviour Agent" do
      code = "defmodule Counter do @behaviour Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentTask.agent?(body)
    end

    test "returns true for Agent function calls" do
      code = """
      defmodule Counter do
        def start do
          Agent.start_link(fn -> 0 end)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentTask.agent?(body)
    end

    test "returns false for non-Agent modules" do
      code = "defmodule Counter do use GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      refute AgentTask.agent?(body)
    end
  end

  describe "use_agent?/1" do
    test "returns true for use Agent" do
      {:ok, ast} = Code.string_to_quoted("use Agent")
      assert AgentTask.use_agent?(ast)
    end

    test "returns true for use Agent with options" do
      {:ok, ast} = Code.string_to_quoted("use Agent, restart: :temporary")
      assert AgentTask.use_agent?(ast)
    end

    test "returns false for other use statements" do
      {:ok, ast} = Code.string_to_quoted("use GenServer")
      refute AgentTask.use_agent?(ast)
    end
  end

  describe "behaviour_agent?/1" do
    test "returns true for @behaviour Agent" do
      {:ok, ast} = Code.string_to_quoted("@behaviour Agent")
      assert AgentTask.behaviour_agent?(ast)
    end

    test "returns false for other behaviours" do
      {:ok, ast} = Code.string_to_quoted("@behaviour GenServer")
      refute AgentTask.behaviour_agent?(ast)
    end
  end

  describe "agent_call?/1" do
    test "returns true for Agent.start_link" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns true for Agent.get" do
      {:ok, ast} = Code.string_to_quoted("Agent.get(agent, fn s -> s end)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns true for Agent.update" do
      {:ok, ast} = Code.string_to_quoted("Agent.update(agent, fn s -> s + 1 end)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns true for Agent.get_and_update" do
      {:ok, ast} = Code.string_to_quoted("Agent.get_and_update(agent, fn s -> {s, s + 1} end)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns true for Agent.cast" do
      {:ok, ast} = Code.string_to_quoted("Agent.cast(agent, fn s -> s + 1 end)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns true for Agent.stop" do
      {:ok, ast} = Code.string_to_quoted("Agent.stop(agent)")
      assert AgentTask.agent_call?(ast)
    end

    test "returns false for non-Agent calls" do
      {:ok, ast} = Code.string_to_quoted("GenServer.call(pid, :msg)")
      refute AgentTask.agent_call?(ast)
    end
  end

  describe "extract_agent/1" do
    test "extracts use Agent" do
      code = "defmodule C do use Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_agent(body)

      # Check field values instead of struct type (delegation returns new struct)
      assert result.detection_method == :use
      assert result.use_options == []
    end

    test "extracts use Agent with options" do
      code = "defmodule C do use Agent, restart: :temporary end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_agent(body)

      assert result.detection_method == :use
      assert result.use_options == [restart: :temporary]
    end

    test "extracts @behaviour Agent" do
      code = "defmodule C do @behaviour Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_agent(body)

      assert result.detection_method == :behaviour
      assert result.use_options == nil
    end

    test "extracts Agent function calls" do
      code = """
      defmodule C do
        def start do
          Agent.start_link(fn -> 0 end)
        end

        def get_value(agent) do
          Agent.get(agent, fn s -> s end)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_agent(body)

      assert result.detection_method == :function_call
      assert length(result.function_calls) == 2
      assert Enum.any?(result.function_calls, &(&1.function == :start_link))
      assert Enum.any?(result.function_calls, &(&1.function == :get))
    end

    test "returns error for non-Agent modules" do
      code = "defmodule C do use GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert {:error, "Module does not use Agent"} = AgentTask.extract_agent(body)
    end
  end

  # ============================================================================
  # Task Detection Tests (Delegation)
  # ============================================================================

  describe "task?/1" do
    test "returns true for Task.async call" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      assert AgentTask.task?(ast)
    end

    test "returns true for module with Task calls" do
      code = """
      defmodule W do
        def run do
          Task.async(fn -> :result end)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentTask.task?(body)
    end

    test "returns false for non-Task code" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      refute AgentTask.task?(ast)
    end
  end

  describe "task_call?/1" do
    test "returns true for Task.async" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      assert AgentTask.task_call?(ast)
    end

    test "returns true for Task.start" do
      {:ok, ast} = Code.string_to_quoted("Task.start(fn -> :ok end)")
      assert AgentTask.task_call?(ast)
    end

    test "returns true for Task.start_link" do
      {:ok, ast} = Code.string_to_quoted("Task.start_link(fn -> :ok end)")
      assert AgentTask.task_call?(ast)
    end

    test "returns true for Task.await" do
      {:ok, ast} = Code.string_to_quoted("Task.await(task)")
      assert AgentTask.task_call?(ast)
    end

    test "returns true for Task.yield" do
      {:ok, ast} = Code.string_to_quoted("Task.yield(task)")
      assert AgentTask.task_call?(ast)
    end

    test "returns true for Task.async_stream" do
      {:ok, ast} = Code.string_to_quoted("Task.async_stream(list, fn x -> x end)")
      assert AgentTask.task_call?(ast)
    end

    test "returns false for non-Task calls" do
      {:ok, ast} = Code.string_to_quoted("Agent.get(a, fn s -> s end)")
      refute AgentTask.task_call?(ast)
    end
  end

  describe "extract_task/1" do
    test "extracts Task.async call" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :result end)")
      {:ok, result} = AgentTask.extract_task(ast)

      # Check field values instead of struct type (delegation returns new struct)
      assert result.type == :task
      assert result.detection_method == :function_call
      assert length(result.function_calls) == 1
      assert hd(result.function_calls).function == :async
    end

    test "extracts multiple Task calls at top level" do
      code = """
      defmodule W do
        def run do
          Task.async(fn -> :result end)
        end

        def wait(task) do
          Task.await(task)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_task(body)

      assert result.type == :task
      assert length(result.function_calls) == 2
    end

    test "returns error for non-Task code" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      assert {:error, "Module does not use Task"} = AgentTask.extract_task(ast)
    end
  end

  # ============================================================================
  # Task.Supervisor Detection Tests
  # ============================================================================

  describe "task_supervisor?/1" do
    test "returns true for use Task.Supervisor" do
      code = "defmodule S do use Task.Supervisor end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentTask.task_supervisor?(body)
    end

    test "returns true for Task.Supervisor calls" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      assert AgentTask.task_supervisor?(ast)
    end

    test "returns false for regular Task usage" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      refute AgentTask.task_supervisor?(ast)
    end
  end

  describe "use_task_supervisor?/1" do
    test "returns true for use Task.Supervisor" do
      {:ok, ast} = Code.string_to_quoted("use Task.Supervisor")
      assert AgentTask.use_task_supervisor?(ast)
    end

    test "returns false for use Task" do
      {:ok, ast} = Code.string_to_quoted("use Task")
      refute AgentTask.use_task_supervisor?(ast)
    end
  end

  describe "task_supervisor_call?/1" do
    test "returns true for Task.Supervisor.async" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      assert AgentTask.task_supervisor_call?(ast)
    end

    test "returns true for Task.Supervisor.async_nolink" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async_nolink(sup, fn -> :ok end)")
      assert AgentTask.task_supervisor_call?(ast)
    end

    test "returns true for Task.Supervisor.start_child" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.start_child(sup, fn -> :ok end)")
      assert AgentTask.task_supervisor_call?(ast)
    end

    test "returns false for regular Task calls" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      refute AgentTask.task_supervisor_call?(ast)
    end
  end

  describe "extract_task/1 with Task.Supervisor" do
    test "extracts use Task.Supervisor" do
      code = "defmodule S do use Task.Supervisor end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_task(body)

      assert result.type == :task_supervisor
      assert result.detection_method == :use
    end

    test "extracts Task.Supervisor calls" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      {:ok, result} = AgentTask.extract_task(ast)

      assert result.type == :task_supervisor
      assert result.detection_method == :function_call
      assert length(result.function_calls) == 1
      assert hd(result.function_calls).supervised == true
    end
  end

  # ============================================================================
  # Backward Compatibility Struct Tests
  # ============================================================================

  describe "backward-compatible Agent struct" do
    test "has expected fields" do
      agent = %Agent{}
      assert Map.has_key?(agent, :detection_method)
      assert Map.has_key?(agent, :use_options)
      assert Map.has_key?(agent, :function_calls)
      assert Map.has_key?(agent, :location)
      assert Map.has_key?(agent, :metadata)
    end
  end

  describe "backward-compatible AgentCall struct" do
    test "has expected fields" do
      call = %AgentCall{}
      assert Map.has_key?(call, :function)
      assert Map.has_key?(call, :location)
      assert Map.has_key?(call, :metadata)
    end
  end

  describe "backward-compatible Task struct" do
    test "has expected fields" do
      task = %Task{}
      assert Map.has_key?(task, :type)
      assert Map.has_key?(task, :detection_method)
      assert Map.has_key?(task, :function_calls)
      assert Map.has_key?(task, :location)
      assert Map.has_key?(task, :metadata)
    end
  end

  describe "backward-compatible TaskCall struct" do
    test "has expected fields" do
      call = %TaskCall{}
      assert Map.has_key?(call, :function)
      assert Map.has_key?(call, :supervised)
      assert Map.has_key?(call, :location)
      assert Map.has_key?(call, :metadata)
    end
  end

  # ============================================================================
  # OTP Behaviour Tests
  # ============================================================================

  describe "otp_behaviour/1" do
    test "returns :agent for agent" do
      assert AgentTask.otp_behaviour(:agent) == :agent
    end

    test "returns :task for task" do
      assert AgentTask.otp_behaviour(:task) == :task
    end
  end

  # ============================================================================
  # Real-World Pattern Tests
  # ============================================================================

  describe "real-world patterns" do
    test "extracts typical Agent counter module" do
      code = """
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
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_agent(body)

      assert result.detection_method == :use
      assert length(result.function_calls) == 3
    end

    test "extracts typical Task async/await pattern" do
      code = """
      defmodule Worker do
        def start_task do
          Task.async(fn -> :result end)
        end

        def wait_task(task) do
          Task.await(task)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_task(body)

      assert result.type == :task
      assert length(result.function_calls) >= 1
    end

    test "extracts Task.Supervisor pattern" do
      code = """
      defmodule MyTaskSupervisor do
        use Task.Supervisor

        def start_link(opts) do
          Task.Supervisor.start_link(opts)
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentTask.extract_task(body)

      assert result.type == :task_supervisor
      assert result.detection_method == :use
    end
  end
end
