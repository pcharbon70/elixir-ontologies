defmodule ElixirOntologies.Extractors.CaseWithTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.CaseWith

  alias ElixirOntologies.Extractors.CaseWith.{
    AfterClause,
    CaseClause,
    CaseExpression,
    ReceiveExpression,
    WithClause,
    WithExpression
  }

  doctest CaseWith

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "case_expression?/1" do
    test "returns true for basic case" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      assert CaseWith.case_expression?(ast)
    end

    test "returns true for case with multiple clauses" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}, {:->, [], [[:b], 2]}]]]}
      assert CaseWith.case_expression?(ast)
    end

    test "returns false for with expression" do
      ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      refute CaseWith.case_expression?(ast)
    end

    test "returns false for if expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      refute CaseWith.case_expression?(ast)
    end

    test "returns false for function call" do
      ast = {:foo, [], []}
      refute CaseWith.case_expression?(ast)
    end

    test "returns false for variable" do
      ast = {:x, [], nil}
      refute CaseWith.case_expression?(ast)
    end
  end

  describe "with_expression?/1" do
    test "returns true for basic with" do
      ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      assert CaseWith.with_expression?(ast)
    end

    test "returns true for with with multiple clauses" do
      ast = {:with, [], [
        {:<-, [], [:ok, {:a, [], []}]},
        {:<-, [], [:ok, {:b, [], []}]},
        [do: :ok]
      ]}
      assert CaseWith.with_expression?(ast)
    end

    test "returns true for with with else" do
      ast = {:with, [], [
        {:<-, [], [:ok, {:get, [], []}]},
        [do: :ok, else: [{:->, [], [[{:error, {:e, [], nil}}], {:e, [], nil}]}]]
      ]}
      assert CaseWith.with_expression?(ast)
    end

    test "returns false for case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      refute CaseWith.with_expression?(ast)
    end

    test "returns false for if expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      refute CaseWith.with_expression?(ast)
    end

    test "returns false for function call" do
      ast = {:foo, [], []}
      refute CaseWith.with_expression?(ast)
    end
  end

  # ===========================================================================
  # Case Extraction Tests
  # ===========================================================================

  describe "extract_case/2" do
    test "extracts case with single clause" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      assert %CaseExpression{} = expr
      assert expr.subject == {:x, [], nil}
      assert length(expr.clauses) == 1
    end

    test "extracts case with multiple clauses" do
      ast = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[:a], 1]},
        {:->, [], [[:b], 2]},
        {:->, [], [[:c], 3]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      assert length(expr.clauses) == 3
      assert expr.metadata.clause_count == 3
    end

    test "extracts clause indices correctly" do
      ast = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[:a], 1]},
        {:->, [], [[:b], 2]},
        {:->, [], [[:c], 3]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      indices = Enum.map(expr.clauses, & &1.index)
      assert indices == [0, 1, 2]
    end

    test "extracts clause patterns" do
      ast = {:case, [], [{:result, [], nil}, [do: [
        {:->, [], [[{:ok, {:value, [], nil}}], {:value, [], nil}]},
        {:->, [], [[{:error, {:reason, [], nil}}], {:reason, [], nil}]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      [clause1, clause2] = expr.clauses

      assert clause1.pattern == {:ok, {:value, [], nil}}
      assert clause2.pattern == {:error, {:reason, [], nil}}
    end

    test "extracts clause bodies" do
      ast = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[:a], {:do_something, [], []}]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      [clause] = expr.clauses
      assert clause.body == {:do_something, [], []}
    end

    test "extracts clauses with guards" do
      ast = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[{:when, [], [{:n, [], nil}, {:>, [], [{:n, [], nil}, 0]}]}], :positive]},
        {:->, [], [[{:_, [], nil}], :other]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      [guarded_clause, simple_clause] = expr.clauses

      assert guarded_clause.has_guard == true
      assert guarded_clause.pattern == {:n, [], nil}
      assert guarded_clause.guard == {:>, [], [{:n, [], nil}, 0]}

      assert simple_clause.has_guard == false
      assert simple_clause.guard == nil
    end

    test "tracks has_guards in metadata" do
      ast_with_guards = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[{:when, [], [{:n, [], nil}, {:>, [], [{:n, [], nil}, 0]}]}], :ok]}
      ]]]}

      ast_without_guards = {:case, [], [{:x, [], nil}, [do: [
        {:->, [], [[:a], 1]}
      ]]]}

      assert {:ok, expr_with} = CaseWith.extract_case(ast_with_guards)
      assert {:ok, expr_without} = CaseWith.extract_case(ast_without_guards)

      assert expr_with.metadata.has_guards == true
      assert expr_without.metadata.has_guards == false
    end

    test "handles complex subject expression" do
      subject = {:get_value, [], [{:x, [], nil}]}
      ast = {:case, [], [subject, [do: [{:->, [], [[:a], 1]}]]]}

      assert {:ok, expr} = CaseWith.extract_case(ast)
      assert expr.subject == subject
    end

    test "returns error for non-case expression" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      assert {:error, {:not_a_case, _}} = CaseWith.extract_case(ast)
    end
  end

  describe "extract_case!/2" do
    test "returns expression for valid case" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}

      expr = CaseWith.extract_case!(ast)
      assert %CaseExpression{} = expr
    end

    test "raises for invalid input" do
      ast = {:if, [], [{:x, [], nil}, [do: :ok]]}

      assert_raise ArgumentError, fn ->
        CaseWith.extract_case!(ast)
      end
    end
  end

  # ===========================================================================
  # With Extraction Tests
  # ===========================================================================

  describe "extract_with/2" do
    test "extracts with with single match clause" do
      ast = {:with, [], [
        {:<-, [], [{:ok, {:a, [], nil}}, {:get, [], []}]},
        [do: {:a, [], nil}]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      assert %WithExpression{} = expr
      assert length(expr.clauses) == 1
      assert expr.has_else == false
    end

    test "extracts with with multiple clauses" do
      ast = {:with, [], [
        {:<-, [], [{:ok, {:a, [], nil}}, {:get_a, [], []}]},
        {:<-, [], [{:ok, {:b, [], nil}}, {:get_b, [], []}]},
        {:<-, [], [{:ok, {:c, [], nil}}, {:get_c, [], []}]},
        [do: :ok]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      assert length(expr.clauses) == 3
      assert expr.metadata.clause_count == 3
    end

    test "extracts clause indices correctly" do
      ast = {:with, [], [
        {:<-, [], [:a, {:a, [], []}]},
        {:<-, [], [:b, {:b, [], []}]},
        [do: :ok]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      indices = Enum.map(expr.clauses, & &1.index)
      assert indices == [0, 1]
    end

    test "extracts match clause patterns and expressions" do
      ast = {:with, [], [
        {:<-, [], [{:ok, {:value, [], nil}}, {:fetch, [], []}]},
        [do: {:value, [], nil}]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      [clause] = expr.clauses

      assert clause.type == :match
      assert clause.pattern == {:ok, {:value, [], nil}}
      assert clause.expression == {:fetch, [], []}
    end

    test "extracts bare match clauses" do
      ast = {:with, [], [
        {:<-, [], [:ok, {:validate, [], []}]},
        {:=, [], [{:user, [], nil}, {:fetch_user, [], []}]},
        [do: {:user, [], nil}]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      [match_clause, bare_clause] = expr.clauses

      assert match_clause.type == :match
      assert bare_clause.type == :bare_match
      assert bare_clause.pattern == {:user, [], nil}
      assert bare_clause.expression == {:fetch_user, [], []}
    end

    test "tracks has_bare_match in metadata" do
      ast_with_bare = {:with, [], [
        {:=, [], [{:x, [], nil}, {:get, [], []}]},
        [do: :ok]
      ]}

      ast_without_bare = {:with, [], [
        {:<-, [], [:ok, {:get, [], []}]},
        [do: :ok]
      ]}

      assert {:ok, with_bare} = CaseWith.extract_with(ast_with_bare)
      assert {:ok, without_bare} = CaseWith.extract_with(ast_without_bare)

      assert with_bare.metadata.has_bare_match == true
      assert without_bare.metadata.has_bare_match == false
    end

    test "extracts body expression" do
      body = {:ok, {:+, [], [{:a, [], nil}, {:b, [], nil}]}}
      ast = {:with, [], [
        {:<-, [], [:ok, {:get, [], []}]},
        [do: body]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      assert expr.body == body
    end

    test "extracts else clauses" do
      ast = {:with, [], [
        {:<-, [], [{:ok, {:a, [], nil}}, {:get, [], []}]},
        [
          do: {:a, [], nil},
          else: [
            {:->, [], [[{:error, {:reason, [], nil}}], {:error, {:reason, [], nil}}]},
            {:->, [], [[{:_, [], nil}], {:error, :unknown}]}
          ]
        ]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      assert expr.has_else == true
      assert length(expr.else_clauses) == 2
      assert expr.metadata.else_clause_count == 2

      [else1, else2] = expr.else_clauses
      assert %CaseClause{} = else1
      assert else1.index == 0
      assert else2.index == 1
    end

    test "handles with without else" do
      ast = {:with, [], [
        {:<-, [], [:ok, {:get, [], []}]},
        [do: :ok]
      ]}

      assert {:ok, expr} = CaseWith.extract_with(ast)
      assert expr.has_else == false
      assert expr.else_clauses == []
    end

    test "returns error for non-with expression" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}
      assert {:error, {:not_a_with, _}} = CaseWith.extract_with(ast)
    end
  end

  describe "extract_with!/2" do
    test "returns expression for valid with" do
      ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}

      expr = CaseWith.extract_with!(ast)
      assert %WithExpression{} = expr
    end

    test "raises for invalid input" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}

      assert_raise ArgumentError, fn ->
        CaseWith.extract_with!(ast)
      end
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_case_expressions/2" do
    test "extracts single case from list" do
      body = [{:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}]

      exprs = CaseWith.extract_case_expressions(body)
      assert length(exprs) == 1
    end

    test "extracts multiple cases from list" do
      body = [
        {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]},
        {:foo, [], []},
        {:case, [], [{:y, [], nil}, [do: [{:->, [], [[:b], 2]}]]]}
      ]

      exprs = CaseWith.extract_case_expressions(body)
      assert length(exprs) == 2
    end

    test "extracts case from function body" do
      ast = {:def, [], [{:run, [], nil}, [do: {:case, [], [{:x, [], nil}, [do: []]]}]]}

      exprs = CaseWith.extract_case_expressions(ast)
      assert length(exprs) == 1
    end

    test "extracts nested case expressions" do
      inner = {:case, [], [{:y, [], nil}, [do: [{:->, [], [[:inner], :inner]}]]]}
      outer = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:outer], inner]}]]]}

      exprs = CaseWith.extract_case_expressions(outer)
      assert length(exprs) == 2
    end

    test "does not extract with expressions" do
      body = [
        {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]},
        {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      ]

      exprs = CaseWith.extract_case_expressions(body)
      assert length(exprs) == 1
    end

    test "handles block structures" do
      block = {:__block__, [], [
        {:case, [], [{:a, [], nil}, [do: [{:->, [], [[:x], 1]}]]]},
        {:case, [], [{:b, [], nil}, [do: [{:->, [], [[:y], 2]}]]]}
      ]}

      exprs = CaseWith.extract_case_expressions(block)
      assert length(exprs) == 2
    end

    test "returns empty list for non-case AST" do
      ast = {:foo, [], [{:bar, [], []}]}

      exprs = CaseWith.extract_case_expressions(ast)
      assert exprs == []
    end
  end

  describe "extract_with_expressions/2" do
    test "extracts single with from list" do
      body = [{:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}]

      exprs = CaseWith.extract_with_expressions(body)
      assert length(exprs) == 1
    end

    test "extracts multiple with expressions from list" do
      body = [
        {:with, [], [{:<-, [], [:ok, {:a, [], []}]}, [do: :ok]]},
        {:foo, [], []},
        {:with, [], [{:<-, [], [:ok, {:b, [], []}]}, [do: :ok]]}
      ]

      exprs = CaseWith.extract_with_expressions(body)
      assert length(exprs) == 2
    end

    test "extracts nested with expressions" do
      inner = {:with, [], [{:<-, [], [:ok, {:inner, [], []}]}, [do: :inner]]}
      outer = {:with, [], [{:<-, [], [:ok, {:outer, [], []}]}, [do: inner]]}

      exprs = CaseWith.extract_with_expressions(outer)
      assert length(exprs) == 2
    end

    test "does not extract case expressions" do
      body = [
        {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]},
        {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      ]

      exprs = CaseWith.extract_with_expressions(body)
      assert length(exprs) == 1
    end

    test "returns empty list for non-with AST" do
      ast = {:foo, [], [{:bar, [], []}]}

      exprs = CaseWith.extract_with_expressions(ast)
      assert exprs == []
    end
  end

  # ===========================================================================
  # Struct Field Tests
  # ===========================================================================

  describe "CaseClause struct" do
    test "has required fields" do
      clause = %CaseClause{index: 0, pattern: :a, body: 1}
      assert clause.index == 0
      assert clause.pattern == :a
      assert clause.body == 1
      assert clause.guard == nil
      assert clause.has_guard == false
      assert clause.location == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(CaseClause, [])
      end
    end
  end

  describe "CaseExpression struct" do
    test "has required fields" do
      expr = %CaseExpression{subject: {:x, [], nil}}
      assert expr.subject == {:x, [], nil}
      assert expr.clauses == []
      assert expr.location == nil
      assert expr.metadata == %{}
    end

    test "enforces subject key" do
      assert_raise ArgumentError, fn ->
        struct!(CaseExpression, [])
      end
    end
  end

  describe "WithClause struct" do
    test "has required fields" do
      clause = %WithClause{index: 0, type: :match, pattern: :ok, expression: {:get, [], []}}
      assert clause.index == 0
      assert clause.type == :match
      assert clause.pattern == :ok
      assert clause.expression == {:get, [], []}
      assert clause.location == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(WithClause, [])
      end
    end
  end

  describe "WithExpression struct" do
    test "has required fields" do
      expr = %WithExpression{clauses: [], body: :ok}
      assert expr.clauses == []
      assert expr.body == :ok
      assert expr.else_clauses == []
      assert expr.has_else == false
      assert expr.location == nil
      assert expr.metadata == %{}
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(WithExpression, [])
      end
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "extracts case from real module AST" do
      code = """
      defmodule Example do
        def handle(result) do
          case result do
            {:ok, value} -> {:success, value}
            {:error, reason} -> {:failure, reason}
            _ -> :unknown
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_case_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs
      assert length(expr.clauses) == 3
    end

    test "extracts case with guards from real code" do
      code = """
      def classify(n) do
        case n do
          x when x > 0 -> :positive
          x when x < 0 -> :negative
          _ -> :zero
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_case_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs

      guarded = Enum.filter(expr.clauses, & &1.has_guard)
      assert length(guarded) == 2
    end

    test "extracts with from real module AST" do
      code = """
      defmodule Example do
        def process(id) do
          with {:ok, user} <- fetch_user(id),
               {:ok, data} <- fetch_data(user) do
            {:ok, transform(data)}
          else
            {:error, :not_found} -> {:error, "User not found"}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_with_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs
      assert length(expr.clauses) == 2
      assert expr.has_else == true
      assert length(expr.else_clauses) == 2
    end

    test "extracts with with bare match from real code" do
      code = """
      def transform(input) do
        with :ok <- validate(input),
             data = prepare(input),
             {:ok, result} <- process(data) do
          result
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_with_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs
      assert length(expr.clauses) == 3

      types = Enum.map(expr.clauses, & &1.type)
      assert types == [:match, :bare_match, :match]
    end

    test "handles complex nested case and with" do
      code = """
      def complex(input) do
        with {:ok, a} <- get_a() do
          case a do
            :special -> handle_special()
            other -> handle_other(other)
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      case_exprs = CaseWith.extract_case_expressions(ast)
      with_exprs = CaseWith.extract_with_expressions(ast)

      assert length(case_exprs) == 1
      assert length(with_exprs) == 1
    end
  end

  # ===========================================================================
  # Receive Type Detection Tests
  # ===========================================================================

  describe "receive_expression?/1" do
    test "returns true for basic receive" do
      ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}
      assert CaseWith.receive_expression?(ast)
    end

    test "returns true for receive with after" do
      ast = {:receive, [], [[do: [], after: [{:->, [], [[0], :timeout]}]]]}
      assert CaseWith.receive_expression?(ast)
    end

    test "returns false for case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      refute CaseWith.receive_expression?(ast)
    end

    test "returns false for with expression" do
      ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      refute CaseWith.receive_expression?(ast)
    end

    test "returns false for function call" do
      ast = {:foo, [], []}
      refute CaseWith.receive_expression?(ast)
    end
  end

  # ===========================================================================
  # Receive Extraction Tests
  # ===========================================================================

  describe "extract_receive/2" do
    test "extracts receive with single clause" do
      ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      assert %ReceiveExpression{} = expr
      assert length(expr.clauses) == 1
      assert expr.has_after == false
      assert expr.after_clause == nil
    end

    test "extracts receive with multiple clauses" do
      ast = {:receive, [], [[do: [
        {:->, [], [[:ping], :pong]},
        {:->, [], [[{:msg, {:data, [], nil}}], {:data, [], nil}]},
        {:->, [], [[{:_, [], nil}], :unknown]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      assert length(expr.clauses) == 3
      assert expr.metadata.clause_count == 3
    end

    test "extracts clause patterns" do
      ast = {:receive, [], [[do: [
        {:->, [], [[{:msg, {:data, [], nil}}], {:data, [], nil}]},
        {:->, [], [[:ping], :pong]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      [clause1, clause2] = expr.clauses

      assert clause1.pattern == {:msg, {:data, [], nil}}
      assert clause2.pattern == :ping
    end

    test "extracts clauses with guards" do
      ast = {:receive, [], [[do: [
        {:->, [], [[{:when, [], [{:n, [], nil}, {:>, [], [{:n, [], nil}, 0]}]}], :positive]}
      ]]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      [clause] = expr.clauses

      assert clause.has_guard == true
      assert clause.pattern == {:n, [], nil}
      assert clause.guard == {:>, [], [{:n, [], nil}, 0]}
    end

    test "extracts receive with after clause" do
      ast = {:receive, [], [[
        do: [{:->, [], [[:msg], :ok]}],
        after: [{:->, [], [[5000], :timeout]}]
      ]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      assert expr.has_after == true
      assert %AfterClause{} = expr.after_clause
      assert expr.after_clause.timeout == 5000
      assert expr.after_clause.body == :timeout
      assert expr.after_clause.is_immediate == false
    end

    test "detects immediate timeout (timeout 0)" do
      ast = {:receive, [], [[
        do: [{:->, [], [[:msg], :ok]}],
        after: [{:->, [], [[0], :no_messages]}]
      ]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      assert expr.after_clause.is_immediate == true
      assert expr.metadata.has_immediate_timeout == true
    end

    test "extracts receive with only after (empty do block)" do
      ast = {:receive, [], [[do: {:__block__, [], []}, after: [{:->, [], [[0], :timeout]}]]]}

      assert {:ok, expr} = CaseWith.extract_receive(ast)
      assert expr.clauses == []
      assert expr.has_after == true
      assert expr.after_clause.timeout == 0
    end

    test "tracks blocking in metadata" do
      # Receive without after is blocking
      ast_blocking = {:receive, [], [[do: [{:->, [], [[:msg], :ok]}]]]}

      # Receive with non-zero after is still potentially blocking
      ast_with_timeout = {:receive, [], [[
        do: [{:->, [], [[:msg], :ok]}],
        after: [{:->, [], [[5000], :timeout]}]
      ]]}

      # Receive with timeout 0 is non-blocking
      ast_immediate = {:receive, [], [[
        do: [{:->, [], [[:msg], :ok]}],
        after: [{:->, [], [[0], :no_messages]}]
      ]]}

      assert {:ok, blocking} = CaseWith.extract_receive(ast_blocking)
      assert {:ok, with_timeout} = CaseWith.extract_receive(ast_with_timeout)
      assert {:ok, immediate} = CaseWith.extract_receive(ast_immediate)

      assert blocking.metadata.is_blocking == true
      assert with_timeout.metadata.is_blocking == true
      assert immediate.metadata.is_blocking == false
    end

    test "returns error for non-receive expression" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}
      assert {:error, {:not_a_receive, _}} = CaseWith.extract_receive(ast)
    end
  end

  describe "extract_receive!/2" do
    test "returns expression for valid receive" do
      ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}

      expr = CaseWith.extract_receive!(ast)
      assert %ReceiveExpression{} = expr
    end

    test "raises for invalid input" do
      ast = {:case, [], [{:x, [], nil}, [do: []]]}

      assert_raise ArgumentError, fn ->
        CaseWith.extract_receive!(ast)
      end
    end
  end

  # ===========================================================================
  # Receive Bulk Extraction Tests
  # ===========================================================================

  describe "extract_receive_expressions/2" do
    test "extracts single receive from list" do
      body = [{:receive, [], [[do: [{:->, [], [[:a], 1]}]]]}]

      exprs = CaseWith.extract_receive_expressions(body)
      assert length(exprs) == 1
    end

    test "extracts multiple receives from list" do
      body = [
        {:receive, [], [[do: [{:->, [], [[:a], 1]}]]]},
        {:foo, [], []},
        {:receive, [], [[do: [{:->, [], [[:b], 2]}]]]}
      ]

      exprs = CaseWith.extract_receive_expressions(body)
      assert length(exprs) == 2
    end

    test "extracts nested receive expressions" do
      inner = {:receive, [], [[do: [{:->, [], [[:inner], :inner]}]]]}
      outer = {:receive, [], [[do: [{:->, [], [[:outer], inner]}]]]}

      exprs = CaseWith.extract_receive_expressions(outer)
      assert length(exprs) == 2
    end

    test "does not extract case or with expressions" do
      body = [
        {:receive, [], [[do: [{:->, [], [[:msg], :ok]}]]]},
        {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]},
        {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      ]

      exprs = CaseWith.extract_receive_expressions(body)
      assert length(exprs) == 1
    end

    test "returns empty list for non-receive AST" do
      ast = {:foo, [], [{:bar, [], []}]}

      exprs = CaseWith.extract_receive_expressions(ast)
      assert exprs == []
    end
  end

  # ===========================================================================
  # Receive Struct Field Tests
  # ===========================================================================

  describe "AfterClause struct" do
    test "has required fields" do
      clause = %AfterClause{timeout: 5000, body: :timeout}
      assert clause.timeout == 5000
      assert clause.body == :timeout
      assert clause.is_immediate == false
      assert clause.location == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(AfterClause, [])
      end
    end
  end

  describe "ReceiveExpression struct" do
    test "has required fields" do
      expr = %ReceiveExpression{}
      assert expr.clauses == []
      assert expr.after_clause == nil
      assert expr.has_after == false
      assert expr.location == nil
      assert expr.metadata == %{}
    end
  end

  # ===========================================================================
  # Receive Integration Tests
  # ===========================================================================

  describe "receive integration" do
    test "extracts receive from GenServer handle_info" do
      code = """
      def loop(state) do
        receive do
          {:call, from, request} ->
            {reply, new_state} = handle_call(request, state)
            send(from, reply)
            loop(new_state)

          {:cast, request} ->
            new_state = handle_cast(request, state)
            loop(new_state)

          :stop ->
            :ok
        after
          5000 ->
            handle_timeout(state)
            loop(state)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_receive_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs
      assert length(expr.clauses) == 3
      assert expr.has_after == true
      assert expr.after_clause.timeout == 5000
    end

    test "extracts receive with guards from real code" do
      code = """
      def receive_data do
        receive do
          {:data, n} when n > 0 -> {:positive, n}
          {:data, n} when n < 0 -> {:negative, n}
          {:data, 0} -> :zero
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_receive_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs

      guarded = Enum.filter(expr.clauses, & &1.has_guard)
      assert length(guarded) == 2
    end

    test "extracts non-blocking receive (timeout 0)" do
      code = """
      def flush_mailbox do
        receive do
          _msg -> flush_mailbox()
        after
          0 -> :done
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      exprs = CaseWith.extract_receive_expressions(ast)

      assert length(exprs) == 1
      [expr] = exprs
      assert expr.metadata.is_blocking == false
      assert expr.metadata.has_immediate_timeout == true
    end
  end
end
