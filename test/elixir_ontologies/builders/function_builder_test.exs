defmodule ElixirOntologies.Builders.FunctionBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{FunctionBuilder, Context}
  alias ElixirOntologies.Extractors.Function
  alias ElixirOntologies.NS.Structure
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest FunctionBuilder

  describe "build/2 basic function" do
    test "builds minimal public function with required fields" do
      function_info = %Function{
        type: :function,
        name: :hello,
        arity: 0,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify IRI format
      assert to_string(function_iri) == "https://example.org/code#MyApp/hello/0"

      # Verify type triple
      assert {function_iri, RDF.type(), Structure.PublicFunction} in triples

      # Verify name triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.functionName() and
                   RDF.Literal.value(obj) == "hello"

               _ ->
                 false
             end)

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and
                   RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)

      # Should have at least type, name, arity, and belongsTo
      assert length(triples) >= 4
    end

    test "builds function with all optional fields populated" do
      function_info = %Function{
        type: :function,
        name: :get_user,
        arity: 2,
        min_arity: 1,
        visibility: :public,
        docstring: "Gets a user by ID",
        location: %SourceLocation{
          start_line: 10,
          start_column: 3,
          end_line: 15,
          end_column: 5
        },
        metadata: %{module: [:MyApp, :Users]}
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/users.ex")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should have many triples
      assert length(triples) > 6

      # Verify IRI
      assert to_string(function_iri) == "https://example.org/code#MyApp.Users/get_user/2"

      # Verify minArity present (different from arity)
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.minArity() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      # Verify docstring
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Gets a user by ID"

               _ ->
                 false
             end)
    end
  end

  describe "build/2 function types and visibility" do
    test "builds public function with PublicFunction type" do
      function_info = create_minimal_function(:function, :public, :test, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.PublicFunction} in triples
    end

    test "builds private function with PrivateFunction type" do
      function_info = create_minimal_function(:function, :private, :internal, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.PrivateFunction} in triples
    end

    test "builds public guard with GuardFunction type" do
      function_info = create_minimal_function(:guard, :public, :is_valid, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.GuardFunction} in triples
    end

    test "builds private guard with GuardFunction type" do
      function_info = create_minimal_function(:guard, :private, :is_internal, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.GuardFunction} in triples
    end

    test "builds delegated function with DelegatedFunction type" do
      function_info = %{
        create_minimal_function(:delegate, :public, :fetch, 1)
        | metadata: %{
            module: [:MyApp],
            delegates_to: {Enum, :fetch, 2}
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.DelegatedFunction} in triples
    end
  end

  describe "build/2 arity handling" do
    test "builds function with zero arity" do
      function_info = create_minimal_function(:function, :public, :hello, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify IRI includes /0
      assert to_string(function_iri) =~ "/hello/0"

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)
    end

    test "builds function with high arity" do
      function_info = create_minimal_function(:function, :public, :complex, 5)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify IRI includes /5
      assert to_string(function_iri) =~ "/complex/5"

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and RDF.Literal.value(obj) == 5

               _ ->
                 false
             end)
    end

    test "includes minArity when different from arity (default parameters)" do
      function_info = %Function{
        type: :function,
        name: :greet,
        arity: 2,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify arity = 2
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)

      # Verify minArity = 1
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.minArity() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)
    end

    test "does not include minArity when equal to arity" do
      function_info = %Function{
        type: :function,
        name: :test,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have minArity triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.minArity()
             end)
    end
  end

  describe "build/2 module relationships" do
    test "builds belongsTo relationship to module" do
      function_info = create_minimal_function(:function, :public, :test, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify belongsTo triple
      module_iri = ~I<https://example.org/code#MyApp>
      assert {function_iri, Structure.belongsTo(), module_iri} in triples
    end

    test "builds inverse containsFunction relationship for module" do
      function_info = create_minimal_function(:function, :public, :test, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify inverse containsFunction triple
      module_iri = ~I<https://example.org/code#MyApp>
      assert {module_iri, Structure.containsFunction(), function_iri} in triples
    end

    test "handles nested module in function belongsTo" do
      function_info = %{
        create_minimal_function(:function, :public, :get, 1)
        | metadata: %{module: [:MyApp, :Users, :Admin]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify belongsTo points to nested module
      module_iri = ~I<https://example.org/code#MyApp.Users.Admin>
      assert {function_iri, Structure.belongsTo(), module_iri} in triples
    end

    test "raises error for function without module context" do
      function_info = %{
        create_minimal_function(:function, :public, :orphan, 0)
        | metadata: %{module: nil}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      # Should raise error - functions must have module context
      assert_raise RuntimeError, ~r/has no module context/, fn ->
        FunctionBuilder.build(function_info, context)
      end
    end
  end

  describe "build/2 documentation handling" do
    test "builds docstring triple for function with documentation" do
      function_info = %{
        create_minimal_function(:function, :public, :documented, 1)
        | docstring: "This function is documented"
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify docstring triple exists
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "This function is documented"

               _ ->
                 false
             end)
    end

    test "does not build docstring triple for @doc false" do
      function_info = %{
        create_minimal_function(:function, :public, :hidden, 0)
        | docstring: false
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have docstring triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.docstring()
             end)
    end

    test "does not build docstring triple for nil documentation" do
      function_info = %{
        create_minimal_function(:function, :public, :undocumented, 0)
        | docstring: nil
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have docstring triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.docstring()
             end)
    end
  end

  describe "build/2 delegation" do
    test "builds delegatesTo triple for defdelegate" do
      function_info = %{
        create_minimal_function(:delegate, :public, :fetch, 2)
        | metadata: %{
            module: [:MyApp],
            delegates_to: {Enum, :fetch, 2}
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify delegatesTo triple exists
      target_iri = ~I<https://example.org/code#Enum/fetch/2>
      assert {function_iri, Structure.delegatesTo(), target_iri} in triples
    end

    test "builds delegatesTo for Elixir module delegation" do
      function_info = %{
        create_minimal_function(:delegate, :public, :map, 2)
        | metadata: %{
            module: [:MyApp, :Utils],
            delegates_to: {Enum, :map, 2}
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Target is Enum.map/2
      target_iri = ~I<https://example.org/code#Enum/map/2>
      assert {function_iri, Structure.delegatesTo(), target_iri} in triples
    end

    test "handles delegation to module with different arity" do
      function_info = %{
        create_minimal_function(:delegate, :public, :wrapper, 1)
        | metadata: %{
            module: [:MyApp],
            delegates_to: {OtherModule, :internal, 3}
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Delegation target has different arity
      target_iri = ~I<https://example.org/code#OtherModule/internal/3>
      assert {function_iri, Structure.delegatesTo(), target_iri} in triples
    end

    test "does not build delegatesTo for non-delegated functions" do
      function_info = create_minimal_function(:function, :public, :normal, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have delegatesTo triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.delegatesTo()
             end)
    end
  end

  describe "build/2 source location" do
    test "builds location triple when location and file path present" do
      function_info = %{
        create_minimal_function(:function, :public, :located, 0)
        | location: %SourceLocation{
            start_line: 42,
            start_column: 3,
            end_line: 50,
            end_column: 5
          }
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_app.ex")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify location triple exists
      assert Enum.any?(triples, fn
               {^function_iri, pred, _obj} ->
                 pred == ElixirOntologies.NS.Core.hasSourceLocation()

               _ ->
                 false
             end)
    end

    test "does not build location triple when location is nil" do
      function_info = %{
        create_minimal_function(:function, :public, :no_location, 0)
        | location: nil
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_app.ex")
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have location triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == ElixirOntologies.NS.Core.hasSourceLocation()
             end)
    end

    test "does not build location triple when file path is nil" do
      function_info = %{
        create_minimal_function(:function, :public, :no_file, 0)
        | location: %SourceLocation{
            start_line: 10,
            start_column: 1,
            end_line: 20,
            end_column: 3
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have location triple (no file path in context)
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == ElixirOntologies.NS.Core.hasSourceLocation()
             end)
    end
  end

  describe "build/2 function naming" do
    test "handles function with special characters (?) in name" do
      function_info = create_minimal_function(:function, :public, :valid?, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      # IRI should have URL-encoded ?
      assert to_string(function_iri) == "https://example.org/code#MyApp/valid%3F/1"
    end

    test "handles function with special characters (!) in name" do
      function_info = create_minimal_function(:function, :public, :create!, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      # IRI should have URL-encoded !
      assert to_string(function_iri) == "https://example.org/code#MyApp/create%21/1"
    end

    test "handles function with underscores in name" do
      function_info = create_minimal_function(:function, :public, :get_user_by_id, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      # Underscores should not be encoded
      assert to_string(function_iri) == "https://example.org/code#MyApp/get_user_by_id/1"
    end

    test "handles single-letter function names" do
      function_info = create_minimal_function(:function, :public, :x, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      assert to_string(function_iri) == "https://example.org/code#MyApp/x/1"
    end
  end

  describe "build/2 IRI generation" do
    test "generates correct IRI format for simple functions" do
      function_info = create_minimal_function(:function, :public, :hello, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      assert to_string(function_iri) == "https://example.org/code#MyApp/hello/0"
    end

    test "generates correct IRI format for nested module functions" do
      function_info = %{
        create_minimal_function(:function, :public, :get, 1)
        | metadata: %{module: [:MyApp, :Web, :Controllers, :UserController]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      assert to_string(function_iri) ==
               "https://example.org/code#MyApp.Web.Controllers.UserController/get/1"
    end

    test "generates stable IRIs across multiple builds" do
      function_info = create_minimal_function(:function, :public, :test, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {iri1, _} = FunctionBuilder.build(function_info, context)
      {iri2, _} = FunctionBuilder.build(function_info, context)

      # Same function should produce same IRI
      assert iri1 == iri2
    end
  end

  describe "build/2 triple validation" do
    test "generates all expected triples for complete function" do
      function_info = %Function{
        type: :function,
        name: :test,
        arity: 2,
        min_arity: 1,
        visibility: :public,
        docstring: "Test function",
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify all expected triple types
      assert {function_iri, RDF.type(), Structure.PublicFunction} in triples

      assert Enum.any?(triples, fn
               {^function_iri, pred, _} -> pred == Structure.functionName()
             end)

      assert Enum.any?(triples, fn
               {^function_iri, pred, _} -> pred == Structure.arity()
             end)

      assert Enum.any?(triples, fn
               {^function_iri, pred, _} -> pred == Structure.minArity()
             end)

      # Check for belongsTo triple (function -> module)
      module_iri = ~I<https://example.org/code#MyApp>
      assert {function_iri, Structure.belongsTo(), module_iri} in triples

      # Check for docstring triple
      assert Enum.any?(triples, fn
               {s, pred, _} when s == function_iri -> pred == Structure.docstring()
               _ -> false
             end)
    end

    test "generates no duplicate triples" do
      function_info = create_minimal_function(:function, :public, :test, 0)
      context = Context.new(base_iri: "https://example.org/code#")

      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify no duplicate triples
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "all triples have valid RDF structure" do
      function_info = create_minimal_function(:function, :public, :test, 1)
      context = Context.new(base_iri: "https://example.org/code#")

      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # All triples should be 3-tuples with valid RDF terms
      Enum.each(triples, fn triple ->
        assert is_tuple(triple)
        assert tuple_size(triple) == 3
        {s, p, o} = triple

        # Subject should be IRI or blank node
        assert is_struct(s, RDF.IRI) or is_struct(s, RDF.BlankNode)

        # Predicate should be IRI
        assert is_struct(p, RDF.IRI)

        # Object can be IRI, blank node, literal, or atom (namespace term)
        assert is_struct(o, RDF.IRI) or is_struct(o, RDF.BlankNode) or
                 is_struct(o, RDF.Literal) or is_atom(o)
      end)
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp create_minimal_function(type, visibility, name, arity) do
    %Function{
      type: type,
      name: name,
      arity: arity,
      min_arity: arity,
      visibility: visibility,
      docstring: nil,
      location: nil,
      metadata: %{module: [:MyApp]}
    }
  end
end
