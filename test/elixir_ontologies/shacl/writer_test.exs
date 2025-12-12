defmodule ElixirOntologies.SHACL.WriterTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Writer
  alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

  # SHACL vocabulary for assertions
  @sh_validation_report ~I<http://www.w3.org/ns/shacl#ValidationReport>
  @sh_validation_result ~I<http://www.w3.org/ns/shacl#ValidationResult>
  @sh_conforms ~I<http://www.w3.org/ns/shacl#conforms>
  @sh_result ~I<http://www.w3.org/ns/shacl#result>
  @sh_focus_node ~I<http://www.w3.org/ns/shacl#focusNode>
  @sh_result_path ~I<http://www.w3.org/ns/shacl#resultPath>
  @sh_source_shape ~I<http://www.w3.org/ns/shacl#sourceShape>
  @sh_result_severity ~I<http://www.w3.org/ns/shacl#resultSeverity>
  @sh_result_message ~I<http://www.w3.org/ns/shacl#resultMessage>
  @sh_violation ~I<http://www.w3.org/ns/shacl#Violation>
  @sh_warning ~I<http://www.w3.org/ns/shacl#Warning>
  @sh_info ~I<http://www.w3.org/ns/shacl#Info>
  @rdf_type ~I<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>

  # Helper: Get all objects for a given predicate
  defp get_objects(graph, predicate) do
    graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, _o} -> p == predicate end)
    |> Enum.map(fn {_s, _p, o} ->
      case o do
        %RDF.Literal{} -> RDF.Literal.value(o)
        %RDF.XSD.Boolean{} -> RDF.Literal.value(o)
        _ -> o
      end
    end)
  end

  describe "to_graph/1 with conformant reports" do
    test "converts conformant report with no results" do
      report = %ValidationReport{
        conforms?: true,
        results: []
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should have exactly 2 triples (type + conforms)
      assert RDF.Graph.triple_count(graph) == 2

      # Should have ValidationReport type
      assert Enum.member?(get_objects(graph, @rdf_type), @sh_validation_report)

      # Should have conforms = true
      assert Enum.member?(get_objects(graph, @sh_conforms), true)
    end

    test "report resource is a blank node" do
      report = %ValidationReport{conforms?: true, results: []}
      {:ok, graph} = Writer.to_graph(report)

      # Get the report subject
      report_subjects = RDF.Graph.subjects(graph) |> Enum.to_list()
      assert length(report_subjects) == 1
      report_subject = hd(report_subjects)
      assert match?(%RDF.BlankNode{}, report_subject)
    end
  end

  describe "to_graph/1 with non-conformant reports" do
    test "converts report with single violation" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<http://example.org/moduleName>,
            source_shape: ~I<http://example.org/ModuleShape>,
            severity: :violation,
            message: "Module name is invalid",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Report should have conforms = false
      assert get_objects(graph, @sh_conforms) |> Enum.member?(false)

      # Should have one result
      result_nodes = get_objects(graph, @sh_result)
      assert length(result_nodes) == 1

      # Result should have ValidationResult type
      assert get_objects(graph, @rdf_type) |> Enum.member?(@sh_validation_result)

      # Result should have all required properties
      assert get_objects(graph, @sh_focus_node)
             |> Enum.member?(~I<http://example.org/Module1>)

      assert get_objects(graph, @sh_result_path)
             |> Enum.member?(~I<http://example.org/moduleName>)

      assert get_objects(graph, @sh_source_shape)
             |> Enum.member?(~I<http://example.org/ModuleShape>)

      assert get_objects(graph, @sh_result_severity) |> Enum.member?(@sh_violation)
      assert get_objects(graph, @sh_result_message) |> Enum.member?("Module name is invalid")
    end

    test "converts report with multiple violations" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<http://example.org/prop1>,
            source_shape: ~I<http://example.org/Shape1>,
            severity: :violation,
            message: "Error 1",
            details: %{}
          },
          %ValidationResult{
            focus_node: ~I<http://example.org/Module2>,
            path: ~I<http://example.org/prop2>,
            source_shape: ~I<http://example.org/Shape2>,
            severity: :violation,
            message: "Error 2",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should have 2 results
      result_nodes = get_objects(graph, @sh_result)
      assert length(result_nodes) == 2

      # Both results should be blank nodes
      assert Enum.all?(result_nodes, &match?(%RDF.BlankNode{}, &1))

      # Should have both focus nodes
      focus_nodes = get_objects(graph, @sh_focus_node)
      assert Enum.member?(focus_nodes, ~I<http://example.org/Module1>)
      assert Enum.member?(focus_nodes, ~I<http://example.org/Module2>)
    end
  end

  describe "to_graph/1 with different severity levels" do
    test "converts violation severity correctly" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Violation",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      assert get_objects(graph, @sh_result_severity) |> Enum.member?(@sh_violation)
    end

    test "converts warning severity correctly" do
      report = %ValidationReport{
        conforms?: true,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :warning,
            message: "Warning",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      assert get_objects(graph, @sh_result_severity) |> Enum.member?(@sh_warning)
    end

    test "converts info severity correctly" do
      report = %ValidationReport{
        conforms?: true,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :info,
            message: "Info",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      assert get_objects(graph, @sh_result_severity) |> Enum.member?(@sh_info)
    end
  end

  describe "to_graph/1 with optional fields" do
    test "omits path when nil" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should not have any sh:resultPath triples
      path_values = get_objects(graph, @sh_result_path)
      assert path_values == []
    end

    test "includes path when present" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: ~I<http://example.org/property>,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should have sh:resultPath triple
      path_values = get_objects(graph, @sh_result_path)
      assert Enum.member?(path_values, ~I<http://example.org/property>)
    end

    test "omits message when nil" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: nil,
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should not have any sh:resultMessage triples
      message_values = get_objects(graph, @sh_result_message)
      assert message_values == []
    end

    test "includes message when present" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Custom error message",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should have sh:resultMessage triple
      message_values = get_objects(graph, @sh_result_message)
      assert Enum.member?(message_values, "Custom error message")
    end
  end

  describe "to_graph/1 with different focus node types" do
    test "handles IRI focus nodes" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      focus_nodes = get_objects(graph, @sh_focus_node)
      assert Enum.member?(focus_nodes, ~I<http://example.org/Module1>)
    end

    test "handles blank node focus nodes" do
      bnode = RDF.bnode("test")

      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: bnode,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      focus_nodes = get_objects(graph, @sh_focus_node)
      assert Enum.member?(focus_nodes, bnode)
    end

    test "handles literal focus nodes" do
      literal = RDF.literal("test value")

      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: literal,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      focus_nodes = get_objects(graph, @sh_focus_node)
      assert Enum.member?(focus_nodes, "test value")
    end
  end

  describe "to_turtle/1 with ValidationReport input" do
    test "serializes conformant report to Turtle" do
      report = %ValidationReport{conforms?: true, results: []}
      {:ok, turtle} = Writer.to_turtle(report)

      # Should be valid Turtle string
      assert is_binary(turtle)

      # Should contain SHACL prefix
      assert String.contains?(turtle, "sh:")

      # Should contain conforms true
      assert String.contains?(turtle, "sh:conforms")
      assert String.contains?(turtle, "true")
    end

    test "serializes non-conformant report to Turtle" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: ~I<http://example.org/prop>,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error message",
            details: %{}
          }
        ]
      }

      {:ok, turtle} = Writer.to_turtle(report)

      # Should contain SHACL vocabulary terms
      assert String.contains?(turtle, "sh:conforms")
      assert String.contains?(turtle, "false")
      assert String.contains?(turtle, "sh:result")
      assert String.contains?(turtle, "sh:ValidationResult")
      assert String.contains?(turtle, "sh:focusNode")
      assert String.contains?(turtle, "sh:resultSeverity")
      assert String.contains?(turtle, "sh:Violation")
      assert String.contains?(turtle, "Error message")
    end

    test "Turtle output can be parsed back to RDF" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: nil,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error",
            details: %{}
          }
        ]
      }

      {:ok, turtle} = Writer.to_turtle(report)
      {:ok, parsed_graph} = RDF.Turtle.read_string(turtle)

      # Parsed graph should have the same structure
      assert RDF.Graph.triple_count(parsed_graph) >= 7
      assert get_objects(parsed_graph, @sh_conforms) |> Enum.member?(false)
    end
  end

  describe "to_turtle/1 with RDF.Graph input" do
    test "serializes graph directly to Turtle" do
      report = %ValidationReport{conforms?: true, results: []}
      {:ok, graph} = Writer.to_graph(report)
      {:ok, turtle} = Writer.to_turtle(graph)

      assert is_binary(turtle)
      assert String.contains?(turtle, "sh:")
      assert String.contains?(turtle, "sh:conforms")
    end

    test "accepts custom prefixes" do
      report = %ValidationReport{conforms?: true, results: []}
      {:ok, graph} = Writer.to_graph(report)

      custom_prefixes = %{
        shacl: "http://www.w3.org/ns/shacl#",
        ex: "http://example.org/"
      }

      {:ok, turtle} = Writer.to_turtle(graph, prefixes: custom_prefixes)

      # Should use custom prefix
      assert String.contains?(turtle, "shacl:")
    end
  end

  describe "integration tests" do
    test "report with warnings and info messages (still conformant)" do
      report = %ValidationReport{
        conforms?: true,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: nil,
            source_shape: ~I<http://example.org/DocShape>,
            severity: :warning,
            message: "Consider adding documentation",
            details: %{}
          },
          %ValidationResult{
            focus_node: ~I<http://example.org/Module2>,
            path: nil,
            source_shape: ~I<http://example.org/InfoShape>,
            severity: :info,
            message: "Coverage: 80%",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)

      # Should be conformant despite having results
      assert get_objects(graph, @sh_conforms) |> Enum.member?(true)

      # Should have both severity types
      severities = get_objects(graph, @sh_result_severity)
      assert Enum.member?(severities, @sh_warning)
      assert Enum.member?(severities, @sh_info)
    end

    test "complex report with mixed severities" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<http://example.org/name>,
            source_shape: ~I<http://example.org/NameShape>,
            severity: :violation,
            message: "Name is invalid",
            details: %{}
          },
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<http://example.org/doc>,
            source_shape: ~I<http://example.org/DocShape>,
            severity: :warning,
            message: "Missing documentation",
            details: %{}
          },
          %ValidationResult{
            focus_node: ~I<http://example.org/Module2>,
            path: nil,
            source_shape: ~I<http://example.org/ArityShape>,
            severity: :violation,
            message: "Arity mismatch",
            details: %{}
          }
        ]
      }

      {:ok, graph} = Writer.to_graph(report)
      {:ok, turtle} = Writer.to_turtle(graph)

      # Should have all 3 results
      assert get_objects(graph, @sh_result) |> length() == 3

      # Turtle should be parseable and complete
      {:ok, parsed} = RDF.Turtle.read_string(turtle)
      assert RDF.Graph.triple_count(parsed) == RDF.Graph.triple_count(graph)
    end

    test "round-trip: report -> graph -> turtle -> graph" do
      original_report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Node>,
            path: ~I<http://example.org/prop>,
            source_shape: ~I<http://example.org/Shape>,
            severity: :violation,
            message: "Error message",
            details: %{}
          }
        ]
      }

      # Convert to graph
      {:ok, graph1} = Writer.to_graph(original_report)

      # Convert to Turtle
      {:ok, turtle} = Writer.to_turtle(graph1)

      # Parse Turtle back to graph
      {:ok, graph2} = RDF.Turtle.read_string(turtle)

      # Graphs should have same triple count
      assert RDF.Graph.triple_count(graph1) == RDF.Graph.triple_count(graph2)

      # Should preserve conforms value
      assert get_objects(graph2, @sh_conforms) |> Enum.member?(false)

      # Should preserve severity
      assert get_objects(graph2, @sh_result_severity) |> Enum.member?(@sh_violation)
    end
  end
end
