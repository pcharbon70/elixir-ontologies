defmodule ElixirOntologies.Builders.TypeSystemBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.TypeSystemBuilder

  alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
  alias ElixirOntologies.Extractors.{TypeDefinition, FunctionSpec}
  alias ElixirOntologies.NS.Structure

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "TestModule")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_function_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "TestModule")
    function_name = Keyword.get(opts, :function_name, "test_func")
    arity = Keyword.get(opts, :arity, 0)
    RDF.iri("#{base_iri}#{module_name}/#{function_name}/#{arity}")
  end

  defp build_test_type_definition(opts \\ []) do
    %TypeDefinition{
      name: Keyword.get(opts, :name, :t),
      arity: Keyword.get(opts, :arity, 0),
      visibility: Keyword.get(opts, :visibility, :public),
      parameters: Keyword.get(opts, :parameters, []),
      expression: Keyword.get(opts, :expression, :any),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_function_spec(opts \\ []) do
    %FunctionSpec{
      name: Keyword.get(opts, :name, :test),
      arity: Keyword.get(opts, :arity, 0),
      parameter_types: Keyword.get(opts, :parameter_types, []),
      return_type: Keyword.get(opts, :return_type, :any),
      type_constraints: Keyword.get(opts, :type_constraints, %{}),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Type Definition Building Tests
  # ===========================================================================

  describe "build_type_definition/3 - basic building" do
    test "builds minimal public type with arity 0" do
      type_def = build_test_type_definition(name: :user_t, visibility: :public, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "User")

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify IRI pattern: Module/type/name/arity
      assert to_string(type_iri) == "https://example.org/code#User/type/user_t/0"

      # Verify type class
      assert {type_iri, RDF.type(), Structure.PublicType} in triples

      # Verify containsType triple
      assert {module_iri, Structure.containsType(), type_iri} in triples

      # Verify typeName
      assert Enum.any?(triples, fn
               {^type_iri, pred, obj} ->
                 pred == Structure.typeName() and is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "user_t"

               _ ->
                 false
             end)

      # Verify typeArity
      assert Enum.any?(triples, fn
               {^type_iri, pred, obj} ->
                 pred == Structure.typeArity() and is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)
    end

    test "builds private type (@typep)" do
      type_def = build_test_type_definition(name: :internal, visibility: :private)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify private type class
      assert {type_iri, RDF.type(), Structure.PrivateType} in triples
    end

    test "builds opaque type (@opaque)" do
      type_def = build_test_type_definition(name: :secret, visibility: :opaque)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify opaque type class
      assert {type_iri, RDF.type(), Structure.OpaqueType} in triples
    end

    test "builds parameterized type with arity 1" do
      type_def = build_test_type_definition(name: :my_list, arity: 1, parameters: [:element])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify IRI includes arity
      assert to_string(type_iri) == "https://example.org/code#TestModule/type/my_list/1"

      # Verify typeArity is 1
      assert Enum.any?(triples, fn
               {^type_iri, pred, obj} ->
                 pred == Structure.typeArity() and is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      # Verify hasTypeVariable triple exists
      assert Enum.any?(triples, fn
               {^type_iri, pred, _} ->
                 pred == Structure.hasTypeVariable()

               _ ->
                 false
             end)
    end

    test "builds parameterized type with multiple parameters" do
      type_def = build_test_type_definition(name: :pair, arity: 2, parameters: [:a, :b])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Count type variables
      type_var_count =
        Enum.count(triples, fn
          {^type_iri, pred, _} ->
            pred == Structure.hasTypeVariable()

          _ ->
            false
        end)

      assert type_var_count == 2
    end
  end

  describe "build_type_definition/3 - IRI generation" do
    test "generates correct IRI pattern" do
      type_def = build_test_type_definition(name: :user_t, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Users")

      {type_iri, _triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      assert to_string(type_iri) == "https://example.org/code#MyApp.Users/type/user_t/0"
    end

    test "escapes special characters in type names" do
      type_def = build_test_type_definition(name: :t?, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, _triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # ? should be URL-encoded as %3F
      assert to_string(type_iri) == "https://example.org/code#TestModule/type/t%3F/0"
    end

    test "different types have different IRIs" do
      type_def1 = build_test_type_definition(name: :t1, arity: 0)
      type_def2 = build_test_type_definition(name: :t2, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri1, _} = TypeSystemBuilder.build_type_definition(type_def1, module_iri, context)
      {type_iri2, _} = TypeSystemBuilder.build_type_definition(type_def2, module_iri, context)

      assert type_iri1 != type_iri2
    end

    test "same name different arity produces different IRIs" do
      type_def1 = build_test_type_definition(name: :t, arity: 0, parameters: [])
      type_def2 = build_test_type_definition(name: :t, arity: 1, parameters: [:a])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri1, _} = TypeSystemBuilder.build_type_definition(type_def1, module_iri, context)
      {type_iri2, _} = TypeSystemBuilder.build_type_definition(type_def2, module_iri, context)

      assert type_iri1 != type_iri2
      assert to_string(type_iri1) =~ ~r/\/type\/t\/0$/
      assert to_string(type_iri2) =~ ~r/\/type\/t\/1$/
    end
  end

  describe "build_type_definition/3 - triple validation" do
    test "all expected triples for public type" do
      type_def = build_test_type_definition(name: :user, visibility: :public, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Expected triples:
      # 1. rdf:type struct:PublicType
      assert {type_iri, RDF.type(), Structure.PublicType} in triples

      # 2. module struct:containsType type
      assert {module_iri, Structure.containsType(), type_iri} in triples

      # 3. struct:typeName
      assert Enum.any?(triples, fn
               {^type_iri, pred, _} -> pred == Structure.typeName()
               _ -> false
             end)

      # 4. struct:typeArity
      assert Enum.any?(triples, fn
               {^type_iri, pred, _} -> pred == Structure.typeArity()
               _ -> false
             end)
    end

    test "no duplicate triples" do
      type_def = build_test_type_definition()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "type with no parameters has no type variables" do
      type_def = build_test_type_definition(arity: 0, parameters: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Should not have hasTypeVariable triples
      has_type_var =
        Enum.any?(triples, fn
          {^type_iri, pred, _} -> pred == Structure.hasTypeVariable()
          _ -> false
        end)

      refute has_type_var
    end
  end

  # ===========================================================================
  # Function Spec Building Tests
  # ===========================================================================

  describe "build_function_spec/3 - basic building" do
    test "builds minimal spec with no parameters" do
      func_spec = build_test_function_spec(name: :now, arity: 0, parameter_types: [])
      context = build_test_context()
      function_iri = build_test_function_iri(function_name: "now", arity: 0)

      {spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Spec IRI should be same as function IRI
      assert spec_iri == function_iri

      # Verify type triple
      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in triples

      # Verify hasSpec triple
      assert {function_iri, Structure.hasSpec(), spec_iri} in triples
    end

    test "builds spec with single parameter" do
      func_spec =
        build_test_function_spec(
          name: :inc,
          arity: 1,
          parameter_types: [{:integer, [], []}]
        )

      context = build_test_context()
      function_iri = build_test_function_iri(function_name: "inc", arity: 1)

      {spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Verify spec type
      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in triples
    end

    test "builds spec with multiple parameters" do
      func_spec =
        build_test_function_spec(
          name: :add,
          arity: 2,
          parameter_types: [{:integer, [], []}, {:integer, [], []}]
        )

      context = build_test_context()
      function_iri = build_test_function_iri(function_name: "add", arity: 2)

      {spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Verify spec exists
      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in triples
    end
  end

  describe "build_function_spec/3 - IRI reuse" do
    test "spec IRI is same as function IRI" do
      func_spec = build_test_function_spec()
      context = build_test_context()
      function_iri = build_test_function_iri()

      {spec_iri, _triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      assert spec_iri == function_iri
      assert to_string(spec_iri) == to_string(function_iri)
    end
  end

  describe "build_function_spec/3 - triple validation" do
    test "all expected triples for basic spec" do
      func_spec = build_test_function_spec(name: :test, arity: 0)
      context = build_test_context()
      function_iri = build_test_function_iri()

      {spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Expected triples:
      # 1. rdf:type struct:FunctionSpec
      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in triples

      # 2. function struct:hasSpec spec
      assert {function_iri, Structure.hasSpec(), spec_iri} in triples
    end

    test "no duplicate triples" do
      func_spec = build_test_function_spec()
      context = build_test_context()
      function_iri = build_test_function_iri()

      {_spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end
  end

  # ===========================================================================
  # Edge Cases and Error Handling
  # ===========================================================================

  describe "edge cases" do
    test "type with zero-length name still works" do
      # Elixir allows atoms with unusual names
      type_def = build_test_type_definition(name: :"")
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      assert {type_iri, RDF.type(), Structure.PublicType} in triples
    end

    test "handles type in nested module" do
      type_def = build_test_type_definition(name: :t)
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Deeply.Nested.Module")

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      assert to_string(type_iri) ==
               "https://example.org/code#MyApp.Deeply.Nested.Module/type/t/0"

      assert {module_iri, Structure.containsType(), type_iri} in triples
    end

    test "spec with empty parameter list" do
      func_spec = build_test_function_spec(arity: 0, parameter_types: [])
      context = build_test_context()
      function_iri = build_test_function_iri()

      {spec_iri, triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in triples
    end

    test "type with large arity" do
      params = Enum.map(1..10, fn i -> String.to_atom("t#{i}") end)
      type_def = build_test_type_definition(name: :many_params, arity: 10, parameters: params)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify typeArity is 10
      assert Enum.any?(triples, fn
               {^type_iri, pred, obj} ->
                 pred == Structure.typeArity() and is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == 10

               _ ->
                 false
             end)

      # Count type variables
      type_var_count =
        Enum.count(triples, fn
          {^type_iri, pred, _} -> pred == Structure.hasTypeVariable()
          _ -> false
        end)

      assert type_var_count == 10
    end
  end

  # ===========================================================================
  # Type Expression Building Tests
  # ===========================================================================

  describe "build_type_expression/2 - union types" do
    test "builds simple union type with two members" do
      context = build_test_context()
      # AST for `integer() | atom()`
      union_ast = {:|, [], [{:integer, [], []}, {:atom, [], []}]}

      {union_node, triples} = TypeSystemBuilder.build_type_expression(union_ast, context)

      # Verify union type class
      assert {union_node, RDF.type(), Structure.UnionType} in triples

      # Count unionOf triples (should be 2)
      union_of_count =
        Enum.count(triples, fn
          {^union_node, pred, _} -> pred == Structure.unionOf()
          _ -> false
        end)

      assert union_of_count == 2

      # Verify member types are BasicType
      basic_type_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.BasicType
          _ -> false
        end)

      assert basic_type_count == 2
    end

    test "builds union type with three members" do
      context = build_test_context()
      # AST for `integer() | atom() | binary()`
      # Unions are right-associative in AST
      union_ast = {:|, [], [{:integer, [], []}, {:|, [], [{:atom, [], []}, {:binary, [], []}]}]}

      {union_node, triples} = TypeSystemBuilder.build_type_expression(union_ast, context)

      # Verify union type class
      assert {union_node, RDF.type(), Structure.UnionType} in triples

      # Count unionOf triples - nested unions should be flattened
      union_of_count =
        Enum.count(triples, fn
          {^union_node, pred, _} -> pred == Structure.unionOf()
          _ -> false
        end)

      # Should have 3 members (flattened)
      assert union_of_count == 3
    end

    test "builds union type with literal atom members" do
      context = build_test_context()
      # AST for `:ok | :error`
      union_ast = {:|, [], [:ok, :error]}

      {union_node, triples} = TypeSystemBuilder.build_type_expression(union_ast, context)

      # Verify union type class
      assert {union_node, RDF.type(), Structure.UnionType} in triples

      # Verify we have unionOf links
      union_of_count =
        Enum.count(triples, fn
          {^union_node, pred, _} -> pred == Structure.unionOf()
          _ -> false
        end)

      assert union_of_count == 2
    end

    test "builds nested union with complex types" do
      context = build_test_context()
      # AST for `{:ok, integer()} | {:error, binary()}`
      # This is a union of tuple types
      union_ast =
        {:|, [],
         [
           {:{}, [], [:ok, {:integer, [], []}]},
           {:{}, [], [:error, {:binary, [], []}]}
         ]}

      {union_node, triples} = TypeSystemBuilder.build_type_expression(union_ast, context)

      # Verify union type class
      assert {union_node, RDF.type(), Structure.UnionType} in triples

      # Verify tuple types are created
      tuple_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.TupleType
          _ -> false
        end)

      assert tuple_count == 2
    end
  end

  describe "build_type_expression/2 - basic types" do
    test "builds simple basic type" do
      context = build_test_context()
      # AST for `integer()`
      basic_ast = {:integer, [], []}

      {node, triples} = TypeSystemBuilder.build_type_expression(basic_ast, context)

      # Verify basic type class
      assert {node, RDF.type(), Structure.BasicType} in triples

      # Verify type name
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "integer"

               _ ->
                 false
             end)
    end

    test "builds parameterized type" do
      context = build_test_context()
      # AST for `list(integer())`
      param_ast = {:list, [], [[{:integer, [], []}]]}

      {node, triples} = TypeSystemBuilder.build_type_expression(param_ast, context)

      # Verify parameterized type class
      assert {node, RDF.type(), Structure.ParameterizedType} in triples

      # Verify has element type link
      has_element =
        Enum.any?(triples, fn
          {^node, pred, _} -> pred == Structure.elementType()
          _ -> false
        end)

      assert has_element
    end

    test "builds parameterized type with type name" do
      context = build_test_context()
      # AST for `list(integer())`
      param_ast = {:list, [], [[{:integer, [], []}]]}

      {node, triples} = TypeSystemBuilder.build_type_expression(param_ast, context)

      # Verify type name is set (the base type name)
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "list"

               _ ->
                 false
             end)
    end

    test "builds keyword parameterized type" do
      context = build_test_context()
      # AST for `keyword(integer())`
      # This is a single-parameter parameterized type
      param_ast = {:keyword, [], [{:integer, [], []}]}

      {node, triples} = TypeSystemBuilder.build_type_expression(param_ast, context)

      # Verify parameterized type class
      assert {node, RDF.type(), Structure.ParameterizedType} in triples

      # Verify type name is keyword
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "keyword"

               _ ->
                 false
             end)

      # Verify element type link exists
      has_element =
        Enum.any?(triples, fn
          {^node, pred, _} -> pred == Structure.elementType()
          _ -> false
        end)

      assert has_element
    end

    test "builds nested parameterized type" do
      context = build_test_context()
      # AST for `list(list(integer()))`
      nested_ast = {:list, [], [[{:list, [], [[{:integer, [], []}]]}]]}

      {node, triples} = TypeSystemBuilder.build_type_expression(nested_ast, context)

      # Verify outer parameterized type
      assert {node, RDF.type(), Structure.ParameterizedType} in triples

      # Verify we have two ParameterizedType instances (outer and inner list)
      param_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.ParameterizedType
          _ -> false
        end)

      assert param_count == 2

      # Verify inner basic type exists (integer)
      basic_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.BasicType
          _ -> false
        end)

      assert basic_count == 1
    end

    test "builds deeply nested parameterized type" do
      context = build_test_context()
      # AST for `list(list(list(atom())))`
      deep_ast = {:list, [], [[{:list, [], [[{:list, [], [[{:atom, [], []}]]}]]}]]}

      {node, triples} = TypeSystemBuilder.build_type_expression(deep_ast, context)

      # Verify outer parameterized type
      assert {node, RDF.type(), Structure.ParameterizedType} in triples

      # Verify we have 3 ParameterizedType instances (3 levels of list)
      param_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.ParameterizedType
          _ -> false
        end)

      assert param_count == 3
    end
  end

  describe "build_type_expression/2 - tuple types" do
    test "builds tuple type with element types" do
      context = build_test_context()
      # AST for `{atom(), integer()}`
      tuple_ast = {:{}, [], [{:atom, [], []}, {:integer, [], []}]}

      {node, triples} = TypeSystemBuilder.build_type_expression(tuple_ast, context)

      # Verify tuple type class
      assert {node, RDF.type(), Structure.TupleType} in triples

      # Verify element type links
      element_count =
        Enum.count(triples, fn
          {^node, pred, _} -> pred == Structure.elementType()
          _ -> false
        end)

      assert element_count == 2
    end
  end

  describe "build_type_expression/2 - function types" do
    test "builds function type with params and return" do
      context = build_test_context()
      # AST for `(integer() -> atom())`
      # Function types in AST are: [{:->, [], [[param_types], return_type]}]
      func_ast = [{:->, [], [[{:integer, [], []}], {:atom, [], []}]}]

      {node, triples} = TypeSystemBuilder.build_type_expression(func_ast, context)

      # Verify function type class
      assert {node, RDF.type(), Structure.FunctionType} in triples

      # Verify has parameter type
      has_param =
        Enum.any?(triples, fn
          {^node, pred, _} -> pred == Structure.hasParameterType()
          _ -> false
        end)

      assert has_param

      # Verify has return type
      has_return =
        Enum.any?(triples, fn
          {^node, pred, _} -> pred == Structure.hasReturnType()
          _ -> false
        end)

      assert has_return
    end
  end

  describe "build_type_expression/2 - variable types" do
    test "builds type variable" do
      context = build_test_context()
      # AST for type variable `t`
      var_ast = {:t, [], nil}

      {node, triples} = TypeSystemBuilder.build_type_expression(var_ast, context)

      # Verify type variable class
      assert {node, RDF.type(), Structure.TypeVariable} in triples

      # Verify variable name
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "t"

               _ ->
                 false
             end)
    end
  end

  describe "build_type_expression/2 - remote types" do
    test "builds simple remote type String.t()" do
      context = build_test_context()
      # AST for `String.t()`
      remote_ast = {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}

      {node, triples} = TypeSystemBuilder.build_type_expression(remote_ast, context)

      # Verify basic type class (remote types use BasicType since RemoteType doesn't exist)
      assert {node, RDF.type(), Structure.BasicType} in triples

      # Verify qualified type name
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "String.t"

               _ ->
                 false
             end)
    end

    test "builds remote type with nested module MyApp.Users.t()" do
      context = build_test_context()
      # AST for `MyApp.Users.t()`
      remote_ast = {{:., [], [{:__aliases__, [alias: false], [:MyApp, :Users]}, :t]}, [], []}

      {node, triples} = TypeSystemBuilder.build_type_expression(remote_ast, context)

      # Verify basic type class
      assert {node, RDF.type(), Structure.BasicType} in triples

      # Verify qualified type name with nested modules
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "MyApp.Users.t"

               _ ->
                 false
             end)
    end

    test "builds remote type with different type name" do
      context = build_test_context()
      # AST for `Enum.result()`
      remote_ast = {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :result]}, [], []}

      {node, triples} = TypeSystemBuilder.build_type_expression(remote_ast, context)

      # Verify type name includes type name (not just "t")
      assert Enum.any?(triples, fn
               {^node, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "Enum.result"

               _ ->
                 false
             end)
    end

    test "builds remote type in union" do
      context = build_test_context()
      # AST for `String.t() | atom()`
      union_ast =
        {:|, [],
         [
           {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []},
           {:atom, [], []}
         ]}

      {node, triples} = TypeSystemBuilder.build_type_expression(union_ast, context)

      # Verify union type class
      assert {node, RDF.type(), Structure.UnionType} in triples

      # Verify both BasicType instances exist (one for String.t, one for atom)
      basic_count =
        Enum.count(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.BasicType
          _ -> false
        end)

      assert basic_count == 2

      # Verify String.t name exists in triples
      assert Enum.any?(triples, fn
               {_, pred, obj} ->
                 pred == Structure.typeName() and
                   is_struct(obj, RDF.Literal) and
                   RDF.Literal.value(obj) == "String.t"

               _ ->
                 false
             end)
    end
  end

  describe "build_type_definition/3 - with type expression" do
    test "type definition includes expression triples" do
      # Type with union expression: @type result :: :ok | :error
      type_def =
        build_test_type_definition(
          name: :result,
          arity: 0,
          expression: {:|, [], [:ok, :error]}
        )

      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify type definition
      assert {type_iri, RDF.type(), Structure.PublicType} in triples

      # Verify union type is created (triples contain UnionType)
      has_union =
        Enum.any?(triples, fn
          {_, pred, obj} -> pred == RDF.type() and obj == Structure.UnionType
          _ -> false
        end)

      assert has_union

      # Verify referencesType link exists
      has_ref =
        Enum.any?(triples, fn
          {^type_iri, pred, _} -> pred == Structure.referencesType()
          _ -> false
        end)

      assert has_ref
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "can build multiple types for same module" do
      type_def1 = build_test_type_definition(name: :t1, arity: 0)
      type_def2 = build_test_type_definition(name: :t2, arity: 1, parameters: [:a])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {type_iri1, _triples1} =
        TypeSystemBuilder.build_type_definition(type_def1, module_iri, context)

      {type_iri2, _triples2} =
        TypeSystemBuilder.build_type_definition(type_def2, module_iri, context)

      # Both types should link to same module
      assert type_iri1 != type_iri2
      assert to_string(type_iri1) =~ "TestModule"
      assert to_string(type_iri2) =~ "TestModule"
    end

    test "can build spec for function that references type" do
      # Build a type
      type_def = build_test_type_definition(name: :user_t, arity: 0)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_type_iri, _type_triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Build a spec that references that type
      func_spec =
        build_test_function_spec(
          name: :get_user,
          arity: 1,
          parameter_types: [{:integer, [], []}],
          return_type: {:user_t, [], []}
        )

      function_iri = build_test_function_iri(function_name: "get_user", arity: 1)

      {spec_iri, spec_triples} =
        TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

      # Verify spec was created
      assert {spec_iri, RDF.type(), Structure.FunctionSpec} in spec_triples
    end
  end
end
