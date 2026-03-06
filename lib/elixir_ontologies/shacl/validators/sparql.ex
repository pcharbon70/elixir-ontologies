defmodule ElixirOntologies.SHACL.Validators.SPARQL do
  @moduledoc """
  SPARQL-based constraint validator for complex validation rules.

  This validator executes SPARQL SELECT queries defined in sh:sparql constraints,
  enabling complex validation logic that cannot be expressed with standard SHACL
  property constraints.

  ## How SPARQL Constraints Work

  1. **Query Definition**: Shape defines a SPARQL SELECT query with `$this` placeholder
  2. **Substitution**: Validator replaces `$this` with the focus node being validated
  3. **Execution**: Modified query runs against the data graph
  4. **Violation Detection**: Each result row = one validation violation
  5. **Reporting**: Results converted to `ValidationResult` structs

  ## The `$this` Placeholder

  SPARQL constraints use the special `$this` placeholder to reference the focus node:

      SELECT $this ?startLine ?endLine
      WHERE {
        $this core:startLine ?startLine .
        $this core:endLine ?endLine .
        FILTER (?endLine < ?startLine)
      }

  During validation, `$this` is replaced with the actual node:

      # For IRI: ~I<http://example.org/loc1>
      SELECT <http://example.org/loc1> ?startLine ?endLine
      WHERE { <http://example.org/loc1> core:startLine ?startLine . ... }

      # For blank node: RDF.bnode("b42")
      SELECT _:b42 ?startLine ?endLine
      WHERE { _:b42 core:startLine ?startLine . ... }

  ## SPARQL Constraints in elixir-shapes.ttl

  This validator supports three SPARQL constraints:

  ### 1. SourceLocationShape - Line Number Validation

  Validates that `endLine >= startLine` for source code locations.

      iex> alias ElixirOntologies.SHACL.Validators.SPARQL
      iex> alias ElixirOntologies.SHACL.Model.SPARQLConstraint
      iex>
      iex> # Valid source location
      iex> data_graph = RDF.Graph.new([
      ...>   {~I<http://example.org/loc1>, ~I<core:startLine>, RDF.XSD.integer(10)},
      ...>   {~I<http://example.org/loc1>, ~I<core:endLine>, RDF.XSD.integer(20)}
      ...> ])
      iex>
      iex> constraint = %SPARQLConstraint{
      ...>   source_shape_id: ~I<http://example.org/shapes#SourceLocationShape>,
      ...>   message: "End line must be >= start line",
      ...>   select_query: \"\"\"
      ...>     SELECT $this
      ...>     WHERE {
      ...>       $this <core:startLine> ?start .
      ...>       $this <core:endLine> ?end .
      ...>       FILTER (?end < ?start)
      ...>     }
      ...>   \"\"\"
      ...> }
      iex>
      iex> SPARQL.validate(data_graph, ~I<http://example.org/loc1>, [constraint])
      []

  ### 2. FunctionArityMatchShape - Arity Consistency

  Validates that function arity matches parameter count.

  ### 3. ProtocolComplianceShape - Implementation Coverage

  Validates that protocol implementations cover all required functions.

  ## Usage

      alias ElixirOntologies.SHACL.Validators.SPARQL
      alias ElixirOntologies.SHACL.Model.SPARQLConstraint

      # Define constraint
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/shapes#MyShape>,
        message: "Custom validation rule violated",
        select_query: \"\"\"
          SELECT $this ?value
          WHERE {
            $this ex:property ?value .
            FILTER (?value < 0)
          }
        \"\"\"
      }

      # Validate
      violations = SPARQL.validate(data_graph, focus_node, [constraint])

  ## Validator Interface

  Follows the standard validator signature from Phase 11.2.1:

      @spec validate(RDF.Graph.t(), RDF.Term.t(), [SPARQLConstraint.t()]) ::
        [ValidationResult.t()]

  - **data_graph** - RDF graph to validate
  - **focus_node** - Node being validated (IRI or blank node)
  - **sparql_constraints** - List of SPARQL constraints to evaluate
  - **Returns** - List of validation violations (empty if conformant)

  ## Error Handling

  - Invalid SPARQL syntax → logged warning, returns empty result
  - Query execution timeout → logged warning, returns empty result
  - Graph query errors → caught and logged, validation continues
  """

  require Logger

  alias ElixirOntologies.NS
  alias ElixirOntologies.SHACL.Model.{SPARQLConstraint, ValidationResult}
  alias ElixirOntologies.SHACL.Vocabulary, as: SH

  # Dialyzer may not see SPARQL library types correctly
  @dialyzer {:nowarn_function, validate_constraint: 3}
  @dialyzer {:nowarn_function, results_to_violations: 3}
  @dialyzer {:nowarn_function, build_details: 1}

  @doc """
  Validate a focus node against SPARQL constraints.

  Executes each SPARQL SELECT query with $this substituted for the focus node.
  If the query returns results, violations are generated.

  ## Parameters

  - `data_graph` - `RDF.Graph.t()` containing data to validate
  - `focus_node` - `RDF.Term.t()` (IRI or blank node) being validated
  - `sparql_constraints` - List of `SPARQLConstraint.t()` to evaluate

  ## Returns

  List of `ValidationResult.t()` - one per query result row. Empty list if conformant.

  ## Examples

      iex> alias ElixirOntologies.SHACL.Validators.SPARQL
      iex> alias ElixirOntologies.SHACL.Model.SPARQLConstraint
      iex>
      iex> # Empty constraints = conformant
      iex> SPARQL.validate(RDF.Graph.new(), ~I<http://example.org/n1>, [])
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), [SPARQLConstraint.t()]) ::
          [ValidationResult.t()]
  def validate(_data_graph, _focus_node, []), do: []

  def validate(data_graph, focus_node, sparql_constraints) do
    sparql_constraints
    |> Enum.flat_map(fn constraint ->
      validate_constraint(data_graph, focus_node, constraint)
    end)
  end

  # Validate a single SPARQL constraint
  @spec validate_constraint(RDF.Graph.t(), RDF.Term.t(), SPARQLConstraint.t()) ::
          [ValidationResult.t()]
  defp validate_constraint(data_graph, focus_node, %SPARQLConstraint{} = constraint) do
    # Step 1: Substitute $this with focus node
    query_with_substitution = substitute_this(constraint.select_query, focus_node)

    query_with_prefixes =
      ensure_prefix_declarations(query_with_substitution, constraint.prefixes_graph)

    # Step 2: Execute SPARQL query
    case execute_query(data_graph, query_with_prefixes) do
      {:ok, result} ->
        # Step 3: Convert results to violations
        results_to_violations(result, focus_node, constraint)

      {:error, reason} ->
        Logger.warning("SPARQL query execution failed: #{inspect(reason)}")
        []
    end
  end

  # Replace $this placeholder with focus node
  # In SHACL-SPARQL, $this appears in both SELECT and WHERE clauses
  # We need to handle them differently:
  # - In SELECT: Keep as constant value but SPARQL doesn't allow that, so we use BIND
  # - In WHERE: Replace with actual IRI
  @spec substitute_this(String.t(), RDF.Term.t()) :: String.t()
  defp substitute_this(query_string, %RDF.IRI{value: value}) when is_binary(value) do
    iri_string = "<#{value}>"

    query_string
    |> replace_select_this_projection()
    |> String.replace("$this", iri_string)
    |> add_this_binding(iri_string)
  end

  defp substitute_this(query_string, %RDF.BlankNode{value: value}) when is_binary(value) do
    # Blank nodes can't be used as a SELECT projection constant (`SELECT _:b1`).
    # Keep a valid SELECT variable while constraining WHERE patterns to the focus bnode.
    bnode_string = "_:#{value}"

    query_string
    |> replace_select_this_projection()
    |> String.replace("$this", bnode_string)
  end

  @spec replace_select_this_projection(String.t()) :: String.t()
  defp replace_select_this_projection(query_string) do
    query_string
    |> String.replace(~r/\bSELECT\s+DISTINCT\s+\$this\b/i, "SELECT DISTINCT ?this")
    |> String.replace(~r/\bSELECT\s+\$this\b/i, "SELECT ?this")
  end

  # Add BIND clause for ?this if needed
  defp add_this_binding(query_string, focus_value) do
    if String.contains?(query_string, "SELECT ?this") do
      # Insert BIND after WHERE {
      String.replace(
        query_string,
        ~r/WHERE\s*\{/,
        "WHERE { BIND(#{focus_value} AS ?this) . ",
        global: false
      )
    else
      query_string
    end
  end

  @spec ensure_prefix_declarations(String.t(), RDF.Graph.t() | nil) :: String.t()
  defp ensure_prefix_declarations(query_string, prefixes_graph) do
    existing_prefixes = extract_existing_prefixes(query_string)
    available_prefixes = merge_available_prefixes(prefixes_graph)

    prefix_declarations =
      available_prefixes
      |> Enum.reject(fn {prefix, _namespace} -> MapSet.member?(existing_prefixes, prefix) end)
      |> Enum.map_join("", fn {prefix, namespace} ->
        "PREFIX #{prefix}: <#{namespace}>\n"
      end)

    prefix_declarations <> query_string
  end

  @spec merge_available_prefixes(RDF.Graph.t() | nil) :: [{String.t(), String.t()}]
  defp merge_available_prefixes(prefixes_graph) do
    default_prefixes =
      NS.prefix_map()
      |> Enum.map(fn {prefix, namespace} -> {to_string(prefix), to_string(namespace)} end)

    custom_prefixes = extract_prefixes_from_graph(prefixes_graph)
    custom_map = Map.new(custom_prefixes)

    default_with_custom_overrides =
      Enum.map(default_prefixes, fn {prefix, namespace} ->
        {prefix, Map.get(custom_map, prefix, namespace)}
      end)

    default_prefix_names = MapSet.new(Enum.map(default_prefixes, fn {prefix, _} -> prefix end))

    extra_custom_prefixes =
      Enum.reject(custom_prefixes, fn {prefix, _} ->
        MapSet.member?(default_prefix_names, prefix)
      end)

    default_with_custom_overrides ++ extra_custom_prefixes
  end

  @spec extract_prefixes_from_graph(RDF.Graph.t() | nil) :: [{String.t(), String.t()}]
  defp extract_prefixes_from_graph(nil), do: []

  defp extract_prefixes_from_graph(%RDF.Graph{} = prefixes_graph) do
    prefixes_graph
    |> RDF.Graph.triples()
    |> Enum.map(fn {subject, _predicate, _object} -> subject end)
    |> Enum.uniq()
    |> Enum.reduce([], fn subject, acc ->
      desc = RDF.Graph.description(prefixes_graph, subject)

      with prefix when is_binary(prefix) <-
             extract_string_value(RDF.Description.get(desc, SH.prefix())),
           namespace when is_binary(namespace) <-
             extract_string_value(RDF.Description.get(desc, SH.namespace())),
           true <- valid_prefix_name?(prefix),
           true <- namespace != "" do
        [{prefix, namespace} | acc]
      else
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  @spec extract_existing_prefixes(String.t()) :: MapSet.t(String.t())
  defp extract_existing_prefixes(query_string) do
    ~r/^\s*PREFIX\s+([A-Za-z][A-Za-z0-9_.-]*)\s*:/mi
    |> Regex.scan(query_string)
    |> Enum.map(fn [_, prefix] -> prefix end)
    |> MapSet.new()
  end

  @spec extract_string_value(term()) :: String.t() | nil
  defp extract_string_value(values) do
    values
    |> normalize_to_list()
    |> Enum.find_value(&term_to_string/1)
  end

  @spec normalize_to_list(term()) :: list()
  defp normalize_to_list(nil), do: []
  defp normalize_to_list(values) when is_list(values), do: values
  defp normalize_to_list(value), do: [value]

  @spec term_to_string(term()) :: String.t() | nil
  defp term_to_string(%RDF.IRI{value: value}) when is_binary(value), do: value
  defp term_to_string(%RDF.Literal{} = literal), do: literal |> RDF.Literal.value() |> to_string()
  defp term_to_string(value) when is_binary(value), do: value
  defp term_to_string(_), do: nil

  @spec valid_prefix_name?(String.t()) :: boolean()
  defp valid_prefix_name?(prefix) do
    Regex.match?(~r/^[A-Za-z][A-Za-z0-9_.-]*$/, prefix)
  end

  # Execute SPARQL query against data graph
  # SPARQL.execute_query returns the result directly or {:error, reason}
  @spec execute_query(RDF.Graph.t(), String.t()) ::
          {:ok, SPARQL.Query.Result.t()} | {:error, term()}
  defp execute_query(data_graph, query_string) do
    case SPARQL.execute_query(data_graph, query_string) do
      {:error, reason} -> {:error, reason}
      %SPARQL.Query.Result{} = result -> {:ok, result}
    end
  rescue
    e -> {:error, e}
  end

  # Convert SPARQL query results to validation violations
  @spec results_to_violations(SPARQL.Query.Result.t(), RDF.Term.t(), SPARQLConstraint.t()) ::
          [ValidationResult.t()]
  defp results_to_violations(%SPARQL.Query.Result{results: solutions}, focus_node, constraint) do
    Enum.map(solutions, fn solution ->
      %ValidationResult{
        severity: :violation,
        focus_node: focus_node,
        path: nil,
        source_shape: constraint.source_shape_id,
        message: constraint.message,
        details: build_details(solution)
      }
    end)
  end

  # Convert SPARQL solution bindings to details map
  @spec build_details(map()) :: map()
  defp build_details(solution) when is_map(solution) do
    solution
    |> Enum.map(fn {var_name, value} ->
      # Convert variable names to atoms (e.g., "?arity" -> :arity)
      key = var_name |> to_string() |> String.trim_leading("?") |> String.to_atom()
      {key, value}
    end)
    |> Map.new()
  end
end
