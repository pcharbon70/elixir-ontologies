defmodule ElixirOntologies.Hex.ProgressStore do
  @moduledoc """
  JSON-based persistence for progress state.

  Provides atomic file operations for saving and loading progress,
  enabling resume capability after interruptions.

  ## Usage

      # Save progress
      :ok = ProgressStore.save(progress, "/tmp/progress.json")

      # Load progress
      {:ok, progress} = ProgressStore.load("/tmp/progress.json")

      # Load or create new
      {:ok, progress, :resumed} = ProgressStore.load_or_create(path, config)
      {:ok, progress, :new} = ProgressStore.load_or_create(path, config)
  """

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult
  alias ElixirOntologies.Hex.Utils

  @checkpoint_interval 10

  @doc """
  Converts progress to a JSON string.
  """
  @spec to_json(Progress.t()) :: String.t()
  def to_json(%Progress{} = progress) do
    progress
    |> to_map()
    |> Jason.encode!(pretty: true)
  end

  defp to_map(%Progress{} = progress) do
    %{
      "started_at" => datetime_to_string(progress.started_at),
      "updated_at" => datetime_to_string(progress.updated_at),
      "total_packages" => progress.total_packages,
      "processed" => Enum.map(progress.processed, &result_to_map/1),
      "current_page" => progress.current_page,
      "config" => progress.config
    }
  end

  defp result_to_map(%PackageResult{} = result) do
    %{
      "name" => result.name,
      "version" => result.version,
      "status" => Atom.to_string(result.status),
      "output_path" => result.output_path,
      "error" => result.error,
      "error_type" => if(result.error_type, do: Atom.to_string(result.error_type)),
      "duration_ms" => result.duration_ms,
      "module_count" => result.module_count,
      "processed_at" => datetime_to_string(result.processed_at)
    }
  end

  defp datetime_to_string(nil), do: nil
  defp datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @doc """
  Parses a JSON string to progress.
  """
  @spec from_json(String.t()) :: {:ok, Progress.t()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} ->
        progress = from_map(map)
        {:ok, progress}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp from_map(map) when is_map(map) do
    %Progress{
      started_at: Utils.parse_datetime(map["started_at"]),
      updated_at: Utils.parse_datetime(map["updated_at"]),
      total_packages: map["total_packages"],
      processed: Enum.map(map["processed"] || [], &result_from_map/1),
      current_page: map["current_page"] || 1,
      config: map["config"] || %{}
    }
  end

  defp result_from_map(map) when is_map(map) do
    %PackageResult{
      name: map["name"],
      version: map["version"],
      status: string_to_status(map["status"]),
      output_path: map["output_path"],
      error: map["error"],
      error_type: string_to_error_type(map["error_type"]),
      duration_ms: map["duration_ms"] || 0,
      module_count: map["module_count"],
      processed_at: Utils.parse_datetime(map["processed_at"])
    }
  end

  # Safe atom conversion - only allow known status values
  @known_statuses ~w(completed failed skipped)a
  @known_error_types ~w(
    download_error extraction_error analysis_error output_error
    timeout not_elixir unknown
  )a

  defp string_to_status(nil), do: nil

  defp string_to_status(str) when is_binary(str) do
    atom = String.to_existing_atom(str)
    if atom in @known_statuses, do: atom, else: nil
  rescue
    ArgumentError -> nil
  end

  defp string_to_error_type(nil), do: nil

  defp string_to_error_type(str) when is_binary(str) do
    atom = String.to_existing_atom(str)
    if atom in @known_error_types, do: atom, else: :unknown
  rescue
    ArgumentError -> :unknown
  end

  @doc """
  Saves progress to a file using atomic write.

  Uses a temporary file and rename to ensure atomicity.
  """
  @spec save(Progress.t(), Path.t()) :: :ok | {:error, term()}
  def save(%Progress{} = progress, file_path) do
    # Ensure parent directory exists
    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Write to temp file first (atomic write pattern)
    temp_path = "#{file_path}.tmp.#{:erlang.phash2(make_ref())}"
    json = to_json(progress)

    with :ok <- File.write(temp_path, json),
         :ok <- File.rename(temp_path, file_path) do
      :ok
    else
      {:error, reason} ->
        # Clean up temp file on failure
        File.rm(temp_path)
        {:error, reason}
    end
  end

  @doc """
  Loads progress from a file.
  """
  @spec load(Path.t()) :: {:ok, Progress.t()} | {:error, term()}
  def load(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        from_json(content)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads existing progress or creates new.

  Returns a tuple indicating whether progress was resumed or newly created.
  """
  @spec load_or_create(Path.t(), map()) :: {:ok, Progress.t(), :resumed | :new}
  def load_or_create(file_path, config \\ %{}) do
    case load(file_path) do
      {:ok, progress} ->
        # Update the config with any new values but preserve processed state
        updated_progress = %{progress | config: Map.merge(progress.config, config)}
        {:ok, updated_progress, :resumed}

      {:error, :not_found} ->
        progress = Progress.new(config)
        {:ok, progress, :new}

      {:error, {:invalid_json, _}} ->
        # Corrupted file - start fresh but log warning
        require Logger
        Logger.warning("Progress file corrupted, starting fresh: #{file_path}")
        progress = Progress.new(config)
        {:ok, progress, :new}

      {:error, _reason} ->
        # Other errors - start fresh
        progress = Progress.new(config)
        {:ok, progress, :new}
    end
  end

  @doc """
  Returns whether a checkpoint should be saved based on processed count.
  """
  @spec should_checkpoint?(Progress.t()) :: boolean()
  def should_checkpoint?(%Progress{} = progress) do
    count = Progress.processed_count(progress)
    count > 0 and rem(count, @checkpoint_interval) == 0
  end

  @doc """
  Saves a checkpoint if the interval has been reached.

  Always updates the `updated_at` timestamp before saving.
  """
  @spec checkpoint(Progress.t(), Path.t()) :: {:ok, Progress.t()} | {:error, term()}
  def checkpoint(%Progress{} = progress, file_path) do
    updated_progress = %{progress | updated_at: DateTime.utc_now()}

    case save(updated_progress, file_path) do
      :ok -> {:ok, updated_progress}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Conditionally checkpoints if the interval has been reached.
  """
  @spec maybe_checkpoint(Progress.t(), Path.t()) :: {:ok, Progress.t()}
  def maybe_checkpoint(%Progress{} = progress, file_path) do
    if should_checkpoint?(progress) do
      case checkpoint(progress, file_path) do
        {:ok, updated} -> {:ok, updated}
        {:error, _} -> {:ok, progress}
      end
    else
      {:ok, progress}
    end
  end

  @doc """
  Returns the checkpoint interval.
  """
  @spec checkpoint_interval() :: pos_integer()
  def checkpoint_interval, do: @checkpoint_interval
end
