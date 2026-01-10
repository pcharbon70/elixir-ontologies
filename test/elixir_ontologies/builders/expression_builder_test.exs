defmodule ElixirOntologies.Builders.ExpressionBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.ExpressionBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.Core

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup do
    # Reset counter before each test
    ExpressionBuilder.reset_counter("https://example.org/code#")
    :ok
  end

  # ===========================================================================
  # Section 21.2.2: Main build/3 Function Tests
  # ===========================================================================

  describe "build/3 in light mode" do
    test "returns :skip when include_expressions is false" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false},
          file_path: "lib/my_app.ex"
        )

      assert ExpressionBuilder.build({:==, [], [1, 2]}, context, []) == :skip
    end

    test "returns :skip for nil AST" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app.ex"
        )

      assert ExpressionBuilder.build(nil, context, []) == :skip
    end
  end

  describe "build/3 for dependency files" do
    test "returns :skip for dependency files even in full mode" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      assert ExpressionBuilder.build({:==, [], [1, 2]}, context, []) == :skip
    end

    test "returns :skip for nested dependency paths" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/nimble_parsec/lib/mix/tasks/compile.ex"
        )

      assert ExpressionBuilder.build({:==, [], [1, 2]}, context, []) == :skip
    end
  end

  describe "build/3 in full mode for project files" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    test "returns {:ok, {iri, triples}} for comparison operators", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build({:==, [], [1, 2]}, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for logical operators", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build({:and, [], [true, false]}, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for arithmetic operators", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build({:+, [], [1, 2]}, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for integer literals", context do
      assert {:ok, {iri, triples}} = ExpressionBuilder.build(42, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for string literals", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build("hello", context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for atom literals", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build(:foo, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for variables", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build({:x, [], nil}, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "returns {:ok, {iri, triples}} for wildcard pattern", context do
      assert {:ok, {iri, triples}} =
               ExpressionBuilder.build({:_}, context.context, [])

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end
  end

  # ===========================================================================
  # Section 21.2.3: Expression Dispatch Tests
  # ===========================================================================

  describe "expression dispatch - comparison operators" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    for op <- [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
      test "dispatches #{op} operator correctly", context do
        ExpressionBuilder.reset_counter("https://example.org/code#")

        assert {:ok, {iri, triples}} =
                 ExpressionBuilder.build({unquote(op), [], [1, 2]}, context.context, [])

        assert has_type?(triples, Core.ComparisonOperator)
        assert has_operator_symbol?(triples, Atom.to_string(unquote(op)))
      end
    end
  end

  describe "expression dispatch - logical operators" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    test "dispatches and operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:and, [], [true, false]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")
    end

    test "dispatches or operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:or, [], [true, false]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "or")
    end

    test "dispatches not operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:not, [], [true]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")
    end

    test "dispatches && operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:&&, [], [true, false]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "&&")
    end

    test "dispatches || operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:||, [], [true, false]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "||")
    end

    test "dispatches ! operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:!, [], [true]}, context.context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "!")
    end
  end

  describe "expression dispatch - arithmetic operators" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    for op <- [:+, :-, :*, :/] do
      test "dispatches #{op} operator correctly", context do
        ExpressionBuilder.reset_counter("https://example.org/code#")

        assert {:ok, {_iri, triples}} =
                 ExpressionBuilder.build({unquote(op), [], [1, 2]}, context.context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        assert has_operator_symbol?(triples, Atom.to_string(unquote(op)))
      end
    end

    test "dispatches div operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:div, [], [10, 3]}, context.context, [])

      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "div")
    end

    test "dispatches rem operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:rem, [], [10, 3]}, context.context, [])

      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "rem")
    end
  end

  describe "expression dispatch - special operators" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    test "dispatches pipe operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:|>, [], [1, 2]}, context.context, [])

      assert has_type?(triples, Core.PipeOperator)
      assert has_operator_symbol?(triples, "|>")
    end

    test "dispatches match operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:=, [], [{:x, [], nil}, 1]}, context.context, [])

      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")
    end

    test "dispatches string concat operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:<>, [], ["a", "b"]}, context.context, [])

      assert has_type?(triples, Core.StringConcatOperator)
      assert has_operator_symbol?(triples, "<>")
    end

    test "dispatches list ++ operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:++, [], [[1], [2]]}, context.context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "++")
    end

    test "dispatches list -- operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:--, [], [[1, 2], [1]]}, context.context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "--")
    end

    test "dispatches in operator", context do
      ExpressionBuilder.reset_counter("https://example.org/code#")

      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:in, [], [1, [1, 2]]}, context.context, [])

      assert has_type?(triples, Core.InOperator)
      assert has_operator_symbol?(triples, "in")
    end
  end

  describe "expression dispatch - literals" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    test "dispatches integer literal", context do
      assert {:ok, {_iri, triples}} = ExpressionBuilder.build(42, context.context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_integer_value?(triples, 42)
    end

    test "dispatches float literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(3.14, context.context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_float_value?(triples, 3.14)
    end

    test "dispatches string literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build("hello", context.context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_string_value?(triples, "hello")
    end

    test "dispatches atom literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(:foo, context.context, [])

      assert has_type?(triples, Core.AtomLiteral)
      assert has_atom_value?(triples, "foo")
    end

    test "dispatches true atom literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(true, context.context, [])

      assert has_type?(triples, Core.AtomLiteral)
      assert has_atom_value?(triples, "true")
    end

    test "dispatches false atom literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(false, context.context, [])

      assert has_type?(triples, Core.AtomLiteral)
      assert has_atom_value?(triples, "false")
    end

    test "dispatches nil atom literal", context do
      # nil is treated as "no expression" and returns :skip
      assert ExpressionBuilder.build(nil, context.context, []) == :skip
    end

    test "dispatches charlist literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(~c"hello", context.context, [])

      # Note: Charlists are treated as ListLiterals since we can't distinguish
      # between ~c"hello" and [104, 101, 108, 108, 111] at runtime
      assert has_type?(triples, Core.ListLiteral)
    end

    test "dispatches list literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build([1, 2, 3], context.context, [])

      assert has_type?(triples, Core.ListLiteral)
    end

    test "dispatches tuple literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({1, 2}, context.context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "dispatches map literal", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build(%{a: 1}, context.context, [])

      assert has_type?(triples, Core.MapLiteral)
    end
  end

  describe "expression dispatch - variables and patterns" do
    setup do
      [
        context:
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app.ex"
          )
      ]
    end

    test "dispatches variable", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:x, [], nil}, context.context, [])

      assert has_type?(triples, Core.Variable)
      assert has_name?(triples, "x")
    end

    test "dispatches wildcard pattern", context do
      assert {:ok, {_iri, triples}} =
               ExpressionBuilder.build({:_}, context.context, [])

      assert has_type?(triples, Core.WildcardPattern)
    end
  end

  # ===========================================================================
  # Counter Tests
  # ===========================================================================

  describe "counter management" do
    test "reset_counter sets counter to 0" do
      base_iri = "https://example.org/code#"

      # Use counter a few times
      ExpressionBuilder.next_counter(base_iri)
      ExpressionBuilder.next_counter(base_iri)

      # Reset
      ExpressionBuilder.reset_counter(base_iri)

      # Next counter should be 0
      assert ExpressionBuilder.next_counter(base_iri) == 0
    end

    test "next_counter increments on each call" do
      base_iri = "https://example.org/code#"

      ExpressionBuilder.reset_counter(base_iri)

      assert ExpressionBuilder.next_counter(base_iri) == 0
      assert ExpressionBuilder.next_counter(base_iri) == 1
      assert ExpressionBuilder.next_counter(base_iri) == 2
    end
  end

  # ===========================================================================
  # IRI Generation Tests
  # ===========================================================================

  describe "fresh_iri/2" do
    test "generates relative IRI with suffix" do
      parent = RDF.IRI.new("https://example.org/code#expr_0")

      assert ExpressionBuilder.fresh_iri(parent, "left") ==
               RDF.IRI.new("https://example.org/code#expr_0/left")

      assert ExpressionBuilder.fresh_iri(parent, "right") ==
               RDF.IRI.new("https://example.org/code#expr_0/right")
    end

    test "handles nested suffixes" do
      parent = RDF.IRI.new("https://example.org/code#expr_0/left")

      assert ExpressionBuilder.fresh_iri(parent, "operand") ==
               RDF.IRI.new("https://example.org/code#expr_0/left/operand")
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == RDF.type() and o == expected_type
    end)
  end

  defp has_operator_symbol?(triples, expected_symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == expected_symbol
    end)
  end

  defp has_integer_value?(triples, expected_value) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.integerValue() and RDF.Literal.value(o) == expected_value
    end)
  end

  defp has_float_value?(triples, expected_value) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.floatValue() and RDF.Literal.value(o) == expected_value
    end)
  end

  defp has_string_value?(triples, expected_value) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.stringValue() and RDF.Literal.value(o) == expected_value
    end)
  end

  defp has_atom_value?(triples, expected_value) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.atomValue() and RDF.Literal.value(o) == expected_value
    end)
  end

  defp has_name?(triples, expected_name) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.name() and RDF.Literal.value(o) == expected_name
    end)
  end
end
