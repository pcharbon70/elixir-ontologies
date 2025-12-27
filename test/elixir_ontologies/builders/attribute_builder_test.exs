defmodule ElixirOntologies.Builders.AttributeBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{AttributeBuilder, Context}
  alias ElixirOntologies.Extractors.Attribute
  alias ElixirOntologies.NS.{Structure, Core}
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest AttributeBuilder

  describe "build/3 basic attribute" do
    test "builds generic module attribute" do
      attribute = %Attribute{
        type: :attribute,
        name: :my_attr,
        value: 42,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify IRI format
      assert to_string(attr_iri) =~ "MyApp/attribute/my_attr"

      # Verify type triple
      assert {attr_iri, RDF.type(), Structure.ModuleAttribute} in triples

      # Verify attribute name triple
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeName() and
                   RDF.Literal.value(obj) == "my_attr"

               _ ->
                 false
             end)

      # Verify attribute value triple
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeValue() and
                   RDF.Literal.value(obj) == "42"

               _ ->
                 false
             end)
    end

    test "builds attribute with nested module" do
      attribute = %Attribute{
        type: :attribute,
        name: :custom,
        value: "test",
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, _triples} =
        AttributeBuilder.build(attribute, context, module: [:MyApp, :Users, :Admin])

      assert to_string(attr_iri) =~ "MyApp.Users.Admin/attribute/custom"
    end

    test "builds attribute with index for accumulated" do
      attribute = %Attribute{
        type: :attribute,
        name: :items,
        value: "item1",
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, _triples} =
        AttributeBuilder.build(attribute, context, module: [:MyApp], index: 0)

      assert to_string(attr_iri) =~ "MyApp/attribute/items/0"
    end
  end

  describe "build/3 doc attributes" do
    test "builds @doc attribute with content" do
      attribute = %Attribute{
        type: :doc_attribute,
        name: :doc,
        value: "Function documentation",
        metadata: %{hidden: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify type is FunctionDocAttribute
      assert {attr_iri, RDF.type(), Structure.FunctionDocAttribute} in triples

      # Verify docstring triple
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Function documentation"

               _ ->
                 false
             end)
    end

    test "builds @moduledoc attribute" do
      attribute = %Attribute{
        type: :moduledoc_attribute,
        name: :moduledoc,
        value: "Module documentation",
        metadata: %{hidden: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify type is ModuledocAttribute
      assert {attr_iri, RDF.type(), Structure.ModuledocAttribute} in triples

      # Verify docstring
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Module documentation"

               _ ->
                 false
             end)
    end

    test "builds @doc false attribute" do
      attribute = %Attribute{
        type: :doc_attribute,
        name: :doc,
        value: false,
        metadata: %{hidden: true}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify isDocFalse is true
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.isDocFalse() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "builds @typedoc attribute" do
      attribute = %Attribute{
        type: :typedoc_attribute,
        name: :typedoc,
        value: "Type documentation",
        metadata: %{hidden: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.TypedocAttribute} in triples
    end
  end

  describe "build/3 deprecated attribute" do
    test "builds @deprecated with message" do
      attribute = %Attribute{
        type: :deprecated_attribute,
        name: :deprecated,
        value: "Use new_func/1 instead",
        metadata: %{message: "Use new_func/1 instead"}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify type
      assert {attr_iri, RDF.type(), Structure.DeprecatedAttribute} in triples

      # Verify deprecation message
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.deprecationMessage() and
                   RDF.Literal.value(obj) == "Use new_func/1 instead"

               _ ->
                 false
             end)
    end
  end

  describe "build/3 since attribute" do
    test "builds @since with version" do
      attribute = %Attribute{
        type: :since_attribute,
        name: :since,
        value: "1.5.0",
        metadata: %{version: "1.5.0"}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Verify type
      assert {attr_iri, RDF.type(), Structure.SinceAttribute} in triples

      # Verify since version
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.sinceVersion() and
                   RDF.Literal.value(obj) == "1.5.0"

               _ ->
                 false
             end)
    end
  end

  describe "build/3 accumulating attribute" do
    test "builds attribute with accumulating flag" do
      attribute = %Attribute{
        type: :attribute,
        name: :callbacks,
        value: {:on_init, 1},
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} =
        AttributeBuilder.build(attribute, context, module: [:MyApp], accumulated: true, index: 0)

      # Verify isAccumulating is true
      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.isAccumulating() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "non-accumulated attribute has no isAccumulating triple" do
      attribute = %Attribute{
        type: :attribute,
        name: :version,
        value: "1.0.0",
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Should NOT have isAccumulating triple
      refute Enum.any?(triples, fn
               {^attr_iri, pred, _obj} ->
                 pred == Structure.isAccumulating()

               _ ->
                 false
             end)
    end
  end

  describe "build/3 with location" do
    test "builds attribute with source location" do
      location = %SourceLocation{
        start_line: 10,
        start_column: 3,
        end_line: 10,
        end_column: 25
      }

      attribute = %Attribute{
        type: :attribute,
        name: :my_attr,
        value: 42,
        location: location,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      # Should have hasSourceLocation triple
      assert Enum.any?(triples, fn
               {^attr_iri, pred, _obj} ->
                 pred == Core.hasSourceLocation()

               _ ->
                 false
             end)

      # Location IRI should include line numbers
      location_triples =
        Enum.filter(triples, fn
          {_s, pred, _o} -> pred == Core.hasSourceLocation()
          _ -> false
        end)

      assert length(location_triples) == 1
      {_, _, location_iri} = hd(location_triples)

      assert to_string(location_iri) =~ "L10-10"

      # Location should have type triple
      assert {location_iri, RDF.type(), Core.SourceLocation} in triples
    end
  end

  describe "build/3 value serialization" do
    test "serializes list values as JSON" do
      attribute = %Attribute{
        type: :attribute,
        name: :items,
        value: [1, 2, 3],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeValue() and
                   RDF.Literal.value(obj) == "[1,2,3]"

               _ ->
                 false
             end)
    end

    test "serializes map values as JSON" do
      attribute = %Attribute{
        type: :attribute,
        name: :config,
        value: %{enabled: true},
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeValue() and
                   RDF.Literal.value(obj) == ~s({"enabled":true})

               _ ->
                 false
             end)
    end

    test "serializes nil value" do
      attribute = %Attribute{
        type: :attribute,
        name: :optional,
        value: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeValue() and
                   RDF.Literal.value(obj) == "nil"

               _ ->
                 false
             end)
    end

    test "serializes atom value" do
      attribute = %Attribute{
        type: :attribute,
        name: :mode,
        value: :production,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert Enum.any?(triples, fn
               {^attr_iri, pred, obj} ->
                 pred == Structure.attributeValue() and
                   RDF.Literal.value(obj) == "production"

               _ ->
                 false
             end)
    end
  end

  describe "build/3 other attribute types" do
    test "builds @external_resource attribute" do
      attribute = %Attribute{
        type: :external_resource_attribute,
        name: :external_resource,
        value: "priv/data.json",
        metadata: %{path: "priv/data.json"}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.ExternalResourceAttribute} in triples
    end

    test "builds @compile attribute" do
      attribute = %Attribute{
        type: :compile_attribute,
        name: :compile,
        value: [:inline],
        metadata: %{options: [:inline]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.CompileAttribute} in triples
    end

    test "builds @before_compile attribute" do
      attribute = %Attribute{
        type: :before_compile_attribute,
        name: :before_compile,
        value: {:__aliases__, [], [:MyHooks]},
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.BeforeCompileAttribute} in triples
    end

    test "builds @derive attribute" do
      attribute = %Attribute{
        type: :derive_attribute,
        name: :derive,
        value: [{:__aliases__, [], [:Jason, :Encoder]}],
        metadata: %{protocols: [[:Jason, :Encoder]]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.DeriveAttribute} in triples
    end

    test "builds @behaviour attribute" do
      attribute = %Attribute{
        type: :behaviour_declaration,
        name: :behaviour,
        value: {:__aliases__, [], [:GenServer]},
        metadata: %{module: [:GenServer]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

      assert {attr_iri, RDF.type(), Structure.BehaviourDeclaration} in triples
    end
  end
end
