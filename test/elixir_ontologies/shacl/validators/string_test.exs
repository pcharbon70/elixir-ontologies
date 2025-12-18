defmodule ElixirOntologies.SHACL.Validators.StringTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.PropertyShape
  alias ElixirOntologies.SHACL.Validators.String

  doctest ElixirOntologies.SHACL.Validators.String

  # Test IRIs and property paths
  @module_iri ~I<http://example.org/Module1>
  @function_iri ~I<http://example.org/Function1>
  @name_prop ~I<https://w3id.org/elixir-code/structure#moduleName>
  @function_name_prop ~I<https://w3id.org/elixir-code/structure#functionName>
  @description_prop ~I<http://example.org/description>

  describe "pattern constraint (sh:pattern)" do
    test "passes when value matches pattern" do
      # Shape requires module name pattern (starts with uppercase)
      shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: @name_prop,
        pattern: ~r/^[A-Z][a-zA-Z0-9_]*$/,
        message: "Module name must be valid Elixir identifier"
      }

      # Graph with valid module name
      graph = RDF.Graph.new([{@module_iri, @name_prop, "MyModule"}])

      # Should pass (matches pattern)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "passes when all values match pattern" do
      # Shape requires uppercase start
      shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/
      }

      # Graph with multiple matching values
      graph =
        RDF.Graph.new([
          {@module_iri, @name_prop, "Alice"},
          {@module_iri, @name_prop, "Bob"},
          {@module_iri, @name_prop, "Charlie"}
        ])

      # Should pass (all match)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "fails when value doesn't match pattern" do
      # Shape requires module name pattern
      shape = %PropertyShape{
        id: RDF.bnode("b3"),
        path: @name_prop,
        pattern: ~r/^[A-Z][a-zA-Z0-9_]*$/,
        message: "Module name must be valid Elixir identifier"
      }

      # Graph with invalid module name (starts with lowercase)
      graph = RDF.Graph.new([{@module_iri, @name_prop, "invalidName"}])

      # Should fail with pattern violation
      [violation] = String.validate(graph, @module_iri, shape)

      assert violation.focus_node == @module_iri
      assert violation.path == @name_prop
      assert violation.severity == :violation
      assert violation.message == "Module name must be valid Elixir identifier"
      assert violation.details.pattern == "^[A-Z][a-zA-Z0-9_]*$"
      assert violation.details.actual_value == "invalidName"

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>
    end

    test "fails for each value that doesn't match pattern" do
      # Shape requires function name pattern (starts with lowercase)
      shape = %PropertyShape{
        id: RDF.bnode("b4"),
        path: @function_name_prop,
        pattern: ~r/^[a-z_][a-z0-9_]*[!?]?$/
      }

      # Graph with 2 invalid and 1 valid function names
      graph =
        RDF.Graph.new([
          {@function_iri, @function_name_prop, "Invalid"},
          {@function_iri, @function_name_prop, "valid_name"},
          {@function_iri, @function_name_prop, "AlsoInvalid"}
        ])

      # Should have 2 violations
      violations = String.validate(graph, @function_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)

      invalid_values = Enum.map(violations, & &1.details.actual_value) |> Enum.sort()
      assert invalid_values == ["AlsoInvalid", "Invalid"]
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b5"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        message: nil
      }

      # Graph with non-matching value
      graph = RDF.Graph.new([{@module_iri, @name_prop, "lowercase"}])

      [violation] = String.validate(graph, @module_iri, shape)

      # Should use default message
      assert violation.message =~ "does not match required pattern"
      assert violation.message =~ "^[A-Z]"
    end

    test "ignores pattern when nil" do
      # Shape without pattern constraint
      shape = %PropertyShape{
        id: RDF.bnode("b6"),
        path: @name_prop,
        pattern: nil
      }

      # Graph with any value
      graph = RDF.Graph.new([{@module_iri, @name_prop, "anything"}])

      # Should pass (no constraint)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "handles complex regex patterns" do
      # Pattern for Elixir function names with optional ! or ?
      pattern = ~r/^[a-z_][a-z0-9_]*[!?]?$/

      shape = %PropertyShape{
        id: RDF.bnode("b7"),
        path: @function_name_prop,
        pattern: pattern
      }

      # Test various function names
      test_cases = [
        {"valid_name", true},
        {"is_valid?", true},
        {"do_something!", true},
        {"_private", true},
        {"snake_case_123", true},
        {"InvalidCamelCase", false},
        {"123invalid", false},
        {"has-dash", false},
        {"multiple!!", false}
      ]

      for {name, should_pass} <- test_cases do
        graph = RDF.Graph.new([{@function_iri, @function_name_prop, name}])
        violations = String.validate(graph, @function_iri, shape)

        if should_pass do
          assert violations == [], "Expected '#{name}' to match pattern"
        else
          assert length(violations) == 1, "Expected '#{name}' to NOT match pattern"
        end
      end
    end

    test "skips non-literal values" do
      # Pattern constraint
      shape = %PropertyShape{
        id: RDF.bnode("b8"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/
      }

      # Graph with IRI value (not a literal)
      graph = RDF.Graph.new([{@module_iri, @name_prop, ~I<http://example.org/IRI>}])

      # Should pass (IRIs are skipped by pattern validator)
      assert [] == String.validate(graph, @module_iri, shape)
    end
  end

  describe "minLength constraint (sh:minLength)" do
    test "passes when value meets minimum length" do
      # Shape requires at least 3 characters
      shape = %PropertyShape{
        id: RDF.bnode("b9"),
        path: @description_prop,
        min_length: 3,
        message: "Description must be at least 3 characters"
      }

      # Graph with 3-character value
      graph = RDF.Graph.new([{@module_iri, @description_prop, "abc"}])

      # Should pass (exactly 3 characters)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "passes when value exceeds minimum length" do
      # Shape requires at least 3 characters
      shape = %PropertyShape{
        id: RDF.bnode("b10"),
        path: @description_prop,
        min_length: 3
      }

      # Graph with long value
      graph = RDF.Graph.new([{@module_iri, @description_prop, "This is a long description"}])

      # Should pass (25 > 3)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "fails when value is too short" do
      # Shape requires at least 5 characters
      shape = %PropertyShape{
        id: RDF.bnode("b11"),
        path: @description_prop,
        min_length: 5,
        message: "Description must be at least 5 characters"
      }

      # Graph with 3-character value
      graph = RDF.Graph.new([{@module_iri, @description_prop, "abc"}])

      # Should fail with minLength violation
      [violation] = String.validate(graph, @module_iri, shape)

      assert violation.focus_node == @module_iri
      assert violation.path == @description_prop
      assert violation.severity == :violation
      assert violation.message == "Description must be at least 5 characters"
      assert violation.details.min_length == 5
      assert violation.details.actual_length == 3
      assert violation.details.actual_value == "abc"

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent>
    end

    test "fails for each value that is too short" do
      # Shape requires at least 4 characters
      shape = %PropertyShape{
        id: RDF.bnode("b12"),
        path: @description_prop,
        min_length: 4
      }

      # Graph with 2 short and 1 long value
      graph =
        RDF.Graph.new([
          {@module_iri, @description_prop, "ab"},
          {@module_iri, @description_prop, "abcde"},
          {@module_iri, @description_prop, "xyz"}
        ])

      # Should have 2 violations
      violations = String.validate(graph, @module_iri, shape)

      assert length(violations) == 2
      assert Enum.all?(violations, fn v -> v.severity == :violation end)

      short_values = Enum.map(violations, & &1.details.actual_value) |> Enum.sort()
      assert short_values == ["ab", "xyz"]
    end

    test "uses default message when property_shape.message is nil" do
      # Shape without custom message
      shape = %PropertyShape{
        id: RDF.bnode("b13"),
        path: @description_prop,
        min_length: 10,
        message: nil
      }

      # Graph with short value
      graph = RDF.Graph.new([{@module_iri, @description_prop, "short"}])

      [violation] = String.validate(graph, @module_iri, shape)

      # Should use default message
      assert violation.message =~ "too short"
      assert violation.message =~ "at least 10"
      assert violation.message =~ "found 5"
    end

    test "ignores minLength when nil" do
      # Shape without minLength constraint
      shape = %PropertyShape{
        id: RDF.bnode("b14"),
        path: @description_prop,
        min_length: nil
      }

      # Graph with any value (even empty)
      graph = RDF.Graph.new([{@module_iri, @description_prop, ""}])

      # Should pass (no constraint)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "handles unicode characters correctly" do
      # Shape requires at least 5 characters
      shape = %PropertyShape{
        id: RDF.bnode("b15"),
        path: @description_prop,
        min_length: 5
      }

      # Test unicode strings
      test_cases = [
        {"hello", 5, true},
        {"héllo", 5, true},
        {"你好世界", 4, false},
        {"你好世界!", 5, true},
        {"🎉🎊🎈", 3, false},
        {"🎉🎊🎈🎁🎀", 5, true}
      ]

      for {text, expected_length, should_pass} <- test_cases do
        graph = RDF.Graph.new([{@module_iri, @description_prop, text}])
        violations = String.validate(graph, @module_iri, shape)

        if should_pass do
          assert violations == [],
                 "Expected '#{text}' (length #{expected_length}) to pass minLength 5"
        else
          assert length(violations) == 1,
                 "Expected '#{text}' (length #{expected_length}) to fail minLength 5"
        end
      end
    end

    test "skips non-literal values" do
      # minLength constraint
      shape = %PropertyShape{
        id: RDF.bnode("b16"),
        path: @description_prop,
        min_length: 10
      }

      # Graph with IRI value (not a literal)
      graph = RDF.Graph.new([{@module_iri, @description_prop, ~I<http://example.org/IRI>}])

      # Should pass (IRIs are skipped by minLength validator)
      assert [] == String.validate(graph, @module_iri, shape)
    end
  end

  describe "combined pattern and minLength constraints" do
    test "passes when both constraints are satisfied" do
      # Shape requires both pattern and minimum length
      shape = %PropertyShape{
        id: RDF.bnode("b17"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        min_length: 3
      }

      # Graph with value matching both constraints
      graph = RDF.Graph.new([{@module_iri, @name_prop, "MyModule"}])

      # Should pass
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "fails with pattern violation when pattern doesn't match" do
      # Shape with both constraints
      shape = %PropertyShape{
        id: RDF.bnode("b18"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        min_length: 3
      }

      # Graph with value that's long enough but doesn't match pattern
      graph = RDF.Graph.new([{@module_iri, @name_prop, "lowercase"}])

      # Should have 1 violation (pattern only)
      [violation] = String.validate(graph, @module_iri, shape)

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>
    end

    test "fails with minLength violation when too short" do
      # Shape with both constraints
      shape = %PropertyShape{
        id: RDF.bnode("b19"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        min_length: 5
      }

      # Graph with value that matches pattern but is too short
      graph = RDF.Graph.new([{@module_iri, @name_prop, "ABC"}])

      # Should have 1 violation (minLength only)
      [violation] = String.validate(graph, @module_iri, shape)

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent>

      assert violation.details.actual_length == 3
    end

    test "returns violations from both constraints" do
      # Shape with both constraints
      shape = %PropertyShape{
        id: RDF.bnode("b20"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        min_length: 10
      }

      # Graph with value that violates both (lowercase and too short)
      graph = RDF.Graph.new([{@module_iri, @name_prop, "abc"}])

      # Should have 2 violations (pattern + minLength)
      violations = String.validate(graph, @module_iri, shape)

      assert length(violations) == 2

      constraint_components =
        Enum.map(violations, & &1.details.constraint_component) |> Enum.sort()

      assert ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent> in constraint_components
      assert ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent> in constraint_components
    end
  end

  describe "edge cases" do
    test "works with blank node focus nodes" do
      blank_node = RDF.bnode("m1")

      shape = %PropertyShape{
        id: RDF.bnode("b21"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/
      }

      graph = RDF.Graph.new([{blank_node, @name_prop, "Module"}])

      assert [] == String.validate(graph, blank_node, shape)
    end

    test "handles empty values list" do
      shape = %PropertyShape{
        id: RDF.bnode("b22"),
        path: @name_prop,
        pattern: ~r/^[A-Z]/,
        min_length: 3
      }

      graph = RDF.Graph.new([])

      # No values = no violations (cardinality validator handles this)
      assert [] == String.validate(graph, @module_iri, shape)
    end

    test "validates source_shape is set correctly" do
      shape_id = RDF.bnode("shape789")

      shape = %PropertyShape{
        id: shape_id,
        path: @name_prop,
        pattern: ~r/^[A-Z]/
      }

      graph = RDF.Graph.new([{@module_iri, @name_prop, "lowercase"}])

      [violation] = String.validate(graph, @module_iri, shape)

      assert violation.source_shape == shape_id
    end

    test "handles empty string" do
      # Pattern that matches empty string
      shape1 = %PropertyShape{
        id: RDF.bnode("b23"),
        path: @description_prop,
        pattern: ~r/^.*$/
      }

      graph = RDF.Graph.new([{@module_iri, @description_prop, ""}])

      # Empty string matches .* pattern
      assert [] == String.validate(graph, @module_iri, shape1)

      # minLength with empty string
      shape2 = %PropertyShape{
        id: RDF.bnode("b24"),
        path: @description_prop,
        min_length: 1
      }

      # Empty string fails minLength 1
      [violation] = String.validate(graph, @module_iri, shape2)
      assert violation.details.actual_length == 0
    end
  end
end
