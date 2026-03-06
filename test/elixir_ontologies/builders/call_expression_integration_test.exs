defmodule ElixirOntologies.Builders.CallExpressionIntegrationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder}
  alias ElixirOntologies.NS.Core

  @moduledoc """
  Integration tests for call and reference expression extraction.

  These tests verify that:
  1. All call types are extracted correctly
  2. Complex nested scenarios work
  3. SPARQL queries can find and navigate calls
  4. Light mode and full mode behave correctly
  """

  describe "call extraction integration tests" do
    test "complete remote call extraction with arguments" do
      context = full_mode_context()

      # AST for String.to_integer("42", 10)
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [], ["42", 10]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify RemoteCall type
      assert has_type?(triples, Core.RemoteCall)

      # Verify moduleName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.moduleName() and RDF.Literal.value(o) == "String"
             end)

      # Verify functionName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.functionName() and RDF.Literal.value(o) == "to_integer"
             end)

      # Verify arity
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.arity() and RDF.Literal.value(o) == 2
             end)

      # Verify refersToModule
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.refersToModule()
             end)

      # Verify refersToFunction
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.refersToFunction()
             end)

      # Verify arguments are extracted
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasArgument()
             end) == true
    end

    test "local call within module context" do
      context = full_mode_context()

      # AST for process_item(item)
      ast = {:process_item, [], [{:item, [], Elixir}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify LocalCall type
      assert has_type?(triples, Core.LocalCall)

      # Verify functionName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.functionName() and
                 RDF.Literal.value(o) == "process_item"
             end)

      # Verify arity
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.arity() and RDF.Literal.value(o) == 1
             end)

      # Verify refersToFunction exists (even if placeholder)
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.refersToFunction()
             end)
    end

    test "anonymous function call extraction" do
      context = full_mode_context()

      # AST for callback.(result)
      ast = {{:., [], [{:callback, [], Elixir}]}, [], [{:result, [], Elixir}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify AnonymousFunctionCall type
      assert has_type?(triples, Core.AnonymousFunctionCall)

      # Verify hasFunctionExpression
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasFunctionExpression()
             end)

      # Verify hasArgument (callback was called with 1 argument)
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasArgument()
             end)
    end

    test "capture operator extraction for function reference" do
      context = full_mode_context()

      # AST for &Enum.map/2
      function_ref = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}
      ast = {:&, [], [{:/, [], [function_ref, 2]}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify FunctionReference type
      assert has_type?(triples, Core.FunctionReference)

      # Verify moduleName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.moduleName() and RDF.Literal.value(o) == "Enum"
             end)

      # Verify functionName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.functionName() and RDF.Literal.value(o) == "map"
             end)

      # Verify arity
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.arity() and RDF.Literal.value(o) == 2
             end)

      # Verify refersToFunction
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.refersToFunction()
             end)
    end

    test "module reference extraction" do
      context = full_mode_context()

      # AST for MyApp.Users
      ast = {:__aliases__, [], [:"MyApp.Users"]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify ModuleReference type
      assert has_type?(triples, Core.ModuleReference)

      # Verify moduleName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.moduleName() and RDF.Literal.value(o) == "MyApp.Users"
             end)

      # Verify refersToModule
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.refersToModule()
             end)
    end

    test "nested call scenario" do
      context = full_mode_context()

      # AST for String.upcase(Integer.to_string(123))
      inner_call = {{:., [], [{:__aliases__, [], [:Integer]}, :to_string]}, [], [123]}
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [inner_call]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Verify outer call is RemoteCall
      assert has_type?(triples, Core.RemoteCall)

      # Verify inner call (as argument) is also RemoteCall
      arg_iri = ExpressionBuilder.fresh_iri(expr_iri, "arg-0")

      assert Enum.any?(triples, fn {s, p, o} ->
               s == arg_iri and p == RDF.type() and o == Core.RemoteCall
             end)

      # Verify nested argument's argument
      inner_arg_iri = ExpressionBuilder.fresh_iri(arg_iri, "arg-0")

      assert Enum.any?(triples, fn {s, p, o} ->
               s == inner_arg_iri and p == RDF.type() and o == Core.IntegerLiteral
             end)
    end
  end

  describe "SPARQL query simulation tests" do
    test "find all RemoteCall expressions" do
      context = full_mode_context()

      # Create a mix of different call types
      remote_ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      local_ast = {:process, [], [{:x, [], Elixir}]}

      {:ok, {remote_iri, remote_triples, _}} = ExpressionBuilder.build(remote_ast, context, [])
      {:ok, {_local_iri, local_triples, _}} = ExpressionBuilder.build(local_ast, context, [])

      # Find all RemoteCall triples
      remote_calls =
        (remote_triples ++ local_triples)
        |> Enum.filter(fn {_s, p, o} ->
          p == RDF.type() and o == Core.RemoteCall
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      assert length(remote_calls) == 1
      assert Enum.member?(remote_calls, remote_iri)
    end

    test "find calls by module name" do
      context = full_mode_context()

      # AST for String.upcase("hello")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Find calls with moduleName = "String"
      string_calls =
        Enum.filter(triples, fn {_s, p, o} ->
          p == Core.moduleName() and RDF.Literal.value(o) == "String"
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      assert length(string_calls) == 1
      assert Enum.member?(string_calls, expr_iri)
    end

    test "find calls by function name" do
      context = full_mode_context()

      # AST for String.upcase("hello")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Find calls with functionName = "upcase"
      upcase_calls =
        Enum.filter(triples, fn {_s, p, o} ->
          p == Core.functionName() and RDF.Literal.value(o) == "upcase"
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      assert length(upcase_calls) == 1
      assert Enum.member?(upcase_calls, expr_iri)
    end

    test "find calls by arity" do
      context = full_mode_context()

      # AST for String.to_integer("42", 10)
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [], ["42", 10]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Find calls with arity = 2
      arity_2_calls =
        Enum.filter(triples, fn {_s, p, o} ->
          p == Core.arity() and RDF.Literal.value(o) == 2
        end)
        |> Enum.map(fn {s, _p, _o} -> s end)

      assert length(arity_2_calls) == 1
      assert Enum.member?(arity_2_calls, expr_iri)
    end

    test "navigate call arguments" do
      context = full_mode_context()

      # AST for calc(a, b, c)
      ast = {:calc, [], [{:a, [], Elixir}, {:b, [], Elixir}, {:c, [], Elixir}]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Find all hasArgument triples
      arguments =
        Enum.filter(triples, fn {s, p, _o} ->
          s == expr_iri and p == Core.hasArgument()
        end)
        |> Enum.map(fn {_s, _p, o} -> o end)

      # Should have 3 arguments
      assert length(arguments) == 3

      # Each argument should be a Variable
      argument_types =
        Enum.map(arguments, fn arg_iri ->
          Enum.find(triples, fn {s, p, _o} ->
            s == arg_iri and p == RDF.type()
          end)
        end)

      assert Enum.all?(argument_types, fn {_s, _p, o} -> o == Core.Variable end)
    end
  end

  describe "mode behavior tests" do
    test "light mode returns skip for expressions" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false},
          file_path: "lib/my_app/users.ex"
        )

      # AST for String.upcase("hello")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      # Light mode should return :skip
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "full mode returns complete expression tree" do
      context = full_mode_context()

      # AST for String.upcase("hello")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Full mode should return triples
      assert is_list(triples)
      assert length(triples) > 0

      # Should have RemoteCall type
      assert has_type?(triples, Core.RemoteCall)

      # Should have moduleName
      assert Enum.any?(triples, fn {s, p, o} ->
               s == expr_iri and p == Core.moduleName()
             end)

      # Should have argument expression
      assert Enum.any?(triples, fn {s, p, _o} ->
               s == expr_iri and p == Core.hasArgument()
             end)
    end

    test "full mode handles dependency files correctly" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      # AST for String.upcase("hello")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      # Dependency files should return :skip even with include_expressions: true
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp full_mode_context do
    Context.new(
      base_iri: "https://example.org/code#",
      config: %{include_expressions: true},
      file_path: "lib/my_app/users.ex"
    )
    |> Context.with_expression_counter()
  end

  defp has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == expected_type end)
  end
end
