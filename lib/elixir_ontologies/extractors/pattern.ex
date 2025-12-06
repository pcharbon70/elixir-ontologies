defmodule ElixirOntologies.Extractors.Pattern do
  @moduledoc """
  Extracts patterns from AST nodes.

  This module analyzes Elixir AST nodes representing patterns and extracts their
  type classification, bound variables, and structure. Supports all 10 pattern types
  defined in the elixir-core.ttl ontology plus guard clauses:

  - Variable: `x`, `name`
  - Wildcard: `_`
  - Pin: `^x`
  - Literal: `:ok`, `42`, `"hello"`
  - Tuple: `{a, b}`, `{:ok, value}`
  - List: `[a, b, c]`, `[head | tail]`
  - Map: `%{key: value}`
  - Struct: `%User{name: name}`, `%_{field: val}`
  - Binary: `<<a, b, c>>`, `<<x::binary-size(4)>>`
  - As: `{:ok, _} = result`
  - Guard: `when is_integer(x)`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Pattern
      iex> {:ok, result} = Pattern.extract({:x, [], Elixir})
      iex> result.type
      :variable
      iex> result.metadata.variable_name
      :x

      iex> alias ElixirOntologies.Extractors.Pattern
      iex> {:ok, result} = Pattern.extract({:^, [], [{:x, [], Elixir}]})
      iex> result.type
      :pin
      iex> result.metadata.pinned_variable
      :x
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Constants
  # ===========================================================================

  # Special forms that are NOT variable patterns even though they look like 3-tuples
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
    # Control flow (when used as expressions, not patterns)
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
    :&
  ]

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of pattern extraction.

  - `:type` - The pattern type classification
  - `:value` - The pattern AST or extracted value
  - `:bindings` - List of variables bound by this pattern
  - `:location` - Source location if available
  - `:metadata` - Type-specific additional information
  """
  @type t :: %__MODULE__{
          type: pattern_type(),
          value: term(),
          bindings: [atom()],
          location: Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type pattern_type ::
          :variable
          | :wildcard
          | :pin
          | :literal
          | :tuple
          | :list
          | :map
          | :struct
          | :binary
          | :as
          | :guard

  defstruct [:type, :value, bindings: [], location: nil, metadata: %{}]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a pattern.

  ## Examples

      iex> ElixirOntologies.Extractors.Pattern.pattern?({:x, [], Elixir})
      true

      iex> ElixirOntologies.Extractors.Pattern.pattern?({:_, [], Elixir})
      true

      iex> ElixirOntologies.Extractors.Pattern.pattern?({:^, [], [{:x, [], Elixir}]})
      true

      iex> ElixirOntologies.Extractors.Pattern.pattern?(:ok)
      true

      iex> ElixirOntologies.Extractors.Pattern.pattern?({:%{}, [], [a: 1]})
      true

      iex> ElixirOntologies.Extractors.Pattern.pattern?({:def, [], [{:foo, [], nil}]})
      false
  """
  @spec pattern?(Macro.t()) :: boolean()
  def pattern?(node), do: pattern_type(node) != nil

  @doc """
  Returns the pattern type classification, or `nil` if not a pattern.

  ## Examples

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:x, [], Elixir})
      :variable

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:_, [], Elixir})
      :wildcard

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:^, [], [{:x, [], Elixir}]})
      :pin

      iex> ElixirOntologies.Extractors.Pattern.pattern_type(:ok)
      :literal

      iex> ElixirOntologies.Extractors.Pattern.pattern_type(42)
      :literal

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:a, {:b, [], nil}})
      :tuple

      iex> ElixirOntologies.Extractors.Pattern.pattern_type([{:a, [], nil}])
      :list

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:%{}, [], [a: 1]})
      :map

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]})
      :struct

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:<<>>, [], [1, 2]})
      :binary

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:when, [], [{:x, [], nil}, true]})
      :guard

      iex> ElixirOntologies.Extractors.Pattern.pattern_type({:def, [], [{:foo, [], nil}]})
      nil
  """
  @spec pattern_type(Macro.t()) :: pattern_type() | nil
  def pattern_type(node) do
    cond do
      wildcard?(node) -> :wildcard
      pin?(node) -> :pin
      guard?(node) -> :guard
      as_pattern?(node) -> :as
      struct_pattern?(node) -> :struct
      map_pattern?(node) -> :map
      binary_pattern?(node) -> :binary
      variable?(node) -> :variable
      literal?(node) -> :literal
      tuple_pattern?(node) -> :tuple
      list_pattern?(node) -> :list
      true -> nil
    end
  end

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a pattern from an AST node.

  Returns `{:ok, %Pattern{}}` on success, or `{:error, reason}` if the node
  is not a recognized pattern type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.Pattern.extract({:x, [], Elixir})
      iex> result.type
      :variable

      iex> {:ok, result} = ElixirOntologies.Extractors.Pattern.extract(:ok)
      iex> result.type
      :literal

      iex> {:ok, result} = ElixirOntologies.Extractors.Pattern.extract([1, 2, 3])
      iex> result.type
      :list

      iex> {:error, _} = ElixirOntologies.Extractors.Pattern.extract({:def, [], nil})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract(node) do
    case pattern_type(node) do
      nil -> {:error, "Not a pattern: #{inspect(node)}"}
      :variable -> {:ok, extract_variable(node)}
      :wildcard -> {:ok, extract_wildcard(node)}
      :pin -> {:ok, extract_pin(node)}
      :literal -> {:ok, extract_literal(node)}
      :tuple -> {:ok, extract_tuple(node)}
      :list -> {:ok, extract_list(node)}
      :map -> {:ok, extract_map(node)}
      :struct -> {:ok, extract_struct(node)}
      :binary -> {:ok, extract_binary(node)}
      :as -> {:ok, extract_as(node)}
      :guard -> {:ok, extract_guard(node)}
    end
  end

  @doc """
  Extracts a pattern from an AST node, raising on error.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract!({:x, [], Elixir})
      iex> result.type
      :variable
  """
  @spec extract!(Macro.t()) :: t()
  def extract!(node) do
    case extract(node) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Type-Specific Extractors
  # ===========================================================================

  @doc """
  Extracts a variable pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_variable({:x, [], Elixir})
      iex> result.metadata.variable_name
      :x
      iex> result.bindings
      [:x]
  """
  @spec extract_variable(Macro.t()) :: t()
  def extract_variable({name, meta, _context} = node) when is_atom(name) do
    %__MODULE__{
      type: :variable,
      value: node,
      bindings: [name],
      location: extract_location(node),
      metadata: %{
        variable_name: name,
        context: extract_var_context(meta)
      }
    }
  end

  @doc """
  Extracts a wildcard pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_wildcard({:_, [], Elixir})
      iex> result.type
      :wildcard
      iex> result.bindings
      []
  """
  @spec extract_wildcard(Macro.t()) :: t()
  def extract_wildcard({:_, _meta, _context} = node) do
    %__MODULE__{
      type: :wildcard,
      value: node,
      bindings: [],
      location: extract_location(node),
      metadata: %{}
    }
  end

  @doc """
  Extracts a pin pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_pin({:^, [], [{:x, [], Elixir}]})
      iex> result.metadata.pinned_variable
      :x
      iex> result.bindings
      []
  """
  @spec extract_pin(Macro.t()) :: t()
  def extract_pin({:^, meta, [{name, _var_meta, _context}]} = node) when is_atom(name) do
    %__MODULE__{
      type: :pin,
      value: node,
      bindings: [],
      location: extract_location({:^, meta, []}),
      metadata: %{
        pinned_variable: name
      }
    }
  end

  @doc """
  Extracts a literal pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_literal(:ok)
      iex> result.value
      :ok

      iex> result = ElixirOntologies.Extractors.Pattern.extract_literal(42)
      iex> result.value
      42
  """
  @spec extract_literal(Macro.t()) :: t()
  def extract_literal(literal) do
    %__MODULE__{
      type: :literal,
      value: literal,
      bindings: [],
      location: nil,
      metadata: %{
        literal_type: classify_literal(literal)
      }
    }
  end

  @doc """
  Extracts a tuple pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_tuple({{:a, [], nil}, {:b, [], nil}})
      iex> result.type
      :tuple
      iex> length(result.metadata.elements)
      2

      iex> result = ElixirOntologies.Extractors.Pattern.extract_tuple({:ok, {:value, [], nil}})
      iex> result.type
      :tuple
  """
  @spec extract_tuple(Macro.t()) :: t()
  def extract_tuple({:{}, meta, elements}) when is_list(elements) do
    element_bindings = collect_bindings(elements)

    %__MODULE__{
      type: :tuple,
      value: elements,
      bindings: element_bindings,
      location: extract_location({:{}, meta, elements}),
      metadata: %{
        elements: elements,
        size: length(elements)
      }
    }
  end

  def extract_tuple(tuple) when is_tuple(tuple) and tuple_size(tuple) == 2 do
    elements = Tuple.to_list(tuple)
    element_bindings = collect_bindings(elements)

    %__MODULE__{
      type: :tuple,
      value: elements,
      bindings: element_bindings,
      location: nil,
      metadata: %{
        elements: elements,
        size: 2
      }
    }
  end

  @doc """
  Extracts a list pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_list([{:a, [], nil}, {:b, [], nil}])
      iex> result.type
      :list
      iex> result.metadata.has_cons_cell
      false

      iex> result = ElixirOntologies.Extractors.Pattern.extract_list([{:|, [], [{:h, [], nil}, {:t, [], nil}]}])
      iex> result.metadata.has_cons_cell
      true
  """
  @spec extract_list(Macro.t()) :: t()
  def extract_list(list) when is_list(list) do
    has_cons = has_cons_cell?(list)
    bindings = collect_bindings(list)

    %__MODULE__{
      type: :list,
      value: list,
      bindings: bindings,
      location: nil,
      metadata: %{
        elements: list,
        has_cons_cell: has_cons,
        length: if(has_cons, do: nil, else: length(list))
      }
    }
  end

  @doc """
  Extracts a map pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_map({:%{}, [], [a: {:v, [], nil}]})
      iex> result.type
      :map
  """
  @spec extract_map(Macro.t()) :: t()
  def extract_map({:%{}, meta, pairs}) do
    bindings = collect_bindings_from_pairs(pairs)

    %__MODULE__{
      type: :map,
      value: pairs,
      bindings: bindings,
      location: extract_location({:%{}, meta, pairs}),
      metadata: %{
        pairs: pairs,
        pair_count: length(pairs)
      }
    }
  end

  @doc """
  Extracts a struct pattern.

  ## Examples

      iex> ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:n, [], nil}]}]}
      iex> result = ElixirOntologies.Extractors.Pattern.extract_struct(ast)
      iex> result.type
      :struct
      iex> result.metadata.struct_name
      [:User]

      iex> ast = {:%, [], [{:_, [], nil}, {:%{}, [], []}]}
      iex> result = ElixirOntologies.Extractors.Pattern.extract_struct(ast)
      iex> result.metadata.struct_name
      :any
  """
  @spec extract_struct(Macro.t()) :: t()
  def extract_struct({:%, meta, [struct_name, {:%{}, _map_meta, pairs}]} = node) do
    {name, is_any_struct} = extract_struct_name(struct_name)
    bindings = collect_bindings_from_pairs(pairs)

    %__MODULE__{
      type: :struct,
      value: node,
      bindings: bindings,
      location: extract_location({:%, meta, []}),
      metadata: %{
        struct_name: name,
        is_any_struct: is_any_struct,
        pairs: pairs
      }
    }
  end

  @doc """
  Extracts a binary pattern.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Pattern.extract_binary({:<<>>, [], [{:a, [], nil}, {:b, [], nil}]})
      iex> result.type
      :binary
  """
  @spec extract_binary(Macro.t()) :: t()
  def extract_binary({:<<>>, meta, segments}) do
    bindings = collect_binary_bindings(segments)

    %__MODULE__{
      type: :binary,
      value: segments,
      bindings: bindings,
      location: extract_location({:<<>>, meta, segments}),
      metadata: %{
        segments: segments,
        has_specifiers: has_binary_specifiers?(segments)
      }
    }
  end

  @doc """
  Extracts an as pattern (pattern = variable).

  ## Examples

      iex> ast = {:=, [], [{:ok, {:_, [], nil}}, {:result, [], nil}]}
      iex> result = ElixirOntologies.Extractors.Pattern.extract_as(ast)
      iex> result.type
      :as
      iex> :result in result.bindings
      true
  """
  @spec extract_as(Macro.t()) :: t()
  def extract_as({:=, meta, [left, right]} = node) do
    left_bindings = collect_bindings([left])
    right_bindings = collect_bindings([right])
    all_bindings = Enum.uniq(left_bindings ++ right_bindings)

    %__MODULE__{
      type: :as,
      value: node,
      bindings: all_bindings,
      location: extract_location({:=, meta, []}),
      metadata: %{
        left_pattern: left,
        right_pattern: right
      }
    }
  end

  @doc """
  Extracts a guard clause.

  ## Examples

      iex> ast = {:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}
      iex> result = ElixirOntologies.Extractors.Pattern.extract_guard(ast)
      iex> result.type
      :guard
  """
  @spec extract_guard(Macro.t()) :: t()
  def extract_guard({:when, meta, [pattern, guard_expr]} = node) do
    pattern_bindings = collect_bindings([pattern])

    %__MODULE__{
      type: :guard,
      value: node,
      bindings: pattern_bindings,
      location: extract_location({:when, meta, []}),
      metadata: %{
        pattern: pattern,
        guard_expression: guard_expr
      }
    }
  end

  # ===========================================================================
  # Binding Collection
  # ===========================================================================

  @doc """
  Collects all variable bindings from a pattern or list of patterns.

  ## Examples

      iex> ElixirOntologies.Extractors.Pattern.collect_bindings([{:x, [], nil}])
      [:x]

      iex> ElixirOntologies.Extractors.Pattern.collect_bindings([{:_, [], nil}])
      []

      iex> ElixirOntologies.Extractors.Pattern.collect_bindings([{:^, [], [{:x, [], nil}]}])
      []
  """
  @spec collect_bindings([Macro.t()]) :: [atom()]
  def collect_bindings(patterns) when is_list(patterns) do
    patterns
    |> Enum.flat_map(&collect_bindings_from_node/1)
    |> Enum.uniq()
  end

  # ===========================================================================
  # Private Helpers - Type Detection
  # ===========================================================================

  defp wildcard?({:_, _meta, context}) when is_atom(context), do: true
  defp wildcard?(_), do: false

  defp pin?({:^, _meta, [{name, _var_meta, context}]})
       when is_atom(name) and is_atom(context),
       do: true

  defp pin?(_), do: false

  defp guard?({:when, _meta, [_pattern, _guard]}), do: true
  defp guard?(_), do: false

  defp as_pattern?({:=, _meta, [_left, _right]}), do: true
  defp as_pattern?(_), do: false

  defp struct_pattern?({:%, _meta, [_struct_name, {:%{}, _map_meta, _pairs}]}), do: true
  defp struct_pattern?(_), do: false

  defp map_pattern?({:%{}, _meta, _pairs}), do: true
  defp map_pattern?(_), do: false

  defp binary_pattern?({:<<>>, _meta, _segments}), do: true
  defp binary_pattern?(_), do: false

  defp variable?({name, _meta, context})
       when is_atom(name) and is_atom(context) and name not in @special_forms do
    # Exclude operators and special forms
    not (name in [:^, :%{}, :%, :<<>>, :{}, :=, :when, :|, :"::"])
  end

  defp variable?(_), do: false

  defp literal?(node) do
    is_atom(node) or is_number(node) or is_binary(node)
  end

  defp tuple_pattern?({:{}, _meta, elements}) when is_list(elements), do: true

  defp tuple_pattern?(tuple) when is_tuple(tuple) and tuple_size(tuple) == 2 do
    # 2-element tuples that aren't special AST forms
    case tuple do
      {atom, _} when is_atom(atom) ->
        # Check if first element could be a pattern
        not (atom in [:%, :%{}, :<<>>, :^, :=, :when, :|, :"::", :__aliases__])

      _ ->
        true
    end
  end

  defp tuple_pattern?(_), do: false

  defp list_pattern?(list) when is_list(list), do: true
  defp list_pattern?(_), do: false

  # ===========================================================================
  # Private Helpers - Binding Collection
  # ===========================================================================

  defp collect_bindings_from_node({:_, _meta, _context}), do: []
  defp collect_bindings_from_node({:^, _meta, _}), do: []

  defp collect_bindings_from_node({name, _meta, context})
       when is_atom(name) and is_atom(context) and name not in @special_forms do
    if variable?({name, [], context}), do: [name], else: []
  end

  defp collect_bindings_from_node({:{}, _meta, elements}) do
    collect_bindings(elements)
  end

  defp collect_bindings_from_node({:%, _meta, [_struct, {:%{}, _map_meta, pairs}]}) do
    collect_bindings_from_pairs(pairs)
  end

  defp collect_bindings_from_node({:%{}, _meta, pairs}) do
    collect_bindings_from_pairs(pairs)
  end

  defp collect_bindings_from_node({:<<>>, _meta, segments}) do
    collect_binary_bindings(segments)
  end

  defp collect_bindings_from_node({:=, _meta, [left, right]}) do
    collect_bindings([left]) ++ collect_bindings([right])
  end

  defp collect_bindings_from_node({:when, _meta, [pattern, _guard]}) do
    collect_bindings([pattern])
  end

  defp collect_bindings_from_node({:|, _meta, [head, tail]}) do
    collect_bindings([head]) ++ collect_bindings([tail])
  end

  defp collect_bindings_from_node(tuple) when is_tuple(tuple) and tuple_size(tuple) == 2 do
    collect_bindings(Tuple.to_list(tuple))
  end

  defp collect_bindings_from_node(list) when is_list(list) do
    collect_bindings(list)
  end

  defp collect_bindings_from_node(_), do: []

  defp collect_bindings_from_pairs(pairs) do
    pairs
    |> Enum.flat_map(fn
      {_key, value} -> collect_bindings([value])
      {key, _sep, value} -> collect_bindings([key, value])
      other -> collect_bindings([other])
    end)
    |> Enum.uniq()
  end

  defp collect_binary_bindings(segments) do
    segments
    |> Enum.flat_map(fn
      {:"::", _meta, [pattern, _specifier]} ->
        collect_bindings([pattern])

      other ->
        collect_bindings([other])
    end)
    |> Enum.uniq()
  end

  # ===========================================================================
  # Private Helpers - Metadata Extraction
  # ===========================================================================

  defp extract_var_context(meta) when is_list(meta) do
    Keyword.get(meta, :context)
  end

  defp extract_var_context(_), do: nil

  defp classify_literal(atom) when is_atom(atom) do
    cond do
      atom in [true, false] -> :boolean
      atom == nil -> :nil
      true -> :atom
    end
  end

  defp classify_literal(int) when is_integer(int), do: :integer
  defp classify_literal(float) when is_float(float), do: :float
  defp classify_literal(str) when is_binary(str), do: :string

  defp has_cons_cell?(list) when is_list(list) do
    Enum.any?(list, fn
      {:|, _, _} -> true
      _ -> false
    end)
  end

  defp extract_struct_name({:_, _meta, _context}), do: {:any, true}
  defp extract_struct_name({:__aliases__, _meta, parts}), do: {parts, false}
  defp extract_struct_name(other), do: {other, false}

  defp has_binary_specifiers?(segments) do
    Enum.any?(segments, fn
      {:"::", _, _} -> true
      _ -> false
    end)
  end

  defp extract_location(node), do: Helpers.extract_location(node)
end
