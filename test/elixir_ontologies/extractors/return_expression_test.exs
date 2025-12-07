defmodule ElixirOntologies.Extractors.ReturnExpressionTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.ReturnExpression

  doctest ReturnExpression

  # ===========================================================================
  # Literal Return Tests
  # ===========================================================================

  describe "extract/2 literal returns" do
    test "extracts atom literal" do
      assert {:ok, result} = ReturnExpression.extract(:ok)
      assert result.expression == :ok
      assert result.type == :literal
      assert result.metadata.is_nil == false
    end

    test "extracts integer literal" do
      assert {:ok, result} = ReturnExpression.extract(42)
      assert result.expression == 42
      assert result.type == :literal
    end

    test "extracts float literal" do
      assert {:ok, result} = ReturnExpression.extract(3.14)
      assert result.expression == 3.14
      assert result.type == :literal
    end

    test "extracts string literal" do
      assert {:ok, result} = ReturnExpression.extract("hello")
      assert result.expression == "hello"
      assert result.type == :literal
    end

    test "extracts list literal" do
      assert {:ok, result} = ReturnExpression.extract([1, 2, 3])
      assert result.expression == [1, 2, 3]
      assert result.type == :literal
    end

    test "extracts tuple literal (3+ elements)" do
      expr = {:{}, [], [1, 2, 3]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :literal
    end

    test "extracts 2-tuple literal" do
      expr = {:ok, {:data, [], nil}}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :literal
    end

    test "extracts map literal" do
      expr = {:%{}, [], [key: {:value, [], nil}]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :literal
    end

    test "extracts struct literal" do
      expr = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :literal
    end
  end

  # ===========================================================================
  # Variable Return Tests
  # ===========================================================================

  describe "extract/2 variable returns" do
    test "extracts simple variable" do
      expr = {:x, [], nil}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :variable
    end

    test "extracts variable with context" do
      expr = {:result, [line: 1], Elixir}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :variable
    end
  end

  # ===========================================================================
  # Function Call Return Tests
  # ===========================================================================

  describe "extract/2 function call returns" do
    test "extracts simple function call" do
      expr = {:foo, [], []}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :call
    end

    test "extracts function call with args" do
      expr = {:add, [], [1, 2]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :call
    end

    test "extracts remote function call" do
      expr = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [[1, 2, 3], {:fn, [], []}]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :call
    end

    test "extracts operator call" do
      expr = {:+, [], [1, 2]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :call
    end
  end

  # ===========================================================================
  # Control Flow Return Tests
  # ===========================================================================

  describe "extract/2 control flow returns" do
    test "extracts case expression" do
      expr = {:case, [], [{:x, [], nil}, [do: []]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.expression == expr
      assert result.type == :control_flow
      assert result.metadata.control_type == :case
      assert result.metadata.multi_return == true
    end

    test "extracts cond expression" do
      expr = {:cond, [], [[do: []]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :cond
    end

    test "extracts if expression" do
      expr = {:if, [], [{:condition, [], nil}, [do: :ok, else: :error]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :if
    end

    test "extracts unless expression" do
      expr = {:unless, [], [{:condition, [], nil}, [do: :ok]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :unless
    end

    test "extracts with expression" do
      expr =
        {:with, [], [{:<-, [], [{:ok, {:x, [], nil}}, {:call, [], []}]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :with
    end

    test "extracts try expression" do
      expr = {:try, [], [[do: :ok, rescue: []]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :try
    end

    test "extracts receive expression" do
      expr = {:receive, [], [[do: []]]}
      assert {:ok, result} = ReturnExpression.extract(expr)
      assert result.type == :control_flow
      assert result.metadata.control_type == :receive
    end
  end

  # ===========================================================================
  # Block Return Tests
  # ===========================================================================

  describe "extract/2 block returns" do
    test "extracts last expression from block" do
      block = {:__block__, [], [{:x, [], nil}, {:y, [], nil}, :final]}
      assert {:ok, result} = ReturnExpression.extract(block)
      assert result.expression == :final
      assert result.type == :literal
    end

    test "extracts last expression when it's a variable" do
      block = {:__block__, [], [:first, {:result, [], nil}]}
      assert {:ok, result} = ReturnExpression.extract(block)
      assert result.expression == {:result, [], nil}
      assert result.type == :variable
    end

    test "extracts last expression when it's a call" do
      block = {:__block__, [], [{:setup, [], []}, {:compute, [], [1, 2]}]}
      assert {:ok, result} = ReturnExpression.extract(block)
      assert result.expression == {:compute, [], [1, 2]}
      assert result.type == :call
    end

    test "extracts last expression when it's control flow" do
      case_expr = {:case, [], [{:x, [], nil}, [do: []]]}
      block = {:__block__, [], [{:setup, [], []}, case_expr]}
      assert {:ok, result} = ReturnExpression.extract(block)
      assert result.expression == case_expr
      assert result.type == :control_flow
    end

    test "handles empty block" do
      block = {:__block__, [], []}
      assert {:ok, result} = ReturnExpression.extract(block)
      assert result.expression == nil
      assert result.metadata.is_nil == true
    end
  end

  # ===========================================================================
  # Nil/Empty Body Tests
  # ===========================================================================

  describe "extract/2 nil body" do
    test "handles nil body (bodyless function)" do
      assert {:ok, result} = ReturnExpression.extract(nil)
      assert result.expression == nil
      assert result.type == :literal
      assert result.metadata.is_nil == true
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "multi_return?/1" do
    test "returns true for control flow" do
      {:ok, result} = ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      assert ReturnExpression.multi_return?(result)
    end

    test "returns false for literal" do
      {:ok, result} = ReturnExpression.extract(:ok)
      refute ReturnExpression.multi_return?(result)
    end

    test "returns false for call" do
      {:ok, result} = ReturnExpression.extract({:foo, [], []})
      refute ReturnExpression.multi_return?(result)
    end
  end

  describe "is_nil_return?/1" do
    test "returns true for nil body" do
      {:ok, result} = ReturnExpression.extract(nil)
      assert ReturnExpression.is_nil_return?(result)
    end

    test "returns false for non-nil" do
      {:ok, result} = ReturnExpression.extract(:ok)
      refute ReturnExpression.is_nil_return?(result)
    end
  end

  describe "control_type/1" do
    test "returns control type for control flow" do
      {:ok, result} = ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      assert ReturnExpression.control_type(result) == :case
    end

    test "returns nil for non-control flow" do
      {:ok, result} = ReturnExpression.extract(:ok)
      assert ReturnExpression.control_type(result) == nil
    end
  end

  describe "describe/1" do
    test "describes literal" do
      {:ok, result} = ReturnExpression.extract(:ok)
      assert ReturnExpression.describe(result) == "literal"
    end

    test "describes variable" do
      {:ok, result} = ReturnExpression.extract({:x, [], nil})
      assert ReturnExpression.describe(result) == "variable"
    end

    test "describes call" do
      {:ok, result} = ReturnExpression.extract({:foo, [], []})
      assert ReturnExpression.describe(result) == "call"
    end

    test "describes control flow with type" do
      {:ok, result} = ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      assert ReturnExpression.describe(result) == "control_flow:case"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns result on success" do
      result = ReturnExpression.extract!(:ok)
      assert result.expression == :ok
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts return from quoted single expression function" do
      {:def, _, [{:foo, _, _}, [do: body]]} =
        quote do
          def foo, do: :ok
        end

      assert {:ok, result} = ReturnExpression.extract(body)
      assert result.expression == :ok
      assert result.type == :literal
    end

    test "extracts return from quoted multi-expression function" do
      {:def, _, [{:bar, _, _}, [do: body]]} =
        quote do
          def bar do
            x = 1
            y = 2
            x + y
          end
        end

      assert {:ok, result} = ReturnExpression.extract(body)
      assert result.type == :call
    end

    test "extracts return from quoted function with case" do
      {:def, _, [{:process, _, _}, [do: body]]} =
        quote do
          def process(x) do
            case x do
              :ok -> :success
              :error -> :failure
            end
          end
        end

      assert {:ok, result} = ReturnExpression.extract(body)
      assert result.type == :control_flow
      assert result.metadata.control_type == :case
    end

    test "extracts return from quoted function with if" do
      {:def, _, [{:check, _, _}, [do: body]]} =
        quote do
          def check(x) do
            if x > 0 do
              :positive
            else
              :non_positive
            end
          end
        end

      assert {:ok, result} = ReturnExpression.extract(body)
      assert result.type == :control_flow
      assert result.metadata.control_type == :if
    end
  end
end
