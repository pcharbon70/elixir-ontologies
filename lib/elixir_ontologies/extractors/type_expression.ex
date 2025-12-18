defmodule ElixirOntologies.Extractors.TypeExpression do
  @moduledoc """
  Parses type expressions from AST into structured representations.

  This module analyzes Elixir AST nodes representing type expressions
  and classifies them into appropriate TypeExpression kinds, enabling
  semantic understanding of type annotations.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `TypeExpression` - Base class for all type expressions
  - `BasicType` - Primitive types like atom(), integer()
  - `UnionType` - Union of types (type1 | type2)
  - `TupleType` - Tuple types ({type1, type2})
  - `ListType` - List types ([type])
  - `MapType` - Map types (%{key => value})
  - `FunctionType` - Function types ((args -> return))
  - `RemoteType` - Types from other modules (Module.type())
  - `TypeVariable` - Type variables in polymorphic types

  ## Usage

      iex> alias ElixirOntologies.Extractors.TypeExpression
      iex> {:ok, result} = TypeExpression.parse({:atom, [], []})
      iex> result.kind
      :basic
      iex> result.name
      :atom

      iex> alias ElixirOntologies.Extractors.TypeExpression
      iex> {:ok, result} = TypeExpression.parse({:|, [], [:ok, :error]})
      iex> result.kind
      :union
      iex> length(result.elements)
      2
  """

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of type expression parsing.

  - `:kind` - The type expression kind
  - `:name` - Type name for basic/remote types
  - `:elements` - Child type expressions for union/tuple/list
  - `:key_type` - Key type for map types
  - `:value_type` - Value type for map types
  - `:param_types` - Parameter types for function types
  - `:return_type` - Return type for function types
  - `:module` - Module path for remote types
  - `:ast` - Original AST node
  - `:metadata` - Additional information
  """
  @type kind ::
          :basic
          | :literal
          | :union
          | :tuple
          | :list
          | :map
          | :function
          | :remote
          | :struct
          | :variable
          | :any

  @type t :: %__MODULE__{
          kind: kind(),
          name: atom() | nil,
          elements: [t()] | nil,
          key_type: t() | nil,
          value_type: t() | nil,
          param_types: [t()] | nil,
          return_type: t() | nil,
          module: [atom()] | nil,
          ast: Macro.t(),
          metadata: map()
        }

  defstruct [
    :kind,
    :name,
    :elements,
    :key_type,
    :value_type,
    :param_types,
    :return_type,
    :module,
    :ast,
    metadata: %{}
  ]

  # ===========================================================================
  # Basic Type Names
  # ===========================================================================

  @basic_types [
    :any,
    :atom,
    :binary,
    :bitstring,
    :boolean,
    :byte,
    :char,
    :charlist,
    :float,
    :fun,
    :function,
    :identifier,
    :integer,
    :iodata,
    :iolist,
    :keyword,
    :list,
    :map,
    :mfa,
    :module,
    :neg_integer,
    nil,
    :no_return,
    :node,
    :non_neg_integer,
    :none,
    :nonempty_charlist,
    :nonempty_list,
    :nonempty_string,
    :number,
    :pid,
    :port,
    :pos_integer,
    :reference,
    :string,
    :struct,
    :term,
    :timeout,
    :tuple
  ]

  # ===========================================================================
  # Main Parsing
  # ===========================================================================

  @doc """
  Parses a type expression AST into a structured representation.

  Returns `{:ok, %TypeExpression{}}` on success.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> result.kind
      :basic
      iex> result.name
      :atom

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> result.kind
      :literal
      iex> result.name
      :ok

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:|, [], [:ok, :error]})
      iex> result.kind
      :union
      iex> length(result.elements)
      2

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({{:atom, [], []}, {:integer, [], []}})
      iex> result.kind
      :tuple
      iex> length(result.elements)
      2

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:atom, [], []}])
      iex> result.kind
      :list
  """
  @spec parse(Macro.t()) :: {:ok, t()}
  def parse(ast) do
    {:ok, do_parse(ast)}
  end

  @doc """
  Parses a type expression AST, raising on error.

  ## Examples

      iex> result = ElixirOntologies.Extractors.TypeExpression.parse!({:atom, [], []})
      iex> result.kind
      :basic
  """
  @spec parse!(Macro.t()) :: t()
  def parse!(ast) do
    {:ok, result} = parse(ast)
    result
  end

  @doc """
  Parses a type expression AST with type variable constraints.

  The constraints map associates type variable names with their constraint type ASTs.
  When a type variable is encountered, its constraint (if present) is parsed and
  stored in the metadata. This enables full semantic understanding of polymorphic
  type expressions.

  ## Examples

      iex> constraints = %{a: {:integer, [], []}}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
      iex> result.kind
      :variable
      iex> result.metadata.constraint.kind
      :basic

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints({:atom, [], []}, %{})
      iex> result.kind
      :basic

      iex> constraints = %{a: {:integer, [], []}, b: {:atom, [], []}}
      iex> ast = {:|, [], [{:a, [], nil}, {:b, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints(ast, constraints)
      iex> result.kind
      :union
      iex> [first, second] = result.elements
      iex> first.metadata.constraint.name
      :integer
      iex> second.metadata.constraint.name
      :atom
  """
  @spec parse_with_constraints(Macro.t(), map()) :: {:ok, t()}
  def parse_with_constraints(ast, constraints) when is_map(constraints) do
    {:ok, do_parse_with_constraints(ast, constraints)}
  end

  @doc """
  Parses a type expression AST with constraints, raising on error.

  ## Examples

      iex> constraints = %{a: {:integer, [], []}}
      iex> result = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints!({:a, [], nil}, constraints)
      iex> result.metadata.constraint.kind
      :basic
  """
  @spec parse_with_constraints!(Macro.t(), map()) :: t()
  def parse_with_constraints!(ast, constraints) when is_map(constraints) do
    {:ok, result} = parse_with_constraints(ast, constraints)
    result
  end

  # ===========================================================================
  # Union Types
  # ===========================================================================

  defp do_parse({:|, _, [_left, _right]} = ast) do
    elements = flatten_union(ast)

    parsed_elements =
      elements
      |> Enum.with_index()
      |> Enum.map(fn {element, index} ->
        parsed = do_parse(element)
        %{parsed | metadata: Map.put(parsed.metadata, :union_position, index)}
      end)

    %__MODULE__{
      kind: :union,
      elements: parsed_elements,
      ast: ast,
      metadata: %{element_count: length(elements)}
    }
  end

  # ===========================================================================
  # Tuple Types
  # ===========================================================================

  # Empty tuple
  defp do_parse({:{}, _, []} = ast) do
    %__MODULE__{
      kind: :tuple,
      elements: [],
      ast: ast,
      metadata: %{arity: 0}
    }
  end

  # N-tuple (3 or more elements)
  defp do_parse({:{}, _, elements} = ast) when is_list(elements) do
    %__MODULE__{
      kind: :tuple,
      elements: Enum.map(elements, &do_parse/1),
      ast: ast,
      metadata: %{arity: length(elements)}
    }
  end

  # 2-tuple (represented as actual tuple, not AST)
  defp do_parse({left, right} = ast) when not is_list(right) and not is_atom(left) do
    %__MODULE__{
      kind: :tuple,
      elements: [do_parse(left), do_parse(right)],
      ast: ast,
      metadata: %{arity: 2}
    }
  end

  # Tagged 2-tuple like {:ok, term()}
  defp do_parse({tag, right} = ast) when is_atom(tag) and not is_list(right) do
    %__MODULE__{
      kind: :tuple,
      elements: [do_parse(tag), do_parse(right)],
      ast: ast,
      metadata: %{arity: 2, tagged: true, tag: tag}
    }
  end

  # ===========================================================================
  # Function Types (must come before List Types to match first)
  # ===========================================================================

  # Function type (list with arrow)
  defp do_parse([{:->, _, [params, return_type]}] = ast) do
    param_types =
      case params do
        [{:..., _, _}] -> :any
        params when is_list(params) -> Enum.map(params, &do_parse/1)
      end

    %__MODULE__{
      kind: :function,
      param_types: param_types,
      return_type: do_parse(return_type),
      ast: ast,
      metadata: %{
        arity: if(param_types == :any, do: :any, else: length(param_types))
      }
    }
  end

  # ===========================================================================
  # List Types
  # ===========================================================================

  # Empty list
  defp do_parse([] = ast) do
    %__MODULE__{
      kind: :list,
      elements: [],
      ast: ast,
      metadata: %{empty: true}
    }
  end

  # Nonempty list marker [...]
  defp do_parse([{:..., _, _}] = ast) do
    %__MODULE__{
      kind: :list,
      elements: [],
      ast: ast,
      metadata: %{nonempty: true}
    }
  end

  # List with element type [type]
  defp do_parse([element] = ast) do
    %__MODULE__{
      kind: :list,
      elements: [do_parse(element)],
      ast: ast,
      metadata: %{}
    }
  end

  # ===========================================================================
  # Map Types
  # ===========================================================================

  # Empty map
  defp do_parse({:%{}, _, []} = ast) do
    %__MODULE__{
      kind: :map,
      elements: [],
      ast: ast,
      metadata: %{empty: true}
    }
  end

  # Map with key-value pairs
  defp do_parse({:%{}, _, pairs} = ast) when is_list(pairs) do
    parsed_pairs = parse_map_pairs(pairs)

    %__MODULE__{
      kind: :map,
      elements: parsed_pairs,
      ast: ast,
      metadata: %{pair_count: length(parsed_pairs)}
    }
  end

  # ===========================================================================
  # Struct Types
  # ===========================================================================

  defp do_parse({:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, fields}]} = ast) do
    parsed_fields =
      if fields == [] do
        nil
      else
        Enum.map(fields, fn {field_name, field_type} ->
          %{name: field_name, type: do_parse(field_type)}
        end)
      end

    %__MODULE__{
      kind: :struct,
      module: module_parts,
      elements: parsed_fields,
      ast: ast,
      metadata: %{
        field_count: if(parsed_fields, do: length(parsed_fields), else: 0)
      }
    }
  end

  # ===========================================================================
  # Remote Types
  # ===========================================================================

  # Remote type with parameters: Module.type(args)
  defp do_parse({{:., _, [{:__aliases__, _, module_parts}, type_name]}, _, args} = ast)
       when is_list(args) do
    parsed_params =
      if args == [] do
        nil
      else
        args
        |> Enum.with_index()
        |> Enum.map(fn {arg, index} ->
          parsed = do_parse(arg)
          %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
        end)
      end

    metadata =
      if args == [] do
        %{parameterized: false, arity: 0}
      else
        %{parameterized: true, param_count: length(args), arity: length(args)}
      end

    %__MODULE__{
      kind: :remote,
      name: type_name,
      module: module_parts,
      elements: parsed_params,
      ast: ast,
      metadata: metadata
    }
  end

  # ===========================================================================
  # Basic Types
  # ===========================================================================

  # Basic type call: atom(), integer(), etc.
  defp do_parse({name, _, []} = ast) when name in @basic_types do
    %__MODULE__{
      kind: :basic,
      name: name,
      ast: ast,
      metadata: %{}
    }
  end

  # Parameterized basic type: list(element), keyword(value)
  defp do_parse({name, _, args} = ast)
       when name in @basic_types and is_list(args) and args != [] do
    parsed_params =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        parsed = do_parse(arg)
        %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
      end)

    %__MODULE__{
      kind: :basic,
      name: name,
      elements: parsed_params,
      ast: ast,
      metadata: %{parameterized: true, param_count: length(args)}
    }
  end

  # ===========================================================================
  # Type Variables
  # ===========================================================================

  # Type variable: a, element, etc. (bare atom with context)
  defp do_parse({name, _, context} = ast) when is_atom(name) and is_atom(context) do
    %__MODULE__{
      kind: :variable,
      name: name,
      ast: ast,
      metadata: %{}
    }
  end

  # ===========================================================================
  # Literal Types
  # ===========================================================================

  # Literal atom
  defp do_parse(atom = ast) when is_atom(atom) do
    %__MODULE__{
      kind: :literal,
      name: atom,
      ast: ast,
      metadata: %{literal_type: :atom}
    }
  end

  # Literal integer
  defp do_parse(int = ast) when is_integer(int) do
    %__MODULE__{
      kind: :literal,
      name: int,
      ast: ast,
      metadata: %{literal_type: :integer}
    }
  end

  # Literal float
  defp do_parse(float = ast) when is_float(float) do
    %__MODULE__{
      kind: :literal,
      name: float,
      ast: ast,
      metadata: %{literal_type: :float}
    }
  end

  # Range literal: 1..10
  defp do_parse({:.., _, [start_ast, end_ast]} = ast) do
    %__MODULE__{
      kind: :literal,
      name: nil,
      ast: ast,
      metadata: %{
        literal_type: :range,
        range_start: evaluate_literal(start_ast),
        range_end: evaluate_literal(end_ast)
      }
    }
  end

  # Step range literal: 1..100//5
  defp do_parse({:..//, _, [start_ast, end_ast, step_ast]} = ast) do
    %__MODULE__{
      kind: :literal,
      name: nil,
      ast: ast,
      metadata: %{
        literal_type: :range,
        range_start: evaluate_literal(start_ast),
        range_end: evaluate_literal(end_ast),
        range_step: evaluate_literal(step_ast)
      }
    }
  end

  # Empty binary: <<>>
  defp do_parse({:<<>>, _, []} = ast) do
    %__MODULE__{
      kind: :literal,
      name: nil,
      ast: ast,
      metadata: %{literal_type: :binary, binary_size: 0}
    }
  end

  # Binary with segments: <<_::8>>, <<_::binary>>, etc.
  defp do_parse({:<<>>, _, segments} = ast) when is_list(segments) do
    parsed_segments = Enum.map(segments, &parse_binary_segment/1)

    %__MODULE__{
      kind: :literal,
      name: nil,
      elements: parsed_segments,
      ast: ast,
      metadata: %{literal_type: :binary, segment_count: length(segments)}
    }
  end

  # ===========================================================================
  # Fallback
  # ===========================================================================

  defp do_parse(ast) do
    %__MODULE__{
      kind: :any,
      ast: ast,
      metadata: %{unrecognized: true}
    }
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the type expression is a basic type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.basic?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:|, [], [:ok, :error]})
      iex> ElixirOntologies.Extractors.TypeExpression.basic?(result)
      false
  """
  @spec basic?(t()) :: boolean()
  def basic?(%__MODULE__{kind: :basic}), do: true
  def basic?(_), do: false

  @doc """
  Returns true if the type expression is a union type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:|, [], [:ok, :error]})
      iex> ElixirOntologies.Extractors.TypeExpression.union?(result)
      true
  """
  @spec union?(t()) :: boolean()
  def union?(%__MODULE__{kind: :union}), do: true
  def union?(_), do: false

  @doc """
  Returns true if the type expression is a tuple type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({{:atom, [], []}, {:integer, [], []}})
      iex> ElixirOntologies.Extractors.TypeExpression.tuple?(result)
      true
  """
  @spec tuple?(t()) :: boolean()
  def tuple?(%__MODULE__{kind: :tuple}), do: true
  def tuple?(_), do: false

  @doc """
  Returns true if the type expression is a list type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:atom, [], []}])
      iex> ElixirOntologies.Extractors.TypeExpression.list?(result)
      true
  """
  @spec list?(t()) :: boolean()
  def list?(%__MODULE__{kind: :list}), do: true
  def list?(_), do: false

  @doc """
  Returns true if the type expression is a map type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:%{}, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.map?(result)
      true
  """
  @spec map?(t()) :: boolean()
  def map?(%__MODULE__{kind: :map}), do: true
  def map?(_), do: false

  @doc """
  Returns true if the type expression is a function type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      iex> ElixirOntologies.Extractors.TypeExpression.function?(result)
      true
  """
  @spec function?(t()) :: boolean()
  def function?(%__MODULE__{kind: :function}), do: true
  def function?(_), do: false

  @doc """
  Returns the parameter types for a function type expression.

  Returns `:any` for any-arity functions (`(... -> return)`), a list of
  TypeExpression structs for fixed-arity functions, or `nil` for non-function types.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      iex> params = ElixirOntologies.Extractors.TypeExpression.param_types(result)
      iex> length(params)
      1
      iex> hd(params).name
      :integer

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:..., [], nil}], {:atom, [], []}]}])
      iex> ElixirOntologies.Extractors.TypeExpression.param_types(result)
      :any

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.param_types(result)
      nil
  """
  @spec param_types(t()) :: [t()] | :any | nil
  def param_types(%__MODULE__{kind: :function, param_types: params}), do: params
  def param_types(_), do: nil

  @doc """
  Returns the return type for a function type expression.

  Returns the TypeExpression for the return type, or `nil` for non-function types.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      iex> return = ElixirOntologies.Extractors.TypeExpression.return_type(result)
      iex> return.kind
      :basic
      iex> return.name
      :atom

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.return_type(result)
      nil
  """
  @spec return_type(t()) :: t() | nil
  def return_type(%__MODULE__{kind: :function, return_type: return}), do: return
  def return_type(_), do: nil

  @doc """
  Returns the arity of a function type expression.

  Returns `:any` for any-arity functions, the number of parameters for
  fixed-arity functions, or `nil` for non-function types.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      iex> ElixirOntologies.Extractors.TypeExpression.function_arity(result)
      1

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[], {:atom, [], []}]}])
      iex> ElixirOntologies.Extractors.TypeExpression.function_arity(result)
      0

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse([{:->, [], [[{:..., [], nil}], {:atom, [], []}]}])
      iex> ElixirOntologies.Extractors.TypeExpression.function_arity(result)
      :any

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.function_arity(result)
      nil
  """
  @spec function_arity(t()) :: non_neg_integer() | :any | nil
  def function_arity(%__MODULE__{kind: :function, metadata: %{arity: arity}}), do: arity
  def function_arity(_), do: nil

  @doc """
  Returns true if the type expression is a remote type.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.remote?(result)
      true
  """
  @spec remote?(t()) :: boolean()
  def remote?(%__MODULE__{kind: :remote}), do: true
  def remote?(_), do: false

  @doc """
  Returns the module as an IRI-compatible string.

  Returns the module path in the format used by Elixir's module system,
  with "Elixir." prefix and dot-separated segments.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.module_iri(result)
      "Elixir.String"

      iex> ast = {{:., [], [{:__aliases__, [], [:MyApp, :Accounts, :User]}, :t]}, [], []}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.module_iri(result)
      "Elixir.MyApp.Accounts.User"
  """
  @spec module_iri(t()) :: String.t() | nil
  def module_iri(%__MODULE__{kind: :remote, module: module_parts}) when is_list(module_parts) do
    "Elixir." <> Enum.join(module_parts, ".")
  end

  def module_iri(_), do: nil

  @doc """
  Returns the full type reference as an IRI-compatible string.

  The format is `Elixir.Module.Path#type_name/arity`, which uniquely
  identifies a type definition within Elixir's module system.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.type_iri(result)
      "Elixir.String#t/0"

      iex> ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.type_iri(result)
      "Elixir.Enumerable#t/1"
  """
  @spec type_iri(t()) :: String.t() | nil
  def type_iri(%__MODULE__{kind: :remote, module: module_parts, name: type_name, metadata: metadata})
      when is_list(module_parts) do
    arity = Map.get(metadata, :arity, 0)
    "Elixir." <> Enum.join(module_parts, ".") <> "##{type_name}/#{arity}"
  end

  def type_iri(_), do: nil

  @doc """
  Returns true if the type expression is a struct type.

  ## Examples

      iex> ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.struct?(result)
      true
  """
  @spec struct?(t()) :: boolean()
  def struct?(%__MODULE__{kind: :struct}), do: true
  def struct?(_), do: false

  @doc """
  Returns the struct module as an IRI-compatible string.

  Returns the module path in the format used by Elixir's module system,
  with "Elixir." prefix and dot-separated segments.

  ## Examples

      iex> ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.struct_module(result)
      "Elixir.User"

      iex> ast = {:%, [], [{:__aliases__, [], [:MyApp, :Accounts, :User]}, {:%{}, [], []}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.struct_module(result)
      "Elixir.MyApp.Accounts.User"

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.struct_module(result)
      nil
  """
  @spec struct_module(t()) :: String.t() | nil
  def struct_module(%__MODULE__{kind: :struct, module: module_parts}) when is_list(module_parts) do
    "Elixir." <> Enum.join(module_parts, ".")
  end

  def struct_module(_), do: nil

  @doc """
  Returns the field type constraints for a struct type.

  Returns a list of maps with `:name` (atom) and `:type` (TypeExpression) keys
  for each field constraint, or `nil` if the struct has no field constraints
  or if the type expression is not a struct type.

  ## Examples

      iex> ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:binary, [], []}, age: {:integer, [], []}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> fields = ElixirOntologies.Extractors.TypeExpression.struct_fields(result)
      iex> length(fields)
      2
      iex> hd(fields).name
      :name
      iex> hd(fields).type.name
      :binary

      iex> ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.struct_fields(result)
      nil

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.struct_fields(result)
      nil
  """
  @spec struct_fields(t()) :: [%{name: atom(), type: t()}] | nil
  def struct_fields(%__MODULE__{kind: :struct, elements: fields}) when is_list(fields), do: fields
  def struct_fields(_), do: nil

  @doc """
  Returns true if the type expression is a type variable.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:a, [], nil})
      iex> ElixirOntologies.Extractors.TypeExpression.variable?(result)
      true
  """
  @spec variable?(t()) :: boolean()
  def variable?(%__MODULE__{kind: :variable}), do: true
  def variable?(_), do: false

  @doc """
  Returns true if the type variable has a constraint.

  Only returns true for type variables parsed with `parse_with_constraints/2`
  that have an associated constraint type.

  ## Examples

      iex> constraints = %{a: {:integer, [], []}}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
      iex> ElixirOntologies.Extractors.TypeExpression.constrained?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints({:b, [], nil}, %{a: {:integer, [], []}})
      iex> ElixirOntologies.Extractors.TypeExpression.constrained?(result)
      false

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:a, [], nil})
      iex> ElixirOntologies.Extractors.TypeExpression.constrained?(result)
      false
  """
  @spec constrained?(t()) :: boolean()
  def constrained?(%__MODULE__{kind: :variable, metadata: %{constrained: true}}), do: true
  def constrained?(_), do: false

  @doc """
  Returns the constraint type expression for a constrained type variable.

  Returns `nil` if the type expression is not a constrained type variable.

  ## Examples

      iex> constraints = %{a: {:integer, [], []}}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
      iex> constraint = ElixirOntologies.Extractors.TypeExpression.constraint_type(result)
      iex> constraint.kind
      :basic
      iex> constraint.name
      :integer

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:a, [], nil})
      iex> ElixirOntologies.Extractors.TypeExpression.constraint_type(result)
      nil
  """
  @spec constraint_type(t()) :: t() | nil
  def constraint_type(%__MODULE__{kind: :variable, metadata: %{constraint: constraint}}),
    do: constraint

  def constraint_type(_), do: nil

  @doc """
  Returns true if the type expression is a literal type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> ElixirOntologies.Extractors.TypeExpression.literal?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(42)
      iex> ElixirOntologies.Extractors.TypeExpression.literal?(result)
      true
  """
  @spec literal?(t()) :: boolean()
  def literal?(%__MODULE__{kind: :literal}), do: true
  def literal?(_), do: false

  @doc """
  Returns the value of a literal type expression.

  Returns the literal value for atom, integer, and float literals,
  or `nil` for range/binary literals and non-literal types.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> ElixirOntologies.Extractors.TypeExpression.literal_value(result)
      :ok

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(42)
      iex> ElixirOntologies.Extractors.TypeExpression.literal_value(result)
      42

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.literal_value(result)
      nil
  """
  @spec literal_value(t()) :: term() | nil
  def literal_value(%__MODULE__{kind: :literal, name: value}), do: value
  def literal_value(_), do: nil

  @doc """
  Returns true if the type expression is a range literal.

  ## Examples

      iex> ast = {:.., [], [1, 10]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.range?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> ElixirOntologies.Extractors.TypeExpression.range?(result)
      false
  """
  @spec range?(t()) :: boolean()
  def range?(%__MODULE__{kind: :literal, metadata: %{literal_type: :range}}), do: true
  def range?(_), do: false

  @doc """
  Returns true if the type expression is a binary literal.

  ## Examples

      iex> ast = {:<<>>, [], []}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.binary_literal?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> ElixirOntologies.Extractors.TypeExpression.binary_literal?(result)
      false
  """
  @spec binary_literal?(t()) :: boolean()
  def binary_literal?(%__MODULE__{kind: :literal, metadata: %{literal_type: :binary}}), do: true
  def binary_literal?(_), do: false

  @doc """
  Returns the range bounds for a range literal type.

  Returns a map with `:start`, `:end`, and optionally `:step` keys,
  or `nil` for non-range types.

  ## Examples

      iex> ast = {:.., [], [1, 10]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.range_bounds(result)
      %{start: 1, end: 10}

      iex> ast = {:..//, [], [1, 100, 5]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
      iex> ElixirOntologies.Extractors.TypeExpression.range_bounds(result)
      %{start: 1, end: 100, step: 5}

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(:ok)
      iex> ElixirOntologies.Extractors.TypeExpression.range_bounds(result)
      nil
  """
  @spec range_bounds(t()) :: %{start: integer(), end: integer(), step: integer()} | %{start: integer(), end: integer()} | nil
  def range_bounds(%__MODULE__{kind: :literal, metadata: %{literal_type: :range} = metadata}) do
    base = %{start: metadata[:range_start], end: metadata[:range_end]}

    case metadata[:range_step] do
      nil -> base
      step -> Map.put(base, :step, step)
    end
  end

  def range_bounds(_), do: nil

  @doc """
  Returns true if the type expression is parameterized (has type parameters).

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:list, [], [{:integer, [], []}]})
      iex> ElixirOntologies.Extractors.TypeExpression.parameterized?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse({:atom, [], []})
      iex> ElixirOntologies.Extractors.TypeExpression.parameterized?(result)
      false
  """
  @spec parameterized?(t()) :: boolean()
  def parameterized?(%__MODULE__{metadata: %{parameterized: true}}), do: true
  def parameterized?(_), do: false

  @doc """
  Returns the list of known basic type names.

  ## Examples

      iex> :atom in ElixirOntologies.Extractors.TypeExpression.basic_type_names()
      true

      iex> :integer in ElixirOntologies.Extractors.TypeExpression.basic_type_names()
      true
  """
  @spec basic_type_names() :: [atom()]
  def basic_type_names, do: @basic_types

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp flatten_union({:|, _, [left, right]}) do
    flatten_union(left) ++ flatten_union(right)
  end

  defp flatten_union(type), do: [type]

  defp parse_map_pairs(pairs) do
    Enum.map(pairs, fn
      # Keyword-style: key: type
      {key, value} when is_atom(key) ->
        %{
          key: do_parse(key),
          value: do_parse(value),
          required: true,
          keyword_style: true
        }

      # Arrow-style: key_type => value_type
      {{key_type, value_type}} ->
        %{
          key: do_parse(key_type),
          value: do_parse(value_type),
          required: detect_required(key_type)
        }

      # Required/optional wrapper
      {{:required, _, [key_type]}, value_type} ->
        %{
          key: do_parse(key_type),
          value: do_parse(value_type),
          required: true
        }

      {{:optional, _, [key_type]}, value_type} ->
        %{
          key: do_parse(key_type),
          value: do_parse(value_type),
          required: false
        }

      # Generic pair
      {key, value} ->
        %{
          key: do_parse(key),
          value: do_parse(value),
          required: detect_required(key)
        }
    end)
  end

  defp detect_required({:required, _, _}), do: true
  defp detect_required({:optional, _, _}), do: false
  defp detect_required(_), do: true

  # Evaluate literal values from AST (handles negation)
  defp evaluate_literal(int) when is_integer(int), do: int
  defp evaluate_literal(float) when is_float(float), do: float
  defp evaluate_literal({:-, _, [value]}) when is_integer(value), do: -value
  defp evaluate_literal({:-, _, [value]}) when is_float(value), do: -value
  defp evaluate_literal(_), do: nil

  # Parse binary segment specifications
  defp parse_binary_segment({:"::", _, [{:_, _, _}, size]}) when is_integer(size) do
    %{type: :sized, size: size}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:binary, _, _}]}) do
    %{type: :binary}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:bitstring, _, _}]}) do
    %{type: :bitstring}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:bytes, _, _}]}) do
    %{type: :bytes}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:integer, _, _}]}) do
    %{type: :integer}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:float, _, _}]}) do
    %{type: :float}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:utf8, _, _}]}) do
    %{type: :utf8}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:utf16, _, _}]}) do
    %{type: :utf16}
  end

  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:utf32, _, _}]}) do
    %{type: :utf32}
  end

  # Variable size: <<_::_*8>>
  defp parse_binary_segment({:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, unit]}]})
       when is_integer(unit) do
    %{type: :variable_size, unit: unit}
  end

  # Generic segment (fallback)
  defp parse_binary_segment(segment) do
    %{type: :unknown, ast: segment}
  end

  # ===========================================================================
  # Constraint-Aware Parsing
  # ===========================================================================

  # Delegate to regular parsing when no constraints
  defp do_parse_with_constraints(ast, constraints) when map_size(constraints) == 0 do
    do_parse(ast)
  end

  # Union types - propagate constraints to elements
  defp do_parse_with_constraints({:|, _, [_left, _right]} = ast, constraints) do
    elements = flatten_union(ast)

    parsed_elements =
      elements
      |> Enum.with_index()
      |> Enum.map(fn {element, index} ->
        parsed = do_parse_with_constraints(element, constraints)
        %{parsed | metadata: Map.put(parsed.metadata, :union_position, index)}
      end)

    %__MODULE__{
      kind: :union,
      elements: parsed_elements,
      ast: ast,
      metadata: %{element_count: length(elements)}
    }
  end

  # Tuple types - propagate constraints to elements
  defp do_parse_with_constraints({:{}, _, []} = ast, _constraints) do
    %__MODULE__{
      kind: :tuple,
      elements: [],
      ast: ast,
      metadata: %{arity: 0}
    }
  end

  defp do_parse_with_constraints({:{}, _, elements} = ast, constraints) when is_list(elements) do
    %__MODULE__{
      kind: :tuple,
      elements: Enum.map(elements, &do_parse_with_constraints(&1, constraints)),
      ast: ast,
      metadata: %{arity: length(elements)}
    }
  end

  defp do_parse_with_constraints({left, right} = ast, constraints)
       when not is_list(right) and not is_atom(left) do
    %__MODULE__{
      kind: :tuple,
      elements: [
        do_parse_with_constraints(left, constraints),
        do_parse_with_constraints(right, constraints)
      ],
      ast: ast,
      metadata: %{arity: 2}
    }
  end

  defp do_parse_with_constraints({tag, right} = ast, constraints)
       when is_atom(tag) and not is_list(right) do
    %__MODULE__{
      kind: :tuple,
      elements: [do_parse(tag), do_parse_with_constraints(right, constraints)],
      ast: ast,
      metadata: %{arity: 2, tagged: true, tag: tag}
    }
  end

  # Function types - propagate constraints
  defp do_parse_with_constraints([{:->, _, [params, return_type]}] = ast, constraints) do
    param_types =
      case params do
        [{:..., _, _}] -> :any
        params when is_list(params) -> Enum.map(params, &do_parse_with_constraints(&1, constraints))
      end

    %__MODULE__{
      kind: :function,
      param_types: param_types,
      return_type: do_parse_with_constraints(return_type, constraints),
      ast: ast,
      metadata: %{
        arity: if(param_types == :any, do: :any, else: length(param_types))
      }
    }
  end

  # List types - propagate constraints
  defp do_parse_with_constraints([] = ast, _constraints) do
    %__MODULE__{
      kind: :list,
      elements: [],
      ast: ast,
      metadata: %{empty: true}
    }
  end

  defp do_parse_with_constraints([{:..., _, _}] = ast, _constraints) do
    %__MODULE__{
      kind: :list,
      elements: [],
      ast: ast,
      metadata: %{nonempty: true}
    }
  end

  defp do_parse_with_constraints([element] = ast, constraints) do
    %__MODULE__{
      kind: :list,
      elements: [do_parse_with_constraints(element, constraints)],
      ast: ast,
      metadata: %{}
    }
  end

  # Map types - propagate constraints
  defp do_parse_with_constraints({:%{}, _, []} = ast, _constraints) do
    %__MODULE__{
      kind: :map,
      elements: [],
      ast: ast,
      metadata: %{empty: true}
    }
  end

  defp do_parse_with_constraints({:%{}, _, pairs} = ast, constraints) when is_list(pairs) do
    parsed_pairs = parse_map_pairs_with_constraints(pairs, constraints)

    %__MODULE__{
      kind: :map,
      elements: parsed_pairs,
      ast: ast,
      metadata: %{pair_count: length(parsed_pairs)}
    }
  end

  # Struct types - propagate constraints to field types
  defp do_parse_with_constraints(
         {:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, fields}]} = ast,
         constraints
       ) do
    parsed_fields =
      if fields == [] do
        nil
      else
        Enum.map(fields, fn {field_name, field_type} ->
          %{name: field_name, type: do_parse_with_constraints(field_type, constraints)}
        end)
      end

    %__MODULE__{
      kind: :struct,
      module: module_parts,
      elements: parsed_fields,
      ast: ast,
      metadata: %{
        field_count: if(parsed_fields, do: length(parsed_fields), else: 0)
      }
    }
  end

  # Remote types - propagate constraints to params
  defp do_parse_with_constraints(
         {{:., _, [{:__aliases__, _, module_parts}, type_name]}, _, args} = ast,
         constraints
       )
       when is_list(args) do
    parsed_params =
      if args == [] do
        nil
      else
        args
        |> Enum.with_index()
        |> Enum.map(fn {arg, index} ->
          parsed = do_parse_with_constraints(arg, constraints)
          %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
        end)
      end

    metadata =
      if args == [] do
        %{parameterized: false, arity: 0}
      else
        %{parameterized: true, param_count: length(args), arity: length(args)}
      end

    %__MODULE__{
      kind: :remote,
      name: type_name,
      module: module_parts,
      elements: parsed_params,
      ast: ast,
      metadata: metadata
    }
  end

  # Basic type call with no args
  defp do_parse_with_constraints({name, _, []} = ast, _constraints) when name in @basic_types do
    %__MODULE__{
      kind: :basic,
      name: name,
      ast: ast,
      metadata: %{}
    }
  end

  # Parameterized basic types - propagate constraints
  defp do_parse_with_constraints({name, _, args} = ast, constraints)
       when name in @basic_types and is_list(args) and args != [] do
    parsed_params =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        parsed = do_parse_with_constraints(arg, constraints)
        %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
      end)

    %__MODULE__{
      kind: :basic,
      name: name,
      elements: parsed_params,
      ast: ast,
      metadata: %{parameterized: true, param_count: length(args)}
    }
  end

  # Type variable with constraint - THE KEY CASE
  defp do_parse_with_constraints({name, _, context} = ast, constraints)
       when is_atom(name) and is_atom(context) do
    case Map.get(constraints, name) do
      nil ->
        # No constraint for this variable
        %__MODULE__{
          kind: :variable,
          name: name,
          ast: ast,
          metadata: %{constrained: false}
        }

      constraint_ast ->
        # Parse the constraint type
        constraint = do_parse(constraint_ast)

        %__MODULE__{
          kind: :variable,
          name: name,
          ast: ast,
          metadata: %{constrained: true, constraint: constraint}
        }
    end
  end

  # Literal atoms
  defp do_parse_with_constraints(atom, _constraints) when is_atom(atom) do
    do_parse(atom)
  end

  # Literal integers
  defp do_parse_with_constraints(int, _constraints) when is_integer(int) do
    do_parse(int)
  end

  # Literal floats
  defp do_parse_with_constraints(float, _constraints) when is_float(float) do
    do_parse(float)
  end

  # Fallback
  defp do_parse_with_constraints(ast, _constraints) do
    do_parse(ast)
  end

  # Helper for parsing map pairs with constraints
  defp parse_map_pairs_with_constraints(pairs, constraints) do
    Enum.map(pairs, fn
      {key, value} when is_atom(key) ->
        %{
          key: do_parse(key),
          value: do_parse_with_constraints(value, constraints),
          required: true,
          keyword_style: true
        }

      {{key_type, value_type}} ->
        %{
          key: do_parse_with_constraints(key_type, constraints),
          value: do_parse_with_constraints(value_type, constraints),
          required: detect_required(key_type)
        }

      {{:required, _, [key_type]}, value_type} ->
        %{
          key: do_parse_with_constraints(key_type, constraints),
          value: do_parse_with_constraints(value_type, constraints),
          required: true
        }

      {{:optional, _, [key_type]}, value_type} ->
        %{
          key: do_parse_with_constraints(key_type, constraints),
          value: do_parse_with_constraints(value_type, constraints),
          required: false
        }

      {key, value} ->
        %{
          key: do_parse_with_constraints(key, constraints),
          value: do_parse_with_constraints(value, constraints),
          required: detect_required(key)
        }
    end)
  end
end
