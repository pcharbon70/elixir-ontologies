defmodule Mix.Tasks.ElixirOntologies.HexBatch do
  @moduledoc """
  Analyzes all Elixir packages from hex.pm and generates RDF knowledge graphs.

  ## Usage

      # Analyze all packages to default output directory (.ttl/)
      mix elixir_ontologies.hex_batch

      # Analyze all packages to custom output directory
      mix elixir_ontologies.hex_batch /path/to/output

      # Resume interrupted processing
      mix elixir_ontologies.hex_batch --resume

      # Analyze with package limit (for testing)
      mix elixir_ontologies.hex_batch --limit 100

      # Analyze a single package
      mix elixir_ontologies.hex_batch --package phoenix

      # List packages without processing (dry run)
      mix elixir_ontologies.hex_batch --dry-run --limit 50

  ## Options

    * `--output-dir`, `-o` - Output directory path (default: .ttl)
    * `--progress-file` - Progress file path (default: OUTPUT_DIR/progress.json)
    * `--resume`, `-r` - Resume from progress file (default: true)
    * `--limit`, `-l` - Maximum number of packages to process
    * `--start-page` - Starting API page number (default: 1)
    * `--delay` - Delay between packages in milliseconds (default: 100)
    * `--timeout` - Per-package timeout in minutes (default: 5)
    * `--sort-by`, `-s` - Sort order: "popularity" or "alphabetical" (default: popularity)
    * `--package`, `-p` - Analyze a single package by name
    * `--dry-run` - List packages only, don't analyze
    * `--build-list` - Create progress.json with package list, don't analyze
    * `--quiet`, `-q` - Minimal output
    * `--verbose`, `-v` - Detailed output with timestamps

  ## Sort Order

  By default, packages are processed in popularity order:
  1. Recent downloads (descending)
  2. Total downloads (descending)
  3. Package name (ascending, as tiebreaker)

  This ensures the most important packages are analyzed first. Use `--sort-by alphabetical`
  to process packages in alphabetical order instead.

  ## Examples

      # Full batch analysis to default .ttl/ directory
      mix elixir_ontologies.hex_batch

      # Full batch analysis to custom directory
      mix elixir_ontologies.hex_batch ./hex_output

      # Process in alphabetical order
      mix elixir_ontologies.hex_batch --sort-by alphabetical

      # Resume after interruption
      mix elixir_ontologies.hex_batch --resume

      # Test with limited packages
      mix elixir_ontologies.hex_batch --limit 10 --verbose

      # Analyze single package for testing
      mix elixir_ontologies.hex_batch --package phoenix

      # Preview packages without processing
      mix elixir_ontologies.hex_batch --dry-run --limit 100

  ## Output

  Each successfully analyzed package produces a TTL file in the output directory
  (default: .ttl/):

      .ttl/
        phoenix-1.7.10.ttl
        ecto-3.11.0.ttl
        ...
        progress.json

  The progress.json file tracks processing state for resume capability.
  """

  use Mix.Task

  alias ElixirOntologies.Hex.Api
  alias ElixirOntologies.Hex.BatchProcessor
  alias ElixirOntologies.Hex.BatchProcessor.Config
  alias ElixirOntologies.Hex.Filter
  alias ElixirOntologies.Hex.HttpClient
  alias ElixirOntologies.Hex.PackageHandler
  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult
  alias ElixirOntologies.Hex.ProgressDisplay
  alias ElixirOntologies.Hex.ProgressStore
  alias ElixirOntologies.Hex.AnalyzerAdapter
  alias ElixirOntologies.Hex.OutputManager
  alias ElixirOntologies.Hex.Utils

  @shortdoc "Analyze all Elixir packages from hex.pm"

  @switches [
    output_dir: :string,
    progress_file: :string,
    resume: :boolean,
    limit: :integer,
    start_page: :integer,
    delay: :integer,
    timeout: :integer,
    package: :string,
    sort_by: :string,
    dry_run: :boolean,
    build_list: :boolean,
    quiet: :boolean,
    verbose: :boolean
  ]

  @aliases [
    o: :output_dir,
    r: :resume,
    l: :limit,
    p: :package,
    s: :sort_by,
    q: :quiet,
    v: :verbose
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Ensure required applications are started
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:jason)

    # Parse options
    {opts, remaining, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if invalid != [] do
      error("Invalid options: #{format_invalid(invalid)}")
      exit({:shutdown, 1})
    end

    # Get output directory from positional arg or option (default: .ttl)
    output_dir = get_output_dir(opts, remaining)

    # Build config
    config = build_config(output_dir, opts)

    # Handle different modes
    cond do
      opts[:package] ->
        run_single_package(opts[:package], config, opts)

      opts[:dry_run] ->
        run_dry_run(config, opts)

      opts[:build_list] ->
        run_build_list(config, opts)

      true ->
        run_batch(config, opts)
    end
  end

  defp get_output_dir(opts, remaining) do
    cond do
      opts[:output_dir] -> opts[:output_dir]
      remaining != [] -> hd(remaining)
      true -> ".ttl"
    end
  end

  defp build_config(output_dir, opts) do
    base_opts = [
      output_dir: output_dir,
      resume: Keyword.get(opts, :resume, true),
      limit: opts[:limit],
      start_page: Keyword.get(opts, :start_page, 1),
      delay_ms: Keyword.get(opts, :delay, 100),
      timeout_minutes: Keyword.get(opts, :timeout, 5),
      sort_by: parse_sort_by(opts[:sort_by]),
      dry_run: Keyword.get(opts, :dry_run, false),
      verbose: Keyword.get(opts, :verbose, false)
    ]

    # Only include progress_file if explicitly provided
    config_opts =
      if opts[:progress_file] do
        Keyword.put(base_opts, :progress_file, opts[:progress_file])
      else
        base_opts
      end

    Config.new(config_opts)
  end

  defp parse_sort_by(nil), do: :popularity
  defp parse_sort_by("popularity"), do: :popularity
  defp parse_sort_by("alphabetical"), do: :alphabetical
  defp parse_sort_by("alpha"), do: :alphabetical
  defp parse_sort_by(_), do: :popularity

  defp run_batch(%Config{} = config, opts) do
    quiet = opts[:quiet]

    unless quiet do
      ProgressDisplay.display_banner(%{
        output_dir: config.output_dir,
        limit: config.limit,
        resume: config.resume,
        dry_run: config.dry_run
      })
    end

    case BatchProcessor.run(config) do
      {:ok, summary} ->
        unless quiet do
          ProgressDisplay.display_summary_map(summary, %{
            output_dir: config.output_dir,
            progress_file: config.progress_file
          })
        end

        if summary.failed > 0 do
          exit({:shutdown, 1})
        else
          :ok
        end

      {:error, reason} ->
        error("Batch processing failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp run_single_package(package_name, %Config{} = config, opts) do
    quiet = opts[:quiet]
    verbose = opts[:verbose]

    unless quiet do
      IO.puts("Analyzing single package: #{package_name}")
      IO.puts("")
    end

    # Initialize HTTP client
    http_client = HttpClient.new()

    # Fetch package metadata
    case Api.get_package(http_client, package_name) do
      {:ok, package} ->
        version = Api.latest_stable_version(package)

        if verbose do
          ProgressDisplay.log_start(package_name, version)
        end

        start_time = System.monotonic_time(:millisecond)

        # Process the package
        result =
          PackageHandler.with_package(
            http_client,
            package_name,
            version,
            [temp_dir: config.temp_dir],
            fn context ->
              analyze_single(context, package_name, version, config)
            end
          )

        duration_ms = System.monotonic_time(:millisecond) - start_time

        case result do
          {:ok, %PackageResult{status: :completed} = pkg_result} ->
            if verbose do
              ProgressDisplay.log_complete(package_name, version, duration_ms)
            end

            unless quiet do
              IO.puts("Success: #{package_name} v#{version}")
              IO.puts("  Output: #{pkg_result.output_path}")
              IO.puts("  Modules: #{pkg_result.module_count || "unknown"}")
              IO.puts("  Duration: #{Utils.format_duration_ms(duration_ms)}")
            end

            :ok

          {:ok, %PackageResult{status: :failed} = pkg_result} ->
            if verbose do
              ProgressDisplay.log_error(package_name, version, pkg_result.error)
            end

            error("Failed: #{package_name} v#{version}")
            error("  Reason: #{pkg_result.error}")
            exit({:shutdown, 1})

          {:error, reason} ->
            if verbose do
              ProgressDisplay.log_error(package_name, version, reason)
            end

            error("Failed: #{package_name} v#{version}")
            error("  Reason: #{inspect(reason)}")
            exit({:shutdown, 1})
        end

      {:error, :not_found} ->
        error("Package not found: #{package_name}")
        exit({:shutdown, 1})

      {:error, reason} ->
        error("Failed to fetch package: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp analyze_single(context, name, version, config) do
    if Filter.has_elixir_source?(context.extract_dir) do
      analyze_config = %{
        base_iri_template: config.base_iri_template,
        timeout_minutes: config.timeout_minutes,
        version: version
      }

      case AnalyzerAdapter.analyze_package(context.extract_dir, name, analyze_config) do
        {:ok, graph, metadata} ->
          case OutputManager.save_graph(graph, config.output_dir, name, version) do
            {:ok, output_path} ->
              {:ok, PackageResult.success(name, version,
                output_path: output_path,
                module_count: metadata.module_count
              )}

            {:error, reason} ->
              {:ok, PackageResult.failure(name, version, error: inspect(reason))}
          end

        {:error, reason} ->
          {:ok, PackageResult.failure(name, version, error: inspect(reason))}
      end
    else
      {:ok, PackageResult.failure(name, version, error: "No Elixir source files found")}
    end
  end

  defp run_dry_run(%Config{} = config, opts) do
    quiet = opts[:quiet]

    unless quiet do
      IO.puts("Dry run - listing Elixir packages from hex.pm")
      IO.puts("Sort order: #{config.sort_by}")
      IO.puts("")
    end

    http_client = HttpClient.new()

    # Use the same sorting logic as batch processor
    package_stream = get_package_stream(http_client, config)

    packages =
      package_stream
      |> Filter.filter_elixir_packages(http_client, delay_ms: config.api_delay_ms || 500, verbose: config.verbose)
      |> maybe_limit(config.limit)
      |> Enum.with_index(1)

    count =
      Enum.reduce(packages, 0, fn {package, index}, _acc ->
        version = Api.latest_stable_version(package)

        unless quiet do
          ProgressDisplay.print_dry_run_package(package.name, version, index)
        end

        index
      end)

    unless quiet do
      ProgressDisplay.display_dry_run_summary(count)
    end

    :ok
  end

  defp run_build_list(%Config{} = config, opts) do
    quiet = opts[:quiet]

    unless quiet do
      IO.puts("Building package list from hex.pm...")
      IO.puts("Sort order: #{config.sort_by}")
      IO.puts("")
    end

    http_client = HttpClient.new()
    package_stream = get_package_stream(http_client, config)

    # Collect packages with progress display
    packages =
      package_stream
      |> Filter.filter_elixir_packages(http_client, delay_ms: config.api_delay_ms || 500, verbose: config.verbose)
      |> maybe_limit(config.limit)
      |> Stream.with_index(1)
      |> Enum.map(fn {package, index} ->
        version = Api.latest_stable_version(package)

        unless quiet do
          IO.write("\r  Fetching package #{index}...")
        end

        %{name: package.name, version: version, downloads: package.downloads}
      end)

    unless quiet do
      IO.puts("\r  Fetched #{length(packages)} packages.    ")
      IO.puts("")
    end

    # Build progress with pending packages
    progress = %Progress{
      Progress.new(%{output_dir: config.output_dir})
      | total_packages: length(packages)
    }

    # Save pending list as a separate JSON file
    pending_file = Path.join(config.output_dir, "pending.json")
    File.mkdir_p!(config.output_dir)

    pending_data = %{
      "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "sort_by" => Atom.to_string(config.sort_by),
      "total_packages" => length(packages),
      "packages" => Enum.map(packages, fn pkg ->
        %{"name" => pkg.name, "version" => pkg.version, "downloads" => pkg.downloads}
      end)
    }

    case File.write(pending_file, Jason.encode!(pending_data, pretty: true)) do
      :ok ->
        # Also save empty progress file
        ProgressStore.save(progress, config.progress_file)

        unless quiet do
          IO.puts("Package list created:")
          IO.puts("  Pending: #{pending_file}")
          IO.puts("  Progress: #{config.progress_file}")
          IO.puts("  Total packages: #{length(packages)}")
          IO.puts("")
          IO.puts("Run without --build-list to start processing.")
        end

        :ok

      {:error, reason} ->
        error("Failed to write pending file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp get_package_stream(http_client, config) do
    case config.sort_by do
      :popularity ->
        Api.stream_all_packages_by_popularity(http_client,
          delay_ms: config.api_delay_ms || 500
        )

      :alphabetical ->
        Api.stream_all_packages(http_client, page: config.start_page)
    end
  end

  defp maybe_limit(stream, nil), do: stream
  defp maybe_limit(stream, limit), do: Stream.take(stream, limit)

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)
  end

  defp error(message) do
    IO.puts(:stderr, "Error: #{message}")
  end
end
