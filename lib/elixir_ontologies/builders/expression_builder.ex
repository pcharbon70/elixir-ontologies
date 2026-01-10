defmodule ElixirOntologies.Builders.ExpressionBuilder do
  @moduledoc """
  Builder module for converting Elixir AST nodes into RDF expressions.

  This module provides the core infrastructure for extracting expression
  information from Elixir AST and representing it as RDF triples according
  to the elixir-core ontology.

  ## Expression Extraction Modes

  The module supports two extraction modes controlled by `include_expressions`
  configuration:

  - **Light Mode** (`include_expressions: false`): Returns `:skip` for all
    expressions. This is the default and provides backward compatibility.

  - **Full Mode** (`include_expressions: true`): Extracts complete expression
    ASTs as RDF triples with proper type information and operand relationships.

  ## Project vs Dependency Files

  Even in full mode, dependency files (those in `deps/` directory) are always
  extracted in light mode. Only project files get full expression extraction.

  ## Usage

      alias ElixirOntologies.Builders.{ExpressionBuilder, Context}

      # Light mode - returns :skip
      context = Context.new(base_iri: "https://example.org/code#", config: %{include_expressions: false})
      ast = {:==, [], [{:x, [], nil}, 1]}
      ExpressionBuilder.build(ast, context, [])
      # => :skip

      # Full mode - extracts expression
      context = Context.new(base_iri: "https://example.org/code#", config: %{include_expressions: true})
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])
      # => {:ok, {~I<https://example.org/code#expr_0>, [...]}}}

  ## AST Pattern Matching

  The module dispatches to specific builder functions based on AST patterns:

  - **Comparison operators**: `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`
  - **Logical operators**: `and`, `or`, `not`, `&&`, `||`, `!`
  - **Arithmetic operators**: `+`, `-`, `*`, `/`, `div`, `rem`
  - **Literals**: Integers, floats, strings, atoms, charlists, binaries
  - **Variables**: `{name, _, context}` pattern
  - **Patterns**: Wildcards, tuples, lists, maps

  ## Return Type

  All `build/3` calls return either:

  - `{:ok, {iri, triples}}` - Expression was successfully built
  - `:skip` - Expression should not be extracted (light mode or nil AST)

  ## IRI Generation

  Expression IRIs follow the pattern `{base_iri}expr_{counter}` with nested
  expressions using relative IRIs like `{parent_iri}/left`, `{parent_iri}/right`.

  The counter is reset per extraction to ensure consistent IRIs within a
  single analysis run.

  """

  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Builders.Helpers
  alias ElixirOntologies.NS.Core

  # ===========================================================================
  # Types
  # ===========================================================================

  @type ast :: Macro.t()
  @type result :: {:ok, {RDF.IRI.t(), [RDF.Triple.t()]}} | :skip

  # ===========================================================================
  # Counter State
  # ===========================================================================

  @doc """
  Resets the expression counter for the given base IRI.

  This should be called at the start of each extraction to ensure
  consistent IRI generation.

  ## Examples

      iex> ExpressionBuilder.reset_counter("https://example.org/code#")
      :ok
  """
  @spec reset_counter(String.t()) :: :ok
  def reset_counter(base_iri) do
    # Ensure table exists
    try do
      :ets.insert(:expression_counter, {base_iri, 0})
    rescue
      ArgumentError ->
        :ets.new(:expression_counter, [:named_table, :public])
        :ets.insert(:expression_counter, {base_iri, 0})
    end

    :ets.delete_all_objects(:expression_counter)
    :ets.insert(:expression_counter, {base_iri, 0})
    :ok
  end

  @doc """
  Gets the next expression counter value for the given base IRI.

  ## Examples

      iex> ExpressionBuilder.reset_counter("https://example.org/code#")
      iex> ExpressionBuilder.next_counter("https://example.org/code#")
      0
      iex> ExpressionBuilder.next_counter("https://example.org/code#")
      1
  """
  @spec next_counter(String.t()) :: non_neg_integer()
  def next_counter(base_iri) do
    try do
      case :ets.lookup(:expression_counter, base_iri) do
        [] ->
          :ets.insert(:expression_counter, {base_iri, 1})
          0
        [{^base_iri, counter}] ->
          :ets.insert(:expression_counter, {base_iri, counter + 1})
          counter
      end
    rescue
      ArgumentError ->
        :ets.new(:expression_counter, [:named_table, :public])
        :ets.insert(:expression_counter, {base_iri, 1})
        0
    end
  end

  # ===========================================================================
  # Main Build Function
  # ===========================================================================

  @doc """
  Builds an RDF representation of an Elixir AST expression.

  Returns `:skip` in light mode or for nil AST nodes. Otherwise returns
  `{:ok, {iri, triples}}` with the expression IRI and generated triples.

  ## Parameters

  - `ast` - The Elixir AST node to convert
  - `context` - The builder context containing config and base IRI
  - `opts` - Optional keyword arguments (reserved for future use)

  ## Examples

      # Light mode
      context = Context.new(base_iri: "https://example.org/code#", config: %{include_expressions: false})
      ExpressionBuilder.build({:==, [], [1, 2]}, context, [])
      # => :skip

      # Full mode (stub - returns generic Expression)
      context = Context.new(base_iri: "https://example.org/code#", config: %{include_expressions: true})
      {:ok, {iri, triples}} = ExpressionBuilder.build({:==, [], [1, 2]}, context, [])
  """
  @spec build(ast(), Context.t(), keyword()) :: result()
  def build(nil, _context, _opts), do: :skip

  def build(ast, context, opts) do
    # Check if we should extract expressions for this file
    file_path = context.file_path || ""

    cond do
      # Light mode - skip all expressions
      !Context.full_mode?(context) ->
        :skip

      # Dependency files - always light mode
      !Context.full_mode_for_file?(context, file_path) ->
        :skip

      # Full mode for project files - dispatch to appropriate builder
      true ->
        build_expression_triples(ast, context, opts)
    end
  end

  # ===========================================================================
  # Expression Dispatch
  # ===========================================================================

  # Comparison operators (==, !=, ===, !==, <, >, <=, >=)
  @doc false
  def build_expression_triples({op, _, [_left, _right]}, context, opts)
      when op in [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :comparison, context, opts)
  end

  # Logical operators (and, or, not, &&, ||, !)
  @doc false
  def build_expression_triples({op, _, _args} = _ast, context, opts)
      when op in [:and, :or] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :logical, context, opts)
  end

  @doc false
  def build_expression_triples({:not, _, [_arg]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:not, :unary_logical, context, opts)
  end

  @doc false
  def build_expression_triples({op, _, _args} = _ast, context, opts)
      when op in [:&&, :||] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :logical_short_circuit, context, opts)
  end

  @doc false
  def build_expression_triples({:!, _, [_arg]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:!, :unary_logical_short_circuit, context, opts)
  end

  # Arithmetic operators (+, -, *, /, div, rem)
  @doc false
  def build_expression_triples({op, _, [_left, _right]}, context, opts)
      when op in [:+, :-, :*, :/] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :arithmetic, context, opts)
  end

  @doc false
  def build_expression_triples({op, _, [_left, _right]}, context, opts)
      when op in [:div, :rem] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :arithmetic, context, opts)
  end

  # Pipe operator (|>)
  @doc false
  def build_expression_triples({:|>, _, [_left, _right]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:|>, :pipe, context, opts)
  end

  # Match operator (=)
  @doc false
  def build_expression_triples({:=, _, [_left, _right]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:=, :match, context, opts)
  end

  # String concatenation (<>)
  @doc false
  def build_expression_triples({:<>, _, [_left, _right]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:<>, :string_concat, context, opts)
  end

  # List operators (++, --)
  @doc false
  def build_expression_triples({op, _, [_left, _right]}, context, opts)
      when op in [:++, :--] do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(op, :list, context, opts)
  end

  # In operator
  @doc false
  def build_expression_triples({:in, _, [_left, _right]}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_expression(:in, :in_operator, context, opts)
  end

  # Capture operator (&)
  @doc false
  def build_expression_triples({:&, _, _} = _ast, context, opts) do
    # STUB: Will be implemented in section 21.4 or 29
    build_stub_expression(:&, :capture, context, opts)
  end

  # Remote call (Module.function)
  @doc false
  def build_expression_triples({:., _, [_module, _function]}, context, opts) do
    # STUB: Will be implemented in section 21.4 or 29
    build_stub_expression(:remote_call, :remote_call, context, opts)
  end

  # Variables ({name, _, context})
  # Note: Must come before local_call pattern to distinguish variables from function calls
  # Variables have ctx as an atom (usually nil) while calls have args as a list
  @doc false
  def build_expression_triples({name, _, ctx} = _ast, context, opts)
      when is_atom(name) and is_atom(ctx) do
    # STUB: Will be implemented in section 21.4
    build_stub_variable(name, context, opts)
  end

  # Local function call (function(args))
  @doc false
  def build_expression_triples({function, _, args} = _ast, context, opts)
      when is_atom(function) and is_list(args) do
    # STUB: Will be implemented in section 21.4 or 29
    build_stub_expression(function, :local_call, context, opts)
  end

  # Integer literals
  @doc false
  def build_expression_triples(integer, context, opts) when is_integer(integer) do
    # STUB: Will be implemented in section 21.4
    build_stub_literal(integer, :integer, context, opts)
  end

  # Float literals
  @doc false
  def build_expression_triples(float, context, opts) when is_float(float) do
    # STUB: Will be implemented in section 21.4
    build_stub_literal(float, :float, context, opts)
  end

  # String literals
  @doc false
  def build_expression_triples(string, context, opts) when is_binary(string) do
    # STUB: Will be implemented in section 21.4
    build_stub_literal(string, :string, context, opts)
  end

  # Atom literals (including true, false, nil)
  @doc false
  def build_expression_triples(atom, context, opts) when is_atom(atom) do
    # STUB: Will be implemented in section 21.4
    build_stub_literal(atom, :atom, context, opts)
  end

  # Charlist literals (lists of char codes)
  # Note: We treat all lists as list literals since we can't distinguish
  # between charlists created with ~c and regular lists at runtime
  @doc false
  def build_expression_triples(list, context, opts)
      when is_list(list) do
    # STUB: Will be implemented in section 21.4 or 22
    build_stub_literal(list, :list, context, opts)
  end

  # Wildcard pattern ({:_})
  # Note: Must come before tuple patterns since {:_} is a 1-tuple
  @doc false
  def build_expression_triples({:_}, context, opts) do
    # STUB: Will be implemented in section 21.4
    build_stub_wildcard(context, opts)
  end

  # Tuple literals
  # Note: Must come after wildcard pattern since {:_} is technically a tuple
  # We need to distinguish tuples from operator ASTs
  @doc false
  def build_expression_triples({elem1, elem2}, context, opts)
      when not is_list(elem2) and elem2 != nil do
    # STUB: Will be implemented in section 21.4 or 22
    # This matches 2-tuples where elem2 is not a list (not operator metadata)
    build_stub_literal({elem1, elem2}, :tuple, context, opts)
  end

  @doc false
  def build_expression_triples(tuple, context, opts) when is_tuple(tuple) do
    # STUB: Will be implemented in section 21.4 or 22
    # Match larger tuples (3+ elements)
    build_stub_literal(tuple, :tuple, context, opts)
  end

  # Map literals
  @doc false
  def build_expression_triples(%{} = map, context, opts) do
    # STUB: Will be implemented in section 21.4 or 22
    build_stub_literal(map, :map, context, opts)
  end

  # Fallback for unknown expressions
  @doc false
  def build_expression_triples(_ast, context, opts) do
    # Return generic Expression type for unhandled AST nodes
    build_stub_expression(:unknown, :generic, context, opts)
  end

  # ===========================================================================
  # Stub Builder Functions (To be implemented in section 21.4)
  # ===========================================================================

  # Generates a stub expression with appropriate type
  defp build_stub_expression(op, type, context, _opts) do
    base_iri = get_base_iri(context)
    counter = next_counter(base_iri)
    expr_iri = RDF.IRI.new("#{base_iri}expr_#{counter}")

    # Determine the expression class based on type
    expr_class =
      case type do
        :comparison -> Core.ComparisonOperator
        :logical -> Core.LogicalOperator
        :unary_logical -> Core.LogicalOperator
        :logical_short_circuit -> Core.LogicalOperator
        :unary_logical_short_circuit -> Core.LogicalOperator
        :arithmetic -> Core.ArithmeticOperator
        :pipe -> Core.PipeOperator
        :match -> Core.MatchOperator
        :string_concat -> Core.StringConcatOperator
        :list -> Core.ListOperator
        :in_operator -> Core.InOperator
        :capture -> Core.CaptureOperator
        :remote_call -> Core.RemoteCall
        :local_call -> Core.LocalCall
        :generic -> Core.Expression
        _ -> Core.Expression
      end

    # Build stub triples
    triples =
      [
        Helpers.type_triple(expr_iri, expr_class)
      ]

    # Add operator symbol for operators
    triples =
      if type != :remote_call and type != :local_call and type != :generic do
        op_str =
          if op == :remote_call do
            "remote_call"
          else
            Atom.to_string(op)
          end

        symbol_triple = Helpers.datatype_property(
          expr_iri,
          Core.operatorSymbol(),
          op_str,
          RDF.XSD.String
        )
        triples ++ [symbol_triple]
      else
        triples
      end

    {:ok, {expr_iri, triples}}
  end

  # Generates a stub literal expression
  defp build_stub_literal(value, type, context, _opts) do
    base_iri = get_base_iri(context)
    counter = next_counter(base_iri)
    expr_iri = RDF.IRI.new("#{base_iri}expr_#{counter}")

    # Determine the literal class based on type
    literal_class =
      case type do
        :integer -> Core.IntegerLiteral
        :float -> Core.FloatLiteral
        :string -> Core.StringLiteral
        :atom -> Core.AtomLiteral
        :charlist -> Core.CharlistLiteral
        :list -> Core.ListLiteral
        :tuple -> Core.TupleLiteral
        :map -> Core.MapLiteral
        _ -> Core.Literal
      end

    # Build stub triples
    triples =
      [
        Helpers.type_triple(expr_iri, literal_class)
      ]

    # Add value property for literals
    {value_prop, value_type} =
      case type do
        :integer -> {Core.integerValue(), RDF.XSD.Integer}
        :float -> {Core.floatValue(), RDF.XSD.Double}
        :string -> {Core.stringValue(), RDF.XSD.String}
        :atom -> {Core.atomValue(), RDF.XSD.String}
        _ -> {nil, nil}
      end

    triples =
      if value_prop do
        value_triple = Helpers.datatype_property(
          expr_iri,
          value_prop,
          value,
          value_type
        )
        triples ++ [value_triple]
      else
        triples
      end

    {:ok, {expr_iri, triples}}
  end

  # Generates a stub variable expression
  defp build_stub_variable(name, context, _opts) do
    base_iri = get_base_iri(context)
    counter = next_counter(base_iri)
    expr_iri = RDF.IRI.new("#{base_iri}expr_#{counter}")

    triples = [
      Helpers.type_triple(expr_iri, Core.Variable),
      Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)
    ]

    {:ok, {expr_iri, triples}}
  end

  # Generates a stub wildcard pattern
  defp build_stub_wildcard(context, _opts) do
    base_iri = get_base_iri(context)
    counter = next_counter(base_iri)
    expr_iri = RDF.IRI.new("#{base_iri}expr_#{counter}")

    triples = [
      Helpers.type_triple(expr_iri, Core.WildcardPattern)
    ]

    {:ok, {expr_iri, triples}}
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Generates a fresh IRI for a nested expression relative to a parent IRI.

  ## Examples

      iex> parent = ~I<https://example.org/code#expr_0>
      iex> ExpressionBuilder.fresh_iri(parent, "left")
      ~I<https://example.org/code#expr_0/left>
  """
  @spec fresh_iri(RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def fresh_iri(parent_iri, suffix) do
    parent_string = RDF.IRI.to_string(parent_iri)
    RDF.IRI.new("#{parent_string}/#{suffix}")
  end

  # Gets the base IRI from the context
  defp get_base_iri(context) do
    case context.base_iri do
      iri when is_binary(iri) -> iri
      %RDF.IRI{} = iri -> RDF.IRI.to_string(iri)
    end
  end
end
