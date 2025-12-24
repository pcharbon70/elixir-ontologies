defmodule ElixirOntologies.Extractors.AnonymousFunction do
  @moduledoc """
  Extracts anonymous function definitions from Elixir AST.

  This module provides extraction of anonymous functions defined with `fn -> end`
  syntax, including support for multi-clause anonymous functions with pattern
  matching and guards.

  ## Ontology Alignment

  Extracted data maps to `struct:AnonymousFunction` class with properties:
  - `struct:arity` - Number of parameters
  - `core:hasClause` - Links to clause resources via `rdf:List`

  See `priv/ontologies/elixir-structure.ttl` for class definitions.

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
  alias ElixirOntologies.Extractors.Pattern

  # Clause ordering starts at 1 (1-indexed) to match Elixir's pattern matching semantics
  @clause_start_index 1

  # ===========================================================================
  # Clause Struct
  # ===========================================================================

  defmodule Clause do
    @moduledoc """
    Represents a clause in an anonymous function.

    ## Fields

    - `:parameters` - List of parameter pattern AST nodes
    - `:guard` - Guard expression AST or nil
    - `:body` - The clause body AST
    - `:order` - 1-indexed clause order (nil for standalone extraction)
    - `:arity` - Number of parameters in this clause
    - `:parameter_patterns` - List of Pattern.t() for each parameter (optional)
    - `:bound_variables` - All variables bound by parameters
    - `:location` - Source location if available
    - `:metadata` - Additional clause metadata
    """

    alias ElixirOntologies.Extractors.Pattern

    @type t :: %__MODULE__{
            parameters: [Macro.t()],
            guard: Macro.t() | nil,
            body: Macro.t(),
            order: pos_integer() | nil,
            arity: non_neg_integer(),
            parameter_patterns: [Pattern.t()] | nil,
            bound_variables: [atom()],
            location: map() | nil,
            metadata: map()
          }

    @enforce_keys [:parameters, :body, :arity]
    defstruct [
      :parameters,
      :guard,
      :body,
      :order,
      :arity,
      parameter_patterns: nil,
      bound_variables: [],
      location: nil,
      metadata: %{}
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

  @doc """
  Checks if an AST node represents an anonymous function clause.

  Anonymous function clauses use the `{:->, meta, [params, body]}` AST form.

  ## Examples

      iex> ElixirOntologies.Extractors.AnonymousFunction.clause_ast?({:->, [], [[{:x, [], nil}], :ok]})
      true

      iex> ElixirOntologies.Extractors.AnonymousFunction.clause_ast?({:fn, [], []})
      false

      iex> ElixirOntologies.Extractors.AnonymousFunction.clause_ast?(:not_ast)
      false
  """
  @spec clause_ast?(Macro.t()) :: boolean()
  def clause_ast?({:->, _meta, [params, _body]}) when is_list(params), do: true
  def clause_ast?(_), do: false

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
      |> Enum.with_index(@clause_start_index)
      |> Enum.map(fn {clause_ast, order} -> do_extract_clause(clause_ast, order) end)

    case validate_and_calculate_arity(extracted_clauses) do
      {:ok, arity} ->
        location = Helpers.extract_location(node)

        {:ok,
         %__MODULE__{
           clauses: extracted_clauses,
           arity: arity,
           location: location,
           metadata: %{}
         }}

      {:error, reason} ->
        {:error, reason}
    end
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
  # Clause Extraction
  # ===========================================================================

  @doc """
  Extracts an individual clause from a `{:->, meta, [params, body]}` AST node.

  This function provides standalone clause extraction with detailed pattern
  analysis for parameters. The order is set to nil for standalone extraction.

  ## Options

  - `:include_patterns` - Whether to extract Pattern.t() for each parameter (default: true)

  ## Examples

      iex> ast = {:->, [], [[{:x, [], nil}], {:x, [], nil}]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.AnonymousFunction.extract_clause(ast)
      iex> clause.arity
      1
      iex> clause.order
      nil

      iex> ElixirOntologies.Extractors.AnonymousFunction.extract_clause({:def, [], []})
      {:error, :not_clause}
  """
  @spec extract_clause(Macro.t(), keyword()) :: {:ok, Clause.t()} | {:error, atom()}
  def extract_clause(ast, opts \\ [])

  def extract_clause({:->, _meta, [params_with_guard, body]} = node, opts) do
    {parameters, guard} = Helpers.extract_params_and_guard(params_with_guard)
    location = Helpers.extract_location(node)
    arity = length(parameters)
    include_patterns = Keyword.get(opts, :include_patterns, true)

    {parameter_patterns, bound_variables} =
      if include_patterns do
        extract_parameter_patterns(parameters)
      else
        {nil, []}
      end

    {:ok,
     %Clause{
       parameters: parameters,
       guard: guard,
       body: body,
       order: nil,
       arity: arity,
       parameter_patterns: parameter_patterns,
       bound_variables: bound_variables,
       location: location,
       metadata: %{}
     }}
  end

  def extract_clause(_, _opts), do: {:error, :not_clause}

  @doc """
  Extracts a clause with an explicit order value.

  Used when extracting clauses as part of a multi-clause anonymous function
  where order matters for pattern matching semantics.

  ## Examples

      iex> ast = {:->, [], [[0], :zero]}
      iex> {:ok, clause} = ElixirOntologies.Extractors.AnonymousFunction.extract_clause_with_order(ast, 1)
      iex> clause.order
      1
  """
  @spec extract_clause_with_order(Macro.t(), pos_integer(), keyword()) ::
          {:ok, Clause.t()} | {:error, atom()}
  def extract_clause_with_order(ast, order, opts \\ [])

  def extract_clause_with_order({:->, _meta, [params_with_guard, body]} = node, order, opts)
      when is_integer(order) and order > 0 do
    {parameters, guard} = Helpers.extract_params_and_guard(params_with_guard)
    location = Helpers.extract_location(node)
    arity = length(parameters)
    include_patterns = Keyword.get(opts, :include_patterns, true)

    {parameter_patterns, bound_variables} =
      if include_patterns do
        extract_parameter_patterns(parameters)
      else
        {nil, []}
      end

    {:ok,
     %Clause{
       parameters: parameters,
       guard: guard,
       body: body,
       order: order,
       arity: arity,
       parameter_patterns: parameter_patterns,
       bound_variables: bound_variables,
       location: location,
       metadata: %{}
     }}
  end

  def extract_clause_with_order(_, _, _opts), do: {:error, :not_clause}

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Internal clause extraction used by extract/1 for whole function extraction
  # Includes pattern analysis by default for consistency
  defp do_extract_clause({:->, _meta, [params_with_guard, body]} = node, order) do
    {parameters, guard} = Helpers.extract_params_and_guard(params_with_guard)
    location = Helpers.extract_location(node)
    arity = length(parameters)
    {parameter_patterns, bound_variables} = extract_parameter_patterns(parameters)

    %Clause{
      parameters: parameters,
      guard: guard,
      body: body,
      order: order,
      arity: arity,
      parameter_patterns: parameter_patterns,
      bound_variables: bound_variables,
      location: location,
      metadata: %{}
    }
  end

  # Handle malformed clause AST gracefully with warning
  defp do_extract_clause(invalid, order) do
    require Logger

    Logger.warning(
      "Malformed anonymous function clause at position #{order}: #{inspect(invalid, limit: 50)}"
    )

    %Clause{
      parameters: [],
      guard: nil,
      body: nil,
      order: order,
      arity: 0,
      parameter_patterns: nil,
      bound_variables: [],
      location: nil,
      metadata: %{malformed: true, original_ast: invalid}
    }
  end

  # Validates that all clauses have consistent arity and returns the arity
  defp validate_and_calculate_arity([]), do: {:ok, 0}

  defp validate_and_calculate_arity([first_clause | rest]) do
    expected_arity = first_clause.arity

    inconsistent =
      Enum.find(rest, fn clause ->
        clause.arity != expected_arity
      end)

    case inconsistent do
      nil ->
        {:ok, expected_arity}

      _clause ->
        {:error, :inconsistent_clause_arity}
    end
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

  # Extract Pattern.t() for each parameter and collect all bound variables
  defp extract_parameter_patterns(parameters) do
    patterns =
      Enum.map(parameters, fn param ->
        case Pattern.extract(param) do
          {:ok, pattern} -> pattern
          _ -> nil
        end
      end)

    bound_variables =
      patterns
      |> Enum.flat_map(fn
        %Pattern{bindings: bindings} -> bindings
        nil -> []
      end)
      |> Enum.uniq()

    {patterns, bound_variables}
  end
end
