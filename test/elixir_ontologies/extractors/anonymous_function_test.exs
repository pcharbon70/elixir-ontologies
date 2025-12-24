defmodule ElixirOntologies.Extractors.AnonymousFunctionTest do
  @moduledoc """
  Tests for the AnonymousFunction extractor module.

  These tests verify extraction of anonymous function definitions including
  single-clause, multi-clause, guards, and arity calculation.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.AnonymousFunction
  alias ElixirOntologies.Extractors.AnonymousFunction.Clause

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "anonymous_function?/1" do
    test "returns true for single-clause anonymous function" do
      ast = quote do: fn x -> x end
      assert AnonymousFunction.anonymous_function?(ast)
    end

    test "returns true for multi-clause anonymous function" do
      ast =
        quote do
          fn
            0 -> :zero
            _ -> :other
          end
        end

      assert AnonymousFunction.anonymous_function?(ast)
    end

    test "returns true for zero-arity anonymous function" do
      ast = quote do: fn -> :ok end
      assert AnonymousFunction.anonymous_function?(ast)
    end

    test "returns false for regular function definition" do
      ast = quote do: def(foo(x), do: x)
      refute AnonymousFunction.anonymous_function?(ast)
    end

    test "returns false for capture operator" do
      ast = quote do: &(&1 + 1)
      refute AnonymousFunction.anonymous_function?(ast)
    end

    test "returns false for non-AST values" do
      refute AnonymousFunction.anonymous_function?(:atom)
      refute AnonymousFunction.anonymous_function?("string")
      refute AnonymousFunction.anonymous_function?(123)
      refute AnonymousFunction.anonymous_function?(nil)
    end
  end

  # ===========================================================================
  # Single-Clause Extraction Tests
  # ===========================================================================

  describe "extract/1 single-clause" do
    test "extracts single-clause anonymous function with one parameter" do
      ast = quote do: fn x -> x + 1 end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert %AnonymousFunction{} = result
      assert result.arity == 1
      assert length(result.clauses) == 1

      [clause] = result.clauses
      assert %Clause{} = clause
      assert length(clause.parameters) == 1
      assert clause.guard == nil
      assert clause.order == 1
    end

    test "extracts single-clause anonymous function with multiple parameters" do
      ast = quote do: fn x, y, z -> x + y + z end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.arity == 3
      assert length(result.clauses) == 1

      [clause] = result.clauses
      assert length(clause.parameters) == 3
    end

    test "extracts zero-arity anonymous function" do
      ast = quote do: fn -> :ok end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.arity == 0
      assert length(result.clauses) == 1

      [clause] = result.clauses
      assert clause.parameters == []
    end

    test "extracts body correctly" do
      ast = quote do: fn x -> x * 2 end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses

      # Body should be the multiplication expression
      assert {:*, _, _} = clause.body
    end
  end

  # ===========================================================================
  # Multi-Clause Extraction Tests
  # ===========================================================================

  describe "extract/1 multi-clause" do
    test "extracts multi-clause anonymous function" do
      ast =
        quote do
          fn
            0 -> :zero
            1 -> :one
            _ -> :other
          end
        end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.arity == 1
      assert length(result.clauses) == 3

      [c1, c2, c3] = result.clauses
      assert c1.order == 1
      assert c2.order == 2
      assert c3.order == 3
    end

    test "preserves clause order for pattern matching semantics" do
      ast =
        quote do
          fn
            {:ok, val} -> val
            {:error, _} -> nil
            _ -> :unknown
          end
        end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [c1, c2, c3] = result.clauses

      assert c1.order == 1
      assert c2.order == 2
      assert c3.order == 3

      # First clause should have one parameter (the tuple pattern)
      assert length(c1.parameters) == 1
    end

    test "extracts correct arity from first clause" do
      ast =
        quote do
          fn
            x, y -> x + y
            a, b -> a - b
          end
        end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.arity == 2
    end
  end

  # ===========================================================================
  # Guard Extraction Tests
  # ===========================================================================

  describe "extract/1 with guards" do
    test "extracts guard from single parameter with guard" do
      ast = quote do: fn x when is_integer(x) -> x * 2 end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses

      assert length(clause.parameters) == 1
      assert clause.guard != nil

      # Guard should be is_integer(x)
      assert {:is_integer, _, _} = clause.guard
    end

    test "extracts guard from multi-clause with guards" do
      ast =
        quote do
          fn
            n when n > 0 -> :positive
            n when n < 0 -> :negative
            0 -> :zero
          end
        end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [c1, c2, c3] = result.clauses

      assert c1.guard != nil
      assert {:>, _, _} = c1.guard

      assert c2.guard != nil
      assert {:<, _, _} = c2.guard

      assert c3.guard == nil
    end

    test "extracts complex guard expression" do
      ast = quote do: fn x when is_number(x) and x > 0 -> x end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses

      # Guard should be and expression
      assert {:and, _, _} = clause.guard
    end

    test "extracts guard with multiple parameters" do
      ast = quote do: fn x, y when x > y -> {x, y} end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.arity == 2
      [clause] = result.clauses

      # When there are multiple params with a guard, the last param wraps the guard
      # The parameters list should have 2 entries
      assert result.arity == 2
      assert clause.guard != nil
      assert {:>, _, _} = clause.guard
    end
  end

  # ===========================================================================
  # Parameter Pattern Tests
  # ===========================================================================

  describe "extract/1 parameter patterns" do
    test "extracts literal pattern" do
      ast = quote do: fn 42 -> :answer end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      assert clause.parameters == [42]
    end

    test "extracts tuple pattern" do
      ast = quote do: fn {a, b} -> a + b end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      # Two-element tuples in AST are {a, b} directly, larger tuples use {:{}, _, [...]}
      assert length(clause.parameters) == 1
      [param] = clause.parameters
      assert is_tuple(param) and tuple_size(param) == 2
    end

    test "extracts list pattern" do
      ast = quote do: fn [head | tail] -> {head, tail} end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      assert length(clause.parameters) == 1
    end

    test "extracts map pattern" do
      ast = quote do: fn %{key: value} -> value end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      assert length(clause.parameters) == 1
    end

    test "extracts underscore pattern" do
      ast = quote do: fn _ -> :ignored end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      [{:_, _, _}] = clause.parameters
    end

    test "extracts pinned variable pattern" do
      ast = quote do: fn ^expected -> :match end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      [clause] = result.clauses
      [{:^, _, _}] = clause.parameters
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/1 error handling" do
    test "returns error for non-anonymous function" do
      ast = quote do: def(foo(x), do: x)
      assert {:error, :not_anonymous_function} = AnonymousFunction.extract(ast)
    end

    test "returns error for capture operator" do
      ast = quote do: &(&1 + 1)
      assert {:error, :not_anonymous_function} = AnonymousFunction.extract(ast)
    end

    test "returns error for atom" do
      assert {:error, :not_anonymous_function} = AnonymousFunction.extract(:atom)
    end

    test "returns error for nil" do
      assert {:error, :not_anonymous_function} = AnonymousFunction.extract(nil)
    end
  end

  # ===========================================================================
  # extract_all/1 Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all anonymous functions from AST" do
      ast =
        quote do
          a = fn x -> x end
          b = fn y -> y * 2 end
        end

      results = AnonymousFunction.extract_all(ast)
      assert length(results) == 2
      assert Enum.all?(results, &match?(%AnonymousFunction{}, &1))
    end

    test "extracts nested anonymous functions" do
      ast =
        quote do
          fn x ->
            fn y -> x + y end
          end
        end

      results = AnonymousFunction.extract_all(ast)
      assert length(results) == 2
    end

    test "returns empty list when no anonymous functions" do
      ast = quote do: 1 + 2
      results = AnonymousFunction.extract_all(ast)
      assert results == []
    end

    test "extracts anonymous functions from complex AST" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
          Enum.filter(list, fn x -> x > 0 end)
          Enum.reduce(list, 0, fn x, acc -> x + acc end)
        end

      results = AnonymousFunction.extract_all(ast)
      assert length(results) == 3
    end
  end

  # ===========================================================================
  # Metadata and Location Tests
  # ===========================================================================

  describe "metadata" do
    test "initializes empty metadata map" do
      ast = quote do: fn x -> x end

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.metadata == %{}
    end

    test "captures location when available" do
      # Create AST with location metadata (needs both line and column)
      ast =
        {:fn, [line: 42, column: 5],
         [{:->, [line: 42, column: 8], [[{:x, [], nil}], {:x, [], nil}]}]}

      assert {:ok, result} = AnonymousFunction.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 42
    end
  end

  # ===========================================================================
  # Clause AST Detection (18.1.2)
  # ===========================================================================

  describe "clause_ast?/1" do
    test "returns true for valid clause AST" do
      ast = {:->, [], [[{:x, [], nil}], :ok]}
      assert AnonymousFunction.clause_ast?(ast)
    end

    test "returns true for clause with multiple parameters" do
      ast = {:->, [], [[{:x, [], nil}, {:y, [], nil}], :ok]}
      assert AnonymousFunction.clause_ast?(ast)
    end

    test "returns true for clause with no parameters" do
      ast = {:->, [], [[], :ok]}
      assert AnonymousFunction.clause_ast?(ast)
    end

    test "returns false for anonymous function" do
      ast = {:fn, [], [{:->, [], [[], :ok]}]}
      refute AnonymousFunction.clause_ast?(ast)
    end

    test "returns false for non-AST" do
      refute AnonymousFunction.clause_ast?(:not_ast)
      refute AnonymousFunction.clause_ast?("string")
      refute AnonymousFunction.clause_ast?(123)
    end
  end

  # ===========================================================================
  # Standalone Clause Extraction (18.1.2)
  # ===========================================================================

  describe "extract_clause/1" do
    test "extracts single-parameter clause" do
      ast = {:->, [], [[{:x, [], nil}], {:x, [], nil}]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert clause.arity == 1
      assert clause.order == nil
      assert length(clause.parameters) == 1
    end

    test "extracts multi-parameter clause" do
      ast = {:->, [], [[{:x, [], nil}, {:y, [], nil}], :ok]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert clause.arity == 2
      assert length(clause.parameters) == 2
    end

    test "extracts clause with guard" do
      # fn x when is_integer(x) -> x end - the clause part
      ast =
        {:->, [],
         [
           [{:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}],
           {:x, [], nil}
         ]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert clause.arity == 1
      assert clause.guard != nil
    end

    test "extracts parameter patterns" do
      ast = {:->, [], [[{:x, [], nil}], :ok]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert is_list(clause.parameter_patterns)
      assert length(clause.parameter_patterns) == 1
      [pattern] = clause.parameter_patterns
      assert pattern.type == :variable
    end

    test "collects bound variables" do
      ast = {:->, [], [[{:x, [], nil}, {:y, [], nil}], :ok]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert :x in clause.bound_variables
      assert :y in clause.bound_variables
    end

    test "handles tuple pattern with bindings" do
      # Create a clause AST with a tuple pattern
      ast = {:->, [], [[{:{}, [], [:ok, {:result, [], nil}]}], {:result, [], nil}]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast)
      assert clause.arity == 1
      assert :result in clause.bound_variables
    end

    test "returns error for non-clause AST" do
      ast = {:def, [], [{:foo, [], nil}]}
      assert {:error, :not_clause} = AnonymousFunction.extract_clause(ast)
    end

    test "can skip pattern extraction" do
      ast = {:->, [], [[{:x, [], nil}], :ok]}

      assert {:ok, clause} = AnonymousFunction.extract_clause(ast, include_patterns: false)
      assert clause.parameter_patterns == nil
      assert clause.bound_variables == []
    end
  end

  # ===========================================================================
  # Clause Extraction with Order (18.1.2)
  # ===========================================================================

  describe "extract_clause_with_order/2" do
    test "extracts clause with explicit order" do
      ast = {:->, [], [[0], :zero]}

      assert {:ok, clause} = AnonymousFunction.extract_clause_with_order(ast, 1)
      assert clause.order == 1
      assert clause.arity == 1
    end

    test "extracts clause with higher order" do
      ast = {:->, [], [[{:n, [], nil}], :positive]}

      assert {:ok, clause} = AnonymousFunction.extract_clause_with_order(ast, 3)
      assert clause.order == 3
    end

    test "returns error for invalid order" do
      ast = {:->, [], [[], :ok]}
      assert {:error, :not_clause} = AnonymousFunction.extract_clause_with_order(ast, 0)
      assert {:error, :not_clause} = AnonymousFunction.extract_clause_with_order(ast, -1)
    end

    test "returns error for non-clause AST" do
      assert {:error, :not_clause} =
               AnonymousFunction.extract_clause_with_order({:def, [], []}, 1)
    end
  end

  # ===========================================================================
  # Enhanced Clause Fields (18.1.2)
  # ===========================================================================

  describe "clause arity field" do
    test "clauses from extract/1 have arity" do
      ast = quote do: fn x, y -> x + y end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert clause.arity == 2
    end

    test "multi-clause function clauses have correct arity" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      assert Enum.all?(anon.clauses, fn c -> c.arity == 1 end)
    end
  end

  describe "clause parameter_patterns field" do
    test "clauses have pattern analysis" do
      ast = quote do: fn {:ok, value} -> value end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert is_list(clause.parameter_patterns)
      [pattern] = clause.parameter_patterns
      assert pattern.type == :tuple
    end

    test "wildcard patterns are recognized" do
      ast = quote do: fn _ -> :ok end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      [pattern] = clause.parameter_patterns
      assert pattern.type == :wildcard
    end

    test "literal patterns are recognized" do
      ast = quote do: fn 0 -> :zero end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      [pattern] = clause.parameter_patterns
      assert pattern.type == :literal
    end
  end

  describe "clause bound_variables field" do
    test "collects variables from simple patterns" do
      ast = quote do: fn x -> x end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert :x in clause.bound_variables
    end

    test "collects variables from nested patterns" do
      ast = quote do: fn {:ok, {a, b}} -> {a, b} end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert :a in clause.bound_variables
      assert :b in clause.bound_variables
    end

    test "empty for wildcard-only patterns" do
      ast = quote do: fn _ -> :ok end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert clause.bound_variables == []
    end

    test "empty for literal-only patterns" do
      ast = quote do: fn 42 -> :answer end

      assert {:ok, anon} = AnonymousFunction.extract(ast)
      [clause] = anon.clauses
      assert clause.bound_variables == []
    end
  end

  # ===========================================================================
  # Doctest Verification
  # ===========================================================================

  doctest ElixirOntologies.Extractors.AnonymousFunction
end
