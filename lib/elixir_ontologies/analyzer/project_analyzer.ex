defmodule ElixirOntologies.Analyzer.ProjectAnalyzer do
  @moduledoc """
  Analyzes entire Mix projects and produces unified RDF knowledge graphs.

  This module orchestrates multi-file analysis by:
  1. Detecting Mix project structure
  2. Discovering all Elixir source files
  3. Analyzing each file using FileAnalyzer
  4. Merging individual graphs into unified project graph
  5. Adding project-level metadata

  ## Usage

      alias ElixirOntologies.Analyzer.ProjectAnalyzer

      # Analyze current project
      {:ok, result} = ProjectAnalyzer.analyze(".")

      # Access results
      result.project          # Mix project metadata
      result.files            # List of analyzed files
      result.graph            # Unified RDF graph
      result.errors           # Any errors encountered

      # Analyze with options
      {:ok, result} = ProjectAnalyzer.analyze(".", exclude_tests: false)

      # Bang variant (raises on error)
      result = ProjectAnalyzer.analyze!(".")

  ## Analysis Pipeline

  1. **Project Detection** - Uses Project.detect/1 to find Mix project
  2. **File Discovery** - Recursively scans source directories for .ex/.exs files
  3. **File Filtering** - Excludes test files by default (configurable)
  4. **File Analysis** - Analyzes each file with FileAnalyzer.analyze/2
  5. **Graph Merging** - Combines individual file graphs into unified graph
  6. **Metadata Addition** - Adds project-level metadata to graph

  ## Configuration Options

  - `exclude_tests` - Skip test/ directories (default: true)
  - `patterns` - File patterns to include (default: ["**/*.{ex,exs}"])
  - `exclude_patterns` - Patterns to exclude (default: [])
  - `config` - Config passed to FileAnalyzer (default: Config.default())
  - `continue_on_error` - Continue if files fail (default: true)

  ## Error Handling

  Hard errors (returns `{:error, reason}`):
  - Project not found
  - No source files found
  - Invalid configuration

  Soft errors (collected in result.errors):
  - Individual file parse errors
  - Individual file analysis failures
  - Permission denied on files
  """

  alias ElixirOntologies.Analyzer.{Project, FileAnalyzer, ChangeTracker}
  alias ElixirOntologies.{Config, Graph}

  require Logger

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  defmodule Result do
    @moduledoc """
    Complete project analysis result with unified knowledge graph.

    ## Fields

    - `project` - Project.Project struct with project metadata
    - `files` - List of FileResult structs (one per analyzed file)
    - `graph` - Unified RDF graph containing all triples from all files
    - `errors` - List of {file_path, error} tuples for failed files
    - `metadata` - Analysis statistics (file counts, duration, etc.)
    """

    @enforce_keys [:project, :files, :graph]
    defstruct [
      :project,
      :files,
      :graph,
      errors: [],
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            project: Project.Project.t(),
            files: [ElixirOntologies.Analyzer.ProjectAnalyzer.FileResult.t()],
            graph: Graph.t(),
            errors: [{String.t(), term()}],
            metadata: map()
          }
  end

  defmodule FileResult do
    @moduledoc """
    Analysis result for a single file within the project.

    ## Fields

    - `file_path` - Absolute path to the file
    - `relative_path` - Path relative to project root
    - `analysis` - FileAnalyzer.Result struct (nil if failed)
    - `status` - :ok | :error | :skipped
    - `error` - Error reason if status is :error
    """

    @enforce_keys [:file_path, :relative_path, :status]
    defstruct [
      :file_path,
      :relative_path,
      :analysis,
      :status,
      error: nil
    ]

    @type t :: %__MODULE__{
            file_path: String.t(),
            relative_path: String.t(),
            analysis: FileAnalyzer.Result.t() | nil,
            status: :ok | :error | :skipped,
            error: term()
          }
  end

  defmodule UpdateResult do
    @moduledoc """
    Result of incremental project analysis update.

    ## Fields

    - `project` - Project.Project struct with project metadata
    - `files` - Updated list of FileResult structs (unchanged + re-analyzed)
    - `graph` - Updated unified RDF graph
    - `changes` - ChangeTracker.Changes struct showing what changed
    - `errors` - List of {file_path, error} tuples for failed files
    - `metadata` - Update statistics (counts, timestamps, etc.)
    """

    @enforce_keys [:project, :files, :graph, :changes]
    defstruct [
      :project,
      :files,
      :graph,
      :changes,
      errors: [],
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            project: Project.Project.t(),
            files: [ElixirOntologies.Analyzer.ProjectAnalyzer.FileResult.t()],
            graph: Graph.t(),
            changes: ChangeTracker.Changes.t(),
            errors: [{String.t(), term()}],
            metadata: map()
          }
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Analyzes a Mix project and returns unified analysis result.

  ## Parameters

  - `path` - Path to project root (directory containing mix.exs)
  - `opts` - Keyword list of options

  ## Options

  - `exclude_tests` - Skip test/ directories (default: true)
  - `patterns` - File patterns to include (default: ["**/*.{ex,exs}"])
  - `exclude_patterns` - Patterns to exclude (default: [])
  - `config` - Config for FileAnalyzer (default: Config.default())
  - `continue_on_error` - Continue on file failures (default: true)

  ## Returns

  - `{:ok, result}` - Successful analysis with Result struct
  - `{:error, reason}` - Analysis failed

  ## Examples

      # Analyze current project
      {:ok, result} = ProjectAnalyzer.analyze(".")

      # Include test files
      {:ok, result} = ProjectAnalyzer.analyze(".", exclude_tests: false)

      # Handle errors
      case ProjectAnalyzer.analyze(".") do
        {:ok, _res} -> IO.puts("Analyzed files")
        {:error, _reason} -> IO.puts("Failed")
      end
  """
  @spec analyze(String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def analyze(path, opts \\ []) do
    config = Keyword.get(opts, :config, Config.default())

    with {:ok, project} <- Project.detect(path),
         files <- discover_files(project, opts),
         {:ok, files} <- validate_files(files),
         {file_results, errors} <- analyze_files(files, project, config, opts),
         graph <- merge_graphs(file_results),
         metadata <- build_metadata(file_results, errors) do
      {:ok,
       %Result{
         project: project,
         files: file_results,
         graph: graph,
         errors: errors,
         metadata: metadata
       }}
    end
  end

  @doc """
  Analyzes a Mix project, raising on error.

  Same as `analyze/2` but raises a runtime error instead of returning
  an error tuple.

  ## Examples

      result = ProjectAnalyzer.analyze!(".")
      # result.files contains list of analyzed files
  """
  @spec analyze!(String.t(), keyword()) :: Result.t()
  def analyze!(path, opts \\ []) do
    case analyze(path, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to analyze project: #{inspect(reason)}"
    end
  end

  @doc """
  Updates an existing analysis result based on file changes.

  Performs incremental analysis by:
  1. Detecting which files have changed, been added, or deleted
  2. Keeping analysis results for unchanged files
  3. Re-analyzing changed files
  4. Analyzing new files
  5. Removing results for deleted files
  6. Rebuilding the unified graph

  ## Parameters

  - `previous_result` - Previous Result struct from analyze/2
  - `path` - Path to project root (should be same as original analysis)
  - `opts` - Keyword list of options (same as analyze/2)

  ## Options

  Same as `analyze/2`, plus:
  - `force_full_analysis` - If true, ignore changes and re-analyze all files

  ## Returns

  - `{:ok, update_result}` - Successful update with UpdateResult struct
  - `{:error, reason}` - Update failed

  ## Examples

      # Initial analysis
      {:ok, initial} = ProjectAnalyzer.analyze(".")

      # ... files are modified ...

      # Incremental update
      {:ok, updated} = ProjectAnalyzer.update(initial, ".")

      # Check what changed
      updated.changes.changed  # => ["lib/foo.ex"]
      updated.changes.new      # => ["lib/bar.ex"]
      updated.changes.deleted  # => []

  ## Fallback Behavior

  If the previous result doesn't contain analysis state (e.g., from an
  older version), this falls back to full re-analysis.
  """
  @spec update(Result.t(), String.t(), keyword()) :: {:ok, UpdateResult.t()} | {:error, term()}
  def update(previous_result, path, opts \\ []) do
    force_full = Keyword.get(opts, :force_full_analysis, false)
    config = Keyword.get(opts, :config, Config.default())

    with {:ok, project} <- Project.detect(path) do
      # Check if we should do full analysis or incremental
      case {force_full, detect_file_changes(previous_result, project, opts)} do
        # Force full analysis requested
        {true, _} ->
          do_full_update(previous_result, project, path, opts, config)

        # No previous state, fall back to full analysis
        {false, nil} ->
          Logger.info("No previous analysis state found, performing full re-analysis")
          do_full_update(previous_result, project, path, opts, config)

        # Incremental update
        {false, {changes, _current_files}} ->
          do_incremental_update(previous_result, project, changes, opts, config)
      end
    end
  end

  @doc """
  Updates an existing analysis result, raising on error.

  Same as `update/3` but raises a runtime error instead of returning
  an error tuple.

  ## Examples

      result = ProjectAnalyzer.analyze!(".")
      updated = ProjectAnalyzer.update!(result, ".")
  """
  @spec update!(Result.t(), String.t(), keyword()) :: UpdateResult.t()
  def update!(previous_result, path, opts \\ []) do
    case update(previous_result, path, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to update project analysis: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Private - File Discovery
  # ===========================================================================

  defp discover_files(project, opts) do
    exclude_tests = Keyword.get(opts, :exclude_tests, true)

    project.source_dirs
    |> Enum.flat_map(&scan_directory(&1))
    |> filter_test_files(exclude_tests, project.path)
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp scan_directory(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn entry ->
          path = Path.join(dir, entry)

          cond do
            File.dir?(path) -> scan_directory(path)
            String.ends_with?(path, ".ex") or String.ends_with?(path, ".exs") -> [path]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp filter_test_files(files, false, _project_path), do: files

  defp filter_test_files(files, true, project_path) do
    Enum.reject(files, fn file ->
      relative = Path.relative_to(file, project_path)
      String.starts_with?(relative, "test/")
    end)
  end

  defp validate_files([]), do: {:error, :no_source_files}
  defp validate_files(files), do: {:ok, files}

  # ===========================================================================
  # Private - File Analysis
  # ===========================================================================

  defp analyze_files(files, project, config, opts) do
    continue_on_error = Keyword.get(opts, :continue_on_error, true)

    files
    |> Enum.reduce({[], []}, fn file, {results, errors} ->
      relative_path = Path.relative_to(file, project.path)

      case FileAnalyzer.analyze(file, config) do
        {:ok, analysis} ->
          result = %FileResult{
            file_path: file,
            relative_path: relative_path,
            analysis: analysis,
            status: :ok
          }

          {[result | results], errors}

        {:error, reason} ->
          if continue_on_error do
            Logger.debug("Failed to analyze #{file}: #{inspect(reason)}")
            {results, [{file, reason} | errors]}
          else
            raise "File analysis failed: #{file} - #{inspect(reason)}"
          end
      end
    end)
    |> then(fn {results, errors} -> {Enum.reverse(results), Enum.reverse(errors)} end)
  end

  # ===========================================================================
  # Private - Graph Merging
  # ===========================================================================

  defp merge_graphs(file_results) do
    base_graph = Graph.new()

    file_results
    |> Enum.reduce(base_graph, fn file_result, acc_graph ->
      file_graph = file_result.analysis.graph

      # Add all triples from file graph to accumulated graph
      Graph.add(acc_graph, file_graph.graph)
    end)
  end

  # ===========================================================================
  # Private - Metadata
  # ===========================================================================

  defp build_metadata(file_results, errors) do
    file_paths = Enum.map(file_results, & &1.file_path)
    analysis_state = ChangeTracker.capture_state(file_paths)

    %{
      file_count: length(file_results),
      error_count: length(errors),
      module_count: Enum.sum(Enum.map(file_results, &length(&1.analysis.modules))),
      successful_files: length(file_results),
      failed_files: length(errors),
      file_paths: file_paths,
      analysis_state: analysis_state,
      last_analysis: DateTime.utc_now()
    }
  end

  # ===========================================================================
  # Private - Incremental Updates
  # ===========================================================================

  defp do_full_update(previous_result, project, _path, opts, config) do
    # Do full re-analysis
    files = discover_files(project, opts)

    case validate_files(files) do
      {:ok, valid_files} ->
        {file_results, errors} = analyze_files(valid_files, project, config, opts)
        graph = merge_graphs(file_results)

        # Create a "changes" struct showing everything as changed
        all_files = Enum.map(file_results, & &1.file_path)
        previous_files = Map.get(previous_result.metadata, :file_paths, [])

        changes = %ChangeTracker.Changes{
          changed: all_files,
          new: all_files -- previous_files,
          deleted: previous_files -- all_files,
          unchanged: []
        }

        metadata = build_update_metadata(changes, file_results, errors, previous_result.metadata)

        {:ok,
         %UpdateResult{
           project: project,
           files: file_results,
           graph: graph,
           changes: changes,
           errors: errors,
           metadata: metadata
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_incremental_update(previous_result, project, changes, opts, config) do
    # Update file list (keep unchanged, identify files to analyze)
    {unchanged_files, files_to_analyze} = update_file_list(previous_result.files, changes)

    # Analyze changed and new files
    {new_file_results, errors} = analyze_updated_files(files_to_analyze, project, config, opts)

    # Combine unchanged and newly analyzed files
    all_file_results = unchanged_files ++ new_file_results

    # Rebuild graph from all files
    graph = merge_graphs(all_file_results)

    # Build metadata with change statistics
    metadata = build_update_metadata(changes, all_file_results, errors, previous_result.metadata)

    {:ok,
     %UpdateResult{
       project: project,
       files: all_file_results,
       graph: graph,
       changes: changes,
       errors: errors,
       metadata: metadata
     }}
  end

  defp detect_file_changes(previous_result, project, opts) do
    # Extract previous state from metadata
    old_state = Map.get(previous_result.metadata, :analysis_state)

    # If no previous state, return nil to trigger full analysis
    if is_nil(old_state) do
      nil
    else
      # Discover current files
      current_files = discover_files(project, opts)

      # Capture current state
      new_state = ChangeTracker.capture_state(current_files)

      # Detect changes
      changes = ChangeTracker.detect_changes(old_state, new_state)

      {changes, current_files}
    end
  end

  defp update_file_list(previous_files, changes) do
    # Create map of previous files by path for quick lookup
    previous_map = Map.new(previous_files, fn file -> {file.file_path, file} end)

    # Keep only unchanged files
    unchanged_files =
      changes.unchanged
      |> Enum.map(&Map.get(previous_map, &1))
      |> Enum.reject(&is_nil/1)

    # Files that need analysis (changed + new)
    files_to_analyze = changes.changed ++ changes.new

    {unchanged_files, files_to_analyze}
  end

  defp analyze_updated_files(files, project, config, opts) do
    # Reuse existing analyze_files logic
    analyze_files(files, project, config, opts)
  end

  defp build_update_metadata(changes, file_results, errors, previous_metadata) do
    base_metadata = build_metadata(file_results, errors)

    Map.merge(base_metadata, %{
      changed_count: length(changes.changed),
      new_count: length(changes.new),
      deleted_count: length(changes.deleted),
      unchanged_count: length(changes.unchanged),
      previous_analysis: Map.get(previous_metadata, :last_analysis),
      update_timestamp: DateTime.utc_now()
    })
  end
end
