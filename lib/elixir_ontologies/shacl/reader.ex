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
         {:ok, top_level_shapes} <- parse_all_node_shapes(shapes_graph, shape_iris, opts),
         {:ok, all_shapes} <- parse_inline_shapes(shapes_graph, top_level_shapes, opts) do
      {:ok, all_shapes}
    end
  end

  # Recursively parse inline shapes referenced in logical operators
  # This handles cases like sh:and ( [ sh:property [...] ] [ sh:property [...] ] )
  # where the shapes are defined inline without explicit sh:NodeShape typing
  # Also handles named shape references (IRIs) that aren't explicitly typed as sh:NodeShape
  @spec parse_inline_shapes(RDF.Graph.t(), [NodeShape.t()], keyword()) ::
          {:ok, [NodeShape.t()]} | {:error, term()}
  defp parse_inline_shapes(graph, shapes, opts) do
    # Recursively discover and parse inline shapes until no new ones are found
    parse_inline_shapes_recursive(graph, shapes, MapSet.new(Enum.map(shapes, & &1.id)), opts)
  end

  # Recursive helper for parse_inline_shapes
  defp parse_inline_shapes_recursive(graph, shapes, parsed_ids, opts) do
    # Collect all shape references from logical operators
    referenced_shape_ids =
      shapes
      |> Enum.flat_map(&collect_logical_shape_refs/1)
      |> MapSet.new()

    # Find referenced shapes (blank nodes or IRIs) that haven't been parsed yet
    new_shape_refs =
      referenced_shape_ids
      |> Enum.filter(fn ref ->
        (match?(%RDF.BlankNode{}, ref) || match?(%RDF.IRI{}, ref)) &&
        !MapSet.member?(parsed_ids, ref)
      end)

    # If no new shapes to parse, we're done
    if Enum.empty?(new_shape_refs) do
      {:ok, shapes}
    else
      # Parse the new referenced shapes (both blank nodes and IRIs)
      case parse_all_node_shapes(graph, new_shape_refs, opts) do
        {:ok, new_shapes} ->
          # Update parsed IDs and shapes, then recurse
          updated_ids = MapSet.union(parsed_ids, MapSet.new(Enum.map(new_shapes, & &1.id)))
          updated_shapes = shapes ++ new_shapes
          parse_inline_shapes_recursive(graph, updated_shapes, updated_ids, opts)

        error ->
          error
      end
    end
  end

  # Collect all shape references from logical operators in a NodeShape
  defp collect_logical_shape_refs(%NodeShape{} = shape) do
    []
    |> concat_list(shape.node_and || [])
    |> concat_list(shape.node_or || [])
    |> concat_list(shape.node_xone || [])
    |> concat_single(shape.node_not)
  end

  # Helper: Concatenate a list to results
  defp concat_list(results, list) when is_list(list), do: results ++ list
  defp concat_list(results, _), do: results

  # Helper: Concatenate a single value to results
  defp concat_single(results, nil), do: results
  defp concat_single(results, value), do: results ++ [value]

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
         {:ok, target_nodes} <- extract_target_nodes(desc),
         {:ok, implicit_class_target} <- extract_implicit_class_target(desc, shape_id),
         {:ok, message} <- extract_optional_string(desc, SHACL.message()),
         {:ok, node_constraints} <- extract_node_constraints(graph, desc),
         {:ok, property_shapes} <- parse_property_shapes(graph, desc),
         {:ok, sparql_constraints} <- parse_sparql_constraints(graph, desc, shape_id) do
      {:ok,
       %NodeShape{
         id: shape_id,
         target_classes: target_classes,
         target_nodes: target_nodes,
         implicit_class_target: implicit_class_target,
         message: message,
         property_shapes: property_shapes,
         sparql_constraints: sparql_constraints,
         # Node-level constraints
         node_datatype: node_constraints[:datatype],
         node_class: node_constraints[:class],
         node_node_kind: node_constraints[:node_kind],
         node_min_inclusive: node_constraints[:min_inclusive],
         node_max_inclusive: node_constraints[:max_inclusive],
         node_min_exclusive: node_constraints[:min_exclusive],
         node_max_exclusive: node_constraints[:max_exclusive],
         node_min_length: node_constraints[:min_length],
         node_max_length: node_constraints[:max_length],
         node_pattern: node_constraints[:pattern],
         node_in: node_constraints[:in],
         node_has_value: node_constraints[:has_value],
         node_language_in: node_constraints[:language_in],
         # Logical operators
         node_and: node_constraints[:node_and],
         node_or: node_constraints[:node_or],
         node_xone: node_constraints[:node_xone],
         node_not: node_constraints[:node_not]
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

  # Extract explicit target nodes from node shape description
  # sh:targetNode can target any RDF term (IRIs, literals, blank nodes)
  @spec extract_target_nodes(RDF.Description.t()) :: {:ok, [RDF.Term.t()]} | {:error, term()}
  defp extract_target_nodes(desc) do
    target_nodes =
      desc
      |> RDF.Description.get(SHACL.target_node(), [])
      |> List.wrap()

    {:ok, target_nodes}
  end

  # Extract implicit class target per SHACL 2.1.3.1
  # When a shape is also defined as an rdfs:Class, it implicitly targets
  # all instances of that class
  @spec extract_implicit_class_target(RDF.Description.t(), RDF.IRI.t() | RDF.BlankNode.t()) ::
          {:ok, RDF.IRI.t() | nil} | {:error, term()}
  defp extract_implicit_class_target(desc, shape_id) do
    # Check if this shape also has rdf:type rdfs:Class
    types =
      desc
      |> RDF.Description.get(SHACL.rdf_type(), [])
      |> List.wrap()

    # RDFS.Class IRI
    rdfs_class = RDF.iri("http://www.w3.org/2000/01/rdf-schema#Class")

    is_class? = Enum.any?(types, fn type -> type == rdfs_class end)

    # If the shape is also a class, use its own IRI as implicit target
    # (only for named shapes with IRIs, not blank nodes)
    implicit_target =
      if is_class? && match?(%RDF.IRI{}, shape_id) do
        shape_id
      else
        nil
      end

    {:ok, implicit_target}
  end

  # Extract node-level constraints from node shape description
  # These are constraints applied directly to focus nodes (not to their properties)
  @spec extract_node_constraints(RDF.Graph.t(), RDF.Description.t()) :: {:ok, map()} | {:error, term()}
  defp extract_node_constraints(graph, desc) do
    with {:ok, datatype} <- extract_optional_iri(desc, SHACL.datatype()),
         {:ok, class_iri} <- extract_optional_iri(desc, SHACL.class()),
         {:ok, node_kind} <- extract_optional_node_kind(desc),
         {:ok, min_inclusive} <- extract_optional_literal(desc, SHACL.min_inclusive()),
         {:ok, max_inclusive} <- extract_optional_literal(desc, SHACL.max_inclusive()),
         {:ok, min_exclusive} <- extract_optional_literal(desc, SHACL.min_exclusive()),
         {:ok, max_exclusive} <- extract_optional_literal(desc, SHACL.max_exclusive()),
         {:ok, min_length} <- extract_optional_integer(desc, SHACL.min_length()),
         {:ok, max_length} <- extract_optional_integer(desc, SHACL.max_length()),
         {:ok, pattern} <- extract_optional_pattern(desc),
         {:ok, in_values} <- extract_node_in_values(graph, desc),
         {:ok, has_value} <- extract_optional_term(desc, SHACL.has_value()),
         {:ok, language_in} <- extract_optional_language_in(graph, desc),
         {:ok, node_and} <- extract_logical_and(graph, desc),
         {:ok, node_or} <- extract_logical_or(graph, desc),
         {:ok, node_xone} <- extract_logical_xone(graph, desc),
         {:ok, node_not} <- extract_logical_not(desc) do
      {:ok,
       %{
         datatype: datatype,
         class: class_iri,
         node_kind: node_kind,
         min_inclusive: min_inclusive,
         max_inclusive: max_inclusive,
         min_exclusive: min_exclusive,
         max_exclusive: max_exclusive,
         min_length: min_length,
         max_length: max_length,
         pattern: pattern,
         in: in_values,
         has_value: has_value,
         language_in: language_in,
         node_and: node_and,
         node_or: node_or,
         node_xone: node_xone,
         node_not: node_not
       }}
    end
  end

  # Helper: Extract sh:in values from RDF list (for node-level constraints)
  @spec extract_node_in_values(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.Term.t()] | nil} | {:error, term()}
  defp extract_node_in_values(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.in_values()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [list_head | _] ->
        case parse_rdf_list(graph, list_head, 0) do
          {:ok, []} -> {:ok, nil}
          # Empty list = no constraint
          {:ok, items} -> {:ok, items}
          error -> error
        end
    end
  end

  # Helper: Extract sh:and logical operator (all shapes must conform)
  @spec extract_logical_and(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.IRI.t() | RDF.BlankNode.t()] | nil} | {:error, term()}
  defp extract_logical_and(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.and_operator()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [list_head | _] ->
        case parse_rdf_list(graph, list_head, 0) do
          {:ok, []} -> {:ok, nil}
          {:ok, shape_refs} -> {:ok, shape_refs}
          error -> error
        end
    end
  end

  # Helper: Extract sh:or logical operator (at least one shape must conform)
  @spec extract_logical_or(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.IRI.t() | RDF.BlankNode.t()] | nil} | {:error, term()}
  defp extract_logical_or(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.or_operator()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [list_head | _] ->
        case parse_rdf_list(graph, list_head, 0) do
          {:ok, []} -> {:ok, nil}
          {:ok, shape_refs} -> {:ok, shape_refs}
          error -> error
        end
    end
  end

  # Helper: Extract sh:xone logical operator (exactly one shape must conform)
  @spec extract_logical_xone(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [RDF.IRI.t() | RDF.BlankNode.t()] | nil} | {:error, term()}
  defp extract_logical_xone(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.xone_operator()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [list_head | _] ->
        case parse_rdf_list(graph, list_head, 0) do
          {:ok, []} -> {:ok, nil}
          {:ok, shape_refs} -> {:ok, shape_refs}
          error -> error
        end
    end
  end

  # Helper: Extract sh:not logical operator (shape must NOT conform)
  @spec extract_logical_not(RDF.Description.t()) ::
          {:ok, RDF.IRI.t() | RDF.BlankNode.t() | nil} | {:error, term()}
  defp extract_logical_not(desc) do
    # sh:not takes a single shape reference, not a list
    # RDF.Description.get may return a list, so we normalize and take first value
    value =
      case desc |> RDF.Description.get(SHACL.not_operator()) |> normalize_to_list() do
        [] -> nil
        [first | _] -> first
      end

    {:ok, value}
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

  # Helper: Extract optional numeric literal (returns the literal, not the value)
  @spec extract_optional_literal(RDF.Description.t(), RDF.IRI.t()) ::
          {:ok, RDF.Literal.t() | nil} | {:error, term()}
  defp extract_optional_literal(desc, predicate) do
    values = desc |> RDF.Description.get(predicate) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [%RDF.Literal{} = lit | _] ->
        {:ok, lit}

      [_other | _] ->
        {:ok, nil}
    end
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

  # Helper: Extract optional node kind
  @spec extract_optional_node_kind(RDF.Description.t()) :: {:ok, atom() | nil}
  defp extract_optional_node_kind(desc) do
    case RDF.Description.get(desc, SHACL.node_kind()) do
      nil ->
        {:ok, nil}

      values when is_list(values) ->
        # Take first value if multiple
        parse_node_kind(List.first(values))

      value ->
        parse_node_kind(value)
    end
  end

  # Helper: Parse node kind IRI to atom
  defp parse_node_kind(%RDF.IRI{} = iri) do
    case to_string(iri) do
      "http://www.w3.org/ns/shacl#IRI" -> {:ok, :iri}
      "http://www.w3.org/ns/shacl#BlankNode" -> {:ok, :blank_node}
      "http://www.w3.org/ns/shacl#Literal" -> {:ok, :literal}
      "http://www.w3.org/ns/shacl#BlankNodeOrIRI" -> {:ok, :blank_node_or_iri}
      "http://www.w3.org/ns/shacl#BlankNodeOrLiteral" -> {:ok, :blank_node_or_literal}
      "http://www.w3.org/ns/shacl#IRIOrLiteral" -> {:ok, :iri_or_literal}
      _ -> {:ok, nil}
    end
  end

  defp parse_node_kind(_), do: {:ok, nil}

  # Helper: Extract optional language tags (sh:languageIn)
  @spec extract_optional_language_in(RDF.Graph.t(), RDF.Description.t()) ::
          {:ok, [String.t()] | nil} | {:error, term()}
  defp extract_optional_language_in(graph, desc) do
    values = desc |> RDF.Description.get(SHACL.language_in()) |> normalize_to_list()

    case values do
      [] ->
        {:ok, nil}

      [list_head | _] ->
        case parse_rdf_list(graph, list_head, 0) do
          {:ok, []} ->
            {:ok, nil}

          {:ok, literals} ->
            # Extract language tags as strings
            language_tags =
              Enum.map(literals, fn lit ->
                case lit do
                  %RDF.Literal{} -> RDF.Literal.value(lit)
                  other -> to_string(other)
                end
              end)

            {:ok, language_tags}

          error ->
            error
        end
    end
  end
end
