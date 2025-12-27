defmodule ElixirOntologies.Builders.Helpers do
  @moduledoc """
  Helper functions for RDF triple generation in builders.

  This module provides common utilities for constructing RDF triples,
  handling datatypes, creating RDF lists, and working with object properties.

  ## Usage

      alias ElixirOntologies.Builders.Helpers
      alias ElixirOntologies.NS.Structure

      # Generate rdf:type triple
      type_triple = Helpers.type_triple(subject_iri, Structure.Module)

      # Generate datatype property triple
      name_triple = Helpers.datatype_property(subject_iri, Structure.moduleName(), "MyApp", RDF.XSD.string())

      # Generate object property triple
      belongs_triple = Helpers.object_property(function_iri, Structure.belongsTo(), module_iri)

      # Build an RDF list
      {list_head, list_triples} = Helpers.build_rdf_list([item1, item2, item3])
  """

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  @doc """
  Generates an `rdf:type` triple.

  ## Parameters

  - `subject` - The subject IRI or blank node
  - `class` - The RDF class IRI

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> subject = ~I<https://example.org/code#MyApp>
      iex> triple = ElixirOntologies.Builders.Helpers.type_triple(subject, Structure.Module)
      iex> {s, _p, _o} = triple
      iex> s
      ~I<https://example.org/code#MyApp>
  """
  @spec type_triple(RDF.IRI.t() | RDF.BlankNode.t(), RDF.IRI.t()) :: RDF.Triple.t()
  def type_triple(subject, class) do
    {subject, RDF.type(), class}
  end

  @doc """
  Generates a datatype property triple.

  Creates a triple with a literal value of the specified datatype.

  ## Parameters

  - `subject` - The subject IRI or blank node
  - `predicate` - The property IRI
  - `value` - The literal value
  - `datatype` - The XSD datatype IRI (optional, defaults to xsd:string)

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> subject = ~I<https://example.org/code#MyApp>
      iex> triple = ElixirOntologies.Builders.Helpers.datatype_property(
      ...>   subject,
      ...>   Structure.moduleName(),
      ...>   "MyApp",
      ...>   RDF.XSD.String
      ...> )
      iex> {_s, _p, o} = triple
      iex> RDF.Literal.value(o)
      "MyApp"

      iex> alias ElixirOntologies.NS.Structure
      iex> subject = ~I<https://example.org/code#MyApp/hello/0>
      iex> triple = ElixirOntologies.Builders.Helpers.datatype_property(
      ...>   subject,
      ...>   Structure.arity(),
      ...>   0,
      ...>   RDF.XSD.NonNegativeInteger
      ...> )
      iex> {_s, _p, o} = triple
      iex> RDF.Literal.value(o)
      0
  """
  @spec datatype_property(
          RDF.IRI.t() | RDF.BlankNode.t(),
          RDF.IRI.t(),
          term(),
          module() | nil
        ) :: RDF.Triple.t()
  def datatype_property(subject, predicate, value, datatype_module \\ nil) do
    literal =
      if datatype_module do
        # Use the datatype module's constructor (e.g., RDF.XSD.String.new/1)
        datatype_module.new(value)
      else
        RDF.literal(value)
      end

    {subject, predicate, literal}
  end

  @doc """
  Generates an object property triple.

  Creates a triple connecting two resources (subject and object).

  ## Parameters

  - `subject` - The subject IRI or blank node
  - `predicate` - The property IRI
  - `object` - The object IRI or blank node

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> function_iri = ~I<https://example.org/code#MyApp/hello/0>
      iex> module_iri = ~I<https://example.org/code#MyApp>
      iex> triple = ElixirOntologies.Builders.Helpers.object_property(
      ...>   function_iri,
      ...>   Structure.belongsTo(),
      ...>   module_iri
      ...> )
      iex> {s, _p, o} = triple
      iex> s == function_iri and o == module_iri
      true
  """
  @spec object_property(
          RDF.IRI.t() | RDF.BlankNode.t(),
          RDF.IRI.t(),
          RDF.IRI.t() | RDF.BlankNode.t()
        ) :: RDF.Triple.t()
  def object_property(subject, predicate, object) do
    {subject, predicate, object}
  end

  # ===========================================================================
  # RDF List Construction
  # ===========================================================================

  @doc """
  Builds an RDF list from a collection of items.

  Creates the rdf:List structure with rdf:first and rdf:rest triples,
  returning both the list head IRI and all necessary triples.

  ## Parameters

  - `items` - List of RDF terms (IRIs, blank nodes, or literals)

  ## Returns

  A tuple `{list_head, triples}` where:
  - `list_head` is the IRI of the list head (or rdf:nil for empty list)
  - `triples` is a list of all triples needed to represent the list

  ## Examples

      iex> items = [
      ...>   ~I<https://example.org/code#param1>,
      ...>   ~I<https://example.org/code#param2>
      ...> ]
      iex> {head, triples} = ElixirOntologies.Builders.Helpers.build_rdf_list(items)
      iex> is_struct(head, RDF.BlankNode)
      true
      iex> length(triples)
      4

      iex> {head, triples} = ElixirOntologies.Builders.Helpers.build_rdf_list([])
      iex> head
      ~I<http://www.w3.org/1999/02/22-rdf-syntax-ns#nil>
      iex> triples
      []
  """
  @spec build_rdf_list([RDF.Term.t()]) ::
          {RDF.IRI.t() | RDF.BlankNode.t(), [RDF.Triple.t()]}
  def build_rdf_list([]) do
    {RDF.nil(), []}
  end

  def build_rdf_list(items) when is_list(items) do
    build_rdf_list_recursive(items, [])
  end

  # Recursive helper for building RDF list
  defp build_rdf_list_recursive([item | rest], acc_triples) do
    node = RDF.bnode()

    # Create rdf:first triple
    first_triple = {node, RDF.first(), item}

    # Recursively build the rest of the list
    {rest_node, rest_triples} = build_rdf_list_recursive(rest, [])

    # Create rdf:rest triple
    rest_triple = {node, RDF.rest(), rest_node}

    # Combine all triples
    all_triples = [first_triple, rest_triple | rest_triples] ++ acc_triples

    {node, all_triples}
  end

  defp build_rdf_list_recursive([], _acc_triples) do
    {RDF.nil(), []}
  end

  # ===========================================================================
  # Blank Node Utilities
  # ===========================================================================

  @doc """
  Creates a new blank node with an optional label.

  ## Parameters

  - `label` - Optional label for the blank node (for debugging/readability)

  ## Examples

      iex> node = ElixirOntologies.Builders.Helpers.blank_node()
      iex> is_struct(node, RDF.BlankNode)
      true

      iex> node = ElixirOntologies.Builders.Helpers.blank_node("function_head")
      iex> is_struct(node, RDF.BlankNode)
      true
  """
  @spec blank_node(String.t() | nil) :: RDF.BlankNode.t()
  def blank_node(label \\ nil) do
    if label do
      RDF.bnode(label)
    else
      RDF.bnode()
    end
  end

  # ===========================================================================
  # Datatype Conversion
  # ===========================================================================

  @doc """
  Converts an Elixir value to an appropriate RDF literal with datatype.

  Automatically infers the XSD datatype based on the Elixir type.

  ## Supported Types

  - `integer()` → xsd:integer
  - `float()` → xsd:double
  - `boolean()` → xsd:boolean
  - `String.t()` → xsd:string
  - `Date.t()` → xsd:date
  - `DateTime.t()` → xsd:dateTime

  ## Examples

      iex> literal = ElixirOntologies.Builders.Helpers.to_literal(42)
      iex> RDF.Literal.value(literal)
      42

      iex> literal = ElixirOntologies.Builders.Helpers.to_literal("hello")
      iex> RDF.Literal.value(literal)
      "hello"

      iex> literal = ElixirOntologies.Builders.Helpers.to_literal(true)
      iex> RDF.Literal.value(literal)
      true

      iex> literal = ElixirOntologies.Builders.Helpers.to_literal(3.14)
      iex> RDF.Literal.value(literal)
      3.14
  """
  @spec to_literal(term()) :: RDF.Literal.t()
  def to_literal(value) when is_integer(value) do
    RDF.XSD.integer(value)
  end

  def to_literal(value) when is_float(value) do
    RDF.XSD.double(value)
  end

  def to_literal(value) when is_boolean(value) do
    RDF.XSD.boolean(value)
  end

  def to_literal(value) when is_binary(value) do
    RDF.XSD.string(value)
  end

  def to_literal(%Date{} = value) do
    RDF.XSD.date(value)
  end

  def to_literal(%DateTime{} = value) do
    RDF.XSD.dateTime(value)
  end

  def to_literal(value) do
    # Fallback to default literal
    RDF.literal(value)
  end

  # ===========================================================================
  # Triple List Utilities
  # ===========================================================================

  @doc """
  Flattens and deduplicates a list of triples.

  Useful for combining triples from multiple builders.

  ## Examples

      iex> triples1 = [{~I<http://example.org/s>, ~I<http://example.org/p>, ~I<http://example.org/o>}]
      iex> triples2 = [{~I<http://example.org/s>, ~I<http://example.org/p>, ~I<http://example.org/o>}]
      iex> result = ElixirOntologies.Builders.Helpers.deduplicate_triples([triples1, triples2])
      iex> length(result)
      1
  """
  @spec deduplicate_triples([[RDF.Triple.t()]]) :: [RDF.Triple.t()]
  def deduplicate_triples(triple_lists) when is_list(triple_lists) do
    triple_lists
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Finalizes a list of triples by flattening nested lists, filtering nils, and deduplicating.

  This is the standard post-processing step for builder triple lists.

  ## Examples

      iex> triples = [
      ...>   {~I<http://example.org/s>, ~I<http://example.org/p>, ~I<http://example.org/o>},
      ...>   nil,
      ...>   [{~I<http://example.org/s2>, ~I<http://example.org/p2>, ~I<http://example.org/o2>}]
      ...> ]
      iex> result = ElixirOntologies.Builders.Helpers.finalize_triples(triples)
      iex> length(result)
      2
      iex> Enum.any?(result, &is_nil/1)
      false
  """
  @spec finalize_triples([RDF.Triple.t() | nil | [RDF.Triple.t()]]) :: [RDF.Triple.t()]
  def finalize_triples(triples) when is_list(triples) do
    triples
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Creates two type triples for dual-typing (e.g., PROV-O base class + domain-specific subclass).

  Useful for evolution builders that need to express both `prov:Activity` and `evolution:FeatureAddition`.

  ## Parameters

  - `subject` - The subject IRI
  - `base_class` - The base class IRI (e.g., `PROV.Activity`)
  - `specialized_class` - The specialized class IRI (e.g., `Evolution.FeatureAddition`)

  ## Examples

      iex> alias ElixirOntologies.NS.{PROV, Evolution}
      iex> subject = ~I<https://example.org/activity/abc123>
      iex> triples = ElixirOntologies.Builders.Helpers.dual_type_triples(subject, PROV.Activity, Evolution.FeatureAddition)
      iex> length(triples)
      2
      iex> Enum.all?(triples, fn {_s, p, _o} -> p == RDF.type() end)
      true
  """
  @spec dual_type_triples(RDF.IRI.t() | RDF.BlankNode.t(), RDF.IRI.t(), RDF.IRI.t()) ::
          [RDF.Triple.t()]
  def dual_type_triples(subject, base_class, specialized_class) do
    [
      type_triple(subject, base_class),
      type_triple(subject, specialized_class)
    ]
  end

  @doc """
  Creates an optional datetime property triple.

  Returns `nil` if the datetime value is `nil`, otherwise creates a properly
  typed xsd:dateTime triple. The datetime is converted to ISO8601 format.

  ## Parameters

  - `subject` - The subject IRI
  - `predicate` - The property IRI
  - `datetime` - The DateTime value (or nil)

  ## Examples

      iex> alias ElixirOntologies.NS.PROV
      iex> subject = ~I<https://example.org/activity/abc123>
      iex> dt = ~U[2025-01-15 10:30:00Z]
      iex> triple = ElixirOntologies.Builders.Helpers.optional_datetime_property(subject, PROV.startedAtTime(), dt)
      iex> {_s, _p, o} = triple
      iex> RDF.Literal.value(o) |> DateTime.to_iso8601()
      "2025-01-15T10:30:00Z"

      iex> alias ElixirOntologies.NS.PROV
      iex> subject = ~I<https://example.org/activity/abc123>
      iex> triple = ElixirOntologies.Builders.Helpers.optional_datetime_property(subject, PROV.startedAtTime(), nil)
      iex> triple
      nil
  """
  @spec optional_datetime_property(
          RDF.IRI.t() | RDF.BlankNode.t(),
          RDF.IRI.t(),
          DateTime.t() | nil
        ) :: RDF.Triple.t() | nil
  def optional_datetime_property(_subject, _predicate, nil), do: nil

  def optional_datetime_property(subject, predicate, %DateTime{} = datetime) do
    datatype_property(subject, predicate, DateTime.to_iso8601(datetime), RDF.XSD.DateTime)
  end

  @doc """
  Creates an optional string property triple.

  Returns `nil` if the value is `nil`, otherwise creates a string literal triple.

  ## Parameters

  - `subject` - The subject IRI
  - `predicate` - The property IRI
  - `value` - The string value (or nil)

  ## Examples

      iex> alias ElixirOntologies.NS.Evolution
      iex> subject = ~I<https://example.org/commit/abc123>
      iex> triple = ElixirOntologies.Builders.Helpers.optional_string_property(subject, Evolution.commitMessage(), "Fix bug")
      iex> {_s, _p, o} = triple
      iex> RDF.Literal.value(o)
      "Fix bug"

      iex> alias ElixirOntologies.NS.Evolution
      iex> subject = ~I<https://example.org/commit/abc123>
      iex> triple = ElixirOntologies.Builders.Helpers.optional_string_property(subject, Evolution.commitMessage(), nil)
      iex> triple
      nil
  """
  @spec optional_string_property(
          RDF.IRI.t() | RDF.BlankNode.t(),
          RDF.IRI.t(),
          String.t() | nil
        ) :: RDF.Triple.t() | nil
  def optional_string_property(_subject, _predicate, nil), do: nil

  def optional_string_property(subject, predicate, value) when is_binary(value) do
    datatype_property(subject, predicate, value, RDF.XSD.String)
  end

  @doc """
  Filters triples by subject.

  Returns only triples where the subject matches the given IRI or blank node.

  ## Examples

      iex> subject = ~I<http://example.org/s>
      iex> triples = [
      ...>   {subject, ~I<http://example.org/p1>, ~I<http://example.org/o1>},
      ...>   {~I<http://example.org/other>, ~I<http://example.org/p2>, ~I<http://example.org/o2>},
      ...>   {subject, ~I<http://example.org/p3>, ~I<http://example.org/o3>}
      ...> ]
      iex> result = ElixirOntologies.Builders.Helpers.filter_by_subject(triples, subject)
      iex> length(result)
      2
  """
  @spec filter_by_subject([RDF.Triple.t()], RDF.IRI.t() | RDF.BlankNode.t()) :: [
          RDF.Triple.t()
        ]
  def filter_by_subject(triples, subject) when is_list(triples) do
    Enum.filter(triples, fn {s, _p, _o} -> s == subject end)
  end

  # ===========================================================================
  # Namespace Helpers
  # ===========================================================================

  @doc """
  Checks if an IRI belongs to a specific namespace.

  ## Examples

      iex> iri = ~I<https://w3id.org/elixir-code/structure#Module>
      iex> ElixirOntologies.Builders.Helpers.in_namespace?(iri, "https://w3id.org/elixir-code/structure#")
      true

      iex> iri = ~I<https://example.org/code#MyApp>
      iex> ElixirOntologies.Builders.Helpers.in_namespace?(iri, "https://w3id.org/elixir-code/structure#")
      false
  """
  @spec in_namespace?(RDF.IRI.t(), String.t()) :: boolean()
  def in_namespace?(%RDF.IRI{value: value}, namespace) when is_binary(namespace) do
    String.starts_with?(value, namespace)
  end

  def in_namespace?(_, _), do: false
end
