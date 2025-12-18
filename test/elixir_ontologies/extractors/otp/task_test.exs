defmodule ElixirOntologies.Extractors.OTP.TaskTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
  alias ElixirOntologies.Extractors.OTP.Task.TaskCall

  doctest ElixirOntologies.Extractors.OTP.Task

  # ============================================================================
  # Task Detection Tests
  # ============================================================================

  describe "task?/1" do
    test "returns true for Task.async call" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      assert TaskExtractor.task?(ast)
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
      assert TaskExtractor.task?(body)
    end

    test "returns false for non-Task code" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      refute TaskExtractor.task?(ast)
    end
  end

  describe "task_call?/1" do
    test "returns true for Task.async" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns true for Task.start" do
      {:ok, ast} = Code.string_to_quoted("Task.start(fn -> :ok end)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns true for Task.start_link" do
      {:ok, ast} = Code.string_to_quoted("Task.start_link(fn -> :ok end)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns true for Task.await" do
      {:ok, ast} = Code.string_to_quoted("Task.await(task)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns true for Task.yield" do
      {:ok, ast} = Code.string_to_quoted("Task.yield(task)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns true for Task.async_stream" do
      {:ok, ast} = Code.string_to_quoted("Task.async_stream(list, fn x -> x end)")
      assert TaskExtractor.task_call?(ast)
    end

    test "returns false for non-Task calls" do
      {:ok, ast} = Code.string_to_quoted("Agent.get(a, fn s -> s end)")
      refute TaskExtractor.task_call?(ast)
    end
  end

  describe "extract/1" do
    test "extracts Task.async call" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :result end)")
      {:ok, result} = TaskExtractor.extract(ast)

      assert %TaskExtractor{} = result
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
      {:ok, result} = TaskExtractor.extract(body)

      assert result.type == :task
      assert length(result.function_calls) == 2
    end

    test "returns error for non-Task code" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      assert {:error, "Module does not use Task"} = TaskExtractor.extract(ast)
    end
  end

  # ============================================================================
  # Task.Supervisor Detection Tests
  # ============================================================================

  describe "task_supervisor?/1" do
    test "returns true for use Task.Supervisor" do
      code = "defmodule S do use Task.Supervisor end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert TaskExtractor.task_supervisor?(body)
    end

    test "returns true for Task.Supervisor calls" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      assert TaskExtractor.task_supervisor?(ast)
    end

    test "returns false for regular Task usage" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      refute TaskExtractor.task_supervisor?(ast)
    end
  end

  describe "use_task_supervisor?/1" do
    test "returns true for use Task.Supervisor" do
      {:ok, ast} = Code.string_to_quoted("use Task.Supervisor")
      assert TaskExtractor.use_task_supervisor?(ast)
    end

    test "returns false for use Task" do
      {:ok, ast} = Code.string_to_quoted("use Task")
      refute TaskExtractor.use_task_supervisor?(ast)
    end
  end

  describe "task_supervisor_call?/1" do
    test "returns true for Task.Supervisor.async" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      assert TaskExtractor.task_supervisor_call?(ast)
    end

    test "returns true for Task.Supervisor.async_nolink" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async_nolink(sup, fn -> :ok end)")
      assert TaskExtractor.task_supervisor_call?(ast)
    end

    test "returns true for Task.Supervisor.start_child" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.start_child(sup, fn -> :ok end)")
      assert TaskExtractor.task_supervisor_call?(ast)
    end

    test "returns false for regular Task calls" do
      {:ok, ast} = Code.string_to_quoted("Task.async(fn -> :ok end)")
      refute TaskExtractor.task_supervisor_call?(ast)
    end
  end

  describe "extract/1 with Task.Supervisor" do
    test "extracts use Task.Supervisor" do
      code = "defmodule S do use Task.Supervisor end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = TaskExtractor.extract(body)

      assert result.type == :task_supervisor
      assert result.detection_method == :use
    end

    test "extracts Task.Supervisor calls" do
      {:ok, ast} = Code.string_to_quoted("Task.Supervisor.async(sup, fn -> :ok end)")
      {:ok, result} = TaskExtractor.extract(ast)

      assert result.type == :task_supervisor
      assert result.detection_method == :function_call
      assert length(result.function_calls) == 1
      assert hd(result.function_calls).supervised == true
    end
  end

  # ============================================================================
  # Struct Tests
  # ============================================================================

  describe "Task struct" do
    test "has expected fields" do
      task = %TaskExtractor{}
      assert Map.has_key?(task, :type)
      assert Map.has_key?(task, :detection_method)
      assert Map.has_key?(task, :function_calls)
      assert Map.has_key?(task, :location)
      assert Map.has_key?(task, :metadata)
    end
  end

  describe "TaskCall struct" do
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

  describe "otp_behaviour/0" do
    test "returns :task" do
      assert TaskExtractor.otp_behaviour() == :task
    end
  end

  # ============================================================================
  # Real-World Pattern Tests
  # ============================================================================

  describe "real-world patterns" do
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
      {:ok, result} = TaskExtractor.extract(body)

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
      {:ok, result} = TaskExtractor.extract(body)

      assert result.type == :task_supervisor
      assert result.detection_method == :use
    end
  end
end
