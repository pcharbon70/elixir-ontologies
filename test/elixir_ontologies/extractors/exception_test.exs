defmodule ElixirOntologies.Extractors.ExceptionTest do
  @moduledoc """
  Tests for the Exception extractor module.

  These tests verify extraction of try expressions including rescue clauses,
  catch clauses, else clauses, and after blocks.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Exception

  alias ElixirOntologies.Extractors.Exception.{
    RescueClause,
    CatchClause,
    ElseClause,
    RaiseExpression,
    ThrowExpression,
    ExitExpression
  }

  doctest Exception

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "try_expression?/1" do
    test "returns true for try/rescue" do
      ast =
        quote do
          try do
            risky()
          rescue
            _ -> :error
          end
        end

      assert Exception.try_expression?(ast)
    end

    test "returns true for try/catch" do
      ast =
        quote do
          try do
            throw(:ball)
          catch
            :throw, v -> v
          end
        end

      assert Exception.try_expression?(ast)
    end

    test "returns true for try/after" do
      ast =
        quote do
          try do
            open()
          after
            close()
          end
        end

      assert Exception.try_expression?(ast)
    end

    test "returns false for if expression" do
      ast = quote do: if(true, do: 1)
      refute Exception.try_expression?(ast)
    end

    test "returns false for case expression" do
      ast = quote do: case(x, do: (y -> y))
      refute Exception.try_expression?(ast)
    end

    test "returns false for atoms" do
      refute Exception.try_expression?(:try)
    end
  end

  # ===========================================================================
  # Basic Try Extraction Tests
  # ===========================================================================

  describe "extract_try/2 basic" do
    test "extracts try body" do
      ast =
        quote do
          try do
            risky_operation()
          rescue
            _ -> :error
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert {:risky_operation, _, _} = result.body
    end

    test "extracts try/after" do
      ast =
        quote do
          try do
            open_file()
          after
            close_file()
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert result.has_after
      assert {:close_file, _, _} = result.after_body
      refute result.has_rescue
      refute result.has_catch
      refute result.has_else
    end

    test "returns error for non-try expression" do
      ast = quote do: if(true, do: 1)
      assert {:error, msg} = Exception.extract_try(ast)
      assert msg =~ "Not a try expression"
    end

    test "extract_try! raises on error" do
      assert_raise ArgumentError, fn ->
        Exception.extract_try!(:not_a_try)
      end
    end
  end

  # ===========================================================================
  # Rescue Clause Tests
  # ===========================================================================

  describe "extract_try/2 with rescue" do
    test "extracts bare rescue with underscore" do
      ast =
        quote do
          try do
            risky()
          rescue
            _ -> :error
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert result.has_rescue
      assert length(result.rescue_clauses) == 1

      [clause] = result.rescue_clauses
      assert %RescueClause{} = clause
      assert clause.is_catch_all
      assert clause.exceptions == []
    end

    test "extracts bare rescue with variable" do
      ast =
        quote do
          try do
            risky()
          rescue
            e -> handle(e)
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.rescue_clauses

      assert clause.is_catch_all
      assert {:e, _, _} = clause.variable
    end

    test "extracts rescue with exception type" do
      ast =
        quote do
          try do
            risky()
          rescue
            ArgumentError -> :arg_error
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.rescue_clauses

      refute clause.is_catch_all
      assert length(clause.exceptions) == 1
      assert {:__aliases__, _, [:ArgumentError]} = hd(clause.exceptions)
    end

    test "extracts rescue with variable binding to exception type" do
      ast =
        quote do
          try do
            risky()
          rescue
            e in ArgumentError -> e.message
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.rescue_clauses

      refute clause.is_catch_all
      assert {:e, _, _} = clause.variable
      assert length(clause.exceptions) == 1
    end

    test "extracts rescue with multiple exception types" do
      ast =
        quote do
          try do
            risky()
          rescue
            e in [ArgumentError, RuntimeError] -> e
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.rescue_clauses

      refute clause.is_catch_all
      assert length(clause.exceptions) == 2
    end

    test "extracts multiple rescue clauses" do
      ast =
        quote do
          try do
            risky()
          rescue
            ArgumentError -> :arg
            RuntimeError -> :runtime
            _ -> :other
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert length(result.rescue_clauses) == 3
      assert result.metadata.rescue_count == 3
    end
  end

  # ===========================================================================
  # Standalone Rescue Clause Extraction Tests
  # ===========================================================================

  describe "extract_rescue_clauses/2" do
    test "extracts clauses from list" do
      clauses = [{:->, [], [[{:e, [], nil}], :error]}]
      result = Exception.extract_rescue_clauses(clauses)

      assert length(result) == 1
      [clause] = result
      assert %RescueClause{} = clause
      assert clause.is_catch_all
    end

    test "returns empty list for nil" do
      assert Exception.extract_rescue_clauses(nil) == []
    end

    test "returns empty list for empty list" do
      assert Exception.extract_rescue_clauses([]) == []
    end

    test "extracts exception module name from alias" do
      # Pattern: ArgumentError (without variable)
      clauses = [{:->, [], [[{:__aliases__, [alias: false], [:ArgumentError]}], :arg_error]}]
      [clause] = Exception.extract_rescue_clauses(clauses)

      refute clause.is_catch_all
      assert length(clause.exceptions) == 1
      {:__aliases__, _, [:ArgumentError]} = hd(clause.exceptions)
    end

    test "extracts multiple exception types from list" do
      # Pattern: e in [ArgumentError, RuntimeError]
      pattern =
        {:in, [],
         [
           {:e, [], nil},
           [
             {:__aliases__, [alias: false], [:ArgumentError]},
             {:__aliases__, [alias: false], [:RuntimeError]}
           ]
         ]}

      clauses = [{:->, [], [[pattern], {:e, [], nil}]}]
      [clause] = Exception.extract_rescue_clauses(clauses)

      refute clause.is_catch_all
      assert {:e, [], nil} = clause.variable
      assert length(clause.exceptions) == 2
    end

    test "handles nested module exception types" do
      # Pattern: e in MyApp.CustomError
      pattern =
        {:in, [],
         [
           {:e, [], nil},
           {:__aliases__, [alias: false], [:MyApp, :CustomError]}
         ]}

      clauses = [{:->, [], [[pattern], :custom_error]}]
      [clause] = Exception.extract_rescue_clauses(clauses)

      refute clause.is_catch_all
      assert length(clause.exceptions) == 1
      {:__aliases__, _, [:MyApp, :CustomError]} = hd(clause.exceptions)
    end
  end

  # ===========================================================================
  # Catch Clause Tests
  # ===========================================================================

  describe "extract_try/2 with catch" do
    test "extracts catch with :throw kind" do
      ast =
        quote do
          try do
            throw(:ball)
          catch
            :throw, value -> {:caught, value}
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert result.has_catch
      assert length(result.catch_clauses) == 1

      [clause] = result.catch_clauses
      assert %CatchClause{} = clause
      assert clause.kind == :throw
      assert {:value, _, _} = clause.pattern
    end

    test "extracts catch with :exit kind" do
      ast =
        quote do
          try do
            exit(:reason)
          catch
            :exit, reason -> reason
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.catch_clauses
      assert clause.kind == :exit
    end

    test "extracts catch with :error kind" do
      ast =
        quote do
          try do
            :erlang.error(:bad)
          catch
            :error, reason -> reason
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.catch_clauses
      assert clause.kind == :error
    end

    test "extracts catch without explicit kind" do
      ast =
        quote do
          try do
            throw(:ball)
          catch
            value -> value
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.catch_clauses

      assert clause.kind == nil
      assert {:value, _, _} = clause.pattern
    end

    test "extracts multiple catch clauses" do
      ast =
        quote do
          try do
            risky()
          catch
            :throw, v -> {:throw, v}
            :exit, r -> {:exit, r}
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert length(result.catch_clauses) == 2
      assert result.metadata.catch_count == 2
    end
  end

  # ===========================================================================
  # Standalone Catch Clause Extraction Tests
  # ===========================================================================

  describe "extract_catch_clauses/2" do
    test "extracts clauses from list with :throw kind" do
      clauses = [{:->, [], [[:throw, {:value, [], nil}], {:value, [], nil}]}]
      result = Exception.extract_catch_clauses(clauses)

      assert length(result) == 1
      [clause] = result
      assert %CatchClause{} = clause
      assert clause.kind == :throw
      assert {:value, [], nil} = clause.pattern
    end

    test "returns empty list for nil" do
      assert Exception.extract_catch_clauses(nil) == []
    end

    test "returns empty list for empty list" do
      assert Exception.extract_catch_clauses([]) == []
    end

    test "extracts :exit kind" do
      clauses = [{:->, [], [[:exit, {:reason, [], nil}], {:reason, [], nil}]}]
      [clause] = Exception.extract_catch_clauses(clauses)

      assert clause.kind == :exit
      assert {:reason, [], nil} = clause.pattern
    end

    test "extracts :error kind" do
      clauses = [{:->, [], [[:error, {:reason, [], nil}], :error_handled]}]
      [clause] = Exception.extract_catch_clauses(clauses)

      assert clause.kind == :error
      assert {:reason, [], nil} = clause.pattern
    end

    test "handles catch without explicit kind" do
      clauses = [{:->, [], [[{:value, [], nil}], {:value, [], nil}]}]
      [clause] = Exception.extract_catch_clauses(clauses)

      assert clause.kind == nil
      assert {:value, [], nil} = clause.pattern
    end

    test "extracts complex pattern" do
      # Pattern: {:ball, color}
      pattern = {:ball, {:color, [], nil}}
      clauses = [{:->, [], [[:throw, pattern], :caught]}]
      [clause] = Exception.extract_catch_clauses(clauses)

      assert clause.kind == :throw
      assert {:ball, {:color, [], nil}} = clause.pattern
    end

    test "extracts multiple catch clauses" do
      clauses = [
        {:->, [], [[:throw, {:t, [], nil}], :throw_handled]},
        {:->, [], [[:exit, {:e, [], nil}], :exit_handled]},
        {:->, [], [[:error, {:r, [], nil}], :error_handled]}
      ]

      result = Exception.extract_catch_clauses(clauses)
      assert length(result) == 3

      [throw_clause, exit_clause, error_clause] = result
      assert throw_clause.kind == :throw
      assert exit_clause.kind == :exit
      assert error_clause.kind == :error
    end
  end

  # ===========================================================================
  # Else Clause Tests
  # ===========================================================================

  describe "extract_try/2 with else" do
    test "extracts else clause" do
      ast =
        quote do
          try do
            {:ok, value}
          rescue
            _ -> :error
          else
            {:ok, v} -> v
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert result.has_else
      assert length(result.else_clauses) == 1

      [clause] = result.else_clauses
      assert %ElseClause{} = clause
      assert {:ok, {:v, _, _}} = clause.pattern
    end

    test "extracts multiple else clauses" do
      ast =
        quote do
          try do
            fetch()
          rescue
            _ -> :error
          else
            {:ok, v} -> v
            {:error, _} -> nil
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      assert length(result.else_clauses) == 2
      assert result.metadata.else_count == 2
    end

    test "extracts else clause with guard" do
      ast =
        quote do
          try do
            get_value()
          rescue
            _ -> :error
          else
            x when is_integer(x) -> x * 2
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)
      [clause] = result.else_clauses

      assert {:x, _, _} = clause.pattern
      assert clause.guard != nil
    end
  end

  # ===========================================================================
  # Full Try Expression Tests
  # ===========================================================================

  describe "extract_try/2 with all clauses" do
    test "extracts try with all clause types" do
      ast =
        quote do
          try do
            body()
          rescue
            e -> rescue_handler(e)
          catch
            :exit, reason -> catch_exit(reason)
          else
            result -> handle_result(result)
          after
            cleanup()
          end
        end

      assert {:ok, result} = Exception.extract_try(ast)

      assert result.has_rescue
      assert result.has_catch
      assert result.has_else
      assert result.has_after

      assert length(result.rescue_clauses) == 1
      assert length(result.catch_clauses) == 1
      assert length(result.else_clauses) == 1
      assert result.after_body != nil

      assert :rescue in result.metadata.clause_types
      assert :catch in result.metadata.clause_types
      assert :else in result.metadata.clause_types
      assert :after in result.metadata.clause_types
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_try_expressions/2" do
    test "extracts multiple try expressions" do
      ast =
        quote do
          try do
            :a
          rescue
            _ -> :b
          end

          try do
            :c
          after
            :d
          end
        end

      tries = Exception.extract_try_expressions(ast)
      assert length(tries) == 2
    end

    test "extracts nested try expressions" do
      ast =
        quote do
          try do
            try do
              :inner
            rescue
              _ -> :inner_error
            end
          rescue
            _ -> :outer_error
          end
        end

      tries = Exception.extract_try_expressions(ast)
      assert length(tries) == 2
    end

    test "extracts try inside function" do
      ast =
        quote do
          def my_func do
            try do
              risky()
            rescue
              _ -> :error
            end
          end
        end

      tries = Exception.extract_try_expressions(ast)
      assert length(tries) == 1
    end

    test "returns empty list when no try expressions" do
      ast =
        quote do
          x = 1 + 2
          y = if true, do: 3
        end

      tries = Exception.extract_try_expressions(ast)
      assert tries == []
    end
  end

  # ===========================================================================
  # Convenience Function Tests
  # ===========================================================================

  describe "convenience functions" do
    test "has_rescue?/1" do
      try_expr = %Exception{body: :ok, has_rescue: true}
      assert Exception.has_rescue?(try_expr)

      try_expr2 = %Exception{body: :ok, has_rescue: false}
      refute Exception.has_rescue?(try_expr2)

      refute Exception.has_rescue?(%{})
    end

    test "has_catch?/1" do
      try_expr = %Exception{body: :ok, has_catch: true}
      assert Exception.has_catch?(try_expr)

      refute Exception.has_catch?(%{})
    end

    test "has_else?/1" do
      try_expr = %Exception{body: :ok, has_else: true}
      assert Exception.has_else?(try_expr)

      refute Exception.has_else?(%{})
    end

    test "has_after?/1" do
      try_expr = %Exception{body: :ok, has_after: true, after_body: :cleanup}
      assert Exception.has_after?(try_expr)

      refute Exception.has_after?(%{})
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "RescueClause struct" do
    test "has required fields" do
      clause = %RescueClause{body: :error}
      assert clause.body == :error
      assert clause.exceptions == []
      assert clause.is_catch_all == false
    end
  end

  describe "CatchClause struct" do
    test "has required fields" do
      clause = %CatchClause{pattern: :value, body: :caught}
      assert clause.pattern == :value
      assert clause.body == :caught
      assert clause.kind == nil
    end
  end

  describe "ElseClause struct" do
    test "has required fields" do
      clause = %ElseClause{pattern: {:ok, :v}, body: :v}
      assert clause.pattern == {:ok, :v}
      assert clause.body == :v
      assert clause.guard == nil
    end
  end

  # ===========================================================================
  # Raise Expression Tests
  # ===========================================================================

  describe "raise_expression?/1" do
    test "returns true for raise with message" do
      ast = {:raise, [], ["error message"]}
      assert Exception.raise_expression?(ast)
    end

    test "returns true for raise with exception module" do
      ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}]}
      assert Exception.raise_expression?(ast)
    end

    test "returns true for reraise" do
      ast = {:reraise, [], [{:e, [], nil}, {:__STACKTRACE__, [], nil}]}
      assert Exception.raise_expression?(ast)
    end

    test "returns false for throw" do
      ast = {:throw, [], [:value]}
      refute Exception.raise_expression?(ast)
    end

    test "returns false for non-raise expressions" do
      refute Exception.raise_expression?({:if, [], [true, [do: 1]]})
      refute Exception.raise_expression?(:atom)
    end
  end

  describe "extract_raise/2" do
    test "extracts raise with message string" do
      ast = {:raise, [], ["error message"]}
      {:ok, result} = Exception.extract_raise(ast)

      assert %RaiseExpression{} = result
      assert result.message == "error message"
      assert result.exception == nil
      assert result.is_reraise == false
    end

    test "extracts raise with exception module only" do
      ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.exception == {:__aliases__, [], [:RuntimeError]}
      assert result.message == nil
      assert result.is_reraise == false
    end

    test "extracts raise with exception and message string" do
      ast = {:raise, [], [{:__aliases__, [], [:ArgumentError]}, "bad argument"]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.exception == {:__aliases__, [], [:ArgumentError]}
      assert result.message == "bad argument"
      assert result.is_reraise == false
    end

    test "extracts raise with exception and keyword options" do
      ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}, [message: "failed", extra: :data]]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.exception == {:__aliases__, [], [:RuntimeError]}
      assert result.message == "failed"
      assert result.attributes == [message: "failed", extra: :data]
      assert result.is_reraise == false
    end

    test "extracts raise with exception struct" do
      struct_ast =
        {:%, [],
         [
           {:__aliases__, [], [:RuntimeError]},
           {:%{}, [], [message: "oops"]}
         ]}

      ast = {:raise, [], [struct_ast]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.exception == struct_ast
      assert result.is_reraise == false
    end

    test "extracts raise with variable as message" do
      ast = {:raise, [], [{:msg, [], nil}]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.message == {:msg, [], nil}
      assert result.exception == nil
    end

    test "extracts raise with exception and variable message" do
      ast = {:raise, [], [{:__aliases__, [], [:ArgumentError]}, {:msg, [], nil}]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.exception == {:__aliases__, [], [:ArgumentError]}
      assert result.message == {:msg, [], nil}
    end

    test "extracts reraise with exception and stacktrace" do
      ast = {:reraise, [], [{:e, [], nil}, {:__STACKTRACE__, [], nil}]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.is_reraise == true
      assert result.exception == {:e, [], nil}
      assert result.stacktrace == {:__STACKTRACE__, [], nil}
    end

    test "extracts reraise with message string and stacktrace" do
      ast = {:reraise, [], ["error", {:stacktrace, [], nil}]}
      {:ok, result} = Exception.extract_raise(ast)

      assert result.is_reraise == true
      assert result.message == "error"
      assert result.stacktrace == {:stacktrace, [], nil}
    end

    test "returns error for non-raise expression" do
      ast = {:throw, [], [:value]}
      assert {:error, _} = Exception.extract_raise(ast)
    end
  end

  describe "extract_raise!/2" do
    test "extracts raise expression" do
      ast = {:raise, [], ["error"]}
      result = Exception.extract_raise!(ast)
      assert result.message == "error"
    end

    test "raises on non-raise expression" do
      ast = {:throw, [], [:value]}

      assert_raise ArgumentError, fn ->
        Exception.extract_raise!(ast)
      end
    end
  end

  describe "extract_raises/2" do
    test "extracts multiple raise expressions" do
      ast =
        quote do
          raise "error1"
          raise "error2"
        end

      raises = Exception.extract_raises(ast)
      assert length(raises) == 2
      assert Enum.all?(raises, &(&1.is_reraise == false))
    end

    test "extracts mixed raise and reraise" do
      ast =
        {:__block__, [],
         [
           {:raise, [], ["error"]},
           {:reraise, [], [{:e, [], nil}, {:stack, [], nil}]}
         ]}

      raises = Exception.extract_raises(ast)
      assert length(raises) == 2

      [raise_expr, reraise_expr] = raises
      refute raise_expr.is_reraise
      assert reraise_expr.is_reraise
    end

    test "returns empty list when no raises" do
      ast =
        quote do
          x = 1
          y = 2
        end

      raises = Exception.extract_raises(ast)
      assert raises == []
    end

    test "extracts nested raise expressions" do
      ast =
        quote do
          if true do
            raise "inner"
          else
            raise "outer"
          end
        end

      raises = Exception.extract_raises(ast)
      assert length(raises) == 2
    end
  end

  describe "RaiseExpression struct" do
    test "has default values" do
      expr = %RaiseExpression{}
      assert expr.exception == nil
      assert expr.message == nil
      assert expr.attributes == nil
      assert expr.is_reraise == false
      assert expr.stacktrace == nil
      assert expr.location == nil
    end
  end

  # ===========================================================================
  # Throw Expression Tests
  # ===========================================================================

  describe "throw_expression?/1" do
    test "returns true for throw with atom" do
      ast = {:throw, [], [:value]}
      assert Exception.throw_expression?(ast)
    end

    test "returns true for throw with tuple" do
      ast = {:throw, [], [{:error, :reason}]}
      assert Exception.throw_expression?(ast)
    end

    test "returns false for raise" do
      ast = {:raise, [], ["error"]}
      refute Exception.throw_expression?(ast)
    end

    test "returns false for non-throw expressions" do
      refute Exception.throw_expression?({:exit, [], [:normal]})
      refute Exception.throw_expression?(:atom)
    end
  end

  describe "extract_throw/2" do
    test "extracts throw with atom value" do
      ast = {:throw, [], [:value]}
      {:ok, result} = Exception.extract_throw(ast)

      assert %ThrowExpression{} = result
      assert result.value == :value
    end

    test "extracts throw with tuple value" do
      ast = {:throw, [], [{:error, :reason}]}
      {:ok, result} = Exception.extract_throw(ast)

      assert result.value == {:error, :reason}
    end

    test "extracts throw with variable" do
      ast = {:throw, [], [{:value, [], nil}]}
      {:ok, result} = Exception.extract_throw(ast)

      assert result.value == {:value, [], nil}
    end

    test "returns error for non-throw expression" do
      ast = {:raise, [], ["error"]}
      assert {:error, _} = Exception.extract_throw(ast)
    end
  end

  describe "extract_throw!/2" do
    test "extracts throw expression" do
      ast = {:throw, [], [:done]}
      result = Exception.extract_throw!(ast)
      assert result.value == :done
    end

    test "raises on non-throw expression" do
      ast = {:raise, [], ["error"]}

      assert_raise ArgumentError, fn ->
        Exception.extract_throw!(ast)
      end
    end
  end

  describe "extract_throws/2" do
    test "extracts multiple throw expressions" do
      ast =
        quote do
          throw(:a)
          throw(:b)
        end

      throws = Exception.extract_throws(ast)
      assert length(throws) == 2
    end

    test "returns empty list when no throws" do
      ast =
        quote do
          x = 1
          y = 2
        end

      throws = Exception.extract_throws(ast)
      assert throws == []
    end

    test "extracts nested throw expressions" do
      ast =
        quote do
          if true do
            throw(:inner)
          else
            throw(:outer)
          end
        end

      throws = Exception.extract_throws(ast)
      assert length(throws) == 2
    end
  end

  describe "ThrowExpression struct" do
    test "has required value field" do
      expr = %ThrowExpression{value: :test}
      assert expr.value == :test
      assert expr.location == nil
    end
  end

  # ===========================================================================
  # Exit Expression Tests
  # ===========================================================================

  describe "exit_expression?/1" do
    test "returns true for exit with atom" do
      ast = {:exit, [], [:normal]}
      assert Exception.exit_expression?(ast)
    end

    test "returns true for exit with tuple" do
      ast = {:exit, [], [{:shutdown, :reason}]}
      assert Exception.exit_expression?(ast)
    end

    test "returns false for throw" do
      ast = {:throw, [], [:value]}
      refute Exception.exit_expression?(ast)
    end

    test "returns false for non-exit expressions" do
      refute Exception.exit_expression?({:raise, [], ["error"]})
      refute Exception.exit_expression?(:atom)
    end
  end

  describe "extract_exit/2" do
    test "extracts exit with atom reason" do
      ast = {:exit, [], [:normal]}
      {:ok, result} = Exception.extract_exit(ast)

      assert %ExitExpression{} = result
      assert result.reason == :normal
    end

    test "extracts exit with tuple reason" do
      ast = {:exit, [], [{:shutdown, :reason}]}
      {:ok, result} = Exception.extract_exit(ast)

      assert result.reason == {:shutdown, :reason}
    end

    test "extracts exit with variable" do
      ast = {:exit, [], [{:reason, [], nil}]}
      {:ok, result} = Exception.extract_exit(ast)

      assert result.reason == {:reason, [], nil}
    end

    test "returns error for non-exit expression" do
      ast = {:throw, [], [:value]}
      assert {:error, _} = Exception.extract_exit(ast)
    end
  end

  describe "extract_exit!/2" do
    test "extracts exit expression" do
      ast = {:exit, [], [:shutdown]}
      result = Exception.extract_exit!(ast)
      assert result.reason == :shutdown
    end

    test "raises on non-exit expression" do
      ast = {:throw, [], [:value]}

      assert_raise ArgumentError, fn ->
        Exception.extract_exit!(ast)
      end
    end
  end

  describe "extract_exits/2" do
    test "extracts multiple exit expressions" do
      ast =
        quote do
          exit(:normal)
          exit(:shutdown)
        end

      exits = Exception.extract_exits(ast)
      assert length(exits) == 2
    end

    test "returns empty list when no exits" do
      ast =
        quote do
          x = 1
          y = 2
        end

      exits = Exception.extract_exits(ast)
      assert exits == []
    end

    test "extracts nested exit expressions" do
      ast =
        quote do
          if true do
            exit(:inner)
          else
            exit(:outer)
          end
        end

      exits = Exception.extract_exits(ast)
      assert length(exits) == 2
    end
  end

  describe "ExitExpression struct" do
    test "has required reason field" do
      expr = %ExitExpression{reason: :normal}
      assert expr.reason == :normal
      assert expr.location == nil
    end
  end
end
