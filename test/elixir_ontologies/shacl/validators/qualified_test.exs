defmodule ElixirOntologies.SHACL.Validators.QualifiedTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape
  alias ElixirOntologies.SHACL.Validators.Qualified

  doctest ElixirOntologies.SHACL.Validators.Qualified

  # Test IRIs
  @genserver_iri ~I<http://example.org/GenServer1>
  @module_iri ~I<http://example.org/Module1>
  @has_function_prop ~I<https://w3id.org/elixir-code/structure#hasFunction>
  @has_child_prop ~I<http://example.org/hasChild>

  # Function IRIs
  @init_fn ~I<http://example.org/Module1#init/1>
  @handle_call_fn ~I<http://example.org/Module1#handle_call/3>
  @handle_cast_fn ~I<http://example.org/Module1#handle_cast/2>
  @terminate_fn ~I<http://example.org/Module1#terminate/2>

  # Class IRIs
  @function_class ~I<https://w3id.org/elixir-code/structure#Function>
  @callback_class ~I<http://example.org/Callback>
  @child_spec_class ~I<http://example.org/ChildSpec>

  describe "qualified value shape constraint" do
    test "passes when exactly minimum qualified values are present" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2,
        message: "Must have at least 2 Functions"
      }

      # Graph with exactly 2 Functions
      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@genserver_iri, @has_function_prop, @handle_call_fn},
          {@init_fn, RDF.type(), @function_class},
          {@handle_call_fn, RDF.type(), @function_class}
        ])

      # Should pass (2 >= 2)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end

    test "passes when more than minimum qualified values are present" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2
      }

      # Graph with 4 Functions
      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@genserver_iri, @has_function_prop, @handle_call_fn},
          {@genserver_iri, @has_function_prop, @handle_cast_fn},
          {@genserver_iri, @has_function_prop, @terminate_fn},
          {@init_fn, RDF.type(), @function_class},
          {@handle_call_fn, RDF.type(), @function_class},
          {@handle_cast_fn, RDF.type(), @function_class},
          {@terminate_fn, RDF.type(), @function_class}
        ])

      # Should pass (4 >= 2)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end

    test "fails when fewer than minimum qualified values are present" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b3"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2,
        message: "Must have at least 2 Functions"
      }

      # Graph with only 1 Function
      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@init_fn, RDF.type(), @function_class}
        ])

      # Should fail with qualified violation
      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      assert violation.focus_node == @genserver_iri
      assert violation.path == @has_function_prop
      assert violation.severity == :violation
      assert violation.message == "Must have at least 2 Functions"
      assert violation.details.qualified_class == @function_class
      assert violation.details.qualified_min_count == 2
      assert violation.details.actual_qualified_count == 1
      assert violation.details.total_values == 1

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#QualifiedMinCountConstraintComponent>
    end

    test "fails when no values have the qualified class" do
      # Shape requires at least 1 Callback
      shape = %PropertyShape{
        id: RDF.bnode("b4"),
        path: @has_function_prop,
        qualified_class: @callback_class,
        qualified_min_count: 1
      }

      # Graph with Functions (not Callbacks)
      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@genserver_iri, @has_function_prop, @handle_call_fn},
          {@init_fn, RDF.type(), @function_class},
          {@handle_call_fn, RDF.type(), @function_class}
        ])

      # Should fail (0 Callbacks)
      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      assert violation.details.qualified_class == @callback_class
      assert violation.details.actual_qualified_count == 0
      assert violation.details.total_values == 2
    end

    test "counts only values with qualified class, ignoring others" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b5"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2
      }

      # Graph with 2 Functions and 2 Callbacks
      callback1 = ~I<http://example.org/callback1>
      callback2 = ~I<http://example.org/callback2>

      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@genserver_iri, @has_function_prop, @handle_call_fn},
          {@genserver_iri, @has_function_prop, callback1},
          {@genserver_iri, @has_function_prop, callback2},
          {@init_fn, RDF.type(), @function_class},
          {@handle_call_fn, RDF.type(), @function_class},
          {callback1, RDF.type(), @callback_class},
          {callback2, RDF.type(), @callback_class}
        ])

      # Should pass (2 Functions, 4 total values)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b6"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 3,
        message: nil
      }

      # Graph with only 1 Function
      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@init_fn, RDF.type(), @function_class}
        ])

      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      # Should use default message
      assert violation.message =~ "too few values of required type"
      assert violation.message =~ "at least 3"
      assert violation.message =~ "found 1"
    end

    test "ignores qualified constraint when qualified_class is nil" do
      # Shape without qualified_class
      shape = %PropertyShape{
        id: RDF.bnode("b7"),
        path: @has_function_prop,
        qualified_class: nil,
        qualified_min_count: 2
      }

      # Graph with any values
      graph = RDF.Graph.new([{@genserver_iri, @has_function_prop, @init_fn}])

      # Should pass (no constraint)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end

    test "ignores qualified constraint when qualified_min_count is nil" do
      # Shape without qualified_min_count
      shape = %PropertyShape{
        id: RDF.bnode("b8"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: nil
      }

      # Graph with any values
      graph = RDF.Graph.new([{@genserver_iri, @has_function_prop, @init_fn}])

      # Should pass (no constraint)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end
  end

  describe "edge cases" do
    test "works with blank node focus nodes" do
      blank_node = RDF.bnode("gs1")

      shape = %PropertyShape{
        id: RDF.bnode("b9"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 1
      }

      graph =
        RDF.Graph.new([
          {blank_node, @has_function_prop, @init_fn},
          {@init_fn, RDF.type(), @function_class}
        ])

      assert [] == Qualified.validate(graph, blank_node, shape)
    end

    test "handles empty values list" do
      # Shape requires at least 1 qualified value
      shape = %PropertyShape{
        id: RDF.bnode("b10"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 1
      }

      # Graph with no values
      graph = RDF.Graph.new([])

      # Should fail (0 < 1)
      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      assert violation.details.actual_qualified_count == 0
      assert violation.details.total_values == 0
    end

    test "works with values that have no rdf:type" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b11"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2
      }

      # Graph with 2 typed Functions and 2 untyped values
      untyped1 = ~I<http://example.org/untyped1>
      untyped2 = ~I<http://example.org/untyped2>

      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@genserver_iri, @has_function_prop, @handle_call_fn},
          {@genserver_iri, @has_function_prop, untyped1},
          {@genserver_iri, @has_function_prop, untyped2},
          {@init_fn, RDF.type(), @function_class},
          {@handle_call_fn, RDF.type(), @function_class}
        ])

      # Should pass (2 typed Functions)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end

    test "works with values that are wrong class" do
      # Shape requires at least 2 Functions
      shape = %PropertyShape{
        id: RDF.bnode("b12"),
        path: @has_child_prop,
        qualified_class: @child_spec_class,
        qualified_min_count: 2
      }

      # Graph with 1 ChildSpec and 3 other things
      child1 = ~I<http://example.org/child1>
      other1 = ~I<http://example.org/other1>
      other2 = ~I<http://example.org/other2>
      other3 = ~I<http://example.org/other3>
      other_class = ~I<http://example.org/OtherClass>

      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_child_prop, child1},
          {@genserver_iri, @has_child_prop, other1},
          {@genserver_iri, @has_child_prop, other2},
          {@genserver_iri, @has_child_prop, other3},
          {child1, RDF.type(), @child_spec_class},
          {other1, RDF.type(), other_class},
          {other2, RDF.type(), other_class},
          {other3, RDF.type(), other_class}
        ])

      # Should fail (only 1 ChildSpec, need 2)
      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      assert violation.details.actual_qualified_count == 1
      assert violation.details.total_values == 4
    end

    test "validates source_shape is set correctly" do
      shape_id = RDF.bnode("shape111")

      shape = %PropertyShape{
        id: shape_id,
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 2
      }

      graph =
        RDF.Graph.new([
          {@genserver_iri, @has_function_prop, @init_fn},
          {@init_fn, RDF.type(), @function_class}
        ])

      [violation] = Qualified.validate(graph, @genserver_iri, shape)

      assert violation.source_shape == shape_id
    end

    test "handles qualified_min_count of 0" do
      # Shape requires at least 0 Functions (always passes)
      shape = %PropertyShape{
        id: RDF.bnode("b13"),
        path: @has_function_prop,
        qualified_class: @function_class,
        qualified_min_count: 0
      }

      # Graph with no Functions
      graph = RDF.Graph.new([])

      # Should pass (0 >= 0)
      assert [] == Qualified.validate(graph, @genserver_iri, shape)
    end
  end
end
