defmodule ElixirOntologies.Extractors.OTP.Agent do
  @moduledoc """
  Extracts Agent usage from module AST nodes.

  This module analyzes Elixir AST nodes to detect modules implementing
  the Agent behaviour and Agent function calls.

  Supports the OTP-related classes from elixir-otp.ttl.

  ## Agent Detection

  Agent implementations can be detected via:

  1. `use Agent` - Macro invocation
  2. `@behaviour Agent` - Direct behaviour declaration
  3. `Agent.*` function calls - Direct Agent API usage

  ## Usage

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "defmodule Counter do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentExtractor.agent?(body)
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Agent Result Struct
  # ===========================================================================

  @type detection_method :: :use | :behaviour | :function_call

  @type t :: %__MODULE__{
          detection_method: detection_method() | nil,
          use_options: keyword() | nil,
          function_calls: [__MODULE__.AgentCall.t()],
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct detection_method: nil,
            use_options: nil,
            function_calls: [],
            location: nil,
            metadata: %{}

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

    defstruct function: nil,
              location: nil,
              metadata: %{}
  end

  # ===========================================================================
  # Agent Detection
  # ===========================================================================

  @doc """
  Checks if a module body implements or uses Agent.

  Returns true if the module uses Agent via `use Agent`, `@behaviour Agent`,
  or contains Agent function calls.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "defmodule Counter do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentExtractor.agent?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "defmodule Counter do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AgentExtractor.agent?(body)
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

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "use Agent"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentExtractor.use_agent?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "use GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentExtractor.use_agent?(ast)
      false
  """
  @spec use_agent?(Macro.t()) :: boolean()
  def use_agent?({:use, _meta, [{:__aliases__, _, [:Agent]} | _opts]}), do: true
  def use_agent?({:use, _meta, [Agent | _opts]}), do: true
  def use_agent?(_), do: false

  @doc """
  Checks if a single AST node is a `@behaviour Agent` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "@behaviour Agent"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentExtractor.behaviour_agent?(ast)
      true
  """
  @spec behaviour_agent?(Macro.t()) :: boolean()
  def behaviour_agent?({:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:Agent]}]}]}),
    do: true

  def behaviour_agent?({:@, _meta, [{:behaviour, _attr_meta, [Agent]}]}), do: true
  def behaviour_agent?(_), do: false

  @doc """
  Checks if a single AST node is an Agent function call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "Agent.start_link(fn -> 0 end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentExtractor.agent_call?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "Agent.get(agent, fn s -> s end)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AgentExtractor.agent_call?(ast)
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

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> code = "defmodule C do use Agent end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = AgentExtractor.extract(body)
      iex> result.detection_method
      :use
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ []) do
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

      iex> alias ElixirOntologies.Extractors.OTP.Agent, as: AgentExtractor
      iex> AgentExtractor.otp_behaviour()
      :agent
  """
  @spec otp_behaviour() :: :agent
  def otp_behaviour, do: :agent

  # ===========================================================================
  # Private Helpers
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

  defp find_agent_calls_in_statement(
         {{:., _, [{:__aliases__, _, [:Agent]}, func]}, meta, _args} = _ast
       )
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

  defp find_agent_calls_in_body(do: body), do: find_agent_calls_in_statement(body)

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
     %__MODULE__{
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
     %__MODULE__{
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

    location =
      if first_call, do: first_call.location, else: Helpers.extract_location_if(nil, opts)

    {:ok,
     %__MODULE__{
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

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [_module]}, opts]})
       when is_list(opts),
       do: opts

  defp extract_use_options({:use, _meta, [module, opts]})
       when is_atom(module) and is_list(opts),
       do: opts

  defp extract_use_options(_), do: []

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
