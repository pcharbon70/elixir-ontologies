defmodule ElixirOntologies.SHACL.Model.ValidationResultTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.ValidationResult

  describe "struct creation" do
    test "creates validation result with all fields" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Constraint violated",
        details: %{expected: "foo", actual: "bar"}
      }

      assert result.focus_node == ~I<http://example.org/Node1>
      assert result.path == ~I<http://example.org/prop1>
      assert result.source_shape == ~I<http://example.org/Shape1>
      assert result.severity == :violation
      assert result.message == "Constraint violated"
      assert result.details == %{expected: "foo", actual: "bar"}
    end

    test "creates validation result with blank node focus_node" do
      result = %ValidationResult{
        focus_node: RDF.bnode("node1"),
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      assert %RDF.BlankNode{} = result.focus_node
    end

    test "creates validation result with literal focus_node" do
      result = %ValidationResult{
        focus_node: RDF.literal("test value"),
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      assert %RDF.Literal{} = result.focus_node
    end

    test "creates validation result without path for node-level constraint" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: nil,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Node constraint violated",
        details: %{}
      }

      assert result.path == nil
    end
  end

  describe "severity levels" do
    test "creates result with :violation severity" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      assert result.severity == :violation
    end

    test "creates result with :warning severity" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :warning,
        message: "Warning",
        details: %{}
      }

      assert result.severity == :warning
    end

    test "creates result with :info severity" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :info,
        message: "Info",
        details: %{}
      }

      assert result.severity == :info
    end
  end

  describe "details field" do
    test "stores arbitrary map data" do
      details = %{
        constraint_component: ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>,
        expected_pattern: "^[A-Z].*",
        actual_value: "badValue"
      }

      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Pattern mismatch",
        details: details
      }

      assert result.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>

      assert result.details.expected_pattern == "^[A-Z].*"
      assert result.details.actual_value == "badValue"
    end

    test "can have empty details map" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      assert result.details == %{}
    end
  end

  describe "real-world usage from elixir-shapes.ttl validation" do
    test "cardinality violation" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Module must have exactly one name",
        details: %{
          min_count: 1,
          max_count: 1,
          actual_count: 0
        }
      }

      assert result.details.min_count == 1
      assert result.details.actual_count == 0
    end

    test "pattern violation" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Module name must match pattern ^[A-Z][a-zA-Z0-9_]*$",
        details: %{
          constraint_component: ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>,
          actual_value: "invalid_name"
        }
      }

      assert result.message =~ "pattern"
      assert result.details.actual_value == "invalid_name"
    end

    test "datatype violation" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: ~I<https://w3id.org/elixir-code/structure#arity>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionShape>,
        severity: :violation,
        message: "Arity must be a non-negative integer",
        details: %{
          expected_datatype: ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>,
          actual_value: "not a number"
        }
      }

      assert result.details.expected_datatype ==
               ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>
    end

    test "value enumeration violation" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MySupervisor>,
        path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#SupervisorShape>,
        severity: :violation,
        message: "Supervisor strategy must be one of the allowed values",
        details: %{
          allowed_values: [
            ~I<https://w3id.org/elixir-code/otp#OneForOne>,
            ~I<https://w3id.org/elixir-code/otp#OneForAll>
          ],
          actual_value: ~I<https://w3id.org/elixir-code/otp#InvalidStrategy>
        }
      }

      assert length(result.details.allowed_values) == 2
    end

    test "SPARQL constraint violation (arity mismatch)" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: nil,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
        severity: :violation,
        message: "Function arity must match parameter count",
        details: %{
          arity: 2,
          parameter_count: 3
        }
      }

      assert result.path == nil
      assert result.details.arity == 2
      assert result.details.parameter_count == 3
    end

    test "warning about missing documentation" do
      result = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: ~I<https://w3id.org/elixir-code/structure#documentation>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#DocumentationShape>,
        severity: :warning,
        message: "Consider adding documentation to public functions",
        details: %{}
      }

      assert result.severity == :warning
    end
  end
end
