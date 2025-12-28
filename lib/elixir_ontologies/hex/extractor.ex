defmodule ElixirOntologies.Hex.Extractor do
  @moduledoc """
  Tarball extraction for Hex.pm packages.

  Hex package tarballs have a specific structure:
  - Outer tar file containing:
    - VERSION - Hex package format version
    - CHECKSUM - Package checksum
    - metadata.config - Erlang term format metadata
    - contents.tar.gz - Gzipped tar of actual source code

  This module handles extracting both layers to access the source code.

  ## Security

  This module validates all extracted paths to prevent:
  - Path traversal attacks (e.g., `../../../etc/passwd`)
  - Symlink escapes outside target directory

  ## Usage

      # Full extraction pipeline
      {:ok, source_dir} = Extractor.extract("/tmp/phoenix-1.7.10.tar", "/tmp/phoenix")

      # Or step by step
      {:ok, outer_dir} = Extractor.extract_outer("/tmp/phoenix.tar", "/tmp/outer")
      {:ok, source_dir} = Extractor.extract_contents(outer_dir, "/tmp/source")
  """

  # Known safe files in hex outer tar
  @safe_outer_files ~w(VERSION CHECKSUM metadata.config contents.tar.gz)

  @doc """
  Extracts the outer tar file containing Hex metadata and contents.

  Only extracts known safe files: VERSION, CHECKSUM, metadata.config, contents.tar.gz.

  ## Returns

    * `{:ok, target_dir}` on success
    * `{:error, :invalid_tarball}` if structure is invalid
    * `{:error, reason}` for extraction failures
  """
  @spec extract_outer(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def extract_outer(tarball_path, target_dir) do
    File.mkdir_p!(target_dir)

    # Use safe extraction with file filtering for outer tar
    extract_opts = [
      {:cwd, to_charlist(target_dir)},
      {:files, Enum.map(@safe_outer_files, &to_charlist/1)}
    ]

    case :erl_tar.extract(to_charlist(tarball_path), extract_opts) do
      :ok ->
        # Verify expected structure
        contents_path = Path.join(target_dir, "contents.tar.gz")

        if File.exists?(contents_path) do
          {:ok, target_dir}
        else
          {:error, :invalid_tarball}
        end

      {:error, reason} ->
        {:error, {:tar_extract, reason}}
    end
  end

  @doc """
  Extracts the inner contents.tar.gz containing source code.

  ## Returns

    * `{:ok, target_dir}` on success
    * `{:error, :no_contents}` if contents.tar.gz not found
    * `{:error, reason}` for extraction failures
  """
  @spec extract_contents(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def extract_contents(outer_dir, target_dir) do
    contents_path = Path.join(outer_dir, "contents.tar.gz")

    if not File.exists?(contents_path) do
      {:error, :no_contents}
    else
      File.mkdir_p!(target_dir)

      case File.read(contents_path) do
        {:ok, compressed_data} ->
          extract_gzipped_tar(compressed_data, target_dir)

        {:error, reason} ->
          {:error, {:read_contents, reason}}
      end
    end
  end

  defp extract_gzipped_tar(compressed_data, target_dir) do
    try do
      # Decompress the gzip data
      decompressed = :zlib.gunzip(compressed_data)

      # Use safe extraction that validates paths
      safe_extract_tar(decompressed, target_dir)
    rescue
      e in ErlangError ->
        {:error, {:decompress, e.original}}
    end
  end

  # Safely extract tar by validating each file path
  defp safe_extract_tar(tar_data, target_dir) do
    target_dir_expanded = Path.expand(target_dir)

    # First, list the files to validate them
    case :erl_tar.table({:binary, tar_data}, [:verbose]) do
      {:ok, entries} ->
        # Validate all paths before extraction
        case validate_tar_entries(entries, target_dir_expanded) do
          :ok ->
            # All paths are safe, extract normally
            case :erl_tar.extract({:binary, tar_data}, [{:cwd, to_charlist(target_dir)}]) do
              :ok -> {:ok, target_dir}
              {:error, reason} -> {:error, {:tar_extract, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:tar_table, reason}}
    end
  end

  # Validate all tar entries for path safety
  defp validate_tar_entries(entries, target_dir) do
    Enum.reduce_while(entries, :ok, fn entry, _acc ->
      case validate_tar_entry(entry, target_dir) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Validate a single tar entry
  defp validate_tar_entry({name, type, _size, _mtime, _mode, _uid, _gid}, target_dir) do
    path = to_string(name)

    cond do
      # Reject symlinks - they can escape the target directory
      type == :symlink ->
        {:error, {:unsafe_symlink, path}}

      # Reject paths with traversal attempts
      String.contains?(path, "..") ->
        {:error, {:path_traversal, path}}

      # Reject absolute paths
      String.starts_with?(path, "/") ->
        {:error, {:absolute_path, path}}

      # Verify the final path stays within target directory
      not path_within_directory?(path, target_dir) ->
        {:error, {:path_escape, path}}

      true ->
        :ok
    end
  end

  # Handle simple entry format (just the name)
  defp validate_tar_entry(name, target_dir) when is_list(name) do
    validate_tar_entry({name, :regular, 0, 0, 0, 0, 0}, target_dir)
  end

  # Check if a relative path stays within the target directory
  defp path_within_directory?(relative_path, target_dir) do
    full_path = Path.expand(relative_path, target_dir)
    String.starts_with?(full_path, target_dir <> "/") or full_path == target_dir
  end

  @doc """
  Full extraction pipeline: extracts outer tar then contents.

  Creates a temporary directory for the outer tar extraction,
  extracts contents to the target directory, and cleans up.

  ## Returns

    * `{:ok, target_dir}` on success with path to source
    * `{:error, reason}` on failure
  """
  @spec extract(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def extract(tarball_path, target_dir) do
    # Create temp dir for outer extraction
    outer_temp = Path.join(Path.dirname(tarball_path), "outer_#{:erlang.phash2(make_ref())}")

    try do
      with {:ok, outer_dir} <- extract_outer(tarball_path, outer_temp),
           {:ok, source_dir} <- extract_contents(outer_dir, target_dir) do
        {:ok, source_dir}
      end
    after
      # Always clean up outer temp dir
      File.rm_rf(outer_temp)
    end
  end

  @doc """
  Extracts metadata from the outer tar directory.

  Parses the metadata.config file which is in Erlang term format.

  ## Returns

    * `{:ok, metadata_map}` on success
    * `{:error, reason}` if parsing fails
  """
  @spec extract_metadata(Path.t()) :: {:ok, map()} | {:error, term()}
  def extract_metadata(outer_dir) do
    metadata_path = Path.join(outer_dir, "metadata.config")

    if not File.exists?(metadata_path) do
      {:error, :no_metadata}
    else
      case :file.consult(to_charlist(metadata_path)) do
        {:ok, terms} ->
          metadata = terms_to_map(terms)
          {:ok, metadata}

        {:error, reason} ->
          {:error, {:parse_metadata, reason}}
      end
    end
  end

  defp terms_to_map(terms) when is_list(terms) do
    terms
    |> Enum.map(fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), convert_value(value)}

      {key, value} when is_binary(key) ->
        {key, convert_value(value)}

      {key, value} when is_list(key) ->
        {List.to_string(key), convert_value(value)}

      other ->
        other
    end)
    |> Map.new()
  end

  defp convert_value(value) when is_list(value) do
    if Enum.all?(value, &is_tuple/1) and Enum.all?(value, fn t -> tuple_size(t) == 2 end) do
      # Looks like a keyword list / proplist
      terms_to_map(value)
    else
      # Regular list - convert charlists to strings
      Enum.map(value, &convert_value/1)
    end
  end

  defp convert_value(value) when is_atom(value), do: Atom.to_string(value)

  defp convert_value(value) when is_binary(value), do: value

  defp convert_value(value), do: value

  @doc """
  Removes a directory and all its contents.

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  @spec cleanup(Path.t()) :: :ok | {:error, term()}
  def cleanup(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Removes a tarball file.

  ## Returns

    * `:ok` on success
    * `:ok` if file doesn't exist
    * `{:error, reason}` on failure
  """
  @spec cleanup_tarball(Path.t()) :: :ok | {:error, term()}
  def cleanup_tarball(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if an extracted package has a mix.exs file.
  """
  @spec has_mix_exs?(Path.t()) :: boolean()
  def has_mix_exs?(path) do
    path
    |> Path.join("mix.exs")
    |> File.exists?()
  end
end
