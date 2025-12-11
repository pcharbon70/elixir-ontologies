defmodule ElixirOntologies.Validator.ReportParser do
  @moduledoc """
  Parses SHACL validation reports from Turtle format.

  This module converts pySHACL validation reports (in RDF/Turtle) into
  structured Elixir data using the Report, Violation, Warning, and Info structs.

  ## SHACL Validation Report Vocabulary

  The parser recognizes these SHACL predicates:
  - `sh:conforms` - Overall conformance boolean
  - `sh:result` - Links to validation results
  - `sh:focusNode` - The node that violated the constraint
  - `sh:resultPath` - The property path
  - `sh:value` - The actual value
  - `sh:resultMessage` - Human-readable message
  - `sh:resultSeverity` - Severity level (Violation, Warning, Info)
  - `sh:sourceShape` - Which shape was violated
  - `sh:sourceConstraintComponent` - Which constraint failed

  ## Example Report RDF

      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:focusNode <http://example.org/MyModule> ;
          sh:resultMessage "Required property missing" ;
          sh:resultSeverity sh:Violation
        ] .

  """

  alias ElixirOntologies.Validator.{Report, Violation, Warning, Info}
  alias RDF.Graph

  require Logger

  # SHACL namespace IRIs
  @sh_conforms RDF.iri("http://www.w3.org/ns/shacl#conforms")
  @sh_result RDF.iri("http://www.w3.org/ns/shacl#result")
  @sh_focus_node RDF.iri("http://www.w3.org/ns/shacl#focusNode")
  @sh_result_path RDF.iri("http://www.w3.org/ns/shacl#resultPath")
  @sh_value RDF.iri("http://www.w3.org/ns/shacl#value")
  @sh_result_message RDF.iri("http://www.w3.org/ns/shacl#resultMessage")
  @sh_result_severity RDF.iri("http://www.w3.org/ns/shacl#resultSeverity")
  @sh_source_shape RDF.iri("http://www.w3.org/ns/shacl#sourceShape")
  @sh_source_constraint_component RDF.iri(
                                     "http://www.w3.org/ns/shacl#sourceConstraintComponent"
                                   )

  @sh_violation RDF.iri("http://www.w3.org/ns/shacl#Violation")
  @sh_warning RDF.iri("http://www.w3.org/ns/shacl#Warning")
  @sh_info RDF.iri("http://www.w3.org/ns/shacl#Info")

  @doc """
  Parses a SHACL validation report from Turtle string.

  ## Parameters

  - `turtle_string`: The validation report in Turtle format

  ## Returns

  - `{:ok, report}` - Successfully parsed report
  - `{:error, reason}` - Parsing failed

  ## Examples

      iex> turtle = \"\"\"
      ...> @prefix sh: <http://www.w3.org/ns/shacl#> .
      ...> [] a sh:ValidationReport ; sh:conforms true .
      ...> \"\"\"
      iex> {:ok, report} = ElixirOntologies.Validator.ReportParser.parse(turtle)
      iex> report.conforms
      true

  """
  @spec parse(String.t()) :: {:ok, Report.t()} | {:error, term()}
  def parse(turtle_string) when is_binary(turtle_string) do
    with {:ok, graph} <- parse_turtle(turtle_string),
         {:ok, report_node} <- find_validation_report(graph),
         {:ok, conforms} <- extract_conforms(graph, report_node) do
      results = extract_results(graph, report_node)

      {violations, warnings, info} = categorize_results(results)

      report = %Report{
        conforms: conforms,
        violations: violations,
        warnings: warnings,
        info: info
      }

      {:ok, report}
    end
  end

  # Parses Turtle string into RDF graph
  @spec parse_turtle(String.t()) :: {:ok, Graph.t()} | {:error, term()}
  defp parse_turtle(turtle_string) do
    case RDF.Turtle.read_string(turtle_string) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, {:turtle_parse_error, reason}}
    end
  end

  # Finds the validation report node in the graph
  @spec find_validation_report(Graph.t()) :: {:ok, term()} | {:error, term()}
  defp find_validation_report(graph) do
    # Look for the subject with sh:conforms predicate by examining triples
    subjects =
      RDF.Graph.triples(graph)
      |> Enum.filter(fn {_s, p, _o} -> p == @sh_conforms end)
      |> Enum.map(fn {s, _p, _o} -> s end)
      |> Enum.uniq()

    case subjects do
      [report_node | _] ->
        {:ok, report_node}

      [] ->
        {:error, :no_validation_report_found}
    end
  end

  # Extracts the sh:conforms value
  @spec extract_conforms(Graph.t(), term()) :: {:ok, boolean()} | {:error, term()}
  defp extract_conforms(graph, report_node) do
    # Get all objects for this subject and predicate using get_objects helper
    values = get_objects(graph, report_node, @sh_conforms)

    case values do
      [] ->
        {:error, :missing_conforms_value}

      [value | _] ->
        parse_conforms_value(value)
    end
  end

  # Parse a conforms value - match any RDF.Literal with boolean value
  defp parse_conforms_value(%RDF.Literal{} = literal) do
    # Use RDF.Literal.value/1 to extract the actual value
    case RDF.Literal.value(literal) do
      value when is_boolean(value) ->
        {:ok, value}

      "true" ->
        {:ok, true}

      "false" ->
        {:ok, false}

      value ->
        {:error, {:invalid_conforms_value, value}}
    end
  end

  defp parse_conforms_value(value) do
    {:error, {:invalid_conforms_value, value}}
  end

  # Extracts all validation results
  @spec extract_results(Graph.t(), term()) :: [map()]
  defp extract_results(graph, report_node) do
    result_nodes = get_objects(graph, report_node, @sh_result)

    Enum.map(result_nodes, fn result_node ->
      extract_result_details(graph, result_node)
    end)
  end

  # Extracts details from a single validation result
  @spec extract_result_details(Graph.t(), term()) :: map()
  defp extract_result_details(graph, result_node) do
    %{
      focus_node: get_single_value(graph, result_node, @sh_focus_node),
      result_path: get_single_value(graph, result_node, @sh_result_path),
      value: get_single_value(graph, result_node, @sh_value),
      message: get_literal_value(graph, result_node, @sh_result_message, ""),
      severity: parse_severity(get_single_value(graph, result_node, @sh_result_severity)),
      source_shape: get_single_value(graph, result_node, @sh_source_shape),
      constraint_component: get_single_value(graph, result_node, @sh_source_constraint_component)
    }
  end

  # Helper to get all object values for a subject-predicate pair
  @spec get_objects(Graph.t(), term(), term()) :: [term()]
  defp get_objects(graph, subject, predicate) do
    RDF.Graph.triples(graph)
    |> Enum.filter(fn {s, p, _o} -> s == subject && p == predicate end)
    |> Enum.map(fn {_s, _p, o} -> o end)
  end

  # Gets a single value from the graph
  @spec get_single_value(Graph.t(), term(), term()) :: term() | nil
  defp get_single_value(graph, subject, predicate) do
    case get_objects(graph, subject, predicate) do
      [value | _] -> value
      [] -> nil
    end
  end

  # Gets a literal string value from the graph
  @spec get_literal_value(Graph.t(), term(), term(), String.t()) :: String.t()
  defp get_literal_value(graph, subject, predicate, default) do
    case get_objects(graph, subject, predicate) do
      [%RDF.Literal{literal: %{value: value}}] when is_binary(value) -> value
      _ -> default
    end
  end

  # Parses severity IRI to atom
  @spec parse_severity(term() | nil) :: :violation | :warning | :info
  defp parse_severity(severity_iri) do
    case severity_iri do
      @sh_violation -> :violation
      @sh_warning -> :warning
      @sh_info -> :info
      _ -> :violation
    end
  end

  # Categorizes results into violations, warnings, and info
  @spec categorize_results([map()]) :: {[Violation.t()], [Warning.t()], [Info.t()]}
  defp categorize_results(results) do
    violations =
      results
      |> Enum.filter(&(&1.severity == :violation))
      |> Enum.map(&struct(Violation, &1))

    warnings =
      results
      |> Enum.filter(&(&1.severity == :warning))
      |> Enum.map(&struct(Warning, &1))

    info =
      results
      |> Enum.filter(&(&1.severity == :info))
      |> Enum.map(&struct(Info, &1))

    {violations, warnings, info}
  end
end
