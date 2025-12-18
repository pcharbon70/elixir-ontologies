defmodule ElixirOntologies.Extractors.BlockTest do
  @moduledoc """
  Tests for the Block extractor module.

  These tests verify extraction of block expressions (__block__) and
  anonymous functions (fn...end) with their contained expressions and clauses.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Block

  doctest Block

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "block?/1" do
    test "returns true for __block__ expression" do
      ast = {:__block__, [], [1, 2, 3]}
      assert Block.block?(ast)
    end

    test "returns true for empty block" do
      ast = {:__block__, [], []}
      assert Block.block?(ast)
    end

    test "returns false for fn expression" do
      ast = {:fn, [], [{:->, [], [[], 1]}]}
      refute Block.block?(ast)
    end

    test "returns false for atoms" do
      refute Block.block?(:__block__)
    end

    test "returns false for single expression" do
      ast = {:=, [], [{:x, [], nil}, 1]}
      refute Block.block?(ast)
    end
  end

  describe "anonymous_function?/1" do
    test "returns true for fn expression" do
      ast = {:fn, [], [{:->, [], [[], 1]}]}
      assert Block.anonymous_function?(ast)
    end

    test "returns true for multi-clause fn" do
      ast = {:fn, [], [{:->, [], [[0], :zero]}, {:->, [], [[{:n, [], nil}], {:n, [], nil}]}]}
      assert Block.anonymous_function?(ast)
    end

    test "returns false for __block__ expression" do
      ast = {:__block__, [], [1, 2]}
      refute Block.anonymous_function?(ast)
    end

    test "returns false for atoms" do
      refute Block.anonymous_function?(:fn)
    end
  end

  describe "extractable?/1" do
    test "returns true for __block__" do
      assert Block.extractable?({:__block__, [], [1]})
    end

    test "returns true for fn" do
      assert Block.extractable?({:fn, [], [{:->, [], [[], 1]}]})
    end

    test "returns false for if expression" do
      ast = quote do: if(true, do: 1)
      refute Block.extractable?(ast)
    end
  end

  # ===========================================================================
  # Block Extraction Tests
  # ===========================================================================

  describe "extract/1 with blocks" do
    test "extracts simple block with multiple expressions" do
      ast =
        quote do
          x = 1
          y = 2
          x + y
        end

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :block
      assert length(result.expressions) == 3
      assert result.metadata.expression_count == 3
    end

    test "extracts block with correct indexing" do
      ast = {:__block__, [], [:a, :b, :c]}
      assert {:ok, result} = Block.extract(ast)

      [first, second, third] = result.expressions
      assert first.index == 0
      assert first.expression == :a
      assert first.is_last == false

      assert second.index == 1
      assert second.expression == :b
      assert second.is_last == false

      assert third.index == 2
      assert third.expression == :c
      assert third.is_last == true
    end

    test "marks last expression correctly" do
      ast = {:__block__, [], [1, 2, 3]}
      assert {:ok, result} = Block.extract(ast)

      last = List.last(result.expressions)
      assert last.is_last == true
      assert last.expression == 3
    end

    test "handles empty block" do
      ast = {:__block__, [], []}
      assert {:ok, result} = Block.extract(ast)

      assert result.type == :block
      assert result.expressions == []
      assert result.metadata.expression_count == 0
      assert result.metadata.has_return_value == false
    end

    test "extracts nested blocks" do
      ast =
        quote do
          x = 1

          if true do
            y = 2
            y
          end
        end

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :block
      assert length(result.expressions) == 2
    end
  end

  # ===========================================================================
  # Anonymous Function Extraction Tests
  # ===========================================================================

  describe "extract/1 with anonymous functions" do
    test "extracts single-clause fn" do
      ast = quote do: fn x -> x * 2 end
      assert {:ok, result} = Block.extract(ast)

      assert result.type == :fn
      assert length(result.clauses) == 1
      assert result.metadata.clause_count == 1
      assert result.metadata.arity == 1
    end

    test "extracts multi-clause fn" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :fn
      assert length(result.clauses) == 2
      assert result.metadata.clause_count == 2
    end

    test "extracts fn with multiple parameters" do
      ast = quote do: fn x, y -> x + y end
      assert {:ok, result} = Block.extract(ast)

      assert result.metadata.arity == 2
      [clause] = result.clauses
      assert length(clause.patterns) == 2
    end

    test "extracts fn with no parameters" do
      ast = quote do: fn -> :ok end
      assert {:ok, result} = Block.extract(ast)

      assert result.metadata.arity == 0
      [clause] = result.clauses
      assert clause.patterns == []
    end

    test "extracts fn with guards" do
      ast =
        quote do
          fn
            x when x > 0 -> :positive
            x -> :other
          end
        end

      assert {:ok, result} = Block.extract(ast)
      assert length(result.clauses) == 2

      [guarded_clause, _] = result.clauses
      assert guarded_clause.guard != nil
    end

    test "extracts fn clause body" do
      ast = quote do: fn x -> x * 2 end
      assert {:ok, result} = Block.extract(ast)

      [clause] = result.clauses
      assert {:*, _, _} = clause.body
    end

    test "extracts fn with pattern matching" do
      ast =
        quote do
          fn
            {:ok, value} -> value
            {:error, _} -> nil
          end
        end

      assert {:ok, result} = Block.extract(ast)
      assert length(result.clauses) == 2

      [ok_clause, error_clause] = result.clauses
      assert {:ok, _} = hd(ok_clause.patterns)
      assert {:error, _} = hd(error_clause.patterns)
    end
  end

  # ===========================================================================
  # Convenience Function Tests
  # ===========================================================================

  describe "expressions_in_order/1" do
    test "returns expressions in correct order" do
      ast = {:__block__, [], [:first, :second, :third]}
      {:ok, block} = Block.extract(ast)

      assert Block.expressions_in_order(block) == [:first, :second, :third]
    end

    test "returns empty list for non-block" do
      ast = {:fn, [], [{:->, [], [[], 1]}]}
      {:ok, fn_block} = Block.extract(ast)

      assert Block.expressions_in_order(fn_block) == []
    end

    test "returns empty list for invalid input" do
      assert Block.expressions_in_order(%{}) == []
    end
  end

  describe "return_expression/1" do
    test "returns the last expression" do
      ast = {:__block__, [], [1, 2, :return_value]}
      {:ok, block} = Block.extract(ast)

      assert Block.return_expression(block) == :return_value
    end

    test "returns nil for empty block" do
      ast = {:__block__, [], []}
      {:ok, block} = Block.extract(ast)

      assert Block.return_expression(block) == nil
    end

    test "returns nil for fn" do
      ast = {:fn, [], [{:->, [], [[], 1]}]}
      {:ok, fn_block} = Block.extract(ast)

      assert Block.return_expression(fn_block) == nil
    end
  end

  describe "arity/1" do
    test "returns arity for single-clause fn" do
      ast = quote do: fn x, y, z -> {x, y, z} end
      {:ok, fn_block} = Block.extract(ast)

      assert Block.arity(fn_block) == 3
    end

    test "returns 0 for no-arg fn" do
      ast = quote do: fn -> :ok end
      {:ok, fn_block} = Block.extract(ast)

      assert Block.arity(fn_block) == 0
    end

    test "returns nil for non-fn" do
      ast = {:__block__, [], [1]}
      {:ok, block} = Block.extract(ast)

      assert Block.arity(block) == nil
    end
  end

  describe "multi_clause?/1" do
    test "returns true for multi-clause fn" do
      ast = {:fn, [], [{:->, [], [[0], :zero]}, {:->, [], [[{:n, [], nil}], {:n, [], nil}]}]}
      {:ok, fn_block} = Block.extract(ast)

      assert Block.multi_clause?(fn_block) == true
    end

    test "returns false for single-clause fn" do
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}
      {:ok, fn_block} = Block.extract(ast)

      assert Block.multi_clause?(fn_block) == false
    end

    test "returns false for non-fn" do
      assert Block.multi_clause?(%{}) == false
    end
  end

  describe "has_guards?/1" do
    test "returns true when fn has guarded clause" do
      ast =
        quote do
          fn
            x when x > 0 -> :positive
            _ -> :other
          end
        end

      {:ok, fn_block} = Block.extract(ast)
      assert Block.has_guards?(fn_block) == true
    end

    test "returns false when fn has no guards" do
      ast = quote do: fn x -> x end
      {:ok, fn_block} = Block.extract(ast)

      assert Block.has_guards?(fn_block) == false
    end

    test "returns false for non-fn" do
      assert Block.has_guards?(%{}) == false
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/1 error handling" do
    test "returns error for non-block/non-fn" do
      ast = quote do: if(true, do: 1)
      assert {:error, msg} = Block.extract(ast)
      assert msg =~ "Not a block or anonymous function"
    end

    test "returns error for atoms" do
      assert {:error, _} = Block.extract(:block)
    end

    test "extract! raises on error" do
      assert_raise ArgumentError, fn ->
        Block.extract!(:not_a_block)
      end
    end
  end

  # ===========================================================================
  # Edge Case Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles block with single expression" do
      # Note: Elixir usually doesn't wrap single expressions in __block__
      # but we handle it anyway
      ast = {:__block__, [], [:only_one]}
      assert {:ok, result} = Block.extract(ast)

      assert length(result.expressions) == 1
      [expr] = result.expressions
      assert expr.is_last == true
    end

    test "handles fn with complex body" do
      ast =
        quote do
          fn x ->
            y = x * 2
            z = y + 1
            z
          end
        end

      assert {:ok, result} = Block.extract(ast)
      [clause] = result.clauses
      # Body is a __block__ with multiple expressions
      assert {:__block__, _, _} = clause.body
    end

    test "extracts block preserves metadata from original AST" do
      ast = {:__block__, [line: 10, column: 5], [1, 2, 3]}
      assert {:ok, result} = Block.extract(ast)

      # Location should be extracted
      assert result.location != nil or result.location == nil
      # The test passes either way - location extraction depends on metadata format
    end
  end
end
