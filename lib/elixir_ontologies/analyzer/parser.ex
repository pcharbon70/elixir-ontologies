defmodule ElixirOntologies.Analyzer.Parser do
  @moduledoc """
  AST parser for Elixir source code.

  This module wraps `Code.string_to_quoted/2` with enhanced source location
  tracking and structured error handling. It integrates with the FileReader
  module for file-based parsing operations.

  ## Features

  - Source location tracking with line and column information
  - Token metadata preservation for advanced analysis
  - Structured error results with location details
  - Integration with FileReader for file parsing
  - Both ok/error and bang variants

  ## Usage

      alias ElixirOntologies.Analyzer.Parser

      # Parse source string
      {:ok, ast} = Parser.parse("defmodule Foo do end")

      # Parse with custom options
      {:ok, ast} = Parser.parse("1 + 2", emit_warnings: false)

      # Parse a file
      {:ok, result} = Parser.parse_file("/path/to/file.ex")
      result.ast     # => {:defmodule, [...], [...]}
      result.source  # => "defmodule Foo do..."

      # Bang variants (raise on error)
      ast = Parser.parse!("defmodule Foo do end")
      result = Parser.parse_file!("/path/to/file.ex")

  ## Parser Options

  Default options enable maximum source location information:

  | Option | Default | Description |
  |--------|---------|-------------|
  | `columns` | `true` | Include column information |
  | `token_metadata` | `true` | Include token metadata |
  | `emit_warnings` | `false` | Suppress compiler warnings |

  Additional options are passed through to `Code.string_to_quoted/2`.

  ## Error Handling

  Parse errors are returned as `{:error, %Parser.Error{}}` with:

  - `message` - Description of the error
  - `line` - Line number where error occurred (if available)
  - `column` - Column number where error occurred (if available)
  - `snippet` - Source snippet around the error location
  """

  alias ElixirOntologies.Analyzer.FileReader

  # Default parser options for maximum location information
  @default_opts [
    columns: true,
    token_metadata: true,
    emit_warnings: false
  ]

  # ============================================================================
  # Error Struct
  # ============================================================================

  defmodule Error do
    @moduledoc """
    Structured parse error with location information.

    ## Fields

    - `message` - Description of the parse error
    - `line` - Line number where the error occurred (nil if unknown)
    - `column` - Column number where the error occurred (nil if unknown)
    - `snippet` - Source code snippet around the error location (nil if unavailable)
    """

    @enforce_keys [:message]
    defstruct [:message, :line, :column, :snippet]

    @type t :: %__MODULE__{
            message: String.t(),
            line: pos_integer() | nil,
            column: pos_integer() | nil,
            snippet: String.t() | nil
          }
  end

  # ============================================================================
  # Result Struct
  # ============================================================================

  defmodule Result do
    @moduledoc """
    Result struct containing parsed AST and file metadata.

    ## Fields

    - `path` - Absolute path to the parsed file
    - `source` - Original source code
    - `ast` - Parsed AST
    - `file_metadata` - Map containing file size and modification time
    """

    @enforce_keys [:path, :source, :ast, :file_metadata]
    defstruct [:path, :source, :ast, :file_metadata]

    @type t :: %__MODULE__{
            path: String.t(),
            source: String.t(),
            ast: Macro.t(),
            file_metadata: %{
              size: non_neg_integer(),
              mtime: NaiveDateTime.t()
            }
          }
  end

  # ============================================================================
  # Public API - String Parsing
  # ============================================================================

  @doc """
  Parses an Elixir source string into an AST.

  Uses default options that enable column tracking and token metadata
  for maximum source location information.

  ## Parameters

  - `source` - Elixir source code string

  ## Returns

  - `{:ok, ast}` - Parsed AST
  - `{:error, %Error{}}` - Parse error with location details

  ## Examples

      iex> {:ok, ast} = Parser.parse("1 + 2")
      iex> is_tuple(ast)
      true

      iex> {:error, error} = Parser.parse("def foo(")
      iex> %Parser.Error{} = error
      iex> error.line
      1

  """
  @spec parse(String.t()) :: {:ok, Macro.t()} | {:error, Error.t()}
  def parse(source) when is_binary(source) do
    parse(source, [])
  end

  @doc """
  Parses an Elixir source string into an AST with custom options.

  Custom options are merged with defaults. Options are passed through
  to `Code.string_to_quoted/2`.

  ## Parameters

  - `source` - Elixir source code string
  - `opts` - Keyword list of options (merged with defaults)

  ## Options

  - `:columns` - Include column information (default: `true`)
  - `:token_metadata` - Include token metadata (default: `true`)
  - `:emit_warnings` - Emit compiler warnings (default: `false`)
  - `:file` - File name for error messages
  - Any other options accepted by `Code.string_to_quoted/2`

  ## Returns

  - `{:ok, ast}` - Parsed AST
  - `{:error, %Error{}}` - Parse error with location details

  ## Examples

      iex> {:ok, ast} = Parser.parse(":foo", file: "test.ex")
      iex> is_atom(ast)
      true

      iex> {:ok, ast} = Parser.parse("1 + 2", columns: false)
      iex> is_tuple(ast)
      true

  """
  @spec parse(String.t(), keyword()) :: {:ok, Macro.t()} | {:error, Error.t()}
  def parse(source, opts) when is_binary(source) and is_list(opts) do
    merged_opts = Keyword.merge(@default_opts, opts)

    case Code.string_to_quoted(source, merged_opts) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {location, message, token}} ->
        {:error, build_error(source, location, message, token)}
    end
  end

  @doc """
  Parses an Elixir source string into an AST, raising on error.

  ## Parameters

  - `source` - Elixir source code string

  ## Returns

  - `ast` - Parsed AST

  ## Raises

  - `SyntaxError` - If the source cannot be parsed

  ## Examples

      ast = Parser.parse!("1 + 2")

  """
  @spec parse!(String.t()) :: Macro.t()
  def parse!(source) when is_binary(source) do
    parse!(source, [])
  end

  @doc """
  Parses an Elixir source string into an AST with custom options, raising on error.

  ## Parameters

  - `source` - Elixir source code string
  - `opts` - Keyword list of options

  ## Returns

  - `ast` - Parsed AST

  ## Raises

  - `SyntaxError` - If the source cannot be parsed

  ## Examples

      ast = Parser.parse!("foo", file: "test.ex")

  """
  @spec parse!(String.t(), keyword()) :: Macro.t()
  def parse!(source, opts) when is_binary(source) and is_list(opts) do
    case parse(source, opts) do
      {:ok, ast} ->
        ast

      {:error, %Error{message: message, line: line, column: column}} ->
        file = Keyword.get(opts, :file, "nofile")

        raise SyntaxError,
          description: message,
          file: file,
          line: line || 1,
          column: column
    end
  end

  # ============================================================================
  # Public API - File Parsing
  # ============================================================================

  @doc """
  Reads and parses an Elixir file into an AST.

  Combines `FileReader.read/1` with `parse/1` for convenient file-based
  parsing. Returns a result struct containing the AST, source code,
  and file metadata.

  ## Parameters

  - `path` - Path to the Elixir file

  ## Returns

  - `{:ok, %Result{}}` - Parsed result with AST and metadata
  - `{:error, {:file_error, reason}}` - File read error
  - `{:error, %Error{}}` - Parse error

  ## Examples

      iex> {:ok, result} = Parser.parse_file("lib/elixir_ontologies.ex")
      iex> %Parser.Result{} = result
      iex> is_tuple(result.ast)
      true
      iex> is_binary(result.source)
      true

      iex> {:error, {:file_error, :enoent}} = Parser.parse_file("/nonexistent.ex")

  """
  @spec parse_file(Path.t()) :: {:ok, Result.t()} | {:error, {:file_error, atom()} | Error.t()}
  def parse_file(path) do
    with {:ok, file_result} <- read_file(path),
         {:ok, ast} <- parse(file_result.source, file: file_result.path) do
      {:ok,
       %Result{
         path: file_result.path,
         source: file_result.source,
         ast: ast,
         file_metadata: %{
           size: file_result.size,
           mtime: file_result.mtime
         }
       }}
    end
  end

  @doc """
  Reads and parses an Elixir file into an AST, raising on error.

  ## Parameters

  - `path` - Path to the Elixir file

  ## Returns

  - `%Result{}` - Parsed result with AST and metadata

  ## Raises

  - `File.Error` - If the file cannot be read
  - `SyntaxError` - If the source cannot be parsed

  ## Examples

      result = Parser.parse_file!("lib/elixir_ontologies.ex")
      result.ast  # => {:defmodule, [...], [...]}

  """
  @spec parse_file!(Path.t()) :: Result.t()
  def parse_file!(path) do
    case parse_file(path) do
      {:ok, result} ->
        result

      {:error, {:file_error, reason}} ->
        raise File.Error,
          reason: reason,
          action: "read file",
          path: Path.expand(path)

      {:error, %Error{} = error} ->
        raise SyntaxError,
          description: error.message,
          file: Path.expand(path),
          line: error.line || 1,
          column: error.column
    end
  end

  # ============================================================================
  # Public API - Utilities
  # ============================================================================

  @doc """
  Returns the default parser options.

  ## Examples

      iex> opts = Parser.default_options()
      iex> opts[:columns]
      true
      iex> opts[:token_metadata]
      true

  """
  @spec default_options() :: keyword()
  def default_options, do: @default_opts

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp read_file(path) do
    case FileReader.read(path) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp build_error(source, location, message, token) do
    {line, column} = extract_location(location)
    snippet = extract_snippet(source, line)

    %Error{
      message: format_message(message, token),
      line: line,
      column: column,
      snippet: snippet
    }
  end

  defp extract_location(location) when is_list(location) do
    line = Keyword.get(location, :line)
    column = Keyword.get(location, :column)
    {line, column}
  end

  defp extract_location(line) when is_integer(line) do
    {line, nil}
  end

  defp extract_location(_), do: {nil, nil}

  defp format_message(message, token) when is_binary(message) and is_binary(token) do
    "#{message}#{token}"
  end

  defp format_message(message, _token) when is_binary(message) do
    message
  end

  defp format_message(message, token) do
    "#{inspect(message)}#{inspect(token)}"
  end

  defp extract_snippet(_source, nil), do: nil

  defp extract_snippet(source, line) when is_integer(line) and line > 0 do
    lines = String.split(source, "\n")

    if line <= length(lines) do
      Enum.at(lines, line - 1)
    else
      nil
    end
  end

  defp extract_snippet(_source, _line), do: nil
end
