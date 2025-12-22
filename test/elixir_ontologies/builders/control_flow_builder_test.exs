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
  alias ElixirOntologies.Extractors.CaseWith.{CaseExpression, CaseClause, WithExpression, WithClause, ReceiveExpression}
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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/check/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/check/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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
          %{condition: {:>, [], [{:x, [], nil}, 0]}, body: :positive, index: 0, is_catch_all: false},
          %{condition: true, body: :default, index: 1, is_catch_all: true}
        ],
        metadata: %{}
      }
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/classify/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/select/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/handle/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/process/1", index: 0)

      clause_triple = find_triple(triples, expr_iri, Core.hasClause())
      assert clause_triple != nil
      assert RDF.Literal.value(elem(clause_triple, 2)) == true
    end

    test "generates hasGuard triple when clauses have guards" do
      case_expr = %CaseExpression{
        subject: {:n, [], nil},
        clauses: [
          %CaseClause{index: 0, pattern: :x, guard: {:>, [], [:x, 0]}, body: :positive, has_guard: true},
          %CaseClause{index: 1, pattern: :_, body: :other, has_guard: false}
        ],
        metadata: %{}
      }
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/classify/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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
        clauses: [%WithClause{index: 0, type: :match, pattern: {:ok, :x}, expression: {:fetch, [], []}}],
        body: :x,
        else_clauses: [],
        metadata: %{}
      }
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/process/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/chain/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/safe/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_receive(receive_expr, context,
        containing_function: "MyApp/listen/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_receive(receive_expr, context,
        containing_function: "MyApp/handle/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_receive(receive_expr, context,
        containing_function: "MyApp/wait/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_receive(receive_expr, context,
        containing_function: "MyApp/listen/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_receive(receive_expr, context,
        containing_function: "MyApp/wait/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/transform/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/product/2", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/filter/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/into_map/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/sum/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/unique/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/map/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_comprehension(comprehension, context,
        containing_function: "MyApp/transform/1", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, _triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0")

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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {expr_iri, triples} = ControlFlowBuilder.build_with(with_expr, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {_expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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

      {_expr_iri, triples} = ControlFlowBuilder.build_case(case_expr, context,
        containing_function: "MyApp/test/0", index: 0)

      Enum.each(triples, fn {_, p, _} ->
        assert %RDF.IRI{} = p
      end)
    end

    test "type triples have correct class IRIs" do
      context = Context.new(base_iri: @base_iri)

      # Test if expression
      if_cond = %Conditional{type: :if, condition: :x, branches: [%Branch{type: :then, body: 1}], metadata: %{}}
      {iri, triples} = ControlFlowBuilder.build_conditional(if_cond, context, containing_function: "MyApp/test/0", index: 0)
      type_triple = find_triple(triples, iri, RDF.type())
      assert elem(type_triple, 2) == Core.IfExpression

      # Test case expression
      case_clause = %CaseClause{index: 0, pattern: :ok, body: 1, has_guard: false}
      case_expr = %CaseExpression{subject: :x, clauses: [case_clause], metadata: %{}}
      {iri2, triples2} = ControlFlowBuilder.build_case(
        case_expr, context, containing_function: "MyApp/test/0", index: 0)
      type_triple2 = find_triple(triples2, iri2, RDF.type())
      assert elem(type_triple2, 2) == Core.CaseExpression

      # Test with expression
      with_clause = %WithClause{index: 0, type: :match, pattern: :ok, expression: :x}
      with_expr = %WithExpression{clauses: [with_clause], body: :ok, else_clauses: [], metadata: %{}}
      {iri3, triples3} = ControlFlowBuilder.build_with(
        with_expr, context, containing_function: "MyApp/test/0", index: 0)
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

      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context,
        containing_function: "MyApp/test/0", index: 0)

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
  # Helper Functions
  # ===========================================================================

  defp find_triple(triples, subject, predicate) do
    Enum.find(triples, fn {s, p, _o} -> s == subject and p == predicate end)
  end
end
