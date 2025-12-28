defmodule ElixirOntologies.Hex.Progress do
  @moduledoc """
  Progress state tracking for Hex batch processing.

  Maintains state about processed packages enabling resume capability
  after interruptions and provides statistics about the batch run.

  ## Usage

      # Create new progress
      progress = Progress.new(%{output_dir: "/tmp/output"})

      # Add results
      progress = Progress.add_result(progress, %PackageResult{
        name: "phoenix",
        version: "1.7.10",
        status: :completed
      })

      # Check if already processed
      Progress.is_processed?(progress, "phoenix")
      # => true

      # Get summary
      Progress.summary(progress)
      # => %{total_processed: 1, succeeded: 1, failed: 0, ...}
  """

  defmodule PackageResult do
    @moduledoc """
    Result of processing a single package.
    """

    @type status :: :completed | :failed | :skipped

    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            status: status(),
            output_path: String.t() | nil,
            error: String.t() | nil,
            error_type: atom() | nil,
            duration_ms: non_neg_integer(),
            module_count: non_neg_integer() | nil,
            processed_at: DateTime.t()
          }

    defstruct [
      :name,
      :version,
      :status,
      :output_path,
      :error,
      :error_type,
      :duration_ms,
      :module_count,
      :processed_at
    ]

    @doc """
    Creates a new successful result.
    """
    @spec success(String.t(), String.t(), keyword()) :: t()
    def success(name, version, opts \\ []) do
      %__MODULE__{
        name: name,
        version: version,
        status: :completed,
        output_path: Keyword.get(opts, :output_path),
        duration_ms: Keyword.get(opts, :duration_ms, 0),
        module_count: Keyword.get(opts, :module_count),
        processed_at: DateTime.utc_now()
      }
    end

    @doc """
    Creates a new failure result.
    """
    @spec failure(String.t(), String.t(), keyword()) :: t()
    def failure(name, version, opts \\ []) do
      %__MODULE__{
        name: name,
        version: version,
        status: :failed,
        error: Keyword.get(opts, :error),
        error_type: Keyword.get(opts, :error_type, :unknown),
        duration_ms: Keyword.get(opts, :duration_ms, 0),
        processed_at: DateTime.utc_now()
      }
    end

    @doc """
    Creates a skipped result.
    """
    @spec skipped(String.t(), String.t(), keyword()) :: t()
    def skipped(name, version, opts \\ []) do
      %__MODULE__{
        name: name,
        version: version,
        status: :skipped,
        error: Keyword.get(opts, :reason),
        error_type: Keyword.get(opts, :error_type),
        duration_ms: 0,
        processed_at: DateTime.utc_now()
      }
    end
  end

  @type t :: %__MODULE__{
          started_at: DateTime.t(),
          updated_at: DateTime.t(),
          total_packages: non_neg_integer() | nil,
          processed: [PackageResult.t()],
          current_page: pos_integer(),
          config: map()
        }

  defstruct [
    :started_at,
    :updated_at,
    :total_packages,
    processed: [],
    current_page: 1,
    config: %{}
  ]

  @doc """
  Creates new progress state with the given configuration.
  """
  @spec new(map()) :: t()
  def new(config \\ %{}) do
    now = DateTime.utc_now()

    %__MODULE__{
      started_at: now,
      updated_at: now,
      config: config
    }
  end

  @doc """
  Adds a package result to the progress.
  """
  @spec add_result(t(), PackageResult.t()) :: t()
  def add_result(%__MODULE__{} = progress, %PackageResult{} = result) do
    %{progress | processed: [result | progress.processed], updated_at: DateTime.utc_now()}
  end

  @doc """
  Updates the current page number.
  """
  @spec update_page(t(), pos_integer()) :: t()
  def update_page(%__MODULE__{} = progress, page) when is_integer(page) and page > 0 do
    %{progress | current_page: page, updated_at: DateTime.utc_now()}
  end

  @doc """
  Sets the total package count.
  """
  @spec set_total(t(), non_neg_integer()) :: t()
  def set_total(%__MODULE__{} = progress, total) when is_integer(total) and total >= 0 do
    %{progress | total_packages: total, updated_at: DateTime.utc_now()}
  end

  @doc """
  Checks if a package has already been processed.
  """
  @spec is_processed?(t(), String.t()) :: boolean()
  def is_processed?(%__MODULE__{processed: processed}, name) when is_binary(name) do
    Enum.any?(processed, fn result -> result.name == name end)
  end

  @doc """
  Returns the count of processed packages.
  """
  @spec processed_count(t()) :: non_neg_integer()
  def processed_count(%__MODULE__{processed: processed}) do
    length(processed)
  end

  @doc """
  Returns the count of successfully completed packages.
  """
  @spec success_count(t()) :: non_neg_integer()
  def success_count(%__MODULE__{processed: processed}) do
    Enum.count(processed, fn r -> r.status == :completed end)
  end

  @doc """
  Returns the count of failed packages.
  """
  @spec failed_count(t()) :: non_neg_integer()
  def failed_count(%__MODULE__{processed: processed}) do
    Enum.count(processed, fn r -> r.status == :failed end)
  end

  @doc """
  Returns the count of skipped packages.
  """
  @spec skipped_count(t()) :: non_neg_integer()
  def skipped_count(%__MODULE__{processed: processed}) do
    Enum.count(processed, fn r -> r.status == :skipped end)
  end

  @doc """
  Returns all processed package names as a set for fast lookup.
  """
  @spec processed_names(t()) :: MapSet.t()
  def processed_names(%__MODULE__{processed: processed}) do
    processed
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  @doc """
  Returns a summary of the progress.
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = progress) do
    total_processed = processed_count(progress)
    succeeded = success_count(progress)
    failed = failed_count(progress)
    skipped = skipped_count(progress)

    duration_seconds = elapsed_seconds(progress)

    avg_duration_ms =
      if total_processed > 0 do
        total_ms = Enum.sum(Enum.map(progress.processed, & &1.duration_ms))
        div(total_ms, total_processed)
      else
        0
      end

    estimated_remaining =
      estimate_remaining_seconds(progress, total_processed, avg_duration_ms)

    %{
      total_processed: total_processed,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      current_page: progress.current_page,
      duration_seconds: duration_seconds,
      avg_duration_ms: avg_duration_ms,
      estimated_remaining_seconds: estimated_remaining,
      success_rate: if(total_processed > 0, do: succeeded / total_processed * 100, else: 0.0)
    }
  end

  defp elapsed_seconds(%__MODULE__{started_at: started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  defp estimate_remaining_seconds(progress, total_processed, avg_duration_ms) do
    case progress.total_packages do
      nil ->
        nil

      total when total > total_processed ->
        remaining = total - total_processed
        div(remaining * avg_duration_ms, 1000)

      _ ->
        0
    end
  end

  @doc """
  Formats the summary as a human-readable string.
  """
  @spec format_summary(t()) :: String.t()
  def format_summary(%__MODULE__{} = progress) do
    stats = summary(progress)

    duration_str = format_duration(stats.duration_seconds)

    remaining_str =
      case stats.estimated_remaining_seconds do
        nil -> "unknown"
        secs -> format_duration(secs)
      end

    """
    Progress Summary:
      Processed: #{stats.total_processed}#{if progress.total_packages, do: " / #{progress.total_packages}", else: ""}
      Succeeded: #{stats.succeeded} (#{Float.round(stats.success_rate, 1)}%)
      Failed: #{stats.failed}
      Skipped: #{stats.skipped}
      Duration: #{duration_str}
      Avg per package: #{stats.avg_duration_ms}ms
      Estimated remaining: #{remaining_str}
    """
  end

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds}s"
  end

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end
end
