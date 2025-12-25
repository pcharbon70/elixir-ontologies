defmodule ElixirOntologies.Extractors.Evolution.Commit do
  @moduledoc """
  Extracts commit metadata from Git repositories for code provenance.

  This module provides functions to extract detailed commit information
  including author, committer, message, and parent relationships. It builds
  on the existing `ElixirOntologies.Analyzer.Git` infrastructure and is
  designed for PROV-O integration.

  ## Commit vs CommitRef

  This module's `Commit` struct differs from `ElixirOntologies.Analyzer.Git.CommitRef`:

  - `CommitRef` - Lightweight reference for current HEAD, used for source URLs
  - `Commit` - Full provenance data for any commit, supports PROV-O modeling

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.Commit

      # Extract current HEAD commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      # Extract specific commit by SHA
      {:ok, commit} = Commit.extract_commit(".", "abc123...")

      # Check if it's a merge commit
      Commit.merge_commit?(commit)
      # => false

  ## Author vs Committer

  In Git, the author and committer can differ:

  - **Author**: Person who originally wrote the code
  - **Committer**: Person who created the commit (may differ during rebase, cherry-pick, etc.)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> String.length(commit.sha) == 40
      true
  """

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Extractors.Evolution.GitUtils

  # ===========================================================================
  # Commit Struct
  # ===========================================================================

  @typedoc """
  Represents a Git commit with full metadata for provenance tracking.

  ## Fields

  - `:sha` - Full 40-character SHA hash
  - `:short_sha` - 7-character abbreviated SHA
  - `:message` - Full commit message (subject + body)
  - `:subject` - First line of the commit message
  - `:body` - Message body (lines after the subject, or nil)
  - `:author_name` - Name of the person who authored the code
  - `:author_email` - Email of the author
  - `:author_date` - Timestamp when the commit was authored
  - `:committer_name` - Name of the person who committed the code
  - `:committer_email` - Email of the committer
  - `:commit_date` - Timestamp when the commit was created
  - `:parents` - List of parent commit SHAs
  - `:is_merge` - True if commit has more than one parent
  - `:tree_sha` - SHA of the tree object
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          sha: String.t(),
          short_sha: String.t(),
          message: String.t() | nil,
          subject: String.t() | nil,
          body: String.t() | nil,
          author_name: String.t() | nil,
          author_email: String.t() | nil,
          author_date: DateTime.t() | nil,
          committer_name: String.t() | nil,
          committer_email: String.t() | nil,
          commit_date: DateTime.t() | nil,
          parents: [String.t()],
          is_merge: boolean(),
          tree_sha: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:sha, :short_sha]
  defstruct [
    :sha,
    :short_sha,
    :message,
    :subject,
    :body,
    :author_name,
    :author_email,
    :author_date,
    :committer_name,
    :committer_email,
    :commit_date,
    :tree_sha,
    parents: [],
    is_merge: false,
    metadata: %{}
  ]

  # ===========================================================================
  # Constants
  # ===========================================================================

  # Delimiter for git log output parsing - unit separator character
  # We put the message (%B) at the end since it can contain any characters
  @field_delimiter "\x1f"

  # Git log format string for extracting all commit fields
  # Message (%B) is placed LAST because it can contain any characters including newlines
  # All other fields are safe (no embedded delimiters)
  @git_format [
    "%H",  # full hash
    "%h",  # abbreviated hash
    "%an", # author name
    "%ae", # author email
    "%aI", # author date (ISO 8601)
    "%cn", # committer name
    "%ce", # committer email
    "%cI", # committer date (ISO 8601)
    "%P",  # parent hashes (space-separated)
    "%T",  # tree hash
    "%B"   # full message (subject + body) - MUST BE LAST
  ]
  |> Enum.join(@field_delimiter)

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts commit information for a specific commit reference.

  The `ref` can be:
  - `"HEAD"` - current commit
  - A full 40-character SHA
  - An abbreviated SHA (at least 7 characters)
  - A branch name
  - A tag name

  ## Parameters

  - `path` - Path to the git repository (or any path within it)
  - `ref` - Commit reference (SHA, branch, tag, or "HEAD")

  ## Returns

  - `{:ok, %Commit{}}` - Successfully extracted commit
  - `{:error, :not_found}` - Repository not found
  - `{:error, :invalid_ref}` - Commit reference not found
  - `{:error, :parse_error}` - Failed to parse git output

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> is_binary(commit.sha)
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.extract_commit("/nonexistent", "HEAD")
      {:error, :not_found}
  """
  @spec extract_commit(String.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def extract_commit(path, ref \\ "HEAD") do
    with {:ok, _} <- validate_ref(ref),
         {:ok, repo_path} <- Git.detect_repo(path),
         {:ok, output} <- run_git_log(repo_path, ref) do
      parse_commit_output(output)
    end
  end

  @doc """
  Extracts commit information, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = Commit.extract_commit!(".", "HEAD")
      iex> %ElixirOntologies.Extractors.Evolution.Commit{} = commit
  """
  @spec extract_commit!(String.t(), String.t()) :: t()
  def extract_commit!(path, ref \\ "HEAD") do
    case extract_commit(path, ref) do
      {:ok, commit} -> commit
      {:error, reason} -> raise ArgumentError, "Failed to extract commit: #{GitUtils.format_error(reason)}"
    end
  end

  @doc """
  Extracts multiple commits from the repository.

  ## Options

  - `:limit` - Maximum number of commits to return (default: 10, max: #{GitUtils.max_commits()})
  - `:offset` - Number of commits to skip (default: 0)
  - `:from` - Starting commit reference (default: "HEAD")

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> {:ok, commits} = Commit.extract_commits(".", limit: 5)
      iex> is_list(commits)
      true
  """
  @spec extract_commits(String.t(), keyword()) :: {:ok, [t()]} | {:error, atom()}
  def extract_commits(path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    offset = Keyword.get(opts, :offset, 0)
    from = Keyword.get(opts, :from, "HEAD")

    # Enforce maximum limit
    effective_limit = min(limit, GitUtils.max_commits())

    with {:ok, _} <- validate_ref(from),
         {:ok, repo_path} <- Git.detect_repo(path),
         {:ok, output} <- run_git_log_multi(repo_path, from, effective_limit, offset) do
      parse_commits_output(output)
    end
  end

  @doc """
  Extracts multiple commits, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commits = Commit.extract_commits!(".", limit: 5)
      iex> is_list(commits)
      true
  """
  @spec extract_commits!(String.t(), keyword()) :: [t()]
  def extract_commits!(path, opts \\ []) do
    case extract_commits(path, opts) do
      {:ok, commits} -> commits
      {:error, reason} -> raise ArgumentError, "Failed to extract commits: #{GitUtils.format_error(reason)}"
    end
  end

  # ===========================================================================
  # Validation Functions
  # ===========================================================================

  @doc """
  Validates if a string is a valid full SHA (40 hex characters).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.valid_sha?("abc123def456abc123def456abc123def456abc1")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.valid_sha?("abc123")
      false

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.valid_sha?("not-a-sha")
      false
  """
  @spec valid_sha?(any()) :: boolean()
  def valid_sha?(sha), do: GitUtils.valid_sha?(sha)

  @doc """
  Validates if a string is a valid short SHA (7-40 hex characters).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.valid_short_sha?("abc123d")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.valid_short_sha?("abc12")
      false
  """
  @spec valid_short_sha?(any()) :: boolean()
  def valid_short_sha?(sha), do: GitUtils.valid_short_sha?(sha)

  @doc """
  Checks if a commit is a merge commit (has multiple parents).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = %Commit{sha: "abc123...", short_sha: "abc123d", parents: ["p1", "p2"], is_merge: true}
      iex> Commit.merge_commit?(commit)
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = %Commit{sha: "abc123...", short_sha: "abc123d", parents: ["p1"], is_merge: false}
      iex> Commit.merge_commit?(commit)
      false
  """
  @spec merge_commit?(t()) :: boolean()
  def merge_commit?(%__MODULE__{is_merge: is_merge}), do: is_merge

  @doc """
  Checks if a commit is the initial commit (has no parents).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = %Commit{sha: "abc123...", short_sha: "abc123d", parents: []}
      iex> Commit.initial_commit?(commit)
      true
  """
  @spec initial_commit?(t()) :: boolean()
  def initial_commit?(%__MODULE__{parents: []}), do: true
  def initial_commit?(%__MODULE__{}), do: false

  # ===========================================================================
  # Message Parsing Helpers
  # ===========================================================================

  @doc """
  Extracts the subject line from a commit message.

  The subject is the first line of the commit message.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.extract_subject("Add new feature\\n\\nThis is the body")
      "Add new feature"

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.extract_subject("Single line message")
      "Single line message"
  """
  @spec extract_subject(String.t() | nil) :: String.t() | nil
  def extract_subject(nil), do: nil

  def extract_subject(message) when is_binary(message) do
    message
    |> String.split("\n", parts: 2)
    |> List.first()
    |> case do
      nil -> nil
      subject -> String.trim(subject)
    end
  end

  @doc """
  Extracts the body from a commit message.

  The body is everything after the first blank line following the subject.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.extract_body("Subject\\n\\nThis is the body\\nWith multiple lines")
      "This is the body\\nWith multiple lines"

      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> Commit.extract_body("Single line message")
      nil
  """
  @spec extract_body(String.t() | nil) :: String.t() | nil
  def extract_body(nil), do: nil

  def extract_body(message) when is_binary(message) do
    case String.split(message, ~r/\n\s*\n/, parts: 2) do
      [_subject, body] ->
        trimmed = String.trim(body)
        if trimmed == "", do: nil, else: trimmed

      [_single] ->
        nil
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp validate_ref(ref) do
    if GitUtils.valid_ref?(ref) do
      {:ok, ref}
    else
      {:error, :invalid_ref}
    end
  end

  defp run_git_log(repo_path, ref) do
    args = ["log", "-1", "--format=#{@git_format}", ref]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} -> {:ok, output}
      {:error, :command_failed} -> {:error, :invalid_ref}
      {:error, :timeout} -> {:error, :timeout}
    end
  end

  defp run_git_log_multi(repo_path, from, limit, offset) do
    # Use commit separator for parsing multiple commits
    format_with_separator = @git_format <> "\x1e"
    args = ["log", "--format=#{format_with_separator}", "-n", "#{limit + offset}", from]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} -> {:ok, output}
      {:error, :command_failed} -> {:error, :invalid_ref}
      {:error, :timeout} -> {:error, :timeout}
    end
  end

  defp parse_commit_output(output) do
    # Split on the delimiter, but only the first 10 fields (message is last and may contain delimiter)
    # Field order: sha, short_sha, author_name, author_email, author_date,
    #              committer_name, committer_email, commit_date, parents, tree_sha, message
    fields = String.split(String.trim(output), @field_delimiter, parts: 11)

    case fields do
      [sha, short_sha, author_name, author_email, author_date,
       committer_name, committer_email, commit_date, parents_str, tree_sha, message] ->
        parents = parse_parents(parents_str)
        trimmed_message = String.trim(message)
        subject = extract_subject(trimmed_message)
        body = extract_body(trimmed_message)

        {:ok,
         %__MODULE__{
           sha: sha,
           short_sha: short_sha,
           message: empty_to_nil(trimmed_message),
           subject: subject,
           body: body,
           author_name: empty_to_nil(author_name),
           author_email: empty_to_nil(author_email),
           author_date: parse_datetime(author_date),
           committer_name: empty_to_nil(committer_name),
           committer_email: empty_to_nil(committer_email),
           commit_date: parse_datetime(commit_date),
           parents: parents,
           is_merge: length(parents) > 1,
           tree_sha: empty_to_nil(tree_sha),
           metadata: %{}
         }}

      _ ->
        {:error, :parse_error}
    end
  end

  defp parse_commits_output(output) do
    # Split by record separator and parse each commit
    commits =
      output
      |> String.split("\x1e", trim: true)
      |> Enum.map(&parse_commit_output/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, commit} -> commit end)

    {:ok, commits}
  end

  defp parse_parents(""), do: []

  defp parse_parents(parents_str) do
    parents_str
    |> String.split(" ", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&valid_sha?/1)
  end

  defp parse_datetime(""), do: nil
  defp parse_datetime(date_str), do: GitUtils.parse_iso8601_datetime!(date_str)

  defp empty_to_nil(str), do: GitUtils.empty_to_nil(str)
end
