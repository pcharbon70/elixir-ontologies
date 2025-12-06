defmodule ElixirOntologies.Extractors.OTP.Task do
  @moduledoc """
  Extracts Task usage from module AST nodes.

  This module analyzes Elixir AST nodes to detect:
  - Task function calls (Task.async, Task.start, etc.)
  - Task.Supervisor usage

  Supports the OTP-related classes from elixir-otp.ttl.

  ## Task Detection

  Task usage is detected via function calls:

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.task_call?(ast)
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Task Result Struct
  # ===========================================================================

  @type task_type :: :task | :task_supervisor

  @type t :: %__MODULE__{
          type: task_type(),
          detection_method: :use | :function_call | nil,
          function_calls: [__MODULE__.TaskCall.t()],
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

  # ===========================================================================
  # Task Call Struct
  # ===========================================================================

  defmodule TaskCall do
    @moduledoc """
    Represents a single Task function call.
    """

    @type function_name ::
            :async | :start | :start_link | :await | :yield | :yield_many | :async_stream |
            :async_nolink

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
  # Task Detection
  # ===========================================================================

  @doc """
  Checks if a module body contains Task usage.

  Returns true if the module contains Task function calls or uses Task.Supervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.task?(ast)
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

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.async(fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.task_call?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.await(task)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.task_call?(ast)
      true
  """
  @spec task_call?(Macro.t()) :: boolean()
  def task_call?({{:., _, [{:__aliases__, _, [:Task]}, func]}, _, _args})
      when func in [
             :async,
             :start,
             :start_link,
             :await,
             :yield,
             :yield_many,
             :async_stream,
             :async_nolink
           ],
      do: true

  def task_call?(_), do: false

  @doc """
  Checks if a single AST node is a `use Task.Supervisor` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "use Task.Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.use_task_supervisor?(ast)
      true
  """
  @spec use_task_supervisor?(Macro.t()) :: boolean()
  def use_task_supervisor?({:use, _meta, [{:__aliases__, _, [:Task, :Supervisor]} | _opts]}),
    do: true

  def use_task_supervisor?(_), do: false

  @doc """
  Checks if a single AST node is a Task.Supervisor function call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.Supervisor.async(sup, fn -> :ok end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> TaskExtractor.task_supervisor_call?(ast)
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

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "Task.async(fn -> :result end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = TaskExtractor.extract(ast)
      iex> result.type
      :task
      iex> length(result.function_calls)
      1
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ []) do
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

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> code = "defmodule S do use Task.Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> TaskExtractor.task_supervisor?(body)
      true
  """
  @spec task_supervisor?(Macro.t()) :: boolean()
  def task_supervisor?(body) do
    statements = Helpers.normalize_body(body)

    uses_task_supervisor?(statements) or
      has_task_supervisor_calls?(statements)
  end

  @doc """
  Returns the OTP behaviour type for Task extractor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Task, as: TaskExtractor
      iex> TaskExtractor.otp_behaviour()
      :task
  """
  @spec otp_behaviour() :: :task
  def otp_behaviour, do: :task

  # ===========================================================================
  # Private Helpers
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
       when func in [
              :async,
              :start,
              :start_link,
              :await,
              :yield,
              :yield_many,
              :async_stream,
              :async_nolink
            ] do
    [
      %TaskCall{
        function: func,
        supervised: false,
        location: extract_call_location(meta),
        metadata: %{}
      }
    ]
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

  defp find_task_supervisor_calls_in_statement(
         {{:., _, [{:__aliases__, _, [:Task, :Supervisor]}, func]}, meta, _args}
       )
       when func in [:async, :async_nolink, :start_child, :start_link] do
    [
      %TaskCall{
        function: func,
        supervised: true,
        location: extract_call_location(meta),
        metadata: %{}
      }
    ]
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

  defp find_task_supervisor_calls_in_body([do: body]),
    do: find_task_supervisor_calls_in_statement(body)

  defp find_task_supervisor_calls_in_body({:__block__, _, statements}) do
    Enum.flat_map(statements, &find_task_supervisor_calls_in_statement/1)
  end

  defp find_task_supervisor_calls_in_body(body), do: find_task_supervisor_calls_in_statement(body)

  defp extract_task_calls(statements, opts) do
    function_calls = find_task_calls(statements)
    first_call = List.first(function_calls)

    location =
      if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %__MODULE__{
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
     %__MODULE__{
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

    location =
      if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %__MODULE__{
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
      {nil, _} ->
        nil

      {line, column} ->
        %ElixirOntologies.Analyzer.Location.SourceLocation{
          start_line: line,
          start_column: column || 1
        }
    end
  end
end
