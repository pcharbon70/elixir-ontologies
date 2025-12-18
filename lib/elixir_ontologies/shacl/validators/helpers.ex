defmodule ElixirOntologies.SHACL.Validators.Helpers do
  @moduledoc """
  Shared helper functions for SHACL constraint validators.

  This module provides common utilities used across all validator modules:
  - Extracting property values from RDF graphs
  - Building ValidationResult structs
  - Extracting literal values and checking RDF types

  ## Usage

      alias ElixirOntologies.SHACL.Validators.Helpers

      # Extract property values
      values = Helpers.get_property_values(graph, focus_node, property_path)

      # Build validation result for a violation
      result = Helpers.build_violation(
        focus_node,
        property_shape,
        "Required property is missing",
        %{expected_count: 1, actual_count: 0}
      )
  """

  alias ElixirOntologies.SHACL.Model.{NodeShape, PropertyShape, ValidationResult}

  @doc """
  Extract all values for a given property path from a focus node.

  Returns a list of RDF terms (IRIs, blank nodes, or literals) that are
  the objects of triples with the given subject and predicate.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() subject node
  - `property_path` - RDF.IRI.t() predicate IRI

  ## Returns

  List of RDF terms (may be empty if property is not present)

  ## Examples

      iex> graph = RDF.Graph.new([
      ...>   {~I<http://example.org/Module1>, ~I<http://example.org/hasName>, "MyModule"}
      ...> ])
      iex> values = get_property_values(graph, ~I<http://example.org/Module1>, ~I<http://example.org/hasName>)
      iex> length(values)
      1
  """
  @spec get_property_values(RDF.Graph.t(), RDF.Term.t(), RDF.IRI.t()) :: [RDF.Term.t()]
  def get_property_values(data_graph, focus_node, property_path) do
    case RDF.Graph.description(data_graph, focus_node) do
      nil ->
        []

      desc ->
        desc
        |> RDF.Description.get(property_path)
        |> normalize_to_list()
    end
  end

  # Normalize RDF.Description.get result to a list
  defp normalize_to_list(nil), do: []
  defp normalize_to_list(list) when is_list(list), do: list
  defp normalize_to_list(single), do: [single]

  @doc """
  Build a ValidationResult struct for a constraint violation.

  Creates a ValidationResult with severity :violation and the provided details.

  ## Parameters

  - `focus_node` - RDF.Term.t() node that violated the constraint
  - `property_shape` - PropertyShape.t() containing path, id, and optional message
  - `default_message` - String.t() default message if property_shape.message is nil
  - `details` - map() additional details about the violation

  ## Returns

  ValidationResult.t() struct

  ## Examples

      iex> property_shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/hasName>,
      ...>   message: "Name is required"
      ...> }
      iex> result = build_violation(
      ...>   ~I<http://example.org/Module1>,
      ...>   property_shape,
      ...>   "Default message",
      ...>   %{expected: 1, actual: 0}
      ...> )
      iex> result.severity
      :violation
  """
  @spec build_violation(RDF.Term.t(), PropertyShape.t(), String.t(), map()) ::
          ValidationResult.t()
  def build_violation(focus_node, property_shape, default_message, details) do
    %ValidationResult{
      focus_node: focus_node,
      path: property_shape.path,
      source_shape: property_shape.id,
      severity: :violation,
      message: property_shape.message || default_message,
      details: details
    }
  end

  @doc """
  Build a ValidationResult struct for a node-level constraint violation.

  Creates a ValidationResult with severity :violation for constraints applied
  directly to the focus node (not to its properties).

  ## Parameters

  - `focus_node` - RDF.Term.t() node that violated the constraint
  - `node_shape` - NodeShape.t() containing id and optional message
  - `default_message` - String.t() default message if node_shape.message is nil
  - `details` - map() additional details about the violation

  ## Returns

  ValidationResult.t() struct with path set to nil (node-level constraints have no path)

  ## Examples

      iex> node_shape = %NodeShape{
      ...>   id: ~I<http://example.org/shapes/PersonShape>,
      ...>   message: "Must be a literal"
      ...> }
      iex> result = build_node_violation(
      ...>   ~I<http://example.org/Person1>,
      ...>   node_shape,
      ...>   "Default message",
      ...>   %{constraint_component: SHACL.NodeKindConstraintComponent}
      ...> )
      iex> result.severity
      :violation
  """
  @spec build_node_violation(RDF.Term.t(), NodeShape.t(), String.t(), map()) ::
          ValidationResult.t()
  def build_node_violation(focus_node, node_shape, default_message, details) do
    %ValidationResult{
      focus_node: focus_node,
      path: nil,
      source_shape: node_shape.id,
      severity: :violation,
      message: node_shape.message || default_message,
      details: details
    }
  end

  @doc """
  Extract the string value from an RDF literal.

  Returns nil if the term is not a literal or has no lexical form.

  ## Parameters

  - `term` - RDF.Term.t()

  ## Returns

  String.t() | nil

  ## Examples

      iex> literal = RDF.Literal.new("hello", datatype: RDF.XSD.string())
      iex> extract_string(literal)
      "hello"

      iex> extract_string(~I<http://example.org/NotALiteral>)
      nil
  """
  @spec extract_string(RDF.Term.t()) :: String.t() | nil
  def extract_string(%RDF.Literal{} = literal) do
    RDF.Literal.lexical(literal)
  end

  def extract_string(_non_literal), do: nil

  @doc """
  Extract the numeric value from an RDF literal.

  Returns nil if the term is not a numeric literal.

  ## Parameters

  - `term` - RDF.Term.t()

  ## Returns

  number() | nil (integer or float)

  ## Examples

      iex> literal = RDF.Literal.new(42, datatype: RDF.XSD.integer())
      iex> extract_number(literal)
      42

      iex> extract_number(~I<http://example.org/NotANumber>)
      nil
  """
  @spec extract_number(RDF.Term.t()) :: number() | nil
  def extract_number(%RDF.Literal{} = literal) do
    value = RDF.Literal.value(literal)

    if is_number(value) do
      value
    else
      nil
    end
  end

  def extract_number(_non_literal), do: nil

  @doc """
  Check if an RDF term is a literal with the specified datatype.

  ## Parameters

  - `term` - RDF.Term.t() to check
  - `datatype_iri` - RDF.IRI.t() expected datatype IRI

  ## Returns

  boolean()

  ## Examples

      iex> literal = RDF.Literal.new("hello", datatype: RDF.XSD.string())
      iex> is_datatype?(literal, RDF.XSD.string())
      true

      iex> is_datatype?(~I<http://example.org/IRI>, RDF.XSD.string())
      false
  """
  @spec is_datatype?(RDF.Term.t(), RDF.IRI.t()) :: boolean()
  def is_datatype?(%RDF.Literal{} = literal, datatype_iri) do
    RDF.Literal.datatype_id(literal) == datatype_iri
  end

  def is_datatype?(_non_literal, _datatype_iri), do: false

  @doc """
  Check if an RDF term is an instance of the specified class.

  Uses rdf:type to determine if the term has the given class.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing type assertions
  - `term` - RDF.Term.t() to check (must be IRI or blank node)
  - `class_iri` - RDF.IRI.t() expected class IRI

  ## Returns

  boolean()

  ## Examples

      iex> graph = RDF.Graph.new([
      ...>   {~I<http://example.org/Module1>, RDF.type(), ~I<http://example.org/Module>}
      ...> ])
      iex> is_instance_of?(graph, ~I<http://example.org/Module1>, ~I<http://example.org/Module>)
      true

      iex> is_instance_of?(graph, ~I<http://example.org/Module1>, ~I<http://example.org/Function>)
      false
  """
  @spec is_instance_of?(RDF.Graph.t(), RDF.Term.t(), RDF.IRI.t()) :: boolean()
  def is_instance_of?(data_graph, term, class_iri) do
    # Literals cannot be instances of classes
    case term do
      %RDF.Literal{} ->
        false

      _ ->
        # Check if term has rdf:type class_iri
        types = get_property_values(data_graph, term, RDF.type())
        Enum.member?(types, class_iri)
    end
  end

  @doc """
  Check if an RDF term matches the specified node kind.

  Node kinds from SHACL specification:
  - :iri - Term must be an IRI
  - :blank_node - Term must be a blank node
  - :literal - Term must be a literal
  - :blank_node_or_iri - Term must be a blank node or IRI
  - :blank_node_or_literal - Term must be a blank node or literal
  - :iri_or_literal - Term must be an IRI or literal

  ## Parameters

  - `term` - RDF.Term.t() to check
  - `node_kind` - atom() one of the node kinds listed above

  ## Returns

  boolean()

  ## Examples

      iex> is_node_kind?(~I<http://example.org/Module1>, :iri)
      true

      iex> is_node_kind?(RDF.Literal.new("hello"), :literal)
      true

      iex> is_node_kind?(~I<http://example.org/Module1>, :literal)
      false
  """
  @spec is_node_kind?(RDF.Term.t(), atom()) :: boolean()
  def is_node_kind?(term, node_kind) do
    case node_kind do
      :iri -> match?(%RDF.IRI{}, term)
      :blank_node -> match?(%RDF.BlankNode{}, term)
      :literal -> match?(%RDF.Literal{}, term)
      :blank_node_or_iri -> match?(%RDF.BlankNode{}, term) or match?(%RDF.IRI{}, term)
      :blank_node_or_literal -> match?(%RDF.BlankNode{}, term) or match?(%RDF.Literal{}, term)
      :iri_or_literal -> match?(%RDF.IRI{}, term) or match?(%RDF.Literal{}, term)
      _ -> false
    end
  end
end
