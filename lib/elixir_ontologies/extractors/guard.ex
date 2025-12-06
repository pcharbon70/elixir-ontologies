defmodule ElixirOntologies.Extractors.Guard do
  @moduledoc """
  Extracts guard clauses from function heads.

  This module analyzes Elixir guard expressions and extracts information
  about the guards including decomposition of combined guards (and/or),
  identification of guard functions, and metadata about guard types.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `GuardClause` - A guard expression on a function clause
  - `hasGuard` property linking function head to guard

  ## Usage

      iex> alias ElixirOntologies.Extractors.Guard
      iex> guard = {:is_integer, [], [{:x, [], nil}]}
      iex> {:ok, result} = Guard.extract(guard)
      iex> result.guard_functions
      [:is_integer]

      iex> alias ElixirOntologies.Extractors.Guard
      iex> guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      iex> {:ok, result} = Guard.extract(guard)
      iex> result.combinator
      :and
      iex> length(result.expressions)
      2
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of guard extraction.

  - `:expression` - The full guard AST expression
  - `:expressions` - List of individual guard expressions (decomposed)
  - `:combinator` - How guards are combined (:none, :and, :or, :mixed)
  - `:guard_functions` - List of guard functions used
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          expression: Macro.t(),
          expressions: [Macro.t()],
          combinator: :none | :and | :or | :mixed,
          guard_functions: [atom()],
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :expression,
    expressions: [],
    combinator: :none,
    guard_functions: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Guard Functions
  # ===========================================================================

  @type_check_guards [
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_exception,
    :is_float,
    :is_function,
    :is_integer,
    :is_list,
    :is_map,
    :is_map_key,
    :is_nil,
    :is_number,
    :is_pid,
    :is_port,
    :is_reference,
    :is_struct,
    :is_tuple
  ]

  @comparison_operators [:==, :!=, :===, :!==, :<, :>, :<=, :>=]

  @arithmetic_operators [:+, :-, :*, :/]

  @other_guards [
    :abs,
    :binary_part,
    :bit_size,
    :byte_size,
    :ceil,
    :div,
    :elem,
    :floor,
    :hd,
    :in,
    :length,
    :map_size,
    :node,
    :not,
    :rem,
    :round,
    :self,
    :tl,
    :trunc,
    :tuple_size
  ]

  @all_guard_functions @type_check_guards ++
                         @comparison_operators ++
                         @arithmetic_operators ++
                         @other_guards

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a guard expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Guard.guard?({:is_integer, [], [{:x, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Guard.guard?({:and, [], [{:is_atom, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]})
      true

      iex> ElixirOntologies.Extractors.Guard.guard?(nil)
      false
  """
  @spec guard?(Macro.t()) :: boolean()
  def guard?({:and, _, [_, _]}), do: true
  def guard?({:or, _, [_, _]}), do: true
  def guard?({name, _, args}) when is_atom(name) and is_list(args), do: true
  def guard?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a guard clause from an AST node.

  Returns `{:ok, %Guard{}}` on success, or `{:error, reason}` if the node
  cannot be processed as a guard.

  ## Examples

      iex> guard = {:is_integer, [], [{:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> result.combinator
      :none
      iex> result.guard_functions
      [:is_integer]

      iex> guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> result.combinator
      :and
      iex> :is_integer in result.guard_functions
      true

      iex> guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> result.combinator
      :or
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(guard, opts \\ [])

  def extract(nil, _opts) do
    {:error, "Cannot extract guard from nil"}
  end

  # Combined guard with `and`
  def extract({:and, meta, [left, right]} = expr, _opts) do
    left_exprs = decompose_guard(left)
    right_exprs = decompose_guard(right)
    all_exprs = left_exprs ++ right_exprs

    combinator = determine_combinator(expr)
    functions = extract_guard_functions(all_exprs)
    location = Helpers.extract_location({:and, meta, [left, right]})

    {:ok,
     %__MODULE__{
       expression: expr,
       expressions: all_exprs,
       combinator: combinator,
       guard_functions: functions,
       location: location,
       metadata: build_metadata(all_exprs, functions)
     }}
  end

  # Combined guard with `or`
  def extract({:or, meta, [left, right]} = expr, _opts) do
    left_exprs = decompose_guard(left)
    right_exprs = decompose_guard(right)
    all_exprs = left_exprs ++ right_exprs

    combinator = determine_combinator(expr)
    functions = extract_guard_functions(all_exprs)
    location = Helpers.extract_location({:or, meta, [left, right]})

    {:ok,
     %__MODULE__{
       expression: expr,
       expressions: all_exprs,
       combinator: combinator,
       guard_functions: functions,
       location: location,
       metadata: build_metadata(all_exprs, functions)
     }}
  end

  # Single guard expression
  def extract({name, meta, args} = expr, _opts) when is_atom(name) and is_list(args) do
    functions = extract_guard_functions([expr])
    location = Helpers.extract_location({name, meta, args})

    {:ok,
     %__MODULE__{
       expression: expr,
       expressions: [expr],
       combinator: :none,
       guard_functions: functions,
       location: location,
       metadata: build_metadata([expr], functions)
     }}
  end

  def extract(expr, _opts) do
    {:error, Helpers.format_error("Cannot extract guard", expr)}
  end

  @doc """
  Extracts a guard clause from an AST node, raising on error.

  ## Examples

      iex> guard = {:is_atom, [], [{:x, [], nil}]}
      iex> result = ElixirOntologies.Extractors.Guard.extract!(guard)
      iex> result.guard_functions
      [:is_atom]
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(guard, opts \\ []) do
    case extract(guard, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ===========================================================================
  # Extraction from Clause
  # ===========================================================================

  @doc """
  Extracts guard from a Clause struct.

  Returns `{:ok, %Guard{}}` if the clause has a guard, `{:ok, nil}` if no guard,
  or `{:error, reason}` on failure.

  ## Examples

      iex> alias ElixirOntologies.Extractors.{Guard, Clause}
      iex> ast = {:def, [], [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}
      iex> {:ok, clause} = Clause.extract(ast)
      iex> {:ok, guard} = Guard.extract_from_clause(clause)
      iex> guard.guard_functions
      [:is_atom]

      iex> alias ElixirOntologies.Extractors.{Guard, Clause}
      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, clause} = Clause.extract(ast)
      iex> Guard.extract_from_clause(clause)
      {:ok, nil}
  """
  @spec extract_from_clause(map()) :: {:ok, t() | nil} | {:error, String.t()}
  def extract_from_clause(%{head: %{guard: nil}}), do: {:ok, nil}

  def extract_from_clause(%{head: %{guard: guard}}) do
    extract(guard)
  end

  def extract_from_clause(_) do
    {:error, "Invalid clause structure"}
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the guard uses the `and` combinator.

  ## Examples

      iex> guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_and?(result)
      true

      iex> guard = {:is_integer, [], [{:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_and?(result)
      false
  """
  @spec has_and?(t()) :: boolean()
  def has_and?(%__MODULE__{combinator: :and}), do: true
  def has_and?(%__MODULE__{combinator: :mixed}), do: true
  def has_and?(_), do: false

  @doc """
  Returns true if the guard uses the `or` combinator.

  ## Examples

      iex> guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_or?(result)
      true
  """
  @spec has_or?(t()) :: boolean()
  def has_or?(%__MODULE__{combinator: :or}), do: true
  def has_or?(%__MODULE__{combinator: :mixed}), do: true
  def has_or?(_), do: false

  @doc """
  Returns true if the guard contains type check functions.

  ## Examples

      iex> guard = {:is_integer, [], [{:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_type_check?(result)
      true

      iex> guard = {:>, [], [{:x, [], nil}, 0]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_type_check?(result)
      false
  """
  @spec has_type_check?(t()) :: boolean()
  def has_type_check?(%__MODULE__{metadata: %{has_type_check: has}}), do: has
  def has_type_check?(_), do: false

  @doc """
  Returns true if the guard contains comparison operators.

  ## Examples

      iex> guard = {:>, [], [{:x, [], nil}, 0]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.has_comparison?(result)
      true
  """
  @spec has_comparison?(t()) :: boolean()
  def has_comparison?(%__MODULE__{metadata: %{has_comparison: has}}), do: has
  def has_comparison?(_), do: false

  @doc """
  Returns the number of individual guard expressions.

  ## Examples

      iex> guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Guard.extract(guard)
      iex> ElixirOntologies.Extractors.Guard.expression_count(result)
      2
  """
  @spec expression_count(t()) :: non_neg_integer()
  def expression_count(%__MODULE__{expressions: exprs}), do: length(exprs)
  def expression_count(_), do: 0

  @doc """
  Returns the list of known guard functions.

  ## Examples

      iex> :is_integer in ElixirOntologies.Extractors.Guard.known_guard_functions()
      true

      iex> :> in ElixirOntologies.Extractors.Guard.known_guard_functions()
      true
  """
  @spec known_guard_functions() :: [atom()]
  def known_guard_functions, do: @all_guard_functions

  @doc """
  Returns the list of type check guard functions.

  ## Examples

      iex> :is_integer in ElixirOntologies.Extractors.Guard.type_check_functions()
      true

      iex> :> in ElixirOntologies.Extractors.Guard.type_check_functions()
      false
  """
  @spec type_check_functions() :: [atom()]
  def type_check_functions, do: @type_check_guards

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp decompose_guard({:and, _, [left, right]}) do
    decompose_guard(left) ++ decompose_guard(right)
  end

  defp decompose_guard({:or, _, [left, right]}) do
    decompose_guard(left) ++ decompose_guard(right)
  end

  defp decompose_guard(expr), do: [expr]

  defp determine_combinator({:and, _, [left, right]}) do
    left_has_or = has_or_combinator?(left)
    right_has_or = has_or_combinator?(right)

    if left_has_or or right_has_or do
      :mixed
    else
      :and
    end
  end

  defp determine_combinator({:or, _, [left, right]}) do
    left_has_and = has_and_combinator?(left)
    right_has_and = has_and_combinator?(right)

    if left_has_and or right_has_and do
      :mixed
    else
      :or
    end
  end

  defp determine_combinator(_), do: :none

  defp has_and_combinator?({:and, _, _}), do: true
  defp has_and_combinator?({:or, _, [left, right]}), do: has_and_combinator?(left) or has_and_combinator?(right)
  defp has_and_combinator?(_), do: false

  defp has_or_combinator?({:or, _, _}), do: true
  defp has_or_combinator?({:and, _, [left, right]}), do: has_or_combinator?(left) or has_or_combinator?(right)
  defp has_or_combinator?(_), do: false

  defp extract_guard_functions(expressions) do
    expressions
    |> Enum.flat_map(&extract_functions_from_expr/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_functions_from_expr({name, _, args}) when is_atom(name) and is_list(args) do
    nested = Enum.flat_map(args, &extract_functions_from_expr/1)

    if name in @all_guard_functions do
      [name | nested]
    else
      nested
    end
  end

  defp extract_functions_from_expr(_), do: []

  defp build_metadata(expressions, functions) do
    %{
      count: length(expressions),
      has_type_check: Enum.any?(functions, &(&1 in @type_check_guards)),
      has_comparison: Enum.any?(functions, &(&1 in @comparison_operators))
    }
  end
end
