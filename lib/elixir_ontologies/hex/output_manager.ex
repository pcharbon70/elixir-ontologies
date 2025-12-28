defmodule ElixirOntologies.Hex.OutputManager do
  @moduledoc """
  Manages TTL output file organization and naming.

  Handles path generation, directory management, graph saving,
  and disk space monitoring for batch processing output.

  ## Usage

      # Generate output path
      path = OutputManager.output_path("/output", "phoenix", "1.7.10")
      # => "/output/phoenix-1.7.10.ttl"

      # Save graph to output directory
      {:ok, path} = OutputManager.save_graph(graph, "/output", "phoenix", "1.7.10")

      # List existing outputs
      outputs = OutputManager.list_outputs("/output")
  """

  alias ElixirOntologies.Graph

  @min_disk_space_mb 500
  @min_disk_space_bytes @min_disk_space_mb * 1024 * 1024

  @doc """
  Generates the output file path for a package.

  Package names are sanitized for filesystem safety.

  ## Examples

      iex> OutputManager.output_path("/output", "phoenix", "1.7.10")
      "/output/phoenix-1.7.10.ttl"

      iex> OutputManager.output_path("/output", "my/package", "1.0.0")
      "/output/my_package-1.0.0.ttl"
  """
  @spec output_path(Path.t(), String.t(), String.t()) :: Path.t()
  def output_path(output_dir, name, version) do
    safe_name = sanitize_name(name)
    safe_version = sanitize_name(version)
    filename = "#{safe_name}-#{safe_version}.ttl"
    Path.join(output_dir, filename)
  end

  @doc """
  Sanitizes a name for filesystem safety.

  Replaces unsafe characters with underscores.
  """
  @spec sanitize_name(String.t()) :: String.t()
  def sanitize_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[\/\\:*?"<>|]/, "_")
    |> String.replace(~r/\.\./, "_")
    |> String.trim("_")
  end

  @doc """
  Ensures the output directory exists and is writable.

  Creates the directory if it doesn't exist.
  """
  @spec ensure_output_dir(Path.t()) :: :ok | {:error, term()}
  def ensure_output_dir(output_dir) do
    case File.mkdir_p(output_dir) do
      :ok ->
        verify_writable(output_dir)

      {:error, reason} ->
        {:error, {:mkdir_failed, reason}}
    end
  end

  defp verify_writable(output_dir) do
    test_file = Path.join(output_dir, ".write_test_#{:rand.uniform(100_000)}")

    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)
        :ok

      {:error, reason} ->
        {:error, {:not_writable, reason}}
    end
  end

  @doc """
  Saves an RDF graph to the output directory.

  Returns `{:ok, path}` on success or `{:error, reason}` on failure.
  """
  @spec save_graph(Graph.t(), Path.t(), String.t(), String.t()) ::
          {:ok, Path.t()} | {:error, term()}
  def save_graph(%Graph{} = graph, output_dir, name, version) do
    path = output_path(output_dir, name, version)

    # Ensure parent directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    case Graph.save(graph, path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:file_write, reason}}
    end
  end

  @doc """
  Lists existing output files in the output directory.

  Returns a list of `{name, version, path}` tuples.
  """
  @spec list_outputs(Path.t()) :: [{String.t(), String.t(), Path.t()}]
  def list_outputs(output_dir) do
    pattern = Path.join(output_dir, "*.ttl")

    pattern
    |> Path.wildcard()
    |> Enum.map(&parse_output_filename/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_output_filename(path) do
    filename = Path.basename(path, ".ttl")

    case String.split(filename, "-", parts: 2) do
      [name, version] when name != "" and version != "" ->
        {name, version, path}

      _ ->
        nil
    end
  end

  @doc """
  Checks if output exists for a specific package.
  """
  @spec output_exists?(Path.t(), String.t(), String.t()) :: boolean()
  def output_exists?(output_dir, name, version) do
    path = output_path(output_dir, name, version)
    File.exists?(path)
  end

  @doc """
  Checks available disk space for the output directory.

  Returns `{:ok, bytes}` with available bytes or `{:error, reason}`.
  """
  @spec check_disk_space(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def check_disk_space(output_dir) do
    # Ensure directory exists for the check
    File.mkdir_p!(output_dir)

    # Use df command to check available space
    case System.cmd("df", ["-B1", "--output=avail", output_dir], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse the output - second line contains the bytes
        case output |> String.trim() |> String.split("\n") |> Enum.at(1) do
          nil ->
            {:error, :parse_failed}

          bytes_str ->
            case Integer.parse(String.trim(bytes_str)) do
              {bytes, _} -> {:ok, bytes}
              :error -> {:error, :parse_failed}
            end
        end

      {error, _code} ->
        {:error, {:df_failed, error}}
    end
  rescue
    e -> {:error, {:system_error, e}}
  end

  @doc """
  Warns if disk space is below threshold.

  Returns `:ok` if space is sufficient, or `:low_disk_space` if below threshold.
  """
  @spec warn_if_low(Path.t(), non_neg_integer()) :: :ok | :low_disk_space
  def warn_if_low(output_dir, threshold_bytes \\ @min_disk_space_bytes) do
    case check_disk_space(output_dir) do
      {:ok, bytes} when bytes < threshold_bytes ->
        require Logger

        Logger.warning(
          "Low disk space: #{format_bytes(bytes)} available (threshold: #{format_bytes(threshold_bytes)})"
        )

        :low_disk_space

      {:ok, _bytes} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Could not check disk space: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Formats bytes as human-readable string.
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  def format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  def format_bytes(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  def format_bytes(bytes) do
    "#{bytes} bytes"
  end

  @doc """
  Returns the minimum disk space threshold in bytes.
  """
  @spec min_disk_space_bytes() :: non_neg_integer()
  def min_disk_space_bytes, do: @min_disk_space_bytes

  @doc """
  Returns the minimum disk space threshold in megabytes.
  """
  @spec min_disk_space_mb() :: non_neg_integer()
  def min_disk_space_mb, do: @min_disk_space_mb
end
