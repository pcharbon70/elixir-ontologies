defmodule ElixirOntologies.Builders.ClosureBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{ClosureBuilder, Context}
  alias ElixirOntologies.Extractors.AnonymousFunction
  alias ElixirOntologies.NS.Core

  doctest ClosureBuilder

  describe "build_closure/3 with captures" do
    test "generates triples for single captured variable" do
      ast = quote do: fn -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      # Should have triples (capturesVariable, type, name)
      assert length(triples) == 3

      # Check capturesVariable triple exists
      assert Enum.any?(triples, fn
               {^anon_iri, pred, _obj} ->
                 pred == Core.capturesVariable()

               _ ->
                 false
             end)
    end

    test "generates variable IRI with correct format" do
      ast = quote do: fn -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      var_iri = ~I<https://example.org/code#MyApp/anon/0/capture/x>

      # Variable should have type core:Variable
      assert {var_iri, RDF.type(), Core.Variable} in triples

      # Variable should have name
      assert Enum.any?(triples, fn
               {^var_iri, pred, obj} ->
                 pred == Core.name() and
                   RDF.Literal.value(obj) == "x"

               _ ->
                 false
             end)
    end

    test "generates triples for multiple captured variables" do
      ast = quote do: fn -> x + y + z end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      # 3 variables * 3 triples each = 9 triples
      assert length(triples) == 9

      # Check all three capturesVariable triples exist
      capture_triples =
        Enum.filter(triples, fn
          {^anon_iri, pred, _} -> pred == Core.capturesVariable()
          _ -> false
        end)

      assert length(capture_triples) == 3

      # Check each variable has its own IRI
      var_x_iri = ~I<https://example.org/code#MyApp/anon/0/capture/x>
      var_y_iri = ~I<https://example.org/code#MyApp/anon/0/capture/y>
      var_z_iri = ~I<https://example.org/code#MyApp/anon/0/capture/z>

      assert {anon_iri, Core.capturesVariable(), var_x_iri} in triples
      assert {anon_iri, Core.capturesVariable(), var_y_iri} in triples
      assert {anon_iri, Core.capturesVariable(), var_z_iri} in triples
    end

    test "captures variable used in nested expression" do
      ast = quote do: fn a -> a + outer_var * 2 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      # Only outer_var should be captured (a is bound by parameter)
      assert length(triples) == 3

      var_iri = ~I<https://example.org/code#MyApp/anon/0/capture/outer_var>
      assert {anon_iri, Core.capturesVariable(), var_iri} in triples
    end
  end

  describe "build_closure/3 without captures" do
    test "returns empty list for function with no captures" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      assert triples == []
    end

    test "returns empty list for function with only bound variables" do
      ast = quote do: fn x, y -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      assert triples == []
    end

    test "returns empty list for zero-arity function with no variables" do
      ast = quote do: fn -> 42 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      assert triples == []
    end
  end

  describe "is_closure?/1" do
    test "returns true for function with captures" do
      ast = quote do: fn -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      assert ClosureBuilder.is_closure?(anon) == true
    end

    test "returns false for function without captures" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      assert ClosureBuilder.is_closure?(anon) == false
    end

    test "returns false for simple literal function" do
      ast = quote do: fn -> :ok end
      {:ok, anon} = AnonymousFunction.extract(ast)

      assert ClosureBuilder.is_closure?(anon) == false
    end

    test "returns true for multi-clause with captures" do
      ast =
        quote do
          fn
            0 -> captured_var
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      assert ClosureBuilder.is_closure?(anon) == true
    end
  end

  describe "variable name triples" do
    test "generates correct name for simple variable" do
      ast = quote do: fn -> my_var end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      var_iri = ~I<https://example.org/code#MyApp/anon/0/capture/my_var>

      # Check variable name
      assert Enum.any?(triples, fn
               {^var_iri, pred, obj} ->
                 pred == Core.name() and
                   RDF.Literal.value(obj) == "my_var"

               _ ->
                 false
             end)
    end

    test "handles underscore-prefixed variables" do
      ast = quote do: fn -> _unused end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      var_iri = ~I<https://example.org/code#MyApp/anon/0/capture/_unused>

      assert {anon_iri, Core.capturesVariable(), var_iri} in triples
    end
  end
end
