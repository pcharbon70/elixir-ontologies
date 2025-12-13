defmodule ElixirOntologies.SHACL.Validators.CardinalityTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape
  alias ElixirOntologies.SHACL.Validators.Cardinality

  doctest ElixirOntologies.SHACL.Validators.Cardinality

  # Test IRIs and property paths
  @module_iri ~I<http://example.org/Module1>
  @name_prop ~I<https://w3id.org/elixir-code/structure#moduleName>
  @function_prop ~I<https://w3id.org/elixir-code/structure#hasFunction>

  describe "minCount constraint" do
    test "passes when property has exactly minCount values" do
      # Shape requires at least 1 value
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: @name_prop,
        min_count: 1,
        message: "Module must have at least one name"
      }

      # Graph with exactly 1 value
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, "MyModule"}
        ])

      # Should pass (no violations)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "passes when property has more than minCount values" do
      # Shape requires at least 1 function
      shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: @function_prop,
        min_count: 1
      }

      # Graph with 3 functions
      graph =
        RDF.Graph.new([
          {@module_iri, @function_prop, ~I<http://example.org/Module1#foo/1>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#bar/2>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#baz/0>}
        ])

      # Should pass (3 >= 1)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "fails when property has fewer than minCount values" do
      # Shape requires at least 1 name
      shape = %PropertyShape{
        id: RDF.bnode("b3"),
        path: @name_prop,
        min_count: 1,
        message: "Module must have a name"
      }

      # Graph with 0 values (missing property)
      graph = RDF.Graph.new([])

      # Should fail with minCount violation
      [violation] = Cardinality.validate(graph, @module_iri, shape)

      assert violation.focus_node == @module_iri
      assert violation.path == @name_prop
      assert violation.severity == :violation
      assert violation.message == "Module must have a name"
      assert violation.details.min_count == 1
      assert violation.details.actual_count == 0

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MinCountConstraintComponent>
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b4"),
        path: @name_prop,
        min_count: 2,
        message: nil
      }

      # Graph with 1 value (< 2)
      graph = RDF.Graph.new([{@module_iri, @name_prop, "MyModule"}])

      [violation] = Cardinality.validate(graph, @module_iri, shape)

      # Should use default message
      assert violation.message ==
               "Property has too few values (expected at least 2, found 1)"
    end

    test "ignores minCount when nil" do
      # Shape without minCount constraint
      shape = %PropertyShape{
        id: RDF.bnode("b5"),
        path: @name_prop,
        min_count: nil
      }

      # Graph with 0 values
      graph = RDF.Graph.new([])

      # Should pass (no constraint)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end
  end

  describe "maxCount constraint" do
    test "passes when property has exactly maxCount values" do
      # Shape allows at most 1 name
      shape = %PropertyShape{
        id: RDF.bnode("b6"),
        path: @name_prop,
        max_count: 1
      }

      # Graph with exactly 1 value
      graph = RDF.Graph.new([{@module_iri, @name_prop, "MyModule"}])

      # Should pass (no violations)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "passes when property has fewer than maxCount values" do
      # Shape allows at most 3 functions
      shape = %PropertyShape{
        id: RDF.bnode("b7"),
        path: @function_prop,
        max_count: 3
      }

      # Graph with 2 functions
      graph =
        RDF.Graph.new([
          {@module_iri, @function_prop, ~I<http://example.org/Module1#foo/1>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#bar/2>}
        ])

      # Should pass (2 <= 3)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "fails when property has more than maxCount values" do
      # Shape allows at most 1 name
      shape = %PropertyShape{
        id: RDF.bnode("b8"),
        path: @name_prop,
        max_count: 1,
        message: "Module must have at most one name"
      }

      # Graph with 2 names (too many)
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, "MyModule"},
          {@module_iri, @name_prop, "OtherName"}
        ])

      # Should fail with maxCount violation
      [violation] = Cardinality.validate(graph, @module_iri, shape)

      assert violation.focus_node == @module_iri
      assert violation.path == @name_prop
      assert violation.severity == :violation
      assert violation.message == "Module must have at most one name"
      assert violation.details.max_count == 1
      assert violation.details.actual_count == 2

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MaxCountConstraintComponent>
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b9"),
        path: @function_prop,
        max_count: 2,
        message: nil
      }

      # Graph with 3 values (> 2)
      graph =
        RDF.Graph.new([
          {@module_iri, @function_prop, ~I<http://example.org/Module1#foo/1>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#bar/2>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#baz/0>}
        ])

      [violation] = Cardinality.validate(graph, @module_iri, shape)

      # Should use default message
      assert violation.message ==
               "Property has too many values (expected at most 2, found 3)"
    end

    test "ignores maxCount when nil" do
      # Shape without maxCount constraint
      shape = %PropertyShape{
        id: RDF.bnode("b10"),
        path: @function_prop,
        max_count: nil
      }

      # Graph with many values
      graph =
        RDF.Graph.new([
          {@module_iri, @function_prop, ~I<http://example.org/Module1#foo/1>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#bar/2>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#baz/0>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#qux/3>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#quux/4>}
        ])

      # Should pass (no constraint)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end
  end

  describe "combined minCount and maxCount (exactly N)" do
    test "passes when property has exactly the required count" do
      # Shape requires exactly 1 name (min=1, max=1)
      shape = %PropertyShape{
        id: RDF.bnode("b11"),
        path: @name_prop,
        min_count: 1,
        max_count: 1,
        message: "Module must have exactly one name"
      }

      # Graph with exactly 1 name
      graph = RDF.Graph.new([{@module_iri, @name_prop, "MyModule"}])

      # Should pass
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "fails with minCount violation when too few values" do
      # Shape requires exactly 1 name
      shape = %PropertyShape{
        id: RDF.bnode("b12"),
        path: @name_prop,
        min_count: 1,
        max_count: 1
      }

      # Graph with 0 names
      graph = RDF.Graph.new([])

      # Should fail with minCount violation (not maxCount)
      [violation] = Cardinality.validate(graph, @module_iri, shape)

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MinCountConstraintComponent>

      assert violation.details.min_count == 1
      assert violation.details.actual_count == 0
    end

    test "fails with maxCount violation when too many values" do
      # Shape requires exactly 1 name
      shape = %PropertyShape{
        id: RDF.bnode("b13"),
        path: @name_prop,
        min_count: 1,
        max_count: 1
      }

      # Graph with 2 names
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, "MyModule"},
          {@module_iri, @name_prop, "OtherName"}
        ])

      # Should fail with maxCount violation (not minCount)
      [violation] = Cardinality.validate(graph, @module_iri, shape)

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MaxCountConstraintComponent>

      assert violation.details.max_count == 1
      assert violation.details.actual_count == 2
    end
  end

  describe "edge cases" do
    test "works with blank node focus nodes" do
      # Blank node as focus node
      blank_node = RDF.bnode("module1")

      shape = %PropertyShape{
        id: RDF.bnode("b14"),
        path: @name_prop,
        min_count: 1
      }

      graph = RDF.Graph.new([{blank_node, @name_prop, "MyModule"}])

      # Should pass
      assert [] == Cardinality.validate(graph, blank_node, shape)
    end

    test "works with literal values" do
      # Multiple literal values
      shape = %PropertyShape{
        id: RDF.bnode("b15"),
        path: @name_prop,
        min_count: 1,
        max_count: 2
      }

      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, RDF.XSD.string("MyModule")},
          {@module_iri, @name_prop, RDF.XSD.string("AlternateName")}
        ])

      # Should pass (2 values, within range)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "works with IRI values" do
      # Multiple IRI values
      shape = %PropertyShape{
        id: RDF.bnode("b16"),
        path: @function_prop,
        min_count: 2,
        max_count: 3
      }

      graph =
        RDF.Graph.new([
          {@module_iri, @function_prop, ~I<http://example.org/Module1#foo/1>},
          {@module_iri, @function_prop, ~I<http://example.org/Module1#bar/2>}
        ])

      # Should pass (2 values, within range)
      assert [] == Cardinality.validate(graph, @module_iri, shape)
    end

    test "works when property path not in graph" do
      # Shape requires at least 1 value
      shape = %PropertyShape{
        id: RDF.bnode("b17"),
        path: @name_prop,
        min_count: 1
      }

      # Graph has different property, not the one we're checking
      graph =
        RDF.Graph.new([
          {@module_iri, ~I<http://example.org/otherProperty>, "value"}
        ])

      # Should fail (property not present = 0 values)
      [violation] = Cardinality.validate(graph, @module_iri, shape)

      assert violation.details.actual_count == 0
    end

    test "validates source_shape is set correctly" do
      shape_id = RDF.bnode("shape123")

      shape = %PropertyShape{
        id: shape_id,
        path: @name_prop,
        min_count: 1
      }

      graph = RDF.Graph.new([])

      [violation] = Cardinality.validate(graph, @module_iri, shape)

      # source_shape should match the property shape ID
      assert violation.source_shape == shape_id
    end
  end
end
