defmodule ElixirOntologies.SHACL.Writer do
  @moduledoc """
  Serialize SHACL validation reports to RDF graphs and Turtle format.

  This module converts ValidationReport structs into RDF graphs following
  the W3C SHACL validation report vocabulary, then serializes to Turtle.

  ## Backward Compatibility

  The Writer accepts both `SHACL.Model.ValidationReport` (new SHACL-compliant format)
  and `Validator.Report` (legacy format). Legacy reports are automatically converted
  using the `ValidationReport.from_legacy_report/1` adapter function.

  ## Usage

      # Given a validation report
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
            source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
            severity: :violation,
            message: "Module name must match pattern",
            details: %{}
          }
        ]
      }

      # Convert to RDF graph
      {:ok, graph} = Writer.to_graph(report)

      # Serialize to Turtle
      {:ok, turtle} = Writer.to_turtle(graph)

      # Or directly from report to Turtle
      {:ok, turtle} = Writer.to_turtle(report)

  ## SHACL Validation Report Vocabulary

  The writer follows the W3C SHACL specification for validation reports:

  - `sh:ValidationReport` - Report resource type
  - `sh:conforms` - Boolean indicating overall conformance
  - `sh:result` - Links to individual validation results
  - `sh:ValidationResult` - Result resource type
  - `sh:focusNode` - The RDF node that violated the constraint
  - `sh:resultPath` - The property path (optional)
  - `sh:sourceShape` - The shape that was violated
  - `sh:resultSeverity` - Severity level (Violation, Warning, Info)
  - `sh:resultMessage` - Human-readable error message

  ## Blank Nodes

  Both the ValidationReport and individual ValidationResult resources are
  represented as blank nodes in the output RDF graph. This is standard
  practice for validation reports as they are typically ephemeral resources.

  ## Severity Mapping

  Elixir severity atoms are mapped to SHACL severity IRIs:

  - `:violation` → `sh:Violation`
  - `:warning` → `sh:Warning`
  - `:info` → `sh:Info`

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}
      iex> alias ElixirOntologies.SHACL.Writer
      iex>
      iex> # Conformant report (no violations)
      iex> report = %ValidationReport{conforms?: true, results: []}
      iex> {:ok, graph} = Writer.to_graph(report)
      iex> RDF.Graph.triple_count(graph)
      2
      iex>
      iex> # Non-conformant report with violation
      iex> report = %ValidationReport{
      ...>   conforms?: false,
      ...>   results: [
      ...>     %ValidationResult{
      ...>       focus_node: ~I<http://example.org/Module1>,
      ...>       path: ~I<http://example.org/prop>,
      ...>       source_shape: ~I<http://example.org/Shape>,
      ...>       severity: :violation,
      ...>       message: "Error message",
      ...>       details: %{}
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, graph} = Writer.to_graph(report)
      iex> RDF.Graph.triple_count(graph)
      9
  """

  alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

  # SHACL Vocabulary
  @sh_validation_report RDF.iri("http://www.w3.org/ns/shacl#ValidationReport")
  @sh_validation_result RDF.iri("http://www.w3.org/ns/shacl#ValidationResult")
  @sh_conforms RDF.iri("http://www.w3.org/ns/shacl#conforms")
  @sh_result RDF.iri("http://www.w3.org/ns/shacl#result")
  @sh_focus_node RDF.iri("http://www.w3.org/ns/shacl#focusNode")
  @sh_result_path RDF.iri("http://www.w3.org/ns/shacl#resultPath")
  @sh_source_shape RDF.iri("http://www.w3.org/ns/shacl#sourceShape")
  @sh_result_severity RDF.iri("http://www.w3.org/ns/shacl#resultSeverity")
  @sh_result_message RDF.iri("http://www.w3.org/ns/shacl#resultMessage")

  # Severity IRIs
  @sh_violation RDF.iri("http://www.w3.org/ns/shacl#Violation")
  @sh_warning RDF.iri("http://www.w3.org/ns/shacl#Warning")
  @sh_info RDF.iri("http://www.w3.org/ns/shacl#Info")

  # RDF Vocabulary
  @rdf_type RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")

  # SHACL prefix map for Turtle serialization
  @shacl_prefixes %{
    sh: "http://www.w3.org/ns/shacl#",
    rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    xsd: "http://www.w3.org/2001/XMLSchema#"
  }

  @doc """
  Convert a ValidationReport struct to an RDF graph.

  Creates an RDF graph following the SHACL validation report vocabulary,
  with blank nodes for the report and result resources.

  ## Parameters

  - `report` - ValidationReport struct to convert

  ## Returns

  - `{:ok, graph}` - RDF graph containing the validation report
  - `{:error, reason}` - Error during conversion

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.ValidationReport
      iex> report = %ValidationReport{conforms?: true, results: []}
      iex> {:ok, graph} = ElixirOntologies.SHACL.Writer.to_graph(report)
      iex> RDF.Graph.triple_count(graph)
      2
  """
  @spec to_graph(ValidationReport.t() | ElixirOntologies.Validator.Report.t()) ::
          {:ok, RDF.Graph.t()} | {:error, term()}
  def to_graph(%ElixirOntologies.Validator.Report{} = legacy_report) do
    # Convert legacy Report to ValidationReport and delegate
    validation_report = ValidationReport.from_legacy_report(legacy_report)
    to_graph(validation_report)
  end

  def to_graph(%ValidationReport{} = report) do
    try do
      # Create blank node for report
      report_node = RDF.bnode()

      # Start with empty graph
      graph = RDF.Graph.new()

      # Add report type and conforms
      graph =
        graph
        |> RDF.Graph.add({report_node, @rdf_type, @sh_validation_report})
        |> RDF.Graph.add({report_node, @sh_conforms, report.conforms?})

      # Add all validation results
      graph =
        Enum.reduce(report.results, graph, fn result, acc_graph ->
          add_validation_result(acc_graph, report_node, result)
        end)

      {:ok, graph}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  @doc """
  Serialize a ValidationReport or RDF graph to Turtle format.

  Accepts either a ValidationReport struct or an RDF graph and produces
  Turtle-formatted string output with SHACL prefixes.

  ## Parameters

  - `input` - ValidationReport struct or RDF.Graph.t()
  - `opts` - Optional keyword list:
    - `:prefixes` - Custom prefix map (default: SHACL prefixes)

  ## Returns

  - `{:ok, turtle_string}` - Turtle-formatted string
  - `{:error, reason}` - Error during serialization

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.ValidationReport
      iex> report = %ValidationReport{conforms?: true, results: []}
      iex> {:ok, turtle} = ElixirOntologies.SHACL.Writer.to_turtle(report)
      iex> String.contains?(turtle, "sh:conforms")
      true
  """
  @spec to_turtle(ValidationReport.t() | RDF.Graph.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def to_turtle(input, opts \\ [])

  def to_turtle(%ValidationReport{} = report, opts) do
    with {:ok, graph} <- to_graph(report) do
      to_turtle(graph, opts)
    end
  end

  def to_turtle(%RDF.Graph{} = graph, opts) do
    prefixes = Keyword.get(opts, :prefixes, @shacl_prefixes)

    case RDF.Turtle.write_string(graph, prefixes: prefixes) do
      {:ok, turtle} -> {:ok, turtle}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private Helpers

  # Add a single ValidationResult to the graph
  @spec add_validation_result(RDF.Graph.t(), RDF.Term.t(), ValidationResult.t()) ::
          RDF.Graph.t()
  defp add_validation_result(graph, report_node, result) do
    # Create blank node for this result
    result_node = RDF.bnode()

    # Add link from report to result
    graph = RDF.Graph.add(graph, {report_node, @sh_result, result_node})

    # Add result type
    graph = RDF.Graph.add(graph, {result_node, @rdf_type, @sh_validation_result})

    # Add required properties
    graph =
      graph
      |> RDF.Graph.add({result_node, @sh_focus_node, result.focus_node})
      |> RDF.Graph.add({result_node, @sh_source_shape, result.source_shape})
      |> RDF.Graph.add({result_node, @sh_result_severity, severity_to_iri(result.severity)})

    # Add optional path (only if not nil)
    graph =
      if result.path != nil do
        RDF.Graph.add(graph, {result_node, @sh_result_path, result.path})
      else
        graph
      end

    # Add optional message (only if not nil)
    graph =
      if result.message != nil do
        RDF.Graph.add(graph, {result_node, @sh_result_message, result.message})
      else
        graph
      end

    graph
  end

  # Map severity atom to SHACL severity IRI
  @spec severity_to_iri(ValidationResult.severity()) :: RDF.IRI.t()
  defp severity_to_iri(:violation), do: @sh_violation
  defp severity_to_iri(:warning), do: @sh_warning
  defp severity_to_iri(:info), do: @sh_info
end
