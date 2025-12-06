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

  # ===========================================================================
  # AST Body Normalization
  # ===========================================================================

  @doc """
  Normalizes an AST body to a list of statements.

  Handles the three common forms of module/function bodies:
  - `{:__block__, _, statements}` - Multiple statements
  - `nil` - Empty body
  - `single` - Single statement

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.normalize_body({:__block__, [], [:a, :b]})
      [:a, :b]

      iex> ElixirOntologies.Extractors.Helpers.normalize_body(nil)
      []

      iex> ElixirOntologies.Extractors.Helpers.normalize_body(:single)
      [:single]
  """
  @spec normalize_body(Macro.t()) :: [Macro.t()]
  def normalize_body({:__block__, _, statements}), do: statements
  def normalize_body(nil), do: []
  def normalize_body(single), do: [single]

  @doc """
  Extracts the body from a keyword list with `:do` key and normalizes it.

  This is commonly used for extracting bodies from `defmodule`, `def`, etc.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.extract_do_body([do: {:__block__, [], [:a, :b]}])
      [:a, :b]

      iex> ElixirOntologies.Extractors.Helpers.extract_do_body([do: :single])
      [:single]

      iex> ElixirOntologies.Extractors.Helpers.extract_do_body([do: nil])
      []

      iex> ElixirOntologies.Extractors.Helpers.extract_do_body([])
      []
  """
  @spec extract_do_body(keyword()) :: [Macro.t()]
  def extract_do_body(opts) when is_list(opts) do
    opts |> Keyword.get(:do) |> normalize_body()
  end

  def extract_do_body(_), do: []

  # ===========================================================================
  # Moduledoc Extraction
  # ===========================================================================

  @doc """
  Extracts @moduledoc value from a list of statements.

  Returns the documentation string if present, `false` if moduledoc is
  explicitly disabled, or `nil` if not present.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> statements = [{:@, [], [{:moduledoc, [], ["My documentation"]}]}]
      iex> Helpers.extract_moduledoc(statements)
      "My documentation"

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> statements = [{:@, [], [{:moduledoc, [], [false]}]}]
      iex> Helpers.extract_moduledoc(statements)
      false

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_moduledoc([])
      nil
  """
  @spec extract_moduledoc([Macro.t()]) :: String.t() | false | nil
  def extract_moduledoc(statements) when is_list(statements) do
    Enum.reduce_while(statements, nil, fn
      {:@, _meta, [{:moduledoc, _doc_meta, [doc]}]}, _acc when is_binary(doc) ->
        {:halt, doc}

      {:@, _meta, [{:moduledoc, _doc_meta, [false]}]}, _acc ->
        {:halt, false}

      _, acc ->
        {:cont, acc}
    end)
  end

  # ===========================================================================
  # Module AST Conversion
  # ===========================================================================

  @doc """
  Converts a module AST node to a module atom.

  Handles both `{:__aliases__, _, parts}` and bare atom forms.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.module_ast_to_atom({:__aliases__, [], [:Foo, :Bar]})
      Foo.Bar

      iex> ElixirOntologies.Extractors.Helpers.module_ast_to_atom(MyModule)
      MyModule

      iex> ElixirOntologies.Extractors.Helpers.module_ast_to_atom("not_a_module")
      nil
  """
  @spec module_ast_to_atom(Macro.t()) :: module() | nil
  def module_ast_to_atom({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  def module_ast_to_atom(atom) when is_atom(atom), do: atom
  def module_ast_to_atom(_), do: nil
end
