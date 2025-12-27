defmodule ElixirOntologies.SHACL.Validators.TypeTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape
  alias ElixirOntologies.SHACL.Validators.Type

  doctest ElixirOntologies.SHACL.Validators.Type

  # Test IRIs and property paths
  @function_iri ~I<http://example.org/Function1>
  @module_iri ~I<http://example.org/Module1>
  @arity_prop ~I<https://w3id.org/elixir-code/structure#arity>
  @name_prop ~I<https://w3id.org/elixir-code/structure#moduleName>
  @has_function_prop ~I<https://w3id.org/elixir-code/structure#hasFunction>

  # Class IRIs
  @function_class ~I<https://w3id.org/elixir-code/structure#Function>
  @module_class ~I<https://w3id.org/elixir-code/structure#Module>

  # XSD Datatype IRIs
  @xsd_non_negative_integer ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>
  @xsd_string ~I<http://www.w3.org/2001/XMLSchema#string>
  @xsd_integer ~I<http://www.w3.org/2001/XMLSchema#integer>
  @xsd_boolean ~I<http://www.w3.org/2001/XMLSchema#boolean>
  @xsd_date ~I<http://www.w3.org/2001/XMLSchema#date>

  describe "datatype constraint (sh:datatype)" do
    test "passes when value has correct datatype" do
      # Shape requires xsd:nonNegativeInteger
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer,
        message: "Arity must be a non-negative integer"
      }

      # Graph with correct datatype
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(2, datatype: @xsd_non_negative_integer)}
        ])

      # Should pass (no violations)
      assert [] == Type.validate(graph, @function_iri, shape)
    end

    test "passes when all values have correct datatype" do
      # Shape requires xsd:string
      shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: @name_prop,
        datatype: @xsd_string
      }

      # Graph with multiple string values
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, RDF.Literal.new("MyModule", datatype: @xsd_string)},
          {@module_iri, @name_prop, RDF.Literal.new("AlternateName", datatype: @xsd_string)}
        ])

      # Should pass (all strings)
      assert [] == Type.validate(graph, @module_iri, shape)
    end

    test "fails when value has wrong datatype" do
      # Shape requires xsd:nonNegativeInteger
      shape = %PropertyShape{
        id: RDF.bnode("b3"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer,
        message: "Arity must be a non-negative integer"
      }

      # Graph with string value (wrong datatype)
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new("two", datatype: @xsd_string)}
        ])

      # Should fail with datatype violation
      [violation] = Type.validate(graph, @function_iri, shape)

      assert violation.focus_node == @function_iri
      assert violation.path == @arity_prop
      assert violation.severity == :violation
      assert violation.message == "Arity must be a non-negative integer"
      assert violation.details.expected_datatype == @xsd_non_negative_integer

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#DatatypeConstraintComponent>
    end

    test "fails when value is IRI instead of literal" do
      # Shape requires xsd:string
      shape = %PropertyShape{
        id: RDF.bnode("b4"),
        path: @name_prop,
        datatype: @xsd_string
      }

      # Graph with IRI value (not a literal)
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, ~I<http://example.org/NotALiteral>}
        ])

      # Should fail (IRI is not a literal)
      [violation] = Type.validate(graph, @module_iri, shape)

      assert violation.details.expected_datatype == @xsd_string
      assert violation.details.actual_value == ~I<http://example.org/NotALiteral>
    end

    test "fails for each value with wrong datatype" do
      # Shape requires xsd:nonNegativeInteger
      shape = %PropertyShape{
        id: RDF.bnode("b5"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer
      }

      # Graph with 2 wrong values and 1 correct value
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new("one", datatype: @xsd_string)},
          {@function_iri, @arity_prop, RDF.Literal.new(2, datatype: @xsd_non_negative_integer)},
          {@function_iri, @arity_prop, RDF.Literal.new("three", datatype: @xsd_string)}
        ])

      # Should have 2 violations (the 2 strings)
      violations = Type.validate(graph, @function_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b6"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer,
        message: nil
      }

      # Graph with wrong datatype
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new("bad", datatype: @xsd_string)}
        ])

      [violation] = Type.validate(graph, @function_iri, shape)

      # Should use default message
      assert violation.message =~ "does not have required datatype"
      assert violation.message =~ "nonNegativeInteger"
    end

    test "ignores datatype when nil" do
      # Shape without datatype constraint
      shape = %PropertyShape{
        id: RDF.bnode("b7"),
        path: @arity_prop,
        datatype: nil
      }

      # Graph with any datatype
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new("anything", datatype: @xsd_string)}
        ])

      # Should pass (no constraint)
      assert [] == Type.validate(graph, @function_iri, shape)
    end

    test "handles various XSD datatypes correctly" do
      test_cases = [
        {@xsd_integer, RDF.Literal.new(42, datatype: @xsd_integer), true},
        {@xsd_integer, RDF.Literal.new("42", datatype: @xsd_string), false},
        {@xsd_boolean, RDF.Literal.new(true, datatype: @xsd_boolean), true},
        {@xsd_boolean, RDF.Literal.new("true", datatype: @xsd_string), false},
        {@xsd_date, RDF.Literal.new("2024-01-01", datatype: @xsd_date), true},
        {@xsd_date, RDF.Literal.new("2024-01-01", datatype: @xsd_string), false}
      ]

      for {expected_type, value, should_pass} <- test_cases do
        shape = %PropertyShape{
          id: RDF.bnode(),
          path: @arity_prop,
          datatype: expected_type
        }

        graph = RDF.Graph.new([{@function_iri, @arity_prop, value}])

        violations = Type.validate(graph, @function_iri, shape)

        if should_pass do
          assert violations == [],
                 "Expected #{inspect(value)} to match #{inspect(expected_type)}"
        else
          assert length(violations) == 1,
                 "Expected #{inspect(value)} to NOT match #{inspect(expected_type)}"
        end
      end
    end
  end

  describe "class constraint (sh:class)" do
    test "passes when value is instance of required class" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b8"),
        path: @has_function_prop,
        class: @function_class,
        message: "Value must be a Function"
      }

      # Graph with Function instance
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, @function_iri},
          {@function_iri, RDF.type(), @function_class}
        ])

      # Should pass
      assert [] == Type.validate(graph, @module_iri, shape)
    end

    test "passes when all values are instances of required class" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b9"),
        path: @has_function_prop,
        class: @function_class
      }

      # Graph with 3 Function instances
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/Function1>},
          {@module_iri, @has_function_prop, ~I<http://example.org/Function2>},
          {@module_iri, @has_function_prop, ~I<http://example.org/Function3>},
          {~I<http://example.org/Function1>, RDF.type(), @function_class},
          {~I<http://example.org/Function2>, RDF.type(), @function_class},
          {~I<http://example.org/Function3>, RDF.type(), @function_class}
        ])

      # Should pass (all are Functions)
      assert [] == Type.validate(graph, @module_iri, shape)
    end

    test "fails when value is not instance of required class" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b10"),
        path: @has_function_prop,
        class: @function_class,
        message: "Value must be a Function"
      }

      # Graph with Module instance (wrong class)
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/WrongClass>},
          {~I<http://example.org/WrongClass>, RDF.type(), @module_class}
        ])

      # Should fail with class violation
      [violation] = Type.validate(graph, @module_iri, shape)

      assert violation.focus_node == @module_iri
      assert violation.path == @has_function_prop
      assert violation.severity == :violation
      assert violation.message == "Value must be a Function"
      assert violation.details.expected_class == @function_class

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#ClassConstraintComponent>
    end

    test "fails when value has no rdf:type" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b11"),
        path: @has_function_prop,
        class: @function_class
      }

      # Graph with value that has no rdf:type
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/Untyped>}
        ])

      # Should fail (no type means not an instance)
      [violation] = Type.validate(graph, @module_iri, shape)

      assert violation.details.expected_class == @function_class
      assert violation.details.actual_value == ~I<http://example.org/Untyped>
    end

    test "fails when value is a literal" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b12"),
        path: @has_function_prop,
        class: @function_class
      }

      # Graph with literal value (literals can't be instances)
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop,
           RDF.Literal.new("not a resource", datatype: @xsd_string)}
        ])

      # Should fail (literals can't have rdf:type)
      [violation] = Type.validate(graph, @module_iri, shape)

      assert violation.details.expected_class == @function_class
    end

    test "fails for each value not in required class" do
      # Shape requires Function class
      shape = %PropertyShape{
        id: RDF.bnode("b13"),
        path: @has_function_prop,
        class: @function_class
      }

      # Graph with 2 wrong and 1 correct
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/Function1>},
          {@module_iri, @has_function_prop, ~I<http://example.org/Module1>},
          {@module_iri, @has_function_prop, ~I<http://example.org/Module2>},
          {~I<http://example.org/Function1>, RDF.type(), @function_class},
          {~I<http://example.org/Module1>, RDF.type(), @module_class},
          {~I<http://example.org/Module2>, RDF.type(), @module_class}
        ])

      # Should have 2 violations
      violations = Type.validate(graph, @module_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b14"),
        path: @has_function_prop,
        class: @function_class,
        message: nil
      }

      # Graph with wrong class
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, @module_iri},
          {@module_iri, RDF.type(), @module_class}
        ])

      [violation] = Type.validate(graph, @module_iri, shape)

      # Should use default message
      assert violation.message =~ "not an instance of class"
      assert violation.message =~ "Function"
    end

    test "ignores class when nil" do
      # Shape without class constraint
      shape = %PropertyShape{
        id: RDF.bnode("b15"),
        path: @has_function_prop,
        class: nil
      }

      # Graph with any value
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/Anything>}
        ])

      # Should pass (no constraint)
      assert [] == Type.validate(graph, @module_iri, shape)
    end
  end

  describe "combined datatype and class constraints" do
    test "passes when both constraints are satisfied" do
      # This is an unusual case (typically either datatype OR class, not both)
      # but the validator should handle it gracefully
      shape = %PropertyShape{
        id: RDF.bnode("b16"),
        path: @has_function_prop,
        datatype: nil,
        class: @function_class
      }

      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, @function_iri},
          {@function_iri, RDF.type(), @function_class}
        ])

      assert [] == Type.validate(graph, @module_iri, shape)
    end

    test "returns violations from both constraints" do
      # Shape with both constraints (unusual but should work)
      shape = %PropertyShape{
        id: RDF.bnode("b17"),
        path: @has_function_prop,
        datatype: @xsd_string,
        class: @function_class
      }

      # Value is an IRI, not a string, and not an instance of Function
      graph =
        RDF.Graph.new([
          {@module_iri, @has_function_prop, ~I<http://example.org/NotStringNotFunction>}
        ])

      # Should have 2 violations (datatype + class)
      violations = Type.validate(graph, @module_iri, shape)

      assert length(violations) == 2

      constraint_components =
        Enum.map(violations, & &1.details.constraint_component) |> Enum.sort()

      assert ~I<http://www.w3.org/ns/shacl#ClassConstraintComponent> in constraint_components

      assert ~I<http://www.w3.org/ns/shacl#DatatypeConstraintComponent> in constraint_components
    end
  end

  describe "edge cases" do
    test "works with blank node focus nodes" do
      blank_node = RDF.bnode("fn1")

      shape = %PropertyShape{
        id: RDF.bnode("b18"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer
      }

      graph =
        RDF.Graph.new([
          {blank_node, @arity_prop, RDF.Literal.new(0, datatype: @xsd_non_negative_integer)}
        ])

      assert [] == Type.validate(graph, blank_node, shape)
    end

    test "handles empty values list" do
      shape = %PropertyShape{
        id: RDF.bnode("b19"),
        path: @arity_prop,
        datatype: @xsd_non_negative_integer
      }

      graph = RDF.Graph.new([])

      # No values = no violations (cardinality validator handles this)
      assert [] == Type.validate(graph, @function_iri, shape)
    end

    test "validates source_shape is set correctly" do
      shape_id = RDF.bnode("shape456")

      shape = %PropertyShape{
        id: shape_id,
        path: @arity_prop,
        datatype: @xsd_non_negative_integer
      }

      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new("bad", datatype: @xsd_string)}
        ])

      [violation] = Type.validate(graph, @function_iri, shape)

      assert violation.source_shape == shape_id
    end
  end
end
