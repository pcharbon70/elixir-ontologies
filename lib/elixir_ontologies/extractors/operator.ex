defmodule ElixirOntologies.Extractors.Operator do
  @moduledoc """
  Extracts operator expressions from AST nodes.

  This module analyzes Elixir AST nodes representing operators and extracts their
  type classification, operands, and metadata. Supports all operator types defined
  in the elixir-core.ttl ontology:

  - Arithmetic: `+`, `-`, `*`, `/`, `div`, `rem`
  - Comparison: `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`
  - Logical: `and`, `or`, `not`, `&&`, `||`, `!`
  - Pipe: `|>`
  - Match: `=`
  - Capture: `&`
  - String Concatenation: `<>`
  - List: `++`, `--`
  - Membership: `in`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Operator
      iex> ast = {:+, [], [1, 2]}
      iex> {:ok, result} = Operator.extract(ast)
      iex> result.type
      :arithmetic
      iex> result.symbol
      :+
      iex> result.operands.left
      1
      iex> result.operands.right
      2

      iex> alias ElixirOntologies.Extractors.Operator
      iex> ast = {:not, [], [{:x, [], Elixir}]}
      iex> {:ok, result} = Operator.extract(ast)
      iex> result.type
      :logical
      iex> result.operator_class
      :UnaryOperator
  """

  alias ElixirOntologies.Analyzer.Location

  # ===========================================================================
  # Operator Classification Constants
  # ===========================================================================

  @arithmetic_operators [:+, :-, :*, :/, :div, :rem]
  @comparison_operators [:==, :!=, :===, :!==, :<, :>, :<=, :>=]
  @logical_operators [:and, :or, :not, :&&, :||, :!]
  @pipe_operator [:|>]
  @match_operator [:=]
  @capture_operator [:&]
  @string_concat_operator [:<>]
  @list_operators [:++, :--]
  @in_operator [:in]

  # All operators combined for quick lookup
  @all_operators @arithmetic_operators ++
                   @comparison_operators ++
                   @logical_operators ++
                   @pipe_operator ++
                   @match_operator ++
                   @capture_operator ++
                   @string_concat_operator ++
                   @list_operators ++
                   @in_operator

  # Operators that can be unary (single operand)
  @unary_capable [:-, :not, :!, :&]

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of operator extraction.

  - `:type` - The operator type classification
  - `:operator_class` - `:UnaryOperator` or `:BinaryOperator`
  - `:symbol` - The operator atom (`:+`, `:==`, etc.)
  - `:arity` - Number of operands (1 or 2)
  - `:operands` - Map containing operand AST nodes
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: operator_type(),
          operator_class: :UnaryOperator | :BinaryOperator,
          symbol: atom(),
          arity: 1 | 2,
          operands: operands(),
          location: Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type operator_type ::
          :arithmetic
          | :comparison
          | :logical
          | :pipe
          | :match
          | :capture
          | :string_concat
          | :list
          | :in

  @type operands :: %{
          optional(:left) => Macro.t(),
          optional(:right) => Macro.t(),
          optional(:operand) => Macro.t()
        }

  defstruct [:type, :operator_class, :symbol, :arity, :operands, :location, metadata: %{}]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents an operator expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.operator?({:+, [], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Operator.operator?({:==, [], [{:a, [], nil}, {:b, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Operator.operator?({:|>, [], [{:x, [], nil}, {:f, [], []}]})
      true

      iex> ElixirOntologies.Extractors.Operator.operator?({:def, [], [{:foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Operator.operator?(:atom)
      false
  """
  @spec operator?(Macro.t()) :: boolean()
  def operator?({op, _meta, args}) when is_atom(op) and is_list(args) do
    op in @all_operators and length(args) in [1, 2]
  end

  def operator?(_), do: false

  @doc """
  Returns the operator type classification, or `nil` if not an operator.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.operator_type({:+, [], [1, 2]})
      :arithmetic

      iex> ElixirOntologies.Extractors.Operator.operator_type({:==, [], [{:a, [], nil}, {:b, [], nil}]})
      :comparison

      iex> ElixirOntologies.Extractors.Operator.operator_type({:and, [], [{:a, [], nil}, {:b, [], nil}]})
      :logical

      iex> ElixirOntologies.Extractors.Operator.operator_type({:|>, [], [{:x, [], nil}, {:f, [], []}]})
      :pipe

      iex> ElixirOntologies.Extractors.Operator.operator_type({:=, [], [{:x, [], nil}, 1]})
      :match

      iex> ElixirOntologies.Extractors.Operator.operator_type({:&, [], [{:/, [], [{:foo, [], nil}, 1]}]})
      :capture

      iex> ElixirOntologies.Extractors.Operator.operator_type({:<>, [], ["a", "b"]})
      :string_concat

      iex> ElixirOntologies.Extractors.Operator.operator_type({:++, [], [[1], [2]]})
      :list

      iex> ElixirOntologies.Extractors.Operator.operator_type({:in, [], [{:x, [], nil}, [1, 2]]})
      :in

      iex> ElixirOntologies.Extractors.Operator.operator_type({:def, [], [{:foo, [], nil}]})
      nil
  """
  @spec operator_type(Macro.t()) :: operator_type() | nil
  def operator_type({op, _meta, args}) when is_atom(op) and is_list(args) do
    cond do
      op in @arithmetic_operators -> :arithmetic
      op in @comparison_operators -> :comparison
      op in @logical_operators -> :logical
      op in @pipe_operator -> :pipe
      op in @match_operator -> :match
      op in @capture_operator -> :capture
      op in @string_concat_operator -> :string_concat
      op in @list_operators -> :list
      op in @in_operator -> :in
      true -> nil
    end
  end

  def operator_type(_), do: nil

  @doc """
  Checks if an operator AST node represents a unary operation.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.unary?({:-, [], [{:x, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Operator.unary?({:not, [], [{:a, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Operator.unary?({:+, [], [1, 2]})
      false
  """
  @spec unary?(Macro.t()) :: boolean()
  def unary?({op, _meta, [_operand]}) when op in @unary_capable, do: true
  def unary?(_), do: false

  @doc """
  Checks if an operator AST node represents a binary operation.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.binary?({:+, [], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Operator.binary?({:-, [], [{:x, [], nil}]})
      false
  """
  @spec binary?(Macro.t()) :: boolean()
  def binary?({op, _meta, [_left, _right]}) when op in @all_operators, do: true
  def binary?(_), do: false

  @doc """
  Returns the operator class based on symbol and arity.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.operator_class(:+, 2)
      :BinaryOperator

      iex> ElixirOntologies.Extractors.Operator.operator_class(:-, 1)
      :UnaryOperator

      iex> ElixirOntologies.Extractors.Operator.operator_class(:not, 1)
      :UnaryOperator
  """
  @spec operator_class(atom(), 1 | 2) :: :UnaryOperator | :BinaryOperator
  def operator_class(_symbol, 1), do: :UnaryOperator
  def operator_class(_symbol, 2), do: :BinaryOperator

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts an operator expression from an AST node.

  Returns `{:ok, %Operator{}}` on success, or `{:error, reason}` if the node
  is not a recognized operator.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.Operator.extract({:+, [], [1, 2]})
      iex> result.type
      :arithmetic
      iex> result.symbol
      :+
      iex> result.arity
      2

      iex> {:ok, result} = ElixirOntologies.Extractors.Operator.extract({:not, [], [{:x, [], Elixir}]})
      iex> result.type
      :logical
      iex> result.operator_class
      :UnaryOperator

      iex> {:error, _} = ElixirOntologies.Extractors.Operator.extract({:def, [], nil})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract({op, meta, [operand]} = node) when op in @unary_capable do
    type = operator_type(node)

    if type do
      {:ok, build_unary(op, meta, operand, type)}
    else
      {:error, "Not an operator: #{inspect(node)}"}
    end
  end

  def extract({op, meta, [left, right]} = node) when op in @all_operators do
    type = operator_type(node)

    if type do
      {:ok, build_binary(op, meta, left, right, type)}
    else
      {:error, "Not an operator: #{inspect(node)}"}
    end
  end

  def extract(node) do
    {:error, "Not an operator: #{inspect(node)}"}
  end

  @doc """
  Extracts an operator expression, raising on error.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Operator.extract!({:+, [], [1, 2]})
      iex> result.symbol
      :+
  """
  @spec extract!(Macro.t()) :: t()
  def extract!(node) do
    case extract(node) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Operator Symbol Information
  # ===========================================================================

  @doc """
  Returns the string representation of an operator symbol.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.symbol_string(:+)
      "+"

      iex> ElixirOntologies.Extractors.Operator.symbol_string(:|>)
      "|>"

      iex> ElixirOntologies.Extractors.Operator.symbol_string(:and)
      "and"
  """
  @spec symbol_string(atom()) :: String.t()
  def symbol_string(op) when is_atom(op), do: Atom.to_string(op)

  @doc """
  Returns all operators of a given type.

  ## Examples

      iex> ElixirOntologies.Extractors.Operator.operators_of_type(:arithmetic)
      [:+, :-, :*, :/, :div, :rem]

      iex> ElixirOntologies.Extractors.Operator.operators_of_type(:comparison)
      [:==, :!=, :===, :!==, :<, :>, :<=, :>=]
  """
  @spec operators_of_type(operator_type()) :: [atom()]
  def operators_of_type(:arithmetic), do: @arithmetic_operators
  def operators_of_type(:comparison), do: @comparison_operators
  def operators_of_type(:logical), do: @logical_operators
  def operators_of_type(:pipe), do: @pipe_operator
  def operators_of_type(:match), do: @match_operator
  def operators_of_type(:capture), do: @capture_operator
  def operators_of_type(:string_concat), do: @string_concat_operator
  def operators_of_type(:list), do: @list_operators
  def operators_of_type(:in), do: @in_operator

  @doc """
  Returns all known operator symbols.

  ## Examples

      iex> ops = ElixirOntologies.Extractors.Operator.all_operators()
      iex> :+ in ops
      true
      iex> :== in ops
      true
      iex> :|> in ops
      true
  """
  @spec all_operators() :: [atom()]
  def all_operators, do: @all_operators

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_unary(op, meta, operand, type) do
    node = {op, meta, [operand]}

    %__MODULE__{
      type: type,
      operator_class: :UnaryOperator,
      symbol: op,
      arity: 1,
      operands: %{operand: operand},
      location: extract_location(node),
      metadata: build_metadata(op, type, 1)
    }
  end

  defp build_binary(op, meta, left, right, type) do
    node = {op, meta, [left, right]}

    %__MODULE__{
      type: type,
      operator_class: :BinaryOperator,
      symbol: op,
      arity: 2,
      operands: %{left: left, right: right},
      location: extract_location(node),
      metadata: build_metadata(op, type, 2)
    }
  end

  defp build_metadata(op, type, arity) do
    base = %{
      symbol_string: symbol_string(op),
      is_shortcircuit: shortcircuit_operator?(op)
    }

    case type do
      :logical ->
        Map.merge(base, %{strict_boolean: strict_boolean_operator?(op)})

      :capture ->
        Map.merge(base, %{capture_type: classify_capture_type(op, arity)})

      _ ->
        base
    end
  end

  defp shortcircuit_operator?(op) when op in [:and, :or, :&&, :||], do: true
  defp shortcircuit_operator?(_), do: false

  defp strict_boolean_operator?(op) when op in [:and, :or, :not], do: true
  defp strict_boolean_operator?(_), do: false

  defp classify_capture_type(:&, _arity), do: :function_capture

  defp extract_location({_op, meta, _args} = node) when is_list(meta) do
    case Location.extract_range(node) do
      {:ok, location} -> location
      _ -> nil
    end
  end

  defp extract_location(_), do: nil
end
