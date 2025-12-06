defmodule ElixirOntologies.Extractors.Block do
  @moduledoc """
  Extracts block structures from AST nodes.

  This module analyzes Elixir AST nodes representing block structures and
  extracts their contained expressions with ordering information. Supports
  two main block types:

  - Block (`__block__`): Sequence of expressions where the last is the return value
  - Anonymous Function (`fn`): Function with one or more clauses

  ## Expression Ordering

  Expressions within a block are extracted with their position (0-based index).
  The last expression in a block is marked as the return value.

  ## Usage

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:__block__, [], [{:=, [], [{:x, [], nil}, 1]}, {:x, [], nil}]}
      iex> {:ok, result} = Block.extract(ast)
      iex> result.type
      :block
      iex> length(result.expressions)
      2

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}
      iex> {:ok, result} = Block.extract(ast)
      iex> result.type
      :fn
      iex> length(result.clauses)
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  @typedoc """
  The result of block extraction.

  - `:type` - Either `:block` or `:fn`
  - `:expressions` - List of indexed expressions (for blocks)
  - `:clauses` - List of function clauses (for fn)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: :block | :fn,
          expressions: [indexed_expression()] | nil,
          clauses: [fn_clause()] | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @typedoc """
  An expression with its position in the block.

  - `:index` - 0-based position in the block
  - `:expression` - The AST of the expression
  - `:is_last` - True if this is the last (return) expression
  """
  @type indexed_expression :: %{
          index: non_neg_integer(),
          expression: Macro.t(),
          is_last: boolean()
        }

  @typedoc """
  A clause in an anonymous function.

  - `:patterns` - Parameter patterns for this clause
  - `:guard` - Optional guard expression
  - `:body` - The clause body
  """
  @type fn_clause :: %{
          patterns: [Macro.t()],
          guard: Macro.t() | nil,
          body: Macro.t()
        }

  defstruct [:type, expressions: nil, clauses: nil, location: nil, metadata: %{}]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a block expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Block.block?({:__block__, [], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Block.block?({:fn, [], [{:->, [], [[], 1]}]})
      false

      iex> ElixirOntologies.Extractors.Block.block?(:atom)
      false
  """
  @spec block?(Macro.t()) :: boolean()
  def block?({:__block__, _meta, exprs}) when is_list(exprs), do: true
  def block?(_), do: false

  @doc """
  Checks if an AST node represents an anonymous function.

  ## Examples

      iex> ElixirOntologies.Extractors.Block.anonymous_function?({:fn, [], [{:->, [], [[], 1]}]})
      true

      iex> ElixirOntologies.Extractors.Block.anonymous_function?({:__block__, [], [1]})
      false

      iex> ElixirOntologies.Extractors.Block.anonymous_function?(:atom)
      false
  """
  @spec anonymous_function?(Macro.t()) :: boolean()
  def anonymous_function?({:fn, _meta, clauses}) when is_list(clauses), do: true
  def anonymous_function?(_), do: false

  @doc """
  Checks if an AST node is either a block or anonymous function.

  ## Examples

      iex> ElixirOntologies.Extractors.Block.extractable?({:__block__, [], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Block.extractable?({:fn, [], [{:->, [], [[], 1]}]})
      true

      iex> ElixirOntologies.Extractors.Block.extractable?({:if, [], [true, [do: 1]]})
      false
  """
  @spec extractable?(Macro.t()) :: boolean()
  def extractable?(node), do: block?(node) or anonymous_function?(node)

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a block or anonymous function from an AST node.

  Returns `{:ok, %Block{}}` on success, or `{:error, reason}` if the node
  is not a block or anonymous function.

  ## Examples

      iex> ast = {:__block__, [], [{:=, [], [{:x, [], nil}, 1]}, {:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Block.extract(ast)
      iex> result.type
      :block
      iex> length(result.expressions)
      2
      iex> hd(result.expressions).index
      0

      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:*, [], [{:x, [], nil}, 2]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Block.extract(ast)
      iex> result.type
      :fn
      iex> result.metadata.clause_count
      1

      iex> {:error, _} = ElixirOntologies.Extractors.Block.extract({:if, [], [true]})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract({:__block__, _meta, exprs} = node) when is_list(exprs) do
    {:ok, extract_block(node)}
  end

  def extract({:fn, _meta, clauses} = node) when is_list(clauses) do
    {:ok, extract_fn(node)}
  end

  def extract(node) do
    {:error, Helpers.format_error("Not a block or anonymous function", node)}
  end

  @doc """
  Extracts a block or anonymous function, raising on error.

  ## Examples

      iex> ast = {:__block__, [], [1, 2, 3]}
      iex> result = ElixirOntologies.Extractors.Block.extract!(ast)
      iex> result.type
      :block
  """
  @spec extract!(Macro.t()) :: t()
  def extract!(node) do
    case extract(node) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Block Extraction
  # ===========================================================================

  @doc """
  Extracts a block expression.

  ## Examples

      iex> ast = {:__block__, [], [{:=, [], [{:x, [], nil}, 1]}, {:x, [], nil}]}
      iex> result = ElixirOntologies.Extractors.Block.extract_block(ast)
      iex> result.type
      :block
      iex> length(result.expressions)
      2
      iex> List.last(result.expressions).is_last
      true
  """
  @spec extract_block(Macro.t()) :: t()
  def extract_block({:__block__, _meta, exprs} = node) when is_list(exprs) do
    indexed = index_expressions(exprs)

    %__MODULE__{
      type: :block,
      expressions: indexed,
      clauses: nil,
      location: Helpers.extract_location(node),
      metadata: %{
        expression_count: length(exprs),
        has_return_value: length(exprs) > 0
      }
    }
  end

  # ===========================================================================
  # Anonymous Function Extraction
  # ===========================================================================

  @doc """
  Extracts an anonymous function.

  ## Examples

      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}
      iex> result = ElixirOntologies.Extractors.Block.extract_fn(ast)
      iex> result.type
      :fn
      iex> result.metadata.arity
      1
  """
  @spec extract_fn(Macro.t()) :: t()
  def extract_fn({:fn, _meta, clauses} = node) when is_list(clauses) do
    extracted_clauses = Enum.map(clauses, &extract_fn_clause/1)
    arity = determine_arity(extracted_clauses)

    %__MODULE__{
      type: :fn,
      expressions: nil,
      clauses: extracted_clauses,
      location: Helpers.extract_location(node),
      metadata: %{
        clause_count: length(clauses),
        arity: arity
      }
    }
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the expressions from a block in order.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:__block__, [], [1, 2, 3]}
      iex> {:ok, block} = Block.extract(ast)
      iex> Block.expressions_in_order(block)
      [1, 2, 3]
  """
  @spec expressions_in_order(t()) :: [Macro.t()]
  def expressions_in_order(%__MODULE__{type: :block, expressions: exprs}) when is_list(exprs) do
    exprs
    |> Enum.sort_by(& &1.index)
    |> Enum.map(& &1.expression)
  end

  def expressions_in_order(_), do: []

  @doc """
  Returns the last (return) expression from a block.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:__block__, [], [1, 2, 3]}
      iex> {:ok, block} = Block.extract(ast)
      iex> Block.return_expression(block)
      3
  """
  @spec return_expression(t()) :: Macro.t() | nil
  def return_expression(%__MODULE__{type: :block, expressions: exprs}) when is_list(exprs) do
    case Enum.find(exprs, & &1.is_last) do
      nil -> nil
      indexed -> indexed.expression
    end
  end

  def return_expression(_), do: nil

  @doc """
  Returns the arity of an anonymous function.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:fn, [], [{:->, [], [[{:x, [], nil}, {:y, [], nil}], 1]}]}
      iex> {:ok, fn_block} = Block.extract(ast)
      iex> Block.arity(fn_block)
      2
  """
  @spec arity(t()) :: non_neg_integer() | :variable | nil
  def arity(%__MODULE__{type: :fn, metadata: %{arity: arity}}), do: arity
  def arity(_), do: nil

  @doc """
  Returns true if the anonymous function has multiple clauses.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Block
      iex> ast = {:fn, [], [{:->, [], [[0], :zero]}, {:->, [], [[{:n, [], nil}], {:n, [], nil}]}]}
      iex> {:ok, fn_block} = Block.extract(ast)
      iex> Block.multi_clause?(fn_block)
      true
  """
  @spec multi_clause?(t()) :: boolean()
  def multi_clause?(%__MODULE__{type: :fn, clauses: clauses}) when is_list(clauses) do
    length(clauses) > 1
  end

  def multi_clause?(_), do: false

  @doc """
  Returns true if any clause in the anonymous function has a guard.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Block
      iex> clause = {:->, [], [[{:when, [], [{:x, [], nil}, {:>, [], [{:x, [], nil}, 0]}]}], :pos]}
      iex> ast = {:fn, [], [clause]}
      iex> {:ok, fn_block} = Block.extract(ast)
      iex> Block.has_guards?(fn_block)
      true
  """
  @spec has_guards?(t()) :: boolean()
  def has_guards?(%__MODULE__{type: :fn, clauses: clauses}) when is_list(clauses) do
    Enum.any?(clauses, fn clause -> clause.guard != nil end)
  end

  def has_guards?(_), do: false

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Index expressions with their position
  defp index_expressions(exprs) do
    count = length(exprs)

    exprs
    |> Enum.with_index()
    |> Enum.map(fn {expr, idx} ->
      %{
        index: idx,
        expression: expr,
        is_last: idx == count - 1
      }
    end)
  end

  # Extract a single fn clause
  defp extract_fn_clause({:->, _meta, [params, body]}) do
    {patterns, guard} = extract_patterns_and_guard(params)

    %{
      patterns: patterns,
      guard: guard,
      body: body
    }
  end

  # Handle fallback for malformed clauses
  defp extract_fn_clause(other) do
    %{
      patterns: [],
      guard: nil,
      body: other
    }
  end

  # Extract patterns and guard from fn parameters
  defp extract_patterns_and_guard(params) when is_list(params) do
    case params do
      # Single parameter with guard: [{:when, [], [pattern, guard]}]
      [{:when, _meta, when_args}] ->
        case when_args do
          [pattern | guard_parts] when guard_parts != [] ->
            guard = Helpers.combine_guards(guard_parts)
            {[pattern], guard}

          _ ->
            {params, nil}
        end

      # Multiple parameters, last might be a when clause
      _ ->
        case List.last(params) do
          {:when, _meta, when_args} ->
            # The when clause contains the last pattern and guards
            patterns = Enum.drop(params, -1)
            [last_pattern | guard_parts] = when_args
            guard = Helpers.combine_guards(guard_parts)
            {patterns ++ [last_pattern], guard}

          _ ->
            {params, nil}
        end
    end
  end

  defp extract_patterns_and_guard(other), do: {[other], nil}

  # Determine the arity of a function from its clauses
  defp determine_arity([]), do: 0

  defp determine_arity(clauses) do
    arities =
      clauses
      |> Enum.map(fn clause -> length(clause.patterns) end)
      |> Enum.uniq()

    case arities do
      [single_arity] -> single_arity
      _ -> :variable
    end
  end
end
