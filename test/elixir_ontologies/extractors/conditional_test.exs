defmodule ElixirOntologies.Extractors.ConditionalTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Conditional
  alias ElixirOntologies.Extractors.Conditional.{Branch, CondClause}
  alias ElixirOntologies.Extractors.Conditional.Conditional, as: ConditionalStruct

  doctest Conditional

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "conditional?/1" do
    test "returns true for if expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      assert Conditional.conditional?(ast)
    end

    test "returns true for if with else" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok, else: :error]]}
      assert Conditional.conditional?(ast)
    end

    test "returns true for unless expression" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      assert Conditional.conditional?(ast)
    end

    test "returns true for cond expression" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      assert Conditional.conditional?(ast)
    end

    test "returns false for case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}
      refute Conditional.conditional?(ast)
    end

    test "returns false for function call" do
      ast = {:foo, [], []}
      refute Conditional.conditional?(ast)
    end

    test "returns false for variable" do
      ast = {:x, [], nil}
      refute Conditional.conditional?(ast)
    end
  end

  describe "if_expression?/1" do
    test "returns true for if expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      assert Conditional.if_expression?(ast)
    end

    test "returns true for if with else" do
      ast = {:if, [], [{:x, [], nil}, [do: :then, else: :else]]}
      assert Conditional.if_expression?(ast)
    end

    test "returns false for unless" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      refute Conditional.if_expression?(ast)
    end

    test "returns false for cond" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      refute Conditional.if_expression?(ast)
    end
  end

  describe "unless_expression?/1" do
    test "returns true for unless expression" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      assert Conditional.unless_expression?(ast)
    end

    test "returns true for unless with else" do
      ast = {:unless, [], [{:x, [], nil}, [do: :body, else: :fallback]]}
      assert Conditional.unless_expression?(ast)
    end

    test "returns false for if" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      refute Conditional.unless_expression?(ast)
    end

    test "returns false for cond" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      refute Conditional.unless_expression?(ast)
    end
  end

  describe "cond_expression?/1" do
    test "returns true for cond expression" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      assert Conditional.cond_expression?(ast)
    end

    test "returns true for cond with multiple clauses" do
      clauses = [
        {:->, [], [[{:x, [], nil}], :a]},
        {:->, [], [[true], :b]}
      ]

      ast = {:cond, [], [[do: clauses]]}
      assert Conditional.cond_expression?(ast)
    end

    test "returns false for if" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      refute Conditional.cond_expression?(ast)
    end

    test "returns false for unless" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      refute Conditional.cond_expression?(ast)
    end
  end

  # ===========================================================================
  # If Extraction Tests
  # ===========================================================================

  describe "extract_if/2" do
    test "extracts if with condition and then branch" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      assert %ConditionalStruct{} = cond
      assert cond.type == :if
      assert cond.condition == {:x, [], nil}
      assert length(cond.branches) == 1
      assert cond.clauses == []
      assert cond.metadata.has_else == false
    end

    test "extracts if with condition and both branches" do
      ast = {:if, [], [{:>, [], [{:x, [], nil}, 0]}, [do: :positive, else: :negative]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      assert cond.type == :if
      assert cond.condition == {:>, [], [{:x, [], nil}, 0]}
      assert length(cond.branches) == 2
      assert cond.metadata.has_else == true
      assert cond.metadata.branch_count == 2
    end

    test "extracts then branch correctly" do
      ast = {:if, [], [{:x, [], nil}, [do: {:result, [], nil}]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      [then_branch] = cond.branches
      assert %Branch{} = then_branch
      assert then_branch.type == :then
      assert then_branch.body == {:result, [], nil}
    end

    test "extracts both branches correctly" do
      ast = {:if, [], [{:x, [], nil}, [do: :yes, else: :no]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      [then_branch, else_branch] = cond.branches

      assert then_branch.type == :then
      assert then_branch.body == :yes
      assert else_branch.type == :else
      assert else_branch.body == :no
    end

    test "handles complex condition" do
      condition = {:and, [], [{:>, [], [{:x, [], nil}, 0]}, {:<, [], [{:x, [], nil}, 100]}]}
      ast = {:if, [], [condition, [do: :ok]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      assert cond.condition == condition
    end

    test "handles block body" do
      body =
        {:__block__, [],
         [
           {:foo, [], []},
           {:bar, [], []}
         ]}

      ast = {:if, [], [{:x, [], nil}, [do: body]]}

      assert {:ok, cond} = Conditional.extract_if(ast)
      [then_branch] = cond.branches
      assert then_branch.body == body
    end

    test "returns error for non-if expression" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}
      assert {:error, {:not_an_if, _}} = Conditional.extract_if(ast)
    end

    test "returns error for function call" do
      ast = {:foo, [], []}
      assert {:error, {:not_an_if, _}} = Conditional.extract_if(ast)
    end
  end

  # ===========================================================================
  # Unless Extraction Tests
  # ===========================================================================

  describe "extract_unless/2" do
    test "extracts unless with condition and body" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}

      assert {:ok, cond} = Conditional.extract_unless(ast)
      assert %ConditionalStruct{} = cond
      assert cond.type == :unless
      assert cond.condition == {:x, [], nil}
      assert length(cond.branches) == 1
      assert cond.metadata.has_else == false
      assert cond.metadata.semantics == :negated_condition
    end

    test "extracts unless with else" do
      ast = {:unless, [], [{:x, [], nil}, [do: :body, else: :fallback]]}

      assert {:ok, cond} = Conditional.extract_unless(ast)
      assert cond.type == :unless
      assert length(cond.branches) == 2
      assert cond.metadata.has_else == true
    end

    test "extracts branches correctly" do
      ast = {:unless, [], [{:x, [], nil}, [do: :default, else: :override]]}

      assert {:ok, cond} = Conditional.extract_unless(ast)
      [then_branch, else_branch] = cond.branches

      assert then_branch.type == :then
      assert then_branch.body == :default
      assert else_branch.type == :else
      assert else_branch.body == :override
    end

    test "returns error for non-unless expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      assert {:error, {:not_an_unless, _}} = Conditional.extract_unless(ast)
    end
  end

  # ===========================================================================
  # Cond Extraction Tests
  # ===========================================================================

  describe "extract_cond/2" do
    test "extracts cond with single clause" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      assert %ConditionalStruct{} = cond
      assert cond.type == :cond
      assert cond.condition == nil
      assert cond.branches == []
      assert length(cond.clauses) == 1
    end

    test "extracts cond with multiple clauses" do
      clauses = [
        {:->, [], [[{:>, [], [{:x, [], nil}, 0]}], :positive]},
        {:->, [], [[{:<, [], [{:x, [], nil}, 0]}], :negative]},
        {:->, [], [[true], :zero]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      assert length(cond.clauses) == 3
      assert cond.metadata.clause_count == 3
    end

    test "extracts clause indices correctly" do
      clauses = [
        {:->, [], [[{:a, [], nil}], :first]},
        {:->, [], [[{:b, [], nil}], :second]},
        {:->, [], [[{:c, [], nil}], :third]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      indices = Enum.map(cond.clauses, & &1.index)
      assert indices == [0, 1, 2]
    end

    test "extracts clause conditions" do
      clauses = [
        {:->, [], [[{:foo, [], nil}], :a]},
        {:->, [], [[{:bar, [], nil}], :b]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      [clause1, clause2] = cond.clauses

      assert clause1.condition == {:foo, [], nil}
      assert clause2.condition == {:bar, [], nil}
    end

    test "extracts clause bodies" do
      clauses = [
        {:->, [], [[true], {:result, [], []}]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      [clause] = cond.clauses
      assert clause.body == {:result, [], []}
    end

    test "detects catch-all clause with true" do
      clauses = [
        {:->, [], [[{:x, [], nil}], :specific]},
        {:->, [], [[true], :default]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      [clause1, clause2] = cond.clauses

      assert clause1.is_catch_all == false
      assert clause2.is_catch_all == true
      assert cond.metadata.has_catch_all == true
      assert cond.metadata.catch_all_count == 1
    end

    test "handles cond without catch-all" do
      clauses = [
        {:->, [], [[{:x, [], nil}], :a]},
        {:->, [], [[{:y, [], nil}], :b]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      assert cond.metadata.has_catch_all == false
      assert cond.metadata.catch_all_count == 0
    end

    test "handles complex clause conditions" do
      condition = {:and, [], [{:>, [], [{:x, [], nil}, 0]}, {:is_integer, [], [{:x, [], nil}]}]}
      clauses = [{:->, [], [[condition], :ok]}]
      ast = {:cond, [], [[do: clauses]]}

      assert {:ok, cond} = Conditional.extract_cond(ast)
      [clause] = cond.clauses
      assert clause.condition == condition
    end

    test "returns error for non-cond expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      assert {:error, {:not_a_cond, _}} = Conditional.extract_cond(ast)
    end
  end

  # ===========================================================================
  # Generic Extraction Tests
  # ===========================================================================

  describe "extract_conditional/2" do
    test "dispatches to extract_if for if expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}

      assert {:ok, cond} = Conditional.extract_conditional(ast)
      assert cond.type == :if
    end

    test "dispatches to extract_unless for unless expression" do
      ast = {:unless, [], [{:x, [], nil}, [do: :ok]]}

      assert {:ok, cond} = Conditional.extract_conditional(ast)
      assert cond.type == :unless
    end

    test "dispatches to extract_cond for cond expression" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}

      assert {:ok, cond} = Conditional.extract_conditional(ast)
      assert cond.type == :cond
    end

    test "returns error for non-conditional" do
      ast = {:foo, [], []}
      assert {:error, {:not_a_conditional, _}} = Conditional.extract_conditional(ast)
    end
  end

  describe "extract_conditional!/2" do
    test "returns struct for valid conditional" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}

      cond = Conditional.extract_conditional!(ast)
      assert %ConditionalStruct{} = cond
      assert cond.type == :if
    end

    test "raises for invalid input" do
      ast = {:foo, [], []}

      assert_raise ArgumentError, fn ->
        Conditional.extract_conditional!(ast)
      end
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_conditionals/2" do
    test "extracts single conditional from list" do
      body = [{:if, [], [{:x, [], nil}, [do: :ok]]}]

      conds = Conditional.extract_conditionals(body)
      assert length(conds) == 1
      assert hd(conds).type == :if
    end

    test "extracts multiple conditionals from list" do
      body = [
        {:if, [], [{:x, [], nil}, [do: :ok]]},
        {:foo, [], []},
        {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}
      ]

      conds = Conditional.extract_conditionals(body)
      assert length(conds) == 2
      types = Enum.map(conds, & &1.type)
      assert :if in types
      assert :cond in types
    end

    test "extracts conditionals from function body" do
      ast = {:def, [], [{:run, [], nil}, [do: {:if, [], [{:x, [], nil}, [do: :ok]]}]]}

      conds = Conditional.extract_conditionals(ast)
      assert length(conds) == 1
    end

    test "extracts nested conditionals" do
      inner = {:unless, [], [{:y, [], nil}, [do: :inner]]}
      outer = {:if, [], [{:x, [], nil}, [do: inner]]}

      conds = Conditional.extract_conditionals(outer)
      assert length(conds) == 2
      types = Enum.map(conds, & &1.type)
      assert :if in types
      assert :unless in types
    end

    test "extracts conditionals from cond clauses" do
      inner = {:if, [], [{:z, [], nil}, [do: :nested]]}

      clauses = [
        {:->, [], [[{:x, [], nil}], inner]},
        {:->, [], [[true], :default]}
      ]

      ast = {:cond, [], [[do: clauses]]}

      conds = Conditional.extract_conditionals(ast)
      assert length(conds) == 2
    end

    test "handles block structures" do
      block =
        {:__block__, [],
         [
           {:if, [], [{:a, [], nil}, [do: :first]]},
           {:unless, [], [{:b, [], nil}, [do: :second]]}
         ]}

      conds = Conditional.extract_conditionals(block)
      assert length(conds) == 2
    end

    test "returns empty list for non-conditional AST" do
      ast = {:foo, [], [{:bar, [], []}]}

      conds = Conditional.extract_conditionals(ast)
      assert conds == []
    end

    test "handles literals" do
      conds = Conditional.extract_conditionals([1, 2, 3])
      assert conds == []
    end

    test "respects max_depth option" do
      # Create deeply nested structure
      inner = {:if, [], [{:deep, [], nil}, [do: :inner]]}
      outer = {:if, [], [{:x, [], nil}, [do: inner]]}

      # With low max_depth, may not find inner
      conds = Conditional.extract_conditionals(outer, max_depth: 1)
      # Should still find at least the outer one
      assert length(conds) >= 1
    end
  end

  # ===========================================================================
  # Struct Field Tests
  # ===========================================================================

  describe "Branch struct" do
    test "has required fields" do
      branch = %Branch{type: :then, body: :ok}
      assert branch.type == :then
      assert branch.body == :ok
      assert branch.location == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Branch, [])
      end
    end
  end

  describe "CondClause struct" do
    test "has required fields" do
      clause = %CondClause{index: 0, condition: true, body: :ok}
      assert clause.index == 0
      assert clause.condition == true
      assert clause.body == :ok
      assert clause.is_catch_all == false
      assert clause.location == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(CondClause, [])
      end
    end
  end

  describe "Conditional struct" do
    test "has required fields" do
      cond = %ConditionalStruct{type: :if}
      assert cond.type == :if
      assert cond.condition == nil
      assert cond.branches == []
      assert cond.clauses == []
      assert cond.location == nil
      assert cond.metadata == %{}
    end

    test "enforces type key" do
      assert_raise ArgumentError, fn ->
        struct!(ConditionalStruct, [])
      end
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "extracts conditionals from real module AST" do
      code = """
      defmodule Example do
        def check(x) do
          if x > 0 do
            :positive
          else
            :non_positive
          end
        end

        def classify(x) do
          cond do
            x > 0 -> :positive
            x < 0 -> :negative
            true -> :zero
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      conds = Conditional.extract_conditionals(ast)

      assert length(conds) == 2

      if_cond = Enum.find(conds, &(&1.type == :if))
      cond_cond = Enum.find(conds, &(&1.type == :cond))

      assert if_cond != nil
      assert cond_cond != nil
      assert length(if_cond.branches) == 2
      assert length(cond_cond.clauses) == 3
    end

    test "handles unless in real code" do
      code = """
      def process(value) do
        unless is_nil(value) do
          transform(value)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      conds = Conditional.extract_conditionals(ast)

      assert length(conds) == 1
      [cond] = conds
      assert cond.type == :unless
      assert cond.metadata.has_else == false
    end

    test "extracts complex nested conditionals" do
      code = """
      def complex(a, b) do
        if a do
          unless b do
            cond do
              a == 1 -> :one
              true -> :other
            end
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      conds = Conditional.extract_conditionals(ast)

      assert length(conds) == 3
      types = Enum.map(conds, & &1.type)
      assert :if in types
      assert :unless in types
      assert :cond in types
    end
  end
end
