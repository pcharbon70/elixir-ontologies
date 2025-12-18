defmodule ElixirOntologies.Builders.ModuleBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{ModuleBuilder, Context}
  alias ElixirOntologies.Extractors.Module
  alias ElixirOntologies.NS.{Structure, Core}
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest ModuleBuilder

  describe "build/2 basic module" do
    test "builds minimal module with required fields" do
      module_info = %Module{
        type: :module,
        name: [:MyApp],
        docstring: nil,
        aliases: [],
        imports: [],
        requires: [],
        uses: [],
        functions: [],
        macros: [],
        types: [],
        location: nil,
        metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify IRI format
      assert to_string(module_iri) == "https://example.org/code#MyApp"

      # Verify type triple
      assert {module_iri, RDF.type(), Structure.Module} in triples

      # Verify name triple
      assert Enum.any?(triples, fn
               {^module_iri, pred, obj} ->
                 pred == Structure.moduleName() and
                   RDF.Literal.value(obj) == "MyApp"

               _ ->
                 false
             end)

      # Should have at least type and name
      assert length(triples) >= 2
    end

    test "builds module with all optional fields populated" do
      module_info = %Module{
        type: :module,
        name: [:MyApp, :Users],
        docstring: "User management module",
        aliases: [%{module: [:MyApp, :Accounts], as: :A, location: nil}],
        imports: [%{module: [:Ecto, :Query], only: nil, except: nil, location: nil}],
        requires: [%{module: :Logger, as: nil, location: nil}],
        uses: [%{module: [:GenServer], opts: [], location: nil}],
        functions: [%{name: :list, arity: 0, visibility: :public}],
        macros: [%{name: :ensure_user, arity: 1, visibility: :public}],
        types: [%{name: :t, arity: 0, visibility: :public}],
        location: %SourceLocation{
          start_line: 1,
          start_column: 1,
          end_line: 50,
          end_column: 3
        },
        metadata: %{parent_module: nil, has_moduledoc: true, nested_modules: []}
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/users.ex")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should have many triples
      assert length(triples) > 10

      # Verify IRI
      assert to_string(module_iri) == "https://example.org/code#MyApp.Users"

      # Verify type
      assert {module_iri, RDF.type(), Structure.Module} in triples

      # Verify name
      assert Enum.any?(triples, fn
               {^module_iri, pred, obj} ->
                 pred == Structure.moduleName() and RDF.Literal.value(obj) == "MyApp.Users"

               _ ->
                 false
             end)

      # Verify docstring
      assert Enum.any?(triples, fn
               {^module_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "User management module"

               _ ->
                 false
             end)
    end
  end

  describe "build/2 module types" do
    test "builds regular module with Module type" do
      module_info = create_minimal_module(:module, [:MyApp])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      assert {module_iri, RDF.type(), Structure.Module} in triples
    end

    test "builds nested module with NestedModule type" do
      module_info = create_minimal_module(:nested_module, [:MyApp, :Users, :Admin])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      assert {module_iri, RDF.type(), Structure.NestedModule} in triples
    end
  end

  describe "build/2 documentation handling" do
    test "builds docstring triple for module with documentation" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | docstring: "This is a documented module"
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify docstring triple exists
      assert Enum.any?(triples, fn
               {^module_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "This is a documented module"

               _ ->
                 false
             end)
    end

    test "does not build docstring triple for @moduledoc false" do
      module_info = %{create_minimal_module(:module, [:MyApp]) | docstring: false}

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should not have docstring triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.docstring()
             end)
    end

    test "does not build docstring triple for nil documentation" do
      module_info = %{create_minimal_module(:module, [:MyApp]) | docstring: nil}

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should not have docstring triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.docstring()
             end)
    end
  end

  describe "build/2 nested module relationships" do
    test "builds nested module with parent reference" do
      module_info = %{
        create_minimal_module(:nested_module, [:MyApp, :Users, :Admin])
        | metadata: %{
            parent_module: [:MyApp, :Users],
            has_moduledoc: false,
            nested_modules: []
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify NestedModule type
      assert {module_iri, RDF.type(), Structure.NestedModule} in triples

      # Verify parent relationship exists
      parent_iri = ~I<https://example.org/code#MyApp.Users>
      assert {module_iri, Structure.parentModule(), parent_iri} in triples

      # Verify inverse relationship
      assert {parent_iri, Structure.hasNestedModule(), module_iri} in triples
    end

    test "builds multiple nested modules under same parent" do
      admin_module = %{
        create_minimal_module(:nested_module, [:MyApp, :Users, :Admin])
        | metadata: %{
            parent_module: [:MyApp, :Users],
            has_moduledoc: false,
            nested_modules: []
          }
      }

      guest_module = %{
        create_minimal_module(:nested_module, [:MyApp, :Users, :Guest])
        | metadata: %{
            parent_module: [:MyApp, :Users],
            has_moduledoc: false,
            nested_modules: []
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {admin_iri, admin_triples} = ModuleBuilder.build(admin_module, context)
      {guest_iri, guest_triples} = ModuleBuilder.build(guest_module, context)

      parent_iri = ~I<https://example.org/code#MyApp.Users>

      # Both should reference the same parent
      assert {admin_iri, Structure.parentModule(), parent_iri} in admin_triples
      assert {guest_iri, Structure.parentModule(), parent_iri} in guest_triples

      # Parent should have both nested modules
      assert {parent_iri, Structure.hasNestedModule(), admin_iri} in admin_triples
      assert {parent_iri, Structure.hasNestedModule(), guest_iri} in guest_triples
    end

    test "handles deeply nested modules" do
      module_info = %{
        create_minimal_module(:nested_module, [:MyApp, :Users, :Admin, :Permissions])
        | metadata: %{
            parent_module: [:MyApp, :Users, :Admin],
            has_moduledoc: false,
            nested_modules: []
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify IRI for deeply nested module
      assert to_string(module_iri) == "https://example.org/code#MyApp.Users.Admin.Permissions"

      # Verify parent relationship
      parent_iri = ~I<https://example.org/code#MyApp.Users.Admin>
      assert {module_iri, Structure.parentModule(), parent_iri} in triples
    end
  end

  describe "build/2 module directives" do
    test "builds alias relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | aliases: [
            %{module: [:MyApp, :Users], as: :U, location: nil},
            %{module: [:MyApp, :Accounts], as: nil, location: nil}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify alias triples
      users_iri = ~I<https://example.org/code#MyApp.Users>
      accounts_iri = ~I<https://example.org/code#MyApp.Accounts>

      assert {module_iri, Structure.aliasesModule(), users_iri} in triples
      assert {module_iri, Structure.aliasesModule(), accounts_iri} in triples
    end

    test "builds import relationships with Elixir modules" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | imports: [
            %{module: [:Ecto, :Query], only: nil, except: nil, location: nil},
            %{module: [:Enum], only: [map: 2], except: nil, location: nil}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify import triples
      query_iri = ~I<https://example.org/code#Ecto.Query>
      enum_iri = ~I<https://example.org/code#Enum>

      assert {module_iri, Structure.importsFrom(), query_iri} in triples
      assert {module_iri, Structure.importsFrom(), enum_iri} in triples
    end

    test "builds import relationships with Erlang modules" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | imports: [
            %{module: :crypto, only: nil, except: nil, location: nil}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify Erlang module import
      crypto_iri = ~I<https://example.org/code#crypto>

      assert {module_iri, Structure.importsFrom(), crypto_iri} in triples
    end

    test "builds require relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | requires: [
            %{module: :Logger, as: nil, location: nil},
            %{module: [:MyApp, :CustomMacros], as: :CM, location: nil}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify require triples
      logger_iri = ~I<https://example.org/code#Logger>
      custom_iri = ~I<https://example.org/code#MyApp.CustomMacros>

      assert {module_iri, Structure.requiresModule(), logger_iri} in triples
      assert {module_iri, Structure.requiresModule(), custom_iri} in triples
    end

    test "builds use relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | uses: [
            %{module: [:GenServer], opts: [], location: nil},
            %{module: [:Phoenix, :Controller], opts: [namespace: MyApp.Web], location: nil}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify use triples
      genserver_iri = ~I<https://example.org/code#GenServer>
      controller_iri = ~I<https://example.org/code#Phoenix.Controller>

      assert {module_iri, Structure.usesModule(), genserver_iri} in triples
      assert {module_iri, Structure.usesModule(), controller_iri} in triples
    end

    test "builds module with all directive types" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | aliases: [%{module: [:MyApp, :Users], as: :U, location: nil}],
          imports: [%{module: [:Enum], only: nil, except: nil, location: nil}],
          requires: [%{module: :Logger, as: nil, location: nil}],
          uses: [%{module: [:GenServer], opts: [], location: nil}]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify all directive types present
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.aliasesModule() end)
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.importsFrom() end)
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.requiresModule() end)
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.usesModule() end)
    end
  end

  describe "build/2 containment relationships" do
    test "builds function containment relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | functions: [
            %{name: :hello, arity: 0, visibility: :public},
            %{name: :greet, arity: 1, visibility: :public}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify containsFunction triples
      hello_iri = ~I<https://example.org/code#MyApp/hello/0>
      greet_iri = ~I<https://example.org/code#MyApp/greet/1>

      assert {module_iri, Structure.containsFunction(), hello_iri} in triples
      assert {module_iri, Structure.containsFunction(), greet_iri} in triples
    end

    test "builds macro containment relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | macros: [
            %{name: :ensure_loaded, arity: 1, visibility: :public},
            %{name: :validate, arity: 2, visibility: :public}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify containsMacro triples
      ensure_iri = ~I<https://example.org/code#MyApp/ensure_loaded/1>
      validate_iri = ~I<https://example.org/code#MyApp/validate/2>

      assert {module_iri, Structure.containsMacro(), ensure_iri} in triples
      assert {module_iri, Structure.containsMacro(), validate_iri} in triples
    end

    test "builds type containment relationships" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | types: [
            %{name: :t, arity: 0, visibility: :public},
            %{name: :option, arity: 1, visibility: :public}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify containsType triples
      t_iri = ~I<https://example.org/code#MyApp/t/0>
      option_iri = ~I<https://example.org/code#MyApp/option/1>

      assert {module_iri, Structure.containsType(), t_iri} in triples
      assert {module_iri, Structure.containsType(), option_iri} in triples
    end

    test "builds module containing all three types" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | functions: [%{name: :hello, arity: 0, visibility: :public}],
          macros: [%{name: :ensure_loaded, arity: 1, visibility: :public}],
          types: [%{name: :t, arity: 0, visibility: :public}]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify all containment types
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.containsFunction() end)
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.containsMacro() end)
      assert Enum.any?(triples, fn {_, p, _} -> p == Structure.containsType() end)
    end
  end

  describe "build/2 source location" do
    test "builds location triple when location and file path present" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | location: %SourceLocation{
            start_line: 10,
            start_column: 1,
            end_line: 50,
            end_column: 3
          }
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_app.ex")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify location triple exists
      assert Enum.any?(triples, fn
               {^module_iri, pred, _obj} ->
                 pred == Core.hasSourceLocation()

               _ ->
                 false
             end)
    end

    test "does not build location triple when location is nil" do
      module_info = %{create_minimal_module(:module, [:MyApp]) | location: nil}

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_app.ex")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should not have location triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Core.hasSourceLocation()
             end)
    end

    test "does not build location triple when file path is nil" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | location: %SourceLocation{
            start_line: 10,
            start_column: 1,
            end_line: 50,
            end_column: 3
          }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should not have location triple (no file path in context)
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Core.hasSourceLocation()
             end)
    end
  end

  describe "build/2 edge cases" do
    test "handles module with special characters in name" do
      # Note: Elixir module names shouldn't have special chars, but test escaping
      module_info = create_minimal_module(:module, [:MyApp, :Foo_Bar])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, _triples} = ModuleBuilder.build(module_info, context)

      # IRI should handle underscore properly
      assert to_string(module_iri) == "https://example.org/code#MyApp.Foo_Bar"
    end

    test "handles empty module with no functions, directives, or types" do
      module_info = create_minimal_module(:module, [:Empty])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should still have type and name triples
      assert length(triples) >= 2
      assert {module_iri, RDF.type(), Structure.Module} in triples
    end

    test "handles module with single-atom name" do
      module_info = create_minimal_module(:module, [:SingleName])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, _triples} = ModuleBuilder.build(module_info, context)

      assert to_string(module_iri) == "https://example.org/code#SingleName"
    end
  end

  describe "build/2 IRI generation" do
    test "generates correct IRI format for simple modules" do
      module_info = create_minimal_module(:module, [:MyApp])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, _triples} = ModuleBuilder.build(module_info, context)

      assert to_string(module_iri) == "https://example.org/code#MyApp"
    end

    test "generates correct IRI format for deeply nested modules" do
      module_info = create_minimal_module(:nested_module, [:MyApp, :Web, :Controllers, :UserController])
      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, _triples} = ModuleBuilder.build(module_info, context)

      assert to_string(module_iri) ==
               "https://example.org/code#MyApp.Web.Controllers.UserController"
    end

    test "generates stable IRIs across multiple builds" do
      module_info = create_minimal_module(:module, [:MyApp, :Users])
      context = Context.new(base_iri: "https://example.org/code#")

      {iri1, _} = ModuleBuilder.build(module_info, context)
      {iri2, _} = ModuleBuilder.build(module_info, context)

      # Same module should produce same IRI
      assert iri1 == iri2
    end
  end

  describe "build/2 triple validation" do
    test "generates all expected triples for complete module" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | docstring: "Test module",
          aliases: [%{module: [:Foo], as: nil, location: nil}],
          functions: [%{name: :test, arity: 0, visibility: :public}]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify all expected triple types
      assert {module_iri, RDF.type(), Structure.Module} in triples

      assert Enum.any?(triples, fn
               {^module_iri, pred, _} -> pred == Structure.moduleName()
             end)

      assert Enum.any?(triples, fn
               {^module_iri, pred, _} -> pred == Structure.docstring()
             end)

      assert Enum.any?(triples, fn
               {^module_iri, pred, _} -> pred == Structure.aliasesModule()
             end)

      assert Enum.any?(triples, fn
               {^module_iri, pred, _} -> pred == Structure.containsFunction()
             end)
    end

    test "generates no duplicate triples" do
      module_info = %{
        create_minimal_module(:module, [:MyApp])
        | functions: [
            %{name: :test, arity: 0, visibility: :public},
            %{name: :test, arity: 1, visibility: :public}
          ]
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify no duplicate triples
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "all triples have valid RDF structure" do
      module_info = create_minimal_module(:module, [:MyApp])
      context = Context.new(base_iri: "https://example.org/code#")

      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

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

  defp create_minimal_module(type, name) do
    %Module{
      type: type,
      name: name,
      docstring: nil,
      aliases: [],
      imports: [],
      requires: [],
      uses: [],
      functions: [],
      macros: [],
      types: [],
      location: nil,
      metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
    }
  end
end
