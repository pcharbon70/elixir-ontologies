defmodule ElixirOntologies.Hex.PackageHandler do
  @moduledoc """
  Package lifecycle management for Hex.pm packages.

  Orchestrates the complete flow of downloading, extracting, processing,
  and cleaning up Hex packages. Provides a context struct to track state
  and a callback pattern for safe resource management.

  ## Usage

      client = ElixirOntologies.Hex.HttpClient.new()

      # Manual lifecycle management
      {:ok, context} = PackageHandler.prepare(client, "phoenix", "1.7.10")
      # ... do something with context.extract_dir ...
      :ok = PackageHandler.cleanup(context)

      # Automatic cleanup with callback
      PackageHandler.with_package(client, "phoenix", "1.7.10", fn context ->
        # Process the package
        {:ok, analyze(context.extract_dir)}
      end)
  """

  alias ElixirOntologies.Hex.Downloader
  alias ElixirOntologies.Hex.Extractor

  defmodule Context do
    @moduledoc """
    Tracks the state of package processing.
    """

    @type status :: :pending | :downloaded | :extracted | :cleaned | :failed

    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            tarball_path: Path.t() | nil,
            extract_dir: Path.t() | nil,
            temp_dir: Path.t() | nil,
            status: status(),
            error: term() | nil
          }

    defstruct [
      :name,
      :version,
      :tarball_path,
      :extract_dir,
      :temp_dir,
      status: :pending,
      error: nil
    ]

    @doc """
    Creates a new context for a package.
    """
    @spec new(String.t(), String.t()) :: t()
    def new(name, version) do
      %__MODULE__{
        name: name,
        version: version,
        status: :pending
      }
    end
  end

  @doc """
  Prepares a package by downloading and extracting it.

  ## Options

    * `:temp_dir` - Base temp directory (default: `System.tmp_dir!/0`)
    * `:verbose` - Log progress (default: false)

  ## Returns

    * `{:ok, %Context{}}` on success with extract_dir populated
    * `{:error, reason, %Context{}}` on failure with partial context
  """
  @spec prepare(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, Context.t()} | {:error, term(), Context.t()}
  def prepare(client, name, version, opts \\ []) do
    context = Context.new(name, version)

    with {:ok, context} <- do_download(client, context, opts),
         {:ok, context} <- do_extract(context, opts) do
      {:ok, context}
    else
      {:error, reason, context} ->
        {:error, reason, %{context | status: :failed, error: reason}}
    end
  end

  defp do_download(client, context, opts) do
    case Downloader.download_to_temp(client, context.name, context.version, opts) do
      {:ok, tarball_path, temp_dir} ->
        {:ok,
         %{
           context
           | tarball_path: tarball_path,
             temp_dir: temp_dir,
             status: :downloaded
         }}

      {:error, reason} ->
        {:error, reason, context}
    end
  end

  defp do_extract(context, _opts) do
    extract_dir = Path.join(context.temp_dir, "source")

    case Extractor.extract(context.tarball_path, extract_dir) do
      {:ok, path} ->
        {:ok, %{context | extract_dir: path, status: :extracted}}

      {:error, reason} ->
        {:error, reason, context}
    end
  end

  @doc """
  Cleans up all temporary files and directories for a context.

  ## Returns

    * `{:ok, %Context{}}` with status updated to :cleaned
  """
  @spec cleanup(Context.t()) :: {:ok, Context.t()}
  def cleanup(%Context{} = context) do
    # Clean up tarball
    if context.tarball_path do
      Extractor.cleanup_tarball(context.tarball_path)
    end

    # Clean up the entire temp directory (includes extract_dir)
    if context.temp_dir do
      Extractor.cleanup(context.temp_dir)
    end

    {:ok, %{context | status: :cleaned}}
  end

  @doc """
  Executes a callback with a prepared package, ensuring cleanup.

  Downloads and extracts the package, calls the callback with the context,
  and always cleans up afterwards (even if the callback raises).

  ## Options

    * `:temp_dir` - Base temp directory (default: `System.tmp_dir!/0`)
    * `:verbose` - Log progress (default: false)

  ## Returns

    * The callback's return value on success
    * `{:error, reason}` if prepare fails

  ## Examples

      PackageHandler.with_package(client, "phoenix", "1.7.10", fn context ->
        analyze_package(context.extract_dir)
      end)
  """
  @spec with_package(Req.Request.t(), String.t(), String.t(), keyword(), (Context.t() -> term())) ::
          term() | {:error, term()}
  def with_package(client, name, version, opts \\ [], callback) when is_function(callback, 1) do
    case prepare(client, name, version, opts) do
      {:ok, context} ->
        try do
          callback.(context)
        after
          cleanup(context)
        end

      {:error, reason, context} ->
        # Clean up any partial state
        cleanup(context)
        {:error, reason}
    end
  end

  @doc """
  Checks if a prepared package is an Elixir project (has mix.exs).
  """
  @spec elixir_project?(Context.t()) :: boolean()
  def elixir_project?(%Context{extract_dir: nil}), do: false

  def elixir_project?(%Context{extract_dir: dir}) do
    Extractor.has_mix_exs?(dir)
  end
end
