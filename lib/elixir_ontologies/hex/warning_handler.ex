defmodule ElixirOntologies.Hex.WarningHandler do
  @moduledoc """
  Logger backend handler that tracks warning-level logs.

  Used to halt batch processing when warnings are detected.
  """

  use GenServer

  @doc """
  Starts the warning handler.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops the warning handler.
  """
  @spec stop(pid() | atom()) :: :ok
  def stop(pid \\ __MODULE__) do
    GenServer.stop(pid)
  end

  @doc """
  Checks if any warnings have been detected.
  """
  @spec warning_detected?(pid() | atom()) :: boolean()
  def warning_detected?(pid \\ __MODULE__) do
    GenServer.call(pid, :warning_detected?)
  end

  @doc """
  Resets the warning state.
  """
  @spec reset(pid() | atom()) :: :ok
  def reset(pid \\ __MODULE__) do
    GenServer.call(pid, :reset)
  end

  @doc """
  Installs the Logger handler that forwards warnings to this process.
  """
  @spec install_logger_handler(pid() | atom()) :: {:ok, term()} | {:error, term()}
  def install_logger_handler(pid \\ __MODULE__) do
    # Use a fixed handler name - we only run one WarningHandler at a time
    handler_id = :elixir_ontologies_warning_handler

    :logger.add_handler(handler_id, __MODULE__, %{
      formatter: {__MODULE__, :format},
      handler: pid
    })
  end

  @doc """
  Removes the Logger handler.
  """
  @spec remove_logger_handler() :: :ok
  def remove_logger_handler do
    :logger.remove_handler(:elixir_ontologies_warning_handler)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{warning_detected: false}}
  end

  @impl true
  def handle_call(:warning_detected?, _from, state) do
    {:reply, state.warning_detected, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | warning_detected: false}}
  end

  @impl true
  def handle_info({:warning, _msg}, state) do
    {:noreply, %{state | warning_detected: true}}
  end

  # Logger handler callbacks

  def format(_log_event, %{handler: _handler_pid}) do
    # Return format that won't be printed (we want original formatter to handle it)
    :none
  end

  def log(%{level: :warning} = event, %{handler: handler_pid}) do
    # Forward warning to our GenServer
    send(handler_pid, {:warning, event})
    # Return original event so default formatter still prints it
    event
  end

  def log(event, _config) do
    # Pass through all other log levels
    event
  end
end
