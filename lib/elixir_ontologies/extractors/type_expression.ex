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

  defp do_parse({:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, _fields}]} = ast) do
    %__MODULE__{
      kind: :struct,
      module: module_parts,
      ast: ast,
      metadata: %{}
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
        %{parameterized: false}
      else
        %{parameterized: true, param_count: length(args)}
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
end
