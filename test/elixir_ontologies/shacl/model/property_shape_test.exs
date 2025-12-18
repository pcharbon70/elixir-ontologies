defmodule ElixirOntologies.SHACL.Model.PropertyShapeTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape

  describe "struct creation" do
    test "creates property shape with required fields" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>
      }

      assert %RDF.BlankNode{} = shape.id
      assert shape.path == ~I<http://example.org/prop1>
      assert shape.message == nil
      assert shape.min_count == nil
      assert shape.max_count == nil
      assert shape.datatype == nil
      assert shape.class == nil
      assert shape.pattern == nil
      assert shape.min_length == nil
      assert shape.in == []
      assert shape.has_value == nil
      assert shape.qualified_class == nil
      assert shape.qualified_min_count == nil
    end
  end

  describe "cardinality constraints" do
    test "creates property shape with min_count" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>,
        min_count: 1
      }

      assert shape.min_count == 1
      assert shape.max_count == nil
    end

    test "creates property shape with max_count" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>,
        max_count: 5
      }

      assert shape.min_count == nil
      assert shape.max_count == 5
    end

    test "creates property shape with exact count (min = max)" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>,
        min_count: 1,
        max_count: 1,
        message: "Must have exactly one value"
      }

      assert shape.min_count == 1
      assert shape.max_count == 1
      assert shape.message == "Must have exactly one value"
    end
  end

  describe "type constraints" do
    test "creates property shape with datatype constraint" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#string>
      }

      assert shape.datatype == ~I<http://www.w3.org/2001/XMLSchema#string>
      assert shape.class == nil
    end

    test "creates property shape with class constraint" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>,
        class: ~I<http://example.org/MyClass>
      }

      assert shape.class == ~I<http://example.org/MyClass>
      assert shape.datatype == nil
    end
  end

  describe "string constraints" do
    test "creates property shape with pattern constraint" do
      pattern = ~r/^[A-Z][a-zA-Z0-9_]*$/

      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/moduleName>,
        pattern: pattern,
        message: "Module name must match pattern"
      }

      assert shape.pattern == pattern
      assert Regex.match?(shape.pattern, "MyModule")
      refute Regex.match?(shape.pattern, "badModule")
    end

    test "creates property shape with min_length constraint" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/name>,
        min_length: 3
      }

      assert shape.min_length == 3
    end

    test "creates property shape with both pattern and min_length" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/name>,
        pattern: ~r/^[a-z]+$/,
        min_length: 2
      }

      assert shape.pattern == ~r/^[a-z]+$/
      assert shape.min_length == 2
    end
  end

  describe "value constraints" do
    test "creates property shape with 'in' constraint" do
      allowed_values = [
        ~I<http://example.org/value1>,
        ~I<http://example.org/value2>,
        ~I<http://example.org/value3>
      ]

      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/strategy>,
        in: allowed_values,
        message: "Must be one of the allowed values"
      }

      assert shape.in == allowed_values
      assert length(shape.in) == 3
    end

    test "creates property shape with has_value constraint" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/type>,
        has_value: ~I<http://example.org/SpecificType>
      }

      assert shape.has_value == ~I<http://example.org/SpecificType>
    end

    test "in constraint defaults to empty list" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>
      }

      assert shape.in == []
    end
  end

  describe "qualified constraints" do
    test "creates property shape with qualified constraint" do
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/hasChild>,
        qualified_class: ~I<http://example.org/ChildClass>,
        qualified_min_count: 2
      }

      assert shape.qualified_class == ~I<http://example.org/ChildClass>
      assert shape.qualified_min_count == 2
    end
  end

  describe "real-world usage from elixir-shapes.ttl" do
    test "creates module name constraint" do
      shape = %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        min_count: 1,
        max_count: 1,
        pattern: ~r/^[A-Z][a-zA-Z0-9_]*$/,
        message: "Module name required and must be valid Elixir module identifier"
      }

      assert shape.min_count == 1
      assert shape.max_count == 1
      assert Regex.match?(shape.pattern, "MyModule")
      assert Regex.match?(shape.pattern, "My_Module123")
      refute Regex.match?(shape.pattern, "myModule")
      refute Regex.match?(shape.pattern, "123Module")
    end

    test "creates function name constraint" do
      shape = %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/structure#functionName>,
        pattern: ~r/^[a-z_][a-z0-9_]*[!?]?$/,
        message: "Function name must be valid Elixir identifier"
      }

      assert Regex.match?(shape.pattern, "my_function")
      assert Regex.match?(shape.pattern, "valid?")
      assert Regex.match?(shape.pattern, "valid!")
      refute Regex.match?(shape.pattern, "Invalid")
      refute Regex.match?(shape.pattern, "123invalid")
    end

    test "creates arity constraint" do
      shape = %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/structure#arity>,
        min_count: 1,
        max_count: 1,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>,
        message: "Function must have exactly one non-negative arity value"
      }

      assert shape.min_count == 1
      assert shape.max_count == 1
      assert shape.datatype == ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>
    end

    test "creates supervisor strategy constraint" do
      shape = %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
        in: [
          ~I<https://w3id.org/elixir-code/otp#OneForOne>,
          ~I<https://w3id.org/elixir-code/otp#OneForAll>,
          ~I<https://w3id.org/elixir-code/otp#RestForOne>
        ],
        message: "Supervisor strategy must be one of the allowed values"
      }

      assert length(shape.in) == 3
      assert ~I<https://w3id.org/elixir-code/otp#OneForOne> in shape.in
    end
  end
end
