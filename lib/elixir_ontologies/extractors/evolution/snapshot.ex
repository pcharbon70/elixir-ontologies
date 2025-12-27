defmodule ElixirOntologies.Extractors.Evolution.Snapshot do
  @moduledoc """
  Extracts codebase snapshot information at specific points in time.

  A snapshot represents the state of a codebase at a particular commit,
  including module lists and statistics. This is useful for:

  - Tracking codebase evolution over time
  - Comparing snapshots to see what changed
  - Capturing point-in-time metrics for reporting

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.Snapshot

      # Extract snapshot at current HEAD
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      # Extract snapshot at specific commit
      {:ok, snapshot} = Snapshot.extract_snapshot(".", "abc123...")

      # Access snapshot data
      snapshot.modules        # List of module names
      snapshot.stats          # Codebase statistics
      snapshot.timestamp      # Commit timestamp

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> {:ok, snapshot} = Snapshot.extract_snapshot(".")
      iex> is_map(snapshot.stats)
      true
  """

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Analyzer.Project
  alias ElixirOntologies.Extractors.Evolution.{Commit, GitUtils}

  # ===========================================================================
  # CodebaseSnapshot Struct
  # ===========================================================================

  @typedoc """
  Represents a codebase snapshot at a specific point in time.

  ## Fields

  - `:snapshot_id` - Unique identifier based on commit SHA (e.g., "snapshot:abc123d")
  - `:commit_sha` - Full 40-character SHA hash
  - `:short_sha` - 7-character abbreviated SHA
  - `:timestamp` - Commit timestamp when snapshot was taken
  - `:project_name` - Name of the project from mix.exs
  - `:project_version` - Version of the project from mix.exs
  - `:modules` - List of module names found in the codebase
  - `:files` - List of source file paths
  - `:stats` - Codebase statistics map
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          snapshot_id: String.t(),
          commit_sha: String.t(),
          short_sha: String.t(),
          timestamp: DateTime.t() | nil,
          project_name: atom() | nil,
          project_version: String.t() | nil,
          modules: [String.t()],
          files: [String.t()],
          stats: stats(),
          metadata: map()
        }

  @typedoc """
  Codebase statistics at a point in time.
  """
  @type stats :: %{
          module_count: non_neg_integer(),
          function_count: non_neg_integer(),
          macro_count: non_neg_integer(),
          protocol_count: non_neg_integer(),
          behaviour_count: non_neg_integer(),
          line_count: non_neg_integer(),
          file_count: non_neg_integer()
        }

  @enforce_keys [:snapshot_id, :commit_sha, :short_sha]
  defstruct [
    :snapshot_id,
    :commit_sha,
    :short_sha,
    :timestamp,
    :project_name,
    :project_version,
    modules: [],
    files: [],
    stats: %{
      module_count: 0,
      function_count: 0,
      macro_count: 0,
      protocol_count: 0,
      behaviour_count: 0,
      line_count: 0,
      file_count: 0
    },
    metadata: %{}
  ]

  # ===========================================================================
  # Main Extraction Functions
  # ===========================================================================

  @doc """
  Extracts a codebase snapshot at a specific commit reference.

  The `ref` can be:
  - `"HEAD"` - current commit (default)
  - A full 40-character SHA
  - An abbreviated SHA (at least 7 characters)
  - A branch name
  - A tag name

  ## Parameters

  - `path` - Path to the git repository
  - `ref` - Commit reference (default: "HEAD")

  ## Returns

  - `{:ok, %CodebaseSnapshot{}}` - Successfully extracted snapshot
  - `{:error, :not_found}` - Repository not found
  - `{:error, :invalid_ref}` - Commit reference not found
  - `{:error, reason}` - Other errors

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> {:ok, snapshot} = Snapshot.extract_snapshot(".")
      iex> is_binary(snapshot.commit_sha)
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> Snapshot.extract_snapshot("/nonexistent")
      {:error, :not_found}
  """
  @spec extract_snapshot(String.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def extract_snapshot(path, ref \\ "HEAD") do
    with {:ok, repo_path} <- Git.detect_repo(path),
         {:ok, commit} <- Commit.extract_commit(repo_path, ref),
         {:ok, project} <- detect_project(repo_path),
         {:ok, files} <- list_elixir_files_at_commit(repo_path, commit.sha),
         {:ok, modules} <- extract_module_names_at_commit(repo_path, commit.sha, files),
         {:ok, stats} <- calculate_statistics(repo_path, commit.sha, files, modules) do
      snapshot = %__MODULE__{
        snapshot_id: "snapshot:#{commit.short_sha}",
        commit_sha: commit.sha,
        short_sha: commit.short_sha,
        timestamp: commit.commit_date,
        project_name: project_name(project),
        project_version: project_version(project),
        modules: Enum.sort(modules),
        files: Enum.sort(files),
        stats: stats,
        metadata: %{}
      }

      {:ok, snapshot}
    end
  end

  @doc """
  Extracts a codebase snapshot, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> snapshot = Snapshot.extract_snapshot!(".")
      iex> %ElixirOntologies.Extractors.Evolution.Snapshot{} = snapshot
  """
  @spec extract_snapshot!(String.t(), String.t()) :: t()
  def extract_snapshot!(path, ref \\ "HEAD") do
    case extract_snapshot(path, ref) do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        raise ArgumentError, "Failed to extract snapshot: #{GitUtils.format_error(reason)}"
    end
  end

  @doc """
  Convenience function to extract snapshot at current HEAD.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> {:ok, snapshot} = Snapshot.extract_current_snapshot(".")
      iex> is_binary(snapshot.snapshot_id)
      true
  """
  @spec extract_current_snapshot(String.t()) :: {:ok, t()} | {:error, atom()}
  def extract_current_snapshot(path), do: extract_snapshot(path, "HEAD")

  # ===========================================================================
  # File Listing Functions
  # ===========================================================================

  @doc """
  Lists all Elixir source files at a specific commit.

  Returns only `.ex` and `.exs` files in the `lib/` directory.
  For umbrella projects, includes files from all app `lib/` directories.

  ## Parameters

  - `repo_path` - Path to the git repository
  - `commit_sha` - Commit SHA to list files at

  ## Returns

  - `{:ok, files}` - List of file paths relative to repo root
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      iex> is_list(files)
      true
  """
  @spec list_elixir_files_at_commit(String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, atom()}
  def list_elixir_files_at_commit(repo_path, commit_sha) do
    args = ["ls-tree", "-r", "--name-only", commit_sha]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(fn file -> elixir_source_file?(file) and lib_or_apps_file?(file) end)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Module Extraction Functions
  # ===========================================================================

  @doc """
  Extracts module names from files at a specific commit.

  Parses each file's AST to find `defmodule` declarations.
  Handles parse errors gracefully by skipping unparseable files.

  ## Parameters

  - `repo_path` - Path to the git repository
  - `commit_sha` - Commit SHA to read files at
  - `files` - List of file paths to parse

  ## Returns

  - `{:ok, modules}` - List of module name strings (e.g., ["MyApp.User", "MyApp.Repo"])
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      iex> {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)
      iex> is_list(modules)
      true
  """
  @spec extract_module_names_at_commit(String.t(), String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, atom()}
  def extract_module_names_at_commit(repo_path, commit_sha, files) do
    modules =
      files
      |> Enum.flat_map(fn file ->
        case read_file_at_commit(repo_path, commit_sha, file) do
          {:ok, content} -> extract_modules_from_source(content)
          {:error, _} -> []
        end
      end)
      |> Enum.uniq()

    {:ok, modules}
  end

  # ===========================================================================
  # Statistics Calculation
  # ===========================================================================

  @doc """
  Calculates codebase statistics at a specific commit.

  Statistics include:
  - Module count
  - Function count (def, defp)
  - Macro count (defmacro, defmacrop)
  - Protocol count
  - Behaviour count
  - Line count
  - File count

  ## Parameters

  - `repo_path` - Path to the git repository
  - `commit_sha` - Commit SHA to calculate stats at
  - `files` - List of file paths
  - `modules` - List of module names (already extracted)

  ## Returns

  - `{:ok, stats}` - Statistics map
  - `{:error, reason}` - Error occurred
  """
  @spec calculate_statistics(String.t(), String.t(), [String.t()], [String.t()]) ::
          {:ok, stats()} | {:error, atom()}
  def calculate_statistics(repo_path, commit_sha, files, modules) do
    # Count lines across all files
    line_count = count_lines_at_commit(repo_path, commit_sha, files)

    # Count functions, macros, protocols, behaviours
    {function_count, macro_count, protocol_count, behaviour_count} =
      count_definitions_at_commit(repo_path, commit_sha, files)

    stats = %{
      module_count: length(modules),
      function_count: function_count,
      macro_count: macro_count,
      protocol_count: protocol_count,
      behaviour_count: behaviour_count,
      line_count: line_count,
      file_count: length(files)
    }

    {:ok, stats}
  end

  @doc """
  Counts total lines of code at a specific commit.

  ## Parameters

  - `repo_path` - Path to the git repository
  - `commit_sha` - Commit SHA to count lines at
  - `files` - List of file paths to count

  ## Returns

  Total line count as an integer.
  """
  @spec count_lines_at_commit(String.t(), String.t(), [String.t()]) :: non_neg_integer()
  def count_lines_at_commit(repo_path, commit_sha, files) do
    files
    |> Enum.reduce(0, fn file, acc ->
      case read_file_at_commit(repo_path, commit_sha, file) do
        {:ok, content} ->
          lines = content |> String.split("\n") |> length()
          acc + lines

        {:error, _} ->
          acc
      end
    end)
  end

  # ===========================================================================
  # Private Functions - Project Detection
  # ===========================================================================

  defp detect_project(repo_path) do
    case Project.detect(repo_path) do
      {:ok, project} -> {:ok, project}
      {:error, _} -> {:ok, nil}
    end
  end

  defp project_name(nil), do: nil
  defp project_name(%Project.Project{name: name}), do: name

  defp project_version(nil), do: nil
  defp project_version(%Project.Project{version: version}), do: version

  # ===========================================================================
  # Private Functions - File Operations
  # ===========================================================================

  defp read_file_at_commit(repo_path, commit_sha, file) do
    args = ["show", "#{commit_sha}:#{file}"]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp elixir_source_file?(file) do
    String.ends_with?(file, ".ex") or String.ends_with?(file, ".exs")
  end

  defp lib_or_apps_file?(file) do
    # Include lib/ files and apps/*/lib/ files for umbrella projects
    String.starts_with?(file, "lib/") or
      Regex.match?(~r/^apps\/[^\/]+\/lib\//, file)
  end

  # ===========================================================================
  # Private Functions - AST Parsing
  # ===========================================================================

  defp extract_modules_from_source(content) do
    case Code.string_to_quoted(content) do
      {:ok, ast} -> find_module_names(ast)
      {:error, _} -> []
    end
  end

  defp find_module_names(ast) do
    {_, modules} = Macro.prewalk(ast, [], &collect_module_names/2)
    modules
  end

  defp collect_module_names({:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc)
       when is_list(parts) do
    module_name = Enum.map_join(parts, ".", &to_string/1)
    {node, [module_name | acc]}
  end

  defp collect_module_names(node, acc), do: {node, acc}

  # ===========================================================================
  # Private Functions - Definition Counting
  # ===========================================================================

  defp count_definitions_at_commit(repo_path, commit_sha, files) do
    files
    |> Enum.reduce({0, 0, 0, 0}, fn file, {funcs, macros, protocols, behaviours} ->
      case read_file_at_commit(repo_path, commit_sha, file) do
        {:ok, content} ->
          {f, m, p, b} = count_definitions_in_source(content)
          {funcs + f, macros + m, protocols + p, behaviours + b}

        {:error, _} ->
          {funcs, macros, protocols, behaviours}
      end
    end)
  end

  defp count_definitions_in_source(content) do
    case Code.string_to_quoted(content) do
      {:ok, ast} -> count_definitions(ast)
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp count_definitions(ast) do
    {_, counts} = Macro.prewalk(ast, {0, 0, 0, 0}, &count_definition/2)
    counts
  end

  defp count_definition({def_type, _, _} = node, {funcs, macros, protocols, behaviours})
       when def_type in [:def, :defp] do
    {node, {funcs + 1, macros, protocols, behaviours}}
  end

  defp count_definition({def_type, _, _} = node, {funcs, macros, protocols, behaviours})
       when def_type in [:defmacro, :defmacrop] do
    {node, {funcs, macros + 1, protocols, behaviours}}
  end

  defp count_definition({:defprotocol, _, _} = node, {funcs, macros, protocols, behaviours}) do
    {node, {funcs, macros, protocols + 1, behaviours}}
  end

  defp count_definition({:defmodule, _, args} = node, {funcs, macros, protocols, behaviours}) do
    # Check if module uses @behaviour or @callback
    is_behaviour = has_behaviour_attributes?(args)

    if is_behaviour do
      {node, {funcs, macros, protocols, behaviours + 1}}
    else
      {node, {funcs, macros, protocols, behaviours}}
    end
  end

  defp count_definition(node, acc), do: {node, acc}

  defp has_behaviour_attributes?(args) when is_list(args) do
    Enum.any?(args, fn
      [do: body] -> has_callback_attribute?(body)
      _ -> false
    end)
  end

  defp has_behaviour_attributes?(_), do: false

  defp has_callback_attribute?({:__block__, _, exprs}) when is_list(exprs) do
    Enum.any?(exprs, &is_callback_attribute?/1)
  end

  defp has_callback_attribute?(expr), do: is_callback_attribute?(expr)

  defp is_callback_attribute?({:@, _, [{:callback, _, _}]}), do: true
  defp is_callback_attribute?(_), do: false
end
