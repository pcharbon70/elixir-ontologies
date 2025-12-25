defmodule ElixirOntologies.Extractors.Evolution.Blame do
  @moduledoc """
  Extracts line-level attribution using git blame.

  This module provides functions to extract blame information for files,
  showing which commit and author last modified each line. It uses the
  porcelain format for machine-readable output.

  ## Uncommitted Changes

  Lines that have been modified but not yet committed will have a special
  SHA of all zeros (0000000...). These lines are marked with `is_uncommitted: true`.

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.Blame

      # Extract blame for a file
      {:ok, blame} = Blame.extract_blame(".", "lib/my_module.ex")

      # Check line attribution
      line = List.first(blame.lines)
      line.author_name
      # => "Developer Name"

      # Get unique authors
      Blame.authors_in_blame(blame)
      # => ["Developer Name", "Another Dev"]

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> blame.line_count > 0
      true
  """

  alias ElixirOntologies.Analyzer.Git

  # ===========================================================================
  # BlameInfo Struct
  # ===========================================================================

  defmodule BlameInfo do
    @moduledoc """
    Represents blame information for a single line.
    """

    @type t :: %__MODULE__{
            line_number: pos_integer(),
            content: String.t(),
            commit_sha: String.t(),
            author_name: String.t() | nil,
            author_email: String.t() | nil,
            author_time: integer() | nil,
            author_date: DateTime.t() | nil,
            committer_name: String.t() | nil,
            committer_email: String.t() | nil,
            committer_time: integer() | nil,
            commit_date: DateTime.t() | nil,
            summary: String.t() | nil,
            filename: String.t() | nil,
            previous: String.t() | nil,
            line_age_seconds: integer() | nil,
            is_uncommitted: boolean()
          }

    @enforce_keys [:line_number, :commit_sha]
    defstruct [
      :line_number,
      :content,
      :commit_sha,
      :author_name,
      :author_email,
      :author_time,
      :author_date,
      :committer_name,
      :committer_email,
      :committer_time,
      :commit_date,
      :summary,
      :filename,
      :previous,
      :line_age_seconds,
      is_uncommitted: false
    ]
  end

  # ===========================================================================
  # FileBlame Struct
  # ===========================================================================

  @typedoc """
  Represents blame information for an entire file.

  ## Fields

  - `:path` - File path
  - `:lines` - List of BlameInfo structs
  - `:line_count` - Total number of lines
  - `:commit_count` - Number of unique commits
  - `:author_count` - Number of unique authors
  - `:oldest_line` - BlameInfo of the oldest line
  - `:newest_line` - BlameInfo of the newest line
  - `:has_uncommitted` - True if any lines are uncommitted
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          path: String.t(),
          lines: [BlameInfo.t()],
          line_count: non_neg_integer(),
          commit_count: non_neg_integer(),
          author_count: non_neg_integer(),
          oldest_line: BlameInfo.t() | nil,
          newest_line: BlameInfo.t() | nil,
          has_uncommitted: boolean(),
          metadata: map()
        }

  @enforce_keys [:path]
  defstruct [
    :path,
    :oldest_line,
    :newest_line,
    lines: [],
    line_count: 0,
    commit_count: 0,
    author_count: 0,
    has_uncommitted: false,
    metadata: %{}
  ]

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts blame information for a file.

  Uses `git blame --porcelain` for machine-readable output.

  ## Options

  - `:revision` - Blame at a specific revision (default: working tree)
  - `:line_range` - Tuple `{start, end}` to blame specific lines

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> blame.path
      "mix.exs"

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> Blame.extract_blame(".", "nonexistent_file.ex")
      {:error, :file_not_found}
  """
  @spec extract_blame(String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, atom()}
  def extract_blame(repo_path, file_path, opts \\ []) do
    revision = Keyword.get(opts, :revision)
    line_range = Keyword.get(opts, :line_range)

    with {:ok, repo_root} <- Git.detect_repo(repo_path),
         {:ok, relative_path} <- normalize_file_path(file_path, repo_root),
         :ok <- check_file_exists(repo_root, relative_path),
         {:ok, output} <- run_blame(repo_root, relative_path, revision, line_range) do
      now = System.os_time(:second)
      lines = parse_porcelain_output(output, now)

      {:ok, build_file_blame(relative_path, lines)}
    end
  end

  @doc """
  Extracts blame information, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> blame = Blame.extract_blame!(".", "mix.exs")
      iex> %ElixirOntologies.Extractors.Evolution.Blame{} = blame
  """
  @spec extract_blame!(String.t(), String.t(), keyword()) :: t()
  def extract_blame!(repo_path, file_path, opts \\ []) do
    case extract_blame(repo_path, file_path, opts) do
      {:ok, blame} -> blame
      {:error, reason} -> raise ArgumentError, "Failed to extract blame: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Checks if a BlameInfo represents an uncommitted line.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame.BlameInfo
      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> line = %BlameInfo{line_number: 1, commit_sha: "0000000000000000000000000000000000000000", is_uncommitted: true}
      iex> Blame.is_uncommitted?(line)
      true
  """
  @spec is_uncommitted?(BlameInfo.t()) :: boolean()
  def is_uncommitted?(%BlameInfo{is_uncommitted: value}), do: value

  @doc """
  Gets the line age in seconds.

  Returns nil for uncommitted lines.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame.BlameInfo
      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> line = %BlameInfo{line_number: 1, commit_sha: "abc", line_age_seconds: 3600}
      iex> Blame.line_age(line)
      3600
  """
  @spec line_age(BlameInfo.t()) :: integer() | nil
  def line_age(%BlameInfo{line_age_seconds: age}), do: age

  @doc """
  Gets unique commits from a FileBlame.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> commits = Blame.commits_in_blame(blame)
      iex> is_list(commits)
      true
  """
  @spec commits_in_blame(t()) :: [String.t()]
  def commits_in_blame(%__MODULE__{lines: lines}) do
    lines
    |> Enum.map(& &1.commit_sha)
    |> Enum.uniq()
  end

  @doc """
  Gets unique authors from a FileBlame.

  Returns a list of `{name, email}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> authors = Blame.authors_in_blame(blame)
      iex> is_list(authors)
      true
  """
  @spec authors_in_blame(t()) :: [{String.t(), String.t()}]
  def authors_in_blame(%__MODULE__{lines: lines}) do
    lines
    |> Enum.filter(&(&1.author_name != nil))
    |> Enum.map(&{&1.author_name, &1.author_email})
    |> Enum.uniq()
  end

  @doc """
  Groups lines by commit SHA.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> by_commit = Blame.lines_by_commit(blame)
      iex> is_map(by_commit)
      true
  """
  @spec lines_by_commit(t()) :: %{String.t() => [BlameInfo.t()]}
  def lines_by_commit(%__MODULE__{lines: lines}) do
    Enum.group_by(lines, & &1.commit_sha)
  end

  @doc """
  Groups lines by author email.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> by_author = Blame.lines_by_author(blame)
      iex> is_map(by_author)
      true
  """
  @spec lines_by_author(t()) :: %{String.t() => [BlameInfo.t()]}
  def lines_by_author(%__MODULE__{lines: lines}) do
    lines
    |> Enum.filter(&(&1.author_email != nil))
    |> Enum.group_by(& &1.author_email)
  end

  @doc """
  Gets the oldest line in a FileBlame.

  Based on author_time. Returns nil if no committed lines.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> oldest = Blame.oldest_line(blame)
      iex> oldest == blame.oldest_line
      true
  """
  @spec oldest_line(t()) :: BlameInfo.t() | nil
  def oldest_line(%__MODULE__{oldest_line: line}), do: line

  @doc """
  Gets the newest line in a FileBlame.

  Based on author_time. Returns nil if no committed lines.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> newest = Blame.newest_line(blame)
      iex> newest == blame.newest_line
      true
  """
  @spec newest_line(t()) :: BlameInfo.t() | nil
  def newest_line(%__MODULE__{newest_line: line}), do: line

  @doc """
  Gets line count for a specific commit.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> commits = Blame.commits_in_blame(blame)
      iex> count = Blame.line_count_for_commit(blame, List.first(commits))
      iex> is_integer(count)
      true
  """
  @spec line_count_for_commit(t(), String.t()) :: non_neg_integer()
  def line_count_for_commit(%__MODULE__{lines: lines}, commit_sha) do
    lines
    |> Enum.count(&(&1.commit_sha == commit_sha))
  end

  @doc """
  Gets line count for a specific author email.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Blame
      iex> {:ok, blame} = Blame.extract_blame(".", "mix.exs")
      iex> authors = Blame.authors_in_blame(blame)
      iex> {_name, email} = List.first(authors)
      iex> count = Blame.line_count_for_author(blame, email)
      iex> is_integer(count)
      true
  """
  @spec line_count_for_author(t(), String.t()) :: non_neg_integer()
  def line_count_for_author(%__MODULE__{lines: lines}, email) do
    lines
    |> Enum.count(&(&1.author_email == email))
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp normalize_file_path(file_path, repo_root) do
    if Path.type(file_path) == :absolute do
      case Path.relative_to(file_path, repo_root) do
        ^file_path -> {:error, :outside_repo}
        relative -> {:ok, relative}
      end
    else
      {:ok, file_path}
    end
  end

  defp check_file_exists(repo_root, relative_path) do
    full_path = Path.join(repo_root, relative_path)

    if File.exists?(full_path) do
      :ok
    else
      {:error, :file_not_found}
    end
  end

  defp run_blame(repo_path, file_path, revision, line_range) do
    args = ["blame", "--porcelain"]

    args =
      if line_range do
        {start_line, end_line} = line_range
        args ++ ["-L", "#{start_line},#{end_line}"]
      else
        args
      end

    args =
      if revision do
        args ++ [revision, "--", file_path]
      else
        args ++ ["--", file_path]
      end

    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _code} -> {:error, :blame_failed}
    end
  end

  defp parse_porcelain_output(output, now) do
    lines = String.split(output, "\n")
    parse_lines(lines, %{}, [], now)
  end

  # Parse porcelain format line by line
  defp parse_lines([], _commit_cache, acc, _now), do: Enum.reverse(acc)

  defp parse_lines([line | rest], commit_cache, acc, now) do
    case parse_header_line(line) do
      {:header, sha, _original_line, final_line, _num_lines} ->
        # Start of a new line blame entry
        {commit_info, new_cache, remaining} = collect_commit_info(rest, sha, commit_cache)
        {content, remaining2} = extract_content_line(remaining)

        blame_info = build_blame_info(sha, final_line, content, commit_info, now)
        parse_lines(remaining2, new_cache, [blame_info | acc], now)

      :not_header ->
        # Skip non-header lines
        parse_lines(rest, commit_cache, acc, now)
    end
  end

  defp parse_header_line(line) do
    # Format: <sha> <original_line> <final_line> [<num_lines>]
    case String.split(line, " ") do
      [sha, orig, final | rest] when byte_size(sha) == 40 ->
        num = if rest == [], do: 1, else: String.to_integer(List.first(rest))

        {:header, sha, String.to_integer(orig), String.to_integer(final), num}

      _ ->
        :not_header
    end
  end

  defp collect_commit_info(lines, sha, commit_cache) do
    if Map.has_key?(commit_cache, sha) do
      # We already have this commit's info, skip to content
      {Map.get(commit_cache, sha), commit_cache, lines}
    else
      # Collect commit info until we hit a content line or another header
      {info, remaining} = collect_info_lines(lines, %{})
      new_cache = Map.put(commit_cache, sha, info)
      {info, new_cache, remaining}
    end
  end

  defp collect_info_lines([], info), do: {info, []}

  defp collect_info_lines([line | rest] = lines, info) do
    cond do
      String.starts_with?(line, "\t") ->
        # Content line - stop collecting
        {info, lines}

      String.starts_with?(line, "author ") ->
        value = String.trim_leading(line, "author ")
        collect_info_lines(rest, Map.put(info, :author_name, value))

      String.starts_with?(line, "author-mail ") ->
        value = String.trim_leading(line, "author-mail ")
        # Remove angle brackets
        email = value |> String.trim_leading("<") |> String.trim_trailing(">")
        collect_info_lines(rest, Map.put(info, :author_email, email))

      String.starts_with?(line, "author-time ") ->
        value = String.trim_leading(line, "author-time ")
        collect_info_lines(rest, Map.put(info, :author_time, String.to_integer(value)))

      String.starts_with?(line, "committer ") ->
        value = String.trim_leading(line, "committer ")
        collect_info_lines(rest, Map.put(info, :committer_name, value))

      String.starts_with?(line, "committer-mail ") ->
        value = String.trim_leading(line, "committer-mail ")
        email = value |> String.trim_leading("<") |> String.trim_trailing(">")
        collect_info_lines(rest, Map.put(info, :committer_email, email))

      String.starts_with?(line, "committer-time ") ->
        value = String.trim_leading(line, "committer-time ")
        collect_info_lines(rest, Map.put(info, :committer_time, String.to_integer(value)))

      String.starts_with?(line, "summary ") ->
        value = String.trim_leading(line, "summary ")
        collect_info_lines(rest, Map.put(info, :summary, value))

      String.starts_with?(line, "filename ") ->
        value = String.trim_leading(line, "filename ")
        collect_info_lines(rest, Map.put(info, :filename, value))

      String.starts_with?(line, "previous ") ->
        value = String.trim_leading(line, "previous ")
        # Format: <sha> <filename>
        [prev_sha | _] = String.split(value, " ", parts: 2)
        collect_info_lines(rest, Map.put(info, :previous, prev_sha))

      true ->
        # Skip other lines (author-tz, committer-tz, boundary, etc.)
        collect_info_lines(rest, info)
    end
  end

  defp extract_content_line([]), do: {"", []}

  defp extract_content_line([line | rest]) do
    if String.starts_with?(line, "\t") do
      {String.trim_leading(line, "\t"), rest}
    else
      {"", [line | rest]}
    end
  end

  defp build_blame_info(sha, line_number, content, info, now) do
    is_uncommitted = uncommitted_sha?(sha)
    author_time = Map.get(info, :author_time)
    committer_time = Map.get(info, :committer_time)

    line_age =
      if is_uncommitted or is_nil(author_time) do
        nil
      else
        now - author_time
      end

    %BlameInfo{
      line_number: line_number,
      content: content,
      commit_sha: sha,
      author_name: Map.get(info, :author_name),
      author_email: Map.get(info, :author_email),
      author_time: author_time,
      author_date: timestamp_to_datetime(author_time),
      committer_name: Map.get(info, :committer_name),
      committer_email: Map.get(info, :committer_email),
      committer_time: committer_time,
      commit_date: timestamp_to_datetime(committer_time),
      summary: Map.get(info, :summary),
      filename: Map.get(info, :filename),
      previous: Map.get(info, :previous),
      line_age_seconds: line_age,
      is_uncommitted: is_uncommitted
    }
  end

  defp uncommitted_sha?(sha) do
    sha == "0000000000000000000000000000000000000000"
  end

  defp timestamp_to_datetime(nil), do: nil

  defp timestamp_to_datetime(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp build_file_blame(path, lines) do
    committed_lines = Enum.filter(lines, &(not &1.is_uncommitted and &1.author_time != nil))

    oldest = find_oldest_line(committed_lines)
    newest = find_newest_line(committed_lines)

    unique_commits = lines |> Enum.map(& &1.commit_sha) |> Enum.uniq() |> length()

    unique_authors =
      lines
      |> Enum.filter(&(&1.author_email != nil))
      |> Enum.map(& &1.author_email)
      |> Enum.uniq()
      |> length()

    has_uncommitted = Enum.any?(lines, & &1.is_uncommitted)

    %__MODULE__{
      path: path,
      lines: lines,
      line_count: length(lines),
      commit_count: unique_commits,
      author_count: unique_authors,
      oldest_line: oldest,
      newest_line: newest,
      has_uncommitted: has_uncommitted,
      metadata: %{}
    }
  end

  defp find_oldest_line([]), do: nil

  defp find_oldest_line(lines) do
    Enum.min_by(lines, & &1.author_time, fn -> nil end)
  end

  defp find_newest_line([]), do: nil

  defp find_newest_line(lines) do
    Enum.max_by(lines, & &1.author_time, fn -> nil end)
  end
end
