defmodule ElixirOntologies.Hex.Downloader do
  @moduledoc """
  Package tarball downloader for Hex.pm packages.

  Downloads package tarballs from repo.hex.pm for extraction and analysis.

  ## Usage

      client = ElixirOntologies.Hex.HttpClient.new()

      # Download to specific path
      {:ok, path} = Downloader.download(client, "phoenix", "1.7.10", "/tmp/phoenix.tar")

      # Download to temporary directory
      {:ok, tarball_path, temp_dir} = Downloader.download_to_temp(client, "phoenix", "1.7.10")
  """

  alias ElixirOntologies.Hex.HttpClient

  @repo_url "https://repo.hex.pm"
  @tarball_path "/tarballs"

  @doc """
  Generates the download URL for a package tarball.

  ## Examples

      iex> Downloader.tarball_url("phoenix", "1.7.10")
      "https://repo.hex.pm/tarballs/phoenix-1.7.10.tar"
  """
  @spec tarball_url(String.t(), String.t()) :: String.t()
  def tarball_url(name, version) do
    encoded_name = URI.encode(name)
    "#{@repo_url}#{@tarball_path}/#{encoded_name}-#{version}.tar"
  end

  @doc """
  Generates the filename for a package tarball.

  ## Examples

      iex> Downloader.tarball_filename("phoenix", "1.7.10")
      "phoenix-1.7.10.tar"
  """
  @spec tarball_filename(String.t(), String.t()) :: String.t()
  def tarball_filename(name, version) do
    "#{name}-#{version}.tar"
  end

  @doc """
  Downloads a package tarball to the specified path.

  ## Options

    * `:verbose` - Log download progress (default: false)

  ## Returns

    * `{:ok, target_path}` on success
    * `{:error, reason}` on failure
  """
  @spec download(Req.Request.t(), String.t(), String.t(), Path.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def download(client, name, version, target_path, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    url = tarball_url(name, version)

    if verbose do
      require Logger
      Logger.info("Downloading #{name}-#{version} from #{url}")
    end

    # Ensure target directory exists
    target_path
    |> Path.dirname()
    |> File.mkdir_p!()

    case HttpClient.download(client, url, target_path) do
      {:ok, path} ->
        if verbose do
          require Logger
          Logger.info("Downloaded #{name}-#{version} to #{path}")
        end

        {:ok, path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a package tarball to a temporary directory.

  Creates a unique temporary directory and downloads the tarball there.

  ## Options

    * `:temp_dir` - Base temp directory (default: `System.tmp_dir!/0`)
    * `:verbose` - Log download progress (default: false)

  ## Returns

    * `{:ok, tarball_path, temp_dir}` on success
    * `{:error, reason}` on failure
  """
  @spec download_to_temp(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, Path.t(), Path.t()} | {:error, term()}
  def download_to_temp(client, name, version, opts \\ []) do
    base_temp = Keyword.get(opts, :temp_dir, System.tmp_dir!())

    # Create unique temp directory using package name and ref
    unique_id = :erlang.phash2(make_ref())
    temp_dir = Path.join(base_temp, "hex_#{name}_#{unique_id}")

    case File.mkdir_p(temp_dir) do
      :ok ->
        tarball_path = Path.join(temp_dir, tarball_filename(name, version))

        case download(client, name, version, tarball_path, opts) do
          {:ok, path} ->
            {:ok, path, temp_dir}

          {:error, reason} ->
            # Clean up temp directory on failure
            File.rm_rf(temp_dir)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:mkdir_failed, reason}}
    end
  end

  @doc """
  Returns the Hex repository base URL.
  """
  @spec repo_url() :: String.t()
  def repo_url, do: @repo_url

  @doc """
  Computes the SHA256 checksum of a file.

  Returns the hex-encoded lowercase checksum string.
  """
  @spec compute_checksum(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def compute_checksum(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        hash = :crypto.hash(:sha256, content)
        checksum = Base.encode16(hash, case: :lower)
        {:ok, checksum}

      {:error, reason} ->
        {:error, {:read_file, reason}}
    end
  end

  @doc """
  Verifies that a file matches an expected checksum.

  The expected checksum should be a hex-encoded SHA256 hash (case-insensitive).

  ## Returns

    * `:ok` if checksum matches
    * `{:error, :checksum_mismatch}` if checksum doesn't match
    * `{:error, reason}` for other failures
  """
  @spec verify_checksum(Path.t(), String.t()) :: :ok | {:error, term()}
  def verify_checksum(file_path, expected_checksum) do
    case compute_checksum(file_path) do
      {:ok, actual} ->
        expected_lower = String.downcase(expected_checksum)

        if actual == expected_lower do
          :ok
        else
          {:error, :checksum_mismatch}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Downloads a package tarball and optionally verifies its checksum.

  ## Options

    * `:verbose` - Log download progress (default: false)
    * `:checksum` - Expected SHA256 checksum to verify (optional)

  ## Returns

    * `{:ok, target_path}` on success
    * `{:error, :checksum_mismatch}` if checksum verification fails
    * `{:error, reason}` on other failures
  """
  @spec download_verified(Req.Request.t(), String.t(), String.t(), Path.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def download_verified(client, name, version, target_path, opts \\ []) do
    checksum = Keyword.get(opts, :checksum)
    download_opts = Keyword.drop(opts, [:checksum])

    case download(client, name, version, target_path, download_opts) do
      {:ok, path} ->
        if checksum do
          case verify_checksum(path, checksum) do
            :ok ->
              {:ok, path}

            {:error, :checksum_mismatch} = error ->
              # Clean up the corrupted file
              File.rm(path)
              error

            {:error, _} = error ->
              error
          end
        else
          {:ok, path}
        end

      {:error, _} = error ->
        error
    end
  end
end
