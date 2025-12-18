defmodule ElixirOntologies.Extractors.Clause do
  @moduledoc """
  Extracts function clauses from AST nodes.

  This module analyzes Elixir AST nodes representing function definitions and
  extracts individual clauses with their head (parameters, guards) and body.
  Supports grouping multi-clause functions and maintaining clause order.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `FunctionClause` - Individual clause with `clauseOrder`
  - `FunctionHead` - Parameters and guards
  - `FunctionBody` - The expression(s) in the clause

  ## Usage

      iex> alias ElixirOntologies.Extractors.Clause
      iex> ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = Clause.extract(ast)
      iex> result.name
      :foo
      iex> result.arity
      1
      iex> result.order
      1

      iex> alias ElixirOntologies.Extractors.Clause
      iex> ast = {:def, [], [{:greet, [], nil}, [do: "hello"]]}
      iex> {:ok, result} = Clause.extract(ast)
      iex> result.body
      "hello"
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of clause extraction.

  - `:name` - Function name as atom
  - `:arity` - Number of parameters
  - `:visibility` - :public or :private
  - `:order` - Clause order (1-indexed)
  - `:head` - Function head with parameters and guard
  - `:body` - Function body expression(s)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private,
          order: pos_integer(),
          head: head(),
          body: Macro.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type head :: %{
          parameters: [Macro.t()],
          guard: Macro.t() | nil
        }

  defstruct [
    :name,
    :arity,
    :visibility,
    :order,
    :head,
    :body,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Function Definition Types
  # ===========================================================================

  @public_functions [:def]
  @private_functions [:defp]
  @all_function_types @public_functions ++ @private_functions

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a function clause.

  ## Examples

      iex> ElixirOntologies.Extractors.Clause.clause?({:def, [], [{:foo, [], nil}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Clause.clause?({:defp, [], [{:bar, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Clause.clause?({:defmodule, [], [{:Foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Clause.clause?(:not_a_clause)
      false
  """
  @spec clause?(Macro.t()) :: boolean()
  def clause?({type, _meta, _args}) when type in @all_function_types, do: true
  def clause?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a function clause from an AST node.

  Returns `{:ok, %Clause{}}` on success, or `{:error, reason}` if the node
  is not a function definition.

  ## Options

  - `:order` - Clause order (1-indexed, defaults to 1)

  ## Examples

      iex> ast = {:def, [], [{:hello, [], [{:name, [], nil}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> result.name
      :hello
      iex> result.arity
      1
      iex> result.head.parameters
      [{:name, [], nil}]

      iex> ast = {:def, [], [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> result.head.guard != nil
      true

      iex> ast = {:defp, [], [{:internal, [], nil}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> result.visibility
      :private

      iex> {:error, _} = ElixirOntologies.Extractors.Clause.extract({:defmodule, [], []})
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # Function with guard and body: def foo(x) when is_integer(x), do: x
  def extract({type, meta, [{:when, _, [{name, _, args}, guard]}, body_opts]} = node, opts)
      when type in @all_function_types and is_atom(name) do
    extract_clause(type, meta, name, args, guard, body_opts, node, opts)
  end

  # Function without guard: def foo(x), do: x
  def extract({type, meta, [{name, _, args}, body_opts]} = node, opts)
      when type in @all_function_types and is_atom(name) do
    extract_clause(type, meta, name, args, nil, body_opts, node, opts)
  end

  # Bodyless function with guard: def foo(x) when is_atom(x)
  def extract({type, meta, [{:when, _, [{name, _, args}, guard]}]} = node, opts)
      when type in @all_function_types do
    extract_clause(type, meta, name, args, guard, nil, node, opts)
  end

  # Bodyless function: def foo(x)
  def extract({type, meta, [{name, _, args}]} = node, opts)
      when type in @all_function_types and is_atom(name) do
    extract_clause(type, meta, name, args, nil, nil, node, opts)
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a function clause", node)}
  end

  @doc """
  Extracts a function clause from an AST node, raising on error.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> result = ElixirOntologies.Extractors.Clause.extract!(ast)
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
  # Bulk Extraction and Grouping
  # ===========================================================================

  @doc """
  Extracts all function clauses from a module body.

  Returns a list of extracted clauses in the order they appear.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]},
      ...>   {:def, [], [{:bar, [], nil}, [do: :ok]]},
      ...>   {:@, [], [{:doc, [], ["docs"]}]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.Clause.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [:foo, :bar]
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(nil), do: []

  def extract_all({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.filter(&clause?/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {node, index} ->
      case extract(node, order: index) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement) do
    if clause?(statement) do
      case extract(statement) do
        {:ok, result} -> [result]
        {:error, _} -> []
      end
    else
      []
    end
  end

  @doc """
  Groups clauses by function name and arity.

  Returns a map where keys are `{name, arity}` tuples and values are lists of
  clauses in order.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 1]]},
      ...>   {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 2]]},
      ...>   {:def, [], [{:bar, [], nil}, [do: :ok]]}
      ...> ]}
      iex> clauses = ElixirOntologies.Extractors.Clause.extract_all(body)
      iex> groups = ElixirOntologies.Extractors.Clause.group_clauses(clauses)
      iex> Map.keys(groups) |> Enum.sort()
      [{:bar, 0}, {:foo, 1}]
      iex> length(groups[{:foo, 1}])
      2
  """
  @spec group_clauses([t()]) :: %{{atom(), non_neg_integer()} => [t()]}
  def group_clauses(clauses) when is_list(clauses) do
    clauses
    |> Enum.group_by(fn %{name: name, arity: arity} -> {name, arity} end)
    |> Enum.map(fn {key, group} ->
      ordered =
        group
        |> Enum.with_index(1)
        |> Enum.map(fn {clause, order} -> %{clause | order: order} end)

      {key, ordered}
    end)
    |> Map.new()
  end

  @doc """
  Assigns proper clause ordering to a list of clauses.

  ## Examples

      iex> clauses = [
      ...>   %ElixirOntologies.Extractors.Clause{name: :foo, arity: 1, order: 1, visibility: :public, head: %{parameters: [], guard: nil}, body: nil, metadata: %{}},
      ...>   %ElixirOntologies.Extractors.Clause{name: :foo, arity: 1, order: 1, visibility: :public, head: %{parameters: [], guard: nil}, body: nil, metadata: %{}}
      ...> ]
      iex> ordered = ElixirOntologies.Extractors.Clause.assign_order(clauses)
      iex> Enum.map(ordered, & &1.order)
      [1, 2]
  """
  @spec assign_order([t()]) :: [t()]
  def assign_order(clauses) when is_list(clauses) do
    clauses
    |> Enum.with_index(1)
    |> Enum.map(fn {clause, order} -> %{clause | order: order} end)
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns a clause identifier string.

  ## Examples

      iex> ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.clause_id(clause)
      "hello/1#1"
  """
  @spec clause_id(t()) :: String.t()
  def clause_id(%__MODULE__{name: name, arity: arity, order: order}) do
    "#{name}/#{arity}##{order}"
  end

  @doc """
  Returns true if the clause has a guard.

  ## Examples

      iex> ast = {:def, [], [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.has_guard?(clause)
      true

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.has_guard?(clause)
      false
  """
  @spec has_guard?(t()) :: boolean()
  def has_guard?(%__MODULE__{head: %{guard: guard}}), do: guard != nil
  def has_guard?(_), do: false

  @doc """
  Returns true if the clause is bodyless (typically protocol definitions).

  ## Examples

      iex> ast = {:def, [], [{:callback, [], [{:x, [], nil}]}]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.bodyless?(clause)
      true

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.bodyless?(clause)
      false
  """
  @spec bodyless?(t()) :: boolean()
  def bodyless?(%__MODULE__{body: nil}), do: true
  def bodyless?(%__MODULE__{metadata: %{bodyless: true}}), do: true
  def bodyless?(_), do: false

  @doc """
  Returns the number of parameters in the clause.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.Clause.extract(ast)
      iex> ElixirOntologies.Extractors.Clause.parameter_count(clause)
      2
  """
  @spec parameter_count(t()) :: non_neg_integer()
  def parameter_count(%__MODULE__{head: %{parameters: params}}) when is_list(params) do
    length(params)
  end

  def parameter_count(_), do: 0

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_clause(type, _meta, name, args, guard, body_opts, node, opts) do
    params = normalize_params(args)
    arity = length(params)
    visibility = if type in @public_functions, do: :public, else: :private
    order = Keyword.get(opts, :order, 1)
    location = Helpers.extract_location(node)
    body = extract_body(body_opts)

    {:ok,
     %__MODULE__{
       name: name,
       arity: arity,
       visibility: visibility,
       order: order,
       head: %{
         parameters: params,
         guard: guard
       },
       body: body,
       location: location,
       metadata: %{
         function_type: type,
         has_guard: guard != nil,
         bodyless: body == nil
       }
     }}
  end

  defp normalize_params(nil), do: []
  defp normalize_params(args) when is_list(args), do: args
  defp normalize_params(_), do: []

  defp extract_body(nil), do: nil
  defp extract_body(do: body), do: body
  defp extract_body([{:do, body} | _rest]), do: body
  defp extract_body(body_opts) when is_list(body_opts), do: Keyword.get(body_opts, :do)
  defp extract_body(_), do: nil
end
