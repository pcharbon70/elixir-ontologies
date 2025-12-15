defmodule ElixirOntologies.SHACL.W3CTestRunner do
  @moduledoc """
  Parser and runner for W3C SHACL Test Suite test cases.

  This module parses RDF test manifests in the W3C SHACL Test Suite format
  and extracts test case metadata for validation testing.

  ## Test Format

  W3C SHACL tests use the following RDF vocabularies:

  - `mf:` - Test Manifest vocabulary (http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#)
  - `sht:` - SHACL Test vocabulary (http://www.w3.org/ns/shacl-test#)
  - `sh:` - SHACL vocabulary (http://www.w3.org/ns/shacl#)

  Each test file contains:

  1. **Test data and shapes** - The RDF graph containing both test data and SHACL shapes
  2. **Test manifest** - Metadata describing the test
  3. **Expected result** - The expected validation report

  ## Example Test Structure

      <class-001>
        a sht:Validate ;
        rdfs:label "Test of sh:class at node shape 001" ;
        mf:action [
          sht:dataGraph <> ;      # Reference to data graph (usually same document)
          sht:shapesGraph <> ;    # Reference to shapes graph
        ] ;
        mf:result [
          a sh:ValidationReport ;
          sh:conforms false ;
          sh:result [ ... ] ;     # Expected validation results
        ] ;
        mf:status sht:approved .

  ## Usage

      # Parse a test file
      {:ok, test_case} = W3CTestRunner.parse_test_file("test/fixtures/w3c/core/class-001.ttl")

      # Run the test
      {:ok, report} = W3CTestRunner.run_test(test_case)

      # Check if test passed
      passed? = W3CTestRunner.test_passed?(test_case, report)
  """

  alias RDF.{Graph, IRI}
  alias ElixirOntologies.SHACL

  @mf_ns "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#"
  @sht_ns "http://www.w3.org/ns/shacl-test#"
  @sh_ns "http://www.w3.org/ns/shacl#"
  @rdfs_ns "http://www.w3.org/2000/01/rdf-schema#"

  @type test_case :: %{
          id: String.t(),
          label: String.t(),
          type: atom(),
          data_graph: Graph.t(),
          shapes_graph: Graph.t(),
          expected_conforms: boolean(),
          expected_result_count: non_neg_integer(),
          file_path: String.t()
        }

  @doc """
  Parses a W3C SHACL test file and extracts test case metadata.

  Returns `{:ok, test_case}` on success, or `{:error, reason}` on failure.

  ## Example

      {:ok, test_case} = W3CTestRunner.parse_test_file("test/fixtures/w3c/core/class-001.ttl")
      test_case.label
      # => "Test of sh:class at node shape 001"
  """
  @spec parse_test_file(String.t()) :: {:ok, test_case()} | {:error, term()}
  def parse_test_file(file_path) do
    # Read with base IRI to resolve relative IRIs
    base_iri = "file://#{Path.expand(file_path)}"

    with {:ok, manifest_graph} <- RDF.Turtle.read_file(file_path, base_iri: base_iri),
         {:ok, test_id} <- extract_test_id(manifest_graph),
         {:ok, label} <- extract_label(manifest_graph, test_id),
         {:ok, type} <- extract_type(manifest_graph, test_id),
         {:ok, expected_conforms} <- extract_expected_conforms(manifest_graph, test_id),
         expected_result_count <- extract_expected_result_count(manifest_graph, test_id),
         {:ok, data_graph} <- load_data_graph(manifest_graph, test_id, file_path),
         {:ok, shapes_graph} <- load_shapes_graph(manifest_graph, test_id, file_path) do
      {:ok,
       %{
         id: test_id,
         label: label,
         type: type,
         data_graph: data_graph,
         shapes_graph: shapes_graph,
         expected_conforms: expected_conforms,
         expected_result_count: expected_result_count,
         file_path: file_path
       }}
    end
  end

  @doc """
  Runs a W3C SHACL test case using the native SHACL validator.

  Returns `{:ok, validation_report}` on success.

  ## Example

      {:ok, test_case} = W3CTestRunner.parse_test_file("test/fixtures/w3c/core/class-001.ttl")
      {:ok, report} = W3CTestRunner.run_test(test_case)
  """
  @spec run_test(test_case()) :: {:ok, SHACL.ValidationReport.t()} | {:error, term()}
  def run_test(%{data_graph: data, shapes_graph: shapes}) do
    SHACL.validate(data, shapes)
  end

  @doc """
  Checks if a test case passed by comparing the actual validation report
  with the expected results.

  Currently implements **partial compliance**: only checks that the
  `sh:conforms` boolean matches the expected value.

  Future enhancement could implement **full compliance** by comparing
  the complete validation report via graph isomorphism.

  ## Example

      {:ok, test_case} = W3CTestRunner.parse_test_file("test/fixtures/w3c/core/class-001.ttl")
      {:ok, report} = W3CTestRunner.run_test(test_case)
      W3CTestRunner.test_passed?(test_case, report)
      # => true (if sh:conforms matches expected)
  """
  @spec test_passed?(test_case(), SHACL.ValidationReport.t()) :: boolean()
  def test_passed?(%{expected_conforms: expected}, %{conforms?: actual}) do
    expected == actual
  end

  @doc """
  Extracts detailed test result comparison for debugging test failures.

  Returns a map with:
  - `:conforms_match` - Whether sh:conforms boolean matches
  - `:expected_conforms` - Expected conformance value
  - `:actual_conforms` - Actual conformance value
  - `:expected_result_count` - Expected number of validation results
  - `:actual_result_count` - Actual number of validation results

  ## Example

      comparison = W3CTestRunner.compare_results(test_case, report)
      comparison.conforms_match
      # => false (if there's a mismatch)
  """
  @spec compare_results(test_case(), SHACL.ValidationReport.t()) :: map()
  def compare_results(test_case, report) do
    %{
      conforms_match: test_case.expected_conforms == report.conforms?,
      expected_conforms: test_case.expected_conforms,
      actual_conforms: report.conforms?,
      expected_result_count: test_case.expected_result_count,
      actual_result_count: length(report.results)
    }
  end

  # Private helper functions

  # Load data graph from external file or use manifest graph
  defp load_data_graph(manifest_graph, test_id, manifest_file_path) do
    mf_action = IRI.new(@mf_ns <> "action")
    sht_data_graph = IRI.new(@sht_ns <> "dataGraph")

    test_desc = Graph.description(manifest_graph, IRI.new(test_id))

    # Get mf:action node
    action_node = case RDF.Description.get(test_desc, mf_action) do
      nodes when is_list(nodes) -> List.first(nodes)
      node -> node
    end

    case action_node do
      nil ->
        # No action node, use manifest graph
        {:ok, manifest_graph}

      action_node ->
        action_desc = Graph.description(manifest_graph, action_node)
        data_graph_ref = RDF.Description.get(action_desc, sht_data_graph)

        case data_graph_ref do
          nil ->
            # No dataGraph specified, use manifest graph
            {:ok, manifest_graph}

          ref ->
            # Try to load external file
            load_external_graph(ref, manifest_file_path, manifest_graph)
        end
    end
  end

  # Load shapes graph from external file or use manifest graph
  defp load_shapes_graph(manifest_graph, test_id, manifest_file_path) do
    mf_action = IRI.new(@mf_ns <> "action")
    sht_shapes_graph = IRI.new(@sht_ns <> "shapesGraph")

    test_desc = Graph.description(manifest_graph, IRI.new(test_id))

    # Get mf:action node
    action_node = case RDF.Description.get(test_desc, mf_action) do
      nodes when is_list(nodes) -> List.first(nodes)
      node -> node
    end

    case action_node do
      nil ->
        # No action node, use manifest graph
        {:ok, manifest_graph}

      action_node ->
        action_desc = Graph.description(manifest_graph, action_node)
        shapes_graph_ref = RDF.Description.get(action_desc, sht_shapes_graph)

        case shapes_graph_ref do
          nil ->
            # No shapesGraph specified, use manifest graph
            {:ok, manifest_graph}

          ref ->
            # Try to load external file
            load_external_graph(ref, manifest_file_path, manifest_graph)
        end
    end
  end

  # Load external graph file if it exists as a relative path
  defp load_external_graph(ref, manifest_file_path, fallback_graph) do
    # Handle both IRI objects and lists
    ref_term = case ref do
      refs when is_list(refs) -> List.first(refs)
      r -> r
    end

    case ref_term do
      nil ->
        {:ok, fallback_graph}

      %RDF.IRI{} = iri ->
        ref_str = to_string(iri)

        # Check if it's a relative file reference (e.g., file:///path/xone-duplicate-data.ttl)
        if String.ends_with?(ref_str, ".ttl") do
          # Resolve relative to manifest file directory
          manifest_dir = Path.dirname(manifest_file_path)
          # Extract filename from IRI
          filename = Path.basename(ref_str)
          external_file_path = Path.join(manifest_dir, filename)

          if File.exists?(external_file_path) do
            # Load the external file
            base_iri = "file://#{Path.expand(external_file_path)}"
            case RDF.Turtle.read_file(external_file_path, base_iri: base_iri) do
              {:ok, graph} -> {:ok, graph}
              {:error, _} -> {:ok, fallback_graph}  # Fall back on error
            end
          else
            # File doesn't exist, use fallback
            {:ok, fallback_graph}
          end
        else
          # Not a file reference, use fallback
          {:ok, fallback_graph}
        end

      _ ->
        # Unknown type, use fallback
        {:ok, fallback_graph}
    end
  end

  defp extract_test_id(graph) do
    # Find the test case node (type sht:Validate)
    sht_validate = IRI.new(@sht_ns <> "Validate")

    test_ids =
      graph
      |> Graph.triples()
      |> Enum.filter(fn {_s, p, o} ->
        p == RDF.type() && o == sht_validate
      end)
      |> Enum.map(fn {s, _p, _o} -> s end)

    case test_ids do
      [test_id | _] ->
        {:ok, to_string(test_id)}

      [] ->
        {:error, "No test case found (no sht:Validate instance)"}
    end
  end

  defp extract_label(graph, test_id) do
    rdfs_label = IRI.new(@rdfs_ns <> "label")
    desc = Graph.description(graph, IRI.new(test_id))

    case RDF.Description.get(desc, rdfs_label) do
      nil ->
        {:error, "No rdfs:label found for test #{test_id}"}

      labels when is_list(labels) ->
        # Multiple labels - take the first one
        {:ok, RDF.Literal.lexical(List.first(labels))}

      label ->
        {:ok, RDF.Literal.lexical(label)}
    end
  end

  defp extract_type(graph, test_id) do
    desc = Graph.description(graph, IRI.new(test_id))

    case RDF.Description.get(desc, RDF.type()) do
      nil ->
        {:error, "No rdf:type found for test #{test_id}"}

      types when is_list(types) ->
        # Multiple types - find the test type
        type_iri = Enum.find(types, fn t -> String.ends_with?(to_string(t), "Validate") end) || List.first(types)
        type_str = to_string(type_iri)

        cond do
          String.ends_with?(type_str, "Validate") -> {:ok, :validate}
          true -> {:ok, :unknown}
        end

      type_iri ->
        type_str = to_string(type_iri)

        cond do
          String.ends_with?(type_str, "Validate") -> {:ok, :validate}
          true -> {:ok, :unknown}
        end
    end
  end

  defp extract_expected_conforms(graph, test_id) do
    # Navigate: test_id -> mf:result -> sh:conforms
    mf_result = IRI.new(@mf_ns <> "result")
    sh_conforms = IRI.new(@sh_ns <> "conforms")

    test_desc = Graph.description(graph, IRI.new(test_id))

    result_node =
      case RDF.Description.get(test_desc, mf_result) do
        nodes when is_list(nodes) -> List.first(nodes)
        node -> node
      end

    with result_node when not is_nil(result_node) <- result_node,
         result_desc <- Graph.description(graph, result_node),
         conforms_value when not is_nil(conforms_value) <-
           RDF.Description.get(result_desc, sh_conforms) do
      value =
        case conforms_value do
          values when is_list(values) -> RDF.Literal.value(List.first(values))
          val -> RDF.Literal.value(val)
        end

      {:ok, value}
    else
      nil ->
        {:error, "No expected sh:conforms value found for test #{test_id}"}
    end
  end

  defp extract_expected_result_count(graph, test_id) do
    # Count the number of sh:result entries in the expected validation report
    mf_result = IRI.new(@mf_ns <> "result")
    sh_result = IRI.new(@sh_ns <> "result")

    test_desc = Graph.description(graph, IRI.new(test_id))

    result_node =
      case RDF.Description.get(test_desc, mf_result) do
        nodes when is_list(nodes) -> List.first(nodes)
        node -> node
      end

    with result_node when not is_nil(result_node) <- result_node do
      # Count all sh:result triples with result_node as subject
      count =
        graph
        |> Graph.triples()
        |> Enum.filter(fn {s, p, _o} ->
          s == result_node && p == sh_result
        end)
        |> length()

      count
    else
      nil -> 0
    end
  end
end
