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

  # SHACL Vocabulary
  @sh_node_shape RDF.iri("http://www.w3.org/ns/shacl#NodeShape")
  @sh_target_class RDF.iri("http://www.w3.org/ns/shacl#targetClass")
  @sh_property RDF.iri("http://www.w3.org/ns/shacl#property")
  @sh_sparql RDF.iri("http://www.w3.org/ns/shacl#sparql")

  # Property Constraint Vocabulary
  @sh_path RDF.iri("http://www.w3.org/ns/shacl#path")
  @sh_message RDF.iri("http://www.w3.org/ns/shacl#message")
  @sh_min_count RDF.iri("http://www.w3.org/ns/shacl#minCount")
  @sh_max_count RDF.iri("http://www.w3.org/ns/shacl#maxCount")
  @sh_datatype RDF.iri("http://www.w3.org/ns/shacl#datatype")
  @sh_class RDF.iri("http://www.w3.org/ns/shacl#class")
  @sh_pattern RDF.iri("http://www.w3.org/ns/shacl#pattern")
  @sh_min_length RDF.iri("http://www.w3.org/ns/shacl#minLength")
  @sh_in RDF.iri("http://www.w3.org/ns/shacl#in")
  @sh_has_value RDF.iri("http://www.w3.org/ns/shacl#hasValue")
  @sh_qualified_value_shape RDF.iri("http://www.w3.org/ns/shacl#qualifiedValueShape")
  @sh_qualified_min_count RDF.iri("http://www.w3.org/ns/shacl#qualifiedMinCount")

  # SPARQL Constraint Vocabulary
  @sh_select RDF.iri("http://www.w3.org/ns/shacl#select")

  # RDF Vocabulary
  @rdf_type RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  @rdf_first RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#first")
  @rdf_rest RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest")
  @rdf_nil RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")

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
        p == @rdf_type && o == @sh_node_shape
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
      |> RDF.Description.get(@sh_target_class, [])
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
      |> RDF.Description.get(@sh_property, [])
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

    with {:ok, path} <- extract_required_iri(desc, @sh_path, "sh:path"),
         {:ok, message} <- extract_optional_string(desc, @sh_message),
         {:ok, min_count} <- extract_optional_integer(desc, @sh_min_count),
         {:ok, max_count} <- extract_optional_integer(desc, @sh_max_count),
         {:ok, datatype} <- extract_optional_iri(desc, @sh_datatype),
         {:ok, class_iri} <- extract_optional_iri(desc, @sh_class),
         {:ok, pattern} <- extract_optional_pattern(desc),
         {:ok, min_length} <- extract_optional_integer(desc, @sh_min_length),
         {:ok, in_values} <- extract_in_values(graph, desc),
         {:ok, has_value} <- extract_optional_term(desc, @sh_has_value),
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
      |> RDF.Description.get(@sh_sparql, [])
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

    with {:ok, message} <- extract_optional_string(desc, @sh_message),
         {:ok, select_query} <- extract_required_string(desc, @sh_select, "sh:select"),
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
    values =
      desc
      |> RDF.Description.get(predicate)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case values do
      [] -> {:ok, nil}
      [%RDF.IRI{} = iri | _] -> {:ok, iri}
      [_other | _] -> {:ok, nil}
    end
  end

  # Helper: Extract required string value
  @spec extract_required_string(RDF.Description.t(), RDF.IRI.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  defp extract_required_string(desc, predicate, name) do
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
      [%RDF.Literal{} = lit | _] -> {:ok, RDF.Literal.value(lit)}
      _other -> {:error, "Expected string literal for #{name}"}
    end
  end

  # Helper: Extract optional string value
  @spec extract_optional_string(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  defp extract_optional_string(desc, predicate) do
    values =
      desc
      |> RDF.Description.get(predicate)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

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
    values =
      desc
      |> RDF.Description.get(predicate)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case values do
      [] -> {:ok, nil}
      [%RDF.Literal{} = lit | _] -> {:ok, RDF.Literal.value(lit)}
      [_other | _] -> {:ok, nil}
    end
  end

  # Helper: Extract optional term (any RDF term)
  @spec extract_optional_term(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, RDF.Term.t() | nil} | {:error, term()}
  defp extract_optional_term(desc, predicate) do
    {:ok, RDF.Description.get(desc, predicate)}
  end

  # Helper: Extract and compile regex pattern
  @spec extract_optional_pattern(RDF.Description.t()) :: {:ok, Regex.t() | nil} | {:error, term()}
  defp extract_optional_pattern(desc) do
    values =
      desc
      |> RDF.Description.get(@sh_pattern)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case values do
      [] ->
        {:ok, nil}

      [%RDF.Literal{} = lit | _] ->
        pattern_string = RDF.Literal.value(lit)

        case Regex.compile(pattern_string) do
          {:ok, regex} -> {:ok, regex}
          {:error, reason} -> {:error, "Failed to compile regex pattern: #{inspect(reason)}"}
        end

      [_other | _] ->
        {:ok, nil}
    end
  end

  # Helper: Extract sh:in values from RDF list
  @spec extract_in_values(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.Term.t()]} | {:error, term()}
  defp extract_in_values(graph, desc) do
    values =
      desc
      |> RDF.Description.get(@sh_in)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case values do
      [] -> {:ok, []}
      [list_head | _] -> parse_rdf_list(graph, list_head)
    end
  end

  # Helper: Parse RDF list into Elixir list
  @spec parse_rdf_list(RDF.Graph.t(), RDF.Term.t()) :: {:ok, [RDF.Term.t()]} | {:error, term()}
  defp parse_rdf_list(_graph, @rdf_nil), do: {:ok, []}

  defp parse_rdf_list(graph, list_node) do
    desc = RDF.Graph.description(graph, list_node)

    first_values =
      desc
      |> RDF.Description.get(@rdf_first)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    rest_values =
      desc
      |> RDF.Description.get(@rdf_rest)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    with [first | _] <- first_values,
         [rest | _] <- rest_values,
         {:ok, rest_list} <- parse_rdf_list(graph, rest) do
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
      desc
      |> RDF.Description.get(@sh_qualified_value_shape)
      |> case do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    case qualified_shape_values do
      [] ->
        {:ok, {nil, nil}}

      [qualified_shape_id | _] ->
        qualified_desc = RDF.Graph.description(graph, qualified_shape_id)

        with {:ok, qualified_class} <- extract_optional_iri(qualified_desc, @sh_class),
             {:ok, qualified_min_count} <- extract_optional_integer(desc, @sh_qualified_min_count) do
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
