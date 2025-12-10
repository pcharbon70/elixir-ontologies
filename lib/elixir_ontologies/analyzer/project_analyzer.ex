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

  alias ElixirOntologies.Analyzer.{Project, FileAnalyzer}
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
    %{
      file_count: length(file_results),
      error_count: length(errors),
      module_count: Enum.sum(Enum.map(file_results, &length(&1.analysis.modules))),
      successful_files: length(file_results),
      failed_files: length(errors)
    }
  end
end
