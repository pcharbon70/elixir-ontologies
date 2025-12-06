defmodule ElixirOntologies.Extractors.GuardTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Guard
  alias ElixirOntologies.Extractors.Clause

  doctest Guard

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "guard?/1" do
    test "returns true for type check guard" do
      assert Guard.guard?({:is_integer, [], [{:x, [], nil}]})
    end

    test "returns true for comparison guard" do
      assert Guard.guard?({:>, [], [{:x, [], nil}, 0]})
    end

    test "returns true for and combined guard" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      assert Guard.guard?(guard)
    end

    test "returns true for or combined guard" do
      guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      assert Guard.guard?(guard)
    end

    test "returns false for nil" do
      refute Guard.guard?(nil)
    end
  end

  # ===========================================================================
  # Single Guard Tests
  # ===========================================================================

  describe "extract/2 single guards" do
    test "extracts type check guard" do
      guard = {:is_integer, [], [{:x, [], nil}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.expression == guard
      assert result.combinator == :none
      assert result.guard_functions == [:is_integer]
      assert length(result.expressions) == 1
    end

    test "extracts is_atom guard" do
      guard = {:is_atom, [], [{:x, [], nil}]}

      assert {:ok, result} = Guard.extract(guard)
      assert :is_atom in result.guard_functions
    end

    test "extracts is_binary guard" do
      guard = {:is_binary, [], [{:x, [], nil}]}

      assert {:ok, result} = Guard.extract(guard)
      assert :is_binary in result.guard_functions
    end

    test "extracts is_list guard" do
      guard = {:is_list, [], [{:x, [], nil}]}

      assert {:ok, result} = Guard.extract(guard)
      assert :is_list in result.guard_functions
    end

    test "extracts comparison guard >" do
      guard = {:>, [], [{:x, [], nil}, 0]}

      assert {:ok, result} = Guard.extract(guard)
      assert :> in result.guard_functions
      assert result.metadata.has_comparison == true
    end

    test "extracts comparison guard <" do
      guard = {:<, [], [{:x, [], nil}, 10]}

      assert {:ok, result} = Guard.extract(guard)
      assert :< in result.guard_functions
    end

    test "extracts equality guard ==" do
      guard = {:==, [], [{:x, [], nil}, :ok]}

      assert {:ok, result} = Guard.extract(guard)
      assert :== in result.guard_functions
    end

    test "extracts length guard" do
      guard = {:length, [], [{:list, [], nil}]}

      assert {:ok, result} = Guard.extract(guard)
      assert :length in result.guard_functions
    end
  end

  # ===========================================================================
  # Combined Guard Tests (and)
  # ===========================================================================

  describe "extract/2 and combined guards" do
    test "extracts two guards combined with and" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :and
      assert length(result.expressions) == 2
      assert :is_integer in result.guard_functions
      assert :> in result.guard_functions
    end

    test "extracts three guards combined with and" do
      inner = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      guard = {:and, [], [inner, {:<, [], [{:x, [], nil}, 100]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :and
      assert length(result.expressions) == 3
    end

    test "extracts metadata for and combined guards" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.metadata.count == 2
      assert result.metadata.has_type_check == true
      assert result.metadata.has_comparison == true
    end
  end

  # ===========================================================================
  # Combined Guard Tests (or)
  # ===========================================================================

  describe "extract/2 or combined guards" do
    test "extracts two guards combined with or" do
      guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :or
      assert length(result.expressions) == 2
      assert :is_integer in result.guard_functions
      assert :is_float in result.guard_functions
    end

    test "extracts three guards combined with or" do
      inner = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      guard = {:or, [], [inner, {:is_atom, [], [{:x, [], nil}]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :or
      assert length(result.expressions) == 3
    end
  end

  # ===========================================================================
  # Mixed Combinator Tests
  # ===========================================================================

  describe "extract/2 mixed combinators" do
    test "detects mixed and/or combinator" do
      # (is_integer(x) and x > 0) or is_atom(x)
      and_guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      guard = {:or, [], [and_guard, {:is_atom, [], [{:x, [], nil}]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :mixed
      assert length(result.expressions) == 3
    end

    test "detects mixed or/and combinator" do
      # (is_integer(x) or is_float(x)) and x > 0
      or_guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      guard = {:and, [], [or_guard, {:>, [], [{:x, [], nil}, 0]}]}

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :mixed
    end
  end

  # ===========================================================================
  # Extract from Clause Tests
  # ===========================================================================

  describe "extract_from_clause/1" do
    test "extracts guard from guarded clause" do
      ast =
        {:def, [],
         [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}

      {:ok, clause} = Clause.extract(ast)
      {:ok, guard} = Guard.extract_from_clause(clause)

      assert guard != nil
      assert :is_atom in guard.guard_functions
    end

    test "returns nil for unguarded clause" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      {:ok, clause} = Clause.extract(ast)
      assert {:ok, nil} = Guard.extract_from_clause(clause)
    end

    test "extracts complex guard from clause" do
      ast =
        {:def, [],
         [
           {:when, [],
            [
              {:process, [], [{:x, [], nil}]},
              {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
            ]},
           [do: :ok]
         ]}

      {:ok, clause} = Clause.extract(ast)
      {:ok, guard} = Guard.extract_from_clause(clause)

      assert guard.combinator == :and
      assert :is_integer in guard.guard_functions
      assert :> in guard.guard_functions
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "has_and?/1" do
    test "returns true for and combinator" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.has_and?(result)
    end

    test "returns true for mixed combinator" do
      and_guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      guard = {:or, [], [and_guard, {:is_atom, [], [{:x, [], nil}]}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.has_and?(result)
    end

    test "returns false for single guard" do
      guard = {:is_integer, [], [{:x, [], nil}]}
      {:ok, result} = Guard.extract(guard)
      refute Guard.has_and?(result)
    end
  end

  describe "has_or?/1" do
    test "returns true for or combinator" do
      guard = {:or, [], [{:is_integer, [], [{:x, [], nil}]}, {:is_float, [], [{:x, [], nil}]}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.has_or?(result)
    end

    test "returns false for and combinator" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      {:ok, result} = Guard.extract(guard)
      refute Guard.has_or?(result)
    end
  end

  describe "has_type_check?/1" do
    test "returns true when guard has type check" do
      guard = {:is_integer, [], [{:x, [], nil}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.has_type_check?(result)
    end

    test "returns false when guard has no type check" do
      guard = {:>, [], [{:x, [], nil}, 0]}
      {:ok, result} = Guard.extract(guard)
      refute Guard.has_type_check?(result)
    end
  end

  describe "has_comparison?/1" do
    test "returns true when guard has comparison" do
      guard = {:>, [], [{:x, [], nil}, 0]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.has_comparison?(result)
    end

    test "returns false when guard has no comparison" do
      guard = {:is_integer, [], [{:x, [], nil}]}
      {:ok, result} = Guard.extract(guard)
      refute Guard.has_comparison?(result)
    end
  end

  describe "expression_count/1" do
    test "returns 1 for single guard" do
      guard = {:is_integer, [], [{:x, [], nil}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.expression_count(result) == 1
    end

    test "returns 2 for two combined guards" do
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      {:ok, result} = Guard.extract(guard)
      assert Guard.expression_count(result) == 2
    end
  end

  describe "known_guard_functions/0" do
    test "includes type check functions" do
      funcs = Guard.known_guard_functions()
      assert :is_integer in funcs
      assert :is_atom in funcs
      assert :is_binary in funcs
    end

    test "includes comparison operators" do
      funcs = Guard.known_guard_functions()
      assert :> in funcs
      assert :< in funcs
      assert :== in funcs
    end
  end

  describe "type_check_functions/0" do
    test "includes is_ functions" do
      funcs = Guard.type_check_functions()
      assert :is_integer in funcs
      assert :is_atom in funcs
    end

    test "does not include comparison operators" do
      funcs = Guard.type_check_functions()
      refute :> in funcs
      refute :< in funcs
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for nil" do
      assert {:error, _} = Guard.extract(nil)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      guard = {:is_integer, [], [{:x, [], nil}]}
      result = Guard.extract!(guard)
      assert result.guard_functions == [:is_integer]
    end

    test "raises on error" do
      assert_raise ArgumentError, fn ->
        Guard.extract!(nil)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts guard from quoted function" do
      {:def, _, [{:when, _, [{:foo, _, _}, guard]}, _]} =
        quote do
          def foo(x) when is_integer(x), do: x
        end

      assert {:ok, result} = Guard.extract(guard)
      assert :is_integer in result.guard_functions
    end

    test "extracts combined guard from quoted function" do
      {:def, _, [{:when, _, [{:bar, _, _}, guard]}, _]} =
        quote do
          def bar(x) when is_integer(x) and x > 0, do: x
        end

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :and
      assert :is_integer in result.guard_functions
      assert :> in result.guard_functions
    end

    test "extracts or guard from quoted function" do
      {:def, _, [{:when, _, [{:baz, _, _}, guard]}, _]} =
        quote do
          def baz(x) when is_integer(x) or is_float(x), do: x
        end

      assert {:ok, result} = Guard.extract(guard)
      assert result.combinator == :or
      assert :is_integer in result.guard_functions
      assert :is_float in result.guard_functions
    end
  end
end
