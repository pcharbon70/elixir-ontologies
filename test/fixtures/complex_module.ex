# Test fixture: Complex module with many constructs
defmodule ComplexModule do
  @moduledoc """
  A complex module demonstrating various Elixir constructs.
  Used for integration testing of the analyzer.
  """

  @behaviour GenServer

  alias ComplexModule.Helper
  import Enum, only: [map: 2, filter: 2]
  require Logger

  @type state :: %{count: integer(), data: list()}
  @type result :: {:ok, term()} | {:error, term()}

  @default_timeout 5000
  @max_retries 3

  defstruct [:name, :value, count: 0]

  # Public functions
  @doc "Creates a new struct"
  @spec new(String.t(), term()) :: %__MODULE__{}
  def new(name, value) do
    %__MODULE__{name: name, value: value}
  end

  @doc "Increments the count"
  def increment(%__MODULE__{count: c} = struct) do
    %{struct | count: c + 1}
  end

  def process(items) when is_list(items) do
    items
    |> filter(&valid?/1)
    |> map(&transform/1)
  end

  def process(_), do: {:error, :invalid_input}

  # Private functions
  defp valid?(item), do: item != nil

  defp transform(item) do
    case item do
      %{type: :a} -> handle_type_a(item)
      %{type: :b} -> handle_type_b(item)
      _ -> {:ok, item}
    end
  end

  defp handle_type_a(item), do: {:ok, Map.put(item, :processed, true)}
  defp handle_type_b(item), do: {:ok, Map.put(item, :processed, true)}

  # Macros
  defmacro debug(expr) do
    quote do
      result = unquote(expr)
      Logger.debug("#{inspect(unquote(Macro.to_string(expr)))} = #{inspect(result)}")
      result
    end
  end

  # Guards
  defguard is_positive(x) when is_integer(x) and x > 0

  # Callbacks
  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_cast({:set, value}, _state), do: {:noreply, value}
end
