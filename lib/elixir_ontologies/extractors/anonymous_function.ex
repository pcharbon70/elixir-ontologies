defmodule ElixirOntologies.Extractors.AnonymousFunction do
  @moduledoc """
  Extracts anonymous function definitions from Elixir AST.

  This module provides extraction of anonymous functions defined with `fn -> end`
  syntax, including support for multi-clause anonymous functions with pattern
  matching and guards.

  ## Anonymous Function Syntax

  ### Single-clause
  ```elixir
  fn x -> x + 1 end
  fn x, y -> x + y end
  ```

  ### Multi-clause with pattern matching
  ```elixir
  fn
    0 -> :zero
    n when n > 0 -> :positive
    _ -> :negative
  end
  ```

  ## Examples

      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}
      iex> ElixirOntologies.Extractors.AnonymousFunction.anonymous_function?(ast)
      true

      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> anon.arity
      1
      iex> length(anon.clauses)
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Clause Struct
  # ===========================================================================

  defmodule Clause do
    @moduledoc """
    Represents a clause in an anonymous function.

    ## Fields

    - `:parameters` - List of parameter patterns
    - `:guard` - Guard expression or nil
    - `:body` - The clause body AST
    - `:order` - 1-indexed clause order
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            parameters: [Macro.t()],
            guard: Macro.t() | nil,
            body: Macro.t(),
            order: pos_integer(),
            location: map() | nil
          }

    @enforce_keys [:parameters, :body, :order]
    defstruct [
      :parameters,
      :guard,
      :body,
      :order,
      location: nil
    ]
  end

  # ===========================================================================
  # Main Struct
  # ===========================================================================

  @typedoc """
  The result of anonymous function extraction.

  - `:clauses` - List of Clause structs
  - `:arity` - Number of parameters (from first clause)
  - `:location` - Source location if available
  - `:metadata` - Additional information (e.g., captured_vars for closures)
  """
  @type t :: %__MODULE__{
          clauses: [Clause.t()],
          arity: non_neg_integer(),
          location: map() | nil,
          metadata: map()
        }

  @enforce_keys [:clauses, :arity]
  defstruct [
    :clauses,
    :arity,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents an anonymous function.

  ## Examples

      iex> ElixirOntologies.Extractors.AnonymousFunction.anonymous_function?({:fn, [], [{:->, [], [[], :ok]}]})
      true

      iex> ElixirOntologies.Extractors.AnonymousFunction.anonymous_function?({:def, [], []})
      false

      iex> ElixirOntologies.Extractors.AnonymousFunction.anonymous_function?(:not_ast)
      false
  """
  @spec anonymous_function?(Macro.t()) :: boolean()
  def anonymous_function?({:fn, _meta, clauses}) when is_list(clauses), do: true
  def anonymous_function?(_), do: false

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts an anonymous function from an AST node.

  Returns `{:ok, %AnonymousFunction{}}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> anon.arity
      1
      iex> length(anon.clauses)
      1

      iex> ElixirOntologies.Extractors.AnonymousFunction.extract({:def, [], []})
      {:error, :not_anonymous_function}
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, atom()}
  def extract({:fn, _meta, clauses} = node) when is_list(clauses) do
    extracted_clauses =
      clauses
      |> Enum.with_index(1)
      |> Enum.map(fn {clause_ast, order} -> extract_clause(clause_ast, order) end)

    arity = calculate_arity(extracted_clauses)
    location = Helpers.extract_location(node)

    {:ok,
     %__MODULE__{
       clauses: extracted_clauses,
       arity: arity,
       location: location,
       metadata: %{}
     }}
  end

  def extract(_), do: {:error, :not_anonymous_function}

  @doc """
  Extracts all anonymous functions from an AST.

  Traverses the AST and extracts all anonymous function definitions found.

  ## Examples

      iex> ast = quote do
      ...>   fn x -> x end
      ...>   fn y -> y * 2 end
      ...> end
      iex> results = ElixirOntologies.Extractors.AnonymousFunction.extract_all(ast)
      iex> length(results)
      2
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(ast) do
    ast
    |> find_all_anonymous_functions()
    |> Enum.map(fn node ->
      {:ok, result} = extract(node)
      result
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_clause({:->, _meta, [params_with_guard, body]} = node, order) do
    {parameters, guard} = extract_params_and_guard(params_with_guard)
    location = Helpers.extract_location(node)

    %Clause{
      parameters: parameters,
      guard: guard,
      body: body,
      order: order,
      location: location
    }
  end

  # Handle malformed clause AST gracefully
  defp extract_clause(_invalid, order) do
    %Clause{
      parameters: [],
      guard: nil,
      body: nil,
      order: order,
      location: nil
    }
  end

  # Extract parameters and guard from the clause pattern list
  # Parameters can contain a {:when, _, [params..., guard]} wrapper for guards
  defp extract_params_and_guard(params) when is_list(params) do
    case params do
      # With guard: [{:when, _, [param1, param2, ..., guard_expr]}]
      # All params and guard are inside the when tuple, guard is last
      [{:when, _meta, when_contents}] when is_list(when_contents) ->
        # Guard is the last element, params are all others
        {parameters, [guard_expr]} = Enum.split(when_contents, -1)
        {parameters, guard_expr}

      # No guard - all are regular parameters
      params ->
        {params, nil}
    end
  end

  defp extract_params_and_guard(_), do: {[], nil}

  defp calculate_arity([]), do: 0

  defp calculate_arity([first_clause | _]) do
    length(first_clause.parameters)
  end

  defp find_all_anonymous_functions(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:fn, _meta, _clauses} = node, acc ->
          {node, [node | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end
end
