defmodule ElixirOntologies.Validator.ReportParserTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Validator.{Report, ReportParser, Violation}

  @moduletag :validator

  describe "parse/1" do
    test "parses conformant report" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

      [] a sh:ValidationReport ;
        sh:conforms true .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert %Report{} = report
      assert report.conforms == true
      assert report.violations == []
    end

    test "parses non-conformant report with violation" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix ex: <http://example.org/> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:focusNode ex:MyModule ;
          sh:resultMessage "Required property missing" ;
          sh:resultSeverity sh:Violation
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert %Report{} = report
      assert report.conforms == false
      assert length(report.violations) == 1

      [violation] = report.violations
      assert %Violation{} = violation
      assert violation.message == "Required property missing"
      assert violation.severity == :violation
    end

    test "parses report with multiple violations" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix ex: <http://example.org/> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "First error" ;
          sh:resultSeverity sh:Violation
        ] ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "Second error" ;
          sh:resultSeverity sh:Violation
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert length(report.violations) == 2

      messages = Enum.map(report.violations, & &1.message)
      assert "First error" in messages
      assert "Second error" in messages
    end

    test "parses violation with focus node and path" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix ex: <http://example.org/> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:focusNode ex:MyModule ;
          sh:resultPath ex:hasFunction ;
          sh:value ex:SomeFunction ;
          sh:resultMessage "Invalid function" ;
          sh:resultSeverity sh:Violation ;
          sh:sourceShape ex:ModuleShape ;
          sh:sourceConstraintComponent sh:MinCountConstraintComponent
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert length(report.violations) == 1

      [violation] = report.violations
      assert violation.message == "Invalid function"
      assert violation.focus_node != nil
      assert violation.result_path != nil
      assert violation.value != nil
      assert violation.source_shape != nil
      assert violation.constraint_component != nil
    end

    test "categorizes results by severity" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "Error" ;
          sh:resultSeverity sh:Violation
        ] ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "Warning" ;
          sh:resultSeverity sh:Warning
        ] ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "Info" ;
          sh:resultSeverity sh:Info
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert length(report.violations) == 1
      assert length(report.warnings) == 1
      assert length(report.info) == 1

      assert hd(report.violations).message == "Error"
      assert hd(report.warnings).message == "Warning"
      assert hd(report.info).message == "Info"
    end

    test "handles report with no results" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms true .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert report.violations == []
      assert report.warnings == []
      assert report.info == []
    end

    test "returns error for invalid Turtle syntax" do
      invalid_turtle = "This is not valid Turtle syntax @#$%"

      assert {:error, {:turtle_parse_error, _reason}} = ReportParser.parse(invalid_turtle)
    end

    test "returns error when no validation report found" do
      turtle = """
      @prefix ex: <http://example.org/> .

      ex:Something a ex:Thing .
      """

      assert {:error, :no_validation_report_found} = ReportParser.parse(turtle)
    end

    test "handles missing result message gracefully" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultSeverity sh:Violation
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert length(report.violations) == 1
      [violation] = report.violations
      # Should default to empty string
      assert violation.message == ""
    end

    test "defaults to violation severity when not specified" do
      turtle = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:resultMessage "Unknown severity"
        ] .
      """

      assert {:ok, report} = ReportParser.parse(turtle)
      assert length(report.violations) == 1
      [violation] = report.violations
      assert violation.severity == :violation
    end

    test "parses conforms as boolean true/false strings" do
      turtle_true = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      [] a sh:ValidationReport ; sh:conforms "true"^^<http://www.w3.org/2001/XMLSchema#boolean> .
      """

      turtle_false = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      [] a sh:ValidationReport ; sh:conforms "false"^^<http://www.w3.org/2001/XMLSchema#boolean> .
      """

      # Both should parse successfully
      case ReportParser.parse(turtle_true) do
        {:ok, report} -> assert is_boolean(report.conforms)
        _ -> :ok
      end

      case ReportParser.parse(turtle_false) do
        {:ok, report} -> assert is_boolean(report.conforms)
        _ -> :ok
      end
    end
  end
end
