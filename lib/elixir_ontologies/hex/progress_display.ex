defmodule ElixirOntologies.Hex.ProgressDisplay do
  @moduledoc """
  Console progress reporting for batch processing.

  Provides status line updates, ETA calculations, and summary display
  for the Hex batch analyzer CLI.

  ## Usage

      # Display status line
      ProgressDisplay.status_line(progress, "phoenix", "1.7.10")

      # Display final summary
      ProgressDisplay.display_summary(progress)
  """

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Utils

  @doc """
  Formats a single-line status display.

  Format: `[123/15000] phoenix v1.7.10 - 45% complete`
  """
  @spec status_line(Progress.t(), String.t(), String.t()) :: String.t()
  def status_line(%Progress{} = progress, package_name, version) do
    processed = Progress.processed_count(progress)
    total = progress.total_packages

    percentage_str =
      if total && total > 0 do
        pct = Float.round(processed / total * 100, 1)
        " - #{pct}% complete"
      else
        ""
      end

    count_str =
      if total do
        "[#{processed}/#{total}]"
      else
        "[#{processed}]"
      end

    "#{count_str} #{package_name} v#{version}#{percentage_str}"
  end

  @doc """
  Prints a status line with carriage return for overwriting.
  """
  @spec print_status(Progress.t(), String.t(), String.t()) :: :ok
  def print_status(%Progress{} = progress, package_name, version) do
    line = status_line(progress, package_name, version)
    IO.write("\r#{clear_line()}#{line}")
    :ok
  end

  defp clear_line do
    # ANSI escape code to clear line
    "\e[K"
  end

  @doc """
  Calculates estimated time remaining in seconds.
  """
  @spec calculate_eta(Progress.t()) :: non_neg_integer() | nil
  def calculate_eta(%Progress{} = progress) do
    processed = Progress.processed_count(progress)
    total = progress.total_packages

    if processed > 0 && total && total > processed do
      # Calculate average duration per package
      total_duration_ms =
        progress.processed
        |> Enum.map(& &1.duration_ms)
        |> Enum.sum()

      avg_duration_ms = div(total_duration_ms, processed)
      remaining = total - processed

      # Convert to seconds
      div(avg_duration_ms * remaining, 1000)
    else
      nil
    end
  end

  @doc """
  Formats ETA as human-readable string.

  Examples: "2h 15m", "45m 30s", "30s"
  """
  @spec format_eta(non_neg_integer() | nil) :: String.t()
  def format_eta(nil), do: "calculating..."

  def format_eta(seconds) when seconds >= 3600 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  def format_eta(seconds) when seconds >= 60 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  def format_eta(seconds) do
    "#{seconds}s"
  end

  @doc """
  Formats statistics line with success/fail/skip counts.

  Format: `✓ 100 ✗ 5 ⊘ 10` (with colors if supported)
  """
  @spec stats_line(Progress.t()) :: String.t()
  def stats_line(%Progress{} = progress) do
    success = Progress.success_count(progress)
    failed = Progress.failed_count(progress)
    skipped = Progress.skipped_count(progress)

    if supports_color?() do
      [
        color(:green, "✓ #{success}"),
        color(:red, "✗ #{failed}"),
        color(:yellow, "⊘ #{skipped}")
      ]
      |> Enum.join(" ")
    else
      "ok:#{success} fail:#{failed} skip:#{skipped}"
    end
  end

  @doc """
  Checks if the terminal supports ANSI colors.
  """
  @spec supports_color?() :: boolean()
  def supports_color? do
    System.get_env("NO_COLOR") == nil &&
      (System.get_env("TERM") != "dumb" || System.get_env("COLORTERM") != nil)
  end

  defp color(name, text) do
    code =
      case name do
        :green -> "\e[32m"
        :red -> "\e[31m"
        :yellow -> "\e[33m"
        :cyan -> "\e[36m"
        :bold -> "\e[1m"
        _ -> ""
      end

    "#{code}#{text}\e[0m"
  end

  @doc """
  Logs package processing start (verbose mode).
  """
  @spec log_start(String.t(), String.t()) :: :ok
  def log_start(name, version) do
    timestamp = format_timestamp()
    IO.puts("[#{timestamp}] Starting: #{name} v#{version}")
    :ok
  end

  @doc """
  Logs package processing completion (verbose mode).
  """
  @spec log_complete(String.t(), String.t(), non_neg_integer()) :: :ok
  def log_complete(name, version, duration_ms) do
    timestamp = format_timestamp()
    duration_str = Utils.format_duration_ms(duration_ms)
    IO.puts("[#{timestamp}] Complete: #{name} v#{version} (#{duration_str})")
    :ok
  end

  @doc """
  Logs package processing error (verbose mode).
  """
  @spec log_error(String.t(), String.t(), term()) :: :ok
  def log_error(name, version, reason) do
    timestamp = format_timestamp()
    reason_str = format_error_reason(reason)

    if supports_color?() do
      IO.puts("[#{timestamp}] #{color(:red, "Error")}: #{name} v#{version} - #{reason_str}")
    else
      IO.puts("[#{timestamp}] Error: #{name} v#{version} - #{reason_str}")
    end

    :ok
  end

  @doc """
  Logs package skipped (verbose mode).
  """
  @spec log_skip(String.t(), String.t(), String.t()) :: :ok
  def log_skip(name, version, reason \\ "not Elixir") do
    timestamp = format_timestamp()

    if supports_color?() do
      IO.puts("[#{timestamp}] #{color(:yellow, "Skip")}: #{name} v#{version} - #{reason}")
    else
      IO.puts("[#{timestamp}] Skip: #{name} v#{version} - #{reason}")
    end

    :ok
  end

  defp format_timestamp do
    {{_y, _mo, _d}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end

  defp format_error_reason(reason) when is_binary(reason), do: reason
  defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_reason(reason), do: inspect(reason, limit: 50)

  @doc """
  Displays final summary after batch completion.
  """
  @spec display_summary(Progress.t(), map()) :: :ok
  def display_summary(%Progress{} = progress, config \\ %{}) do
    summary = Progress.summary(progress)

    IO.puts("")
    IO.puts(separator())
    IO.puts(header("Batch Processing Complete"))
    IO.puts(separator())
    IO.puts("")

    # Results
    IO.puts("Results:")
    IO.puts("  Total processed: #{summary.total_processed}")
    IO.puts("  Succeeded:       #{summary.succeeded}")
    IO.puts("  Failed:          #{summary.failed}")
    IO.puts("  Skipped:         #{summary.skipped}")
    IO.puts("")

    # Timing
    if summary.total_processed > 0 do
      IO.puts("Timing:")
      IO.puts("  Total duration:    #{format_total_duration(progress)}")
      IO.puts("  Average per pkg:   #{Utils.format_duration_ms(summary.avg_duration_ms)}")
      IO.puts("")
    end

    # Paths
    output_dir = Map.get(config, :output_dir) || Map.get(config, "output_dir")
    progress_file = Map.get(config, :progress_file) || Map.get(config, "progress_file")

    if output_dir || progress_file do
      IO.puts("Output:")

      if output_dir do
        IO.puts("  Output directory:  #{output_dir}")
      end

      if progress_file do
        IO.puts("  Progress file:     #{progress_file}")
      end

      IO.puts("")
    end

    # Retry suggestion
    if summary.failed > 0 do
      IO.puts("To retry failed packages, run again with --resume")
      IO.puts("")
    end

    IO.puts(separator())
    :ok
  end

  defp separator do
    String.duplicate("=", 60)
  end

  defp header(text) do
    if supports_color?() do
      color(:bold, text)
    else
      text
    end
  end

  defp format_total_duration(%Progress{} = progress) do
    if progress.started_at do
      diff_seconds = DateTime.diff(DateTime.utc_now(), progress.started_at)
      format_eta(diff_seconds)
    else
      "unknown"
    end
  end

  @doc """
  Displays a startup banner.
  """
  @spec display_banner(map()) :: :ok
  def display_banner(config) do
    IO.puts(separator())
    IO.puts(header("Hex.pm Batch Analyzer"))
    IO.puts(separator())
    IO.puts("")

    output_dir = Map.get(config, :output_dir)
    limit = Map.get(config, :limit)
    resume = Map.get(config, :resume)
    dry_run = Map.get(config, :dry_run)

    IO.puts("Configuration:")
    IO.puts("  Output directory: #{output_dir}")

    if limit do
      IO.puts("  Package limit:    #{limit}")
    end

    if resume do
      IO.puts("  Resume mode:      enabled")
    end

    if dry_run do
      IO.puts("  Dry run:          enabled (no analysis)")
    end

    IO.puts("")
    :ok
  end

  @doc """
  Displays dry run package list entry.
  """
  @spec print_dry_run_package(String.t(), String.t(), non_neg_integer()) :: :ok
  def print_dry_run_package(name, version, index) do
    IO.puts("  #{index}. #{name} v#{version}")
    :ok
  end

  @doc """
  Displays dry run summary.
  """
  @spec display_dry_run_summary(non_neg_integer()) :: :ok
  def display_dry_run_summary(count) do
    IO.puts("")
    IO.puts("Total Elixir packages found: #{count}")
    IO.puts("")
    IO.puts("Run without --dry-run to process these packages.")
    :ok
  end
end
