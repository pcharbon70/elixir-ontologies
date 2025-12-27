defmodule ElixirOntologies.Extractors.Conditional do
  @moduledoc """
  Extracts conditional expressions from Elixir AST.

  This module provides extraction of conditional expressions including:
  - **if** - conditional with optional else branch
  - **unless** - negated conditional with optional else branch
  - **cond** - multi-clause conditional

  ## Conditional Types

  ### If Expressions

  If expressions have a condition and one or two branches:

      if condition do
        then_body
      else
        else_body
      end

  ### Unless Expressions

  Unless expressions are semantically `if not condition`:

      unless condition do
        body
      else
        fallback
      end

  ### Cond Expressions

  Cond expressions have multiple condition-body clauses:

      cond do
        condition1 -> body1
        condition2 -> body2
        true -> default
      end

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :then, else: :else]]}
      iex> ElixirOntologies.Extractors.Conditional.conditional?(ast)
      true

      iex> ast = {:if, [], [{:x, [], nil}, [do: :then, else: :else]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_conditional(ast)
      iex> cond.type
      :if
      iex> length(cond.branches)
      2
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definitions
  # ===========================================================================

  defmodule Branch do
    @moduledoc """
    Represents a branch in an if/unless expression.

    ## Fields

    - `:type` - Branch type (:then or :else)
    - `:body` - The branch body AST
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            type: :then | :else,
            body: Macro.t(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:type, :body]
    defstruct [:type, :body, :location]
  end

  defmodule CondClause do
    @moduledoc """
    Represents a clause in a cond expression.

    ## Fields

    - `:index` - 0-based position in the cond
    - `:condition` - The condition expression
    - `:body` - The clause body
    - `:is_catch_all` - True if condition is literal `true`
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            condition: Macro.t(),
            body: Macro.t(),
            is_catch_all: boolean(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:index, :condition, :body]
    defstruct [:index, :condition, :body, is_catch_all: false, location: nil]
  end

  defmodule Conditional do
    @moduledoc """
    Represents a conditional expression extracted from AST.

    ## Fields

    - `:type` - The conditional type (:if, :unless, or :cond)
    - `:condition` - The main condition (for if/unless, nil for cond)
    - `:branches` - List of Branch structs (for if/unless)
    - `:clauses` - List of CondClause structs (for cond)
    - `:location` - Source location if available
    - `:metadata` - Additional information
    """

    @type conditional_type :: :if | :unless | :cond

    @type t :: %__MODULE__{
            type: conditional_type(),
            condition: Macro.t() | nil,
            branches: [ElixirOntologies.Extractors.Conditional.Branch.t()],
            clauses: [ElixirOntologies.Extractors.Conditional.CondClause.t()],
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:type]
    defstruct [:type, :condition, :location, branches: [], clauses: [], metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a conditional expression.

  Returns `true` for if, unless, and cond expressions.

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.conditional?(ast)
      true

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.conditional?(ast)
      true

      iex> ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      iex> ElixirOntologies.Extractors.Conditional.conditional?(ast)
      true

      iex> ast = {:case, [], [{:x, [], nil}, [do: []]]}
      iex> ElixirOntologies.Extractors.Conditional.conditional?(ast)
      false
  """
  @spec conditional?(Macro.t()) :: boolean()
  def conditional?(ast) do
    if_expression?(ast) or unless_expression?(ast) or cond_expression?(ast)
  end

  @doc """
  Checks if the given AST node represents an if expression.

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.if_expression?(ast)
      true

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.if_expression?(ast)
      false
  """
  @spec if_expression?(Macro.t()) :: boolean()
  def if_expression?({:if, _meta, [_condition, opts]}) when is_list(opts), do: true
  def if_expression?(_), do: false

  @doc """
  Checks if the given AST node represents an unless expression.

  ## Examples

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.unless_expression?(ast)
      true

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.Conditional.unless_expression?(ast)
      false
  """
  @spec unless_expression?(Macro.t()) :: boolean()
  def unless_expression?({:unless, _meta, [_condition, opts]}) when is_list(opts), do: true
  def unless_expression?(_), do: false

  @doc """
  Checks if the given AST node represents a cond expression.

  ## Examples

      iex> ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      iex> ElixirOntologies.Extractors.Conditional.cond_expression?(ast)
      true

      iex> ast = {:case, [], [{:x, [], nil}, [do: []]]}
      iex> ElixirOntologies.Extractors.Conditional.cond_expression?(ast)
      false
  """
  @spec cond_expression?(Macro.t()) :: boolean()
  def cond_expression?({:cond, _meta, [opts]}) when is_list(opts), do: true
  def cond_expression?(_), do: false

  # ===========================================================================
  # Single Extraction
  # ===========================================================================

  @doc """
  Extracts a conditional expression from an AST node.

  Returns `{:ok, %Conditional{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :then, else: :else]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_conditional(ast)
      iex> cond.type
      :if
      iex> cond.condition
      {:x, [], nil}
      iex> length(cond.branches)
      2

      iex> ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_conditional(ast)
      iex> cond.type
      :cond
      iex> length(cond.clauses)
      1

      iex> ast = {:foo, [], []}
      iex> ElixirOntologies.Extractors.Conditional.extract_conditional(ast)
      {:error, {:not_a_conditional, "Not a conditional expression: {:foo, [], []}"}}
  """
  @spec extract_conditional(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
  def extract_conditional(ast, opts \\ [])

  def extract_conditional({:if, _meta, [_condition, _opts]} = ast, opts) do
    extract_if(ast, opts)
  end

  def extract_conditional({:unless, _meta, [_condition, _opts]} = ast, opts) do
    extract_unless(ast, opts)
  end

  def extract_conditional({:cond, _meta, [_opts]} = ast, opts) do
    extract_cond(ast, opts)
  end

  def extract_conditional(ast, _opts) do
    {:error, {:not_a_conditional, Helpers.format_error("Not a conditional expression", ast)}}
  end

  @doc """
  Extracts a conditional expression, raising on error.

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> cond = ElixirOntologies.Extractors.Conditional.extract_conditional!(ast)
      iex> cond.type
      :if
  """
  @spec extract_conditional!(Macro.t(), keyword()) :: Conditional.t()
  def extract_conditional!(ast, opts \\ []) do
    case extract_conditional(ast, opts) do
      {:ok, cond} -> cond
      {:error, reason} -> raise ArgumentError, "Failed to extract conditional: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Type-Specific Extraction
  # ===========================================================================

  @doc """
  Extracts an if expression.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:if, [], [{:>, [], [{:x, [], nil}, 0]}, [do: :positive, else: :negative]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_if(ast)
      iex> cond.type
      :if
      iex> cond.metadata.has_else
      true
      iex> length(cond.branches)
      2

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_if(ast)
      iex> cond.metadata.has_else
      false
      iex> length(cond.branches)
      1
  """
  @spec extract_if(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
  def extract_if(ast, extract_opts \\ [])

  def extract_if({:if, _meta, [condition, opts]} = ast, extract_opts) do
    then_body = Keyword.get(opts, :do)
    else_body = Keyword.get(opts, :else)
    location = Helpers.extract_location_if(ast, extract_opts)

    branches = build_branches(then_body, else_body)

    {:ok,
     %Conditional{
       type: :if,
       condition: condition,
       branches: branches,
       clauses: [],
       location: location,
       metadata: %{
         has_else: else_body != nil,
         branch_count: length(branches)
       }
     }}
  end

  def extract_if(ast, _opts) do
    {:error, {:not_an_if, Helpers.format_error("Not an if expression", ast)}}
  end

  @doc """
  Extracts an unless expression.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :body, else: :fallback]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_unless(ast)
      iex> cond.type
      :unless
      iex> cond.metadata.has_else
      true

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :body]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_unless(ast)
      iex> cond.metadata.has_else
      false
  """
  @spec extract_unless(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
  def extract_unless(ast, extract_opts \\ [])

  def extract_unless({:unless, _meta, [condition, opts]} = ast, extract_opts) do
    then_body = Keyword.get(opts, :do)
    else_body = Keyword.get(opts, :else)
    location = Helpers.extract_location_if(ast, extract_opts)

    branches = build_branches(then_body, else_body)

    {:ok,
     %Conditional{
       type: :unless,
       condition: condition,
       branches: branches,
       clauses: [],
       location: location,
       metadata: %{
         has_else: else_body != nil,
         branch_count: length(branches),
         semantics: :negated_condition
       }
     }}
  end

  def extract_unless(ast, _opts) do
    {:error, {:not_an_unless, Helpers.format_error("Not an unless expression", ast)}}
  end

  @doc """
  Extracts a cond expression.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> clauses = [
      ...>   {:->, [], [[{:>, [], [{:x, [], nil}, 0]}], :positive]},
      ...>   {:->, [], [[{:<, [], [{:x, [], nil}, 0]}], :negative]},
      ...>   {:->, [], [[true], :zero]}
      ...> ]
      iex> ast = {:cond, [], [[do: clauses]]}
      iex> {:ok, cond} = ElixirOntologies.Extractors.Conditional.extract_cond(ast)
      iex> cond.type
      :cond
      iex> length(cond.clauses)
      3
      iex> Enum.at(cond.clauses, 2).is_catch_all
      true
  """
  @spec extract_cond(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
  def extract_cond(ast, extract_opts \\ [])

  def extract_cond({:cond, _meta, [opts]} = ast, extract_opts) do
    do_clauses = Keyword.get(opts, :do, [])
    location = Helpers.extract_location_if(ast, extract_opts)

    clauses = build_cond_clauses(do_clauses, extract_opts)
    catch_all_count = Enum.count(clauses, & &1.is_catch_all)

    {:ok,
     %Conditional{
       type: :cond,
       condition: nil,
       branches: [],
       clauses: clauses,
       location: location,
       metadata: %{
         clause_count: length(clauses),
         has_catch_all: catch_all_count > 0,
         catch_all_count: catch_all_count
       }
     }}
  end

  def extract_cond(ast, _opts) do
    {:error, {:not_a_cond, Helpers.format_error("Not a cond expression", ast)}}
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all conditional expressions from an AST.

  Walks the entire AST tree and extracts all if, unless, and cond expressions.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:if, [], [{:x, [], nil}, [do: :ok]]},
      ...>   {:foo, [], []},
      ...>   {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      ...> ]
      iex> conds = ElixirOntologies.Extractors.Conditional.extract_conditionals(body)
      iex> length(conds)
      2

      iex> ast = {:def, [], [{:run, [], nil}, [do: {:if, [], [{:x, [], nil}, [do: :ok]]}]]}
      iex> conds = ElixirOntologies.Extractors.Conditional.extract_conditionals(ast)
      iex> length(conds)
      1
  """
  @spec extract_conditionals(Macro.t(), keyword()) :: [Conditional.t()]
  def extract_conditionals(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_conditionals_recursive(ast, opts, 0, max_depth)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_branches(then_body, else_body) do
    branches = [%Branch{type: :then, body: then_body}]

    if else_body != nil do
      branches ++ [%Branch{type: :else, body: else_body}]
    else
      branches
    end
  end

  defp build_cond_clauses(clauses, opts) when is_list(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.map(fn {clause_ast, index} ->
      build_cond_clause(clause_ast, index, opts)
    end)
  end

  defp build_cond_clause({:->, _meta, [[condition], body]} = ast, index, opts) do
    location = Helpers.extract_location_if(ast, opts)
    is_catch_all = catch_all_condition?(condition)

    %CondClause{
      index: index,
      condition: condition,
      body: body,
      is_catch_all: is_catch_all,
      location: location
    }
  end

  defp build_cond_clause(malformed, index, _opts) do
    %CondClause{
      index: index,
      condition: malformed,
      body: nil,
      is_catch_all: false,
      location: nil
    }
  end

  # Detect catch-all conditions (true is the standard catch-all in cond)
  defp catch_all_condition?(true), do: true
  defp catch_all_condition?(_), do: false

  # ===========================================================================
  # Recursive Extraction
  # ===========================================================================

  defp extract_conditionals_recursive(_ast, _opts, depth, max_depth) when depth > max_depth do
    []
  end

  defp extract_conditionals_recursive(statements, opts, depth, max_depth)
       when is_list(statements) do
    Enum.flat_map(statements, &extract_conditionals_recursive(&1, opts, depth, max_depth))
  end

  defp extract_conditionals_recursive({:__block__, _meta, statements}, opts, depth, max_depth) do
    extract_conditionals_recursive(statements, opts, depth, max_depth)
  end

  # Handle if expression
  defp extract_conditionals_recursive(
         {:if, _meta, [_condition, body_opts]} = ast,
         opts,
         depth,
         max_depth
       ) do
    case extract_if(ast, opts) do
      {:ok, cond} ->
        # Also extract from branches
        nested = extract_from_branches(body_opts, opts, depth + 1, max_depth)
        [cond | nested]

      {:error, _} ->
        []
    end
  end

  # Handle unless expression
  defp extract_conditionals_recursive(
         {:unless, _meta, [_condition, body_opts]} = ast,
         opts,
         depth,
         max_depth
       ) do
    case extract_unless(ast, opts) do
      {:ok, cond} ->
        nested = extract_from_branches(body_opts, opts, depth + 1, max_depth)
        [cond | nested]

      {:error, _} ->
        []
    end
  end

  # Handle cond expression
  defp extract_conditionals_recursive({:cond, _meta, [body_opts]} = ast, opts, depth, max_depth) do
    case extract_cond(ast, opts) do
      {:ok, cond} ->
        # Extract from clause bodies
        do_clauses = Keyword.get(body_opts, :do, [])
        nested = extract_from_cond_clauses(do_clauses, opts, depth + 1, max_depth)
        [cond | nested]

      {:error, _} ->
        []
    end
  end

  # Handle other AST nodes - recurse into args
  defp extract_conditionals_recursive({_name, _meta, args}, opts, depth, max_depth)
       when is_list(args) do
    extract_conditionals_recursive(args, opts, depth + 1, max_depth)
  end

  # Handle two-element tuples
  defp extract_conditionals_recursive({left, right}, opts, depth, max_depth) do
    extract_conditionals_recursive(left, opts, depth + 1, max_depth) ++
      extract_conditionals_recursive(right, opts, depth + 1, max_depth)
  end

  # Handle three-element tuples that aren't AST nodes
  defp extract_conditionals_recursive({a, b, c}, opts, depth, max_depth)
       when not is_atom(a) or not is_list(b) do
    extract_conditionals_recursive(a, opts, depth + 1, max_depth) ++
      extract_conditionals_recursive(b, opts, depth + 1, max_depth) ++
      extract_conditionals_recursive(c, opts, depth + 1, max_depth)
  end

  defp extract_conditionals_recursive(_other, _opts, _depth, _max_depth) do
    []
  end

  # Extract conditionals from if/unless branches
  defp extract_from_branches(opts, extract_opts, depth, max_depth) when is_list(opts) do
    do_body = Keyword.get(opts, :do)
    else_body = Keyword.get(opts, :else)

    from_do = extract_conditionals_recursive(do_body, extract_opts, depth, max_depth)
    from_else = extract_conditionals_recursive(else_body, extract_opts, depth, max_depth)

    from_do ++ from_else
  end

  defp extract_from_branches(_, _opts, _depth, _max_depth), do: []

  # Extract conditionals from cond clause bodies
  defp extract_from_cond_clauses(clauses, opts, depth, max_depth) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _, [[_condition], body]} ->
        extract_conditionals_recursive(body, opts, depth, max_depth)

      _ ->
        []
    end)
  end
end
