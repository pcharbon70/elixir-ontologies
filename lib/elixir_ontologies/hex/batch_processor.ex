defmodule ElixirOntologies.Hex.BatchProcessor do
  @moduledoc """
  Main orchestration for Hex.pm batch package analysis.

  Coordinates all components to process packages sequentially with
  proper error handling, progress tracking, and rate limiting.

  ## Usage

      config = BatchProcessor.Config.new(
        output_dir: "/output",
        progress_file: "/output/progress.json"
      )

      {:ok, summary} = BatchProcessor.run(config)
  """

  require Logger

  alias ElixirOntologies.Hex.Api
  alias ElixirOntologies.Hex.AnalyzerAdapter
  alias ElixirOntologies.Hex.FailureTracker
  alias ElixirOntologies.Hex.Filter
  alias ElixirOntologies.Hex.HttpClient
  alias ElixirOntologies.Hex.OutputManager
  alias ElixirOntologies.Hex.PackageHandler
  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult
  alias ElixirOntologies.Hex.ProgressStore
  alias ElixirOntologies.Hex.RateLimiter

  defmodule Config do
    @moduledoc """
    Configuration for batch processing.
    """

    defstruct [
      :output_dir,
      :progress_file,
      :temp_dir,
      :limit,
      :start_page,
      :delay_ms,
      :api_delay_ms,
      :timeout_minutes,
      :base_iri_template,
      :sort_by,
      :resume,
      :dry_run,
      :verbose
    ]

    @type sort_order :: :popularity | :alphabetical
    @type t :: %__MODULE__{
            output_dir: String.t(),
            progress_file: String.t(),
            temp_dir: String.t(),
            limit: non_neg_integer() | nil,
            start_page: pos_integer(),
            delay_ms: non_neg_integer(),
            api_delay_ms: non_neg_integer(),
            timeout_minutes: pos_integer(),
            base_iri_template: String.t(),
            sort_by: sort_order(),
            resume: boolean(),
            dry_run: boolean(),
            verbose: boolean()
          }

    @doc """
    Creates a new config with defaults.

    ## Options

      * `:output_dir` - Output directory path (required)
      * `:progress_file` - Progress JSON file path (default: output_dir/progress.json)
      * `:temp_dir` - Temporary directory (default: System.tmp_dir!/0)
      * `:limit` - Maximum packages to process (default: nil = no limit)
      * `:start_page` - Starting API page (default: 1)
      * `:delay_ms` - Delay between packages in ms (default: 100)
      * `:api_delay_ms` - Delay between API calls in ms (default: 50)
      * `:timeout_minutes` - Per-package timeout (default: 5)
      * `:base_iri_template` - IRI template with :name/:version placeholders (default: https://elixir-code.org/:name/:version/)
      * `:sort_by` - Sort order: :popularity or :alphabetical (default: :popularity)
      * `:resume` - Resume from progress file (default: true)
      * `:dry_run` - List packages only, don't analyze (default: false)
      * `:verbose` - Verbose output (default: false)
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      output_dir = Keyword.get(opts, :output_dir, "hex_output")

      %__MODULE__{
        output_dir: output_dir,
        progress_file: Keyword.get(opts, :progress_file, Path.join(output_dir, "progress.json")),
        temp_dir: Keyword.get(opts, :temp_dir, System.tmp_dir!()),
        limit: Keyword.get(opts, :limit),
        start_page: Keyword.get(opts, :start_page, 1),
        delay_ms: Keyword.get(opts, :delay_ms, 100),
        api_delay_ms: Keyword.get(opts, :api_delay_ms, 50),
        timeout_minutes: Keyword.get(opts, :timeout_minutes, 5),
        base_iri_template: Keyword.get(opts, :base_iri_template, "https://elixir-code.org/:name/:version/"),
        sort_by: Keyword.get(opts, :sort_by, :popularity),
        resume: Keyword.get(opts, :resume, true),
        dry_run: Keyword.get(opts, :dry_run, false),
        verbose: Keyword.get(opts, :verbose, false)
      }
    end

    @doc """
    Validates config, returning errors if any.
    """
    @spec validate(t()) :: :ok | {:error, term()}
    def validate(%__MODULE__{} = config) do
      cond do
        is_nil(config.output_dir) or config.output_dir == "" ->
          {:error, :output_dir_required}

        is_nil(config.progress_file) or config.progress_file == "" ->
          {:error, :progress_file_required}

        config.timeout_minutes <= 0 ->
          {:error, :invalid_timeout}

        true ->
          :ok
      end
    end
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :http_client,
      :progress,
      :rate_limiter,
      :processed_count,
      :started_at,
      :interrupted
    ]

    @type t :: %__MODULE__{
            config: Config.t(),
            http_client: term(),
            progress: Progress.t(),
            rate_limiter: RateLimiter.State.t(),
            processed_count: non_neg_integer(),
            started_at: DateTime.t(),
            interrupted: boolean()
          }
  end

  @doc """
  Runs batch processing with the given configuration.

  Returns `{:ok, summary}` on completion or `{:error, reason}` on failure.
  """
  @spec run(Config.t()) :: {:ok, map()} | {:error, term()}
  def run(%Config{} = config) do
    with :ok <- Config.validate(config),
         {:ok, state} <- init(config) do
      run_processing(state)
    end
  end

  @doc """
  Initializes the batch processor state.
  """
  @spec init(Config.t()) :: {:ok, State.t()} | {:error, term()}
  def init(%Config{} = config) do
    with :ok <- Config.validate(config),
         :ok <- OutputManager.ensure_output_dir(config.output_dir),
         :ok <- ensure_temp_dir(config.temp_dir),
         http_client <- HttpClient.new(),
         {:ok, progress, status} <- load_progress(config),
         rate_limiter <- RateLimiter.new() do
      if config.verbose do
        log_init(config, status)
      end

      {:ok,
       %State{
         config: config,
         http_client: http_client,
         progress: progress,
         rate_limiter: rate_limiter,
         processed_count: 0,
         started_at: DateTime.utc_now(),
         interrupted: false
       }}
    end
  end

  defp ensure_temp_dir(temp_dir) do
    case File.mkdir_p(temp_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:temp_dir_error, reason}}
    end
  end

  defp load_progress(%Config{resume: true} = config) do
    ProgressStore.load_or_create(config.progress_file, %{
      "output_dir" => config.output_dir,
      "started_at" => DateTime.to_iso8601(DateTime.utc_now())
    })
  end

  defp load_progress(%Config{resume: false} = config) do
    progress =
      Progress.new(%{
        "output_dir" => config.output_dir,
        "started_at" => DateTime.to_iso8601(DateTime.utc_now())
      })

    {:ok, progress, :new}
  end

  defp log_init(config, status) do
    Logger.info("Batch processor initialized")
    Logger.info("  Output directory: #{config.output_dir}")
    Logger.info("  Progress file: #{config.progress_file}")
    Logger.info("  Status: #{status}")

    if config.limit do
      Logger.info("  Limit: #{config.limit} packages")
    end

    if config.dry_run do
      Logger.info("  Mode: DRY RUN (no analysis)")
    end
  end

  defp run_processing(%State{} = state) do
    setup_signal_handlers()

    state =
      state.http_client
      |> get_package_stream(state.config)
      |> filter_packages()
      |> skip_processed(state.progress)
      |> maybe_limit(state.config.limit)
      |> Enum.reduce_while(state, fn package, acc_state ->
        if acc_state.interrupted do
          {:halt, acc_state}
        else
          updated_state = process_one_package(package, acc_state)
          {:cont, updated_state}
        end
      end)

    # Final save
    :ok = ProgressStore.save(state.progress, state.config.progress_file)

    summary = Progress.summary(state.progress)
    {:ok, summary}
  end

  defp get_package_stream(http_client, config) do
    case config.sort_by do
      :popularity ->
        # Fetch all packages first, sort by popularity, then stream
        Api.stream_all_packages_by_popularity(http_client,
          delay_ms: config.api_delay_ms,
          on_page: fn page ->
            if config.verbose do
              Logger.info("Fetching package list page #{page}...")
            end
          end
        )

      :alphabetical ->
        # Use API's default alphabetical sorting with streaming
        Api.stream_all_packages(http_client, page: config.start_page)
    end
  end

  defp filter_packages(stream) do
    Filter.filter_likely_elixir(stream)
  end

  defp skip_processed(stream, progress) do
    processed_names = Progress.processed_names(progress)

    Stream.reject(stream, fn package ->
      MapSet.member?(processed_names, package.name)
    end)
  end

  defp maybe_limit(stream, nil), do: stream
  defp maybe_limit(stream, limit), do: Stream.take(stream, limit)

  defp process_one_package(package, %State{} = state) do
    if state.config.verbose do
      Logger.info("Processing: #{package.name} @ #{Api.latest_stable_version(package)}")
    end

    start_time = System.monotonic_time(:millisecond)

    # Rate limiting
    state = %{state | rate_limiter: RateLimiter.acquire(state.rate_limiter)}

    # Process the package
    {result, state} = do_process_package(package, state)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    result = %{result | duration_ms: duration_ms}

    # Update progress
    progress = Progress.add_result(state.progress, result)
    state = %{state | progress: progress, processed_count: state.processed_count + 1}

    # Maybe checkpoint
    {:ok, progress} = ProgressStore.maybe_checkpoint(progress, state.config.progress_file)
    state = %{state | progress: progress}

    # Inter-package delay
    if state.config.delay_ms > 0 do
      Process.sleep(state.config.delay_ms)
    end

    state
  end

  defp do_process_package(package, %State{} = state) do
    version = Api.latest_stable_version(package)

    if state.config.dry_run do
      result = PackageResult.skipped(package.name, version, reason: "dry_run")
      {result, state}
    else
      process_package_with_handler(package, version, state)
    end
  end

  defp process_package_with_handler(package, version, %State{} = state) do
    result =
      PackageHandler.with_package(
        state.http_client,
        package.name,
        version,
        [temp_dir: state.config.temp_dir],
        fn context ->
          analyze_and_save(context, package.name, version, state)
        end
      )

    case result do
      {:ok, outcome} ->
        {outcome, state}

      {:error, reason} ->
        failure =
          FailureTracker.record_failure(package.name, version, reason, nil)

        if state.config.verbose do
          Logger.warning("Failed: #{package.name} - #{inspect(reason)}")
        end

        {failure, state}
    end
  rescue
    e ->
      stacktrace = __STACKTRACE__

      failure =
        FailureTracker.record_failure(package.name, version, e, stacktrace)

      if state.config.verbose do
        Logger.error("Exception: #{package.name} - #{Exception.message(e)}")
      end

      {failure, state}
  end

  defp analyze_and_save(context, name, version, %State{} = state) do
    # Verify Elixir source exists
    if Filter.has_elixir_source?(context.extract_dir) do
      do_analyze_and_save(context.extract_dir, name, version, state)
    else
      {:error, :no_elixir_source}
    end
  end

  defp do_analyze_and_save(source_path, name, version, %State{} = state) do
    analyze_config = %{
      base_iri_template: state.config.base_iri_template,
      timeout_minutes: state.config.timeout_minutes,
      version: version
    }

    case AnalyzerAdapter.analyze_package(source_path, name, analyze_config) do
      {:ok, graph, metadata} ->
        save_analysis_output(graph, name, version, metadata, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_analysis_output(graph, name, version, metadata, %State{} = state) do
    case OutputManager.save_graph(graph, state.config.output_dir, name, version) do
      {:ok, output_path} ->
        {:ok, PackageResult.success(name, version,
          output_path: output_path,
          module_count: metadata.module_count
        )}

      {:error, reason} ->
        {:error, {:output_error, reason}}
    end
  end

  defp setup_signal_handlers do
    # Trap exits so we can handle interruption
    Process.flag(:trap_exit, true)
  end

  @doc """
  Handles graceful shutdown on interruption.
  """
  @spec handle_interrupt(State.t()) :: State.t()
  def handle_interrupt(%State{} = state) do
    Logger.info("Interrupted - saving progress...")
    :ok = ProgressStore.save(state.progress, state.config.progress_file)
    %{state | interrupted: true}
  end
end
