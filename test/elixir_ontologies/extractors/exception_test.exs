defmodule ElixirOntologies.Extractors.ExceptionTest do
  @moduledoc """
  Tests for the Exception extractor module.

  These tests verify extraction of try expressions including rescue clauses,
  catch clauses, else clauses, and after blocks.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Exception
  alias ElixirOntologies.Extractors.Exception.{RescueClause, CatchClause, ElseClause}

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
end
