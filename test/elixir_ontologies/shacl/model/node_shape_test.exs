defmodule ElixirOntologies.SHACL.Model.NodeShapeTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{NodeShape, PropertyShape, SPARQLConstraint}

  describe "struct creation" do
    test "creates node shape with required id" do
      shape = %NodeShape{id: ~I<http://example.org/Shape1>}

      assert shape.id == ~I<http://example.org/Shape1>
      assert shape.target_classes == []
      assert shape.property_shapes == []
      assert shape.sparql_constraints == []
    end

    test "creates node shape with all fields" do
      prop_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<http://example.org/prop1>
      }

      sparql_constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Test constraint",
        select_query: "SELECT $this WHERE { $this ?p ?o }",
        prefixes_graph: nil
      }

      shape = %NodeShape{
        id: ~I<http://example.org/Shape1>,
        target_classes: [~I<http://example.org/Class1>],
        property_shapes: [prop_shape],
        sparql_constraints: [sparql_constraint]
      }

      assert shape.id == ~I<http://example.org/Shape1>
      assert shape.target_classes == [~I<http://example.org/Class1>]
      assert length(shape.property_shapes) == 1
      assert hd(shape.property_shapes) == prop_shape
      assert length(shape.sparql_constraints) == 1
      assert hd(shape.sparql_constraints) == sparql_constraint
    end

    test "creates node shape with blank node id" do
      shape = %NodeShape{id: RDF.bnode("shape1")}

      assert %RDF.BlankNode{} = shape.id
      assert shape.target_classes == []
    end
  end

  describe "real-world usage" do
    test "creates ModuleShape from elixir-shapes.ttl" do
      shape = %NodeShape{
        id: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        target_classes: [~I<https://w3id.org/elixir-code/structure#Module>],
        property_shapes: [],
        sparql_constraints: []
      }

      assert shape.id == ~I<https://w3id.org/elixir-code/shapes#ModuleShape>
      assert ~I<https://w3id.org/elixir-code/structure#Module> in shape.target_classes
    end

    test "creates FunctionShape with multiple target classes" do
      shape = %NodeShape{
        id: ~I<https://w3id.org/elixir-code/shapes#FunctionShape>,
        target_classes: [
          ~I<https://w3id.org/elixir-code/structure#Function>,
          ~I<https://w3id.org/elixir-code/structure#PrivateFunction>
        ]
      }

      assert length(shape.target_classes) == 2
    end
  end
end
