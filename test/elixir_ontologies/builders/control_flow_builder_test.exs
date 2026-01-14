defmodule ElixirOntologies.Builders.ControlFlowBuilderTest do
  @moduledoc """
  Tests for the ControlFlowBuilder module.

  These tests verify RDF triple generation for control flow structures including
  conditionals (if/unless/cond), case expressions, with expressions, receive
  expressions, and comprehensions.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
  alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}

  alias ElixirOntologies.Extractors.CaseWith.{
    CaseExpression,
    CaseClause,
    WithExpression,
    WithClause,
    ReceiveExpression
  }

  alias ElixirOntologies.Extractors.Comprehension
  alias ElixirOntologies.NS.Core

  @base_iri "https://example.org/code#"

  # ===========================================================================
  # Conditional IRI Generation Tests
  # ===========================================================================

  describe "conditional_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ControlFlowBuilder.conditional_iri(@base_iri, "MyApp/foo/1", 0)
      assert to_string(iri) == "https://example.org/code#cond/MyApp/foo/1/0"
    end

    test "increments index for multiple conditionals" do
      iri0 = ControlFlowBuilder.conditional_iri(@base_iri, "MyApp/bar/2", 0)
      iri1 = ControlFlowBuilder.conditional_iri(@base_iri, "MyApp/bar/2", 1)

      assert to_string(iri0) == "https://example.org/code#cond/MyApp/bar/2/0"
      assert to_string(iri1) == "https://example.org/code#cond/MyApp/bar/2/1"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ControlFlowBuilder.conditional_iri(base, "Test/func/0", 5)
      assert to_string(iri) == "https://example.org/code#cond/Test/func/0/5"
    end
  end

  # ===========================================================================
  # Case IRI Generation Tests
  # ===========================================================================

  describe "case_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ControlFlowBuilder.case_iri(@base_iri, "MyApp/run/1", 0)
      assert to_string(iri) == "https://example.org/code#case/MyApp/run/1/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ControlFlowBuilder.case_iri(base, "Test/match/0", 3)
      assert to_string(iri) == "https://example.org/code#case/Test/match/0/3"
    end
  end

  # ===========================================================================
  # With IRI Generation Tests
  # ===========================================================================

  describe "with_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ControlFlowBuilder.with_iri(@base_iri, "MyApp/process/2", 0)
      assert to_string(iri) == "https://example.org/code#with/MyApp/process/2/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ControlFlowBuilder.with_iri(base, "Test/chain/1", 2)
      assert to_string(iri) == "https://example.org/code#with/Test/chain/1/2"
    end
  end

  # ===========================================================================
  # If Expression Building Tests
  # ===========================================================================

  describe "build_conditional/3 with if" do
    test "generates type triple for if expression" do
      conditional = %Conditional{
        type: :if,
        condition: {:is_valid, [], nil},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.IfExpression
    end

    test "generates hasCondition triple for if expression" do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 0]},
        branches: [%Branch{type: :then, body: :positive}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/check/1",
          index: 0
        )

      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil
      assert RDF.Literal.value(elem(condition_triple, 2)) == true
    end

    test "generates hasThenBranch triple for if with then branch" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :yes}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      then_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      assert then_triple != nil
      assert RDF.Literal.value(elem(then_triple, 2)) == true
    end

    test "generates hasElseBranch triple for if with else branch" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [
          %Branch{type: :then, body: :yes},
          %Branch{type: :else, body: :no}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      else_triple = find_triple(triples, expr_iri, Core.hasElseBranch())
      assert else_triple != nil
      assert RDF.Literal.value(elem(else_triple, 2)) == true
    end
  end

  # ===========================================================================
  # Unless Expression Building Tests
  # ===========================================================================

  describe "build_conditional/3 with unless" do
    test "generates type triple for unless expression" do
      conditional = %Conditional{
        type: :unless,
        condition: {:is_nil, [], [{:x, [], nil}]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/check/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.UnlessExpression
    end

    test "generates hasCondition triple for unless expression" do
      conditional = %Conditional{
        type: :unless,
        condition: :error,
        branches: [%Branch{type: :then, body: :proceed}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil
    end
  end

  # ===========================================================================
  # Cond Expression Building Tests
  # ===========================================================================

  describe "build_conditional/3 with cond" do
    test "generates type triple for cond expression" do
      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{
            condition: {:>, [], [{:x, [], nil}, 0]},
            body: :positive,
            index: 0,
            is_catch_all: false
          },
          %{condition: true, body: :default, index: 1, is_catch_all: true}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/classify/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.CondExpression
    end

    test "generates hasClause triple for cond with clauses" do
      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: :a, body: 1, index: 0, is_catch_all: false},
          %{condition: :b, body: 2, index: 1, is_catch_all: false}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/select/0",
          index: 0
        )

      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert RDF.Literal.value(elem(clause_triple, 2)) == true
    end

    test "does not generate hasCondition for cond (conditions are per-clause)" do
      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [%{condition: true, body: :ok, index: 0, is_catch_all: true}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple == nil
    end
  end

  # ===========================================================================
  # Case Expression Building Tests
  # ===========================================================================

  describe "build_case/3" do
    test "generates type triple for case expression" do
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [%CaseClause{index: 0, pattern: :ok, body: :success, has_guard: false}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/handle/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.CaseExpression
    end

    test "generates hasClause triple for case with clauses" do
      case_expr = %CaseExpression{
        subject: {:result, [], nil},
        clauses: [
          %CaseClause{index: 0, pattern: {:ok, :_}, body: :success, has_guard: false},
          %CaseClause{index: 1, pattern: {:error, :_}, body: :failure, has_guard: false}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/process/1",
          index: 0
        )

      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert RDF.Literal.value(elem(clause_triple, 2)) == true
    end

    test "generates hasGuard triple when clauses have guards" do
      case_expr = %CaseExpression{
        subject: {:n, [], nil},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: :x,
            guard: {:>, [], [:x, 0]},
            body: :positive,
            has_guard: true
          },
          %CaseClause{index: 1, pattern: :_, body: :other, has_guard: false}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/classify/1",
          index: 0
        )

      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple != nil
      assert RDF.Literal.value(elem(guard_triple, 2)) == true
    end

    test "does not generate hasGuard when no clauses have guards" do
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [
          %CaseClause{index: 0, pattern: :a, body: 1, has_guard: false},
          %CaseClause{index: 1, pattern: :b, body: 2, has_guard: false}
        ],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple == nil
    end
  end

  # ===========================================================================
  # With Expression Building Tests
  # ===========================================================================

  describe "build_with/3" do
    test "generates type triple for with expression" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{index: 0, type: :match, pattern: {:ok, :x}, expression: {:fetch, [], []}}
        ],
        body: :x,
        else_clauses: [],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/process/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.WithExpression
    end

    test "generates hasClause triple for with clauses" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{index: 0, type: :match, pattern: {:ok, :a}, expression: :expr1},
          %WithClause{index: 1, type: :match, pattern: {:ok, :b}, expression: :expr2}
        ],
        body: {:a, :b},
        else_clauses: [],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/chain/0",
          index: 0
        )

      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert RDF.Literal.value(elem(clause_triple, 2)) == true
    end

    test "generates hasElseClause triple when else clauses present" do
      with_expr = %WithExpression{
        clauses: [%WithClause{index: 0, type: :match, pattern: {:ok, :x}, expression: :expr}],
        body: :x,
        else_clauses: [%CaseClause{index: 0, pattern: :error, body: :default, has_guard: false}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/safe/0",
          index: 0
        )

      else_triple = find_triple(triples, expr_iri, Core.hasElseClause())
      assert else_triple != nil
      assert RDF.Literal.value(elem(else_triple, 2)) == true
    end

    test "does not generate hasElseClause when no else clauses" do
      with_expr = %WithExpression{
        clauses: [%WithClause{index: 0, type: :match, pattern: {:ok, :x}, expression: :expr}],
        body: :x,
        else_clauses: [],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      else_triple = find_triple(triples, expr_iri, Core.hasElseClause())
      assert else_triple == nil
    end
  end

  # ===========================================================================
  # Receive IRI Generation Tests
  # ===========================================================================

  describe "receive_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ControlFlowBuilder.receive_iri(@base_iri, "MyApp/wait/0", 0)
      assert to_string(iri) == "https://example.org/code#receive/MyApp/wait/0/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ControlFlowBuilder.receive_iri(base, "Test/listen/1", 2)
      assert to_string(iri) == "https://example.org/code#receive/Test/listen/1/2"
    end
  end

  # ===========================================================================
  # Comprehension IRI Generation Tests
  # ===========================================================================

  describe "comprehension_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ControlFlowBuilder.comprehension_iri(@base_iri, "MyApp/transform/1", 0)
      assert to_string(iri) == "https://example.org/code#for/MyApp/transform/1/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ControlFlowBuilder.comprehension_iri(base, "Test/map/1", 3)
      assert to_string(iri) == "https://example.org/code#for/Test/map/1/3"
    end
  end

  # ===========================================================================
  # Receive Expression Building Tests
  # ===========================================================================

  describe "build_receive/3" do
    test "generates type triple for receive expression" do
      receive_expr = %ReceiveExpression{
        clauses: [{:->, [], [[{:msg, [], nil}], :ok]}],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/listen/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ReceiveExpression
    end

    test "generates hasClause triple for receive with clauses" do
      receive_expr = %ReceiveExpression{
        clauses: [
          {:->, [], [[{:msg, [], nil}], :ok]},
          {:->, [], [[{:error, :_}], :err]}
        ],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/handle/0",
          index: 0
        )

      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert RDF.Literal.value(elem(clause_triple, 2)) == true
    end

    test "generates hasAfterTimeout triple for receive with after block" do
      receive_expr = %ReceiveExpression{
        clauses: [{:->, [], [[{:msg, [], nil}], :ok]}],
        after_clause: {5000, :timeout},
        has_after: true,
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/wait/0",
          index: 0
        )

      after_triple = find_triple(triples, expr_iri, Core.hasAfterTimeout())
      assert after_triple != nil
      assert RDF.Literal.value(elem(after_triple, 2)) == true
    end

    test "does not generate hasAfterTimeout when no after block" do
      receive_expr = %ReceiveExpression{
        clauses: [{:->, [], [[{:msg, [], nil}], :ok]}],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/listen/0",
          index: 0
        )

      after_triple = find_triple(triples, expr_iri, Core.hasAfterTimeout())
      assert after_triple == nil
    end

    test "generates startLine triple for receive with location" do
      receive_expr = %ReceiveExpression{
        clauses: [{:->, [], [[{:msg, [], nil}], :ok]}],
        after_clause: nil,
        has_after: false,
        location: %{line: 25},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/wait/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 25
    end
  end

  # ===========================================================================
  # Comprehension Expression Building Tests
  # ===========================================================================

  describe "build_comprehension/3" do
    test "generates type triple for comprehension" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:x, [], nil},
        options: %{},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/transform/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ForComprehension
    end

    test "generates hasGenerator triple for comprehension with generators" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}, {:y, {:other, [], nil}}],
        filters: [],
        body: {:x, :y},
        options: %{},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/product/2",
          index: 0
        )

      generator_triple = find_triple(triples, expr_iri, Core.hasGenerator())
      assert generator_triple != nil
      assert RDF.Literal.value(elem(generator_triple, 2)) == true
    end

    test "generates hasFilter triple for comprehension with filters" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}],
        filters: [{:>, [], [{:x, [], nil}, 0]}],
        body: {:x, [], nil},
        options: %{},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/filter/1",
          index: 0
        )

      filter_triple = find_triple(triples, expr_iri, Core.hasFilter())
      assert filter_triple != nil
      assert RDF.Literal.value(elem(filter_triple, 2)) == true
    end

    test "generates hasIntoOption triple for comprehension with into option" do
      comprehension = %Comprehension{
        type: :into,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:x, [], nil},
        options: %{into: %{}},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/into_map/1",
          index: 0
        )

      into_triple = find_triple(triples, expr_iri, Core.hasIntoOption())
      assert into_triple != nil
      assert RDF.Literal.value(elem(into_triple, 2)) == true
    end

    test "generates hasReduceOption triple for comprehension with reduce option" do
      comprehension = %Comprehension{
        type: :reduce,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:+, [], [:acc, :x]},
        options: %{reduce: 0},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/sum/1",
          index: 0
        )

      reduce_triple = find_triple(triples, expr_iri, Core.hasReduceOption())
      assert reduce_triple != nil
      assert RDF.Literal.value(elem(reduce_triple, 2)) == true
    end

    test "generates hasUniqOption triple for comprehension with uniq option" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:x, [], nil},
        options: %{uniq: true},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/unique/1",
          index: 0
        )

      uniq_triple = find_triple(triples, expr_iri, Core.hasUniqOption())
      assert uniq_triple != nil
      assert RDF.Literal.value(elem(uniq_triple, 2)) == true
    end

    test "does not generate hasFilter when no filters present" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:x, [], nil},
        options: %{},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/map/1",
          index: 0
        )

      filter_triple = find_triple(triples, expr_iri, Core.hasFilter())
      assert filter_triple == nil
    end

    test "generates startLine triple for comprehension with location" do
      comprehension = %Comprehension{
        type: :list,
        generators: [{:x, {:list, [], nil}}],
        filters: [],
        body: {:x, [], nil},
        options: %{},
        location: %{line: 50},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_comprehension(comprehension, context,
          containing_function: "MyApp/transform/1",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 50
    end
  end

  # ===========================================================================
  # Location Handling Tests
  # ===========================================================================

  describe "location handling" do
    test "generates startLine triple for conditional with location" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}],
        location: %{line: 42},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 42
    end

    test "generates startLine triple for case with location" do
      case_expr = %CaseExpression{
        subject: :x,
        clauses: [%CaseClause{index: 0, pattern: :_, body: :ok, has_guard: false}],
        location: %{line: 100},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 100
    end

    test "generates startLine triple for with with location" do
      with_expr = %WithExpression{
        clauses: [%WithClause{index: 0, type: :match, pattern: :ok, expression: :x}],
        body: :ok,
        else_clauses: [],
        location: %{line: 55},
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 55
    end

    test "does not generate location triple when location is nil" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}],
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple == nil
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "uses default index 0 when not specified" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0"
        )

      assert to_string(expr_iri) == "https://example.org/code#cond/MyApp/test/0/0"
    end

    test "uses unknown/0 when containing_function not specified" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} = ControlFlowBuilder.build_conditional(conditional, context)

      assert to_string(expr_iri) == "https://example.org/code#cond/unknown/0/0"
    end

    test "handles if without condition" do
      conditional = %Conditional{
        type: :if,
        condition: nil,
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      # Should still have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil

      # Should not have condition triple
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple == nil
    end

    test "handles case with empty clauses" do
      case_expr = %CaseExpression{
        subject: :x,
        clauses: [],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil

      # Should not have clause triple
      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple == nil
    end

    test "handles with with empty clauses" do
      with_expr = %WithExpression{
        clauses: [],
        body: :ok,
        else_clauses: [],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil

      # Should not have clause triple
      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple == nil
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "all triples have valid subjects (IRIs)" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      Enum.each(triples, fn {s, _, _} ->
        assert %RDF.IRI{} = s
      end)
    end

    test "all triples have valid predicates (IRIs)" do
      case_expr = %CaseExpression{
        subject: :x,
        clauses: [%CaseClause{index: 0, pattern: :ok, body: :ok, has_guard: false}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {_expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      Enum.each(triples, fn {_, p, _} ->
        assert %RDF.IRI{} = p
      end)
    end

    test "type triples have correct class IRIs" do
      context = Context.new(base_iri: @base_iri)

      # Test if expression
      if_cond = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: 1}],
        metadata: %{}
      }

      {iri, triples} =
        ControlFlowBuilder.build_conditional(if_cond, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      type_triple = find_triple(triples, iri, RDF.type())
      assert elem(type_triple, 2) == Core.IfExpression

      # Test case expression
      case_clause = %CaseClause{index: 0, pattern: :ok, body: 1, has_guard: false}
      case_expr = %CaseExpression{subject: :x, clauses: [case_clause], metadata: %{}}

      {iri2, triples2} =
        ControlFlowBuilder.build_case(
          case_expr,
          context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      type_triple2 = find_triple(triples2, iri2, RDF.type())
      assert elem(type_triple2, 2) == Core.CaseExpression

      # Test with expression
      with_clause = %WithClause{index: 0, type: :match, pattern: :ok, expression: :x}

      with_expr = %WithExpression{
        clauses: [with_clause],
        body: :ok,
        else_clauses: [],
        metadata: %{}
      }

      {iri3, triples3} =
        ControlFlowBuilder.build_with(
          with_expr,
          context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      type_triple3 = find_triple(triples3, iri3, RDF.type())
      assert elem(type_triple3, 2) == Core.WithExpression
    end

    test "boolean properties have correct literal type" do
      conditional = %Conditional{
        type: :if,
        condition: :x,
        branches: [%Branch{type: :then, body: :ok}, %Branch{type: :else, body: :err}],
        metadata: %{}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      # Check hasCondition is boolean
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert %RDF.Literal{} = elem(cond_triple, 2)
      assert RDF.Literal.value(elem(cond_triple, 2)) == true

      # Check hasThenBranch is boolean
      then_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      assert %RDF.Literal{} = elem(then_triple, 2)
      assert RDF.Literal.value(elem(then_triple, 2)) == true
    end
  end

  # ===========================================================================
  # ExpressionBuilder Integration Tests
  # ===========================================================================

  describe "ExpressionBuilder integration" do
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "build_conditional/3 with expression_builder in full mode builds condition expression" do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [%Branch{type: :then, body: :ok}, %Branch{type: :else, body: :err}],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have an expression IRI for the condition (not just boolean)
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())

      # In full mode, hasCondition should link to an expression IRI, not a boolean
      assert %RDF.IRI{} = elem(cond_triple, 2)

      # Should have triples for the comparison operator
      condition_iri = elem(cond_triple, 2)
      type_triple = find_triple(triples, condition_iri, RDF.type())

      # The condition should be a ComparisonOperator
      assert elem(type_triple, 2) == Core.ComparisonOperator
    end

    test "build_conditional/3 without expression_builder uses boolean flags" do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [%Branch{type: :then, body: :ok}, %Branch{type: :else, body: :err}],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0
          # No expression_builder
        )

      # Should have boolean flag for condition
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())

      # In light mode, hasCondition should be a boolean literal
      assert %RDF.Literal{} = elem(cond_triple, 2)
      assert RDF.Literal.value(elem(cond_triple, 2)) == true
    end

    test "build_conditional/3 in light mode uses boolean flags even with expression_builder" do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      # Light mode: include_expressions is false
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: false},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should use boolean flag in light mode
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert %RDF.Literal{} = elem(cond_triple, 2)
      assert RDF.Literal.value(elem(cond_triple, 2)) == true
    end

    test "build_conditional/3 with dependency file uses boolean flags even in full mode" do
      conditional = %Conditional{
        type: :if,
        condition: {:>, [], [{:x, [], nil}, 5]},
        branches: [%Branch{type: :then, body: :ok}],
        metadata: %{}
      }

      # Dependency file path
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should use boolean flag for dependency files
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert %RDF.Literal{} = elem(cond_triple, 2)
      assert RDF.Literal.value(elem(cond_triple, 2)) == true
    end

    test "build_conditional/3 builds branch body expressions in full mode" do
      conditional = %Conditional{
        type: :if,
        condition: {:x, [], nil},
        branches: [
          %Branch{type: :then, body: {:+, [], [{:y, [], nil}, 1]}},
          %Branch{type: :else, body: {:*, [], [{:z, [], nil}, 2]}}
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have expression IRIs for branch bodies
      then_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      else_triple = find_triple(triples, expr_iri, Core.hasElseBranch())

      # Both should link to expression IRIs
      assert %RDF.IRI{} = elem(then_triple, 2)
      assert %RDF.IRI{} = elem(else_triple, 2)
    end
  end

  # ===========================================================================
  # Cond Expression Integration Tests (Phase 25.2)
  # ===========================================================================

  describe "cond clause expression extraction" do
    test "cond clause extraction in light mode uses boolean flag" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: {:>, [], [{:x, [], nil}, 0]}, body: :positive, index: 0, is_catch_all: false},
          %{condition: true, body: :default, index: 1, is_catch_all: true}
        ],
        metadata: %{}
      }

      # Light mode: include_expressions is false
      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: false},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/classify/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should use boolean flag for hasClause in light mode
      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert %RDF.Literal{} = elem(clause_triple, 2)
      assert RDF.Literal.value(elem(clause_triple, 2)) == true

      # Should NOT have expression IRIs in light mode
      refute find_triple(triples, expr_iri, Core.hasCondition()) != nil and
             match?(%RDF.IRI{}, elem(find_triple(triples, expr_iri, Core.hasCondition()), 2))
    end

    test "cond clause extraction in full mode builds expression trees" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: {:>, [], [{:x, [], nil}, 0]}, body: :positive, index: 0, is_catch_all: false},
          %{condition: true, body: :default, index: 1, is_catch_all: true}
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/classify/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition links to expression IRIs (not boolean)
      has_condition_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasCondition() end)

      # In full mode, we should have hasCondition links to IRIs, not boolean
      assert length(has_condition_triples) > 0
      # All hasCondition values should be IRIs in full mode
      Enum.each(has_condition_triples, fn {_s, _p, o} ->
        assert %RDF.IRI{} = o
      end)
    end

    test "cond clause extraction captures condition expression" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{
            condition: {:==, [], [{:x, [], nil}, 5]},
            body: :matched,
            index: 0,
            is_catch_all: false
          }
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition linking to an expression IRI
      cond_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert cond_triple != nil
      condition_iri = elem(cond_triple, 2)
      assert %RDF.IRI{} = condition_iri

      # The condition should be a ComparisonOperator
      type_triple = find_triple(triples, condition_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ComparisonOperator
    end

    test "cond clause extraction captures body expression" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{
            condition: {:>, [], [{:x, [], nil}, 0]},
            body: {:*, [], [{:x, [], nil}, 2]},
            index: 0,
            is_catch_all: false
          }
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/double/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasThenBranch linking to the body expression IRI
      body_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      assert body_triple != nil
      body_iri = elem(body_triple, 2)
      assert %RDF.IRI{} = body_iri

      # The body should have an expression type
      type_triple = find_triple(triples, body_iri, RDF.type())
      assert type_triple != nil
    end

    test "cond clause extraction handles multiple clauses" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: {:>, [], [{:x, [], nil}, 10]}, body: :large, index: 0, is_catch_all: false},
          %{condition: {:>, [], [{:x, [], nil}, 5]}, body: :medium, index: 1, is_catch_all: false},
          %{condition: true, body: :small, index: 2, is_catch_all: true}
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/categorize/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition links for each clause (3 total)
      has_condition_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasCondition() end)

      assert length(has_condition_triples) == 3

      # Should have hasThenBranch links for each clause body (3 total)
      has_body_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasThenBranch() end)

      assert length(has_body_triples) == 3
    end

    test "cond clause extraction handles catch-all clause" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: {:>, [], [{:x, [], nil}, 0]}, body: :positive, index: 0, is_catch_all: false},
          %{condition: true, body: :zero_or_negative, index: 1, is_catch_all: true}
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/sign/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should handle the catch-all clause (condition: true)
      # The catch-all clause should still generate condition and body triples
      has_condition_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasCondition() end)

      assert length(has_condition_triples) == 2

      has_body_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasThenBranch() end)

      assert length(has_body_triples) == 2
    end

    test "cond clause extraction preserves clause order" do
      alias ElixirOntologies.Builders.ExpressionBuilder

      conditional = %Conditional{
        type: :cond,
        condition: nil,
        branches: [],
        clauses: [
          %{condition: {:==, [], [{:x, [], nil}, 1]}, body: :one, index: 0, is_catch_all: false},
          %{condition: {:==, [], [{:x, [], nil}, 2]}, body: :two, index: 1, is_catch_all: false},
          %{condition: {:==, [], [{:x, [], nil}, 3]}, body: :three, index: 2, is_catch_all: false}
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {_expr_iri, triples} =
        ControlFlowBuilder.build_conditional(conditional, context,
          containing_function: "MyApp/number_name/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Find all condition IRIs
      condition_iris =
        triples
        |> Enum.filter(fn {_s, p, _o} -> p == Core.hasCondition() end)
        |> Enum.map(fn {_s, _p, o} -> o end)
        |> Enum.filter(fn o -> match?(%RDF.IRI{}, o) end)

      # Check that the suffixes preserve order (cond_0_condition, cond_1_condition, cond_2_condition)
      suffixes =
        condition_iris
        |> Enum.map(fn iri ->
          iri
          |> to_string()
          |> String.split("/")
          |> List.last()
        end)
        |> Enum.sort()

      # Should have suffixes in order
      assert Enum.at(suffixes, 0) =~ "cond_0"
      assert Enum.at(suffixes, 1) =~ "cond_1"
      assert Enum.at(suffixes, 2) =~ "cond_2"
    end
  end

  # ===========================================================================
  # Case Expression Integration Tests (Phase 25.3)
  # ===========================================================================

  describe "case expression integration" do
    alias ElixirOntologies.Extractors.CaseWith.{CaseExpression, CaseClause}
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "case subject expression extraction in full mode" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},  # Variable uses Elixir as context
        clauses: [
          %CaseClause{index: 0, pattern: {:a, [], Elixir}, guard: nil, body: 1, has_guard: false}
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition linking to the subject expression
      subject_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert subject_triple != nil
      subject_iri = elem(subject_triple, 2)
      assert %RDF.IRI{} = subject_iri

      # The subject should be a Variable
      type_triple = find_triple(triples, subject_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.Variable
    end

    test "case clause pattern extraction in full mode" do
      case_expr = %CaseExpression{
        subject: {:x, [], nil},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:x, [], Elixir},  # Variable pattern uses Elixir as context
            guard: nil,
            body: :matched,
            has_guard: false
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasPattern linking to a pattern IRI
      pattern_triple = find_triple(triples, expr_iri, Core.hasPattern())
      assert pattern_triple != nil
      pattern_iri = elem(pattern_triple, 2)
      assert %RDF.IRI{} = pattern_iri

      # The pattern should be a VariablePattern
      pattern_type_triple = find_triple(triples, pattern_iri, RDF.type())
      assert pattern_type_triple != nil
      assert elem(pattern_type_triple, 2) == Core.VariablePattern
    end

    test "case clause guard extraction in full mode" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:x, [], Elixir},
            guard: {:when, [], [{:>, [], [{:x, [], Elixir}, 0]}]},
            body: :positive,
            has_guard: true
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasGuard linking to guard expression
      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple != nil
      guard_iri = elem(guard_triple, 2)
      assert %RDF.IRI{} = guard_iri
    end

    test "case clause body extraction in full mode" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:a, [], Elixir},
            guard: nil,
            body: {:+, [], [{:a, [], Elixir}, 1]},
            has_guard: false
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasThenBranch linking to body expression
      body_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      assert body_triple != nil
      body_iri = elem(body_triple, 2)
      assert %RDF.IRI{} = body_iri

      # The body should have an expression type
      type_triple = find_triple(triples, body_iri, RDF.type())
      assert type_triple != nil
    end

    test "case extraction with multiple clauses" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:a, [], Elixir},
            guard: nil,
            body: :one,
            has_guard: false
          },
          %CaseClause{
            index: 1,
            pattern: {:b, [], Elixir},
            guard: nil,
            body: :two,
            has_guard: false
          },
          %CaseClause{
            index: 2,
            pattern: {:c, [], Elixir},
            guard: nil,
            body: :three,
            has_guard: false
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasThenBranch links for each clause (3 total)
      body_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasThenBranch() end)

      assert length(body_triples) == 3
    end

    test "case extraction with guarded clauses" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:a, [], Elixir},
            guard: {:when, [], [{:>, [], [{:a, [], Elixir}, 0]}]},
            body: :positive,
            has_guard: true
          },
          %CaseClause{
            index: 1,
            pattern: {:b, [], Elixir},
            guard: nil,
            body: :other,
            has_guard: false
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasGuard linking for the guarded clause
      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple != nil
      guard_iri = elem(guard_triple, 2)
      assert %RDF.IRI{} = guard_iri

      # Should still have body expressions for both clauses
      body_triples =
        Enum.filter(triples, fn {s, p, _o} -> s == expr_iri and p == Core.hasThenBranch() end)

      assert length(body_triples) == 2
    end

    test "case extraction preserves clause order" do
      case_expr = %CaseExpression{
        subject: {:x, [], Elixir},
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:one, [], Elixir},
            guard: nil,
            body: 1,
            has_guard: false
          },
          %CaseClause{
            index: 1,
            pattern: {:two, [], Elixir},
            guard: nil,
            body: 2,
            has_guard: false
          },
          %CaseClause{
            index: 2,
            pattern: {:three, [], Elixir},
            guard: nil,
            body: 3,
            has_guard: false
          }
        ],
        location: nil,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {_expr_iri, triples} =
        ControlFlowBuilder.build_case(case_expr, context,
          containing_function: "MyApp/test/1",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Find all body IRIs
      body_iris =
        triples
        |> Enum.filter(fn {_s, p, _o} -> p == Core.hasThenBranch() end)
        |> Enum.map(fn {_s, _p, o} -> o end)
        |> Enum.filter(fn o -> match?(%RDF.IRI{}, o) end)

      # Check that the suffixes preserve order (case_0_body, case_1_body, case_2_body)
      suffixes =
        body_iris
        |> Enum.map(fn iri ->
          iri
          |> to_string()
          |> String.split("/")
          |> List.last()
        end)
        |> Enum.sort()

      # Should have suffixes in order
      assert Enum.at(suffixes, 0) =~ "case_0"
      assert Enum.at(suffixes, 1) =~ "case_1"
      assert Enum.at(suffixes, 2) =~ "case_2"
    end
  end

  # ===========================================================================
  # With Expression Integration Tests (Phase 25.4)
  # ===========================================================================

  describe "with expression integration" do
    alias ElixirOntologies.Extractors.CaseWith.{WithExpression, WithClause, CaseClause}
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "with clause pattern extraction in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result, [], Elixir}
          }
        ],
        body: {:result, [], Elixir},
        else_clauses: [],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasPattern linking to the pattern IRI
      pattern_triple = find_triple(triples, expr_iri, Core.hasPattern())
      assert pattern_triple != nil

      # Pattern should be a VariablePattern for the variable { :ok, [], Elixir }
      pattern_iri = elem(pattern_triple, 2)
      pattern_type_triple = find_triple(triples, pattern_iri, RDF.type())
      assert pattern_type_triple != nil
      assert elem(pattern_type_triple, 2) == Core.VariablePattern
    end

    test "with clause expression extraction in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:x, [], Elixir},
            expression: {:get_value, [], []}
          }
        ],
        body: {:x, [], Elixir},
        else_clauses: [],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition linking to the matched expression
      # (The expression on the right side of the <- operator)
      expr_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert expr_triple != nil

      # The expression should be a LocalCall
      matched_expr_iri = elem(expr_triple, 2)
      expr_type_triple = find_triple(triples, matched_expr_iri, RDF.type())
      assert expr_type_triple != nil
      assert elem(expr_type_triple, 2) == Core.LocalCall
    end

    test "with body extraction in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result, [], Elixir}
          }
        ],
        body: {:result, [], Elixir},
        else_clauses: [],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasBody linking to body expression
      body_triple = find_triple(triples, expr_iri, ElixirOntologies.NS.Structure.hasBody())
      assert body_triple != nil

      # Body should be a Variable
      body_iri = elem(body_triple, 2)
      body_type_triple = find_triple(triples, body_iri, RDF.type())
      assert body_type_triple != nil
      assert elem(body_type_triple, 2) == Core.Variable
    end

    test "with else clause extraction in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result, [], Elixir}
          }
        ],
        body: {:result, [], Elixir},
        else_clauses: [
          %CaseClause{
            index: 0,
            pattern: {:error, [], Elixir},
            guard: nil,
            body: {:handle_error, [], []},
            has_guard: false
          }
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasPattern linking to else pattern
      pattern_triple = find_triple(triples, expr_iri, Core.hasPattern())
      # Find the else pattern (there should be at least 2 patterns - one for with clause, one for else)
      pattern_iris =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == Core.hasPattern() end)
        |> Enum.map(fn {_s, _p, o} -> o end)

      # Should have at least 2 patterns (with clause + else clause)
      assert length(pattern_iris) >= 2

      # Should have hasThenBranch linking to else body
      body_triple = find_triple(triples, expr_iri, Core.hasThenBranch())
      assert body_triple != nil

      # Else body should be a LocalCall
      body_iri = elem(body_triple, 2)
      body_type_triple = find_triple(triples, body_iri, RDF.type())
      assert body_type_triple != nil
      assert elem(body_type_triple, 2) == Core.LocalCall
    end

    test "with extraction with multiple clauses in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result1, [], Elixir}
          },
          %WithClause{
            index: 1,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result2, [], Elixir}
          },
          %WithClause{
            index: 2,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result3, [], Elixir}
          }
        ],
        body: {:final_result, [], Elixir},
        else_clauses: [],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have 3 hasPattern links (one per clause)
      pattern_iris =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == Core.hasPattern() end)
        |> Enum.map(fn {_s, _p, o} -> o end)

      assert length(pattern_iris) == 3

      # Should have hasCondition links for each expression being matched
      condition_links =
        triples
        |> Enum.filter(fn {s, p, _o} ->
          s == expr_iri and p == Core.hasCondition()
        end)

      assert length(condition_links) == 3
    end

    test "with extraction handles else clauses with guards in full mode" do
      with_expr = %WithExpression{
        clauses: [
          %WithClause{
            index: 0,
            type: :match,
            pattern: {:ok, [], Elixir},
            expression: {:result, [], Elixir}
          }
        ],
        body: {:result, [], Elixir},
        else_clauses: [
          %CaseClause{
            index: 0,
            pattern: {:error, [], Elixir},
            guard: {:when, [], [{:x, [], Elixir}, {:is_exception, [], []}]},
            body: {:raise, [], []},
            has_guard: true
          }
        ],
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_with(with_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasGuard link for the else clause
      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple != nil
    end
  end

  # ===========================================================================
  # Receive Expression Integration Tests (Phase 25.5)
  # ===========================================================================

  describe "receive expression integration" do
    alias ElixirOntologies.Extractors.CaseWith.{ReceiveExpression, CaseClause, AfterClause}
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "receive clause pattern extraction in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:msg, [], Elixir},
            guard: nil,
            body: {:handle, [], []},
            has_guard: false
          }
        ],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasPattern linking to the pattern IRI
      pattern_triple = find_triple(triples, expr_iri, Core.hasPattern())
      assert pattern_triple != nil

      # Pattern should be a VariablePattern
      pattern_iri = elem(pattern_triple, 2)
      pattern_type_triple = find_triple(triples, pattern_iri, RDF.type())
      assert pattern_type_triple != nil
      assert elem(pattern_type_triple, 2) == Core.VariablePattern
    end

    test "receive clause guard extraction in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:x, [], Elixir},
            guard: {:when, [], [{:x, [], Elixir}, {:is_integer, [], [{:x, [], Elixir}]}]},
            body: {:x, [], Elixir},
            has_guard: true
          }
        ],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasGuard linking to guard expression
      guard_triple = find_triple(triples, expr_iri, Core.hasGuard())
      assert guard_triple != nil

      # Guard should be a function call
      guard_iri = elem(guard_triple, 2)
      guard_type_triple = find_triple(triples, guard_iri, RDF.type())
      assert guard_type_triple != nil
      assert elem(guard_type_triple, 2) == Core.LocalCall
    end

    test "receive clause body extraction in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:msg, [], Elixir},
            guard: nil,
            body: {:process_msg, [], [{:msg, [], Elixir}]},
            has_guard: false
          }
        ],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasBody linking to body expression
      body_triple = find_triple(triples, expr_iri, ElixirOntologies.NS.Structure.hasBody())
      assert body_triple != nil

      # Body should be a LocalCall
      body_iri = elem(body_triple, 2)
      body_type_triple = find_triple(triples, body_iri, RDF.type())
      assert body_type_triple != nil
      assert elem(body_type_triple, 2) == Core.LocalCall
    end

    test "receive timeout expression extraction in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [],
        after_clause: %AfterClause{
          timeout: 5000,
          body: :timeout,
          is_immediate: false
        },
        has_after: true,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasCondition linking to timeout expression
      timeout_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert timeout_triple != nil

      # Timeout should be an IntegerLiteral
      timeout_iri = elem(timeout_triple, 2)
      timeout_type_triple = find_triple(triples, timeout_iri, RDF.type())
      assert timeout_type_triple != nil
      assert elem(timeout_type_triple, 2) == Core.IntegerLiteral
    end

    test "receive after block extraction in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [],
        after_clause: %AfterClause{
          timeout: 5000,
          body: {:handle_timeout, [], []},
          is_immediate: false
        },
        has_after: true,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasAfterClause linking to after body
      after_triple = find_triple(triples, expr_iri, Core.hasAfterClause())
      assert after_triple != nil

      # After body should be a LocalCall
      after_body_iri = elem(after_triple, 2)
      after_body_type_triple = find_triple(triples, after_body_iri, RDF.type())
      assert after_body_type_triple != nil
      assert elem(after_body_type_triple, 2) == Core.LocalCall
    end

    test "receive extraction with multiple clauses in full mode" do
      receive_expr = %ReceiveExpression{
        clauses: [
          %CaseClause{
            index: 0,
            pattern: {:ping, [], Elixir},
            guard: nil,
            body: {:pong, [], []},
            has_guard: false
          },
          %CaseClause{
            index: 1,
            pattern: {:stop, [], Elixir},
            guard: nil,
            body: {:exit, [], [:normal]},
            has_guard: false
          },
          %CaseClause{
            index: 2,
            pattern: {:_, [], nil},
            guard: nil,
            body: {:unknown_msg, [], []},
            has_guard: false
          }
        ],
        after_clause: nil,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_receive(receive_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have 3 hasPattern links (one per clause)
      pattern_iris =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == Core.hasPattern() end)
        |> Enum.map(fn {_s, _p, o} -> o end)

      assert length(pattern_iris) == 3

      # Should have 3 hasBody links (one per clause)
      body_iris =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == ElixirOntologies.NS.Structure.hasBody() end)
        |> Enum.map(fn {_s, _p, o} -> o end)

      assert length(body_iris) == 3
    end
  end

  # ===========================================================================
  # Try Expression Integration Tests (Phase 25.6)
  # ===========================================================================

  describe "try expression integration" do
    alias ElixirOntologies.Extractors.{Exception, Exception.RescueClause, Exception.CatchClause}
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "try expression extraction for try body in full mode" do
      try_expr = %Exception{
        body: {:risky_operation, [], []},
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

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.TryExpression

      # Should have hasBody linking to try body
      body_triple = find_triple(triples, expr_iri, ElixirOntologies.NS.Structure.hasBody())
      assert body_triple != nil

      # Body should be a LocalCall
      body_iri = elem(body_triple, 2)
      body_type_triple = find_triple(triples, body_iri, RDF.type())
      assert body_type_triple != nil
      assert elem(body_type_triple, 2) == Core.LocalCall
    end

    test "try expression rescue pattern extraction in full mode" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [
          %RescueClause{
            exceptions: [],
            variable: {:e, [], Elixir},
            body: {:handle_error, [], []},
            is_catch_all: true
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_body: nil,
        has_rescue: true,
        has_catch: false,
        has_else: false,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasRescueClause linking to rescue clause
      rescue_triples =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == Core.hasRescueClause() end)

      assert length(rescue_triples) == 1
    end

    test "try expression catch pattern extraction in full mode" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [
          %CatchClause{
            kind: :throw,
            pattern: {:value, [], Elixir},
            body: {:handle_throw, [], []}
          }
        ],
        else_clauses: [],
        after_body: nil,
        has_rescue: false,
        has_catch: true,
        has_else: false,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasPattern linking to catch pattern
      pattern_triple = find_triple(triples, expr_iri, Core.hasPattern())
      assert pattern_triple != nil

      # Should have hasCatchClause linking to catch clause
      catch_triple = find_triple(triples, expr_iri, Core.hasCatchClause())
      assert catch_triple != nil

      # Should have hasBody linking to catch body
      body_triple = find_triple(triples, expr_iri, ElixirOntologies.NS.Structure.hasBody())
      assert body_triple != nil
    end

    test "try expression after block extraction in full mode" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        after_body: {:cleanup, [], []},
        has_rescue: false,
        has_catch: false,
        has_else: false,
        has_after: true,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasAfterClause linking to after body
      after_triple = find_triple(triples, expr_iri, Core.hasAfterClause())
      assert after_triple != nil

      # After body should be a LocalCall
      after_body_iri = elem(after_triple, 2)
      after_body_type_triple = find_triple(triples, after_body_iri, RDF.type())
      assert after_body_type_triple != nil
      assert elem(after_body_type_triple, 2) == Core.LocalCall
    end

    test "try expression extraction handles multiple rescue clauses in full mode" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [
          %RescueClause{
            exceptions: [RuntimeError],
            variable: nil,
            body: {:handle_runtime, [], []},
            is_catch_all: false
          },
          %RescueClause{
            exceptions: [],
            variable: {:e, [], Elixir},
            body: {:handle_any, [], []},
            is_catch_all: true
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_body: nil,
        has_rescue: true,
        has_catch: false,
        has_else: false,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have 2 hasRescueClause links
      rescue_triples =
        triples
        |> Enum.filter(fn {s, p, _o} -> s == expr_iri and p == Core.hasRescueClause() end)

      assert length(rescue_triples) == 2
    end

    test "try expression extraction handles wildcard rescue in full mode" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [
          %RescueClause{
            exceptions: [],
            variable: nil,
            body: :error,
            is_catch_all: true
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_body: nil,
        has_rescue: true,
        has_catch: false,
        has_else: false,
        has_after: false,
        metadata: %{}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have hasRescueClause link
      rescue_triple = find_triple(triples, expr_iri, Core.hasRescueClause())
      assert rescue_triple != nil
    end

    test "try expression extraction for simple try (no rescue/catch/after) in full mode" do
      try_expr = %Exception{
        body: {:simple, [], []},
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

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.TryExpression

      # Should have hasBody linking to try body
      body_triple = find_triple(triples, expr_iri, ElixirOntologies.NS.Structure.hasBody())
      assert body_triple != nil

      # Should NOT have any rescue, catch, or after links
      refute find_triple(triples, expr_iri, Core.hasRescueClause())
      refute find_triple(triples, expr_iri, Core.hasCatchClause())
      refute find_triple(triples, expr_iri, Core.hasAfterClause())
    end
  end

  # ===========================================================================
  # Raise/Throw Expression Integration Tests (Phase 25.7)
  # ===========================================================================

  describe "raise/throw expression integration" do
    alias ElixirOntologies.Extractors.Exception.{RaiseExpression, ThrowExpression}
    alias ElixirOntologies.Builders.ExpressionBuilder

    test "raise expression extraction with message in full mode" do
      raise_expr = %RaiseExpression{
        exception: nil,
        message: "something went wrong",
        attributes: nil,
        is_reraise: false,
        stacktrace: nil,
        location: %{line: 10}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression

      # Should have hasCondition linking to message expression
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil

      # Message should be a StringLiteral
      msg_iri = elem(condition_triple, 2)
      msg_type_triple = find_triple(triples, msg_iri, RDF.type())
      assert msg_type_triple != nil
      assert elem(msg_type_triple, 2) == Core.StringLiteral

      # Should have location
      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 10
    end

    test "raise expression extraction with exception and message in full mode" do
      raise_expr = %RaiseExpression{
        exception: RuntimeError,
        message: "error occurred",
        attributes: nil,
        is_reraise: false,
        stacktrace: nil,
        location: %{line: 15}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/test/0",
          index: 1,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression

      # Should have hasCondition linking to message expression
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil
    end

    test "raise expression extraction for reraise in full mode" do
      # Reraise uses __STACKTRACE__ as the stacktrace
      raise_expr = %RaiseExpression{
        exception: nil,
        message: nil,
        attributes: nil,
        is_reraise: true,
        stacktrace: {:@, [], [{:__STACKTRACE__, [], Elixir}]},
        location: %{line: 20}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression

      # Reraise with no message should not have hasCondition
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple == nil
    end

    test "throw expression extraction for value in full mode" do
      throw_expr = %ThrowExpression{
        value: :error,
        location: %{line: 25}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/test/0",
          index: 0,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ThrowExpression

      # Should have hasCondition linking to value expression
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil

      # Value should be an AtomLiteral
      value_iri = elem(condition_triple, 2)
      value_type_triple = find_triple(triples, value_iri, RDF.type())
      assert value_type_triple != nil
      assert elem(value_type_triple, 2) == Core.AtomLiteral

      # Should have location
      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 25
    end

    test "throw expression extraction handles complex expressions" do
      # Throw a tuple value
      throw_expr = %ThrowExpression{
        value: {:{}, [], [:error, "message", 123]},
        location: %{line: 30}
      }

      context =
        Context.new(
          base_iri: @base_iri,
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      {expr_iri, triples} =
        ControlFlowBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/test/0",
          index: 1,
          expression_builder: ExpressionBuilder
        )

      # Should have type triple
      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ThrowExpression

      # Should have hasCondition linking to value expression
      condition_triple = find_triple(triples, expr_iri, Core.hasCondition())
      assert condition_triple != nil

      # Value should be a TupleLiteral
      value_iri = elem(condition_triple, 2)
      value_type_triple = find_triple(triples, value_iri, RDF.type())
      assert value_type_triple != nil
      assert elem(value_type_triple, 2) == Core.TupleLiteral
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp find_triple(triples, subject, predicate) do
    Enum.find(triples, fn {s, p, _o} -> s == subject and p == predicate end)
  end
end
