defmodule ElixirOntologies.Hex.AnalyzerAdapter do
  @moduledoc """
  Adapter for ProjectAnalyzer integration in batch processing.

  Wraps ProjectAnalyzer with timeout protection and extracts
  metadata for progress tracking.

  ## Usage

      # Analyze a package
      {:ok, graph, metadata} = AnalyzerAdapter.analyze_package(
        "/tmp/package",
        "phoenix",
        %{
          base_iri_template: "https://elixir-code.org/:name/:version/",
          version: "1.7.10",
          timeout_minutes: 5
        }
      )
  """

  alias ElixirOntologies.Analyzer.ProjectAnalyzer

  @default_timeout_minutes 5

  @doc """
  Analyzes a package with timeout protection.

  Returns `{:ok, graph, metadata}` on success or `{:error, reason}` on failure.

  ## Config Options

    * `:base_iri_template` - IRI template with `:name` and `:version` placeholders
      (default: "https://elixir-code.org/:name/:version/")
    * `:version` - Package version for IRI generation (required for proper IRIs)
    * `:timeout_minutes` - Analysis timeout in minutes (default: #{@default_timeout_minutes})
  """
  @spec analyze_package(Path.t(), String.t(), map()) ::
          {:ok, term(), map()} | {:error, term()}
  def analyze_package(path, name, config \\ %{}) do
    timeout = Map.get(config, :timeout_minutes, @default_timeout_minutes)
    timeout_ms = timeout * 60 * 1000

    base_iri = generate_base_iri(config, name)

    opts = [
      base_iri: base_iri,
      exclude_tests: true,
      continue_on_error: true,
      include_git_info: false
    ]

    with_timeout(timeout_ms, fn ->
      case ProjectAnalyzer.analyze(path, opts) do
        {:ok, result} ->
          metadata = extract_metadata(result)
          {:ok, result.graph, metadata}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Runs a function with timeout protection.

  Returns `{:error, :timeout}` if the function exceeds the timeout.
  Returns `{:error, {:task_exit, reason}}` if the function crashes.
  """
  @spec with_timeout(non_neg_integer(), (() -> term())) :: term()
  def with_timeout(timeout_ms, fun) when is_function(fun, 0) do
    caller = self()
    ref = make_ref()

    # Spawn unlinked process to avoid crashing caller on exception
    pid = spawn(fn ->
      result = try do
        {:ok, fun.()}
      catch
        kind, reason ->
          {:error, {:task_exit, {kind, reason}}}
      end
      send(caller, {ref, result})
    end)

    receive do
      {^ref, {:ok, result}} ->
        result

      {^ref, {:error, _} = error} ->
        error
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        {:error, :timeout}
    end
  end

  @doc """
  Extracts metadata from analysis result for progress tracking.
  """
  @spec extract_metadata(ProjectAnalyzer.Result.t()) :: map()
  def extract_metadata(%ProjectAnalyzer.Result{} = result) do
    module_count = count_modules(result.files)
    function_count = count_functions(result.files)
    triple_count = count_triples(result.graph)

    %{
      module_count: module_count,
      function_count: function_count,
      triple_count: triple_count,
      file_count: length(result.files),
      error_count: length(result.errors)
    }
  end

  defp generate_base_iri(config, name) do
    template = Map.get(config, :base_iri_template, "https://elixir-code.org/:name/:version/")
    version = Map.get(config, :version, "unknown")

    template
    |> String.replace(":name", name)
    |> String.replace(":version", version)
  end

  defp count_modules(files) do
    files
    |> Enum.filter(&(&1.status == :ok))
    |> Enum.map(fn file ->
      case file.analysis do
        %{result: %{modules: modules}} when is_list(modules) -> length(modules)
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp count_functions(files) do
    files
    |> Enum.filter(&(&1.status == :ok))
    |> Enum.map(&count_file_functions/1)
    |> Enum.sum()
  end

  defp count_file_functions(file) do
    case file.analysis do
      %{result: %{modules: modules}} when is_list(modules) ->
        Enum.map(modules, &count_module_functions/1) |> Enum.sum()

      _ ->
        0
    end
  end

  defp count_module_functions(mod) do
    case mod do
      %{functions: functions} when is_list(functions) -> length(functions)
      _ -> 0
    end
  end

  defp count_triples(graph) do
    case graph do
      %{triples: triples} when is_list(triples) -> length(triples)
      %{triples: triples} when is_map(triples) -> map_size(triples)
      _ -> 0
    end
  end

  @doc """
  Returns the default timeout in minutes.
  """
  @spec default_timeout_minutes() :: non_neg_integer()
  def default_timeout_minutes, do: @default_timeout_minutes
end
