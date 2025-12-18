defmodule ElixirOntologies.Extractors.OperatorTest do
  @moduledoc """
  Tests for the Operator extractor module.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Operator

  doctest Operator

  # ============================================================================
  # Arithmetic Operator Tests
  # ============================================================================

  describe "arithmetic operators" do
    test "extracts addition operator" do
      ast = {:+, [], [1, 2]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :+
      assert result.operator_class == :BinaryOperator
      assert result.arity == 2
      assert result.operands.left == 1
      assert result.operands.right == 2
    end

    test "extracts subtraction operator" do
      ast = {:-, [], [5, 3]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :-
      assert result.operands.left == 5
      assert result.operands.right == 3
    end

    test "extracts multiplication operator" do
      ast = {:*, [], [2, 4]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :*
    end

    test "extracts division operator" do
      ast = {:/, [], [10, 2]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :/
    end

    test "extracts div operator" do
      ast = {:div, [], [10, 3]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :div
    end

    test "extracts rem operator" do
      ast = {:rem, [], [10, 3]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :rem
    end

    test "extracts unary minus (negation)" do
      ast = {:-, [], [{:x, [], Elixir}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :arithmetic
      assert result.symbol == :-
      assert result.operator_class == :UnaryOperator
      assert result.arity == 1
      assert result.operands.operand == {:x, [], Elixir}
    end
  end

  # ============================================================================
  # Comparison Operator Tests
  # ============================================================================

  describe "comparison operators" do
    test "extracts == operator" do
      ast = {:==, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :==
      assert result.operator_class == :BinaryOperator
    end

    test "extracts != operator" do
      ast = {:!=, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :!=
    end

    test "extracts === operator" do
      ast = {:===, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :===
    end

    test "extracts !== operator" do
      ast = {:!==, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :!==
    end

    test "extracts < operator" do
      ast = {:<, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :<
    end

    test "extracts > operator" do
      ast = {:>, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :>
    end

    test "extracts <= operator" do
      ast = {:<=, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :<=
    end

    test "extracts >= operator" do
      ast = {:>=, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :comparison
      assert result.symbol == :>=
    end
  end

  # ============================================================================
  # Logical Operator Tests
  # ============================================================================

  describe "logical operators" do
    test "extracts and operator" do
      ast = {:and, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :and
      assert result.operator_class == :BinaryOperator
      assert result.metadata.strict_boolean == true
      assert result.metadata.is_shortcircuit == true
    end

    test "extracts or operator" do
      ast = {:or, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :or
      assert result.metadata.strict_boolean == true
    end

    test "extracts not operator (unary)" do
      ast = {:not, [], [{:a, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :not
      assert result.operator_class == :UnaryOperator
      assert result.arity == 1
      assert result.metadata.strict_boolean == true
    end

    test "extracts && operator" do
      ast = {:&&, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :&&
      assert result.metadata.strict_boolean == false
      assert result.metadata.is_shortcircuit == true
    end

    test "extracts || operator" do
      ast = {:||, [], [{:a, [], nil}, {:b, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :||
      assert result.metadata.strict_boolean == false
    end

    test "extracts ! operator (unary)" do
      ast = {:!, [], [{:a, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :logical
      assert result.symbol == :!
      assert result.operator_class == :UnaryOperator
      assert result.metadata.strict_boolean == false
    end
  end

  # ============================================================================
  # Pipe Operator Tests
  # ============================================================================

  describe "pipe operator" do
    test "extracts |> operator" do
      ast = {:|>, [], [{:x, [], nil}, {:f, [], []}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :pipe
      assert result.symbol == :|>
      assert result.operator_class == :BinaryOperator
      assert result.operands.left == {:x, [], nil}
      assert result.operands.right == {:f, [], []}
    end

    test "extracts chained pipe" do
      # x |> f() |> g() parses as nested
      # The outer pipe has left = (x |> f()) and right = g()
      inner_pipe = {:|>, [], [{:x, [], nil}, {:f, [], []}]}
      ast = {:|>, [], [inner_pipe, {:g, [], []}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :pipe
      assert result.operands.left == inner_pipe
      assert result.operands.right == {:g, [], []}
    end
  end

  # ============================================================================
  # Match Operator Tests
  # ============================================================================

  describe "match operator" do
    test "extracts = operator with variable binding" do
      ast = {:=, [], [{:x, [], nil}, 1]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :match
      assert result.symbol == :=
      assert result.operator_class == :BinaryOperator
      assert result.operands.left == {:x, [], nil}
      assert result.operands.right == 1
    end

    test "extracts = operator with pattern" do
      # {:ok, value} = result
      pattern = {:ok, {:value, [], nil}}
      ast = {:=, [], [pattern, {:result, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :match
      assert result.operands.left == pattern
    end
  end

  # ============================================================================
  # Capture Operator Tests
  # ============================================================================

  describe "capture operator" do
    test "extracts & with function reference" do
      # &foo/1
      ast = {:&, [], [{:/, [], [{:foo, [], nil}, 1]}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :capture
      assert result.symbol == :&
      assert result.operator_class == :UnaryOperator
      assert result.metadata.capture_type == :function_capture
    end

    test "extracts & with module function reference" do
      # &Enum.map/2
      ast =
        {:&, [],
         [
           {:/, [],
            [
              {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :map]}, [no_parens: true], []},
              2
            ]}
         ]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :capture
      assert result.symbol == :&
    end

    test "extracts & with anonymous function body" do
      # &(&1 + &2)
      ast =
        {:&, [],
         [
           {:+, [], [{:&, [], [1]}, {:&, [], [2]}]}
         ]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :capture
      assert result.symbol == :&
    end
  end

  # ============================================================================
  # String Concat Operator Tests
  # ============================================================================

  describe "string concat operator" do
    test "extracts <> operator" do
      ast = {:<>, [], ["hello", "world"]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :string_concat
      assert result.symbol == :<>
      assert result.operator_class == :BinaryOperator
      assert result.operands.left == "hello"
      assert result.operands.right == "world"
    end

    test "extracts <> with variables" do
      ast = {:<>, [], [{:prefix, [], nil}, {:suffix, [], nil}]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :string_concat
    end
  end

  # ============================================================================
  # List Operator Tests
  # ============================================================================

  describe "list operators" do
    test "extracts ++ operator" do
      ast = {:++, [], [[1, 2], [3, 4]]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :list
      assert result.symbol == :++
      assert result.operator_class == :BinaryOperator
      assert result.operands.left == [1, 2]
      assert result.operands.right == [3, 4]
    end

    test "extracts -- operator" do
      ast = {:--, [], [[1, 2, 3], [2]]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :list
      assert result.symbol == :--
    end
  end

  # ============================================================================
  # In Operator Tests
  # ============================================================================

  describe "in operator" do
    test "extracts in operator" do
      ast = {:in, [], [{:x, [], nil}, [1, 2, 3]]}

      assert {:ok, result} = Operator.extract(ast)
      assert result.type == :in
      assert result.symbol == :in
      assert result.operator_class == :BinaryOperator
      assert result.operands.left == {:x, [], nil}
      assert result.operands.right == [1, 2, 3]
    end
  end

  # ============================================================================
  # Type Detection Tests
  # ============================================================================

  describe "operator?/1" do
    test "returns true for operators" do
      assert Operator.operator?({:+, [], [1, 2]})
      assert Operator.operator?({:==, [], [{:a, [], nil}, {:b, [], nil}]})
      assert Operator.operator?({:|>, [], [{:x, [], nil}, {:f, [], []}]})
      assert Operator.operator?({:not, [], [{:a, [], nil}]})
    end

    test "returns false for non-operators" do
      refute Operator.operator?({:def, [], [{:foo, [], nil}]})
      refute Operator.operator?({:defmodule, [], [nil]})
      refute Operator.operator?(:atom)
      refute Operator.operator?(42)
      refute Operator.operator?("string")
    end
  end

  describe "operator_type/1" do
    test "returns correct type for each operator category" do
      assert Operator.operator_type({:+, [], [1, 2]}) == :arithmetic
      assert Operator.operator_type({:-, [], [1, 2]}) == :arithmetic
      assert Operator.operator_type({:==, [], [{:a, [], nil}, {:b, [], nil}]}) == :comparison
      assert Operator.operator_type({:and, [], [{:a, [], nil}, {:b, [], nil}]}) == :logical
      assert Operator.operator_type({:|>, [], [{:x, [], nil}, {:f, [], []}]}) == :pipe
      assert Operator.operator_type({:=, [], [{:x, [], nil}, 1]}) == :match
      assert Operator.operator_type({:&, [], [{:/, [], [{:foo, [], nil}, 1]}]}) == :capture
      assert Operator.operator_type({:<>, [], ["a", "b"]}) == :string_concat
      assert Operator.operator_type({:++, [], [[1], [2]]}) == :list
      assert Operator.operator_type({:in, [], [{:x, [], nil}, [1, 2]]}) == :in
    end

    test "returns nil for non-operators" do
      assert Operator.operator_type({:def, [], [{:foo, [], nil}]}) == nil
      assert Operator.operator_type(:atom) == nil
    end
  end

  describe "unary?/1" do
    test "identifies unary operators" do
      assert Operator.unary?({:-, [], [{:x, [], nil}]})
      assert Operator.unary?({:not, [], [{:a, [], nil}]})
      assert Operator.unary?({:!, [], [{:a, [], nil}]})
      assert Operator.unary?({:&, [], [{:/, [], [{:foo, [], nil}, 1]}]})
    end

    test "returns false for binary operators" do
      refute Operator.unary?({:+, [], [1, 2]})
      refute Operator.unary?({:-, [], [5, 3]})
      refute Operator.unary?({:and, [], [{:a, [], nil}, {:b, [], nil}]})
    end
  end

  describe "binary?/1" do
    test "identifies binary operators" do
      assert Operator.binary?({:+, [], [1, 2]})
      assert Operator.binary?({:-, [], [5, 3]})
      assert Operator.binary?({:==, [], [{:a, [], nil}, {:b, [], nil}]})
      assert Operator.binary?({:|>, [], [{:x, [], nil}, {:f, [], []}]})
    end

    test "returns false for unary operators" do
      refute Operator.binary?({:-, [], [{:x, [], nil}]})
      refute Operator.binary?({:not, [], [{:a, [], nil}]})
    end
  end

  # ============================================================================
  # Helper Function Tests
  # ============================================================================

  describe "operator_class/2" do
    test "returns UnaryOperator for arity 1" do
      assert Operator.operator_class(:-, 1) == :UnaryOperator
      assert Operator.operator_class(:not, 1) == :UnaryOperator
    end

    test "returns BinaryOperator for arity 2" do
      assert Operator.operator_class(:+, 2) == :BinaryOperator
      assert Operator.operator_class(:==, 2) == :BinaryOperator
    end
  end

  describe "symbol_string/1" do
    test "converts operator atoms to strings" do
      assert Operator.symbol_string(:+) == "+"
      assert Operator.symbol_string(:|>) == "|>"
      assert Operator.symbol_string(:and) == "and"
      assert Operator.symbol_string(:==) == "=="
      assert Operator.symbol_string(:<>) == "<>"
    end
  end

  describe "operators_of_type/1" do
    test "returns operators for each type" do
      assert :+ in Operator.operators_of_type(:arithmetic)
      assert :div in Operator.operators_of_type(:arithmetic)
      assert :== in Operator.operators_of_type(:comparison)
      assert :and in Operator.operators_of_type(:logical)
      assert :|> in Operator.operators_of_type(:pipe)
      assert := in Operator.operators_of_type(:match)
      assert :& in Operator.operators_of_type(:capture)
      assert :<> in Operator.operators_of_type(:string_concat)
      assert :++ in Operator.operators_of_type(:list)
      assert :in in Operator.operators_of_type(:in)
    end
  end

  describe "all_operators/0" do
    test "returns all known operators" do
      ops = Operator.all_operators()
      assert :+ in ops
      assert :== in ops
      assert :|> in ops
      assert := in ops
      assert :& in ops
      assert :<> in ops
      assert :++ in ops
      assert :in in ops
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "extract/1 error handling" do
    test "returns error for non-operator AST" do
      assert {:error, _} = Operator.extract({:def, [], [{:foo, [], nil}]})
    end

    test "returns error for atoms" do
      assert {:error, _} = Operator.extract(:atom)
    end

    test "returns error for integers" do
      assert {:error, _} = Operator.extract(42)
    end

    test "returns error for strings" do
      assert {:error, _} = Operator.extract("string")
    end
  end

  describe "extract!/1 error handling" do
    test "raises for non-operator" do
      assert_raise ArgumentError, fn ->
        Operator.extract!({:def, [], [{:foo, [], nil}]})
      end
    end
  end

  # ============================================================================
  # Metadata Tests
  # ============================================================================

  describe "metadata" do
    test "includes symbol_string" do
      {:ok, result} = Operator.extract({:+, [], [1, 2]})
      assert result.metadata.symbol_string == "+"
    end

    test "includes is_shortcircuit for logical operators" do
      {:ok, and_result} = Operator.extract({:and, [], [{:a, [], nil}, {:b, [], nil}]})
      assert and_result.metadata.is_shortcircuit == true

      {:ok, plus_result} = Operator.extract({:+, [], [1, 2]})
      assert plus_result.metadata.is_shortcircuit == false
    end

    test "includes strict_boolean for logical operators" do
      {:ok, and_result} = Operator.extract({:and, [], [{:a, [], nil}, {:b, [], nil}]})
      assert and_result.metadata.strict_boolean == true

      {:ok, amp_result} = Operator.extract({:&&, [], [{:a, [], nil}, {:b, [], nil}]})
      assert amp_result.metadata.strict_boolean == false
    end

    test "includes capture_type for capture operator" do
      {:ok, result} = Operator.extract({:&, [], [{:/, [], [{:foo, [], nil}, 1]}]})
      assert result.metadata.capture_type == :function_capture
    end
  end

  # ============================================================================
  # Location Extraction Tests
  # ============================================================================

  describe "location extraction" do
    test "extracts location when metadata present" do
      ast = {:+, [line: 10, column: 5], [1, 2]}

      {:ok, result} = Operator.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 10
      assert result.location.start_column == 5
    end

    test "handles missing location metadata" do
      ast = {:+, [], [1, 2]}

      {:ok, result} = Operator.extract(ast)
      assert result.location == nil
    end
  end
end
