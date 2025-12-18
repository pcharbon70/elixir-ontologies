defmodule ElixirOntologies.SHACL.Model.ValidationReportTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

  describe "struct creation" do
    test "creates empty conformant report" do
      report = %ValidationReport{
        conforms?: true,
        results: []
      }

      assert report.conforms? == true
      assert report.results == []
    end

    test "creates non-conformant report with violations" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      report = %ValidationReport{
        conforms?: false,
        results: [violation]
      }

      assert report.conforms? == false
      assert length(report.results) == 1
    end
  end

  describe "conformance semantics" do
    test "report with no results conforms" do
      report = %ValidationReport{
        conforms?: true,
        results: []
      }

      assert report.conforms? == true
    end

    test "report with only violations does not conform" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      report = %ValidationReport{
        conforms?: false,
        results: [violation]
      }

      assert report.conforms? == false
      has_violations = Enum.any?(report.results, &(&1.severity == :violation))
      assert has_violations == true
    end

    test "report with only warnings conforms" do
      warning = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :warning,
        message: "Warning",
        details: %{}
      }

      report = %ValidationReport{
        conforms?: true,
        results: [warning]
      }

      assert report.conforms? == true
      has_violations = Enum.any?(report.results, &(&1.severity == :violation))
      assert has_violations == false
    end

    test "report with only info messages conforms" do
      info = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :info,
        message: "Info",
        details: %{}
      }

      report = %ValidationReport{
        conforms?: true,
        results: [info]
      }

      assert report.conforms? == true
    end

    test "report with violations and warnings does not conform" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: ~I<http://example.org/prop1>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      warning = %ValidationResult{
        focus_node: ~I<http://example.org/Node2>,
        path: ~I<http://example.org/prop2>,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :warning,
        message: "Warning",
        details: %{}
      }

      report = %ValidationReport{
        conforms?: false,
        results: [violation, warning]
      }

      assert report.conforms? == false
      assert length(report.results) == 2
    end

    test "conformance check logic matches expected algorithm" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/Node1>,
        path: nil,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :violation,
        message: "Error",
        details: %{}
      }

      warning = %ValidationResult{
        focus_node: ~I<http://example.org/Node2>,
        path: nil,
        source_shape: ~I<http://example.org/Shape1>,
        severity: :warning,
        message: "Warning",
        details: %{}
      }

      # Report with only warnings should conform
      report1 = %ValidationReport{conforms?: true, results: [warning]}
      assert Enum.all?(report1.results, &(&1.severity != :violation))

      # Report with violation should not conform
      report2 = %ValidationReport{conforms?: false, results: [violation, warning]}
      refute Enum.all?(report2.results, &(&1.severity != :violation))
    end
  end

  describe "multiple violations" do
    test "report with multiple violations" do
      violations = [
        %ValidationResult{
          focus_node: ~I<http://example.org/Node1>,
          path: ~I<http://example.org/prop1>,
          source_shape: ~I<http://example.org/Shape1>,
          severity: :violation,
          message: "Error 1",
          details: %{}
        },
        %ValidationResult{
          focus_node: ~I<http://example.org/Node2>,
          path: ~I<http://example.org/prop2>,
          source_shape: ~I<http://example.org/Shape2>,
          severity: :violation,
          message: "Error 2",
          details: %{}
        },
        %ValidationResult{
          focus_node: ~I<http://example.org/Node3>,
          path: ~I<http://example.org/prop3>,
          source_shape: ~I<http://example.org/Shape3>,
          severity: :violation,
          message: "Error 3",
          details: %{}
        }
      ]

      report = %ValidationReport{
        conforms?: false,
        results: violations
      }

      assert length(report.results) == 3
      assert report.conforms? == false
    end
  end

  describe "real-world usage from elixir-shapes.ttl validation" do
    test "valid Elixir module - conforms" do
      report = %ValidationReport{
        conforms?: true,
        results: []
      }

      assert report.conforms? == true
      assert Enum.empty?(report.results)
    end

    test "module with name pattern violation" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/BadModule>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Module name must match pattern ^[A-Z][a-zA-Z0-9_]*$",
        details: %{actual_value: "bad_name"}
      }

      report = %ValidationReport{
        conforms?: false,
        results: [violation]
      }

      assert report.conforms? == false
      assert length(report.results) == 1
    end

    test "function with multiple violations" do
      violations = [
        %ValidationResult{
          focus_node: ~I<http://example.org/MyModule#foo/2>,
          path: nil,
          source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
          severity: :violation,
          message: "Function arity must match parameter count",
          details: %{arity: 2, parameter_count: 3}
        },
        %ValidationResult{
          focus_node: ~I<http://example.org/MyModule#foo/2>,
          path: ~I<https://w3id.org/elixir-code/structure#functionName>,
          source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionShape>,
          severity: :violation,
          message: "Function name must match pattern",
          details: %{actual_value: "Invalid"}
        }
      ]

      report = %ValidationReport{
        conforms?: false,
        results: violations
      }

      assert length(report.results) == 2
      assert Enum.all?(report.results, &(&1.severity == :violation))
    end

    test "module with violations and warnings" do
      violation = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Required property missing",
        details: %{}
      }

      warning = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: ~I<https://w3id.org/elixir-code/structure#documentation>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#DocumentationShape>,
        severity: :warning,
        message: "Consider adding type specs",
        details: %{}
      }

      info = %ValidationResult{
        focus_node: ~I<http://example.org/MyModule>,
        path: nil,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#MetricsShape>,
        severity: :info,
        message: "Documentation coverage: 80%",
        details: %{coverage: 0.8}
      }

      report = %ValidationReport{
        conforms?: false,
        results: [violation, warning, info]
      }

      assert report.conforms? == false
      assert length(report.results) == 3

      violations = Enum.filter(report.results, &(&1.severity == :violation))
      warnings = Enum.filter(report.results, &(&1.severity == :warning))
      infos = Enum.filter(report.results, &(&1.severity == :info))

      assert length(violations) == 1
      assert length(warnings) == 1
      assert length(infos) == 1
    end
  end
end
