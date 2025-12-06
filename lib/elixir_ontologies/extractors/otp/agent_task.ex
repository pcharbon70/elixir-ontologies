defmodule ElixirOntologies.Extractors.OTP.AgentTask do
  @moduledoc """
  Extracts Agent and Task usage from module AST nodes.

  This module analyzes Elixir AST nodes to detect:
  - Modules implementing the Agent behaviour
  - Task function calls (Task.async, Task.start, etc.)
  - Task.Supervisor usage

  Supports the OTP-related classes from elixir-otp.ttl.

  ## Agent Detection

  Agent implementations can be detected via:

  1. `use Agent` - Macro invocation
  2. `@behaviour Agent` - Direct behaviour declaration
  3. `Agent.*` function calls - Direct Agent API usage

  ## Usage

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "defmodule Counter do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentTask.agent?(body)
      true

  ## Task Detection

  Task usage is detected via function calls:

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.task_call?(ast)
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Agent Result Struct
  # ===========================================================================

  defmodule Agent do
    @moduledoc """
    Represents an extracted Agent implementation or usage.
    """

    @type detection_method :: :use | :behaviour | :function_call

    @type t :: %__MODULE__{
            detection_method: detection_method() | nil,
            use_options: keyword() | nil,
            function_calls: [ElixirOntologies.Extractors.OTP.AgentTask.AgentCall.t()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      detection_method: nil,
      use_options: nil,
      function_calls: [],
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Agent Call Struct
  # ===========================================================================

  defmodule AgentCall do
    @moduledoc """
    Represents a single Agent function call.
    """

    @type function_name :: :start | :start_link | :get | :get_and_update | :update | :cast | :stop

    @type t :: %__MODULE__{
            function: function_name(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      function: nil,
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Task Result Struct
  # ===========================================================================

  defmodule Task do
    @moduledoc """
    Represents extracted Task usage.
    """

    @type task_type :: :task | :task_supervisor

    @type t :: %__MODULE__{
            type: task_type(),
            detection_method: :use | :function_call | nil,
            function_calls: [ElixirOntologies.Extractors.OTP.AgentTask.TaskCall.t()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      type: :task,
      detection_method: nil,
      function_calls: [],
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Task Call Struct
  # ===========================================================================

  defmodule TaskCall do
    @moduledoc """
    Represents a single Task function call.
    """

    @type function_name :: :async | :start | :start_link | :await | :yield | :yield_many | :async_stream | :async_nolink

    @type t :: %__MODULE__{
            function: function_name(),
            supervised: boolean(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      function: nil,
      supervised: false,
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Agent Detection
  # ===========================================================================

  @doc """
  Checks if a module body implements or uses Agent.

  Returns true if the module uses Agent via `use Agent`, `@behaviour Agent`,
  or contains Agent function calls.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "defmodule Counter do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentTask.agent?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "defmodule Counter do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentTask.agent?(body)
      false
  """
  @spec agent?(Macro.t()) :: boolean()
  def agent?(body) do
    statements = Helpers.normalize_body(body)

    uses_agent?(statements) or
      declares_agent_behaviour?(statements) or
      has_agent_calls?(statements)
  end

  @doc """
  Checks if a single AST node is a `use Agent` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "use Agent"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.use_agent?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "use GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.use_agent?(ast)
      false
  """
  @spec use_agent?(Macro.t()) :: boolean()
  def use_agent?({:use, _meta, [{:__aliases__, _, [:Agent]} | _opts]}), do: true
  def use_agent?({:use, _meta, [Agent | _opts]}), do: true
  def use_agent?(_), do: false

  @doc """
  Checks if a single AST node is a `@behaviour Agent` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "@behaviour Agent"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.behaviour_agent?(ast)
      true
  """
  @spec behaviour_agent?(Macro.t()) :: boolean()
  def behaviour_agent?({:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:Agent]}]}]}), do: true
  def behaviour_agent?({:@, _meta, [{:behaviour, _attr_meta, [Agent]}]}), do: true
  def behaviour_agent?(_), do: false

  @doc """
  Checks if a single AST node is an Agent function call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Agent.start_link(fn -> 0 end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.agent_call?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Agent.get(agent, fn s -> s end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.agent_call?(ast)
      true
  """
  @spec agent_call?(Macro.t()) :: boolean()
  def agent_call?({{:., _, [{:__aliases__, _, [:Agent]}, func]}, _, _args})
      when func in [:start, :start_link, :get, :get_and_update, :update, :cast, :stop],
      do: true

  def agent_call?(_), do: false

  @doc """
  Extracts Agent implementation details from a module body.

  Returns `{:ok, result}` if Agent usage is found, or `{:error, reason}` if not.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "defmodule C do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = AgentTask.extract_agent(body)
      iex> result.detection_method
      :use
  """
  @spec extract_agent(Macro.t(), keyword()) :: {:ok, Agent.t()} | {:error, String.t()}
  def extract_agent(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_agent?(statements) ->
        extract_use_agent(statements, opts)

      declares_agent_behaviour?(statements) ->
        extract_behaviour_agent(statements, opts)

      has_agent_calls?(statements) ->
        extract_agent_calls_only(statements, opts)

      true ->
        {:error, "Module does not use Agent"}
    end
  end

  @doc """
  Returns the OTP behaviour type for Agent extractor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> AgentTask.otp_behaviour(:agent)
      :agent
  """
  @spec otp_behaviour(:agent | :task) :: :agent | :task
  def otp_behaviour(:agent), do: :agent
  def otp_behaviour(:task), do: :task

  # ===========================================================================
  # Task Detection
  # ===========================================================================

  @doc """
  Checks if a module body contains Task usage.

  Returns true if the module contains Task function calls or uses Task.Supervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.task?(ast)
      true
  """
  @spec task?(Macro.t()) :: boolean()
  def task?(body) do
    statements = Helpers.normalize_body(body)

    has_task_calls?(statements) or
      uses_task_supervisor?(statements)
  end

  @doc """
  Checks if a single AST node is a Task function call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.task_call?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.await(task)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.task_call?(ast)
      true
  """
  @spec task_call?(Macro.t()) :: boolean()
  def task_call?({{:., _, [{:__aliases__, _, [:Task]}, func]}, _, _args})
      when func in [:async, :start, :start_link, :await, :yield, :yield_many, :async_stream, :async_nolink],
      do: true

  def task_call?(_), do: false

  @doc """
  Checks if a single AST node is a `use Task.Supervisor` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "use Task.Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.use_task_supervisor?(ast)
      true
  """
  @spec use_task_supervisor?(Macro.t()) :: boolean()
  def use_task_supervisor?({:use, _meta, [{:__aliases__, _, [:Task, :Supervisor]} | _opts]}), do: true
  def use_task_supervisor?(_), do: false

  @doc """
  Checks if a single AST node is a Task.Supervisor function call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.Supervisor.async(sup, fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentTask.task_supervisor_call?(ast)
      true
  """
  @spec task_supervisor_call?(Macro.t()) :: boolean()
  def task_supervisor_call?({{:., _, [{:__aliases__, _, [:Task, :Supervisor]}, func]}, _, _args})
      when func in [:async, :async_nolink, :start_child, :start_link],
      do: true

  def task_supervisor_call?(_), do: false

  @doc """
  Extracts Task usage details from a module body.

  Returns `{:ok, result}` if Task usage is found, or `{:error, reason}` if not.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "Task.async(fn -> :result end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = AgentTask.extract_task(ast)
      iex> result.type
      :task
      iex> length(result.function_calls)
      1
  """
  @spec extract_task(Macro.t(), keyword()) :: {:ok, Task.t()} | {:error, String.t()}
  def extract_task(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_task_supervisor?(statements) ->
        extract_task_supervisor_use(statements, opts)

      has_task_supervisor_calls?(statements) ->
        extract_task_supervisor_calls(statements, opts)

      has_task_calls?(statements) ->
        extract_task_calls(statements, opts)

      true ->
        {:error, "Module does not use Task"}
    end
  end

  @doc """
  Checks if a module body uses Task.Supervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.AgentTask
      iex> code = "defmodule S do use Task.Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentTask.task_supervisor?(body)
      true
  """
  @spec task_supervisor?(Macro.t()) :: boolean()
  def task_supervisor?(body) do
    statements = Helpers.normalize_body(body)

    uses_task_supervisor?(statements) or
      has_task_supervisor_calls?(statements)
  end

  # ===========================================================================
  # Private Helpers - Agent
  # ===========================================================================

  defp uses_agent?(statements) do
    Enum.any?(statements, &use_agent?/1)
  end

  defp declares_agent_behaviour?(statements) do
    Enum.any?(statements, &behaviour_agent?/1)
  end

  defp has_agent_calls?(statements) do
    find_agent_calls(statements) != []
  end

  defp find_agent_calls(statements) do
    statements
    |> Enum.flat_map(&find_agent_calls_in_statement/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp find_agent_calls_in_statement({{:., _, [{:__aliases__, _, [:Agent]}, func]}, meta, _args} = _ast)
       when func in [:start, :start_link, :get, :get_and_update, :update, :cast, :stop] do
    [%AgentCall{function: func, location: extract_call_location(meta), metadata: %{}}]
  end

  defp find_agent_calls_in_statement({:def, _, [_, body]}) do
    find_agent_calls_in_body(body)
  end

  defp find_agent_calls_in_statement({:defp, _, [_, body]}) do
    find_agent_calls_in_body(body)
  end

  defp find_agent_calls_in_statement({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_agent_calls_in_statement/1)
  end

  defp find_agent_calls_in_statement(_), do: []

  defp find_agent_calls_in_body([do: body]), do: find_agent_calls_in_statement(body)
  defp find_agent_calls_in_body({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_agent_calls_in_statement/1)
  end
  defp find_agent_calls_in_body(body), do: find_agent_calls_in_statement(body)

  defp extract_use_agent(statements, opts) do
    use_node = Enum.find(statements, &use_agent?/1)
    location = Helpers.extract_location_if(use_node, opts)
    options = extract_use_options(use_node)
    function_calls = find_agent_calls(statements)

    {:ok,
     %Agent{
       detection_method: :use,
       use_options: options,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :agent,
         has_options: options != []
       }
     }}
  end

  defp extract_behaviour_agent(statements, opts) do
    behaviour_node = Enum.find(statements, &behaviour_agent?/1)
    location = Helpers.extract_location_if(behaviour_node, opts)
    function_calls = find_agent_calls(statements)

    {:ok,
     %Agent{
       detection_method: :behaviour,
       use_options: nil,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :agent
       }
     }}
  end

  defp extract_agent_calls_only(statements, opts) do
    function_calls = find_agent_calls(statements)
    first_call = List.first(function_calls)
    location = if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %Agent{
       detection_method: :function_call,
       use_options: nil,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :agent,
         call_count: length(function_calls)
       }
     }}
  end

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [_module]}]}), do: []
  defp extract_use_options({:use, _meta, [module]}) when is_atom(module), do: []
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [_module]}, opts]}) when is_list(opts), do: opts
  defp extract_use_options({:use, _meta, [module, opts]}) when is_atom(module) and is_list(opts), do: opts
  defp extract_use_options(_), do: []

  # ===========================================================================
  # Private Helpers - Task
  # ===========================================================================

  defp has_task_calls?(statements) do
    find_task_calls(statements) != []
  end

  defp uses_task_supervisor?(statements) do
    Enum.any?(statements, &use_task_supervisor?/1)
  end

  defp has_task_supervisor_calls?(statements) do
    find_task_supervisor_calls(statements) != []
  end

  defp find_task_calls(statements) do
    statements
    |> Enum.flat_map(&find_task_calls_in_statement/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp find_task_calls_in_statement({{:., _, [{:__aliases__, _, [:Task]}, func]}, meta, _args})
       when func in [:async, :start, :start_link, :await, :yield, :yield_many, :async_stream, :async_nolink] do
    [%TaskCall{function: func, supervised: false, location: extract_call_location(meta), metadata: %{}}]
  end

  defp find_task_calls_in_statement({:def, _, [_, body]}) do
    find_task_calls_in_body(body)
  end

  defp find_task_calls_in_statement({:defp, _, [_, body]}) do
    find_task_calls_in_body(body)
  end

  defp find_task_calls_in_statement({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_task_calls_in_statement/1)
  end

  defp find_task_calls_in_statement(_), do: []

  defp find_task_calls_in_body([do: body]), do: find_task_calls_in_statement(body)
  defp find_task_calls_in_body({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_task_calls_in_statement/1)
  end
  defp find_task_calls_in_body(body), do: find_task_calls_in_statement(body)

  defp find_task_supervisor_calls(statements) do
    statements
    |> Enum.flat_map(&find_task_supervisor_calls_in_statement/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp find_task_supervisor_calls_in_statement({{:., _, [{:__aliases__, _, [:Task, :Supervisor]}, func]}, meta, _args})
       when func in [:async, :async_nolink, :start_child, :start_link] do
    [%TaskCall{function: func, supervised: true, location: extract_call_location(meta), metadata: %{}}]
  end

  defp find_task_supervisor_calls_in_statement({:def, _, [_, body]}) do
    find_task_supervisor_calls_in_body(body)
  end

  defp find_task_supervisor_calls_in_statement({:defp, _, [_, body]}) do
    find_task_supervisor_calls_in_body(body)
  end

  defp find_task_supervisor_calls_in_statement({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_task_supervisor_calls_in_statement/1)
  end

  defp find_task_supervisor_calls_in_statement(_), do: []

  defp find_task_supervisor_calls_in_body([do: body]), do: find_task_supervisor_calls_in_statement(body)
  defp find_task_supervisor_calls_in_body({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_task_supervisor_calls_in_statement/1)
  end
  defp find_task_supervisor_calls_in_body(body), do: find_task_supervisor_calls_in_statement(body)

  defp extract_task_calls(statements, opts) do
    function_calls = find_task_calls(statements)
    first_call = List.first(function_calls)
    location = if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %Task{
       type: :task,
       detection_method: :function_call,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :task,
         call_count: length(function_calls)
       }
     }}
  end

  defp extract_task_supervisor_use(statements, opts) do
    use_node = Enum.find(statements, &use_task_supervisor?/1)
    location = Helpers.extract_location_if(use_node, opts)
    function_calls = find_task_supervisor_calls(statements) ++ find_task_calls(statements)

    {:ok,
     %Task{
       type: :task_supervisor,
       detection_method: :use,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :task
       }
     }}
  end

  defp extract_task_supervisor_calls(statements, opts) do
    function_calls = find_task_supervisor_calls(statements)
    first_call = List.first(function_calls)
    location = if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %Task{
       type: :task_supervisor,
       detection_method: :function_call,
       function_calls: function_calls,
       location: location,
       metadata: %{
         otp_behaviour: :task,
         call_count: length(function_calls)
       }
     }}
  end

  defp extract_call_location(meta) do
    case {Keyword.get(meta, :line), Keyword.get(meta, :column)} do
      {nil, _} -> nil
      {line, column} ->
        %ElixirOntologies.Analyzer.Location.SourceLocation{
          start_line: line,
          start_column: column || 1
        }
    end
  end
end
