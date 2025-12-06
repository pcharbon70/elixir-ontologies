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

  # ===========================================================================
  # Conditional Location Extraction
  # ===========================================================================

  @doc """
  Extracts location from an AST node if the `:include_location` option is true.

  This helper reduces boilerplate in extractor functions that conditionally
  include location information based on options.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> node = {:def, [line: 1, column: 1], []}
      iex> Helpers.extract_location_if(node, include_location: true)
      %ElixirOntologies.Analyzer.Location.SourceLocation{start_line: 1, start_column: 1}

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> node = {:def, [line: 1], []}
      iex> Helpers.extract_location_if(node, include_location: false)
      nil

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> node = {:def, [line: 1, column: 1], []}
      iex> Helpers.extract_location_if(node, [])
      %ElixirOntologies.Analyzer.Location.SourceLocation{start_line: 1, start_column: 1}
  """
  @spec extract_location_if(Macro.t(), keyword()) :: Location.SourceLocation.t() | nil
  def extract_location_if(node, opts) do
    if Keyword.get(opts, :include_location, true) do
      extract_location(node)
    else
      nil
    end
  end

  # ===========================================================================
  # Function Signature Extraction
  # ===========================================================================

  @doc """
  Computes the arity from a function's argument list AST.

  Returns 0 for nil or non-list arguments.

  ## Examples

      iex> ElixirOntologies.Extractors.Helpers.compute_arity([{:x, [], nil}, {:y, [], nil}])
      2

      iex> ElixirOntologies.Extractors.Helpers.compute_arity(nil)
      0

      iex> ElixirOntologies.Extractors.Helpers.compute_arity([])
      0
  """
  @spec compute_arity(Macro.t()) :: non_neg_integer()
  def compute_arity(nil), do: 0
  def compute_arity(args) when is_list(args), do: length(args)
  def compute_arity(_), do: 0

  @doc """
  Extracts parameter names from a function's argument list AST.

  Returns a list of atoms representing parameter names. Unknown patterns
  are represented as `:_`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_parameter_names([{:x, [], nil}, {:y, [], nil}])
      [:x, :y]

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_parameter_names(nil)
      []

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_parameter_names([{:x, [], nil}, {:y, [], [{:z, [], nil}]}])
      [:x, :y]
  """
  @spec extract_parameter_names(Macro.t()) :: [atom()]
  def extract_parameter_names(nil), do: []

  def extract_parameter_names(args) when is_list(args) do
    Enum.map(args, fn
      {name, _meta, context} when is_atom(name) and is_atom(context) -> name
      {name, _meta, _args} when is_atom(name) -> name
      _ -> :_
    end)
  end

  @doc """
  Extracts function signature (name and arity) from a def/defp AST node.

  Handles both regular function heads and those with guard clauses.
  Returns `nil` for non-function AST nodes.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> code = "def foo(x, y), do: x + y"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> Helpers.extract_function_signature(ast)
      {:foo, 2}

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> code = "def foo(x) when is_integer(x), do: x"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> Helpers.extract_function_signature(ast)
      {:foo, 1}

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.extract_function_signature(:not_a_def)
      nil
  """
  @spec extract_function_signature(Macro.t()) :: {atom(), non_neg_integer()} | nil
  # Handle function with when clause first (to avoid matching :when as function name)
  def extract_function_signature({def_type, _meta, [{:when, _, [{name, _fn_meta, args} | _]} | _]})
      when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    {name, compute_arity(args)}
  end

  # Regular function without guard (exclude :when)
  def extract_function_signature({def_type, _meta, [{name, _fn_meta, args} | _]})
      when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) and name != :when do
    {name, compute_arity(args)}
  end

  def extract_function_signature(_), do: nil

  # ===========================================================================
  # @derive Extraction
  # ===========================================================================

  defmodule DeriveInfo do
    @moduledoc """
    Represents a `@derive` directive.

    This is a shared struct used by both Protocol and Struct extractors
    since @derive is a general Elixir feature.
    """

    @typedoc """
    Information about a @derive directive.

    - `:protocols` - List of derived protocols (with options)
    - `:location` - Source location
    """
    @type t :: %__MODULE__{
            protocols: [derive_protocol()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @typedoc """
    A protocol in a @derive directive.
    """
    @type derive_protocol :: %{
            protocol: [atom()] | atom(),
            options: keyword() | nil
          }

    defstruct [
      protocols: [],
      location: nil
    ]
  end

  @doc """
  Checks if an AST node is a @derive attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> code = "@derive [Inspect]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> Helpers.derive_attribute?(ast)
      true

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> Helpers.derive_attribute?({:@, [], [{:doc, [], ["test"]}]})
      false
  """
  @spec derive_attribute?(Macro.t()) :: boolean()
  def derive_attribute?({:@, _meta, [{:derive, _attr_meta, _args}]}), do: true
  def derive_attribute?(_), do: false

  @doc """
  Extracts all @derive directives from a module body.

  Returns a list of `DeriveInfo` structs containing the derived protocols
  and their options.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Helpers
      iex> code = "defmodule M do @derive [Inspect, Enumerable]; defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> derives = Helpers.extract_derives(body)
      iex> length(derives)
      1
      iex> hd(derives).protocols |> Enum.map(& &1.protocol)
      [[:Inspect], [:Enumerable]]
  """
  @spec extract_derives(Macro.t()) :: [DeriveInfo.t()]
  def extract_derives(body) do
    body
    |> normalize_body()
    |> Enum.filter(&derive_attribute?/1)
    |> Enum.map(&extract_single_derive/1)
  end

  defp extract_single_derive({:@, meta, [{:derive, _attr_meta, [protocols]}]}) do
    location = extract_location({:@, meta, []})
    protocol_list = normalize_derive_protocols(protocols)

    %DeriveInfo{
      protocols: protocol_list,
      location: location
    }
  end

  defp normalize_derive_protocols(protocols) when is_list(protocols) do
    Enum.map(protocols, &normalize_derive_protocol/1)
  end

  defp normalize_derive_protocols(single) do
    [normalize_derive_protocol(single)]
  end

  defp normalize_derive_protocol({:__aliases__, _, parts}) do
    %{protocol: parts, options: nil}
  end

  defp normalize_derive_protocol({{:__aliases__, _, parts}, opts}) when is_list(opts) do
    %{protocol: parts, options: opts}
  end

  defp normalize_derive_protocol(atom) when is_atom(atom) do
    %{protocol: atom, options: nil}
  end

  defp normalize_derive_protocol({atom, opts}) when is_atom(atom) and is_list(opts) do
    %{protocol: atom, options: opts}
  end
end
