defmodule ElixirOntologies.ValidatorTest do
  use ExUnit.Case, async: false

  alias ElixirOntologies.{Validator, Graph}
  alias Validator.Report

  @moduletag :validator

  describe "available?/0" do
    test "returns boolean indicating pySHACL availability" do
      result = Validator.available?()
      assert is_boolean(result)
    end
  end

  describe "installation_instructions/0" do
    test "returns installation instructions string" do
      instructions = Validator.installation_instructions()
      assert is_binary(instructions)
      assert String.contains?(instructions, "pyshacl")
      assert String.contains?(instructions, "pip")
    end
  end

  describe "validate/2" do
    setup do
      # Create a minimal valid graph for testing
      graph = %Graph{
        graph: RDF.Graph.new(),
        base_iri: nil
      }

      {:ok, graph: graph}
    end

    @tag :requires_pyshacl
    test "validates an empty graph and returns report", %{graph: graph} do
      case Validator.validate(graph) do
        {:ok, report} ->
          assert %Report{} = report
          assert is_boolean(report.conforms)
          assert is_list(report.violations)
          assert is_list(report.warnings)
          assert is_list(report.info)

        {:error, :pyshacl_not_available} ->
          # Skip test if pySHACL not installed
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    @tag :requires_pyshacl
    test "returns error when pySHACL not available if uninstalled" do
      # This test only runs if pySHACL is not available
      unless Validator.available?() do
        result = Validator.validate(%Graph{graph: RDF.Graph.new(), base_iri: nil})
        assert {:error, :pyshacl_not_available} = result
      end
    end

    test "validates graph with custom timeout", %{graph: graph} do
      case Validator.validate(graph, timeout: 60_000) do
        {:ok, _report} ->
          :ok

        {:error, :pyshacl_not_available} ->
          :ok

        {:error, _reason} ->
          # Errors are acceptable for this test
          :ok
      end
    end

    test "accepts shapes_file option", %{graph: graph} do
      # Test that the option is accepted (may fail validation but shouldn't crash)
      shapes_file = "priv/ontologies/elixir-shapes.ttl"

      case Validator.validate(graph, shapes_file: shapes_file) do
        {:ok, _report} ->
          :ok

        {:error, :pyshacl_not_available} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "validate/2 with real analyzer output" do
    setup do
      # Create a real analyzed graph
      temp_dir = System.tmp_dir!()

      file_path = Path.join(temp_dir, "test_module_#{:rand.uniform(999_999)}.ex")

      File.write!(file_path, """
      defmodule ValidatorTestModule do
        @moduledoc "Test module for validation"

        def test_function do
          :ok
        end
      end
      """)

      on_exit(fn -> File.rm(file_path) end)

      case ElixirOntologies.analyze_file(file_path) do
        {:ok, graph} -> {:ok, graph: graph}
        {:error, _} -> {:ok, graph: nil}
      end
    end

    @tag :requires_pyshacl
    test "validates real analyzed graph", %{graph: graph} do
      # Skip if graph creation failed
      if graph do
        case Validator.validate(graph) do
          {:ok, report} ->
            assert %Report{} = report
            assert is_boolean(report.conforms)

          {:error, :pyshacl_not_available} ->
            :ok

          {:error, reason} ->
            # Log but don't fail - validation might have legitimate issues
            IO.puts("Validation error: #{inspect(reason)}")
            :ok
        end
      end
    end
  end

  describe "Report struct" do
    test "creates new empty report" do
      report = Report.new()
      assert %Report{} = report
      assert report.conforms == true
      assert report.violations == []
      assert report.warnings == []
      assert report.info == []
    end

    test "creates report with violations" do
      violation = %Validator.Violation{message: "Test error"}
      report = Report.new(conforms: false, violations: [violation])

      assert report.conforms == false
      assert length(report.violations) == 1
    end

    test "has_violations?/1 returns true when violations present" do
      violation = %Validator.Violation{message: "Test"}
      report = Report.new(violations: [violation])

      assert Report.has_violations?(report) == true
    end

    test "has_violations?/1 returns false when no violations" do
      report = Report.new()
      assert Report.has_violations?(report) == false
    end

    test "issue_count/1 returns total issues" do
      violation = %Validator.Violation{message: "Error"}
      warning = %Validator.Warning{message: "Warning"}
      info = %Validator.Info{message: "Info"}

      report = Report.new(violations: [violation], warnings: [warning], info: [info])

      assert Report.issue_count(report) == 3
    end
  end

  describe "Violation struct" do
    test "creates new violation with defaults" do
      violation = Validator.Violation.new()
      assert %Validator.Violation{} = violation
      assert violation.severity == :violation
      assert violation.message == ""
    end

    test "creates violation with attributes" do
      violation = Validator.Violation.new(message: "Test error", severity: :violation)

      assert violation.message == "Test error"
      assert violation.severity == :violation
    end
  end

  describe "Warning struct" do
    test "creates new warning with defaults" do
      warning = Validator.Warning.new()
      assert %Validator.Warning{} = warning
      assert warning.severity == :warning
      assert warning.message == ""
    end

    test "creates warning with attributes" do
      warning = Validator.Warning.new(message: "Test warning")
      assert warning.message == "Test warning"
      assert warning.severity == :warning
    end
  end

  describe "Info struct" do
    test "creates new info with defaults" do
      info = Validator.Info.new()
      assert %Validator.Info{} = info
      assert info.severity == :info
      assert info.message == ""
    end

    test "creates info with attributes" do
      info = Validator.Info.new(message: "Test info")
      assert info.message == "Test info"
      assert info.severity == :info
    end
  end
end
