defmodule ElixirOntologies.Builders.GuardExtractionTest do
  use ExUnit.Case, async: true
  import RDF.Sigils

  alias ElixirOntologies.Builders.{ClauseBuilder, Context, ExpressionBuilder}
  alias ElixirOntologies.Extractors.Clause
  alias ElixirOntologies.NS.{Structure, Core}

  @base_iri "https://example.org/code#"

  # ===========================================================================
  # Real-world Guard Examples
  # ===========================================================================

  describe "real-world guard examples" do
    test "extracts simple is_integer guard" do
      context = full_mode_context()

      clause_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify guard exists
      guard_iri = find_guard_iri(clause_iri, triples)
      assert guard_iri != nil

      # Verify guard has inGuardContext property
      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and p == Core.inGuardContext() and RDF.Literal.value(o) == true
             end)

      # Verify guard is a LocalCall (is_integer is imported from Kernel)
      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and
                 p == RDF.type() and
                 o == Core.LocalCall
             end)

      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and
                 p == Core.name() and
                 RDF.Literal.value(o) == "is_integer"
             end)
    end

    test "extracts compound guard with and" do
      context = full_mode_context()

      # when is_integer(x) and x > 0
      clause_info = %Clause{
        name: :process_positive,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process_positive/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify guard exists
      guard_iri = find_guard_iri(clause_iri, triples)
      assert guard_iri != nil

      # Verify guard is a LogicalOperator with operator "and"
      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and p == RDF.type() and o == Core.LogicalOperator
             end)

      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and
                 p == Core.operatorSymbol() and
                 RDF.Literal.value(o) == "and"
             end)

      # Verify guard has inGuardContext
      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and p == Core.inGuardContext() and RDF.Literal.value(o) == true
             end)

      # Verify hasLeftOperand and hasRightOperand
      left_iri = find_object(triples, guard_iri, Core.hasLeftOperand())
      right_iri = find_object(triples, guard_iri, Core.hasRightOperand())
      assert left_iri != nil
      assert right_iri != nil
    end

    test "extracts complex guard with multiple operators" do
      context = full_mode_context()

      # when is_binary(x) or (is_integer(x) and x > 0)
      guard_ast =
        {:or, [],
         [
           {:is_binary, [], [{:x, [], nil}]},
           {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
         ]}

      clause_info = %Clause{
        name: :process_value,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: guard_ast
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process_value/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify top-level or guard
      guard_iri = find_guard_iri(clause_iri, triples)
      assert guard_iri != nil

      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and
                 p == Core.operatorSymbol() and
                 RDF.Literal.value(o) == "or"
             end)
    end

    test "extracts guard with comparison operator" do
      context = full_mode_context()

      # when x > 0
      clause_info = %Clause{
        name: :positive,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:>, [], [{:x, [], nil}, 0]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/positive/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      guard_iri = find_guard_iri(clause_iri, triples)
      assert guard_iri != nil

      # Verify it's a ComparisonOperator
      assert Enum.any?(triples, fn {s, p, o} ->
               s == guard_iri and p == RDF.type() and o == Core.ComparisonOperator
             end)
    end
  end

  # ===========================================================================
  # Multi-clause Function Guards
  # ===========================================================================

  describe "multi-clause function guards" do
    test "extracts different guards for each clause" do
      context = full_mode_context()

      # Clause 1: when is_integer(x)
      clause1_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      # Clause 2: when is_binary(x)
      clause2_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 2,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_binary, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>

      {clause1_iri, triples1} =
        ClauseBuilder.build_clause(clause1_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      {clause2_iri, triples2} =
        ClauseBuilder.build_clause(clause2_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify clauses have different IRIs
      assert clause1_iri != clause2_iri

      # Verify each has its own guard with different function names
      guard1_iri = find_guard_iri(clause1_iri, triples1)
      guard2_iri = find_guard_iri(clause2_iri, triples2)

      assert Enum.any?(triples1, fn {s, p, o} ->
               s == guard1_iri and p == Core.name() and RDF.Literal.value(o) == "is_integer"
             end)

      assert Enum.any?(triples2, fn {s, p, o} ->
               s == guard2_iri and p == Core.name() and RDF.Literal.value(o) == "is_binary"
             end)
    end

    test "handles mixed guarded and unguarded clauses" do
      context = full_mode_context()

      # Clause 1: with guard
      guarded_clause = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      # Clause 2: without guard (fallback)
      unguarded_clause = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 2,
        head: %{
          parameters: [{:x, [], nil}],
          guard: nil
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>

      {guarded_iri, guarded_triples} =
        ClauseBuilder.build_clause(guarded_clause, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      {unguarded_iri, unguarded_triples} =
        ClauseBuilder.build_clause(unguarded_clause, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify guarded clause has guard
      assert find_guard_iri(guarded_iri, guarded_triples) != nil

      # Verify unguarded clause has no guard
      assert find_guard_iri(unguarded_iri, unguarded_triples) == nil
    end
  end

  # ===========================================================================
  # Light Mode Backward Compatibility
  # ===========================================================================

  describe "light mode (backward compatibility)" do
    test "uses blank node for guard in light mode" do
      context = Context.new(base_iri: @base_iri)

      clause_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>
      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the guard triple
      head_bnode = find_head_bnode(clause_iri, triples)
      guard_node = find_object(triples, head_bnode, Core.hasGuard())

      # In light mode, guard should be a blank node
      assert is_struct(guard_node, RDF.BlankNode)
    end

    test "light mode does not extract expression trees" do
      context = Context.new(base_iri: @base_iri)

      clause_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>
      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Should only have basic guard triples, not expression tree
      # Count triples - should be much fewer than full mode
      assert length(triples) < 20
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles deeply nested and/or combinations" do
      context = full_mode_context()

      # a and b and c
      guard_ast =
        {:and, [],
         [
           {:is_integer, [], [{:x, [], nil}]},
           {:and, [], [{:>, [], [{:x, [], nil}, 0]}, {:<, [], [{:x, [], nil}, 100]}]}
         ]}

      clause_info = %Clause{
        name: :range_check,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: guard_ast
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/range_check/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Verify nested structure exists
      guard_iri = find_guard_iri(clause_iri, triples)
      assert guard_iri != nil

      # Should have nested and operator
      inner_and_iri = find_object(triples, guard_iri, Core.hasRightOperand())
      assert inner_and_iri != nil
    end

    test "handles guard with multiple arguments" do
      context = full_mode_context()

      # is_function(x, 1)
      guard_ast = {:is_function, [], [{:x, [], nil}, 1]}

      clause_info = %Clause{
        name: :check_function,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: guard_ast
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/check_function/1>

      {clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      guard_iri = find_guard_iri(clause_iri, triples)

      # Verify hasArgument links
      args = find_all_objects(triples, guard_iri, Core.hasArgument())
      assert length(args) == 2
    end
  end

  # ===========================================================================
  # SPARQL Query Tests
  # ===========================================================================

  describe "SPARQL query patterns" do
    test "guards are queryable by inGuardContext property" do
      context = full_mode_context()

      clause_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_integer, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>

      {_clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Simulate SPARQL query: Find all expressions with inGuardContext = true
      guard_expressions =
        Enum.filter(triples, fn {_s, p, o} ->
          p == Core.inGuardContext() and RDF.Literal.value(o) == true
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      # Should find at least the guard expression
      assert length(guard_expressions) >= 1
    end

    test "can find all functions using specific guard function" do
      context = full_mode_context()

      clause_info = %Clause{
        name: :process,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:x, [], nil}],
          guard: {:is_binary, [], [{:x, [], nil}]}
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/process/1>

      {_clause_iri, triples} =
        ClauseBuilder.build_clause(clause_info, function_iri, context,
          expression_builder: ExpressionBuilder
        )

      # Simulate SPARQL: Find all LocalCalls with name "is_binary"
      is_binary_calls =
        Enum.filter(triples, fn {_s, p, o} ->
          p == Core.name() and RDF.Literal.value(o) == "is_binary"
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      assert length(is_binary_calls) == 1
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp full_mode_context do
    Context.new(
      base_iri: @base_iri,
      config: %{include_expressions: true},
      file_path: "lib/my_app.ex"
    )
  end

  defp find_guard_iri(clause_iri, triples) do
    head_bnode = find_head_bnode(clause_iri, triples)
    find_object(triples, head_bnode, Core.hasGuard())
  end

  defp find_head_bnode(clause_iri, triples) do
    result =
      Enum.find(triples, fn {s, p, _o} ->
        s == clause_iri and p == Structure.hasHead()
      end)

    if result, do: elem(result, 2), else: nil
  end

  defp find_object(triples, subject, predicate) do
    result =
      Enum.find(triples, fn {s, p, _o} ->
        s == subject and p == predicate
      end)

    if result, do: elem(result, 2), else: nil
  end

  defp find_all_objects(triples, subject, predicate) do
    Enum.filter(triples, fn {s, p, _o} ->
      s == subject and p == predicate
    end)
    |> Enum.map(fn {_s, _p, o} -> o end)
  end
end
