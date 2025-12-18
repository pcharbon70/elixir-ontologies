defmodule ElixirOntologies.Extractors.FunctionSpec do
  @moduledoc """
  Extracts function spec definitions from AST nodes.

  This module analyzes Elixir AST nodes representing function specs
  (@spec) and extracts information including function name, arity,
  parameter types, return type, and type constraints from `when` clauses.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `FunctionSpec` - Type specification for a function
  - `hasSpec` - Links function to spec
  - `hasParameterTypes` - Ordered list of parameter types
  - `hasReturnType` - The return type expression

  ## Usage

      iex> alias ElixirOntologies.Extractors.FunctionSpec
      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:add, [], [{:integer, [], []}, {:integer, [], []}]}, {:integer, [], []}]}]}]}
      iex> {:ok, result} = FunctionSpec.extract(ast)
      iex> result.name
      :add
      iex> result.arity
      2

      iex> alias ElixirOntologies.Extractors.FunctionSpec
      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:now, [], []}, :ok]}]}]}
      iex> {:ok, result} = FunctionSpec.extract(ast)
      iex> result.arity
      0
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of function spec extraction.

  - `:name` - Function name as atom
  - `:arity` - Number of parameters
  - `:parameter_types` - List of parameter type expressions
  - `:return_type` - The return type expression
  - `:type_constraints` - Map of type variable constraints from `when` clause
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          parameter_types: [Macro.t()],
          return_type: Macro.t(),
          type_constraints: %{atom() => Macro.t()},
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :name,
    :arity,
    :return_type,
    parameter_types: [],
    type_constraints: %{},
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a function spec.

  ## Examples

      iex> ElixirOntologies.Extractors.FunctionSpec.spec?({:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]})
      true

      iex> ElixirOntologies.Extractors.FunctionSpec.spec?({:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]})
      false

      iex> ElixirOntologies.Extractors.FunctionSpec.spec?({:@, [], [{:doc, [], ["docs"]}]})
      false

      iex> ElixirOntologies.Extractors.FunctionSpec.spec?(nil)
      false
  """
  @spec spec?(Macro.t()) :: boolean()
  def spec?({:@, _, [{:spec, _, _}]}), do: true
  def spec?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a function spec from an AST node.

  Returns `{:ok, %FunctionSpec{}}` on success, or `{:error, reason}` if the node
  is not a function spec.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:add, [], [{:integer, [], []}, {:integer, [], []}]}, {:integer, [], []}]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> result.name
      :add
      iex> result.arity
      2
      iex> length(result.parameter_types)
      2
      iex> result.return_type
      {:integer, [], []}

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:now, [], []}, :ok]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> result.name
      :now
      iex> result.arity
      0
      iex> result.parameter_types
      []

      iex> ast = {:@, [], [{:spec, [], [{:when, [], [{:"::", [], [{:identity, [], [{:a, [], nil}]}, {:a, [], nil}]}, [a: {:var, [], nil}]]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> result.name
      :identity
      iex> result.type_constraints
      %{a: {:var, [], nil}}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # @spec name(...) :: return_type when constraints
  def extract({:@, meta, [{:spec, _, [{:when, _, [spec_def, constraints]}]}]} = _node, _opts) do
    case extract_spec_definition(spec_def) do
      {:ok, name, param_types, return_type} ->
        constraint_map = extract_constraints(constraints)
        location = Helpers.extract_location({:@, meta, []})

        {:ok,
         %__MODULE__{
           name: name,
           arity: length(param_types),
           parameter_types: param_types,
           return_type: return_type,
           type_constraints: constraint_map,
           location: location,
           metadata: %{
             has_when_clause: true
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # @spec name(...) :: return_type
  def extract({:@, meta, [{:spec, _, [{:"::", _, [func_call, return_type]}]}]} = _node, _opts) do
    case extract_func_call(func_call) do
      {:ok, name, param_types} ->
        location = Helpers.extract_location({:@, meta, []})

        {:ok,
         %__MODULE__{
           name: name,
           arity: length(param_types),
           parameter_types: param_types,
           return_type: return_type,
           type_constraints: %{},
           location: location,
           metadata: %{
             has_when_clause: false
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a function spec", node)}
  end

  @doc """
  Extracts a function spec from an AST node, raising on error.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      iex> result = ElixirOntologies.Extractors.FunctionSpec.extract!(ast)
      iex> result.name
      :foo
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
  Extracts all function specs from a module body.

  Returns a list of extracted function specs in the order they appear.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:@, [], [{:spec, [], [{:"::", [], [{:add, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]},
      ...>   {:@, [], [{:spec, [], [{:"::", [], [{:sub, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]},
      ...>   {:@, [], [{:doc, [], ["docs"]}]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.FunctionSpec.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [:add, :sub]
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(nil), do: []

  def extract_all({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.filter(&spec?/1)
    |> Enum.map(fn node ->
      case extract(node) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement) do
    if spec?(statement) do
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
  Returns true if the spec has a when clause.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:when, [], [{:"::", [], [{:identity, [], [{:a, [], nil}]}, {:a, [], nil}]}, [a: {:var, [], nil}]]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.has_when_clause?(result)
      true

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.has_when_clause?(result)
      false
  """
  @spec has_when_clause?(t()) :: boolean()
  def has_when_clause?(%__MODULE__{type_constraints: constraints}) when map_size(constraints) > 0,
    do: true

  def has_when_clause?(_), do: false

  @doc """
  Returns a spec identifier string.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:add, [], [{:integer, [], []}, {:integer, [], []}]}, {:integer, [], []}]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.spec_id(result)
      "add/2"

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:now, [], []}, :ok]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.spec_id(result)
      "now/0"
  """
  @spec spec_id(t()) :: String.t()
  def spec_id(%__MODULE__{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end

  @doc """
  Returns true if the return type is a union type.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], []}, {:|, [], [:ok, :error]}]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.union_return?(result)
      true

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.union_return?(result)
      false
  """
  @spec union_return?(t()) :: boolean()
  def union_return?(%__MODULE__{return_type: {:|, _, _}}), do: true
  def union_return?(_), do: false

  @doc """
  Flattens a union return type into a list of individual types.

  If the return type is not a union, returns a list containing just that type.

  ## Examples

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], []}, {:|, [], [:ok, :error]}]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.flatten_union_return(result)
      [:ok, :error]

      iex> ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.FunctionSpec.extract(ast)
      iex> ElixirOntologies.Extractors.FunctionSpec.flatten_union_return(result)
      [:ok]
  """
  @spec flatten_union_return(t()) :: [Macro.t()]
  def flatten_union_return(%__MODULE__{return_type: return_type}) do
    flatten_union(return_type)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_spec_definition({:"::", _, [func_call, return_type]}) do
    case extract_func_call(func_call) do
      {:ok, name, param_types} -> {:ok, name, param_types, return_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_spec_definition(node) do
    {:error, Helpers.format_error("Invalid spec definition", node)}
  end

  # Function call with no arguments: name()
  defp extract_func_call({name, _, []}) when is_atom(name) do
    {:ok, name, []}
  end

  # Function call with arguments: name(type1, type2, ...)
  defp extract_func_call({name, _, args}) when is_atom(name) and is_list(args) do
    {:ok, name, args}
  end

  # Function call with nil context (no args): name
  defp extract_func_call({name, _, context}) when is_atom(name) and is_atom(context) do
    {:ok, name, []}
  end

  defp extract_func_call(node) do
    {:error, Helpers.format_error("Invalid function in spec", node)}
  end

  defp extract_constraints(constraints) when is_list(constraints) do
    constraints
    |> Enum.map(fn
      {key, value} when is_atom(key) -> {key, value}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_constraints(_), do: %{}

  defp flatten_union({:|, _, [left, right]}) do
    flatten_union(left) ++ flatten_union(right)
  end

  defp flatten_union(type), do: [type]
end
