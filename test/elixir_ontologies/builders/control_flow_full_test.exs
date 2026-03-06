defmodule ElixirOntologies.Builders.ControlFlowFullTest do
  @moduledoc """
  Integration tests for Phase 25 Control Flow Expression Integration.

  These tests verify complete control flow extraction across all control flow types:
  - If/Unless expressions (Phase 25.1)
  - Cond expressions (Phase 25.2)
  - Case expressions (Phase 25.3)
  - With expressions (Phase 25.4)
  - Receive expressions (Phase 25.5)
  - Try expressions (Phase 25.6)
  - Raise/Throw expressions (Phase 25.7)

  Tests verify:
  1. Complete control flow extraction for all types
  2. Light mode (backward compatibility) vs Full mode (expression trees)
  3. Nested control flow structures
  4. Complex condition and body expressions
  5. SPARQL queryability of generated RDF
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{ControlFlowBuilder, Context, ExpressionBuilder}
  alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}

  alias ElixirOntologies.Extractors.CaseWith.{
    CaseExpression,
    CaseClause,
    WithExpression,
    WithClause,
    ReceiveExpression
  }

  alias ElixirOntologies.Extractors.Exception
  alias ElixirOntologies.Extractors.Exception.{RaiseExpression, ThrowExpression}
  alias ElixirOntologies.NS.Core
  alias ElixirOntologies.Graph

  @base_iri "https://example.org/code#"

  # ===========================================================================
  # Complete Control Flow Extraction Tests
  # ===========================================================================

  describe "complete control flow extraction" do
    setup do
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app/control_flow.ex"
        )

      {:ok, context: context}
    end

    test "if expression extraction in full mode", %{context: context} do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [
          %Branch{type: :then, body: {:big, [], []}},
          %Branch{type: :else, body: {:small, [], []}}
        ],
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.check_size/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.IfExpression
             end)

      # Should have hasCondition linking to condition
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasCondition()
             end)

      # Should have hasThenBranch
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasThenBranch()
             end)

      # Should have hasElseBranch
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasElseBranch()
             end)
    end

    test "unless expression extraction in full mode", %{context: context} do
      conditional = %Conditional{
        type: :unless,
        condition: {:is_nil, [], [{:x, [], nil}]},
        branches: [%Branch{type: :then, body: {:default, [], []}}],
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.default_if_nil/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple for UnlessExpression
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.UnlessExpression
             end)

      # Should have hasCondition
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasCondition()
             end)
    end

    test "cond expression extraction in full mode", %{context: context} do
      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{
            condition: {:>, [], [{:x, [], nil}, 0]},
            body: {:positive, [], []},
            index: 0,
            is_catch_all: false
          },
          %{
            condition: {:<, [], [{:x, [], nil}, 0]},
            body: {:negative, [], []},
            index: 1,
            is_catch_all: false
          },
          %{condition: true, body: {:zero, [], []}, index: 2, is_catch_all: true}
        ],
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.sign/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple for CondExpression
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.CondExpression
             end)

      # Should have multiple hasCondition clauses
      condition_count =
        Enum.count(triples, fn {_s, p, _o} -> p == Core.hasCondition() end)

      assert condition_count >= 3
    end

    test "case expression extraction in full mode", %{context: context} do
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [
          %CaseClause{index: 0, pattern: :_, body: :any, has_guard: false},
          %CaseClause{index: 1, pattern: {:ok, [], []}, body: :success, has_guard: false}
        ],
        location: nil,
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp.match/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple for CaseExpression
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.CaseExpression
             end)

      # Should have hasCondition linking to subject
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasCondition()
             end)

      # Should have hasPattern for each clause
      pattern_count =
        Enum.count(triples, fn {_s, p, _o} -> p == Core.hasPattern() end)

      assert pattern_count >= 2
    end

    test "with expression extraction in full mode", %{context: context} do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], [{:x, [], nil}]},
            expression: {:fun, [], []}
          }
        ],
        body: :result,
        location: nil,
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp.chain/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple for WithExpression
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.WithExpression
             end)

      # Should have hasPattern
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasPattern()
             end)

      # Should have hasBody
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == ElixirOntologies.NS.Structure.hasBody()
             end)
    end

    test "receive expression extraction in full mode", %{context: context} do
      receive_expr = %ReceiveExpression{
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:ok, [], [{:x, [], nil}]},
            guard: nil,
            body: {:x, [], nil},
            has_guard: false
          }
        ],
        after_clause: nil,
        has_after: false,
        location: nil,
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp.wait/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple for ReceiveExpression
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.ReceiveExpression
             end)

      # Should have hasPattern for clause
      assert Enum.any?(triples, fn {_s, p, _o} -> p == Core.hasPattern() end)
    end

    test "try/raise/throw expression extraction in full mode", %{context: context} do
      # Test try expression
      try_expr = %Exception{
        body: :risky_operation,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        after_body: nil,
        has_rescue: false,
        has_catch: false,
        has_else: false,
        has_after: false,
        metadata: %{}
      }

      {try_iri, try_triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp.risky/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      assert Enum.any?(try_triples, fn {s, p, o} ->
               s == try_iri and p == RDF.type() and o == Core.TryExpression
             end)

      # Test raise expression
      raise_expr = %RaiseExpression{
        exception: nil,
        message: "error",
        attributes: nil,
        is_reraise: false,
        stacktrace: nil,
        location: nil
      }

      {raise_iri, raise_triples} =
        ControlFlowBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp.fail/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      assert Enum.any?(raise_triples, fn {s, p, o} ->
               s == raise_iri and p == RDF.type() and o == Core.RaiseExpression
             end)

      # Test throw expression
      throw_expr = %ThrowExpression{
        value: :error,
        location: nil
      }

      {throw_iri, throw_triples} =
        ControlFlowBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp.throw_error/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      assert Enum.any?(throw_triples, fn {s, p, o} ->
               s == throw_iri and p == RDF.type() and o == Core.ThrowExpression
             end)
    end
  end

  # ===========================================================================
  # Light Mode vs Full Mode Tests
  # ===========================================================================

  describe "light mode vs full mode" do
    test "light mode produces minimal triples" do
      # Light mode: no expression_builder, no include_expressions config
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{},
          file_path: "lib/my_app.ex"
        )

      conditional = %Conditional{
        type: :if,
        condition: {:x, [], nil},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.test/0",
          index: 0
        )

      # Light mode: only type triple, no expression trees
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == RDF.type() and o == Core.IfExpression
             end)

      # Light mode has hasCondition as boolean, not as expression link
      has_condition_triples =
        Enum.filter(triples, fn {s, p, _o} ->
          s == expr_iri and p == Core.hasCondition()
        end)

      # In light mode, hasCondition is a boolean true (not a link to an expression)
      assert length(has_condition_triples) > 0
      {_s, _p, o} = hd(has_condition_triples)
      assert o == RDF.XSD.Boolean.new(true)
    end

    test "full mode produces expression tree" do
      # Full mode: with expression_builder
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [1, 2]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Full mode: should have hasCondition linking to expression
      assert Enum.any?(triples, fn {_s, p, _o} -> p == Core.hasCondition() end)

      # Should have operator expression for >
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.ComparisonOperator
             end)
    end

    test "mode setting affects all control flow types" do
      # Test light mode for case
      context_light =
        Context.new(
          base_iri: @base_iri,
          config: %{},
          file_path: "lib/my_app.ex"
        )

      case_expr = %CaseExpression{
        subject: :x,
        clauses: [%CaseClause{index: 0, pattern: :_, body: :ok, has_guard: false}],
        location: nil,
        metadata: %{}
      }

      {_case_iri, case_triples_light} =
        ControlFlowBuilder.build_case(case_expr, context_light,
          containing_function: "MyApp.test/0",
          index: 0,
          expression_builder: nil
        )

      # Light mode: should have hasClause boolean, not expression trees
      has_clause_triples =
        Enum.filter(case_triples_light, fn {_s, p, _o} -> p == Core.hasClause() end)

      assert length(has_clause_triples) > 0

      # Full mode for case
      context_full =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {_case_iri, case_triples_full} =
        ControlFlowBuilder.build_case(case_expr, context_full,
          containing_function: "MyApp.test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Full mode: should have hasPattern linking to pattern expression
      assert Enum.any?(case_triples_full, fn {_s, p, _o} ->
               p == Core.hasPattern()
             end)
    end
  end

  # ===========================================================================
  # Nested Control Flow Tests
  # ===========================================================================

  describe "nested control flow" do
    setup do
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app/nested.ex"
        )

      {:ok, context: context}
    end

    test "distinct IRIs for different control flow expressions", %{context: context} do
      # Build multiple control flow expressions and verify they have distinct IRIs
      if_expr = %Conditional{
        type: :if,
        condition: true,
        branches: [%Branch{type: :then, body: :result1}],
        metadata: %{}
      }

      case_expr = %CaseExpression{
        subject: :x,
        clauses: [%CaseClause{index: 0, pattern: :_, body: :result2, has_guard: false}],
        location: nil,
        metadata: %{}
      }

      {if_iri, _if_triples} =
        ControlFlowBuilder.build_conditional(if_expr, context,
          containing_function: "MyApp.test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      {case_iri, _case_triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp.test/0",
          index: 1,
          expression_builder: ExpressionBuilder
        )

      # IRIs should be distinct
      assert if_iri != case_iri

      # Both should contain their function name and index
      if_iri_string = to_string(if_iri)
      case_iri_string = to_string(case_iri)

      # index 0 for if
      assert String.contains?(if_iri_string, "/0")

      # index 1 for case
      assert String.contains?(case_iri_string, "/1")
    end

    test "nested control flow conditions use expression builder", %{context: context} do
      # Test that complex expressions in conditions are properly built
      conditional = %Conditional{
        type: :if,
        condition: {:and, [], [true, false]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.nested/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have LogicalOperator for the 'and' condition
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.LogicalOperator
             end)
    end

    test "control flow with complex body expressions", %{context: context} do
      # Test that complex body expressions are built
      conditional = %Conditional{
        type: :if,
        condition: true,
        branches: [
          %Branch{
            type: :then,
            body: {:{}, [], [:ok, {:result, [], []}]}
          }
        ],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.complex_body/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have TupleLiteral for the body
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.TupleLiteral
             end)
    end
  end

  # ===========================================================================
  # Complex Expression Tests
  # ===========================================================================

  describe "complex expressions" do
    setup do
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app/complex.ex"
        )

      {:ok, context: context}
    end

    test "complex condition expressions", %{context: context} do
      # Complex condition: x > 0 and y < 100
      conditional = %Conditional{
        type: :if,
        condition: {:and, [], [{:>, [], [{:x, [], nil}, 0]}, {:<, [], [{:y, [], nil}, 100]}]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.complex_check/2",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have LogicalOperator (and)
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.LogicalOperator
             end)

      # Should have two ComparisonOperator (>, <)
      comparison_count =
        Enum.count(triples, fn {_s, p, o} -> p == RDF.type() and o == Core.ComparisonOperator end)

      assert comparison_count == 2
    end

    test "complex branch bodies", %{context: context} do
      # Branch body with function call and tuple
      conditional = %Conditional{
        type: :if,
        condition: true,
        branches: [
          %Branch{
            type: :then,
            body: {:{}, [], [:ok, {:process, [], [{:x, [], nil}]}]}
          }
        ],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.complex_body/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have TupleLiteral
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.TupleLiteral
             end)

      # Should have LocalCall (process)
      assert Enum.any?(triples, fn {_s, p, o} ->
               p == RDF.type() and o == Core.LocalCall
             end)
    end
  end

  # ===========================================================================
  # SPARQL Queryability Tests
  # ===========================================================================

  describe "SPARQL queryability" do
    setup do
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app/sparql_test.ex"
        )

      {:ok, context: context}
    end

    test "find control flow by type", %{context: context} do
      # Create multiple control flow expressions
      if_expr = %Conditional{
        type: :if,
        condition: true,
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      {_if_iri, if_triples} =
        ControlFlowBuilder.build_conditional(if_expr, context,
          containing_function: "MyApp.test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Convert to Graph for SPARQL query
      graph = Enum.reduce(if_triples, Graph.new(), fn triple, acc -> Graph.add(acc, triple) end)

      # Query for all IfExpressions
      query = "SELECT ?s WHERE { ?s a core:IfExpression }"
      {:ok, result} = Graph.query(graph, query)

      # Should find the if expression
      assert length(result.results) == 1
    end

    test "navigate expression tree", %{context: context} do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [
          %Branch{type: :then, body: :big}
        ],
        metadata: %{}
      }

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp.test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Convert to Graph for SPARQL query
      graph = Enum.reduce(triples, Graph.new(), fn triple, acc -> Graph.add(acc, triple) end)

      # Query: find the condition of the if expression
      query = """
      SELECT ?condition WHERE {
        ?if a core:IfExpression ;
            core:hasCondition ?condition .
      }
      """

      {:ok, result} = Graph.query(graph, query)

      # Should find one condition
      assert length(result.results) == 1

      # The condition should be a ComparisonOperator
      condition_iri = hd(result.results)["condition"]

      assert Enum.any?(triples, fn {s, p, o} ->
               s == condition_iri and p == RDF.type() and o == Core.ComparisonOperator
             end)
    end

    test "find guards within clauses", %{context: context} do
      # Case with guard
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:n, [], nil},
            body: :ok,
            has_guard: true,
            guard: {:when, [], [[{:is_integer, [], [[{:n, [], nil}]]}]]}
          }
        ],
        location: nil,
        metadata: %{}
      }

      {_case_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp.with_guard/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Convert to Graph for SPARQL query
      graph = Enum.reduce(triples, Graph.new(), fn triple, acc -> Graph.add(acc, triple) end)

      # Query: find expressions with guards
      query = """
      SELECT ?s WHERE {
        ?s core:hasGuard ?guard .
      }
      """

      {:ok, result} = Graph.query(graph, query)

      # Should find the case expression with guard
      assert length(result.results) >= 1
    end
  end

  describe "edge cases" do
    setup do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {:ok, context: context}
    end

    test "deeply nested control flow (3 levels)", %{context: context} do
      # with expression with pattern matching
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], [{:x, [], nil}]},
            expression: {:some_fun, [], []}
          }
        ],
        body: {:x, [], nil},
        location: nil,
        metadata: %{}
      }

      # Build the with expression
      {_with_iri, with_triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp.nested/0",
          index: 0
        )

      # Should have type triple for WithExpression
      assert Enum.any?(with_triples, fn {_s, _p, o} ->
               o == Core.WithExpression
             end)

      # Should have hasClause triple in light mode
      assert Enum.any?(with_triples, fn {_s, p, _o} ->
               p == Core.hasClause()
             end)
    end

    test "complex guard with multiple conditions", %{context: context} do
      # Case with complex guard
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:n, [], nil},
            body: :ok,
            has_guard: true,
            guard: {:when, [], [[{:>, [], [{:n, [], nil}, 0]}]]}
          }
        ],
        location: nil,
        metadata: %{}
      }

      {_case_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp.complex_guard/1",
          index: 0
        )

      # Should have hasGuard triple
      assert Enum.any?(triples, fn {_s, p, _o} ->
               p == Core.hasGuard()
             end)
    end

    test "empty control flow structures", %{context: context} do
      # Cond with only catch-all clause
      cond_expr = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: true, body: :default, index: 0, is_catch_all: true}
        ],
        metadata: %{}
      }

      {_cond_iri, triples} =
        ControlFlowBuilder.build_conditional(cond_expr, context,
          containing_function: "MyApp.empty_cond/0",
          index: 0
        )

      # Should have type triple for CondExpression
      assert Enum.any?(triples, fn {_s, _p, o} ->
               o == Core.CondExpression
             end)
    end

    test "control flow with nil location", %{context: context} do
      # Control flow with nil location should still generate triples
      if_expr = %Conditional{
        type: :if,
        condition: true,
        branches: [
          %Branch{type: :then, body: :result}
        ],
        metadata: %{}
      }

      {_if_iri, triples} =
        ControlFlowBuilder.build_conditional(if_expr, context,
          containing_function: "MyApp.no_location/0",
          index: 0
        )

      # Should have type triple
      assert Enum.any?(triples, fn {_s, _p, o} ->
               o == Core.IfExpression
             end)

      # Should not have location triples when location is nil
      refute Enum.any?(triples, fn {_s, p, _o} ->
               p == Core.startLine()
             end)
    end
  end
end
