defmodule ElixirOntologies.SHACL.Validators.ValueTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape
  alias ElixirOntologies.SHACL.Validators.Value

  doctest ElixirOntologies.SHACL.Validators.Value

  # Test IRIs and property paths
  @supervisor_iri ~I<http://example.org/Supervisor1>
  @function_iri ~I<http://example.org/Function1>
  @strategy_prop ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>
  @restart_prop ~I<https://w3id.org/elixir-code/otp#restartStrategy>
  @arity_prop ~I<https://w3id.org/elixir-code/structure#arity>
  @flag_prop ~I<http://example.org/flag>

  # OTP Strategy IRIs
  @one_for_one ~I<https://w3id.org/elixir-code/otp#OneForOne>
  @one_for_all ~I<https://w3id.org/elixir-code/otp#OneForAll>
  @rest_for_one ~I<https://w3id.org/elixir-code/otp#RestForOne>

  # Restart strategy IRIs
  @permanent ~I<https://w3id.org/elixir-code/otp#Permanent>
  @transient ~I<https://w3id.org/elixir-code/otp#Transient>
  @temporary ~I<https://w3id.org/elixir-code/otp#Temporary>

  # XSD Datatype IRIs
  @xsd_non_negative_integer ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>

  describe "in constraint (sh:in)" do
    test "passes when value is in allowed list" do
      # Shape requires one of three supervisor strategies
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: @strategy_prop,
        in: [@one_for_one, @one_for_all, @rest_for_one],
        message: "Supervisor strategy must be one of the allowed values"
      }

      # Graph with allowed value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_one}])

      # Should pass (value in list)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "passes when all values are in allowed list" do
      # Shape with enumeration
      shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: @restart_prop,
        in: [@permanent, @transient, @temporary]
      }

      # Graph with multiple allowed values
      graph =
        RDF.Graph.new([
          {@supervisor_iri, @restart_prop, @permanent},
          {@supervisor_iri, @restart_prop, @transient}
        ])

      # Should pass (all in list)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "fails when value is not in allowed list" do
      # Shape with enumeration
      shape = %PropertyShape{
        id: RDF.bnode("b3"),
        path: @strategy_prop,
        in: [@one_for_one, @one_for_all],
        message: "Invalid supervisor strategy"
      }

      # Graph with disallowed value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @rest_for_one}])

      # Should fail with in violation
      [violation] = Value.validate(graph, @supervisor_iri, shape)

      assert violation.focus_node == @supervisor_iri
      assert violation.path == @strategy_prop
      assert violation.severity == :violation
      assert violation.message == "Invalid supervisor strategy"
      assert violation.details.actual_value == @rest_for_one
      assert @one_for_one in violation.details.allowed_values
      assert @one_for_all in violation.details.allowed_values

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#InConstraintComponent>
    end

    test "fails for each value not in allowed list" do
      # Shape with enumeration
      shape = %PropertyShape{
        id: RDF.bnode("b4"),
        path: @restart_prop,
        in: [@permanent, @transient]
      }

      # Graph with 2 disallowed and 1 allowed value
      invalid_iri = ~I<http://example.org/InvalidStrategy>

      graph =
        RDF.Graph.new([
          {@supervisor_iri, @restart_prop, @permanent},
          {@supervisor_iri, @restart_prop, @temporary},
          {@supervisor_iri, @restart_prop, invalid_iri}
        ])

      # Should have 2 violations
      violations = Value.validate(graph, @supervisor_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)

      invalid_values = Enum.map(violations, & &1.details.actual_value) |> Enum.sort()
      assert invalid_values == Enum.sort([@temporary, invalid_iri])
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b5"),
        path: @strategy_prop,
        in: [@one_for_one],
        message: nil
      }

      # Graph with disallowed value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_all}])

      [violation] = Value.validate(graph, @supervisor_iri, shape)

      # Should use default message
      assert violation.message =~ "not one of the allowed values"
    end

    test "ignores in constraint when empty list" do
      # Shape with empty in list (no constraint)
      shape = %PropertyShape{
        id: RDF.bnode("b6"),
        path: @strategy_prop,
        in: []
      }

      # Graph with any value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_one}])

      # Should pass (empty list = no constraint)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "works with literal values in enumeration" do
      # Shape with string literals in enumeration (RDF.Graph converts to RDF literals)
      green_lit = RDF.literal("green")
      red_lit = RDF.literal("red")
      blue_lit = RDF.literal("blue")
      yellow_lit = RDF.literal("yellow")

      shape = %PropertyShape{
        id: RDF.bnode("b7"),
        path: @flag_prop,
        in: [red_lit, green_lit, blue_lit]
      }

      # Graph with allowed literal
      graph = RDF.Graph.new([{@supervisor_iri, @flag_prop, green_lit}])

      # Should pass
      assert [] == Value.validate(graph, @supervisor_iri, shape)

      # Graph with disallowed literal
      graph2 = RDF.Graph.new([{@supervisor_iri, @flag_prop, yellow_lit}])

      # Should fail
      [violation] = Value.validate(graph2, @supervisor_iri, shape)
      assert violation.details.actual_value == yellow_lit
    end

    test "distinguishes between IRIs and literals" do
      # Shape allowing only IRIs
      shape = %PropertyShape{
        id: RDF.bnode("b8"),
        path: @strategy_prop,
        in: [@one_for_one, @one_for_all]
      }

      # Graph with literal (not in IRI list)
      one_for_one_lit = RDF.literal("OneForOne")
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, one_for_one_lit}])

      # Should fail (literal is not same as IRI)
      [violation] = Value.validate(graph, @supervisor_iri, shape)
      assert violation.details.actual_value == one_for_one_lit
    end
  end

  describe "hasValue constraint (sh:hasValue)" do
    test "passes when required value is present" do
      # Shape requires specific value to be present
      shape = %PropertyShape{
        id: RDF.bnode("b9"),
        path: @strategy_prop,
        has_value: @one_for_one,
        message: "Must have OneForOne strategy"
      }

      # Graph with required value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_one}])

      # Should pass
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "passes when required value is one of multiple values" do
      # Shape requires specific value
      shape = %PropertyShape{
        id: RDF.bnode("b10"),
        path: @restart_prop,
        has_value: @permanent
      }

      # Graph with required value among others
      graph =
        RDF.Graph.new([
          {@supervisor_iri, @restart_prop, @transient},
          {@supervisor_iri, @restart_prop, @permanent},
          {@supervisor_iri, @restart_prop, @temporary}
        ])

      # Should pass (permanent is present)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "fails when required value is missing" do
      # Shape requires specific value
      shape = %PropertyShape{
        id: RDF.bnode("b11"),
        path: @strategy_prop,
        has_value: @one_for_one,
        message: "Must have OneForOne strategy"
      }

      # Graph with different value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_all}])

      # Should fail with hasValue violation
      [violation] = Value.validate(graph, @supervisor_iri, shape)

      assert violation.focus_node == @supervisor_iri
      assert violation.path == @strategy_prop
      assert violation.severity == :violation
      assert violation.message == "Must have OneForOne strategy"
      assert violation.details.required_value == @one_for_one

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#HasValueConstraintComponent>
    end

    test "fails when property has no values" do
      # Shape requires specific value
      shape = %PropertyShape{
        id: RDF.bnode("b12"),
        path: @strategy_prop,
        has_value: @one_for_one
      }

      # Graph with no values for property
      graph = RDF.Graph.new([])

      # Should fail (required value not present)
      [violation] = Value.validate(graph, @supervisor_iri, shape)

      assert violation.details.required_value == @one_for_one
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b13"),
        path: @strategy_prop,
        has_value: @one_for_one,
        message: nil
      }

      # Graph missing required value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_all}])

      [violation] = Value.validate(graph, @supervisor_iri, shape)

      # Should use default message
      assert violation.message =~ "Required value is missing"
    end

    test "ignores hasValue when nil" do
      # Shape without hasValue constraint
      shape = %PropertyShape{
        id: RDF.bnode("b14"),
        path: @strategy_prop,
        has_value: nil
      }

      # Graph with any value or no value
      graph = RDF.Graph.new([])

      # Should pass (no constraint)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "works with literal required values" do
      # Shape requiring specific literal
      enabled_lit = RDF.literal("enabled")
      disabled_lit = RDF.literal("disabled")

      shape = %PropertyShape{
        id: RDF.bnode("b15"),
        path: @flag_prop,
        has_value: enabled_lit
      }

      # Graph with required literal
      graph = RDF.Graph.new([{@supervisor_iri, @flag_prop, enabled_lit}])

      # Should pass
      assert [] == Value.validate(graph, @supervisor_iri, shape)

      # Graph without required literal
      graph2 = RDF.Graph.new([{@supervisor_iri, @flag_prop, disabled_lit}])

      # Should fail
      [violation] = Value.validate(graph2, @supervisor_iri, shape)
      assert violation.details.required_value == enabled_lit
    end
  end

  describe "maxInclusive constraint (sh:maxInclusive)" do
    test "passes when value equals maximum" do
      # Shape requires arity <= 255
      shape = %PropertyShape{
        id: RDF.bnode("b16"),
        path: @arity_prop,
        max_inclusive: 255,
        message: "Function arity must be <= 255"
      }

      # Graph with maximum value
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(255, datatype: @xsd_non_negative_integer)}
        ])

      # Should pass (255 == 255)
      assert [] == Value.validate(graph, @function_iri, shape)
    end

    test "passes when value is less than maximum" do
      # Shape requires arity <= 255
      shape = %PropertyShape{
        id: RDF.bnode("b17"),
        path: @arity_prop,
        max_inclusive: 255
      }

      # Graph with value below maximum
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(10, datatype: @xsd_non_negative_integer)}
        ])

      # Should pass (10 < 255)
      assert [] == Value.validate(graph, @function_iri, shape)
    end

    test "fails when value exceeds maximum" do
      # Shape requires arity <= 255
      shape = %PropertyShape{
        id: RDF.bnode("b18"),
        path: @arity_prop,
        max_inclusive: 255,
        message: "Function arity must be <= 255"
      }

      # Graph with value above maximum
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(300, datatype: @xsd_non_negative_integer)}
        ])

      # Should fail with maxInclusive violation
      [violation] = Value.validate(graph, @function_iri, shape)

      assert violation.focus_node == @function_iri
      assert violation.path == @arity_prop
      assert violation.severity == :violation
      assert violation.message == "Function arity must be <= 255"
      assert violation.details.max_inclusive == 255
      assert violation.details.actual_value == 300

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MaxInclusiveConstraintComponent>
    end

    test "fails for each value exceeding maximum" do
      # Shape with max constraint
      shape = %PropertyShape{
        id: RDF.bnode("b19"),
        path: @arity_prop,
        max_inclusive: 10
      }

      # Graph with 2 values above and 1 below max
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(5, datatype: @xsd_non_negative_integer)},
          {@function_iri, @arity_prop, RDF.Literal.new(15, datatype: @xsd_non_negative_integer)},
          {@function_iri, @arity_prop, RDF.Literal.new(20, datatype: @xsd_non_negative_integer)}
        ])

      # Should have 2 violations
      violations = Value.validate(graph, @function_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)

      exceeding_values = Enum.map(violations, & &1.details.actual_value) |> Enum.sort()
      assert exceeding_values == [15, 20]
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b20"),
        path: @arity_prop,
        max_inclusive: 100,
        message: nil
      }

      # Graph with value above max
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop, RDF.Literal.new(150, datatype: @xsd_non_negative_integer)}
        ])

      [violation] = Value.validate(graph, @function_iri, shape)

      # Should use default message
      assert violation.message =~ "exceeds maximum"
      assert violation.message =~ "<= 100"
      assert violation.message =~ "found 150"
    end

    test "ignores maxInclusive when nil" do
      # Shape without maxInclusive constraint
      shape = %PropertyShape{
        id: RDF.bnode("b21"),
        path: @arity_prop,
        max_inclusive: nil
      }

      # Graph with any numeric value
      graph =
        RDF.Graph.new([
          {@function_iri, @arity_prop,
           RDF.Literal.new(999999, datatype: @xsd_non_negative_integer)}
        ])

      # Should pass (no constraint)
      assert [] == Value.validate(graph, @function_iri, shape)
    end

    test "works with integer boundaries" do
      # Shape with integer max
      shape = %PropertyShape{
        id: RDF.bnode("b22"),
        path: @arity_prop,
        max_inclusive: 10
      }

      # Test various integer values
      test_cases = [
        {8, true},
        {10, true},
        {11, false},
        {15, false}
      ]

      for {value, should_pass} <- test_cases do
        graph =
          RDF.Graph.new([
            {@function_iri, @arity_prop, RDF.Literal.new(value, datatype: @xsd_non_negative_integer)}
          ])

        violations = Value.validate(graph, @function_iri, shape)

        if should_pass do
          assert violations == [], "Expected #{value} to pass maxInclusive 10"
        else
          assert length(violations) == 1, "Expected #{value} to fail maxInclusive 10"
        end
      end
    end

    test "skips non-numeric values" do
      # maxInclusive constraint
      shape = %PropertyShape{
        id: RDF.bnode("b23"),
        path: @arity_prop,
        max_inclusive: 10
      }

      # Graph with non-numeric literal
      graph = RDF.Graph.new([{@function_iri, @arity_prop, "not a number"}])

      # Should pass (non-numeric values are skipped)
      assert [] == Value.validate(graph, @function_iri, shape)
    end
  end

  describe "combined constraints" do
    test "passes when all constraints are satisfied" do
      # Shape with multiple value constraints
      shape = %PropertyShape{
        id: RDF.bnode("b24"),
        path: @strategy_prop,
        in: [@one_for_one, @one_for_all, @rest_for_one],
        has_value: @one_for_one
      }

      # Graph with value satisfying both constraints
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_one}])

      # Should pass
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "returns violations from multiple constraints" do
      # Shape with in and hasValue
      shape = %PropertyShape{
        id: RDF.bnode("b25"),
        path: @strategy_prop,
        in: [@one_for_one, @one_for_all],
        has_value: @rest_for_one
      }

      # Graph with value in list but missing required value
      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_one}])

      # Should have 1 violation (hasValue not satisfied)
      [violation] = Value.validate(graph, @supervisor_iri, shape)

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#HasValueConstraintComponent>
    end
  end

  describe "edge cases" do
    test "works with blank node focus nodes" do
      blank_node = RDF.bnode("s1")

      shape = %PropertyShape{
        id: RDF.bnode("b26"),
        path: @strategy_prop,
        in: [@one_for_one]
      }

      graph = RDF.Graph.new([{blank_node, @strategy_prop, @one_for_one}])

      assert [] == Value.validate(graph, blank_node, shape)
    end

    test "handles empty values list" do
      shape = %PropertyShape{
        id: RDF.bnode("b27"),
        path: @strategy_prop,
        in: [@one_for_one],
        max_inclusive: 255
      }

      graph = RDF.Graph.new([])

      # No values = no violations for in/maxInclusive (cardinality handles this)
      # hasValue would fail with empty list (tested separately)
      assert [] == Value.validate(graph, @supervisor_iri, shape)
    end

    test "validates source_shape is set correctly" do
      shape_id = RDF.bnode("shape999")

      shape = %PropertyShape{
        id: shape_id,
        path: @strategy_prop,
        in: [@one_for_one]
      }

      graph = RDF.Graph.new([{@supervisor_iri, @strategy_prop, @one_for_all}])

      [violation] = Value.validate(graph, @supervisor_iri, shape)

      assert violation.source_shape == shape_id
    end
  end
end
