defmodule ElixirOntologies.Extractors.Evolution.GitUtils do
  @moduledoc """
  Shared utilities for Git operations across evolution extractors.

  This module provides common functionality for:
  - Git command execution with timeout and error handling
  - SHA and reference validation
  - Path validation and normalization
  - DateTime parsing from git output
  - Email anonymization for privacy

  ## Security

  All functions that accept user input perform validation to prevent
  command injection and path traversal attacks.

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.GitUtils

      # Run a git command with timeout
      {:ok, output} = GitUtils.run_git_command(".", ["log", "-1"])

      # Validate references
      GitUtils.valid_sha?("abc123def456...")
      GitUtils.valid_ref?("HEAD")

      # Safe path handling
      {:ok, relative} = GitUtils.normalize_file_path("lib/foo.ex", "/repo")
  """

  alias ElixirOntologies.Utils.IdGenerator

  # ===========================================================================
  # Constants
  # ===========================================================================

  @default_timeout 30_000
  @max_commits 10_000

  @sha_regex ~r/^[0-9a-f]{40}$/i
  @short_sha_regex ~r/^[0-9a-f]{7,40}$/i
  @uncommitted_sha "0000000000000000000000000000000000000000"

  # ===========================================================================
  # Git Command Execution
  # ===========================================================================

  @doc """
  Runs a git command with timeout and error handling.

  ## Options

  - `:timeout` - Command timeout in milliseconds (default: 30000)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> {:ok, output} = GitUtils.run_git_command(".", ["rev-parse", "HEAD"])
      iex> String.length(String.trim(output)) == 40
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.run_git_command("/nonexistent", ["status"])
      {:error, :command_failed}
  """
  @spec run_git_command(String.t(), [String.t()], keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def run_git_command(repo_path, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    task =
      Task.async(fn ->
        try do
          case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
            {output, 0} -> {:ok, output}
            {_output, _code} -> {:error, :command_failed}
          end
        rescue
          _ -> {:error, :command_failed}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Returns the default command timeout in milliseconds.
  """
  @spec default_timeout() :: pos_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Returns the maximum number of commits to fetch.
  """
  @spec max_commits() :: pos_integer()
  def max_commits, do: @max_commits

  # ===========================================================================
  # SHA Validation
  # ===========================================================================

  @doc """
  Validates a full 40-character SHA hash.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_sha?("abc123def456abc123def456abc123def456abc1")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_sha?("abc123")
      false

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_sha?("not-a-sha")
      false
  """
  @spec valid_sha?(any()) :: boolean()
  def valid_sha?(sha) when is_binary(sha) do
    Regex.match?(@sha_regex, sha)
  end

  def valid_sha?(_), do: false

  @doc """
  Validates a short SHA (7-40 characters).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_short_sha?("abc123d")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_short_sha?("abc12")
      false
  """
  @spec valid_short_sha?(any()) :: boolean()
  def valid_short_sha?(sha) when is_binary(sha) do
    Regex.match?(@short_sha_regex, sha)
  end

  def valid_short_sha?(_), do: false

  @doc """
  Checks if a SHA represents uncommitted changes.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.uncommitted_sha?("0000000000000000000000000000000000000000")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.uncommitted_sha?("abc123def456abc123def456abc123def456abc1")
      false
  """
  @spec uncommitted_sha?(String.t()) :: boolean()
  def uncommitted_sha?(sha), do: sha == @uncommitted_sha

  @doc """
  Returns the SHA used for uncommitted changes.
  """
  @spec uncommitted_sha() :: String.t()
  def uncommitted_sha, do: @uncommitted_sha

  # ===========================================================================
  # Reference Validation
  # ===========================================================================

  @doc """
  Validates a git reference (SHA, HEAD, branch name, tag).

  Prevents command injection by only allowing safe patterns.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_ref?("HEAD")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_ref?("main")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_ref?("abc123def456abc123def456abc123def456abc1")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.valid_ref?("HEAD; rm -rf /")
      false
  """
  @spec valid_ref?(any()) :: boolean()
  def valid_ref?(ref) when is_binary(ref) do
    Enum.any?(safe_ref_patterns(), &Regex.match?(&1, ref))
  end

  def valid_ref?(_), do: false

  # Safe ref patterns - HEAD, branch names, tags, commit SHAs
  # Defined as a function to avoid compile-time escaping issues with Regex references
  defp safe_ref_patterns do
    [
      ~r/^HEAD$/,
      ~r/^HEAD~\d+$/,
      ~r/^HEAD\^\d*$/,
      ~r/^[0-9a-f]{7,40}$/i,
      ~r/^refs\/(heads|tags|remotes)\/[a-zA-Z0-9_\-\.\/]+$/,
      ~r/^[a-zA-Z][a-zA-Z0-9_\-\.]*$/
    ]
  end

  # ===========================================================================
  # Path Validation
  # ===========================================================================

  @doc """
  Checks if a file path is safe (no path traversal).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.safe_path?("lib/my_module.ex")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.safe_path?("../../../etc/passwd")
      false

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.safe_path?("lib/../etc/passwd")
      false
  """
  @spec safe_path?(any()) :: boolean()
  def safe_path?(path) when is_binary(path) do
    # Check for path traversal attempts
    not String.contains?(path, "..") and
      not String.contains?(path, "\x00") and
      not String.starts_with?(path, "/") and
      not String.contains?(path, "//")
  end

  def safe_path?(_), do: false

  @doc """
  Normalizes a file path relative to a repository root.

  Validates the path is safe and within the repository.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.normalize_file_path("lib/foo.ex", "/repo")
      {:ok, "lib/foo.ex"}

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.normalize_file_path("../secret", "/repo")
      {:error, :invalid_path}
  """
  @spec normalize_file_path(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_path | :outside_repo}
  def normalize_file_path(file_path, repo_root) do
    cond do
      # Check for path traversal in relative paths
      not safe_path?(file_path) and Path.type(file_path) == :relative ->
        {:error, :invalid_path}

      # Handle absolute paths
      Path.type(file_path) == :absolute ->
        case Path.relative_to(file_path, repo_root) do
          ^file_path -> {:error, :outside_repo}
          relative -> validate_relative_path(relative)
        end

      # Validate relative paths
      true ->
        validate_relative_path(file_path)
    end
  end

  defp validate_relative_path(path) do
    if safe_path?(path) do
      {:ok, path}
    else
      {:error, :invalid_path}
    end
  end

  # ===========================================================================
  # DateTime Parsing
  # ===========================================================================

  @doc """
  Parses an ISO 8601 datetime string safely.

  Returns nil if parsing fails.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> {:ok, dt} = GitUtils.parse_iso8601_datetime("2024-01-15T10:30:00Z")
      iex> dt.year
      2024

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.parse_iso8601_datetime("invalid")
      {:error, :invalid_datetime}
  """
  @spec parse_iso8601_datetime(String.t()) :: {:ok, DateTime.t()} | {:error, :invalid_datetime}
  def parse_iso8601_datetime(date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(String.trim(date_str)) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_datetime}
    end
  end

  def parse_iso8601_datetime(_), do: {:error, :invalid_datetime}

  @doc """
  Parses an ISO 8601 datetime string, returning nil on failure.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> dt = GitUtils.parse_iso8601_datetime!(" 2024-01-15T10:30:00Z ")
      iex> dt.year
      2024

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.parse_iso8601_datetime!("invalid")
      nil
  """
  @spec parse_iso8601_datetime!(String.t()) :: DateTime.t() | nil
  def parse_iso8601_datetime!(date_str) do
    case parse_iso8601_datetime(date_str) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  @doc """
  Parses a Unix timestamp to DateTime.

  Returns nil if parsing fails.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> {:ok, dt} = GitUtils.parse_unix_timestamp(1705315800)
      iex> dt.year
      2024

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.parse_unix_timestamp(nil)
      {:error, :invalid_timestamp}
  """
  @spec parse_unix_timestamp(integer() | nil) ::
          {:ok, DateTime.t()} | {:error, :invalid_timestamp}
  def parse_unix_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, dt} -> {:ok, dt}
      _ -> {:error, :invalid_timestamp}
    end
  end

  def parse_unix_timestamp(_), do: {:error, :invalid_timestamp}

  @doc """
  Parses a Unix timestamp, returning nil on failure.
  """
  @spec parse_unix_timestamp!(integer() | nil) :: DateTime.t() | nil
  def parse_unix_timestamp!(timestamp) do
    case parse_unix_timestamp(timestamp) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  # ===========================================================================
  # String Utilities
  # ===========================================================================

  @doc """
  Converts empty strings to nil.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.empty_to_nil("")
      nil

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.empty_to_nil("hello")
      "hello"
  """
  @spec empty_to_nil(String.t()) :: String.t() | nil
  def empty_to_nil(""), do: nil
  def empty_to_nil(str), do: str

  # ===========================================================================
  # Email Anonymization
  # ===========================================================================

  @doc """
  Anonymizes an email address using SHA256 hashing.

  Useful for privacy-sensitive contexts (GDPR compliance).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> hash = GitUtils.anonymize_email("user@example.com")
      iex> String.length(hash) == 64
      true

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.anonymize_email(nil)
      nil
  """
  @spec anonymize_email(String.t() | nil) :: String.t() | nil
  def anonymize_email(nil), do: nil

  def anonymize_email(email) when is_binary(email) do
    IdGenerator.full_hash(email)
  end

  @doc """
  Conditionally anonymizes an email based on options.

  ## Options

  - `:anonymize_emails` - If true, hash the email (default: false)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> GitUtils.maybe_anonymize_email("user@example.com", anonymize_emails: false)
      "user@example.com"

      iex> alias ElixirOntologies.Extractors.Evolution.GitUtils
      iex> hash = GitUtils.maybe_anonymize_email("user@example.com", anonymize_emails: true)
      iex> String.length(hash) == 64
      true
  """
  @spec maybe_anonymize_email(String.t() | nil, keyword()) :: String.t() | nil
  def maybe_anonymize_email(email, opts \\ []) do
    if Keyword.get(opts, :anonymize_emails, false) do
      anonymize_email(email)
    else
      email
    end
  end

  # ===========================================================================
  # Error Helpers
  # ===========================================================================

  @typedoc """
  Standard error atoms used across evolution extractors.

  - `:repo_not_found` - Repository path doesn't exist
  - `:invalid_ref` - Invalid git reference
  - `:invalid_path` - Invalid or unsafe file path
  - `:outside_repo` - Path is outside repository
  - `:file_not_found` - File doesn't exist
  - `:file_not_tracked` - File not in git history
  - `:command_failed` - Git command failed
  - `:parse_error` - Failed to parse git output
  - `:timeout` - Command timed out
  """
  @type error_reason ::
          :repo_not_found
          | :invalid_ref
          | :invalid_path
          | :outside_repo
          | :file_not_found
          | :file_not_tracked
          | :command_failed
          | :parse_error
          | :timeout

  @doc """
  Formats an error reason for display.
  """
  @spec format_error(error_reason()) :: String.t()
  def format_error(:repo_not_found), do: "Repository not found"
  def format_error(:invalid_ref), do: "Invalid git reference"
  def format_error(:invalid_path), do: "Invalid or unsafe file path"
  def format_error(:outside_repo), do: "Path is outside repository"
  def format_error(:file_not_found), do: "File not found"
  def format_error(:file_not_tracked), do: "File not tracked in git"
  def format_error(:command_failed), do: "Git command failed"
  def format_error(:parse_error), do: "Failed to parse git output"
  def format_error(:timeout), do: "Command timed out"
  def format_error(other), do: "Unknown error: #{inspect(other)}"
end
