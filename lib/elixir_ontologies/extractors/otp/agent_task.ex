defmodule ElixirOntologies.Extractors.OTP.AgentTask do
  @moduledoc """
  Backward-compatibility module for Agent and Task extraction.

  This module delegates to the separate Agent and Task extractor modules.
  For new code, prefer using the specific modules directly:

  - `ElixirOntologies.Extractors.OTP.Agent` for Agent extraction
  - `ElixirOntologies.Extractors.OTP.Task` for Task extraction

  ## Deprecated

  This module is maintained for backward compatibility. The nested structs
  (Agent, AgentCall, Task, TaskCall) are re-exported from the separate modules.
  """

  alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
  alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor

  # Re-export structs for backward compatibility
  defmodule Agent do
    @moduledoc false
    defstruct [:detection_method, :use_options, :function_calls, :location, :metadata]
  end

  defmodule AgentCall do
    @moduledoc false
    defstruct [:function, :location, :metadata]
  end

  defmodule Task do
    @moduledoc false
    defstruct [:type, :detection_method, :function_calls, :location, :metadata]
  end

  defmodule TaskCall do
    @moduledoc false
    defstruct [:function, :supervised, :location, :metadata]
  end

  # ===========================================================================
  # Agent Delegations
  # ===========================================================================

  @doc """
  Checks if a module body implements or uses Agent.

  Delegates to `ElixirOntologies.Extractors.OTP.Agent.agent?/1`.
  """
  @spec agent?(Macro.t()) :: boolean()
  defdelegate agent?(body), to: AgentExtractor

  @doc """
  Checks if a single AST node is a `use Agent` invocation.

  Delegates to `ElixirOntologies.Extractors.OTP.Agent.use_agent?/1`.
  """
  @spec use_agent?(Macro.t()) :: boolean()
  defdelegate use_agent?(ast), to: AgentExtractor

  @doc """
  Checks if a single AST node is a `@behaviour Agent` declaration.

  Delegates to `ElixirOntologies.Extractors.OTP.Agent.behaviour_agent?/1`.
  """
  @spec behaviour_agent?(Macro.t()) :: boolean()
  defdelegate behaviour_agent?(ast), to: AgentExtractor

  @doc """
  Checks if a single AST node is an Agent function call.

  Delegates to `ElixirOntologies.Extractors.OTP.Agent.agent_call?/1`.
  """
  @spec agent_call?(Macro.t()) :: boolean()
  defdelegate agent_call?(ast), to: AgentExtractor

  @doc """
  Extracts Agent implementation details from a module body.

  Delegates to `ElixirOntologies.Extractors.OTP.Agent.extract/2`.
  """
  @spec extract_agent(Macro.t(), keyword()) ::
          {:ok, AgentExtractor.t()} | {:error, String.t()}
  def extract_agent(body, opts \\ []), do: AgentExtractor.extract(body, opts)

  # ===========================================================================
  # Task Delegations
  # ===========================================================================

  @doc """
  Checks if a module body contains Task usage.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.task?/1`.
  """
  @spec task?(Macro.t()) :: boolean()
  defdelegate task?(ast), to: TaskExtractor

  @doc """
  Checks if a single AST node is a Task function call.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.task_call?/1`.
  """
  @spec task_call?(Macro.t()) :: boolean()
  defdelegate task_call?(ast), to: TaskExtractor

  @doc """
  Checks if a single AST node is a `use Task.Supervisor` invocation.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.use_task_supervisor?/1`.
  """
  @spec use_task_supervisor?(Macro.t()) :: boolean()
  defdelegate use_task_supervisor?(ast), to: TaskExtractor

  @doc """
  Checks if a single AST node is a Task.Supervisor function call.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.task_supervisor_call?/1`.
  """
  @spec task_supervisor_call?(Macro.t()) :: boolean()
  defdelegate task_supervisor_call?(ast), to: TaskExtractor

  @doc """
  Extracts Task usage details from a module body.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.extract/2`.
  """
  @spec extract_task(Macro.t(), keyword()) ::
          {:ok, TaskExtractor.t()} | {:error, String.t()}
  def extract_task(body, opts \\ []), do: TaskExtractor.extract(body, opts)

  @doc """
  Checks if a module body uses Task.Supervisor.

  Delegates to `ElixirOntologies.Extractors.OTP.Task.task_supervisor?/1`.
  """
  @spec task_supervisor?(Macro.t()) :: boolean()
  defdelegate task_supervisor?(body), to: TaskExtractor

  @doc """
  Returns the OTP behaviour type.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> AgentTask.otp_behaviour(:agent)
      :agent

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> AgentTask.otp_behaviour(:task)
      :task
  """
  @spec otp_behaviour(:agent | :task) :: :agent | :task
  def otp_behaviour(:agent), do: :agent
  def otp_behaviour(:task), do: :task
end
