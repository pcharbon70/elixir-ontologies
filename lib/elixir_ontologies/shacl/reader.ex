defmodule ElixirOntologies.SHACL.Reader do
  @moduledoc """
  Parse SHACL shapes from RDF graphs into Elixir data structures.

  This module reads SHACL shapes files (Turtle format) and converts them into
  the internal data model structs (NodeShape, PropertyShape, SPARQLConstraint).

  ## Usage

      # Load shapes from file
      {:ok, graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")

      # Parse into NodeShape structs
      {:ok, shapes} = Reader.parse_shapes(graph)

      # shapes is now a list of NodeShape.t() with all constraints parsed

  ## Supported SHACL Features

  This reader supports all SHACL constraint types used in elixir-shapes.ttl:

  **Node Targeting:**
  - `sh:targetClass` - Target nodes by RDF class

  **Property Constraints:**
  - `sh:minCount`, `sh:maxCount` - Cardinality constraints
  - `sh:datatype`, `sh:class` - Type constraints
  - `sh:pattern`, `sh:minLength` - String constraints
  - `sh:minInclusive`, `sh:maxInclusive` - Numeric constraints
  - `sh:in`, `sh:hasValue` - Value constraints
  - `sh:qualifiedValueShape`, `sh:qualifiedMinCount` - Qualified constraints

  **Advanced Constraints:**
  - `sh:sparql` with `sh:select` - SPARQL-based constraints

  ## Examples

      # Parse all shapes from elixir-shapes.ttl
      {:ok, graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")
      {:ok, shapes} = ElixirOntologies.SHACL.Reader.parse_shapes(graph)

      # Find ModuleShape
      module_shape = Enum.find(shapes, fn s ->
        s.id == RDF.iri("https://w3id.org/elixir-code/shapes#ModuleShape")
      end)

      # Access its property shapes
      property_shapes = module_shape.property_shapes
  """

  alias ElixirOntologies.SHACL.Model.{NodeShape, PropertyShape, SPARQLConstraint}
  alias ElixirOntologies.SHACL.Vocabulary, as: SHACL

  require Logger

  # Module attribute for pattern matching (function calls can't be used in patterns)
  @rdf_nil SHACL.rdf_nil()

  # Security limits for regex compilation
  @max_regex_length 500
  @regex_compile_timeout 100

  # Security limit for RDF list depth (prevent stack overflow)
  @max_list_depth 100

  @doc """
  Parse SHACL shapes from an RDF graph into NodeShape structs.

  ## Parameters

  - `shapes_graph` - RDF.Graph.t() containing SHACL shapes (typically loaded from elixir-shapes.ttl)
  - `opts` - Keyword list of options (reserved for future use)

  ## Returns

  - `{:ok, [NodeShape.t()]}` - Successfully parsed list of node shapes
  - `{:error, reason}` - Parse error with diagnostic message

  ## Examples

      iex> {:ok, graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")
      iex> {:ok, shapes} = Reader.parse_shapes(graph)
      iex> length(shapes)
      29
  """
  @spec parse_shapes(RDF.Graph.t(), keyword()) :: {:ok, [NodeShape.t()]} | {:error, term()}
  def parse_shapes(shapes_graph, opts \\ []) do
    with {:ok, shape_iris} <- find_node_shapes(shapes_graph),
         {:ok, shapes} <- parse_all_node_shapes(shapes_graph, shape_iris, opts) do
      {:ok, shapes}
    end
  end

  # Find all NodeShape instances in the graph
  @spec find_node_shapes(RDF.Graph.t()) ::
          {:ok, [RDF.IRI.t() | RDF.BlankNode.t()]} | {:error, term()}
  defp find_node_shapes(graph) do
    shapes =
      graph
      |> RDF.Graph.triples()
      |> Enum.filter(fn {_s, p, o} ->
        p == SHACL.rdf_type() && o == SHACL.node_shape()
      end)
      |> Enum.map(fn {s, _p, _o} -> s end)
      |> Enum.uniq()

    {:ok, shapes}
  end

  # Parse all node shapes
  @spec parse_all_node_shapes(RDF.Graph.t(), [RDF.IRI.t() | RDF.BlankNode.t()], keyword()) ::
          {:ok, [NodeShape.t()]} | {:error, term()}
  defp parse_all_node_shapes(graph, shape_iris, _opts) do
    shapes =
      Enum.reduce_while(shape_iris, [], fn shape_iri, acc ->
        case parse_node_shape(graph, shape_iri) do
          {:ok, shape} -> {:cont, [shape | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case shapes do
      {:error, _} = error -> error
      shapes when is_list(shapes) -> {:ok, Enum.reverse(shapes)}
    end
  end

  # Parse a single node shape
  @spec parse_node_shape(RDF.Graph.t(), RDF.IRI.t() | RDF.BlankNode.t()) ::
          {:ok, NodeShape.t()} | {:error, term()}
  defp parse_node_shape(graph, shape_id) do
    desc = RDF.Graph.description(graph, shape_id)

    with {:ok, target_classes} <- extract_target_classes(desc),
         {:ok, property_shapes} <- parse_property_shapes(graph, desc),
         {:ok, sparql_constraints} <- parse_sparql_constraints(graph, desc, shape_id) do
      {:ok,
       %NodeShape{
         id: shape_id,
         target_classes: target_classes,
         property_shapes: property_shapes,
         sparql_constraints: sparql_constraints
       }}
    end
  end

  # Extract target classes from node shape description
  @spec extract_target_classes(RDF.Description.t()) :: {:ok, [RDF.IRI.t()]} | {:error, term()}
  defp extract_target_classes(desc) do
    target_classes =
      desc
      |> RDF.Description.get(SHACL.target_class(), [])
      |> List.wrap()
      |> Enum.filter(&match?(%RDF.IRI{}, &1))

    {:ok, target_classes}
  end

  # Parse all property shapes for a node shape
  @spec parse_property_shapes(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [PropertyShape.t()]} | {:error, term()}
  defp parse_property_shapes(graph, node_desc) do
    property_ids =
      node_desc
      |> RDF.Description.get(SHACL.property(), [])
      |> List.wrap()

    property_shapes =
      Enum.reduce_while(property_ids, [], fn prop_id, acc ->
        case parse_property_shape(graph, prop_id) do
          {:ok, prop_shape} -> {:cont, [prop_shape | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case property_shapes do
      {:error, _} = error -> error
      shapes when is_list(shapes) -> {:ok, Enum.reverse(shapes)}
    end
  end

  # Parse a single property shape
  @spec parse_property_shape(RDF.Graph.t(), RDF.BlankNode.t() | RDF.IRI.t()) ::
          {:ok, PropertyShape.t()} | {:error, term()}
  defp parse_property_shape(graph, prop_id) do
    desc = RDF.Graph.description(graph, prop_id)

    with {:ok, path} <- extract_required_iri(desc, SHACL.path(), "sh:path"),
         {:ok, message} <- extract_optional_string(desc, SHACL.message()),
         {:ok, min_count} <- extract_optional_integer(desc, SHACL.min_count()),
         {:ok, max_count} <- extract_optional_integer(desc, SHACL.max_count()),
         {:ok, datatype} <- extract_optional_iri(desc, SHACL.datatype()),
         {:ok, class_iri} <- extract_optional_iri(desc, SHACL.class()),
         {:ok, pattern} <- extract_optional_pattern(desc),
         {:ok, min_length} <- extract_optional_integer(desc, SHACL.min_length()),
         {:ok, min_inclusive} <- extract_optional_numeric(desc, SHACL.min_inclusive()),
         {:ok, max_inclusive} <- extract_optional_numeric(desc, SHACL.max_inclusive()),
         {:ok, in_values} <- extract_in_values(graph, desc),
         {:ok, has_value} <- extract_optional_term(desc, SHACL.has_value()),
         {:ok, {qualified_class, qualified_min_count}} <-
           extract_qualified_constraints(graph, desc) do
      {:ok,
       %PropertyShape{
         id: prop_id,
         path: path,
         message: message,
         min_count: min_count,
         max_count: max_count,
         datatype: datatype,
         class: class_iri,
         pattern: pattern,
         min_length: min_length,
         min_inclusive: min_inclusive,
         max_inclusive: max_inclusive,
         in: in_values,
         has_value: has_value,
         qualified_class: qualified_class,
         qualified_min_count: qualified_min_count
       }}
    end
  end

  # Parse SPARQL constraints for a node shape
  @spec parse_sparql_constraints(
          RDF.Graph.t(),
          RDF.Description.t(),
          RDF.IRI.t() | RDF.BlankNode.t()
        ) ::
          {:ok, [SPARQLConstraint.t()]} | {:error, term()}
  defp parse_sparql_constraints(graph, node_desc, shape_id) do
    sparql_ids =
      node_desc
      |> RDF.Description.get(SHACL.sparql(), [])
      |> List.wrap()

    constraints =
      Enum.reduce_while(sparql_ids, [], fn sparql_id, acc ->
        case parse_sparql_constraint(graph, sparql_id, shape_id) do
          {:ok, constraint} -> {:cont, [constraint | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case constraints do
      {:error, _} = error -> error
      constraints when is_list(constraints) -> {:ok, Enum.reverse(constraints)}
    end
  end

  # Parse a single SPARQL constraint
  @spec parse_sparql_constraint(
          RDF.Graph.t(),
          RDF.BlankNode.t() | RDF.IRI.t(),
          RDF.IRI.t() | RDF.BlankNode.t()
        ) ::
          {:ok, SPARQLConstraint.t()} | {:error, term()}
  defp parse_sparql_constraint(graph, sparql_id, source_shape_id) do
    desc = RDF.Graph.description(graph, sparql_id)

    with {:ok, message} <- extract_optional_string(desc, SHACL.message()),
         {:ok, select_query} <- extract_required_string(desc, SHACL.select(), "sh:select"),
         {:ok, prefixes_graph} <- extract_optional_prefixes(desc) do
      {:ok,
       %SPARQLConstraint{
         source_shape_id: source_shape_id,
         message: message,
         select_query: select_query,
         prefixes_graph: prefixes_graph
       }}
    end
  end

  # Helper: Extract required IRI value
  @spec extract_required_iri(RDF.Description.t(), RDF.IRI.t(), String.t()) ::
          {:ok, RDF.IRI.t()} | {:error, term()}
  defp extract_required_iri(desc, predicate, name) do
    values =
      desc
      |> RDF.Description.get(predicate)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case values do
      [] -> {:error, "Missing required property: #{name}"}
      [%RDF.IRI{} = iri | _] -> {:ok, iri}
      _other -> {:error, "Expected IRI for #{name}, got different type"}
    end
  end

  # Helper: Extract optional IRI value
  @spec extract_optional_iri(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, RDF.IRI.t() | nil} | {:error, term()}
  defp extract_optional_iri(desc, predicate) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] -> {:ok, nil}
      [%RDF.IRI{} = iri | _] -> {:ok, iri}
      [_other | _] -> {:ok, nil}
    end
  end

  # Helper: Normalize RDF.Description.get/2 result to a list
  # Handles nil, single values, and lists consistently
  @spec normalize_to_list(term()) :: list()
  defp normalize_to_list(nil), do: []
  defp normalize_to_list(list) when is_list(list), do: list
  defp normalize_to_list(single), do: [single]

  # Helper: Extract required string value
  @spec extract_required_string(RDF.Description.t(), RDF.IRI.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  defp extract_required_string(desc, predicate, name) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] -> {:error, "Missing required property: #{name}"}
      [%RDF.Literal{} = lit | _] -> {:ok, RDF.Literal.value(lit)}
      _other -> {:error, "Expected string literal for #{name}"}
    end
  end

  # Helper: Extract optional string value
  @spec extract_optional_string(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  defp extract_optional_string(desc, predicate) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] -> {:ok, nil}
      [%RDF.Literal{} = lit | _] -> {:ok, RDF.Literal.value(lit)}
      [_other | _] -> {:ok, nil}
    end
  end

  # Helper: Extract optional integer value
  @spec extract_optional_integer(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defp extract_optional_integer(desc, predicate) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [%RDF.Literal{} = lit | _] ->
        value = RDF.Literal.value(lit)

        if is_integer(value) and value >= 0 do
          {:ok, value}
        else
          # Invalid integer value - gracefully ignore
          {:ok, nil}
        end

      [_other | _] ->
        {:ok, nil}
    end
  end

  # Helper: Extract optional numeric value (integer or float)
  @spec extract_optional_numeric(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, integer() | float() | nil} | {:error, term()}
  defp extract_optional_numeric(desc, predicate) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [%RDF.Literal{} = lit | _] ->
        value = RDF.Literal.value(lit)

        cond do
          is_integer(value) -> {:ok, value}
          is_float(value) -> {:ok, value}
          true -> {:ok, nil}
        end

      [_other | _] ->
        {:ok, nil}
    end
  end

  # Helper: Extract optional term (any RDF term)
  @spec extract_optional_term(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, RDF.Term.t() | nil} | {:error, term()}
  defp extract_optional_term(desc, predicate) do
    {:ok, RDF.Description.get(desc, predicate)}
  end

  # Helper: Extract and compile regex pattern with security limits
  @spec extract_optional_pattern(RDF.Description.t()) :: {:ok, Regex.t() | nil} | {:error, term()}
  defp extract_optional_pattern(desc) do
    values = desc |> RDF.Description.get(SHACL.pattern()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [%RDF.Literal{} = lit | _] ->
        pattern_string = RDF.Literal.value(lit)

        # Security check: Reject patterns that are too long (ReDoS prevention)
        if byte_size(pattern_string) > @max_regex_length do
          Logger.warning(
            "Skipping regex pattern that exceeds maximum length: " <>
              "#{byte_size(pattern_string)} bytes (max: #{@max_regex_length})"
          )

          {:ok, nil}
        else
          # Compile with timeout to prevent ReDoS attacks
          compile_with_timeout(pattern_string, @regex_compile_timeout)
        end

      [_other | _] ->
        {:ok, nil}
    end
  end

  # Compile regex with timeout protection against ReDoS
  @spec compile_with_timeout(String.t(), non_neg_integer()) ::
          {:ok, Regex.t() | nil} | {:error, term()}
  defp compile_with_timeout(pattern_string, timeout_ms) do
    task = Task.async(fn -> Regex.compile(pattern_string) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, regex}} ->
        {:ok, regex}

      {:ok, {:error, reason}} ->
        Logger.warning("Regex compilation failed: #{inspect(reason)}")
        {:ok, nil}

      nil ->
        Logger.warning(
          "Regex compilation timed out after #{timeout_ms}ms - " <>
            "potential ReDoS pattern: #{String.slice(pattern_string, 0, 50)}..."
        )

        {:ok, nil}

      {:exit, reason} ->
        Logger.warning("Regex compilation process exited: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  # Helper: Extract sh:in values from RDF list
  @spec extract_in_values(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.Term.t()]} | {:error, term()}
  defp extract_in_values(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.in_values()) |> normalize_to_list()

    case values do
      [] -> {:ok, []}
      [list_head | _] -> parse_rdf_list(graph, list_head)
    end
  end

  # Helper: Parse RDF list into Elixir list with depth limit
  @spec parse_rdf_list(RDF.Graph.t(), RDF.Term.t(), non_neg_integer()) ::
          {:ok, [RDF.Term.t()]} | {:error, term()}
  defp parse_rdf_list(graph, list_node, depth \\ 0)

  defp parse_rdf_list(_graph, @rdf_nil, _depth), do: {:ok, []}

  defp parse_rdf_list(_graph, _node, depth) when depth > @max_list_depth do
    Logger.warning("RDF list depth limit exceeded (max: #{@max_list_depth})")
    {:error, "RDF list depth limit exceeded (max: #{@max_list_depth})"}
  end

  defp parse_rdf_list(graph, list_node, depth) do
    desc = RDF.Graph.description(graph, list_node)

    first_values = desc |> RDF.Description.get(SHACL.rdf_first()) |> normalize_to_list()
    rest_values = desc |> RDF.Description.get(SHACL.rdf_rest()) |> normalize_to_list()

    with [first | _] <- first_values,
         [rest | _] <- rest_values,
         {:ok, rest_list} <- parse_rdf_list(graph, rest, depth + 1) do
      {:ok, [first | rest_list]}
    else
      [] -> {:error, "Malformed RDF list: missing rdf:first or rdf:rest"}
      error -> error
    end
  end

  # Helper: Extract qualified constraints
  @spec extract_qualified_constraints(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, {RDF.IRI.t() | nil, non_neg_integer() | nil}} | {:error, term()}
  defp extract_qualified_constraints(graph, desc) do
    qualified_shape_values =
      desc |> RDF.Description.get(SHACL.qualified_value_shape()) |> normalize_to_list()

    case qualified_shape_values do
      [] ->
        {:ok, {nil, nil}}

      [qualified_shape_id | _] ->
        qualified_desc = RDF.Graph.description(graph, qualified_shape_id)

        with {:ok, qualified_class} <- extract_optional_iri(qualified_desc, SHACL.class()),
             {:ok, qualified_min_count} <- extract_optional_integer(desc, SHACL.qualified_min_count()) do
          {:ok, {qualified_class, qualified_min_count}}
        end
    end
  end

  # Helper: Extract optional prefixes (not currently used, reserved for future)
  @spec extract_optional_prefixes(RDF.Description.t()) :: {:ok, RDF.Graph.t() | nil}
  defp extract_optional_prefixes(_desc) do
    # Prefixes are currently not parsed; we'll use the shapes graph's prefixes
    {:ok, nil}
  end
end
