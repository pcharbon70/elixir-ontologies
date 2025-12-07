defmodule ElixirOntologies.Analyzer.Git.Adapter do
  @moduledoc """
  Behaviour for git command execution.

  This module defines a behaviour for running git commands, allowing for
  different implementations (system commands, libgit2 bindings, mocks, etc.).

  ## Usage

  The default implementation uses `System.cmd/3`:

      # Using default adapter
      Git.Adapter.run_command("/path/to/repo", ["status"])

  For testing, you can implement a mock adapter:

      defmodule MyApp.MockGitAdapter do
        @behaviour Git.Adapter

        @impl true
        def run_command(_repo_path, ["status"]) do
          {:ok, "On branch main\\nnothing to commit"}
        end
      end

  ## Configuration

      config :elixir_ontologies, Git.Adapter,
        implementation: MyApp.MockGitAdapter,
        timeout: 10_000
  """

  @type command_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Runs a git command in the specified repository.

  ## Parameters

  - `repo_path` - The path to the git repository
  - `args` - List of arguments to pass to git
  - `opts` - Options (implementation-specific)

  ## Returns

  - `{:ok, output}` - Command succeeded with output
  - `{:error, reason}` - Command failed
  """
  @callback run_command(repo_path :: String.t(), args :: [String.t()], opts :: keyword()) ::
              command_result()

  @doc """
  Runs a git command with default options.
  """
  @callback run_command(repo_path :: String.t(), args :: [String.t()]) :: command_result()

  @optional_callbacks [run_command: 2]

  # ===========================================================================
  # Default Implementation
  # ===========================================================================

  @doc """
  Runs a git command using the configured adapter.

  Falls back to the default System.cmd implementation if no adapter is configured.
  """
  @spec run_command(String.t(), [String.t()], keyword()) :: command_result()
  def run_command(repo_path, args, opts \\ []) do
    adapter = get_adapter()
    adapter.run_command(repo_path, args, opts)
  end

  @doc """
  Returns the configured git adapter module.
  """
  @spec get_adapter() :: module()
  def get_adapter do
    Application.get_env(:elixir_ontologies, __MODULE__, [])[:implementation] ||
      ElixirOntologies.Analyzer.Git.Adapter.System
  end
end

defmodule ElixirOntologies.Analyzer.Git.Adapter.System do
  @moduledoc """
  Default git adapter using System.cmd/3.

  This is the default implementation that executes git commands
  as system subprocesses.
  """

  @behaviour ElixirOntologies.Analyzer.Git.Adapter

  @default_timeout 30_000

  @impl true
  def run_command(repo_path, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, get_default_timeout())

    cmd_opts = [
      cd: repo_path,
      stderr_to_stdout: true
    ]

    # Add timeout if supported (OTP 26+)
    cmd_opts =
      if function_exported?(System, :cmd, 4) do
        Keyword.put(cmd_opts, :timeout, timeout)
      else
        cmd_opts
      end

    try do
      case System.cmd("git", args, cmd_opts) do
        {output, 0} -> {:ok, output}
        {_output, _code} -> {:error, :command_failed}
      end
    rescue
      e in ErlangError ->
        case e.original do
          :timeout -> {:error, :timeout}
          _ -> {:error, {:system_error, e.original}}
        end
    end
  end

  defp get_default_timeout do
    Application.get_env(:elixir_ontologies, ElixirOntologies.Analyzer.Git.Adapter, [])[:timeout] ||
      @default_timeout
  end
end
