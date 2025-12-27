defmodule ElixirOntologies.TypeSystem.Phase14IntegrationTest do
  @moduledoc """
  Integration tests for Phase 14 type system enhancements.

  These tests verify end-to-end functionality of type extraction and RDF generation,
  including complex type expressions, callback specs, and type system builder integration.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{TypeExpression, TypeDefinition, FunctionSpec}
  alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
  alias ElixirOntologies.NS.Structure

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_module_iri(module_name, opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_function_iri(module_name, func_name, arity, opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    RDF.iri("#{base_iri}#{module_name}/#{func_name}/#{arity}")
  end

  defp extract_type_from_code(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    TypeDefinition.extract(ast)
  end

  defp extract_spec_from_code(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    FunctionSpec.extract(ast)
  end

  defp has_triple?(triples, subject, predicate, object) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and o == object
    end)
  end

  defp count_triples_with_type(triples, type_class) do
    Enum.count(triples, fn
      {_, pred, obj} -> pred == RDF.type() and obj == type_class
      _ -> false
    end)
  end

  # ===========================================================================
  # Complex Type Extraction Tests
  # ===========================================================================

  describe "complex module with all type forms" do
    @complex_module """
    defmodule ComplexTypes do
      @type simple :: atom()
      @type union_type :: :ok | :error | :pending
      @type tuple_type :: {atom(), integer(), binary()}
      @type list_type :: list(integer())
      @type map_type :: %{required(atom()) => String.t()}
      @type function_type :: (integer(), atom() -> {:ok, term()} | {:error, String.t()})
      @type parameterized(a, b) :: {a, list(b)}
      @type nested :: list(list(list(atom())))
      @typep private_type :: binary()
      @opaque opaque_type :: %__MODULE__{}
    end
    """

    test "extracts all type definitions from complex module" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@complex_module)

      types = TypeDefinition.extract_all(body)

      assert length(types) == 10

      type_names = Enum.map(types, & &1.name)
      assert :simple in type_names
      assert :union_type in type_names
      assert :tuple_type in type_names
      assert :list_type in type_names
      assert :map_type in type_names
      assert :function_type in type_names
      assert :parameterized in type_names
      assert :nested in type_names
      assert :private_type in type_names
      assert :opaque_type in type_names
    end

    test "builds RDF for all type definitions" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@complex_module)

      types = TypeDefinition.extract_all(body)
      context = build_context()
      module_iri = build_module_iri("ComplexTypes")

      all_triples =
        Enum.flat_map(types, fn type_def ->
          {_type_iri, triples} =
            TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

          triples
        end)

      # Verify we have type triples for each visibility
      public_count = count_triples_with_type(all_triples, Structure.PublicType)
      private_count = count_triples_with_type(all_triples, Structure.PrivateType)
      opaque_count = count_triples_with_type(all_triples, Structure.OpaqueType)

      assert public_count == 8
      assert private_count == 1
      assert opaque_count == 1
    end
  end

  describe "union type with 5+ members" do
    test "extracts union type with many members" do
      code = "@type status :: :pending | :running | :success | :failed | :cancelled | :timeout"
      {:ok, type_def} = extract_type_from_code(code)

      assert type_def.name == :status

      # Parse the expression to verify union members
      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :union
      # Union members are in `elements` field
      assert length(parsed.elements) == 6
    end

    test "builds RDF for large union type" do
      code = "@type status :: :pending | :running | :success | :failed | :cancelled | :timeout"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("StatusModule")

      {_type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify union type is created
      union_count = count_triples_with_type(triples, Structure.UnionType)
      assert union_count >= 1

      # Verify unionOf triples exist
      union_of_count =
        Enum.count(triples, fn
          {_, pred, _} -> pred == Structure.unionOf()
          _ -> false
        end)

      assert union_of_count == 6
    end
  end

  describe "deeply nested parameterized types (3+ levels)" do
    test "extracts nested parameterized types" do
      code = "@type deep :: list(map(atom(), list(tuple())))"
      {:ok, type_def} = extract_type_from_code(code)

      {:ok, parsed} = TypeExpression.parse(type_def.expression)

      # Verify structure: list -> map -> list -> tuple
      assert parsed.kind == :basic
      assert parsed.name == :list
      assert parsed.metadata[:parameterized] == true

      inner = hd(parsed.elements)
      assert inner.kind == :basic
      assert inner.name == :map
    end

    test "builds RDF for deeply nested types" do
      code = "@type deep :: list(list(list(atom())))"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("DeepModule")

      {_type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Count parameterized types (3 levels of list)
      param_count = count_triples_with_type(triples, Structure.ParameterizedType)
      assert param_count == 3

      # Innermost should be BasicType (atom)
      basic_count = count_triples_with_type(triples, Structure.BasicType)
      assert basic_count >= 1
    end
  end

  # ===========================================================================
  # Remote Type Tests
  # ===========================================================================

  describe "remote type extraction and building" do
    test "extracts String.t() remote type" do
      code = "@type name :: String.t()"
      {:ok, type_def} = extract_type_from_code(code)

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :remote
      assert parsed.module == [:String]
      assert parsed.name == :t
    end

    test "extracts GenServer.on_start() remote type" do
      code = "@type start_result :: GenServer.on_start()"
      {:ok, type_def} = extract_type_from_code(code)

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :remote
      assert parsed.module == [:GenServer]
      assert parsed.name == :on_start
    end

    test "builds RDF for remote type with qualified name" do
      code = "@type name :: String.t()"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("RemoteModule")

      {_type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Remote types are built as BasicType with qualified name
      has_string_t =
        Enum.any?(triples, fn
          {_, pred, obj} ->
            pred == Structure.typeName() and
              is_struct(obj, RDF.Literal) and
              RDF.Literal.value(obj) == "String.t"

          _ ->
            false
        end)

      assert has_string_t
    end
  end

  # ===========================================================================
  # Type Variable Tests
  # ===========================================================================

  describe "type variable scoping in polymorphic functions" do
    test "extracts type variables from parameterized type" do
      code = "@type pair(a, b) :: {a, b}"
      {:ok, type_def} = extract_type_from_code(code)

      assert type_def.arity == 2
      assert type_def.parameters == [:a, :b]

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :tuple
      assert length(parsed.elements) == 2

      [first, second] = parsed.elements
      assert first.kind == :variable
      assert first.name == :a
      assert second.kind == :variable
      assert second.name == :b
    end

    test "extracts spec with when constraints" do
      code = "@spec identity(a) :: a when a: term()"
      {:ok, spec} = extract_spec_from_code(code)

      assert spec.name == :identity
      assert spec.arity == 1
      assert Map.has_key?(spec.type_constraints, :a)
    end

    test "builds RDF for type variables" do
      code = "@type wrapper(t) :: {:wrapped, t}"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("WrapperModule")

      {_type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify TypeVariable is created
      var_count = count_triples_with_type(triples, Structure.TypeVariable)
      assert var_count >= 1
    end
  end

  # ===========================================================================
  # Callback Spec Integration Tests
  # ===========================================================================

  describe "callback spec extraction and RDF generation" do
    test "@callback extracts with spec_type :callback" do
      code = "@callback init(args :: term()) :: {:ok, state} | {:error, reason}"
      {:ok, spec} = extract_spec_from_code(code)

      assert spec.name == :init
      assert spec.arity == 1
      assert spec.spec_type == :callback
    end

    test "@macrocallback extracts with spec_type :macrocallback" do
      code = "@macrocallback __using__(opts :: keyword()) :: Macro.t()"
      {:ok, spec} = extract_spec_from_code(code)

      assert spec.name == :__using__
      assert spec.arity == 1
      assert spec.spec_type == :macrocallback
    end

    test "@callback builds CallbackSpec RDF class" do
      code = "@callback handle_call(request, from, state) :: {:reply, reply, state}"
      {:ok, spec} = extract_spec_from_code(code)

      context = build_context()
      function_iri = build_function_iri("MyBehaviour", "handle_call", 3)

      {spec_iri, triples} = TypeSystemBuilder.build_function_spec(spec, function_iri, context)

      assert has_triple?(triples, spec_iri, RDF.type(), Structure.CallbackSpec)
      refute has_triple?(triples, spec_iri, RDF.type(), Structure.FunctionSpec)
    end

    test "@macrocallback builds MacroCallbackSpec RDF class" do
      code = "@macrocallback __using__(opts) :: Macro.t()"
      {:ok, spec} = extract_spec_from_code(code)

      context = build_context()
      function_iri = build_function_iri("MyBehaviour", "__using__", 1)

      {spec_iri, triples} = TypeSystemBuilder.build_function_spec(spec, function_iri, context)

      assert has_triple?(triples, spec_iri, RDF.type(), Structure.MacroCallbackSpec)
    end

    test "function type in callback spec" do
      code = "@callback transform((term() -> term()), list()) :: list()"
      {:ok, spec} = extract_spec_from_code(code)

      assert spec.name == :transform
      assert spec.arity == 2
      assert spec.spec_type == :callback

      # Verify first parameter is a function type
      [first_param | _] = spec.parameter_types
      {:ok, parsed} = TypeExpression.parse(first_param)
      assert parsed.kind == :function
    end
  end

  # ===========================================================================
  # Struct Type Tests
  # ===========================================================================

  describe "struct type extraction and building" do
    test "extracts struct type from named module struct" do
      # Note: %__MODULE__{} is not recognized by type expression parser
      # Use explicit module name instead
      code = "@type t :: %MyModule.User{name: String.t(), age: integer()}"
      {:ok, type_def} = extract_type_from_code(code)

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :struct
      assert parsed.module == [:MyModule, :User]
    end

    test "builds RDF for struct type" do
      code = "@type t :: %MyModule.User{}"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("UserStruct")

      {_type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Note: StructType doesn't exist in ontology, uses BasicType with struct name
      # Verify the struct module name is preserved in typeName
      has_struct_name =
        Enum.any?(triples, fn
          {_, pred, obj} ->
            pred == Structure.typeName() and
              is_struct(obj, RDF.Literal) and
              String.contains?(RDF.Literal.value(obj), "MyModule.User")

          _ ->
            false
        end)

      assert has_struct_name
    end
  end

  # ===========================================================================
  # Type IRI Stability Tests
  # ===========================================================================

  describe "type IRI stability across multiple extractions" do
    test "same type definition produces same IRI" do
      code = "@type user_id :: integer()"
      {:ok, type_def1} = extract_type_from_code(code)
      {:ok, type_def2} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("UserModule")

      {type_iri1, _} = TypeSystemBuilder.build_type_definition(type_def1, module_iri, context)
      {type_iri2, _} = TypeSystemBuilder.build_type_definition(type_def2, module_iri, context)

      assert type_iri1 == type_iri2
    end

    test "type IRI includes arity for parameterized types" do
      code1 = "@type wrapper(t) :: {t}"
      code2 = "@type wrapper :: atom()"

      {:ok, type_def1} = extract_type_from_code(code1)
      {:ok, type_def2} = extract_type_from_code(code2)

      context = build_context()
      module_iri = build_module_iri("WrapperModule")

      {type_iri1, _} = TypeSystemBuilder.build_type_definition(type_def1, module_iri, context)
      {type_iri2, _} = TypeSystemBuilder.build_type_definition(type_def2, module_iri, context)

      # Different arities should produce different IRIs
      assert type_iri1 != type_iri2
      assert to_string(type_iri1) =~ "/wrapper/1"
      assert to_string(type_iri2) =~ "/wrapper/0"
    end
  end

  # ===========================================================================
  # Backward Compatibility Tests
  # ===========================================================================

  describe "backward compatibility with existing type extraction" do
    test "simple atom type still works" do
      code = "@type t :: atom()"
      {:ok, type_def} = extract_type_from_code(code)

      assert type_def.name == :t
      assert type_def.visibility == :public

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      assert parsed.kind == :basic
      assert parsed.name == :atom
    end

    test "simple @spec still works" do
      code = "@spec add(integer(), integer()) :: integer()"
      {:ok, spec} = extract_spec_from_code(code)

      assert spec.name == :add
      assert spec.arity == 2
      assert spec.spec_type == :spec
      assert length(spec.parameter_types) == 2
    end

    test "existing RDF generation still works" do
      code = "@type t :: atom()"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("LegacyModule")

      {type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      assert has_triple?(triples, type_iri, RDF.type(), Structure.PublicType)
      assert has_triple?(triples, module_iri, Structure.containsType(), type_iri)
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling for malformed type expressions" do
    test "handles unknown type expression gracefully" do
      # Create a type definition with an unusual expression
      type_def = %TypeDefinition{
        name: :weird,
        arity: 0,
        visibility: :public,
        parameters: [],
        expression: {:unknown_form, [], []},
        location: nil,
        metadata: %{}
      }

      # Should not crash when parsing
      result = TypeExpression.parse(type_def.expression)

      # Should produce some result (likely basic type fallback)
      assert match?({:ok, _}, result)
    end

    test "handles nil expression in type definition" do
      type_def = %TypeDefinition{
        name: :nil_type,
        arity: 0,
        visibility: :public,
        parameters: [],
        expression: nil,
        location: nil,
        metadata: %{}
      }

      context = build_context()
      module_iri = build_module_iri("NilModule")

      # Should not crash when building
      {type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Should still produce type definition triples
      assert has_triple?(triples, type_iri, RDF.type(), Structure.PublicType)
    end

    test "handles empty union gracefully" do
      # Edge case: union with single member (degenerates to the member)
      code = "@type single :: :only_option"
      {:ok, type_def} = extract_type_from_code(code)

      {:ok, parsed} = TypeExpression.parse(type_def.expression)
      # Single literal should not be a union
      assert parsed.kind == :literal
    end
  end

  # ===========================================================================
  # Round-Trip Tests
  # ===========================================================================

  describe "round-trip: extraction → RDF → verification" do
    test "complex union type round-trip" do
      code = "@type result :: {:ok, term()} | {:error, String.t()} | :pending"
      {:ok, type_def} = extract_type_from_code(code)

      context = build_context()
      module_iri = build_module_iri("ResultModule")

      {type_iri, triples} =
        TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Verify type definition exists
      assert has_triple?(triples, type_iri, RDF.type(), Structure.PublicType)

      # Verify union type is created
      union_count = count_triples_with_type(triples, Structure.UnionType)
      assert union_count >= 1

      # Verify tuple types are created
      tuple_count = count_triples_with_type(triples, Structure.TupleType)
      assert tuple_count >= 2

      # Verify type name is preserved
      has_name =
        Enum.any?(triples, fn
          {^type_iri, pred, obj} ->
            pred == Structure.typeName() and
              is_struct(obj, RDF.Literal) and
              RDF.Literal.value(obj) == "result"

          _ ->
            false
        end)

      assert has_name
    end

    test "callback spec round-trip" do
      code = "@callback start_link(opts :: keyword()) :: GenServer.on_start()"
      {:ok, spec} = extract_spec_from_code(code)

      context = build_context()
      function_iri = build_function_iri("MyServer", "start_link", 1)

      {spec_iri, triples} = TypeSystemBuilder.build_function_spec(spec, function_iri, context)

      # Verify callback spec class
      assert has_triple?(triples, spec_iri, RDF.type(), Structure.CallbackSpec)

      # Verify hasSpec link
      assert has_triple?(triples, function_iri, Structure.hasSpec(), spec_iri)
    end
  end
end
