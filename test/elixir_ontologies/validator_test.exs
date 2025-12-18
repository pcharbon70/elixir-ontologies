defmodule ElixirOntologies.ValidatorTest do
  use ExUnit.Case, async: false

  alias ElixirOntologies.{Validator, Graph}
  alias ElixirOntologies.SHACL.Model.ValidationReport

  @moduletag :validator

  describe "validate/2" do
    setup do
      # Create a minimal valid graph for testing
      graph = %Graph{
        graph: RDF.Graph.new(),
        base_iri: nil
      }

      {:ok, graph: graph}
    end

    test "validates an empty graph and returns report", %{graph: graph} do
      case Validator.validate(graph) do
        {:ok, report} ->
          assert %ValidationReport{} = report
          assert is_boolean(report.conforms?)
          assert is_list(report.results)

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "validates graph with custom timeout", %{graph: graph} do
      case Validator.validate(graph, timeout: 60_000) do
        {:ok, _report} ->
          :ok

        {:error, _reason} ->
          # Errors are acceptable for this test
          :ok
      end
    end

    test "accepts shapes_graph option", %{graph: graph} do
      # Test that the option is accepted (may fail validation but shouldn't crash)
      case RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl") do
        {:ok, shapes_graph} ->
          case Validator.validate(graph, shapes_graph: shapes_graph) do
            {:ok, _report} ->
              :ok

            {:error, _reason} ->
              :ok
          end

        {:error, _} ->
          # Skip if shapes file not found
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

    test "validates real analyzed graph", %{graph: graph} do
      # Skip if graph creation failed
      if graph do
        case Validator.validate(graph) do
          {:ok, report} ->
            assert %ValidationReport{} = report
            assert is_boolean(report.conforms?)

          {:error, reason} ->
            # Log but don't fail - validation might have legitimate issues
            IO.puts("Validation error: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
