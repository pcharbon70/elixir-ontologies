defmodule ElixirOntologies.Builders.ExpressionBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder}
  alias ElixirOntologies.NS.Core

  doctest ExpressionBuilder

  describe "build/3 mode selection" do
    setup do
      # Reset counter before each test
      ExpressionBuilder.reset_counter("https://example.org/code#")
      :ok
    end

    test "returns :skip when include_expressions is false" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns :skip for nil AST regardless of mode" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      assert ExpressionBuilder.build(nil, context, []) == :skip
    end

    test "returns :skip for dependency files even when include_expressions is true" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns {:ok, {expr_iri, triples}} when include_expressions is true and project file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      result = ExpressionBuilder.build(ast, context, [])

      assert {:ok, {expr_iri, triples}} = result
      assert is_struct(expr_iri, RDF.IRI)
      assert is_list(triples)
    end
  end

  describe "build/3 IRI generation" do
    setup do
      ExpressionBuilder.reset_counter("https://example.org/code#")
      :ok
    end

    test "generates IRI with correct base" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples}} = ExpressionBuilder.build(ast, context, [])

      iri_string = RDF.IRI.to_string(expr_iri)
      assert String.starts_with?(iri_string, "https://example.org/code#expr/")
    end

    test "accepts custom suffix option" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples}} = ExpressionBuilder.build(ast, context, suffix: "my_expr")

      iri_string = RDF.IRI.to_string(expr_iri)
      assert iri_string == "https://example.org/code#expr/my_expr"
    end

    test "generates unique IRIs for multiple calls" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _}} = ExpressionBuilder.build(ast, context, [])

      refute iri1 == iri2
    end

    test "generates deterministic sequential IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri3, _}} = ExpressionBuilder.build(ast, context, [])

      # IRIs should be sequential based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end
  end

  describe "comparison operators" do
    for op <- [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
      @op op

      test "dispatches #{op} to ComparisonOperator" do
        context =
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app/users.ex"
          )

        ast = {@op, [], [{:x, [], nil}, 1]}
        {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

        # Check for ComparisonOperator type
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ComparisonOperator
        end)

        # Check for operator symbol
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.operatorSymbol() and
            RDF.Literal.value(o) == to_string(@op)
        end)
      end
    end
  end

  describe "logical operators" do
    test "dispatches and to LogicalOperator" do
      context = full_mode_context()
      ast = {:and, [], [true, false]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")
    end

    test "dispatches or to LogicalOperator" do
      context = full_mode_context()
      ast = {:or, [], [true, false]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "or")
    end

    test "dispatches && to LogicalOperator" do
      context = full_mode_context()
      ast = {:&&, [], [true, false]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "&&")
    end

    test "dispatches || to LogicalOperator" do
      context = full_mode_context()
      ast = {:||, [], [true, false]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "||")
    end

    test "dispatches not to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:not, [], [true]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")
    end

    test "dispatches ! to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:!, [], [true]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "!")
    end
  end

  describe "arithmetic operators" do
    for op <- [:+, :-, :*, :/, :div, :rem] do
      @op op

      test "dispatches #{op} to ArithmeticOperator" do
        context = full_mode_context()
        ast = {@op, [], [1, 2]}
        {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        assert has_operator_symbol?(triples, to_string(@op))
      end
    end
  end

  describe "pipe operator" do
    test "dispatches |> to PipeOperator" do
      context = full_mode_context()
      ast = {:|>, [], [1, Enum]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.PipeOperator)
      assert has_operator_symbol?(triples, "|>")
    end
  end

  describe "string concatenation operator" do
    test "dispatches <> to StringConcatOperator" do
      context = full_mode_context()
      ast = {:<>, [], ["hello", "world"]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.StringConcatOperator)
      assert has_operator_symbol?(triples, "<>")
    end
  end

  describe "list operators" do
    test "dispatches ++ to ListOperator" do
      context = full_mode_context()
      ast = {:++, [], [[1], [2]]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "++")
    end

    test "dispatches -- to ListOperator" do
      context = full_mode_context()
      ast = {:--, [], [[1, 2], [1]]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "--")
    end
  end

  describe "match operator" do
    test "dispatches = to MatchOperator" do
      context = full_mode_context()
      ast = {:"=", [], [{:x, [], nil}, 1]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")
    end
  end

  describe "variables" do
    test "dispatches variable pattern to Variable" do
      context = full_mode_context()
      ast = {:x, [], nil}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.Variable)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "x"
      end)
    end

    test "handles variables with different names" do
      context = full_mode_context()

      for var_name <- [:user, :count, :result, :acc] do
        ast = {var_name, [], nil}
        {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.Variable)
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.name() and RDF.Literal.value(o) == to_string(var_name)
        end)
      end
    end
  end

  describe "wildcard pattern" do
    test "dispatches _ to WildcardPattern" do
      context = full_mode_context()
      ast = {:_}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.WildcardPattern)
    end
  end

  describe "remote calls" do
    test "dispatches Module.function to RemoteCall" do
      context = full_mode_context()

      # AST for String.to_integer("123")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [],
         ["123"]}

      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)

      # Check for name property with module and function
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and
          RDF.Literal.value(o) == "String.to_integer"
      end)
    end

    test "handles nested module names" do
      context = full_mode_context()

      # AST for MyApp.Users.get(1)
      ast =
        {{:., [], [{:__aliases__, [], [:MyApp, :Users]}, :get]}, [], [1]}

      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "MyApp.Users.get"
      end)
    end
  end

  describe "local calls" do
    test "dispatches function(args) to LocalCall" do
      context = full_mode_context()
      ast = {:foo, [], [1, 2]}
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LocalCall)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "foo"
      end)
    end
  end

  describe "literals" do
    test "returns empty triples for standalone integer literals" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(42, context, [])

      # Literals are handled inline in parent expressions
      assert triples == []
    end

    test "returns empty triples for standalone float literals" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(3.14, context, [])

      assert triples == []
    end

    test "returns empty triples for standalone string literals" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build("hello", context, [])

      assert triples == []
    end

    test "returns empty triples for standalone atom literals" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(:ok, context, [])

      assert triples == []
    end

    test "returns empty triples for true" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(true, context, [])

      assert triples == []
    end

    test "returns empty triples for false" do
      context = full_mode_context()
      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(false, context, [])

      assert triples == []
    end

    test "returns :skip for nil literals" do
      context = full_mode_context()
      assert ExpressionBuilder.build(nil, context, []) == :skip
    end
  end

  describe "unknown expressions" do
    test "dispatches unknown AST to generic Expression type" do
      context = full_mode_context()

      # Some unusual AST that doesn't match our patterns
      # Using a 2-element tuple which is not a standard Elixir AST form
      unusual_ast = {:some_unknown_form, :unexpected_second_element}

      {:ok, {_expr_iri, triples}} = ExpressionBuilder.build(unusual_ast, context, [])

      assert has_type?(triples, Core.Expression)
    end
  end

  describe "expression_iri/3" do
    test "generates IRI with counter-based suffix when no options provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, updated_context} = ExpressionBuilder.expression_iri("https://example.org/code#", context)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_0"
      assert Context.get_expression_counter(updated_context) == 1
    end

    test "increments counter on each call" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri1, ctx1} = ExpressionBuilder.expression_iri("https://example.org/code#", context)
      {iri2, ctx2} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx1)
      {iri3, _ctx3} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx2)

      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "uses custom suffix when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, suffix: "my_custom_expr")

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/my_custom_expr"
      # Counter should not be incremented when custom suffix is used
      assert Context.get_expression_counter(updated_context) == 5
    end

    test "uses explicit counter option when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, counter: 42)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_42"
      # Counter should not be incremented when explicit counter is used
      assert Context.get_expression_counter(updated_context) == 10
    end

    test "handles different base IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, _ctx} =
        ExpressionBuilder.expression_iri("https://other.org/base#", context)

      assert RDF.IRI.to_string(iri) == "https://other.org/base#expr/expr_0"
    end
  end

  describe "fresh_iri/2" do
    test "creates relative IRI from parent with left child" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      child_iri = ExpressionBuilder.fresh_iri(parent, "left")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/0/left"
    end

    test "creates relative IRI from parent with right child" do
      parent = RDF.IRI.new("https://example.org/code#expr/5")

      child_iri = ExpressionBuilder.fresh_iri(parent, "right")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/5/right"
    end

    test "creates nested relative IRIs" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left_iri = ExpressionBuilder.fresh_iri(parent, "left")
      left_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")

      assert RDF.IRI.to_string(left_iri) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(left_left_iri) == "https://example.org/code#expr/0/left/left"
    end

    test "handles various child names" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      assert ExpressionBuilder.fresh_iri(parent, "condition")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/condition"

      assert ExpressionBuilder.fresh_iri(parent, "then")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/then"

      assert ExpressionBuilder.fresh_iri(parent, "else")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/else"

      assert ExpressionBuilder.fresh_iri(parent, "operand")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/operand"
    end
  end

  describe "get_or_create_iri/3" do
    test "creates new IRI when cache is nil" do
      generator = fn -> RDF.IRI.new("https://example.org/expr/0") end

      {iri, cache} = ExpressionBuilder.get_or_create_iri(nil, :some_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/0"
      assert cache == %{}
    end

    test "creates and caches new IRI on first call" do
      cache = %{}
      generator = fn -> RDF.IRI.new("https://example.org/expr/new") end

      {iri, updated_cache} =
        ExpressionBuilder.get_or_create_iri(cache, :my_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/new"
      assert Map.has_key?(updated_cache, :my_key)
    end

    test "reuses cached IRI on subsequent calls with same key" do
      cache = %{}
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :same_key, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :same_key, gen2)

      # Second generator should not be called - IRI is reused
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/expr/first"
      assert cache2 == cache1
    end

    test "creates different IRIs for different keys" do
      cache = %{}

      # Each key gets its own generator
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :key2, gen2)

      # Should create two different IRIs
      refute iri1 == iri2
      assert Map.has_key?(cache2, :key1)
      assert Map.has_key?(cache2, :key2)
    end

    test "works with complex cache keys" do
      cache = %{}

      # Using AST structure as cache key
      ast_key1 = {:==, [], [{:x, [], nil}, 1]}
      ast_key2 = {:==, [], [{:y, [], nil}, 2]}
      ast_key3 = {:==, [], [{:x, [], nil}, 1]} # Same as key1

      # Create unique generators for each key
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/hash1") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/hash2") end
      gen3 = fn -> RDF.IRI.new("https://example.org/expr/hash3") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, ast_key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, ast_key2, gen2)
      {iri3, _cache3} = ExpressionBuilder.get_or_create_iri(cache2, ast_key3, gen3)

      # key1 and key3 are the same, so IRIs should match (key3 reuses cached value from key1)
      assert iri1 == iri3
      refute iri1 == iri2
    end
  end

  describe "Context expression counter" do
    test "with_expression_counter/1 initializes counter to 0" do
      context = Context.new(base_iri: "https://example.org/code#")

      initialized = Context.with_expression_counter(context)

      assert Context.get_expression_counter(initialized) == 0
    end

    test "next_expression_counter/1 returns current counter and increments" do
      context = Context.new(base_iri: "https://example.org/code#")
      context = Context.with_expression_counter(context)

      {counter1, ctx1} = Context.next_expression_counter(context)
      {counter2, ctx2} = Context.next_expression_counter(ctx1)
      {counter3, _ctx3} = Context.next_expression_counter(ctx2)

      assert counter1 == 0
      assert counter2 == 1
      assert counter3 == 2
    end

    test "next_expression_counter/1 works with pre-initialized counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {counter, updated_ctx} = Context.next_expression_counter(context)

      assert counter == 5
      assert Context.get_expression_counter(updated_ctx) == 6
    end

    test "get_expression_counter/1 returns current counter without incrementing" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      assert Context.get_expression_counter(context) == 10
      assert Context.get_expression_counter(context) == 10 # Still 10
    end

    test "get_expression_counter/1 defaults to 0 when not set" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_expression_counter(context) == 0
    end
  end

  describe "integration tests" do
    setup do
      ExpressionBuilder.reset_counter("https://example.org/code#")
      ExpressionBuilder.reset_counter("https://other.org/base#")
      :ok
    end

    test "complete IRI flow through ExpressionBuilder" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      # Build multiple expressions and verify sequential IRIs
      ast1 = {:==, [], [{:x, [], nil}, 1]}
      ast2 = {:>, [], [{:y, [], nil}, 5]}
      ast3 = {:and, [], [true, false]}

      {:ok, {iri1, _}} = ExpressionBuilder.build(ast1, context, [])
      {:ok, {iri2, _}} = ExpressionBuilder.build(ast2, context, [])
      {:ok, {iri3, _}} = ExpressionBuilder.build(ast3, context, [])

      # Sequential IRIs based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "fresh_iri creates proper hierarchy for nested expressions" do
      # Simulate nested binary operator: x > 5 and y < 10
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left = ExpressionBuilder.fresh_iri(parent, "left")
      right = ExpressionBuilder.fresh_iri(parent, "right")

      # Verify hierarchy
      assert RDF.IRI.to_string(left) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(right) == "https://example.org/code#expr/0/right"

      # Nested children
      left_left = ExpressionBuilder.fresh_iri(left, "left")
      assert RDF.IRI.to_string(left_left) == "https://example.org/code#expr/0/left/left"
    end

    test "get_or_create_iri enables expression deduplication" do
      # Simulate shared sub-expression: x == 1 appearing twice
      shared_expr = {:==, [], [{:x, [], nil}, 1]}

      cache = %{}

      # First occurrence - creates new IRI
      {iri1, cache1} =
        ExpressionBuilder.get_or_create_iri(
          cache,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_0") end
        )

      # Second occurrence - reuses cached IRI
      {iri2, cache2} =
        ExpressionBuilder.get_or_create_iri(
          cache1,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_new") end
        )

      # Same IRI should be returned
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/shared_0"

      # Different expression - creates new IRI
      different_expr = {:!=, [], [{:y, [], nil}, 2]}
      {iri3, _cache3} =
        ExpressionBuilder.get_or_create_iri(
          cache2,
          different_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_1") end
        )

      refute iri1 == iri3
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/shared_1"
    end

    test "counter properly resets between different contexts" do
      # Setup: reset counters for both base IRIs
      ExpressionBuilder.reset_counter("https://example.org/code#")
      ExpressionBuilder.reset_counter("https://other.org/base#")

      # Context 1
      context1 =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      {:ok, {iri1, _}} = ExpressionBuilder.build({:==, [], [1, 1]}, context1, [])
      {:ok, {iri2, _}} = ExpressionBuilder.build({:==, [], [2, 2]}, context1, [])

      # Context 2 - different base IRI, so counter starts at 0
      context2 =
        Context.new(
          base_iri: "https://other.org/base#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/accounts.ex"
        )

      {:ok, {iri3, _}} = ExpressionBuilder.build({:==, [], [3, 3]}, context2, [])

      # context1 starts at expr_0 and increments
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"

      # context2 has different base IRI, so starts at expr_0
      assert RDF.IRI.to_string(iri3) == "https://other.org/base#expr/expr_0"
    end

    test "custom suffix option bypasses counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )

      # Use custom suffix
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {iri1, _}} = ExpressionBuilder.build(ast, context, suffix: "custom_expr")

      # Next expression without suffix should use counter
      {:ok, {iri2, _}} = ExpressionBuilder.build(ast, context, [])

      # Custom suffix should be respected
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/custom_expr"
      # Counter expression should start at 0
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_0"
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp full_mode_context do
    Context.new(
      base_iri: "https://example.org/code#",
      config: %{include_expressions: true},
      file_path: "lib/my_app/users.ex"
    )
  end

  defp has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == expected_type end)
  end

  defp has_operator_symbol?(triples, symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end
end
