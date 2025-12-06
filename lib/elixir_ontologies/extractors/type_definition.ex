defmodule ElixirOntologies.Extractors.TypeDefinition do
  @moduledoc """
  Extracts type definitions from AST nodes.

  This module analyzes Elixir AST nodes representing type definitions
  (@type, @typep, @opaque) and extracts information including type name,
  arity, parameters, visibility, and the type expression.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `TypeDefinition` - Base class for type definitions
  - `PublicType`, `PrivateType`, `OpaqueType` - Visibility subclasses
  - `TypeVariable` - Type parameters in parametric types

  ## Usage

      iex> alias ElixirOntologies.Extractors.TypeDefinition
      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = TypeDefinition.extract(ast)
      iex> result.name
      :t
      iex> result.visibility
      :public

      iex> alias ElixirOntologies.Extractors.TypeDefinition
      iex> ast = {:@, [], [{:typep, [], [{:"::", [], [{:internal, [], nil}, :atom]}]}]}
      iex> {:ok, result} = TypeDefinition.extract(ast)
      iex> result.visibility
      :private
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of type definition extraction.

  - `:name` - Type name as atom
  - `:arity` - Number of type parameters
  - `:visibility` - :public, :private, or :opaque
  - `:parameters` - List of type parameter names
  - `:expression` - The type expression AST
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private | :opaque,
          parameters: [atom()],
          expression: Macro.t(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :name,
    :arity,
    :visibility,
    :expression,
    parameters: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Definition Attributes
  # ===========================================================================

  @type_attributes [:type, :typep, :opaque]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a type definition.

  ## Examples

      iex> ElixirOntologies.Extractors.TypeDefinition.type_definition?({:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]})
      true

      iex> ElixirOntologies.Extractors.TypeDefinition.type_definition?({:@, [], [{:typep, [], [{:"::", [], [{:t, [], nil}, :any]}]}]})
      true

      iex> ElixirOntologies.Extractors.TypeDefinition.type_definition?({:@, [], [{:opaque, [], [{:"::", [], [{:t, [], nil}, :any]}]}]})
      true

      iex> ElixirOntologies.Extractors.TypeDefinition.type_definition?({:@, [], [{:doc, [], ["docs"]}]})
      false

      iex> ElixirOntologies.Extractors.TypeDefinition.type_definition?(nil)
      false
  """
  @spec type_definition?(Macro.t()) :: boolean()
  def type_definition?({:@, _, [{attr, _, _}]}) when attr in @type_attributes, do: true
  def type_definition?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a type definition from an AST node.

  Returns `{:ok, %TypeDefinition{}}` on success, or `{:error, reason}` if the node
  is not a type definition.

  ## Examples

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> result.name
      :t
      iex> result.arity
      0
      iex> result.visibility
      :public

      iex> ast = {:@, [], [{:typep, [], [{:"::", [], [{:internal, [], nil}, :atom]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> result.visibility
      :private

      iex> ast = {:@, [], [{:opaque, [], [{:"::", [], [{:secret, [], nil}, :binary]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> result.visibility
      :opaque

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> result.name
      :my_list
      iex> result.arity
      1
      iex> result.parameters
      [:a]
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # @type name :: expression
  def extract({:@, meta, [{attr, _, [{:"::", _, [type_def, expression]}]}]} = _node, _opts)
      when attr in @type_attributes do
    {name, params} = extract_name_and_params(type_def)
    arity = length(params)
    visibility = attr_to_visibility(attr)
    location = Helpers.extract_location({:@, meta, []})

    {:ok,
     %__MODULE__{
       name: name,
       arity: arity,
       visibility: visibility,
       parameters: params,
       expression: expression,
       location: location,
       metadata: %{
         attribute: attr,
         is_parameterized: arity > 0
       }
     }}
  end

  # @type name (without :: expression, just a declaration)
  def extract({:@, meta, [{attr, _, [{name, _, context}]}]} = _node, _opts)
      when attr in @type_attributes and is_atom(name) and is_atom(context) do
    visibility = attr_to_visibility(attr)
    location = Helpers.extract_location({:@, meta, []})

    {:ok,
     %__MODULE__{
       name: name,
       arity: 0,
       visibility: visibility,
       parameters: [],
       expression: nil,
       location: location,
       metadata: %{
         attribute: attr,
         is_parameterized: false
       }
     }}
  end

  # @type name(params) (parameterized without expression)
  def extract({:@, meta, [{attr, _, [{name, _, params}]}]} = _node, _opts)
      when attr in @type_attributes and is_atom(name) and is_list(params) do
    param_names = extract_param_names(params)
    visibility = attr_to_visibility(attr)
    location = Helpers.extract_location({:@, meta, []})

    {:ok,
     %__MODULE__{
       name: name,
       arity: length(param_names),
       visibility: visibility,
       parameters: param_names,
       expression: nil,
       location: location,
       metadata: %{
         attribute: attr,
         is_parameterized: length(param_names) > 0
       }
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a type definition", node)}
  end

  @doc """
  Extracts a type definition from an AST node, raising on error.

  ## Examples

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> result = ElixirOntologies.Extractors.TypeDefinition.extract!(ast)
      iex> result.name
      :t
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all type definitions from a module body.

  Returns a list of extracted type definitions in the order they appear.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]},
      ...>   {:@, [], [{:typep, [], [{:"::", [], [{:internal, [], nil}, :atom]}]}]},
      ...>   {:@, [], [{:doc, [], ["docs"]}]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.TypeDefinition.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [:t, :internal]
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(nil), do: []

  def extract_all({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.filter(&type_definition?/1)
    |> Enum.map(fn node ->
      case extract(node) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement) do
    if type_definition?(statement) do
      case extract(statement) do
        {:ok, result} -> [result]
        {:error, _} -> []
      end
    else
      []
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the type definition is parameterized.

  ## Examples

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.parameterized?(result)
      true

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.parameterized?(result)
      false
  """
  @spec parameterized?(t()) :: boolean()
  def parameterized?(%__MODULE__{arity: arity}) when arity > 0, do: true
  def parameterized?(_), do: false

  @doc """
  Returns true if the type is public (@type).

  ## Examples

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.public?(result)
      true
  """
  @spec public?(t()) :: boolean()
  def public?(%__MODULE__{visibility: :public}), do: true
  def public?(_), do: false

  @doc """
  Returns true if the type is private (@typep).

  ## Examples

      iex> ast = {:@, [], [{:typep, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.private?(result)
      true
  """
  @spec private?(t()) :: boolean()
  def private?(%__MODULE__{visibility: :private}), do: true
  def private?(_), do: false

  @doc """
  Returns true if the type is opaque (@opaque).

  ## Examples

      iex> ast = {:@, [], [{:opaque, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.opaque?(result)
      true
  """
  @spec opaque?(t()) :: boolean()
  def opaque?(%__MODULE__{visibility: :opaque}), do: true
  def opaque?(_), do: false

  @doc """
  Returns a type identifier string.

  ## Examples

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.type_id(result)
      "my_list/1"

      iex> ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.TypeDefinition.extract(ast)
      iex> ElixirOntologies.Extractors.TypeDefinition.type_id(result)
      "t/0"
  """
  @spec type_id(t()) :: String.t()
  def type_id(%__MODULE__{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_name_and_params({name, _, nil}) when is_atom(name) do
    {name, []}
  end

  defp extract_name_and_params({name, _, context}) when is_atom(name) and is_atom(context) do
    {name, []}
  end

  defp extract_name_and_params({name, _, params}) when is_atom(name) and is_list(params) do
    {name, extract_param_names(params)}
  end

  defp extract_name_and_params(_), do: {nil, []}

  defp extract_param_names(params) when is_list(params) do
    Enum.map(params, fn
      {name, _, _} when is_atom(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_param_names(_), do: []

  defp attr_to_visibility(:type), do: :public
  defp attr_to_visibility(:typep), do: :private
  defp attr_to_visibility(:opaque), do: :opaque
end
