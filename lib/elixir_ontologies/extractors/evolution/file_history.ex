defmodule ElixirOntologies.Extractors.Evolution.FileHistory do
  @moduledoc """
  Extracts file history from Git repositories.

  This module provides functions to extract the history of changes to individual
  files, including tracking commits that modified each file, detecting renames
  and moves, and building a chronological change list.

  ## Rename Tracking

  Git tracks file renames using similarity detection. When a file is renamed,
  this module tracks:
  - The original path
  - The new path
  - The commit where the rename occurred
  - The similarity percentage (if available)

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.FileHistory

      # Extract history for a file
      {:ok, history} = FileHistory.extract_file_history(".", "lib/my_module.ex")

      # Check if file was renamed
      FileHistory.renamed?(history)

      # Get original path
      FileHistory.original_path(history)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")
      iex> is_integer(history.commit_count)
      true
  """

  alias ElixirOntologies.Analyzer.Git

  # ===========================================================================
  # Rename Struct
  # ===========================================================================

  defmodule Rename do
    @moduledoc """
    Represents a file rename or move operation.
    """

    @type t :: %__MODULE__{
            from_path: String.t(),
            to_path: String.t(),
            commit_sha: String.t(),
            similarity: non_neg_integer() | nil
          }

    @enforce_keys [:from_path, :to_path, :commit_sha]
    defstruct [
      :from_path,
      :to_path,
      :commit_sha,
      :similarity
    ]
  end

  # ===========================================================================
  # FileHistory Struct
  # ===========================================================================

  @typedoc """
  Represents the complete history of a file.

  ## Fields

  - `:path` - Current file path
  - `:original_path` - Original path if file was renamed (nil otherwise)
  - `:commits` - List of commit SHAs that modified this file (newest first)
  - `:renames` - List of Rename structs (oldest to newest)
  - `:first_commit` - SHA of the first commit that created the file
  - `:last_commit` - SHA of the most recent commit
  - `:commit_count` - Total number of commits that touched this file
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          path: String.t(),
          original_path: String.t() | nil,
          commits: [String.t()],
          renames: [Rename.t()],
          first_commit: String.t() | nil,
          last_commit: String.t() | nil,
          commit_count: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [:path]
  defstruct [
    :path,
    :original_path,
    :first_commit,
    :last_commit,
    commits: [],
    renames: [],
    commit_count: 0,
    metadata: %{}
  ]

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts the complete history of a file.

  Uses `git log --follow` to track file history across renames.

  ## Options

  - `:follow` - Follow file renames (default: true)
  - `:limit` - Maximum number of commits to retrieve (default: nil = all)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")
      iex> history.path
      "mix.exs"

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> FileHistory.extract_file_history(".", "nonexistent_file.ex")
      {:error, :file_not_tracked}
  """
  @spec extract_file_history(String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, atom()}
  def extract_file_history(repo_path, file_path, opts \\ []) do
    follow = Keyword.get(opts, :follow, true)
    limit = Keyword.get(opts, :limit)

    with {:ok, repo_root} <- Git.detect_repo(repo_path),
         {:ok, relative_path} <- normalize_file_path(file_path, repo_root),
         {:ok, commits} <- extract_commits_for_file(repo_root, relative_path, follow, limit),
         {:ok, renames} <- extract_renames(repo_root, relative_path) do
      if commits == [] do
        {:error, :file_not_tracked}
      else
        original = find_original_path(renames, relative_path)

        {:ok,
         %__MODULE__{
           path: relative_path,
           original_path: original,
           commits: commits,
           renames: renames,
           first_commit: List.last(commits),
           last_commit: List.first(commits),
           commit_count: length(commits),
           metadata: %{}
         }}
      end
    end
  end

  @doc """
  Extracts file history, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = FileHistory.extract_file_history!(".", "mix.exs")
      iex> %ElixirOntologies.Extractors.Evolution.FileHistory{} = history
  """
  @spec extract_file_history!(String.t(), String.t(), keyword()) :: t()
  def extract_file_history!(repo_path, file_path, opts \\ []) do
    case extract_file_history(repo_path, file_path, opts) do
      {:ok, history} -> history
      {:error, reason} -> raise ArgumentError, "Failed to extract file history: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts commit SHAs that modified a file.

  Returns commits in reverse chronological order (newest first).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> {:ok, commits} = FileHistory.extract_commits_for_file(".", "mix.exs")
      iex> is_list(commits)
      true
  """
  @spec extract_commits_for_file(String.t(), String.t(), boolean(), non_neg_integer() | nil) ::
          {:ok, [String.t()]} | {:error, atom()}
  def extract_commits_for_file(repo_path, file_path, follow \\ true, limit \\ nil) do
    args = build_log_args(follow, limit) ++ ["--", file_path]

    case run_git_command(repo_path, args) do
      {:ok, output} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&valid_sha?/1)

        {:ok, commits}

      {:error, _} ->
        {:ok, []}
    end
  end

  @doc """
  Extracts rename history for a file.

  Returns a list of Rename structs in chronological order (oldest first).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> {:ok, renames} = FileHistory.extract_renames(".", "mix.exs")
      iex> is_list(renames)
      true
  """
  @spec extract_renames(String.t(), String.t()) :: {:ok, [Rename.t()]} | {:error, atom()}
  def extract_renames(repo_path, file_path) do
    # Use --name-status with --follow to detect renames
    # Format: commit_sha, then status lines
    args = ["log", "--format=%H", "--name-status", "--follow", "--diff-filter=R", "--", file_path]

    case run_git_command(repo_path, args) do
      {:ok, output} ->
        renames = parse_rename_output(output)
        {:ok, renames}

      {:error, _} ->
        {:ok, []}
    end
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Checks if a file exists in the git history.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> FileHistory.file_exists_in_history?(".", "mix.exs")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> FileHistory.file_exists_in_history?(".", "nonexistent_xyz.ex")
      false
  """
  @spec file_exists_in_history?(String.t(), String.t()) :: boolean()
  def file_exists_in_history?(repo_path, file_path) do
    case extract_file_history(repo_path, file_path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Checks if a file was renamed at any point in its history.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "new.ex", renames: [%FileHistory.Rename{from_path: "old.ex", to_path: "new.ex", commit_sha: "abc"}]}
      iex> FileHistory.renamed?(history)
      true

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "file.ex", renames: []}
      iex> FileHistory.renamed?(history)
      false
  """
  @spec renamed?(t()) :: boolean()
  def renamed?(%__MODULE__{renames: renames}), do: renames != []

  @doc """
  Gets the original path of a file if it was renamed.

  Returns nil if the file was never renamed.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "new.ex", original_path: "old.ex"}
      iex> FileHistory.original_path(history)
      "old.ex"

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "file.ex", original_path: nil}
      iex> FileHistory.original_path(history)
      nil
  """
  @spec original_path(t()) :: String.t() | nil
  def original_path(%__MODULE__{original_path: path}), do: path

  @doc """
  Gets the number of times a file was renamed.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "file.ex", renames: [%FileHistory.Rename{from_path: "a", to_path: "b", commit_sha: "1"}, %FileHistory.Rename{from_path: "b", to_path: "c", commit_sha: "2"}]}
      iex> FileHistory.rename_count(history)
      2
  """
  @spec rename_count(t()) :: non_neg_integer()
  def rename_count(%__MODULE__{renames: renames}), do: length(renames)

  @doc """
  Gets the path at a specific commit.

  Traces through rename history to find the path at the given commit.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.FileHistory
      iex> history = %FileHistory{path: "current.ex", renames: []}
      iex> FileHistory.path_at_commit(history, "any_sha")
      "current.ex"
  """
  @spec path_at_commit(t(), String.t()) :: String.t()
  def path_at_commit(%__MODULE__{path: current_path, renames: []}, _commit_sha) do
    current_path
  end

  def path_at_commit(%__MODULE__{path: current_path, renames: renames, commits: commits}, commit_sha) do
    # Find where this commit is in history
    commit_index = Enum.find_index(commits, &(&1 == commit_sha))

    if is_nil(commit_index) do
      current_path
    else
      # Trace through renames to find the path at this commit
      # Renames are in chronological order, commits are reverse chronological
      trace_path_at_index(current_path, renames, commits, commit_index)
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp normalize_file_path(file_path, repo_root) do
    # Convert to relative path if absolute
    if Path.type(file_path) == :absolute do
      case Path.relative_to(file_path, repo_root) do
        ^file_path -> {:error, :outside_repo}
        relative -> {:ok, relative}
      end
    else
      {:ok, file_path}
    end
  end

  defp build_log_args(follow, limit) do
    base = ["log", "--format=%H"]

    base =
      if follow do
        base ++ ["--follow"]
      else
        base
      end

    if limit do
      base ++ ["-n", "#{limit}"]
    else
      base
    end
  end

  defp run_git_command(repo_path, args) do
    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _code} -> {:error, :command_failed}
    end
  end

  defp valid_sha?(sha) when is_binary(sha) do
    String.length(sha) == 40 and Regex.match?(~r/^[0-9a-f]+$/i, sha)
  end

  defp valid_sha?(_), do: false

  defp parse_rename_output(output) do
    # Output format:
    # <commit_sha>
    # R<similarity>\t<old_path>\t<new_path>
    # <commit_sha>
    # R<similarity>\t<old_path>\t<new_path>
    # ...

    lines = String.split(output, "\n", trim: true)
    parse_rename_lines(lines, nil, [])
  end

  defp parse_rename_lines([], _current_sha, acc), do: Enum.reverse(acc)

  defp parse_rename_lines([line | rest], current_sha, acc) do
    cond do
      # This is a SHA line
      valid_sha?(String.trim(line)) ->
        parse_rename_lines(rest, String.trim(line), acc)

      # This is a rename line (R followed by similarity, then paths)
      String.starts_with?(line, "R") and not is_nil(current_sha) ->
        case parse_rename_line(line, current_sha) do
          {:ok, rename} ->
            parse_rename_lines(rest, current_sha, [rename | acc])

          :skip ->
            parse_rename_lines(rest, current_sha, acc)
        end

      true ->
        parse_rename_lines(rest, current_sha, acc)
    end
  end

  defp parse_rename_line(line, commit_sha) do
    # Format: R<similarity>\t<from_path>\t<to_path>
    # or: R\t<from_path>\t<to_path> (no similarity score)
    case String.split(line, "\t") do
      [status, from_path, to_path] ->
        similarity = parse_similarity(status)

        {:ok,
         %Rename{
           from_path: from_path,
           to_path: to_path,
           commit_sha: commit_sha,
           similarity: similarity
         }}

      _ ->
        :skip
    end
  end

  defp parse_similarity(status) do
    # Status is like "R100" or "R095" or just "R"
    case Regex.run(~r/^R(\d+)?$/, status) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp find_original_path([], _current), do: nil

  defp find_original_path(renames, _current) do
    # The original path is the from_path of the first rename
    case List.first(renames) do
      nil -> nil
      rename -> rename.from_path
    end
  end

  defp trace_path_at_index(current_path, _renames, _commits, nil), do: current_path

  defp trace_path_at_index(current_path, [], _commits, _index), do: current_path

  defp trace_path_at_index(current_path, renames, commits, target_index) do
    # For each rename, determine if the target commit is before or after the rename
    # Renames are in chronological order (oldest first)
    # Commits are in reverse chronological order (newest first)
    Enum.reduce(Enum.reverse(renames), current_path, fn rename, path ->
      rename_index = Enum.find_index(commits, &(&1 == rename.commit_sha))

      if rename_index && target_index >= rename_index do
        # Target is at or before the rename (in newer commits), use to_path
        if path == rename.to_path, do: path, else: path
      else
        # Target is after the rename (in older commits), use from_path
        if path == rename.to_path, do: rename.from_path, else: path
      end
    end)
  end
end
