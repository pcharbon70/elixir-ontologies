defmodule ElixirOntologies.Extractors.ControlFlowTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.ControlFlow

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "control_flow?/1" do
    test "returns true for if expression" do
      ast = {:if, [], [true, [do: :ok]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for unless expression" do
      ast = {:unless, [], [false, [do: :ok]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for cond expression" do
      ast = {:cond, [], [[do: []]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for with expression" do
      ast = {:with, [], [[do: :ok]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for try expression" do
      ast = {:try, [], [[do: :ok]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for receive expression" do
      ast = {:receive, [], [[do: []]]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for raise expression" do
      ast = {:raise, [], ["error"]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns true for throw expression" do
      ast = {:throw, [], [:value]}
      assert ControlFlow.control_flow?(ast)
    end

    test "returns false for non-control-flow nodes" do
      refute ControlFlow.control_flow?({:def, [], [{:foo, [], nil}]})
      refute ControlFlow.control_flow?({:defmodule, [], [{:__aliases__, [], [:Foo]}, []]})
      refute ControlFlow.control_flow?(:atom)
      refute ControlFlow.control_flow?(42)
    end
  end

  describe "control_flow_type/1" do
    test "returns :if for if expression" do
      assert ControlFlow.control_flow_type({:if, [], [true, [do: :ok]]}) == :if
    end

    test "returns :unless for unless expression" do
      assert ControlFlow.control_flow_type({:unless, [], [false, [do: :ok]]}) == :unless
    end

    test "returns :case for case expression" do
      assert ControlFlow.control_flow_type({:case, [], [{:x, [], nil}, [do: []]]}) == :case
    end

    test "returns :cond for cond expression" do
      assert ControlFlow.control_flow_type({:cond, [], [[do: []]]}) == :cond
    end

    test "returns :with for with expression" do
      assert ControlFlow.control_flow_type({:with, [], [[do: :ok]]}) == :with
    end

    test "returns :try for try expression" do
      assert ControlFlow.control_flow_type({:try, [], [[do: :ok]]}) == :try
    end

    test "returns :receive for receive expression" do
      assert ControlFlow.control_flow_type({:receive, [], [[do: []]]}) == :receive
    end

    test "returns :raise for raise expression" do
      assert ControlFlow.control_flow_type({:raise, [], ["error"]}) == :raise
    end

    test "returns :throw for throw expression" do
      assert ControlFlow.control_flow_type({:throw, [], [:value]}) == :throw
    end

    test "returns nil for non-control-flow" do
      assert ControlFlow.control_flow_type({:def, [], nil}) == nil
    end
  end

  # ===========================================================================
  # If Expression Tests
  # ===========================================================================

  describe "extract_if/1" do
    test "extracts if with else branch" do
      ast = {:if, [], [{:>, [], [{:x, [], nil}, 0]}, [do: :positive, else: :negative]]}
      result = ControlFlow.extract_if(ast)

      assert result.type == :if
      assert result.condition == {:>, [], [{:x, [], nil}, 0]}
      assert result.branches.then == :positive
      assert result.branches.else == :negative
      assert result.metadata.has_else == true
    end

    test "extracts if without else branch" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      result = ControlFlow.extract_if(ast)

      assert result.type == :if
      assert result.branches.then == :ok
      assert result.branches.else == nil
      assert result.metadata.has_else == false
    end

    test "extracts if with complex condition" do
      condition = {:and, [], [{:>, [], [{:x, [], nil}, 0]}, {:<, [], [{:x, [], nil}, 10]}]}
      ast = {:if, [], [condition, [do: :in_range]]}
      result = ControlFlow.extract_if(ast)

      assert result.condition == condition
    end

    test "extracts if with block body" do
      body = {:__block__, [], [:first, :second, :third]}
      ast = {:if, [], [true, [do: body]]}
      result = ControlFlow.extract_if(ast)

      assert result.branches.then == body
    end
  end

  # ===========================================================================
  # Unless Expression Tests
  # ===========================================================================

  describe "extract_unless/1" do
    test "extracts unless with else branch" do
      ast = {:unless, [], [{:==, [], [{:x, [], nil}, 0]}, [do: :non_zero, else: :zero]]}
      result = ControlFlow.extract_unless(ast)

      assert result.type == :unless
      assert result.branches.then == :non_zero
      assert result.branches.else == :zero
      assert result.metadata.has_else == true
    end

    test "extracts unless without else branch" do
      ast = {:unless, [], [false, [do: :ok]]}
      result = ControlFlow.extract_unless(ast)

      assert result.type == :unless
      assert result.branches.then == :ok
      assert result.branches.else == nil
      assert result.metadata.has_else == false
    end
  end

  # ===========================================================================
  # Case Expression Tests
  # ===========================================================================

  describe "extract_case/1" do
    test "extracts case with single clause" do
      clause = {:->, [], [[:ok], :success]}
      ast = {:case, [], [{:value, [], nil}, [do: [clause]]]}
      result = ControlFlow.extract_case(ast)

      assert result.type == :case
      assert result.condition == {:value, [], nil}
      assert length(result.clauses) == 1
      assert hd(result.clauses).patterns == [:ok]
      assert hd(result.clauses).body == :success
    end

    test "extracts case with multiple clauses" do
      clauses = [
        {:->, [], [[:ok], :success]},
        {:->, [], [[:error], :failure]},
        {:->, [], [[{:_, [], nil}], :unknown]}
      ]
      ast = {:case, [], [{:value, [], nil}, [do: clauses]]}
      result = ControlFlow.extract_case(ast)

      assert result.type == :case
      assert length(result.clauses) == 3
      assert result.metadata.clause_count == 3
    end

    test "extracts case with tuple pattern" do
      clause = {:->, [], [[{:ok, {:result, [], nil}}], {:result, [], nil}]}
      ast = {:case, [], [{:value, [], nil}, [do: [clause]]]}
      result = ControlFlow.extract_case(ast)

      assert length(result.clauses) == 1
      assert hd(result.clauses).patterns == [{:ok, {:result, [], nil}}]
    end

    test "extracts case with guard" do
      # x when is_integer(x) -> x
      pattern = {:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}
      clause = {:->, [], [[pattern], {:x, [], nil}]}
      ast = {:case, [], [{:value, [], nil}, [do: [clause]]]}
      result = ControlFlow.extract_case(ast)

      assert length(result.clauses) == 1
      clause = hd(result.clauses)
      assert clause.patterns == [{:x, [], nil}]
      assert clause.guard == {:is_integer, [], [{:x, [], nil}]}
    end
  end

  # ===========================================================================
  # Cond Expression Tests
  # ===========================================================================

  describe "extract_cond/1" do
    test "extracts cond with single condition" do
      clause = {:->, [], [[true], :ok]}
      ast = {:cond, [], [[do: [clause]]]}
      result = ControlFlow.extract_cond(ast)

      assert result.type == :cond
      assert length(result.clauses) == 1
      assert hd(result.clauses).patterns == [true]
      assert hd(result.clauses).body == :ok
    end

    test "extracts cond with multiple conditions" do
      clauses = [
        {:->, [], [[{:>, [], [{:x, [], nil}, 0]}], :positive]},
        {:->, [], [[{:<, [], [{:x, [], nil}, 0]}], :negative]},
        {:->, [], [[true], :zero]}
      ]
      ast = {:cond, [], [[do: clauses]]}
      result = ControlFlow.extract_cond(ast)

      assert result.type == :cond
      assert length(result.clauses) == 3
      assert result.metadata.clause_count == 3
    end

    test "extracts cond clause conditions correctly" do
      clauses = [
        {:->, [], [[{:>, [], [{:x, [], nil}, 0]}], :positive]},
        {:->, [], [[true], :default]}
      ]
      ast = {:cond, [], [[do: clauses]]}
      result = ControlFlow.extract_cond(ast)

      first_clause = hd(result.clauses)
      assert first_clause.patterns == [{:>, [], [{:x, [], nil}, 0]}]
      assert first_clause.body == :positive

      last_clause = List.last(result.clauses)
      assert last_clause.patterns == [true]
      assert last_clause.body == :default
    end
  end

  # ===========================================================================
  # With Expression Tests
  # ===========================================================================

  describe "extract_with/1" do
    test "extracts with single match clause" do
      match = {:<-, [], [{:ok, {:x, [], nil}}, {:get, [], []}]}
      ast = {:with, [], [match, [do: {:ok, {:x, [], nil}}]]}
      result = ControlFlow.extract_with(ast)

      assert result.type == :with
      assert length(result.clauses) == 1
      assert result.metadata.has_else == false
    end

    test "extracts with multiple match clauses" do
      match1 = {:<-, [], [{:ok, {:a, [], nil}}, {:get_a, [], []}]}
      match2 = {:<-, [], [{:ok, {:b, [], nil}}, {:get_b, [], [{:a, [], nil}]}]}
      ast = {:with, [], [match1, match2, [do: {:ok, {:+, [], [{:a, [], nil}, {:b, [], nil}]}}]]}
      result = ControlFlow.extract_with(ast)

      assert result.type == :with
      assert length(result.clauses) == 2
      assert result.metadata.match_clause_count == 2
    end

    test "extracts with else clause" do
      match = {:<-, [], [{:ok, {:x, [], nil}}, {:get, [], []}]}
      else_clause = {:->, [], [[{:error, {:reason, [], nil}}], {:error, {:reason, [], nil}}]}
      ast = {:with, [], [match, [do: {:ok, {:x, [], nil}}, else: [else_clause]]]}
      result = ControlFlow.extract_with(ast)

      assert result.type == :with
      assert result.metadata.has_else == true
      assert result.metadata.else_clause_count == 1
    end

    test "extracts with match clause patterns" do
      match = {:<-, [], [{:ok, {:x, [], nil}}, {:get, [], []}]}
      ast = {:with, [], [match, [do: :ok]]}
      result = ControlFlow.extract_with(ast)

      clause = hd(result.clauses)
      assert clause.patterns == [{:ok, {:x, [], nil}}]
      assert clause.body == {:get, [], []}
    end
  end

  # ===========================================================================
  # Try Expression Tests
  # ===========================================================================

  describe "extract_try/1" do
    test "extracts try with rescue only" do
      rescue_clause = {:->, [], [[{:e, [], nil}], :error]}
      ast = {:try, [], [[do: {:risky, [], []}, rescue: [rescue_clause]]]}
      result = ControlFlow.extract_try(ast)

      assert result.type == :try
      assert result.branches.do == {:risky, [], []}
      assert result.metadata.has_rescue == true
      assert result.metadata.has_catch == false
      assert result.metadata.has_after == false
      assert result.metadata.rescue_clause_count == 1
    end

    test "extracts try with catch only" do
      catch_clause = {:->, [], [[:exit, {:reason, [], nil}], {:exit, {:reason, [], nil}}]}
      ast = {:try, [], [[do: {:risky, [], []}, catch: [catch_clause]]]}
      result = ControlFlow.extract_try(ast)

      assert result.type == :try
      assert result.metadata.has_rescue == false
      assert result.metadata.has_catch == true
      assert result.metadata.catch_clause_count == 1
    end

    test "extracts try with after only" do
      ast = {:try, [], [[do: {:risky, [], []}, after: {:cleanup, [], []}]]}
      result = ControlFlow.extract_try(ast)

      assert result.type == :try
      assert result.metadata.has_rescue == false
      assert result.metadata.has_catch == false
      assert result.metadata.has_after == true
      assert result.branches.after == {:cleanup, [], []}
    end

    test "extracts try with all clauses" do
      rescue_clause = {:->, [], [[{:e, [], nil}], :error]}
      catch_clause = {:->, [], [[:exit, {:reason, [], nil}], :caught]}
      ast = {:try, [], [[
        do: {:risky, [], []},
        rescue: [rescue_clause],
        catch: [catch_clause],
        after: {:cleanup, [], []}
      ]]}
      result = ControlFlow.extract_try(ast)

      assert result.type == :try
      assert result.metadata.has_rescue == true
      assert result.metadata.has_catch == true
      assert result.metadata.has_after == true
    end

    test "extracts try with multiple rescue clauses" do
      rescue1 = {:->, [], [[{:in, [], [{:e, [], nil}, {:__aliases__, [], [:RuntimeError]}]}], :runtime]}
      rescue2 = {:->, [], [[{:in, [], [{:e, [], nil}, {:__aliases__, [], [:ArgumentError]}]}], :argument]}
      ast = {:try, [], [[do: :ok, rescue: [rescue1, rescue2]]]}
      result = ControlFlow.extract_try(ast)

      assert result.metadata.rescue_clause_count == 2
    end
  end

  # ===========================================================================
  # Receive Expression Tests
  # ===========================================================================

  describe "extract_receive/1" do
    test "extracts receive without timeout" do
      clause = {:->, [], [[{:ok, {:msg, [], nil}}], {:msg, [], nil}]}
      ast = {:receive, [], [[do: [clause]]]}
      result = ControlFlow.extract_receive(ast)

      assert result.type == :receive
      assert result.metadata.has_timeout == false
      assert result.metadata.timeout_value == nil
      assert length(result.clauses) == 1
    end

    test "extracts receive with timeout" do
      do_clause = {:->, [], [[{:ok, {:msg, [], nil}}], {:msg, [], nil}]}
      after_clause = {:->, [], [[5000], :timeout]}
      ast = {:receive, [], [[do: [do_clause], after: [after_clause]]]}
      result = ControlFlow.extract_receive(ast)

      assert result.type == :receive
      assert result.metadata.has_timeout == true
      assert result.metadata.timeout_value == 5000
      assert result.branches.after == :timeout
    end

    test "extracts receive with multiple clauses" do
      clauses = [
        {:->, [], [[{:ok, {:msg, [], nil}}], {:msg, [], nil}]},
        {:->, [], [[{:error, {:reason, [], nil}}], {:error, {:reason, [], nil}}]}
      ]
      ast = {:receive, [], [[do: clauses]]}
      result = ControlFlow.extract_receive(ast)

      assert length(result.clauses) == 2
      assert result.metadata.clause_count == 2
    end

    test "extracts receive with variable timeout" do
      do_clause = {:->, [], [[:msg], :msg]}
      timeout_var = {:timeout, [], nil}
      after_clause = {:->, [], [[timeout_var], :timeout]}
      ast = {:receive, [], [[do: [do_clause], after: [after_clause]]]}
      result = ControlFlow.extract_receive(ast)

      assert result.metadata.has_timeout == true
      assert result.metadata.timeout_value == {:timeout, [], nil}
    end
  end

  # ===========================================================================
  # Raise Expression Tests
  # ===========================================================================

  describe "extract_raise/1" do
    test "extracts raise with string message" do
      ast = {:raise, [], ["error message"]}
      result = ControlFlow.extract_raise(ast)

      assert result.type == :raise
      assert result.metadata.raise_type == :message
      assert result.metadata.message == "error message"
    end

    test "extracts raise with exception module" do
      ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}]}
      result = ControlFlow.extract_raise(ast)

      assert result.type == :raise
      assert result.metadata.raise_type == :exception
      assert result.metadata.exception_module == [:RuntimeError]
    end

    test "extracts raise with exception module and options" do
      ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}, [message: "custom error"]]}
      result = ControlFlow.extract_raise(ast)

      assert result.type == :raise
      assert result.metadata.raise_type == :exception
      assert result.metadata.exception_module == [:RuntimeError]
      assert result.metadata.options == [message: "custom error"]
    end

    test "extracts raise with namespaced exception" do
      ast = {:raise, [], [{:__aliases__, [], [:MyApp, :CustomError]}]}
      result = ControlFlow.extract_raise(ast)

      assert result.metadata.exception_module == [:MyApp, :CustomError]
    end

    test "extracts reraise" do
      ast = {:raise, [], [{:e, [], nil}]}
      result = ControlFlow.extract_raise(ast)

      assert result.metadata.raise_type == :reraise
      assert result.metadata.exception == {:e, [], nil}
    end
  end

  # ===========================================================================
  # Throw Expression Tests
  # ===========================================================================

  describe "extract_throw/1" do
    test "extracts throw with atom value" do
      ast = {:throw, [], [:value]}
      result = ControlFlow.extract_throw(ast)

      assert result.type == :throw
      assert result.metadata.thrown_value == :value
    end

    test "extracts throw with tuple value" do
      ast = {:throw, [], [{:error, :not_found}]}
      result = ControlFlow.extract_throw(ast)

      assert result.type == :throw
      assert result.metadata.thrown_value == {:error, :not_found}
    end

    test "extracts throw with variable" do
      ast = {:throw, [], [{:value, [], nil}]}
      result = ControlFlow.extract_throw(ast)

      assert result.type == :throw
      assert result.metadata.thrown_value == {:value, [], nil}
    end
  end

  # ===========================================================================
  # Main Extraction Tests
  # ===========================================================================

  describe "extract/1" do
    test "returns {:ok, result} for valid control flow" do
      assert {:ok, %ControlFlow{type: :if}} = ControlFlow.extract({:if, [], [true, [do: :ok]]})
      assert {:ok, %ControlFlow{type: :case}} = ControlFlow.extract({:case, [], [{:x, [], nil}, [do: []]]})
      assert {:ok, %ControlFlow{type: :raise}} = ControlFlow.extract({:raise, [], ["error"]})
    end

    test "returns {:error, reason} for non-control-flow" do
      assert {:error, _} = ControlFlow.extract({:def, [], nil})
      assert {:error, _} = ControlFlow.extract(:atom)
    end
  end

  describe "extract!/1" do
    test "returns result for valid control flow" do
      result = ControlFlow.extract!({:if, [], [true, [do: :ok]]})
      assert result.type == :if
    end

    test "raises ArgumentError for non-control-flow" do
      assert_raise ArgumentError, fn ->
        ControlFlow.extract!({:def, [], nil})
      end
    end
  end

  # ===========================================================================
  # Clause Extraction Tests
  # ===========================================================================

  describe "extract_clauses/1" do
    test "extracts simple clauses" do
      clauses = [
        {:->, [], [[:a], :body_a]},
        {:->, [], [[:b], :body_b]}
      ]
      result = ControlFlow.extract_clauses(clauses)

      assert length(result) == 2
      assert hd(result).patterns == [:a]
      assert hd(result).body == :body_a
    end

    test "extracts clauses with guards" do
      pattern_with_guard = {:when, [], [{:x, [], nil}, {:>, [], [{:x, [], nil}, 0]}]}
      clauses = [{:->, [], [[pattern_with_guard], :positive]}]
      result = ControlFlow.extract_clauses(clauses)

      assert length(result) == 1
      clause = hd(result)
      assert clause.patterns == [{:x, [], nil}]
      assert clause.guard == {:>, [], [{:x, [], nil}, 0]}
    end

    test "extracts clauses with multiple patterns" do
      clauses = [{:->, [], [[{:ok, {:a, [], nil}}, {:b, [], nil}], :body]}]
      result = ControlFlow.extract_clauses(clauses)

      assert length(result) == 1
      assert hd(result).patterns == [{:ok, {:a, [], nil}}, {:b, [], nil}]
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles nested control flow" do
      # if condition do case ... end else ... end
      inner_case = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:ok], :success]}]]]}
      ast = {:if, [], [true, [do: inner_case, else: :fallback]]}
      result = ControlFlow.extract_if(ast)

      assert result.type == :if
      assert result.branches.then == inner_case
    end

    test "handles empty clause lists" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}
      result = ControlFlow.extract_case(ast)

      assert result.clauses == []
      assert result.metadata.clause_count == 0
    end

    test "handles complex pattern matching in case" do
      # case value do %{key: val} -> val end
      pattern = {:%{}, [], [key: {:val, [], nil}]}
      clause = {:->, [], [[pattern], {:val, [], nil}]}
      ast = {:case, [], [{:value, [], nil}, [do: [clause]]]}
      result = ControlFlow.extract_case(ast)

      assert hd(result.clauses).patterns == [pattern]
    end

    test "handles with without final options" do
      # Edge case: with should always have options as last element
      match = {:<-, [], [{:ok, {:x, [], nil}}, {:get, [], []}]}
      ast = {:with, [], [match, [do: :ok]]}
      result = ControlFlow.extract_with(ast)

      assert result.type == :with
      assert result.branches.do == :ok
    end
  end
end
