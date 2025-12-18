defmodule ElixirOntologies.Analyzer.FileReader do
  @moduledoc """
  File reader for Elixir source files.

  This module provides utilities for reading Elixir source files with proper
  encoding handling and metadata tracking. It is the foundation for all AST
  parsing operations.

  ## Features

  - UTF-8 encoding with BOM detection and stripping
  - File metadata tracking (path, size, modification time)
  - Consistent error handling with ok/error tuples
  - Bang variants for raising on errors

  ## Usage

      alias ElixirOntologies.Analyzer.FileReader

      # Read a file
      {:ok, result} = FileReader.read("/path/to/file.ex")
      result.source  # => "defmodule MyModule do..."
      result.path    # => "/path/to/file.ex"
      result.size    # => 1234
      result.mtime   # => ~N[2025-01-15 10:30:00]

      # Read with bang (raises on error)
      result = FileReader.read!("/path/to/file.ex")

      # Check file properties
      FileReader.exists?("/path/to/file.ex")      # => true
      FileReader.elixir_file?("/path/to/file.ex") # => true

  ## Error Handling

  Errors are returned as `{:error, reason}` tuples:

  | Error | Reason |
  |-------|--------|
  | File not found | `:enoent` |
  | Permission denied | `:eacces` |
  | Not a regular file | `:not_regular_file` |
  | Encoding error | `{:encoding_error, details}` |
  """

  # Valid Elixir file extensions
  @elixir_extensions [".ex", ".exs"]

  # ============================================================================
  # Result Struct
  # ============================================================================

  defmodule Result do
    @moduledoc """
    Result struct containing file contents and metadata.

    ## Fields

    - `path` - Absolute path to the file
    - `source` - File contents as UTF-8 string (BOM stripped if present)
    - `size` - Original file size in bytes
    - `mtime` - Last modification time as NaiveDateTime
    """

    @enforce_keys [:path, :source, :size, :mtime]
    defstruct [:path, :source, :size, :mtime]

    @type t :: %__MODULE__{
            path: String.t(),
            source: String.t(),
            size: non_neg_integer(),
            mtime: NaiveDateTime.t()
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Reads a file and returns its contents with metadata.

  The file is read as UTF-8. If a UTF-8 BOM is present at the start of the
  file, it is automatically stripped from the source.

  ## Parameters

  - `path` - Path to the file (relative or absolute)

  ## Returns

  - `{:ok, %Result{}}` - File contents and metadata
  - `{:error, reason}` - Error reason (atom or tuple)

  ## Examples

      iex> {:ok, result} = FileReader.read("lib/elixir_ontologies.ex")
      iex> is_binary(result.source)
      true
      iex> result.size > 0
      true

      iex> FileReader.read("/nonexistent/file.ex")
      {:error, :enoent}

  """
  @spec read(Path.t()) :: {:ok, Result.t()} | {:error, atom() | tuple()}
  def read(path) do
    abs_path = Path.expand(path)

    with {:ok, stat} <- file_stat(abs_path),
         :ok <- validate_regular_file(stat),
         {:ok, content} <- read_file(abs_path) do
      source = strip_bom(content)
      mtime = stat_to_naive_datetime(stat.mtime)

      {:ok,
       %Result{
         path: abs_path,
         source: source,
         size: stat.size,
         mtime: mtime
       }}
    end
  end

  @doc """
  Reads a file and returns its contents with metadata, raising on error.

  Same as `read/1` but raises `File.Error` on failure.

  ## Parameters

  - `path` - Path to the file (relative or absolute)

  ## Returns

  - `%Result{}` - File contents and metadata

  ## Raises

  - `File.Error` - If the file cannot be read

  ## Examples

      result = FileReader.read!("lib/elixir_ontologies.ex")
      result.source  # => "defmodule ElixirOntologies do..."

  """
  @spec read!(Path.t()) :: Result.t()
  def read!(path) do
    case read(path) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise File.Error,
          reason: reason,
          action: "read file",
          path: Path.expand(path)
    end
  end

  @doc """
  Checks if a file exists.

  ## Parameters

  - `path` - Path to check

  ## Returns

  - `true` if file exists, `false` otherwise

  ## Examples

      iex> FileReader.exists?("lib/elixir_ontologies.ex")
      true

      iex> FileReader.exists?("/nonexistent/file.ex")
      false

  """
  @spec exists?(Path.t()) :: boolean()
  def exists?(path) do
    File.exists?(path)
  end

  @doc """
  Checks if a path has an Elixir file extension (.ex or .exs).

  ## Parameters

  - `path` - Path to check

  ## Returns

  - `true` if path ends with .ex or .exs, `false` otherwise

  ## Examples

      iex> FileReader.elixir_file?("lib/my_module.ex")
      true

      iex> FileReader.elixir_file?("test/my_test.exs")
      true

      iex> FileReader.elixir_file?("README.md")
      false

  """
  @spec elixir_file?(Path.t()) :: boolean()
  def elixir_file?(path) do
    ext = Path.extname(path)
    ext in @elixir_extensions
  end

  @doc """
  Checks if content starts with a UTF-8 BOM.

  ## Parameters

  - `content` - Binary content to check

  ## Returns

  - `true` if content starts with UTF-8 BOM, `false` otherwise

  ## Examples

      iex> FileReader.has_bom?(<<0xEF, 0xBB, 0xBF, "hello">>)
      true

      iex> FileReader.has_bom?("hello")
      false

  """
  @spec has_bom?(binary()) :: boolean()
  def has_bom?(<<0xEF, 0xBB, 0xBF, _rest::binary>>), do: true
  def has_bom?(_), do: false

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp file_stat(path) do
    case File.stat(path) do
      {:ok, stat} -> {:ok, stat}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_regular_file(%File.Stat{type: :regular}), do: :ok
  defp validate_regular_file(_stat), do: {:error, :not_regular_file}

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        validate_encoding(content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_encoding(content) do
    if String.valid?(content) do
      {:ok, content}
    else
      {:error, {:encoding_error, "file contains invalid UTF-8 sequences"}}
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(content), do: content

  defp stat_to_naive_datetime({{year, month, day}, {hour, minute, second}}) do
    NaiveDateTime.new!(year, month, day, hour, minute, second)
  end
end
