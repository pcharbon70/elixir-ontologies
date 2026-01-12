defmodule ElixirOntologies.Builders.ExpressionBuilderIntegrationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder}
  alias ElixirOntologies.NS.Core

  @moduledoc """
  Integration tests for ExpressionBuilder.

  These tests verify complex multi-expression scenarios and the generated
  RDF structure. They test expression building in more realistic scenarios
  than the unit tests, focusing on:
  1. Multiple independent expressions
  2. Nested expression hierarchies
  3. Context threading between builds
  4. Cross-expression type queries
  """

  describe "multi-expression scenarios" do
    setup do
      context =
        [
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        ]
        |> Context.new()
        |> Context.with_expression_counter()

      {:ok, context: context}
    end

    test "build and track multiple independent expressions with context threading", %{context: context} do
      # Build multiple independent expressions, threading the context
      {:ok, {_expr_iri1, triples1, context1}} =
        ExpressionBuilder.build({:+, [], [1, 2]}, context, [])

      {:ok, {_expr_iri2, triples2, context2}} =
        ExpressionBuilder.build({:==, [], [5, 5]}, context1, [])

      {:ok, {_expr_iri3, triples3, _context3}} =
        ExpressionBuilder.build({:&, [], [1]}, context2, [])

      # Each expression should have its own IRI
      expr_iris =
        [triples1, triples2, triples3]
        |> Enum.flat_map(fn triples ->
          triples
          |> Enum.filter(fn {_s, p, o} ->
            p == RDF.type() and
              (o == Core.ArithmeticOperator or
                 o == Core.ComparisonOperator or o == Core.CaptureOperator)
          end)
          |> Enum.map(fn {s, _p, _o} -> s end)
        end)

      assert length(expr_iris) == 3

      # Verify we have distinct IRIs for each expression
      assert Enum.uniq(expr_iris) |> length() == 3
    end

    test "build nested expression hierarchy", %{context: context} do
      # Build a complex nested expression: (1 + 2) == (3 * 4)
      {:ok, {_expr_iri, triples, _context}} =
        ExpressionBuilder.build(
          {:==, [], [{:+, [], [1, 2]}, {:*, [], [3, 4]}]},
          context,
          []
        )

      # Count all operators in the hierarchy
      operators =
        Enum.filter(triples, fn {_s, p, o} ->
          p == RDF.type() and
            (o == Core.ComparisonOperator or o == Core.ArithmeticOperator)
        end)

      # Should have comparison operator (==), plus operator (+), multiply operator (*)
      assert length(operators) == 3

      # Verify root is comparison operator
      assert Enum.any?(triples, fn {s, p, o} ->
        p == RDF.type() and o == Core.ComparisonOperator and
          Enum.any?(triples, fn {s2, p2, o2} ->
            s2 == s and p2 == Core.operatorSymbol() and RDF.Literal.value(o2) == "=="
          end)
      end)

      # Verify left operand is addition
      assert Enum.any?(triples, fn {s, p, o} ->
        p == RDF.type() and o == Core.ArithmeticOperator and
          Enum.any?(triples, fn {s2, p2, o2} ->
            s2 == s and p2 == Core.operatorSymbol() and RDF.Literal.value(o2) == "+"
          end)
      end)

      # Verify right operand is multiplication
      assert Enum.any?(triples, fn {s, p, o} ->
        p == RDF.type() and o == Core.ArithmeticOperator and
          Enum.any?(triples, fn {s2, p2, o2} ->
            s2 == s and p2 == Core.operatorSymbol() and RDF.Literal.value(o2) == "*"
          end)
      end)
    end

    test "query expression types across multiple builds", %{context: context} do
      # Build various expression types, threading context
      {:ok, {_, triples1, context1}} = ExpressionBuilder.build({:+, [], [1, 2]}, context, [])
      {:ok, {_, triples2, context2}} = ExpressionBuilder.build({:==, [], [1, 2]}, context1, [])
      {:ok, {_, triples3, context3}} = ExpressionBuilder.build({:and, [], [true, false]}, context2, [])
      {:ok, {_, triples4, _context4}} = ExpressionBuilder.build({:&, [], [1]}, context3, [])

      all_triples = triples1 ++ triples2 ++ triples3 ++ triples4

      # Count arithmetic operators
      arithmetic_count =
        Enum.count(all_triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ArithmeticOperator
        end)

      assert arithmetic_count >= 1

      # Count comparison operators
      comparison_count =
        Enum.count(all_triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ComparisonOperator
        end)

      assert comparison_count >= 1

      # Count logical operators
      logical_count =
        Enum.count(all_triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.LogicalOperator
        end)

      assert logical_count >= 1

      # Count capture operators
      capture_count =
        Enum.count(all_triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.CaptureOperator
        end)

      assert capture_count >= 1
    end

    test "deeply nested expression hierarchy", %{context: context} do
      # Build: (1 + (2 * 3)) == (4 - (5 / 2))
      ast =
        {:==, [], [{:+, [], [1, {:*, [], [2, 3]}]}, {:-, [], [4, {:/, [], [5, 2]}]}]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      # Count all operators (==, +, *, -, /)
      operators =
        Enum.filter(triples, fn {_s, p, o} ->
          p == RDF.type() and
            (o == core_type?(Core.ComparisonOperator) or
               o == core_type?(Core.ArithmeticOperator))
        end)

      # Should have 5 operators: ==, +, *, -, /
      assert length(operators) == 5
    end

    test "mixed operator types in single expression tree", %{context: context} do
      # Build: (1 > 0) and (2 < 3)
      ast = {:and, [], [{:>, [], [1, 0]}, {:<, [], [2, 3]}]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      # Should have logical operator (and) and two comparison operators (>, <)
      logical_ops =
        Enum.filter(triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.LogicalOperator
        end)

      assert length(logical_ops) == 1

      comparison_ops =
        Enum.filter(triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ComparisonOperator
        end)

      assert length(comparison_ops) == 2
    end
  end

  describe "capture operator variants" do
    setup do
      context =
        [
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        ]
        |> Context.new()
        |> Context.with_expression_counter()

      {:ok, context: context}
    end

    test "argument index capture operators", %{context: context} do
      # Build &1, &2, &3
      {:ok, {_, triples1, context1}} = ExpressionBuilder.build({:&, [], [1]}, context, [])
      {:ok, {_, triples2, context2}} = ExpressionBuilder.build({:&, [], [2]}, context1, [])
      {:ok, {_, triples3, _context3}} = ExpressionBuilder.build({:&, [], [3]}, context2, [])

      all_triples = triples1 ++ triples2 ++ triples3

      # Verify each has captureIndex property
      capture_indices =
        Enum.flat_map(all_triples, fn {s, _p, o} ->
          if o == Core.CaptureOperator do
            Enum.filter(all_triples, fn {s2, p2, o2} ->
              s2 == s and p2 == Core.captureIndex() and match?(%RDF.Literal{}, o2)
            end)
            |> Enum.map(fn {_s, _p, o} -> RDF.Literal.value(o) end)
          else
            []
          end
        end)

      assert Enum.sort(capture_indices) == [1, 2, 3]
    end

    test "function reference capture operators", %{context: context} do
      # Build &Enum.map/2
      function_ref = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}
      ast = {:&, [], [{:/, [], [function_ref, 2]}]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      # Find the capture operator
      [capture_op_iri] =
        Enum.filter(triples, fn {_s, p, o} -> p == RDF.type() and o == Core.CaptureOperator end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      # Verify module name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == capture_op_iri and p == Core.captureModuleName() and RDF.Literal.value(o) == "Enum"
      end)

      # Verify function name
      assert Enum.any?(triples, fn {s, p, o} ->
        s == capture_op_iri and p == Core.captureFunctionName() and
          RDF.Literal.value(o) == "map"
      end)

      # Verify arity
      assert Enum.any?(triples, fn {s, p, o} ->
        s == capture_op_iri and p == Core.captureArity() and RDF.Literal.value(o) == 2
      end)
    end
  end

  describe "operator categories" do
    setup do
      context =
        [
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        ]
        |> Context.new()
        |> Context.with_expression_counter()

      {:ok, context: context}
    end

    test "all comparison operators", %{context: context} do
      comparison_ops = [:==, :!=, :===, :!==, :<, :>, :<=, :>=]

      {_final_context, all_triples} =
        Enum.reduce(comparison_ops, {context, []}, fn op, {ctx, acc} ->
          {:ok, {_, triples, new_ctx}} = ExpressionBuilder.build({op, [], [1, 2]}, ctx, [])
          {new_ctx, acc ++ triples}
        end)

      # Verify all comparison operators were created
      comparison_exprs =
        Enum.filter(all_triples, fn {_s, p, o} -> p == RDF.type() and o == Core.ComparisonOperator end)

      assert length(comparison_exprs) == length(comparison_ops)
    end

    test "all arithmetic operators", %{context: context} do
      arithmetic_ops = [:+, :-, :*, :/]

      {_final_context, all_triples} =
        Enum.reduce(arithmetic_ops, {context, []}, fn op, {ctx, acc} ->
          {:ok, {_, triples, new_ctx}} = ExpressionBuilder.build({op, [], [1, 2]}, ctx, [])
          {new_ctx, acc ++ triples}
        end)

      # Verify all arithmetic operators were created
      arithmetic_exprs =
        Enum.filter(all_triples, fn {_s, p, o} -> p == RDF.type() and o == Core.ArithmeticOperator end)

      assert length(arithmetic_exprs) == length(arithmetic_ops)
    end

    test "all logical operators", %{context: context} do
      # Binary logical operators
      binary_ops = [:and, :or]

      {ctx1, all_triples} =
        Enum.reduce(binary_ops, {context, []}, fn op, {ctx, acc} ->
          {:ok, {_, triples, new_ctx}} =
            ExpressionBuilder.build({op, [], [true, false]}, ctx, [])

          {new_ctx, acc ++ triples}
        end)

      # Unary logical operator (not)
      {:ok, {_, not_triples, _ctx2}} = ExpressionBuilder.build({:not, [], [true]}, ctx1, [])

      all_triples = all_triples ++ not_triples

      # Verify all logical operators were created
      logical_exprs =
        Enum.filter(all_triples, fn {_s, p, o} -> p == RDF.type() and o == Core.LogicalOperator end)

      assert length(logical_exprs) == 3
    end
  end

  describe "special operators" do
    setup do
      context =
        [
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        ]
        |> Context.new()
        |> Context.with_expression_counter()

      {:ok, context: context}
    end

    test "string concatenation operator", %{context: context} do
      {:ok, {_expr_iri, triples, _context}} =
        ExpressionBuilder.build({:<>, [], ["hello", "world"]}, context, [])

      # Verify StringConcatOperator type
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == RDF.type() and o == Core.StringConcatOperator
      end)

      # Verify operator symbol
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.operatorSymbol() and RDF.Literal.value(o) == "<>"
      end)
    end

    test "in operator", %{context: context} do
      {:ok, {_expr_iri, triples, _context}} =
        ExpressionBuilder.build({:in, [], [1, [1, 2, 3]]}, context, [])

      # Verify InOperator type
      assert Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == Core.InOperator end)

      # Verify operator symbol
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.operatorSymbol() and RDF.Literal.value(o) == "in"
      end)
    end

    test "unary plus operator", %{context: context} do
      {:ok, {_expr_iri, triples, _context}} =
        ExpressionBuilder.build({:+, [], [5]}, context, [])

      # Verify ArithmeticOperator type (unary plus is typed as arithmetic)
      assert Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == Core.ArithmeticOperator end)

      # Verify operator symbol
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.operatorSymbol() and RDF.Literal.value(o) == "+"
      end)

      # Verify unary operators have hasOperand property (not hasLeftOperand/hasRightOperand)
      assert Enum.any?(triples, fn {s, p, _o} ->
        p == Core.hasOperand()
      end)
    end

    test "unary minus operator", %{context: context} do
      {:ok, {_expr_iri, triples, _context}} =
        ExpressionBuilder.build({:-, [], [5]}, context, [])

      # Verify ArithmeticOperator type (unary minus is typed as arithmetic)
      assert Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == Core.ArithmeticOperator end)

      # Verify operator symbol
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.operatorSymbol() and RDF.Literal.value(o) == "-"
      end)
    end
  end

  # Helper to match core types (handles both IRIs and terms)
  defp core_type?(type) when is_atom(type), do: type
  defp core_type?(iri), do: iri
end
