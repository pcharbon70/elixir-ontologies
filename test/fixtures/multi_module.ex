# Test fixture: Multiple modules in one file
defmodule MultiModule.First do
  @moduledoc "First module in multi-module file"

  def hello, do: :world
end

defmodule MultiModule.Second do
  @moduledoc "Second module"

  @default_value 42

  def get_default, do: @default_value

  defp private_helper(x), do: x * 2
end

defmodule MultiModule.Third do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}
end
