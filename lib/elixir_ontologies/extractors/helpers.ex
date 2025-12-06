defmodule ElixirOntologies.Extractors.Helpers do
  @moduledoc """
  Shared utility functions for extractor modules.

  This module provides common functionality used across all AST extractors,
  including location extraction, guard combination, and error message formatting.

  ## Usage

      alias ElixirOntologies.Extractors.Helpers

      # Extract location from AST node
      location = Helpers.extract_location({:if, [line: 1], [condition, opts]})

      # Combine guards
      guard = Helpers.combine_guards([{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}])
      # => {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}

      # Format error message with limited output
      msg = Helpers.format_error("Not a pattern", node)
  """

  alias ElixirOntologies.Analyzer.Location

  # ===========================================================================
  # Constants
  # ===========================================================================

  @default_inspect_limit 20
  @default_printable_limit 100
  @max_recursion_depth 100

  # Special forms that are NOT variable references or local calls
  @special_forms [
    # Elixir special forms
    :__block__,
    :__aliases__,
    :__MODULE__,
    :__DIR__,
    :__ENV__,
    :__CALLER__,
    :__STACKTRACE__,
    :fn,
    :do,
    :else,
    :catch,
    :rescue,
    :after,
    # Definition forms
    :def,
    :defp,
    :defmacro,
    :defmacrop,
    :defmodule,
    :defprotocol,
    :defimpl,
    :defstruct,
    :defdelegate,
    :defguard,
    :defguardp,
    :defexception,
    :defoverridable,
    # Import/require/use
    :import,
    :require,
    :use,
    :alias,
    # Control flow
    :if,
    :unless,
    :case,
    :cond,
    :with,
    :for,
    :try,
    :receive,
    :raise,
    :throw,
    :quote,
    :unquote,
    :unquote_splicing,
    # Other
    :super,
    :&,
    :^,
    :=,
    :|>,
    :.,
    :|,
    :"::",
    :<<>>,
    :{},
    :%{},
    :%
  ]

  # ===========================================================================
  # Special Forms
  # ===========================================================================

  @doc """
  Returns the list of special forms that are NOT variable references or local calls.

  This includes Elixir special forms, definition macros, control flow constructs,
  and syntactic operators that have special AST representation.

  ## Examples

      iex> :def in ElixirOntologies.Extractors.Helpers.special_forms()
      true

      iex> :my_function in ElixirOntologies.Extractors.Helpers.special_forms()
      false
  """
  @spec special_forms() :: [atom()]
  def special_forms, do: @special_forms

  @doc """
  Checks if an atom is a special form.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.special_form?(:def)
      true

      iex> ElixirOntologies.Extractors.Helpers.special_form?(:my_function)
      false
  """
  @spec special_form?(atom()) :: boolean()
  def special_form?(name) when is_atom(name), do: name in @special_forms

  # ===========================================================================
  # Location Extraction
  # ===========================================================================

  @doc """
  Extracts source location from an AST node.

  Returns a `Location.SourceLocation` struct if location metadata is available,
  otherwise returns `nil`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> alias ElixirOntologies.Analyzer.Location.SourceLocation
      iex> %SourceLocation{start_line: 1, start_column: 1} = Helpers.extract_location({:x, [line: 1, column: 1], nil})
      %SourceLocation{start_line: 1, start_column: 1, end_line: nil, end_column: nil}

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_location(:atom)
      nil
  """
  @spec extract_location(Macro.t()) :: Location.SourceLocation.t() | nil
  def extract_location({_form, meta, _args} = node) when is_list(meta) do
    case Location.extract_range(node) do
      {:ok, location} -> location
      _ -> nil
    end
  end

  def extract_location(_), do: nil

  # ===========================================================================
  # Guard Helpers
  # ===========================================================================

  @doc """
  Combines multiple guard expressions into a single `and` expression.

  When pattern matching with guards like `x when is_integer(x) and x > 0`,
  the guards may be provided as a list. This function combines them into
  a single nested `and` expression.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.combine_guards([{:is_integer, [], [{:x, [], nil}]}])
      {:is_integer, [], [{:x, [], nil}]}

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.combine_guards([])
      nil

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> guards = [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]
      iex> Helpers.combine_guards(guards)
      {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
  """
  @spec combine_guards([Macro.t()]) :: Macro.t() | nil
  def combine_guards([single]), do: single
  def combine_guards([first | rest]), do: {:and, [], [first, combine_guards(rest)]}
  def combine_guards([]), do: nil

  # ===========================================================================
  # Error Formatting
  # ===========================================================================

  @doc """
  Formats an error message with limited inspect output.

  Large AST nodes are truncated to prevent huge error messages.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.format_error("Not a pattern", {:x, [], nil})
      "Not a pattern: {:x, [], nil}"
  """
  @spec format_error(String.t(), term()) :: String.t()
  def format_error(message, node) do
    inspected = inspect(node, limit: @default_inspect_limit, printable_limit: @default_printable_limit)
    "#{message}: #{inspected}"
  end

  # ===========================================================================
  # Recursion Safety
  # ===========================================================================

  @doc """
  Returns the maximum recursion depth for AST traversal.

  This limit prevents stack overflow when processing pathologically deep AST structures.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.max_recursion_depth()
      100
  """
  @spec max_recursion_depth() :: pos_integer()
  def max_recursion_depth, do: @max_recursion_depth

  @doc """
  Checks if the current depth exceeds the maximum recursion depth.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.depth_exceeded?(50)
      false

      iex> ElixirOntologies.Extractors.Helpers.depth_exceeded?(100)
      false

      iex> ElixirOntologies.Extractors.Helpers.depth_exceeded?(101)
      true
  """
  @spec depth_exceeded?(non_neg_integer()) :: boolean()
  def depth_exceeded?(depth), do: depth > @max_recursion_depth
end
