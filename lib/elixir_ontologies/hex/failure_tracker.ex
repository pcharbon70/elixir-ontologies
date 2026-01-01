defmodule ElixirOntologies.Hex.FailureTracker do
  @moduledoc """
  Failure tracking and classification for Hex batch processing.

  Categorizes errors by type for debugging and determines which
  failures are candidates for retry.

  ## Error Types

    * `:download_error` - Network/HTTP failures
    * `:extraction_error` - Tarball unpacking failures
    * `:analysis_error` - ProjectAnalyzer failures
    * `:output_error` - TTL writing failures
    * `:timeout` - Processing timeout
    * `:not_elixir` - Erlang-only package
    * `:unknown` - Unclassified errors

  ## Usage

      # Classify an error
      type = FailureTracker.classify_error({:error, :not_found})
      # => :download_error

      # Record a failure
      result = FailureTracker.record_failure("phoenix", "1.7.10", error, stacktrace)

      # Analyze failures
      by_type = FailureTracker.failures_by_type(progress.processed)
      retryable = FailureTracker.retry_candidates(progress.processed)
  """

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult

  @error_types [
    :download_error,
    :extraction_error,
    :analysis_error,
    :output_error,
    :timeout,
    :not_elixir,
    :unknown
  ]

  @retryable_types [:download_error, :timeout, :extraction_error]

  @doc """
  Returns the list of defined error types.
  """
  @spec error_types() :: [atom()]
  def error_types, do: @error_types

  @doc """
  Classifies an error term into an error type.
  """
  @spec classify_error(term()) :: atom()
  def classify_error(error) do
    cond do
      download_error?(error) -> :download_error
      extraction_error?(error) -> :extraction_error
      not_elixir_error?(error) -> :not_elixir
      output_error?(error) -> :output_error
      timeout_error?(error) -> :timeout
      analysis_error?(error) -> :analysis_error
      true -> :unknown
    end
  end

  # Download/network error detection
  defp download_error?(:not_found), do: true
  defp download_error?(:rate_limited), do: true
  defp download_error?({:http_error, _}), do: true
  defp download_error?({:error, :not_found}), do: true
  defp download_error?({:error, :rate_limited}), do: true
  defp download_error?({:error, {:http_error, _}}), do: true
  defp download_error?(%{__struct__: Req.TransportError}), do: true
  defp download_error?(%{__struct__: Mint.TransportError}), do: true
  defp download_error?(_), do: false

  # Extraction error detection
  defp extraction_error?(:invalid_tarball), do: true
  defp extraction_error?(:no_contents), do: true
  defp extraction_error?({:tar_extract, _}), do: true
  defp extraction_error?({:tar_table, _}), do: true
  defp extraction_error?({:path_traversal, _}), do: true
  defp extraction_error?({:absolute_path, _}), do: true
  defp extraction_error?({:path_escape, _}), do: true
  defp extraction_error?({:unsafe_symlink, _}), do: true
  defp extraction_error?({:decompress, _}), do: true
  defp extraction_error?({:error, :invalid_tarball}), do: true
  defp extraction_error?({:error, :no_contents}), do: true
  defp extraction_error?({:error, {:tar_extract, _}}), do: true
  defp extraction_error?({:error, {:decompress, _}}), do: true
  defp extraction_error?({:error, {:path_traversal, _}}), do: true
  defp extraction_error?({:error, {:unsafe_symlink, _}}), do: true
  defp extraction_error?(_), do: false

  # Not Elixir package detection
  defp not_elixir_error?(:not_elixir), do: true
  defp not_elixir_error?(:no_mix_exs), do: true
  defp not_elixir_error?(:no_elixir_source), do: true
  defp not_elixir_error?({:error, :not_elixir}), do: true
  defp not_elixir_error?({:error, :no_mix_exs}), do: true
  defp not_elixir_error?({:error, :no_elixir_source}), do: true
  defp not_elixir_error?(_), do: false

  # Output error detection
  defp output_error?({:file_write, _}), do: true
  defp output_error?({:output_error, _}), do: true
  defp output_error?({:error, {:file_write, _}}), do: true
  defp output_error?({:error, {:output_error, _}}), do: true
  defp output_error?(_), do: false

  # Timeout error detection
  defp timeout_error?(:timeout), do: true
  defp timeout_error?({:error, :timeout}), do: true
  defp timeout_error?(_), do: false

  # Analysis error detection (exceptions)
  defp analysis_error?(%{__exception__: true}), do: true
  defp analysis_error?(_), do: false

  @doc """
  Records a failure and creates a PackageResult.

  Formats the error and optional stacktrace for logging.
  """
  @spec record_failure(String.t(), String.t(), term(), list() | nil, keyword()) ::
          PackageResult.t()
  def record_failure(name, version, error, stacktrace \\ nil, opts \\ []) do
    error_type = classify_error(error)
    error_message = format_error(error, stacktrace)
    duration_ms = Keyword.get(opts, :duration_ms, 0)

    PackageResult.failure(name, version,
      error: error_message,
      error_type: error_type,
      duration_ms: duration_ms
    )
  end

  defp format_error(error, nil) do
    inspect(error, limit: :infinity)
  end

  defp format_error(error, stacktrace) when is_list(stacktrace) do
    error_str = inspect(error, limit: :infinity)

    # Take first 5 stack frames
    stack_str =
      stacktrace
      |> Enum.take(5)
      |> Enum.map_join("\n  ", &Exception.format_stacktrace_entry/1)

    if stack_str != "" do
      "#{error_str}\n  #{stack_str}"
    else
      error_str
    end
  end

  @doc """
  Groups failed results by error type.
  """
  @spec failures_by_type([PackageResult.t()]) :: %{atom() => [PackageResult.t()]}
  def failures_by_type(results) when is_list(results) do
    results
    |> Enum.filter(&(&1.status == :failed))
    |> Enum.group_by(& &1.error_type)
  end

  @doc """
  Returns failures that are candidates for retry.

  Retryable errors include `:download_error`, `:timeout`, and `:extraction_error`.
  Non-retryable errors include `:not_elixir` and `:analysis_error`.
  """
  @spec retry_candidates([PackageResult.t()]) :: [PackageResult.t()]
  def retry_candidates(results) when is_list(results) do
    results
    |> Enum.filter(fn result ->
      result.status == :failed and result.error_type in @retryable_types
    end)
  end

  @doc """
  Returns the count of failures by type.
  """
  @spec failure_counts([PackageResult.t()]) :: %{atom() => non_neg_integer()}
  def failure_counts(results) when is_list(results) do
    results
    |> failures_by_type()
    |> Map.new(fn {type, list} -> {type, length(list)} end)
  end

  @doc """
  Exports failures to a JSON file for analysis.
  """
  @spec export_failures(Progress.t(), Path.t()) :: :ok | {:error, term()}
  def export_failures(%Progress{} = progress, file_path) do
    by_type = failures_by_type(progress.processed)
    counts = failure_counts(progress.processed)

    export_data = %{
      "exported_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "summary" => %{
        "total_failures" => Progress.failed_count(progress),
        "by_type" => counts
      },
      "failures" =>
        Map.new(by_type, fn {type, results} ->
          {Atom.to_string(type),
           Enum.map(results, fn r ->
             %{
               "name" => r.name,
               "version" => r.version,
               "error" => r.error,
               "processed_at" => DateTime.to_iso8601(r.processed_at)
             }
           end)}
        end)
    }

    json = Jason.encode!(export_data, pretty: true)

    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write(file_path, json)
  end

  @doc """
  Formats a failure summary for logging.
  """
  @spec format_failure_summary([PackageResult.t()]) :: String.t()
  def format_failure_summary(results) when is_list(results) do
    counts = failure_counts(results)
    total = Enum.sum(Map.values(counts))

    if total == 0 do
      "No failures"
    else
      type_summary =
        counts
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.map_join("\n", fn {type, count} -> "  #{type}: #{count}" end)

      "Failures (#{total} total):\n#{type_summary}"
    end
  end
end
