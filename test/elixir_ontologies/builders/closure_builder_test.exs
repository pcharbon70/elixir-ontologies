defmodule ElixirOntologies.Builders.ClosureBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{ClosureBuilder, Context}
  alias ElixirOntologies.Extractors.{AnonymousFunction, Closure}
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

  # ===========================================================================
  # Closure-to-Scope Linking Tests
  # ===========================================================================

  describe "closure-to-scope linking" do
    test "scope chain building with module and function levels" do
      # Build a scope chain representing module -> function -> closure
      scopes = [
        %{type: :module, name: "MyModule", variables: [:config, :version]},
        %{type: :function, name: "my_func", variables: [:arg1, :arg2]},
        %{type: :closure, variables: []}
      ]

      chain = Closure.build_scope_chain(scopes)

      # Should have 3 scopes
      assert length(chain) == 3

      # First in chain is module (outermost), last is closure (innermost)
      assert hd(chain).type == :module
      assert hd(chain).level == 0

      innermost = List.last(chain)
      assert innermost.type == :closure
      assert innermost.level == 2
      assert innermost.parent != nil

      # Function scope is in the middle
      function_scope = Enum.at(chain, 1)
      assert function_scope.type == :function
      assert function_scope.name == "my_func"
      assert :arg1 in function_scope.variables
    end

    test "variable source identification from outer scope" do
      # Create a scope chain where y comes from function scope
      scopes = [
        %{type: :module, name: "MyModule", variables: [:config]},
        %{type: :function, name: "my_func", variables: [:y]},
        %{type: :closure, variables: [:x]}
      ]

      chain = Closure.build_scope_chain(scopes)

      # Analyze which scope provides the free variable :y
      {:ok, analysis} = Closure.analyze_closure_scope([:y], chain)

      # y should be found in the function scope
      assert Map.has_key?(analysis.variable_sources, :y)
      assert analysis.variable_sources[:y].type == :function
      assert analysis.variable_sources[:y].name == "my_func"
    end

    test "variable source identification from module scope" do
      # Create a scope chain where config comes from module scope
      scopes = [
        %{type: :module, name: "MyModule", variables: [:config]},
        %{type: :function, name: "my_func", variables: [:x]},
        %{type: :closure, variables: []}
      ]

      chain = Closure.build_scope_chain(scopes)

      {:ok, analysis} = Closure.analyze_closure_scope([:config], chain)

      # config should be found in the module scope
      assert Map.has_key?(analysis.variable_sources, :config)
      assert analysis.variable_sources[:config].type == :module
    end

    test "nested closure scope chain" do
      # Build a scope chain for nested closures: module -> function -> outer closure -> inner closure
      scopes = [
        %{type: :module, name: "MyModule", variables: [:module_var]},
        %{type: :function, name: "my_func", variables: [:func_var]},
        %{type: :closure, variables: [:outer_var]},
        %{type: :closure, variables: [:inner_var]}
      ]

      chain = Closure.build_scope_chain(scopes)

      # Should have 4 scopes
      assert length(chain) == 4

      # First is module (level 0), last is inner closure (level 3)
      assert hd(chain).type == :module
      assert hd(chain).level == 0

      innermost = List.last(chain)
      assert innermost.level == 3
      assert innermost.type == :closure
    end

    test "multiple free variables from different scopes" do
      scopes = [
        %{type: :module, name: "MyModule", variables: [:module_config]},
        %{type: :function, name: "my_func", variables: [:local_state]},
        %{type: :closure, variables: []}
      ]

      chain = Closure.build_scope_chain(scopes)

      # Both module_config and local_state are free variables
      {:ok, analysis} = Closure.analyze_closure_scope([:module_config, :local_state], chain)

      # module_config from module scope
      assert analysis.variable_sources[:module_config].type == :module

      # local_state from function scope
      assert analysis.variable_sources[:local_state].type == :function
    end

    test "closure builder generates triples consistent with scope analysis" do
      # Create a closure that captures from enclosing scope
      ast = quote do: fn -> outer_var + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      # Build closure triples
      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      # Verify capturesVariable triple exists for outer_var
      var_iri = ~I<https://example.org/code#MyApp/anon/0/capture/outer_var>
      assert {anon_iri, Core.capturesVariable(), var_iri} in triples

      # Also verify we can analyze the scope for this closure
      {:ok, closure_analysis} = Closure.analyze_closure(anon)
      assert closure_analysis.has_captures
      assert Enum.any?(closure_analysis.free_variables, fn fv -> fv.name == :outer_var end)
    end

    test "unfound variables not in variable_sources" do
      # Create a scope chain where the variable doesn't exist in any scope
      scopes = [
        %{type: :module, name: "MyModule", variables: []},
        %{type: :function, name: "my_func", variables: [:x]},
        %{type: :closure, variables: []}
      ]

      chain = Closure.build_scope_chain(scopes)

      # Try to find :unknown_var which doesn't exist in any scope
      {:ok, analysis} = Closure.analyze_closure_scope([:unknown_var], chain)

      # unknown_var should not be in variable_sources since it wasn't found
      refute Map.has_key?(analysis.variable_sources, :unknown_var)
    end
  end
end
