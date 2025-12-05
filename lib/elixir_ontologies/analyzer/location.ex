defmodule ElixirOntologies.Analyzer.Location do
  @moduledoc """
  Extracts source location information from Elixir AST metadata.

  This module provides utilities for extracting line and column information
  from AST nodes, supporting the `hasSourceLocation` RDF property and
  enabling precise source code navigation.

  ## AST Metadata Structure

  Elixir AST nodes store location in metadata (second element of 3-tuple).
  With `columns: true` and `token_metadata: true` parser options, metadata
  may include:

  | Key | Type | Description |
  |-----|------|-------------|
  | `line` | integer | Start line number |
  | `column` | integer | Start column number |
  | `end` | keyword | End position `[line: n, column: m]` |
  | `do` | keyword | Position of `do` keyword |
  | `closing` | keyword | Position of closing delimiter |
  | `end_of_expression` | keyword | Position after expression |

  ## Usage

      alias ElixirOntologies.Analyzer.Location

      # Extract start position
      {:ok, {line, column}} = Location.extract(ast_node)

      # Extract full range
      {:ok, location} = Location.extract_range(ast_node)
      location.start_line   # => 1
      location.end_line     # => 5

      # Calculate span between nodes
      {:ok, span} = Location.span(start_node, end_node)

  ## Handling Missing Metadata

  Not all AST nodes have location metadata. Functions return `:no_location`
  when metadata is absent or incomplete:

      Location.extract(:atom)  # => :no_location
      Location.extract({:ok, [], []})  # => :no_location (no line in meta)

  """

  # ============================================================================
  # SourceLocation Struct
  # ============================================================================

  defmodule SourceLocation do
    @moduledoc """
    Source location with start and end positions.

    ## Fields

    - `start_line` - Line number where the construct begins (1-indexed)
    - `start_column` - Column number where the construct begins (1-indexed)
    - `end_line` - Line number where the construct ends (nil if unknown)
    - `end_column` - Column number where the construct ends (nil if unknown)
    """

    @enforce_keys [:start_line, :start_column]
    defstruct [:start_line, :start_column, :end_line, :end_column]

    @type t :: %__MODULE__{
            start_line: pos_integer(),
            start_column: pos_integer(),
            end_line: pos_integer() | nil,
            end_column: pos_integer() | nil
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Extracts start line and column from an AST node's metadata.

  Returns the start position as a tuple `{line, column}` where both are
  1-indexed positive integers.

  ## Parameters

  - `node` - An Elixir AST node (3-tuple with metadata)

  ## Returns

  - `{:ok, {line, column}}` - Start position found
  - `:no_location` - No location metadata available

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("def foo, do: :ok", columns: true)
      iex> Location.extract(ast)
      {:ok, {1, 1}}

      iex> Location.extract(:atom)
      :no_location

      iex> Location.extract({:ok, [], []})
      :no_location

  """
  @spec extract(Macro.t()) :: {:ok, {pos_integer(), pos_integer()}} | :no_location
  def extract({_form, meta, _args}) when is_list(meta) do
    case {Keyword.get(meta, :line), Keyword.get(meta, :column)} do
      {line, column} when is_integer(line) and is_integer(column) and line > 0 and column > 0 ->
        {:ok, {line, column}}

      _ ->
        :no_location
    end
  end

  def extract(_), do: :no_location

  @doc """
  Extracts start line and column, raising on missing metadata.

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - `{line, column}` - Start position

  ## Raises

  - `ArgumentError` - If no location metadata is available

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("def foo, do: :ok", columns: true)
      iex> Location.extract!(ast)
      {1, 1}

  """
  @spec extract!(Macro.t()) :: {pos_integer(), pos_integer()}
  def extract!(node) do
    case extract(node) do
      {:ok, position} -> position
      :no_location -> raise ArgumentError, "AST node has no location metadata"
    end
  end

  @doc """
  Extracts a full source location range from an AST node.

  Attempts to determine both start and end positions. End position is
  extracted from:
  1. `end` metadata key (for block constructs like `defmodule`, `def`)
  2. `closing` metadata key (for function calls with parentheses)
  3. Falls back to nil if not determinable

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - `{:ok, %SourceLocation{}}` - Location range found
  - `:no_location` - No start location metadata available

  ## Examples

      iex> code = "defmodule Foo do\\n  :ok\\nend"
      iex> {:ok, ast} = Code.string_to_quoted(code, columns: true, token_metadata: true)
      iex> {:ok, loc} = Location.extract_range(ast)
      iex> loc.start_line
      1
      iex> loc.start_column
      1
      iex> loc.end_line
      3
      iex> loc.end_column
      1

      iex> Location.extract_range(:atom)
      :no_location

  """
  @spec extract_range(Macro.t()) :: {:ok, SourceLocation.t()} | :no_location
  def extract_range({_form, meta, _args} = node) when is_list(meta) do
    case extract(node) do
      {:ok, {start_line, start_column}} ->
        {end_line, end_column} = extract_end_position(meta)

        {:ok,
         %SourceLocation{
           start_line: start_line,
           start_column: start_column,
           end_line: end_line,
           end_column: end_column
         }}

      :no_location ->
        :no_location
    end
  end

  def extract_range(_), do: :no_location

  @doc """
  Extracts a full source location range, raising on missing metadata.

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - `%SourceLocation{}` - Location range

  ## Raises

  - `ArgumentError` - If no location metadata is available

  ## Examples

      iex> code = "def foo, do: :ok"
      iex> {:ok, ast} = Code.string_to_quoted(code, columns: true, token_metadata: true)
      iex> loc = Location.extract_range!(ast)
      iex> loc.start_line
      1

  """
  @spec extract_range!(Macro.t()) :: SourceLocation.t()
  def extract_range!(node) do
    case extract_range(node) do
      {:ok, location} -> location
      :no_location -> raise ArgumentError, "AST node has no location metadata"
    end
  end

  @doc """
  Calculates a span from a start node to an end node.

  Creates a `SourceLocation` using the start position of `start_node`
  and the end position (or start if end unavailable) of `end_node`.

  Useful for calculating the extent of a compound construct where
  the first and last child nodes are known.

  ## Parameters

  - `start_node` - AST node marking the beginning
  - `end_node` - AST node marking the end

  ## Returns

  - `{:ok, %SourceLocation{}}` - Span calculated
  - `:no_location` - Missing location metadata on start node

  ## Examples

      iex> {:ok, start_ast} = Code.string_to_quoted("def foo, do: nil", columns: true)
      iex> {:ok, end_ast} = Code.string_to_quoted("def bar, do: nil", columns: true)
      iex> {:ok, span} = Location.span(start_ast, end_ast)
      iex> span.start_line
      1
      iex> span.end_line
      1

      iex> Location.span(:atom, :atom)
      :no_location

  """
  @spec span(Macro.t(), Macro.t()) :: {:ok, SourceLocation.t()} | :no_location
  def span(start_node, end_node) do
    with {:ok, {start_line, start_column}} <- extract(start_node) do
      {end_line, end_column} = get_end_from_node(end_node)

      {:ok,
       %SourceLocation{
         start_line: start_line,
         start_column: start_column,
         end_line: end_line,
         end_column: end_column
       }}
    end
  end

  @doc """
  Calculates a span from a start node to an end node, raising on error.

  ## Parameters

  - `start_node` - AST node marking the beginning
  - `end_node` - AST node marking the end

  ## Returns

  - `%SourceLocation{}` - Span calculated

  ## Raises

  - `ArgumentError` - If start node has no location metadata

  ## Examples

      iex> {:ok, start_ast} = Code.string_to_quoted("foo()", columns: true)
      iex> {:ok, end_ast} = Code.string_to_quoted("bar()", columns: true)
      iex> span = Location.span!(start_ast, end_ast)
      iex> span.start_line
      1

  """
  @spec span!(Macro.t(), Macro.t()) :: SourceLocation.t()
  def span!(start_node, end_node) do
    case span(start_node, end_node) do
      {:ok, location} -> location
      :no_location -> raise ArgumentError, "Start node has no location metadata"
    end
  end

  @doc """
  Checks if an AST node has location metadata.

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - `true` if the node has both line and column metadata
  - `false` otherwise

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("foo()", columns: true)
      iex> Location.has_location?(ast)
      true

      iex> Location.has_location?(:bare_atom)
      false

      iex> Location.has_location?({:ok, [], []})
      false

  """
  @spec has_location?(Macro.t()) :: boolean()
  def has_location?(node) do
    case extract(node) do
      {:ok, _} -> true
      :no_location -> false
    end
  end

  @doc """
  Gets the start line from an AST node, or nil if not available.

  Convenience function for when only the line number is needed.

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - Line number (positive integer) or `nil`

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("foo()", columns: true)
      iex> Location.line(ast)
      1

      iex> Location.line(:bare_atom)
      nil

  """
  @spec line(Macro.t()) :: pos_integer() | nil
  def line({_form, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :line) do
      line when is_integer(line) and line > 0 -> line
      _ -> nil
    end
  end

  def line(_), do: nil

  @doc """
  Gets the start column from an AST node, or nil if not available.

  Convenience function for when only the column number is needed.

  ## Parameters

  - `node` - An Elixir AST node

  ## Returns

  - Column number (positive integer) or `nil`

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("foo()", columns: true)
      iex> Location.column(ast)
      1

      iex> Location.column(:bare_atom)
      nil

  """
  @spec column(Macro.t()) :: pos_integer() | nil
  def column({_form, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :column) do
      column when is_integer(column) and column > 0 -> column
      _ -> nil
    end
  end

  def column(_), do: nil

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Extract end position from metadata
  # Tries multiple metadata keys that might contain end position
  defp extract_end_position(meta) do
    cond do
      # Block end position (defmodule, def, etc.)
      end_meta = Keyword.get(meta, :end) ->
        {get_nested_line(end_meta), get_nested_column(end_meta)}

      # Closing delimiter (function calls with parens)
      closing_meta = Keyword.get(meta, :closing) ->
        {get_nested_line(closing_meta), get_nested_column(closing_meta)}

      # End of expression
      eoe_meta = Keyword.get(meta, :end_of_expression) ->
        {get_nested_line(eoe_meta), get_nested_column(eoe_meta)}

      true ->
        {nil, nil}
    end
  end

  # Get end position from an AST node (for span calculation)
  # Prefers explicit end position, falls back to start position
  defp get_end_from_node({_form, meta, _args}) when is_list(meta) do
    case extract_end_position(meta) do
      {nil, nil} ->
        # Fall back to start position of end node
        line = Keyword.get(meta, :line)
        column = Keyword.get(meta, :column)

        line = if is_integer(line) and line > 0, do: line, else: nil
        column = if is_integer(column) and column > 0, do: column, else: nil

        {line, column}

      end_pos ->
        end_pos
    end
  end

  defp get_end_from_node(_), do: {nil, nil}

  # Extract line from nested keyword list like [line: 5, column: 3]
  defp get_nested_line(keyword) when is_list(keyword) do
    case Keyword.get(keyword, :line) do
      line when is_integer(line) and line > 0 -> line
      _ -> nil
    end
  end

  defp get_nested_line(_), do: nil

  # Extract column from nested keyword list
  defp get_nested_column(keyword) when is_list(keyword) do
    case Keyword.get(keyword, :column) do
      column when is_integer(column) and column > 0 -> column
      _ -> nil
    end
  end

  defp get_nested_column(_), do: nil
end
