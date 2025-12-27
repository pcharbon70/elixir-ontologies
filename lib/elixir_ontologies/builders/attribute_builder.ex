defmodule ElixirOntologies.Builders.AttributeBuilder do
  @moduledoc """
  Builds RDF triples for module attributes.

  This module transforms `ElixirOntologies.Extractors.Attribute` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Attribute type classification (DocAttribute, DeprecatedAttribute, etc.)
  - Attribute name and value properties
  - Accumulating attribute tracking
  - Documentation content extraction
  - Type-specific metadata (deprecation message, since version, etc.)

  ## Usage

      alias ElixirOntologies.Builders.{AttributeBuilder, Context}
      alias ElixirOntologies.Extractors.Attribute

      attribute = %Attribute{
        type: :doc_attribute,
        name: :doc,
        value: "Function documentation",
        metadata: %{hidden: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      # Module is passed via options
      {attr_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])

  ## Examples

      iex> alias ElixirOntologies.Builders.{AttributeBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Attribute
      iex> attribute = %Attribute{
      ...>   type: :doc_attribute,
      ...>   name: :doc,
      ...>   value: "My docs",
      ...>   metadata: %{hidden: false}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {attr_iri, _triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])
      iex> to_string(attr_iri) =~ "attribute"
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Attribute
  alias NS.Structure

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a module attribute.

  Takes an attribute extraction result and builder context, returns the
  attribute IRI and a list of RDF triples.

  ## Parameters

  - `attribute` - Attribute struct from extraction
  - `context` - Builder context with base IRI
  - `opts` - Options including `:module` (required) and optional `:index`

  ## Options

  - `:module` - The module containing the attribute (required, as list of atoms)
  - `:index` - Index for accumulated/multiple attributes (optional)
  - `:accumulated` - Whether this is an accumulated attribute (optional)

  ## Returns

  A tuple `{attribute_iri, triples}` where:
  - `attribute_iri` - The IRI of the attribute
  - `triples` - List of RDF triples describing the attribute

  ## Examples

      iex> alias ElixirOntologies.Builders.{AttributeBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Attribute
      iex> attribute = %Attribute{
      ...>   type: :attribute,
      ...>   name: :my_attr,
      ...>   value: 42,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = AttributeBuilder.build(attribute, context, module: [:MyApp])
      iex> length(triples) > 0
      true
  """
  @spec build(Attribute.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(attribute, context, opts \\ []) do
    build_attribute(attribute, context, opts)
  end

  @doc """
  Builds RDF triples for a module attribute with options.

  This is the full-featured version that accepts all options.

  ## Examples

      iex> alias ElixirOntologies.Builders.{AttributeBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Attribute
      iex> attribute = %Attribute{
      ...>   type: :deprecated_attribute,
      ...>   name: :deprecated,
      ...>   value: "Use new_func/1",
      ...>   metadata: %{message: "Use new_func/1"}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = AttributeBuilder.build_attribute(attribute, context, module: [:MyApp])
      iex> to_string(iri) =~ "deprecated"
      true
  """
  @spec build_attribute(Attribute.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_attribute(attribute, context, opts) do
    # Get module from options
    module_name = get_module_name(opts)

    # Generate attribute IRI
    index = Keyword.get(opts, :index)
    attr_iri = IRI.for_attribute(context.base_iri, module_name, attribute.name, index)

    # Build all triples
    accumulated = Keyword.get(opts, :accumulated, false)

    triples =
      [
        build_type_triple(attr_iri, attribute),
        build_name_triple(attr_iri, attribute),
        build_value_triple(attr_iri, attribute)
      ] ++
        build_accumulated_triple(attr_iri, accumulated) ++
        build_doc_triples(attr_iri, attribute) ++
        build_deprecation_triple(attr_iri, attribute) ++
        build_since_triple(attr_iri, attribute) ++
        build_external_resource_triple(attr_iri, attribute) ++
        build_location_triple(attr_iri, attribute, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {attr_iri, triples}
  end

  # ===========================================================================
  # Module Name Extraction
  # ===========================================================================

  defp get_module_name(opts) do
    case Keyword.get(opts, :module) do
      nil -> "Unknown"
      parts when is_list(parts) -> Enum.map_join(parts, ".", &Atom.to_string/1)
      atom when is_atom(atom) -> Atom.to_string(atom) |> String.replace_prefix("Elixir.", "")
      str when is_binary(str) -> str
    end
  end

  # ===========================================================================
  # Type Classification
  # ===========================================================================

  # Map attribute types to ontology classes
  defp type_class(:doc_attribute), do: Structure.FunctionDocAttribute
  defp type_class(:moduledoc_attribute), do: Structure.ModuledocAttribute
  defp type_class(:typedoc_attribute), do: Structure.TypedocAttribute
  defp type_class(:deprecated_attribute), do: Structure.DeprecatedAttribute
  defp type_class(:since_attribute), do: Structure.SinceAttribute
  defp type_class(:external_resource_attribute), do: Structure.ExternalResourceAttribute
  defp type_class(:compile_attribute), do: Structure.CompileAttribute
  defp type_class(:on_definition_attribute), do: Structure.OnDefinitionAttribute
  defp type_class(:before_compile_attribute), do: Structure.BeforeCompileAttribute
  defp type_class(:after_compile_attribute), do: Structure.AfterCompileAttribute
  defp type_class(:derive_attribute), do: Structure.DeriveAttribute
  defp type_class(:behaviour_declaration), do: Structure.BehaviourDeclaration
  defp type_class(_), do: Structure.ModuleAttribute

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  # Build rdf:type triple
  defp build_type_triple(attr_iri, attribute) do
    Helpers.type_triple(attr_iri, type_class(attribute.type))
  end

  # Build structure:attributeName triple
  defp build_name_triple(attr_iri, attribute) do
    Helpers.datatype_property(
      attr_iri,
      Structure.attributeName(),
      Atom.to_string(attribute.name),
      RDF.XSD.String
    )
  end

  # Build structure:attributeValue triple
  defp build_value_triple(attr_iri, attribute) do
    serialized = serialize_value(attribute.value)

    Helpers.datatype_property(
      attr_iri,
      Structure.attributeValue(),
      serialized,
      RDF.XSD.String
    )
  end

  # Serialize attribute value to string
  defp serialize_value(nil), do: "nil"
  defp serialize_value(value) when is_binary(value), do: value
  defp serialize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize_value(value) when is_integer(value), do: Integer.to_string(value)
  defp serialize_value(value) when is_float(value), do: Float.to_string(value)
  defp serialize_value(value) when is_boolean(value), do: Atom.to_string(value)

  defp serialize_value(value) when is_list(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end

  defp serialize_value(value) when is_map(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end

  defp serialize_value(value), do: inspect(value)

  # Build structure:isAccumulating triple
  defp build_accumulated_triple(_attr_iri, false), do: []

  defp build_accumulated_triple(attr_iri, true) do
    [
      Helpers.datatype_property(
        attr_iri,
        Structure.isAccumulating(),
        true,
        RDF.XSD.Boolean
      )
    ]
  end

  # Build documentation-specific triples
  defp build_doc_triples(attr_iri, %{type: type, value: value, metadata: metadata})
       when type in [:doc_attribute, :moduledoc_attribute, :typedoc_attribute] do
    triples = []

    # Add docstring if present
    triples =
      if is_binary(value) and value != "" do
        [
          Helpers.datatype_property(
            attr_iri,
            Structure.docstring(),
            value,
            RDF.XSD.String
          )
          | triples
        ]
      else
        triples
      end

    # Add isDocFalse if hidden
    triples =
      if Map.get(metadata, :hidden, false) do
        [
          Helpers.datatype_property(
            attr_iri,
            Structure.isDocFalse(),
            true,
            RDF.XSD.Boolean
          )
          | triples
        ]
      else
        triples
      end

    triples
  end

  defp build_doc_triples(_attr_iri, _attribute), do: []

  # Build deprecation message triple
  defp build_deprecation_triple(attr_iri, %{type: :deprecated_attribute, metadata: metadata}) do
    case Map.get(metadata, :message) do
      nil ->
        []

      message when is_binary(message) ->
        [
          Helpers.datatype_property(
            attr_iri,
            Structure.deprecationMessage(),
            message,
            RDF.XSD.String
          )
        ]

      _ ->
        []
    end
  end

  defp build_deprecation_triple(_attr_iri, _attribute), do: []

  # Build since version triple
  defp build_since_triple(attr_iri, %{type: :since_attribute, metadata: metadata}) do
    case Map.get(metadata, :version) do
      nil ->
        []

      version when is_binary(version) ->
        [
          Helpers.datatype_property(
            attr_iri,
            Structure.sinceVersion(),
            version,
            RDF.XSD.String
          )
        ]

      _ ->
        []
    end
  end

  defp build_since_triple(_attr_iri, _attribute), do: []

  # Build external resource path triple
  defp build_external_resource_triple(
         attr_iri,
         %{type: :external_resource_attribute, metadata: metadata}
       ) do
    case Map.get(metadata, :path) do
      nil ->
        []

      path when is_binary(path) ->
        [
          Helpers.datatype_property(
            attr_iri,
            Structure.attributeValue(),
            path,
            RDF.XSD.String
          )
        ]

      _ ->
        []
    end
  end

  defp build_external_resource_triple(_attr_iri, _attribute), do: []

  # Build location triple
  defp build_location_triple(_attr_iri, %{location: nil}, _context), do: []

  defp build_location_triple(attr_iri, attribute, context) do
    location = attribute.location

    case location do
      %{start_line: line} when is_integer(line) and line > 0 ->
        location_iri = generate_location_iri(attr_iri, location)

        [
          Helpers.object_property(attr_iri, NS.Core.hasSourceLocation(), location_iri),
          build_location_line_triples(location_iri, location, context)
        ]

      _ ->
        []
    end
  end

  defp generate_location_iri(attr_iri, location) do
    line = location.start_line || 0
    end_line = location.end_line || line

    RDF.iri("#{attr_iri}/L#{line}-#{end_line}")
  end

  defp build_location_line_triples(location_iri, location, _context) do
    triples = [Helpers.type_triple(location_iri, NS.Core.SourceLocation)]

    triples =
      if location.start_line do
        [
          Helpers.datatype_property(
            location_iri,
            NS.Core.startLine(),
            location.start_line,
            RDF.XSD.PositiveInteger
          )
          | triples
        ]
      else
        triples
      end

    triples =
      if location.end_line do
        [
          Helpers.datatype_property(
            location_iri,
            NS.Core.endLine(),
            location.end_line,
            RDF.XSD.PositiveInteger
          )
          | triples
        ]
      else
        triples
      end

    triples
  end
end
