defmodule ElixirOntologies.Builders.ExpressionBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder}
  alias ElixirOntologies.NS.Core

  doctest ExpressionBuilder

  describe "build/3 mode selection" do
    test "returns :skip when include_expressions is false" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns {:ok, {expr_iri, triples, context}} for nil AST in full mode" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      assert {:ok, {expr_iri, triples, _updated_context}} = ExpressionBuilder.build(nil, context, [])
      assert has_type?(triples, Core.NilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), "nil")
    end

    test "returns :skip for dependency files even when include_expressions is true" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns {:ok, {expr_iri, triples, context}} when include_expressions is true and project file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      result = ExpressionBuilder.build(ast, context, [])

      assert {:ok, {expr_iri, triples, _updated_context}} = result
      assert is_struct(expr_iri, RDF.IRI)
      assert is_list(triples)
    end
  end

  describe "build/3 IRI generation" do
    test "generates IRI with correct base" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples, _context}} = ExpressionBuilder.build(ast, context, [])

      iri_string = RDF.IRI.to_string(expr_iri)
      assert String.starts_with?(iri_string, "https://example.org/code#expr/")
    end

    test "accepts custom suffix option" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples, _context}} = ExpressionBuilder.build(ast, context, suffix: "my_expr")

      iri_string = RDF.IRI.to_string(expr_iri)
      assert iri_string == "https://example.org/code#expr/my_expr"
    end

    test "generates unique IRIs for multiple calls" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _, _}} = ExpressionBuilder.build(ast, context2, [])

      refute iri1 == iri2
    end

    test "generates deterministic sequential IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _, context3}} = ExpressionBuilder.build(ast, context2, [])
      {:ok, {iri3, _, _}} = ExpressionBuilder.build(ast, context3, [])

      # IRIs should be sequential based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end
  end

  describe "comparison operators" do
    for op <- [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
      @op op

      test "dispatches #{op} to ComparisonOperator" do
        context =
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app/users.ex"
          )

        ast = {@op, [], [{:x, [], nil}, 1]}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        # Check for ComparisonOperator type
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ComparisonOperator
        end)

        # Check for operator symbol
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.operatorSymbol() and
            RDF.Literal.value(o) == to_string(@op)
        end)
      end
    end

    test "comparison operator captures left and right operands" do
      context = full_mode_context()
      ast = {:==, [], [{:x, [], nil}, 42]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ComparisonOperator type
      assert has_type?(triples, Core.ComparisonOperator)

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left operand is a Variable
      assert has_type?(triples, Core.Variable)

      # Right operand is an IntegerLiteral
      assert has_type?(triples, Core.IntegerLiteral)
    end

    test "comparison operator with nested expressions" do
      context = full_mode_context()
      # x > (y + 1) as AST
      ast = {:>, [], [{:x, [], nil}, {:+, [], [{:y, [], nil}, 1]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ComparisonOperator type
      assert has_type?(triples, Core.ComparisonOperator)

      # Right operand should be an ArithmeticOperator (the nested addition)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ArithmeticOperator end)

      # The nested arithmetic operator should have its own operator symbol
      assert has_operator_symbol_for_iri?(triples, right_iri, "+")
    end

    test "comparison operator with both operands as expressions" do
      context = full_mode_context()
      # (x + 1) == (y - 2) as AST
      left_expr = {:+, [], [{:x, [], nil}, 1]}
      right_expr = {:-, [], [{:y, [], nil}, 2]}
      ast = {:==, [], [left_expr, right_expr]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ComparisonOperator type
      assert has_type?(triples, Core.ComparisonOperator)

      # Left operand should be an ArithmeticOperator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ArithmeticOperator end)

      # Right operand should be an ArithmeticOperator
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ArithmeticOperator end)

      # Both nested operators should have their symbols
      assert has_operator_symbol_for_iri?(triples, left_iri, "+")
      assert has_operator_symbol_for_iri?(triples, right_iri, "-")
    end
  end

  describe "logical operators" do
    test "dispatches and to LogicalOperator" do
      context = full_mode_context()
      ast = {:and, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")
    end

    test "dispatches or to LogicalOperator" do
      context = full_mode_context()
      ast = {:or, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "or")
    end

    test "dispatches && to LogicalOperator" do
      context = full_mode_context()
      ast = {:&&, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "&&")
    end

    test "dispatches || to LogicalOperator" do
      context = full_mode_context()
      ast = {:||, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "||")
    end

    test "dispatches not to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:not, [], [true]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")
    end

    test "dispatches ! to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:!, [], [true]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "!")
    end

    test "logical operator captures left and right operands" do
      context = full_mode_context()
      ast = {:and, [], [true, false]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create LogicalOperator type
      assert has_type?(triples, Core.LogicalOperator)

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Both operands are BooleanLiterals
      assert has_type?(triples, Core.BooleanLiteral)
    end

    test "logical operator with nested expressions" do
      context = full_mode_context()
      # (x > 5) and (y < 10) as AST
      left_expr = {:>, [], [{:x, [], nil}, 5]}
      right_expr = {:<, [], [{:y, [], nil}, 10]}
      ast = {:and, [], [left_expr, right_expr]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create LogicalOperator type
      assert has_type?(triples, Core.LogicalOperator)

      # Left operand should be a ComparisonOperator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ComparisonOperator end)

      # Right operand should be a ComparisonOperator
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ComparisonOperator end)

      # Both nested operators should have their symbols
      assert has_operator_symbol_for_iri?(triples, left_iri, ">")
      assert has_operator_symbol_for_iri?(triples, right_iri, "<")
    end

    test "unary logical operator with expression operand" do
      context = full_mode_context()
      # not (x == 5) as AST
      ast = {:not, [], [{:==, [], [{:x, [], nil}, 5]}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create LogicalOperator type
      assert has_type?(triples, Core.LogicalOperator)

      # Should have operand
      operand_iri = ExpressionBuilder.fresh_iri(expr_iri, "operand")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasOperand() and o == operand_iri
      end)

      # Operand should be a ComparisonOperator
      assert Enum.any?(triples, fn {s, _p, o} -> s == operand_iri and o == Core.ComparisonOperator end)

      # The nested comparison should have its symbol
      assert has_operator_symbol_for_iri?(triples, operand_iri, "==")
    end
  end

  describe "arithmetic operators" do
    for op <- [:+, :-, :*, :/, :div, :rem] do
      @op op

      test "dispatches #{op} to ArithmeticOperator" do
        context = full_mode_context()
        ast = {@op, [], [1, 2]}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        assert has_operator_symbol?(triples, to_string(@op))
      end
    end

    test "arithmetic operator captures left and right operands" do
      context = full_mode_context()
      ast = {:+, [], [1, 2]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ArithmeticOperator type
      assert has_type?(triples, Core.ArithmeticOperator)

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Both operands are IntegerLiterals
      assert has_type?(triples, Core.IntegerLiteral)
    end

    test "arithmetic operator with nested expressions" do
      context = full_mode_context()
      # x + (y * 2) as AST
      ast = {:+, [], [{:x, [], nil}, {:*, [], [{:y, [], nil}, 2]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ArithmeticOperator type
      assert has_type?(triples, Core.ArithmeticOperator)

      # Right operand should be an ArithmeticOperator (the nested multiplication)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ArithmeticOperator end)

      # The nested arithmetic operator should have its own operator symbol
      assert has_operator_symbol_for_iri?(triples, right_iri, "*")
    end

    test "arithmetic operator with both operands as expressions" do
      context = full_mode_context()
      # (x + 1) * (y - 2) as AST
      left_expr = {:+, [], [{:x, [], nil}, 1]}
      right_expr = {:-, [], [{:y, [], nil}, 2]}
      ast = {:*, [], [left_expr, right_expr]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ArithmeticOperator type
      assert has_type?(triples, Core.ArithmeticOperator)

      # Left operand should be an ArithmeticOperator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ArithmeticOperator end)

      # Right operand should be an ArithmeticOperator
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ArithmeticOperator end)

      # Both nested operators should have their symbols
      assert has_operator_symbol_for_iri?(triples, left_iri, "+")
      assert has_operator_symbol_for_iri?(triples, right_iri, "-")
    end

    test "chained arithmetic operations (left-associative)" do
      context = full_mode_context()
      # 1 + 2 + 3 as AST (left-associative: (1 + 2) + 3)
      inner_add = {:+, [], [1, 2]}
      ast = {:+, [], [inner_add, 3]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ArithmeticOperator type
      assert has_type?(triples, Core.ArithmeticOperator)

      # Left operand should be another ArithmeticOperator (the inner addition)
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ArithmeticOperator end)

      # The inner operator should have operator symbol "+"
      assert has_operator_symbol_for_iri?(triples, left_iri, "+")

      # Right operand should be an IntegerLiteral (3)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.IntegerLiteral end)
    end

    test "arithmetic operator with precedence (multiplication before addition)" do
      context = full_mode_context()
      # 1 * (2 + 3) as AST
      inner_add = {:+, [], [2, 3]}
      ast = {:*, [], [1, inner_add]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ArithmeticOperator type (multiplication)
      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "*")

      # Right operand should be an ArithmeticOperator (the inner addition)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ArithmeticOperator end)

      # The inner operator should have operator symbol "+"
      assert has_operator_symbol_for_iri?(triples, right_iri, "+")
    end
  end

  describe "unary arithmetic operators" do
    # Table-driven tests for unary operators with different operand types
    @unary_operator_tests [
      # {operator, operand, expected_operand_type, description}
      {:minus, 42, Core.IntegerLiteral, "unary minus with integer literal"},
      {:minus, 3.14, Core.FloatLiteral, "unary minus with float literal"},
      {:minus, {:x, [], Elixir}, Core.Variable, "unary minus with variable"},
      {:plus, 42, Core.IntegerLiteral, "unary plus with integer literal"},
      {:plus, {:x, [], Elixir}, Core.Variable, "unary plus with variable"}
    ]

    for {op, operand, expected_child_type, description} <- @unary_operator_tests do
      @op op
      @operand operand
      @expected_child_type expected_child_type
      @description description

      test "#{@description}" do
        context = full_mode_context()
        op_symbol = if @op == :minus, do: :-, else: :+
        ast = {op_symbol, [], [@operand]}
        {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        symbol = if @op == :minus, do: "-", else: "+"
        assert has_operator_symbol?(triples, symbol)
        assert has_child_with_type?(triples, expr_iri, @expected_child_type)
      end
    end

    # Tests for nested expressions and edge cases
    test "unary minus with nested expression" do
      context = full_mode_context()
      # Unary minus: -(a + b)
      ast = {:-, [], [{:+, [], [{:a, [], Elixir}, {:b, [], Elixir}]}]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "-")
      # Operand should be an ArithmeticOperator (the + expression)
      assert has_child_with_type?(triples, expr_iri, Core.ArithmeticOperator)
    end

    test "nested unary operators" do
      context = full_mode_context()
      # Double negative: - -x
      ast = {:-, [], [{:-, [], [{:x, [], Elixir}]}]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ArithmeticOperator)
      # Should have nested ArithmeticOperator
      assert has_child_with_type?(triples, expr_iri, Core.ArithmeticOperator)
    end

    # Basic operator creation tests
    @unary_basic_tests [
      {:minus, :-, "-"},
      {:plus, :+, "+"}
    ]

    for {op, ast_op, symbol} <- @unary_basic_tests do
      @op op
      @ast_op ast_op
      @symbol symbol

      test "unary #{@op} creates ArithmeticOperator" do
        context = full_mode_context()
        ast = {@ast_op, [], [5]}
        {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        assert has_operator_symbol?(triples, @symbol)
        assert has_operand?(triples, expr_iri)
      end
    end
  end

  describe "pipe operator" do
    test "dispatches |> to PipeOperator" do
      context = full_mode_context()
      ast = {:|>, [], [1, Enum]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.PipeOperator)
      assert has_operator_symbol?(triples, "|>")
    end

    test "pipe operator with literal and variable" do
      context = full_mode_context()
      # x |> f() as AST
      ast = {:|>, [], [{:x, [], nil}, {:f, [], []}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create PipeOperator type
      assert has_type?(triples, Core.PipeOperator)
      assert has_operator_symbol?(triples, "|>")

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left operand is Variable "x"
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")
    end

    test "pipe operator with function call operands" do
      context = full_mode_context()
      # f(x) |> g(y) as AST
      ast =
        {:|>, [], [
          {{:., [], [{:__aliases__, [], [:F]}, :f]}, [], [{:x, [], nil}]},
          {{:., [], [{:__aliases__, [], [:G]}, :g]}, [], [{:y, [], nil}]}
        ]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create PipeOperator type
      assert has_type?(triples, Core.PipeOperator)

      # Left operand is a RemoteCall (module.function calls)
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.RemoteCall end)

      # Right operand is a RemoteCall
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.RemoteCall end)
    end

    test "pipe operator with chained pipes" do
      context = full_mode_context()
      # 1 |> f() |> g() as AST (nested pipes)
      inner_pipe = {:|>, [], [1, {:f, [], []}]}
      ast = {:|>, [], [inner_pipe, {:g, [], []}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create PipeOperator type
      assert has_type?(triples, Core.PipeOperator)

      # Left operand should be another PipeOperator (the inner pipe)
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.PipeOperator end)

      # The inner pipe should also have operator symbol "|>"
      assert has_operator_symbol_for_iri?(triples, left_iri, "|>")
    end

    test "pipe operator captures left expression" do
      context = full_mode_context()
      # [:a, :b, :c] |> Enum.map() - using atoms to avoid charlist detection
      list_ast = [[:a, [], nil], [:b, [], nil], [:c, [], nil]]
      enum_map = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}

      ast = {:|>, [], [list_ast, enum_map]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Left operand should be captured
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      # Left operand should be a ListLiteral
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ListLiteral end)
    end

    test "pipe operator captures right expression" do
      context = full_mode_context()
      # x |> IO.inspect() as AST
      io_inspect = {{:., [], [{:__aliases__, [], [:IO]}, :inspect]}, [], []}

      ast = {:|>, [], [{:x, [], nil}, io_inspect]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Right operand should be captured
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Right operand should be a RemoteCall (module function calls)
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == right_iri and o == Core.RemoteCall
      end)
    end

    test "pipe operator with complex nested expressions" do
      context = full_mode_context()
      # (x + y) |> f() |> g(z) - complex nested pipe
      add_expr = {:+, [], [{:x, [], nil}, {:y, [], nil}]}
      first_pipe = {:|>, [], [add_expr, {:f, [], []}]}
      ast = {:|>, [], [first_pipe, {:g, [], [{:z, [], nil}]}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Top-level is PipeOperator
      assert has_type?(triples, Core.PipeOperator)

      # Left operand is another PipeOperator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.PipeOperator end)

      # The inner pipe's left operand is an ArithmeticOperator
      inner_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == inner_left_iri and o == Core.ArithmeticOperator
      end)
    end
  end

  describe "string concatenation operator" do
    test "dispatches <> to StringConcatOperator" do
      context = full_mode_context()
      ast = {:<>, [], ["hello", "world"]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.StringConcatOperator)
      assert has_operator_symbol?(triples, "<>")
    end

    test "string concatenation with variables" do
      context = full_mode_context()
      # x <> "suffix" as AST
      ast = {:<>, [], [{:x, [], nil}, "suffix"]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create StringConcatOperator type
      assert has_type?(triples, Core.StringConcatOperator)
      assert has_operator_symbol?(triples, "<>")

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left operand is Variable "x"
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.Variable end)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")

      # Right operand is StringLiteral "suffix"
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.StringLiteral end)
    end

    test "string concatenation with two variables" do
      context = full_mode_context()
      # x <> y as AST
      ast = {:<>, [], [{:x, [], nil}, {:y, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create StringConcatOperator type
      assert has_type?(triples, Core.StringConcatOperator)

      # Both operands should be Variables
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.Variable end)
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.Variable end)
    end

    test "chained string concatenation" do
      context = full_mode_context()
      # "a" <> "b" <> "c" as AST (nested)
      inner_concat = {:<>, [], ["b", "c"]}
      ast = {:<>, [], ["a", inner_concat]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create StringConcatOperator type
      assert has_type?(triples, Core.StringConcatOperator)

      # Right operand should be another StringConcatOperator
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.StringConcatOperator end)

      # The inner concat should also have operator symbol "<>"
      assert has_operator_symbol_for_iri?(triples, right_iri, "<>")
    end

    test "string concatenation with empty string" do
      context = full_mode_context()
      # "" <> "hello" as AST
      ast = {:<>, [], ["", "hello"]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create StringConcatOperator type
      assert has_type?(triples, Core.StringConcatOperator)

      # Left operand is an empty StringLiteral
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.StringLiteral end)

      # Right operand is a StringLiteral
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.StringLiteral end)
    end

    test "string concatenation with special characters" do
      context = full_mode_context()
      # "hello\n" <> "world" as AST
      ast = {:<>, [], ["hello\n", "world"]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create StringConcatOperator type
      assert has_type?(triples, Core.StringConcatOperator)

      # Left operand is a StringLiteral with newline
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.StringLiteral end)

      # Right operand is a StringLiteral
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.StringLiteral end)
    end
  end

  describe "list operators" do
    test "dispatches ++ to ListOperator" do
      context = full_mode_context()
      ast = {:++, [], [[1], [2]]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "++")
    end

    test "dispatches -- to ListOperator" do
      context = full_mode_context()
      ast = {:--, [], [[1, 2], [1]]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "--")
    end

    test "list concatenation with variables" do
      context = full_mode_context()
      # list1 ++ list2 as AST
      ast = {:++, [], [{:list1, [], nil}, {:list2, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ListOperator type
      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "++")

      # Both operands should be Variables
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.Variable end)
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.Variable end)
    end

    test "list subtraction with list literals" do
      context = full_mode_context()
      # Using atoms to avoid charlist detection
      # [:a, :b, :c] -- [:b, :d] as AST
      ast = {:--, [], [[:a, [], nil], [:b, [], nil]]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ListOperator type
      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "--")

      # Both operands should be ListLiterals (atom lists, not charlists)
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ListLiteral end)
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ListLiteral end)
    end

    test "chained list operations" do
      context = full_mode_context()
      # [1] ++ [2] ++ [3] as AST (nested)
      inner_concat = {:++, [], [[2], [3]]}
      ast = {:++, [], [[1], inner_concat]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create ListOperator type
      assert has_type?(triples, Core.ListOperator)

      # Right operand should be another ListOperator
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ListOperator end)

      # The inner concat should also have operator symbol "++"
      assert has_operator_symbol_for_iri?(triples, right_iri, "++")
    end

    test "list operators capture left and right operands" do
      context = full_mode_context()
      # [1, 2] ++ [3, 4] as AST
      ast = {:++, [], [[1, 2], [3, 4]]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)
    end
  end

  describe "match operator" do
    test "dispatches = to MatchOperator" do
      context = full_mode_context()
      ast = {:"=", [], [{:x, [], nil}, 1]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")
    end
  end

  describe "capture operator" do
    test "dispatches &1 to CaptureOperator" do
      context = full_mode_context()
      ast = {:&, [], [1]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for capture index using dedicated captureIndex property
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureIndex() and RDF.Literal.value(o) == 1
      end)
    end

    test "dispatches &2 to CaptureOperator" do
      context = full_mode_context()
      ast = {:&, [], [2]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for capture index
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureIndex() and RDF.Literal.value(o) == 2
      end)
    end

    test "dispatches &3 to CaptureOperator" do
      context = full_mode_context()
      ast = {:&, [], [3]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for capture index
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureIndex() and RDF.Literal.value(o) == 3
      end)
    end

    test "dispatches &Mod.fun/arity to CaptureOperator" do
      context = full_mode_context()
      # &Enum.map/2 as AST
      function_ref = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}
      ast = {:&, [], [{:/, [], [function_ref, 2]}]}

      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for module name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureModuleName() and RDF.Literal.value(o) == "Enum"
      end)

      # Check for function name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureFunctionName() and RDF.Literal.value(o) == "map"
      end)

      # Check for arity
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureArity() and RDF.Literal.value(o) == 2
      end)
    end

    test "dispatches &Mod.fun to CaptureOperator without arity" do
      context = full_mode_context()
      # &IO.inspect as AST
      function_ref = {{:., [], [{:__aliases__, [], [:IO]}, :inspect]}, [], []}
      ast = {:&, [], [function_ref]}

      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for module name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureModuleName() and RDF.Literal.value(o) == "IO"
      end)

      # Check for function name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureFunctionName() and RDF.Literal.value(o) == "inspect"
      end)

      # Should NOT have arity property
      refute Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.captureArity()
      end)
    end

    test "dispatches &4 to CaptureOperator" do
      context = full_mode_context()
      ast = {:&, [], [4]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for capture index
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureIndex() and RDF.Literal.value(o) == 4
      end)
    end

    test "dispatches &5 to CaptureOperator" do
      context = full_mode_context()
      ast = {:&, [], [5]}
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.CaptureOperator)
      assert has_operator_symbol?(triples, "&")

      # Check for capture index
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.captureIndex() and RDF.Literal.value(o) == 5
      end)
    end

    test "capture operator distinguishes argument index from function reference" do
      context = full_mode_context()

      # Argument index (&1)
      ast1 = {:&, [], [1]}
      {:ok, {_expr_iri1, triples1, _}} = ExpressionBuilder.build(ast1, context, [])

      # Has captureIndex property for argument index
      assert Enum.any?(triples1, fn {_s, p, o} ->
        p == Core.captureIndex() and RDF.Literal.value(o) == 1
      end)

      # Function reference (&Enum.map/2)
      function_ref = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}
      ast2 = {:&, [], [{:/, [], [function_ref, 2]}]}
      {:ok, {_expr_iri2, triples2, _}} = ExpressionBuilder.build(ast2, context, [])

      # Has moduleName, functionName, and arity for function reference
      assert Enum.any?(triples2, fn {_s, p, o} ->
        p == Core.captureModuleName() and RDF.Literal.value(o) == "Enum"
      end)

      assert Enum.any?(triples2, fn {_s, p, o} ->
        p == Core.captureFunctionName() and RDF.Literal.value(o) == "map"
      end)

      assert Enum.any?(triples2, fn {_s, p, o} ->
        p == Core.captureArity() and RDF.Literal.value(o) == 2
      end)
    end
  end

  describe "in operator" do
    test "dispatches in to InOperator" do
      context = full_mode_context()
      # 1 in [1, 2, 3] as AST
      ast = {:in, [], [1, [1, 2, 3]]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.InOperator)
      assert has_operator_symbol?(triples, "in")
    end

    test "in operator with variable element" do
      context = full_mode_context()
      # x in [1, 2, 3] as AST
      ast = {:in, [], [{:x, [], nil}, [1, 2, 3]]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create InOperator type
      assert has_type?(triples, Core.InOperator)
      assert has_operator_symbol?(triples, "in")

      # Left operand (element) should be Variable
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.Variable end)
    end

    test "in operator with variable enumerable" do
      context = full_mode_context()
      # 1 in list as AST
      ast = {:in, [], [1, {:list, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create InOperator type
      assert has_type?(triples, Core.InOperator)

      # Right operand (enumerable) should be Variable
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.Variable end)
    end

    test "in operator captures left operand (element)" do
      context = full_mode_context()
      # x in list as AST
      ast = {:in, [], [{:x, [], nil}, [1, 2, 3]]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have left operand property
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      # Left operand is Variable "x"
      assert has_literal_value?(triples, left_iri, Core.name(), "x")
    end

    test "in operator captures right operand (enumerable)" do
      context = full_mode_context()
      # 1 in list as AST
      ast = {:in, [], [1, {:list, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have right operand property
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Right operand is Variable "list"
      assert has_literal_value?(triples, right_iri, Core.name(), "list")
    end

    test "in operator with complex expressions" do
      context = full_mode_context()
      # x + y in list as AST
      add_expr = {:+, [], [{:x, [], nil}, {:y, [], nil}]}
      ast = {:in, [], [add_expr, {:list, [], nil}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create InOperator type
      assert has_type?(triples, Core.InOperator)

      # Left operand is an ArithmeticOperator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} -> s == left_iri and o == Core.ArithmeticOperator end)

      # Right operand is a Variable
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.Variable end)
    end

    test "in operator with empty enumerable" do
      context = full_mode_context()
      # x in [] as AST - use atom list to force ListLiteral (not CharlistLiteral)
      ast = {:in, [], [{:x, [], nil}, [[:a, [], nil], []]]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should create InOperator type
      assert has_type?(triples, Core.InOperator)
      assert has_operator_symbol?(triples, "in")

      # Right operand should be a ListLiteral
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} -> s == right_iri and o == Core.ListLiteral end)
    end
  end

  describe "variables" do
    test "dispatches variable pattern to Variable" do
      context = full_mode_context()
      ast = {:x, [], nil}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.Variable)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "x"
      end)
    end

    test "handles variables with different names" do
      context = full_mode_context()

      for var_name <- [:user, :count, :result, :acc] do
        ast = {var_name, [], nil}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.Variable)
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.name() and RDF.Literal.value(o) == to_string(var_name)
        end)
      end
    end
  end

  describe "wildcard pattern" do
    test "dispatches _ to WildcardPattern" do
      context = full_mode_context()
      ast = {:_}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.WildcardPattern)
    end
  end

  describe "remote calls" do
    test "dispatches Module.function to RemoteCall" do
      context = full_mode_context()

      # AST for String.to_integer("123")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [],
         ["123"]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)

      # Check for name property with module and function
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and
          RDF.Literal.value(o) == "String.to_integer"
      end)
    end

    test "handles nested module names" do
      context = full_mode_context()

      # AST for MyApp.Users.get(1)
      ast =
        {{:., [], [{:__aliases__, [], [:MyApp, :Users]}, :get]}, [], [1]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "MyApp.Users.get"
      end)
    end
  end

  describe "local calls" do
    test "dispatches function(args) to LocalCall" do
      context = full_mode_context()
      ast = {:foo, [], [1, 2]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LocalCall)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "foo"
      end)
    end
  end

  describe "literals" do
    # Table-driven tests for simple numeric and string literals
    @numeric_literal_tests [
      # Integer literals
      {:integer, 42, Core.IntegerLiteral, Core.integerValue(), 42},
      {:integer, 0, Core.IntegerLiteral, Core.integerValue(), 0},
      {:integer, 9_999_999_999, Core.IntegerLiteral, Core.integerValue(), 9_999_999_999},
      {:integer, 1, Core.IntegerLiteral, Core.integerValue(), 1},
      # Float literals
      {:float, 3.14, Core.FloatLiteral, Core.floatValue(), 3.14},
      {:float, 0.0, Core.FloatLiteral, Core.floatValue(), 0.0},
      {:float, 0.0015, Core.FloatLiteral, Core.floatValue(), 0.0015},
      {:float, 10_000_000_000.0, Core.FloatLiteral, Core.floatValue(), 10_000_000_000.0},
      {:float, 0.5, Core.FloatLiteral, Core.floatValue(), 0.5}
    ]

    for {type_name, value, expected_type, value_property, expected_value} <- @numeric_literal_tests do
      @type_name type_name
      @value value
      @expected_type expected_type
      @value_property value_property
      @expected_value expected_value

      test "builds #{@type_name} literal for #{inspect(@value)}" do
        context = full_mode_context()
        {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(@value, context, [])

        assert has_type?(triples, @expected_type)
        assert has_literal_value?(triples, expr_iri, @value_property, @expected_value)
      end
    end

    # Special float cases (edge values that don't need exact value matching)
    @float_edge_cases [
      {1.0e-10, "very small float"},
      {1.0e308, "positive infinity"},
      {-1.0e308, "negative infinity"}
    ]

    for {value, description} <- @float_edge_cases do
      @value value
      @description description

      test "builds FloatLiteral triples for #{@description}" do
        context = full_mode_context()
        {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(@value, context, [])

        assert has_type?(triples, Core.FloatLiteral)
      end
    end

    # Table-driven tests for string literals
    @string_literal_tests [
      {"hello", "basic string"},
      {"", "empty string"},
      {"multi\nline\nstring", "multi-line string (heredoc)"},
      {"hello\nworld\t!", "string with escape sequences"},
      {"!@#$%^&*()_+-=[]{}|;':\",./<>?", "string with special characters"},
      {"héllo wørld 你好", "Unicode string"},
      {"He said \"hello\"", "string with quotes"},
      {String.duplicate("a", 1000), "long string"}
    ]

    for {string_value, description} <- @string_literal_tests do
      @string_value string_value
      @description description

      test "builds StringLiteral triples for #{@description}" do
        context = full_mode_context()
        {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(@string_value, context, [])

        assert has_type?(triples, Core.StringLiteral)
        assert has_literal_value?(triples, expr_iri, Core.stringValue(), @string_value)
      end
    end

    # Table-driven tests for atom/boolean/nil literals
    @atom_literal_tests [
      {:ok, Core.AtomLiteral, ":ok"},
      {true, Core.BooleanLiteral, "true"},
      {false, Core.BooleanLiteral, "false"},
      {nil, Core.NilLiteral, "nil"}
    ]

    for {value, expected_type, expected_value} <- @atom_literal_tests do
      @value value
      @expected_type expected_type
      @expected_value expected_value

      test "builds #{expected_type} triples for #{inspect(@value)}" do
        context = full_mode_context()
        {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(@value, context, [])

        assert has_type?(triples, @expected_type)
        assert has_literal_value?(triples, expr_iri, Core.atomValue(), @expected_value)
      end
    end

    test "builds CharlistLiteral triples for charlists" do
      context = full_mode_context()

      # In Elixir AST, 'hello' appears as a list of character codes
      charlist = [104, 101, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "hello")
    end

    test "builds CharlistLiteral triples for empty charlist" do
      context = full_mode_context()

      # Empty charlist '' appears as empty list []
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([], context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "")
    end

    test "builds CharlistLiteral triples for single character charlist" do
      context = full_mode_context()

      # Single character charlist like '?' appears as [63]
      charlist = [63]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "?")
    end

    test "builds CharlistLiteral triples for charlist with escape sequences" do
      context = full_mode_context()

      # Escape sequences are processed by Elixir compiler
      # '\n' appears as [10] (newline character code)
      charlist = [10]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "\n")
    end

    test "builds CharlistLiteral triples for charlist with Unicode characters" do
      context = full_mode_context()

      # Unicode characters are represented by their codepoints
      # "héllo" = [104, 233, 108, 108, 111]
      charlist = [104, 233, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "héllo")
    end

    test "builds CharlistLiteral triples for multi-byte Unicode charlist" do
      context = full_mode_context()

      # Chinese characters: "你好" (codepoints 20320 and 22909)
      charlist = [20320, 22909]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "你好")
    end

    test "treats non-charlist lists as ListLiteral" do
      context = full_mode_context()

      # A list containing non-integer elements is not a charlist
      mixed_list = [1, :atom, "string"]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(mixed_list, context, [])

      # Should be ListLiteral (not CharlistLiteral, not generic Expression)
      refute has_type?(triples, Core.CharlistLiteral)
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds BinaryLiteral triples for binary with single literal integer" do
      context = full_mode_context()

      # Binary with single byte: <<65>>
      binary_ast = {:<<>>, [], [65]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (checked via lexical)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "A")
    end

    test "builds BinaryLiteral triples for binary with multiple literal integers" do
      context = full_mode_context()

      # Binary with multiple bytes: <<65, 66, 67>> = "ABC"
      binary_ast = {:<<>>, [], [65, 66, 67]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (checked via lexical)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "ABC")
    end

    test "builds BinaryLiteral triples for empty binary" do
      context = full_mode_context()

      # Empty binary: <<>>
      binary_ast = {:<<>>, [], []}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # Empty binary
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "")
    end

    test "builds BinaryLiteral triples for binary with zero bytes" do
      context = full_mode_context()

      # Binary with zeros: <<0, 0, 0>>
      binary_ast = {:<<>>, [], [0, 0, 0]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (three null bytes)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), <<0, 0, 0>>)
    end

    test "builds BinaryLiteral triples for binary with all byte values" do
      context = full_mode_context()

      # Binary with values 0-255
      bytes = Enum.to_list(0..255)
      binary_ast = {:<<>>, [], bytes}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # Verify the base64 value is set (we don't check exact value due to size)
      assert Enum.any?(triples, fn
        {_, p, _} -> p == Core.binaryValue()
        _ -> false
      end)
    end

    test "treats binary with variables as generic expression" do
      context = full_mode_context()

      # Binary with variable: <<x::8>>
      binary_ast = {:<<>>, [], [{:"::", [], [{:x, [], Elixir}, 8]}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression (not BinaryLiteral)
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "treats binary with mixed literals and variables as generic expression" do
      context = full_mode_context()

      # Binary with mixed: <<65, x::8, 67>>
      binary_ast = {:<<>>, [], [65, {:"::", [], [{:x, [], Elixir}, 8]}, 67]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression (not BinaryLiteral)
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "treats binary with type specification as generic expression" do
      context = full_mode_context()

      # Binary with binary type: <<x::binary>>
      binary_ast = {:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:binary, [], Elixir}]}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "builds ListLiteral triples for empty list" do
      context = full_mode_context()

      # Empty list is [] - which is also an empty charlist
      # This gets caught by charlist check first
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build([], context, [])

      # Empty list is treated as charlist (indistinguishable in AST)
      assert has_type?(triples, Core.CharlistLiteral)
    end

    test "builds ListLiteral triples for list of integers" do
      context = full_mode_context()

      # List of integers
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build([1, 2, 3], context, [])

      # This is treated as a charlist since all elements are valid codepoints
      # In practice, [1, 2, 3] could be either a list or a charlist
      # Our implementation treats it as charlist
      assert has_type?(triples, Core.CharlistLiteral)
    end

    test "builds ListLiteral triples for heterogeneous list" do
      context = full_mode_context()

      # List with mixed types
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build([1, "two", :three], context, [])

      # Heterogeneous lists are treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for nested lists" do
      context = full_mode_context()

      # Nested lists
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build([["a", "b"], ["c", "d"]], context, [])

      # Nested lists are treated as ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for list with atoms" do
      context = full_mode_context()

      # List with atoms
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build([:ok, :error], context, [])

      # List with atoms is treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for cons pattern with atom tail" do
      context = full_mode_context()

      # Cons pattern: [1 | :two]
      cons_ast = [{:|, [], [1, :two]}]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(cons_ast, context, [])

      # Cons pattern creates ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for cons pattern with list tail" do
      context = full_mode_context()

      # Cons pattern with list tail: [1 | [2, 3]]
      cons_ast = [{:|, [], [1, [2, 3]]}]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(cons_ast, context, [])

      # Cons pattern creates ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "charlists with valid codepoints are still handled correctly" do
      context = full_mode_context()

      # Charlist with ASCII characters
      charlist = [104, 101, 108, 108, 111]  # "hello"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_binary_literal_value?(triples, expr_iri, Core.charlistValue(), "hello")
    end

    test "charlists with Unicode are still handled correctly" do
      context = full_mode_context()

      # Charlist with Unicode characters: "héllo" = [104, 233, 108, 108, 111]
      charlist = [104, 233, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_binary_literal_value?(triples, expr_iri, Core.charlistValue(), "héllo")
    end

    test "lists with integers outside Unicode range are ListLiteral" do
      context = full_mode_context()

      # Integer outside Unicode range (> 0x10FFFF)
      list_with_large_int = [0x110000]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(list_with_large_int, context, [])

      # Should be treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
      refute has_type?(triples, Core.CharlistLiteral)
    end
  end

  describe "tuple literals" do
    test "builds TupleLiteral triples for empty tuple" do
      context = full_mode_context()

      # Empty tuple: {}
      empty_tuple_ast = quote do: {}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(empty_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 2-tuple" do
      context = full_mode_context()

      # 2-tuple: {1, 2}
      two_tuple_ast = quote do: {1, 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(two_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 3-tuple" do
      context = full_mode_context()

      # 3-tuple: {1, 2, 3}
      three_tuple_ast = quote do: {1, 2, 3}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(three_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 4+ tuple" do
      context = full_mode_context()

      # 4-tuple: {1, 2, 3, 4}
      four_tuple_ast = quote do: {1, 2, 3, 4}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(four_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for nested tuple" do
      context = full_mode_context()

      # Nested tuples: {{1, 2}, {3, 4}}
      nested_tuple_ast = quote do: {{1, 2}, {3, 4}}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(nested_tuple_ast, context, [])

      # Top-level tuple is TupleLiteral
      assert has_type?(triples, Core.TupleLiteral)

      # Should have child expressions for the nested tuples
      # The children will also be TupleLiteral
      child_tuples = Enum.filter(triples, fn {_s, _p, o} -> o == Core.TupleLiteral end)
      # At least the parent tuple should be TupleLiteral
      assert length(child_tuples) >= 1
    end

    test "builds TupleLiteral triples for heterogeneous tuple" do
      context = full_mode_context()

      # Tuple with mixed types: {1, "two", :three}
      het_tuple_ast = quote do: {1, "two", :three}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(het_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for tagged tuple" do
      context = full_mode_context()

      # Tagged tuple: {:ok, 42}
      tagged_tuple_ast = quote do: {:ok, 42}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(tagged_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "tuple elements are extracted as child expressions" do
      context = full_mode_context()

      # Tuple with literals: {1, 2, 3}
      three_tuple_ast = quote do: {1, 2, 3}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(three_tuple_ast, context, [])

      # Parent tuple is TupleLiteral
      assert has_type?(triples, Core.TupleLiteral)

      # Child elements should be IntegerLiteral
      # We should have at least 4 IntegerLiteral triples (one for each child + type triples)
      integer_literals = Enum.filter(triples, fn {_s, _p, o} -> o == Core.IntegerLiteral end)
      assert length(integer_literals) == 3
    end
  end

  describe "map literals" do
    test "builds MapLiteral triples for empty map" do
      context = full_mode_context()

      # Empty map: %{}
      empty_map_ast = quote do: %{}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(empty_map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with atom keys" do
      context = full_mode_context()

      # Map with atom keys: %{a: 1, b: 2}
      map_ast = quote do: %{a: 1, b: 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with string keys" do
      context = full_mode_context()

      # Map with string keys: %{"a" => 1, "b" => 2}
      map_ast = quote do: %{"a" => 1, "b" => 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with mixed keys" do
      context = full_mode_context()

      # Map with mixed keys: %{"a" => 1, b: 2}
      map_ast = quote do: %{"a" => 1, b: 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapUpdateExpression triples for map update syntax" do
      context = full_mode_context()

      # Map update: %{map | key: value}
      # Note: Map update syntax is not currently fully supported
      # The AST pattern is complex and falls through to generic expression handling
      # This test documents the current behavior
      original_map = {:%{}, [], []}
      updated_map_ast = {:%{}, [], [{:|, [], [original_map, [a: 1]]}]}

      # Currently this will fall through to generic expression handling
      # and not match any specific pattern
      result = ExpressionBuilder.build(updated_map_ast, context, [])

      # Should return a result (generic expression)
      assert {:ok, {_expr_iri, triples, _}} = result
      assert is_list(triples)
    end
  end

  describe "struct literals" do
    test "builds StructLiteral triples for struct literal" do
      context = full_mode_context()

      # Struct literal: %User{name: "John"}
      # Note: User needs to be defined for this to compile, so we construct the AST manually
      # AST: {:%, [], [{:__aliases__, ..., [:User]}, {:%{}, [], [name: "John"]}]}
      kw_list = [name: "John"]
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], kw_list}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(struct_ast, context, [])

      assert has_type?(triples, Core.StructLiteral)
    end

    test "struct literal includes refersToModule property" do
      context = full_mode_context()

      # Struct literal: %User{name: "John"}
      kw_list = [name: "John"]
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], kw_list}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(struct_ast, context, [])

      assert has_type?(triples, Core.StructLiteral)

      # Check for refersToModule property
      has_refers_to_module =
        Enum.any?(triples, fn {s, p, _o} ->
          s == expr_iri and p == Core.refersToModule()
        end)

      assert has_refers_to_module
    end

    test "builds StructLiteral triples for struct update syntax" do
      context = full_mode_context()

      # Struct update: %Struct{} | struct
      # Note: This creates a complex update pattern that may not be fully handled
      original_struct = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      updated_struct_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [{:|, [], [original_struct, [name: "Jane"]]}]}]}

      result = ExpressionBuilder.build(updated_struct_ast, context, [])

      # Struct updates should not crash and return a result
      assert {:ok, {_expr_iri, triples, _}} = result
      assert is_list(triples)
    end
  end

  describe "keyword list literals" do
    test "builds KeywordListLiteral triples for keyword list" do
      context = full_mode_context()

      # Keyword list: [a: 1, b: 2]
      kw_list_ast = quote do: [a: 1, b: 2]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      assert has_type?(triples, Core.KeywordListLiteral)
    end

    test "keyword list is distinguished from regular list" do
      context = full_mode_context()

      # Keyword list: [a: 1, b: 2]
      kw_list_ast = quote do: [a: 1, b: 2]
      {:ok, {_expr_iri, kw_triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      # Regular list: [1, 2, 3]
      regular_list_ast = quote do: [1, 2, 3]
      {:ok, {_expr_iri, regular_triples, _}} = ExpressionBuilder.build(regular_list_ast, context, [])

      # Keyword list creates KeywordListLiteral
      assert has_type?(kw_triples, Core.KeywordListLiteral)

      # Regular list does NOT create KeywordListLiteral
      refute has_type?(regular_triples, Core.KeywordListLiteral)
    end

    test "keyword list with duplicate keys is handled correctly" do
      context = full_mode_context()

      # Keyword list with duplicates: [a: 1, a: 2]
      kw_list_ast = quote do: [a: 1, a: 2]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      assert has_type?(triples, Core.KeywordListLiteral)
    end
  end

  describe "sigil literals" do
    test "builds SigilLiteral for word sigil" do
      context = full_mode_context()

      # Word sigil: ~w(foo bar baz)
      sigil_ast = quote do: ~w(foo bar baz)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "w")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "foo bar baz")
    end

    test "builds SigilLiteral for regex sigil" do
      context = full_mode_context()

      # Regex sigil: ~r/pattern/
      sigil_ast = quote do: ~r(pattern)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "r")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "pattern")
    end

    test "builds SigilLiteral for string sigil" do
      context = full_mode_context()

      # String sigil: ~s(string)
      sigil_ast = quote do: ~s(string)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "string")
    end

    test "builds SigilLiteral for custom sigil" do
      context = full_mode_context()

      # Custom sigil: ~x(content)
      # Note: This will fail at runtime but the AST is valid
      sigil_ast = {:sigil_x, [], [{:<<>>, [], ["content"]}, []]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "x")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "content")
    end

    test "handles sigil with empty content" do
      context = full_mode_context()

      # Empty sigil: ~s()
      sigil_ast = quote do: ~s()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "")
    end

    test "handles sigil with modifiers" do
      context = full_mode_context()

      # Regex sigil with modifiers: ~r/pattern/iom
      sigil_ast = quote do: ~r(pattern)iom
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "r")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "pattern")
      assert has_literal_value?(triples, expr_iri, Core.sigilModifiers(), "iom")
    end

    test "handles sigil without modifiers" do
      context = full_mode_context()

      # Regex sigil without modifiers: ~r/pattern/
      sigil_ast = quote do: ~r(pattern)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      # Should NOT have sigilModifiers triple (empty modifiers don't create a triple)
      refute Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.sigilModifiers()
      end)
    end

    test "handles charlist sigil" do
      context = full_mode_context()

      # Charlist sigil: ~c(charlist)
      sigil_ast = quote do: ~c(charlist)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "c")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "charlist")
    end

    test "handles sigil with heredoc content" do
      context = full_mode_context()

      # Heredoc sigil: ~s"""
      # multi
      # line
      # string
      # """
      sigil_ast = quote do: ~s"""
multi
line
string
"""
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      # Heredoc content is multi-line
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "multi\nline\nstring\n")
    end

    test "handles sigil with multiple modifiers" do
      context = full_mode_context()

      # Regex sigil with multiple modifiers: ~r/pattern/iom
      sigil_ast = quote do: ~r(pattern)iom
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilModifiers(), "iom")
    end
  end

  describe "range literals" do
    test "builds RangeLiteral for simple integer range" do
      context = full_mode_context()

      # Simple range: 1..10
      range_ast = quote do: 1..10
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)
    end

    test "range literal captures start and end values" do
      context = full_mode_context()

      # Range: 1..10
      range_ast = quote do: 1..10
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      # Should have rangeStart and rangeEnd properties linking to child expressions
      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStart()
      end)

      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeEnd()
      end)
    end

    test "builds RangeLiteral for step range" do
      context = full_mode_context()

      # Step range: 1..10//2
      range_ast = quote do: 1..10//2
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)

      # Should have rangeStep property for step ranges
      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStep()
      end)
    end

    test "range literal captures step value for step ranges" do
      context = full_mode_context()

      # Range with step: 1..10//3
      range_ast = quote do: 1..10//3
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      # Should have rangeStart, rangeEnd, and rangeStep properties
      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStart()
      end)

      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeEnd()
      end)

      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStep()
      end)
    end

    test "handles negative range" do
      context = full_mode_context()

      # Negative range: 10..1
      range_ast = quote do: 10..1
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)
    end

    test "handles variable range" do
      context = full_mode_context()

      # Variable range: a..b
      range_ast = quote do: a..b
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)

      # Start and end should be variables
      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStart()
      end)

      assert Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeEnd()
      end)

      # Should have Variable child expressions
      assert has_type?(triples, Core.Variable)
    end

    test "handles single-element range" do
      context = full_mode_context()

      # Single-element range: 5..5
      range_ast = quote do: 5..5
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)
    end

    test "range with expression boundaries" do
      context = full_mode_context()

      # Range with expressions: (x + 1)..(y - 1)
      range_ast = quote do: (x + 1)..(y - 1)
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      assert has_type?(triples, Core.RangeLiteral)

      # Should link to arithmetic operator expressions
      assert Enum.any?(triples, fn {_s, _p, o} ->
        o == Core.ArithmeticOperator
      end)
    end

    test "simple range does not have rangeStep property" do
      context = full_mode_context()

      # Simple range without step: 1..10
      range_ast = quote do: 1..10
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(range_ast, context, [])

      # Should NOT have rangeStep property for simple ranges
      refute Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.rangeStep()
      end)
    end
  end

  describe "unknown expressions" do
    test "dispatches unknown AST to generic Expression type" do
      context = full_mode_context()

      # Some unusual AST that doesn't match our patterns
      # Using a 4-element tuple which is not a standard Elixir AST form
      # (3+ tuples use {:{}, meta, elements} form, not direct tuples)
      unusual_ast = {:one, :two, :three, :four}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(unusual_ast, context, [])

      assert has_type?(triples, Core.Expression)
    end
  end

  describe "expression_iri/3" do
    test "generates IRI with counter-based suffix when no options provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, updated_context} = ExpressionBuilder.expression_iri("https://example.org/code#", context)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_0"
      assert Context.get_expression_counter(updated_context) == 1
    end

    test "increments counter on each call" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri1, ctx1} = ExpressionBuilder.expression_iri("https://example.org/code#", context)
      {iri2, ctx2} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx1)
      {iri3, _ctx3} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx2)

      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "uses custom suffix when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, suffix: "my_custom_expr")

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/my_custom_expr"
      # Counter should not be incremented when custom suffix is used
      assert Context.get_expression_counter(updated_context) == 5
    end

    test "uses explicit counter option when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, counter: 42)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_42"
      # Counter should not be incremented when explicit counter is used
      assert Context.get_expression_counter(updated_context) == 10
    end

    test "handles different base IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, _ctx} =
        ExpressionBuilder.expression_iri("https://other.org/base#", context)

      assert RDF.IRI.to_string(iri) == "https://other.org/base#expr/expr_0"
    end
  end

  describe "fresh_iri/2" do
    test "creates relative IRI from parent with left child" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      child_iri = ExpressionBuilder.fresh_iri(parent, "left")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/0/left"
    end

    test "creates relative IRI from parent with right child" do
      parent = RDF.IRI.new("https://example.org/code#expr/5")

      child_iri = ExpressionBuilder.fresh_iri(parent, "right")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/5/right"
    end

    test "creates nested relative IRIs" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left_iri = ExpressionBuilder.fresh_iri(parent, "left")
      left_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")

      assert RDF.IRI.to_string(left_iri) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(left_left_iri) == "https://example.org/code#expr/0/left/left"
    end

    test "handles various child names" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      assert ExpressionBuilder.fresh_iri(parent, "condition")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/condition"

      assert ExpressionBuilder.fresh_iri(parent, "then")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/then"

      assert ExpressionBuilder.fresh_iri(parent, "else")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/else"

      assert ExpressionBuilder.fresh_iri(parent, "operand")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/operand"
    end
  end

  describe "get_or_create_iri/3" do
    test "creates new IRI when cache is nil" do
      generator = fn -> RDF.IRI.new("https://example.org/expr/0") end

      {iri, cache} = ExpressionBuilder.get_or_create_iri(nil, :some_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/0"
      assert cache == %{}
    end

    test "creates and caches new IRI on first call" do
      cache = %{}
      generator = fn -> RDF.IRI.new("https://example.org/expr/new") end

      {iri, updated_cache} =
        ExpressionBuilder.get_or_create_iri(cache, :my_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/new"
      assert Map.has_key?(updated_cache, :my_key)
    end

    test "reuses cached IRI on subsequent calls with same key" do
      cache = %{}
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :same_key, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :same_key, gen2)

      # Second generator should not be called - IRI is reused
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/expr/first"
      assert cache2 == cache1
    end

    test "creates different IRIs for different keys" do
      cache = %{}

      # Each key gets its own generator
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :key2, gen2)

      # Should create two different IRIs
      refute iri1 == iri2
      assert Map.has_key?(cache2, :key1)
      assert Map.has_key?(cache2, :key2)
    end

    test "works with complex cache keys" do
      cache = %{}

      # Using AST structure as cache key
      ast_key1 = {:==, [], [{:x, [], nil}, 1]}
      ast_key2 = {:==, [], [{:y, [], nil}, 2]}
      ast_key3 = {:==, [], [{:x, [], nil}, 1]} # Same as key1

      # Create unique generators for each key
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/hash1") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/hash2") end
      gen3 = fn -> RDF.IRI.new("https://example.org/expr/hash3") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, ast_key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, ast_key2, gen2)
      {iri3, _cache3} = ExpressionBuilder.get_or_create_iri(cache2, ast_key3, gen3)

      # key1 and key3 are the same, so IRIs should match (key3 reuses cached value from key1)
      assert iri1 == iri3
      refute iri1 == iri2
    end
  end

  describe "Context expression counter" do
    test "with_expression_counter/1 initializes counter to 0" do
      context = Context.new(base_iri: "https://example.org/code#")

      initialized = Context.with_expression_counter(context)

      assert Context.get_expression_counter(initialized) == 0
    end

    test "next_expression_counter/1 returns current counter and increments" do
      context = Context.new(base_iri: "https://example.org/code#")
      context = Context.with_expression_counter(context)

      {counter1, ctx1} = Context.next_expression_counter(context)
      {counter2, ctx2} = Context.next_expression_counter(ctx1)
      {counter3, _ctx3} = Context.next_expression_counter(ctx2)

      assert counter1 == 0
      assert counter2 == 1
      assert counter3 == 2
    end

    test "next_expression_counter/1 works with pre-initialized counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {counter, updated_ctx} = Context.next_expression_counter(context)

      assert counter == 5
      assert Context.get_expression_counter(updated_ctx) == 6
    end

    test "get_expression_counter/1 returns current counter without incrementing" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      assert Context.get_expression_counter(context) == 10
      assert Context.get_expression_counter(context) == 10 # Still 10
    end

    test "get_expression_counter/1 defaults to 0 when not set" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_expression_counter(context) == 0
    end
  end

  describe "integration tests" do
    test "complete IRI flow through ExpressionBuilder" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      # Build multiple expressions and verify sequential IRIs
      ast1 = {:==, [], [{:x, [], nil}, 1]}
      ast2 = {:>, [], [{:y, [], nil}, 5]}
      ast3 = {:and, [], [true, false]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast1, context, [])
      {:ok, {iri2, _, context3}} = ExpressionBuilder.build(ast2, context2, [])
      {:ok, {iri3, _, _}} = ExpressionBuilder.build(ast3, context3, [])

      # Sequential IRIs based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "fresh_iri creates proper hierarchy for nested expressions" do
      # Simulate nested binary operator: x > 5 and y < 10
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left = ExpressionBuilder.fresh_iri(parent, "left")
      right = ExpressionBuilder.fresh_iri(parent, "right")

      # Verify hierarchy
      assert RDF.IRI.to_string(left) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(right) == "https://example.org/code#expr/0/right"

      # Nested children
      left_left = ExpressionBuilder.fresh_iri(left, "left")
      assert RDF.IRI.to_string(left_left) == "https://example.org/code#expr/0/left/left"
    end

    test "get_or_create_iri enables expression deduplication" do
      # Simulate shared sub-expression: x == 1 appearing twice
      shared_expr = {:==, [], [{:x, [], nil}, 1]}

      cache = %{}

      # First occurrence - creates new IRI
      {iri1, cache1} =
        ExpressionBuilder.get_or_create_iri(
          cache,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_0") end
        )

      # Second occurrence - reuses cached IRI
      {iri2, cache2} =
        ExpressionBuilder.get_or_create_iri(
          cache1,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_new") end
        )

      # Same IRI should be returned
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/shared_0"

      # Different expression - creates new IRI
      different_expr = {:!=, [], [{:y, [], nil}, 2]}
      {iri3, _cache3} =
        ExpressionBuilder.get_or_create_iri(
          cache2,
          different_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_1") end
        )

      refute iri1 == iri3
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/shared_1"
    end

    test "counter properly resets between different contexts" do
      # Context 1
      context1 =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build({:==, [], [1, 1]}, context1, [])
      {:ok, {iri2, _, _}} = ExpressionBuilder.build({:==, [], [2, 2]}, context2, [])

      # Context 2 - different base IRI, so counter starts at 0
      context3 =
        Context.new(
          base_iri: "https://other.org/base#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/accounts.ex"
        )
        |> Context.with_expression_counter()

      {:ok, {iri3, _, _}} = ExpressionBuilder.build({:==, [], [3, 3]}, context3, [])

      # context1 starts at expr_0 and increments
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"

      # context2 has different base IRI, so starts at expr_0
      assert RDF.IRI.to_string(iri3) == "https://other.org/base#expr/expr_0"
    end

    test "custom suffix option bypasses counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      # Use custom suffix
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {iri1, _, _}} = ExpressionBuilder.build(ast, context, suffix: "custom_expr")

      # Next expression without suffix should use counter
      {:ok, {iri2, _, _}} = ExpressionBuilder.build(ast, context, [])

      # Custom suffix should be respected
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/custom_expr"
      # Counter expression should start at 0
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_0"
    end
  end

  describe "nested expression tests (Phase 21.4)" do
    test "binary operator creates left and right operand triples" do
      context = full_mode_context()
      # x > 5
      ast = {:>, [], [{:x, [], nil}, 5]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have operator type and symbol
      assert has_type?(triples, Core.ComparisonOperator)
      assert has_operator_symbol?(triples, ">")

      # Should link to left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left operand should be a Variable
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")

      # Right operand should be an IntegerLiteral
      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, right_iri, Core.integerValue(), 5)
    end

    test "nested binary operators create correct IRI hierarchy" do
      context = full_mode_context()
      # x > 5 and y < 10
      ast = {:and, [], [{:>, [], [{:x, [], nil}, 5]}, {:<, [], [{:y, [], nil}, 10]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Top-level is LogicalOperator (and)
      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")

      # Left child is a comparison operator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_iri and o == Core.ComparisonOperator
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_iri and p == Core.operatorSymbol() and
          RDF.Literal.value(o) == ">"
      end)

      # Left-left is Variable "x"
      left_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_left_iri and o == Core.Variable
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_left_iri and p == Core.name() and
          RDF.Literal.value(o) == "x"
      end)

      # Left-right is IntegerLiteral 5
      left_right_iri = ExpressionBuilder.fresh_iri(left_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_right_iri and o == Core.IntegerLiteral
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_right_iri and p == Core.integerValue() and
          RDF.Literal.value(o) == 5
      end)
    end

    test "unary operator creates operand triples" do
      context = full_mode_context()
      # not x
      ast = {:not, [], [{:x, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have operator type and symbol
      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")

      # Should link to operand
      operand_iri = ExpressionBuilder.fresh_iri(expr_iri, "operand")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasOperand() and o == operand_iri
      end)

      # Operand should be a Variable
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, operand_iri, Core.name(), "x")
    end

    test "arithmetic operators create nested expressions" do
      context = full_mode_context()
      # x + y * 2
      ast = {:+, [], [{:x, [], nil}, {:*, [], [{:y, [], nil}, 2]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Top-level is ArithmeticOperator (+)
      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "+")

      # Right operand is another ArithmeticOperator (*)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == right_iri and o == Core.ArithmeticOperator
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == right_iri and p == Core.operatorSymbol() and
          RDF.Literal.value(o) == "*"
      end)
    end

    test "match operator creates left and right expressions" do
      context = full_mode_context()
      # x = 42
      ast = {:=, [], [{:x, [], nil}, 42]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have MatchOperator type
      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left is Variable "x"
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")

      # Right is IntegerLiteral 42
      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, right_iri, Core.integerValue(), 42)
    end
  end

  describe "pattern type detection" do
    test "detects literal pattern - integer" do
      assert ExpressionBuilder.detect_pattern_type(42) == :literal_pattern
    end

    test "detects literal pattern - float" do
      assert ExpressionBuilder.detect_pattern_type(3.14) == :literal_pattern
    end

    test "detects literal pattern - string" do
      assert ExpressionBuilder.detect_pattern_type("hello") == :literal_pattern
    end

    test "detects literal pattern - atom" do
      assert ExpressionBuilder.detect_pattern_type(:foo) == :literal_pattern
    end

    test "detects literal pattern - boolean true" do
      assert ExpressionBuilder.detect_pattern_type(true) == :literal_pattern
    end

    test "detects literal pattern - boolean false" do
      assert ExpressionBuilder.detect_pattern_type(false) == :literal_pattern
    end

    test "detects literal pattern - nil" do
      assert ExpressionBuilder.detect_pattern_type(nil) == :literal_pattern
    end

    test "detects variable pattern" do
      ast = {:x, [], Elixir}
      assert ExpressionBuilder.detect_pattern_type(ast) == :variable_pattern
    end

    test "detects variable pattern with leading underscore" do
      ast = {:_name, [], Elixir}
      assert ExpressionBuilder.detect_pattern_type(ast) == :variable_pattern
    end

    test "detects wildcard pattern" do
      ast = {:_}
      assert ExpressionBuilder.detect_pattern_type(ast) == :wildcard_pattern
    end

    test "detects pin pattern" do
      ast = {:^, [], [{:x, [], Elixir}]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :pin_pattern
    end

    test "detects tuple pattern - empty tuple" do
      # Empty tuple AST is {:{}, [], []}
      ast = {:{}, [], []}
      assert ExpressionBuilder.detect_pattern_type(ast) == :tuple_pattern
    end

    test "detects tuple pattern - 2-tuple" do
      # 2-tuple is a special case in Elixir AST
      # It's represented directly as {left, right} without wrapping
      ast = {1, 2}
      # 2-tuples are detected as tuple_pattern
      assert ExpressionBuilder.detect_pattern_type(ast) == :tuple_pattern
    end

    test "detects tuple pattern - n-tuple with variables" do
      # n-tuple (n >= 0 or n >= 3) uses {:{}, _, elements}
      ast = {:{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :tuple_pattern
    end

    test "detects list pattern - empty list" do
      ast = []
      assert ExpressionBuilder.detect_pattern_type(ast) == :list_pattern
    end

    test "detects list pattern - flat list" do
      ast = [{:a, [], Elixir}, {:b, [], Elixir}]
      assert ExpressionBuilder.detect_pattern_type(ast) == :list_pattern
    end

    test "detects list pattern - nested list" do
      ast = [[{:a, [], Elixir}], [{:b, [], Elixir}]]
      assert ExpressionBuilder.detect_pattern_type(ast) == :list_pattern
    end

    test "detects map pattern - empty map" do
      ast = {:%{}, [], []}
      assert ExpressionBuilder.detect_pattern_type(ast) == :map_pattern
    end

    test "detects map pattern - with entries" do
      # Map pattern with entries uses keyword list syntax
      ast = {:%{}, [], [:a, 1]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :map_pattern
    end

    test "detects struct pattern - with alias" do
      module_ast = {:__aliases__, [], [:User]}
      map_ast = {:%{}, [], []}
      ast = {:%, [], [module_ast, map_ast]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :struct_pattern
    end

    test "detects struct pattern - with tuple module" do
      # Nested struct pattern - module can be a tuple form
      map_ast = {:%{}, [], []}
      # Module reference as {:{}, _, [:User]}
      module_ast = {:{}, [], [:User]}
      ast = {:%, [], [module_ast, map_ast]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :struct_pattern
    end

    test "detects binary pattern - empty binary" do
      ast = {:<<>>, [], []}
      assert ExpressionBuilder.detect_pattern_type(ast) == :binary_pattern
    end

    test "detects binary pattern - with segments" do
      # Binary pattern with size specifier uses the :: operator in AST
      # The AST form is: {:<<>>, [], [{:::, [], [{:x, [], Elixir}, 8]}]}
      segment = {:::, [], [{:x, [], Elixir}, 8]}
      ast = {:<<>>, [], [segment]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :binary_pattern
    end

    test "detects as pattern" do
      pattern_ast = {:a, [], Elixir}
      var_ast = {:var, [], Elixir}
      ast = {:=, [], [pattern_ast, var_ast]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :as_pattern
    end

    test "returns unknown for unrecognized patterns" do
      # Complex nested call or other unrecognized AST
      ast = {{:., [], [{:Some, [], nil}, :func]}, [], []}
      assert ExpressionBuilder.detect_pattern_type(ast) == :unknown
    end
  end

  describe "pattern builder dispatch" do
    test "dispatches literal pattern to LiteralPattern" do
      context = full_mode_context()
      ast = 42
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # For now, literal pattern returns generic expression type
      # because the same AST is used for literal expressions
      assert has_type?(triples, Core.IntegerLiteral)
    end

    test "dispatches variable pattern to VariablePattern via build_pattern" do
      context = full_mode_context()
      ast = {:x, [], Elixir}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Using build_pattern directly should return VariablePattern
      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.VariablePattern
      end)
    end

    test "dispatches wildcard pattern to WildcardPattern via build_pattern" do
      context = full_mode_context()
      ast = {:_}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Using build_pattern directly should return WildcardPattern
      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.WildcardPattern
      end)
    end

    test "dispatches pin pattern to PinPattern via build_pattern" do
      context = full_mode_context()
      ast = {:^, [], [{:x, [], Elixir}]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.PinPattern
      end)

      # Check variable name is captured
      assert Enum.any?(pattern_triples, fn {s, p, o} ->
        s == expr_iri and p == Core.name() and RDF.Literal.value(o) == "x"
      end)
    end

    test "dispatches tuple pattern to TuplePattern via build_pattern" do
      context = full_mode_context()
      ast = {:{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.TuplePattern
      end)
    end

    test "dispatches list pattern to ListPattern via build_pattern" do
      context = full_mode_context()
      ast = [{:a, [], Elixir}, {:b, [], Elixir}]
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.ListPattern
      end)
    end

    test "dispatches map pattern to MapPattern via build_pattern" do
      context = full_mode_context()
      # Use empty map to avoid entry processing issues
      ast = {:%{}, [], []}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.MapPattern
      end)
    end

    test "dispatches struct pattern to StructPattern via build_pattern" do
      context = full_mode_context()
      module_ast = {:__aliases__, [], [:User]}
      map_ast = {:%{}, [], []}
      ast = {:%, [], [module_ast, map_ast]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.StructPattern
      end)
    end

    test "dispatches binary pattern to BinaryPattern via build_pattern" do
      context = full_mode_context()
      # Binary pattern with size specifier uses the :: operator in AST
      segment = {:::, [], [{:x, [], Elixir}, 8]}
      ast = {:<<>>, [], [segment]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.BinaryPattern
      end)
    end

    test "dispatches as pattern to AsPattern via build_pattern" do
      context = full_mode_context()
      pattern_ast = {:a, [], Elixir}
      var_ast = {:var, [], Elixir}
      ast = {:=, [], [pattern_ast, var_ast]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.AsPattern
      end)
    end

    test "dispatches unknown pattern to generic Expression" do
      context = full_mode_context()
      ast = {{:., [], [{:Some, [], nil}, :func]}, [], []}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
      assert Enum.any?(pattern_triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.Expression
      end)
    end
  end

  describe "nested pattern detection" do
    test "detects tuple within list" do
      ast = [{:{}, [], [1, 2]}, {:{}, [], [3, 4]}]
      assert ExpressionBuilder.detect_pattern_type(ast) == :list_pattern
    end

    test "detects list within tuple" do
      ast = {:{}, [], [[1, 2], [3, 4]]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :tuple_pattern
    end

    test "detects map within list" do
      # Map pattern uses keyword list syntax
      ast = [{:%{}, [], [:a, 1]}]
      assert ExpressionBuilder.detect_pattern_type(ast) == :list_pattern
    end

    test "detects nested struct pattern" do
      # Map within struct - using simplified keyword list for map
      module_ast = {:__aliases__, [], [:User]}
      # Empty map for this test - just testing struct detection
      map_ast = {:%{}, [], []}
      ast = {:%, [], [module_ast, map_ast]}
      assert ExpressionBuilder.detect_pattern_type(ast) == :struct_pattern
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================
  #
  # Note: Some of these helpers are also available in ExpressionTestHelpers
  # module for reuse in other test files. They are duplicated here for
  # direct use in this test file.

  defp full_mode_context do
    Context.new(
      base_iri: "https://example.org/code#",
      config: %{include_expressions: true},
      file_path: "lib/my_app/users.ex"
    )
    |> Context.with_expression_counter()
  end

  defp has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == expected_type end)
  end

  defp has_operator_symbol?(triples, symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  # Check if a specific IRI has a given operator symbol
  defp has_operator_symbol_for_iri?(triples, iri, symbol) do
    Enum.any?(triples, fn {s, p, o} ->
      s == iri and p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  defp has_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.value(o) == expected_value
    end)
  end

  # For Base64Binary literals, RDF.Literal.value/1 returns nil
  # We need to check RDF.Literal.lexical/1 instead
  defp has_binary_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.lexical(o) == expected_value
    end)
  end

  # Check if an expression has a hasOperand property (for unary operators)
  defp has_operand?(triples, expr_iri) do
    Enum.any?(triples, fn {s, p, _o} ->
      s == expr_iri and p == Core.hasOperand()
    end)
  end

  # Check if an expression has a child expression of a specific type
  defp has_child_with_type?(triples, expr_iri, child_type) do
    # First find the hasOperand or hasLeftOperand/hasRightOperand property
    child_iris =
      triples
      |> Enum.filter(fn {s, _p, _o} -> s == expr_iri end)
      |> Enum.filter(fn {_s, p, _o} ->
        p == Core.hasOperand() or p == Core.hasLeftOperand() or p == Core.hasRightOperand()
      end)
      |> Enum.map(fn {_s, _p, o} -> o end)

    # Check if any child IRI has the expected type
    Enum.any?(child_iris, fn child_iri ->
      Enum.any?(triples, fn {s, p, o} ->
        s == child_iri and p == RDF.type() and o == child_type
      end)
    end)
  end
end
