defmodule ElixirOntologies.Extractors.OTP.AgentTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
  alias ElixirOntologies.Extractors.OTP.Agent.AgentCall

  doctest ElixirOntologies.Extractors.OTP.Agent

  # ============================================================================
  # Agent Detection Tests
  # ============================================================================

  describe "agent?/1" do
    test "returns true for use Agent" do
      code = "defmodule Counter do use Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentExtractor.agent?(body)
    end

    test "returns true for @behaviour Agent" do
      code = "defmodule Counter do @behaviour Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert AgentExtractor.agent?(body)
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
      assert AgentExtractor.agent?(body)
    end

    test "returns false for non-Agent modules" do
      code = "defmodule Counter do use GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      refute AgentExtractor.agent?(body)
    end
  end

  describe "use_agent?/1" do
    test "returns true for use Agent" do
      {:ok, ast} = Code.string_to_quoted("use Agent")
      assert AgentExtractor.use_agent?(ast)
    end

    test "returns true for use Agent with options" do
      {:ok, ast} = Code.string_to_quoted("use Agent, restart: :temporary")
      assert AgentExtractor.use_agent?(ast)
    end

    test "returns false for other use statements" do
      {:ok, ast} = Code.string_to_quoted("use GenServer")
      refute AgentExtractor.use_agent?(ast)
    end
  end

  describe "behaviour_agent?/1" do
    test "returns true for @behaviour Agent" do
      {:ok, ast} = Code.string_to_quoted("@behaviour Agent")
      assert AgentExtractor.behaviour_agent?(ast)
    end

    test "returns false for other behaviours" do
      {:ok, ast} = Code.string_to_quoted("@behaviour GenServer")
      refute AgentExtractor.behaviour_agent?(ast)
    end
  end

  describe "agent_call?/1" do
    test "returns true for Agent.start_link" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns true for Agent.get" do
      {:ok, ast} = Code.string_to_quoted("Agent.get(agent, fn s -> s end)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns true for Agent.update" do
      {:ok, ast} = Code.string_to_quoted("Agent.update(agent, fn s -> s + 1 end)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns true for Agent.get_and_update" do
      {:ok, ast} = Code.string_to_quoted("Agent.get_and_update(agent, fn s -> {s, s + 1} end)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns true for Agent.cast" do
      {:ok, ast} = Code.string_to_quoted("Agent.cast(agent, fn s -> s + 1 end)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns true for Agent.stop" do
      {:ok, ast} = Code.string_to_quoted("Agent.stop(agent)")
      assert AgentExtractor.agent_call?(ast)
    end

    test "returns false for non-Agent calls" do
      {:ok, ast} = Code.string_to_quoted("GenServer.call(pid, :msg)")
      refute AgentExtractor.agent_call?(ast)
    end
  end

  describe "extract/1" do
    test "extracts use Agent" do
      code = "defmodule C do use Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentExtractor.extract(body)

      assert %AgentExtractor{} = result
      assert result.detection_method == :use
      assert result.use_options == []
    end

    test "extracts use Agent with options" do
      code = "defmodule C do use Agent, restart: :temporary end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentExtractor.extract(body)

      assert result.detection_method == :use
      assert result.use_options == [restart: :temporary]
    end

    test "extracts @behaviour Agent" do
      code = "defmodule C do @behaviour Agent end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = AgentExtractor.extract(body)

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
      {:ok, result} = AgentExtractor.extract(body)

      assert result.detection_method == :function_call
      assert length(result.function_calls) == 2
      assert Enum.any?(result.function_calls, &(&1.function == :start_link))
      assert Enum.any?(result.function_calls, &(&1.function == :get))
    end

    test "returns error for non-Agent modules" do
      code = "defmodule C do use GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert {:error, "Module does not use Agent"} = AgentExtractor.extract(body)
    end
  end

  # ============================================================================
  # Struct Tests
  # ============================================================================

  describe "Agent struct" do
    test "has expected fields" do
      agent = %AgentExtractor{}
      assert Map.has_key?(agent, :detection_method)
      assert Map.has_key?(agent, :use_options)
      assert Map.has_key?(agent, :function_calls)
      assert Map.has_key?(agent, :location)
      assert Map.has_key?(agent, :metadata)
    end
  end

  describe "AgentCall struct" do
    test "has expected fields" do
      call = %AgentCall{}
      assert Map.has_key?(call, :function)
      assert Map.has_key?(call, :location)
      assert Map.has_key?(call, :metadata)
    end
  end

  # ============================================================================
  # OTP Behaviour Tests
  # ============================================================================

  describe "otp_behaviour/0" do
    test "returns :agent" do
      assert AgentExtractor.otp_behaviour() == :agent
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
      {:ok, result} = AgentExtractor.extract(body)

      assert result.detection_method == :use
      assert length(result.function_calls) == 3
    end
  end
end
