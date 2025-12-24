defmodule ElixirOntologies.Builders.ProtocolBuilder do
  @moduledoc """
  Builds RDF triples for Elixir protocols and their implementations.

  This module transforms `ElixirOntologies.Extractors.Protocol` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Protocol definitions (defprotocol) with function signatures
  - Protocol implementations (defimpl) for specific types
  - Protocol properties (fallbackToAny, protocolName)
  - Implementation relationships (implementsProtocol, forDataType)
  - Protocol function definitions and linkages
  - Special implementation types (Any, derived protocols)

  ## Protocol vs Implementation

  **Protocols** define polymorphic interfaces:
  - Use module IRI pattern: `base#Enumerable`
  - Define function signatures without bodies
  - Can have `@fallback_to_any` flag

  **Implementations** provide type-specific behavior:
  - Use combined IRI: `base#Enumerable.for.List`
  - Implement protocol functions for specific types
  - Link to both protocol and target type

  ## Usage

      alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
      alias ElixirOntologies.Extractors.Protocol

      # Build protocol
      protocol_info = %Protocol{
        name: [:Enumerable],
        functions: [%{name: :count, arity: 1, ...}],
        fallback_to_any: false
      }
      context = Context.new(base_iri: "https://example.org/code#")
      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Build implementation
      impl_info = %Protocol.Implementation{
        protocol: [:Enumerable],
        for_type: [:List],
        functions: [%{name: :count, arity: 1, ...}]
      }
      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Protocol
      iex> protocol_info = %Protocol{
      ...>   name: [:Stringable],
      ...>   functions: [],
      ...>   fallback_to_any: false,
      ...>   doc: nil,
      ...>   typedoc: nil,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {protocol_iri, _triples} = ProtocolBuilder.build_protocol(protocol_info, context)
      iex> to_string(protocol_iri)
      "https://example.org/code#Stringable"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Protocol
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Protocol Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a protocol definition.

  Takes a protocol extraction result and builder context, returns the protocol IRI
  and a list of RDF triples representing the protocol and its functions.

  ## Parameters

  - `protocol_info` - Protocol extraction result from `Extractors.Protocol.extract/1`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{protocol_iri, triples}` where:
  - `protocol_iri` - The IRI of the protocol (using module pattern)
  - `triples` - List of RDF triples describing the protocol

  ## Examples

      iex> alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Protocol
      iex> protocol_info = %Protocol{
      ...>   name: [:Enumerable],
      ...>   functions: [],
      ...>   fallback_to_any: true,
      ...>   doc: nil,
      ...>   typedoc: nil,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^protocol_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_protocol(Protocol.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_protocol(protocol_info, context) do
    # Generate protocol IRI (uses module pattern)
    protocol_iri = generate_protocol_iri(protocol_info, context)

    # Build all triples
    triples =
      [
        # Core protocol triples
        build_type_triple(protocol_iri, :protocol),
        build_protocol_name_triple(protocol_iri, protocol_info),
        build_fallback_triple(protocol_iri, protocol_info)
      ] ++
        build_protocol_function_triples(protocol_iri, protocol_info, context) ++
        build_docstring_triple(protocol_iri, protocol_info) ++
        build_location_triple(protocol_iri, protocol_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {protocol_iri, triples}
  end

  # ===========================================================================
  # Public API - Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a protocol implementation.

  Takes an implementation extraction result and builder context, returns the
  implementation IRI and a list of RDF triples representing the implementation
  and its relationship to the protocol and target type.

  ## Parameters

  - `impl_info` - Implementation extraction result from `Protocol.extract_implementation/1`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{impl_iri, triples}` where:
  - `impl_iri` - The IRI of the implementation (protocol + type combination)
  - `triples` - List of RDF triples describing the implementation

  ## Examples

      iex> alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Protocol.Implementation
      iex> impl_info = %Implementation{
      ...>   protocol: [:Enumerable],
      ...>   for_type: [:List],
      ...>   functions: [],
      ...>   is_any: false,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^impl_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_implementation(Protocol.Implementation.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_implementation(impl_info, context) do
    # Generate implementation IRI (protocol + type)
    impl_iri = generate_implementation_iri(impl_info, context)

    # Build all triples
    triples =
      [
        # Core implementation triples
        build_type_triple(impl_iri, :implementation),
        build_implements_protocol_triple(impl_iri, impl_info, context),
        build_for_type_triple(impl_iri, impl_info, context)
      ] ++
        build_implementation_function_triples(impl_iri, impl_info, context) ++
        build_location_triple(impl_iri, impl_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {impl_iri, triples}
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  # Generate protocol IRI using module pattern
  defp generate_protocol_iri(protocol_info, context) do
    protocol_name = module_name_string(protocol_info.name)
    IRI.for_module(context.base_iri, protocol_name)
  end

  # Generate implementation IRI (protocol.for.Type pattern)
  defp generate_implementation_iri(impl_info, context) do
    protocol_name = module_name_string(impl_info.protocol)
    type_name = type_name_string(impl_info.for_type)

    # Pattern: Enumerable.for.List
    impl_name = "#{protocol_name}.for.#{type_name}"
    IRI.for_module(context.base_iri, impl_name)
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Build rdf:type triple
  defp build_type_triple(subject_iri, :protocol) do
    Helpers.type_triple(subject_iri, Structure.Protocol)
  end

  defp build_type_triple(subject_iri, :implementation) do
    Helpers.type_triple(subject_iri, Structure.ProtocolImplementation)
  end

  # Build struct:protocolName datatype property
  defp build_protocol_name_triple(protocol_iri, protocol_info) do
    protocol_name = module_name_string(protocol_info.name)

    Helpers.datatype_property(
      protocol_iri,
      Structure.protocolName(),
      protocol_name,
      RDF.XSD.String
    )
  end

  # Build struct:fallbackToAny datatype property
  defp build_fallback_triple(protocol_iri, protocol_info) do
    Helpers.datatype_property(
      protocol_iri,
      Structure.fallbackToAny(),
      protocol_info.fallback_to_any,
      RDF.XSD.Boolean
    )
  end

  # ===========================================================================
  # Protocol Function Triple Generation
  # ===========================================================================

  # Build triples for protocol function definitions
  defp build_protocol_function_triples(protocol_iri, protocol_info, context) do
    protocol_info.functions
    |> Enum.flat_map(fn func ->
      func_iri = generate_protocol_function_iri(protocol_iri, func, context)

      [
        # rdf:type struct:ProtocolFunction
        Helpers.type_triple(func_iri, Structure.ProtocolFunction),
        # struct:functionName
        Helpers.datatype_property(
          func_iri,
          Structure.functionName(),
          Atom.to_string(func.name),
          RDF.XSD.String
        ),
        # struct:arity
        Helpers.datatype_property(
          func_iri,
          Structure.arity(),
          func.arity,
          RDF.XSD.NonNegativeInteger
        ),
        # protocol struct:definesProtocolFunction function
        Helpers.object_property(protocol_iri, Structure.definesProtocolFunction(), func_iri)
      ] ++ build_function_doc_triple(func_iri, func)
    end)
  end

  # Generate IRI for protocol function
  defp generate_protocol_function_iri(protocol_iri, func, _context) do
    # Pattern: Protocol/function_name/arity
    RDF.iri("#{protocol_iri}/#{func.name}/#{func.arity}")
  end

  # Build function documentation triple if present
  defp build_function_doc_triple(func_iri, func) do
    case func.doc do
      nil ->
        []

      doc when is_binary(doc) ->
        [Helpers.datatype_property(func_iri, Structure.docstring(), doc, RDF.XSD.String)]
    end
  end

  # ===========================================================================
  # Implementation Relationship Triple Generation
  # ===========================================================================

  # Build struct:implementsProtocol triple
  defp build_implements_protocol_triple(impl_iri, impl_info, context) do
    protocol_name = module_name_string(impl_info.protocol)
    protocol_iri = IRI.for_module(context.base_iri, protocol_name)

    Helpers.object_property(impl_iri, Structure.implementsProtocol(), protocol_iri)
  end

  # Build struct:forDataType triple
  defp build_for_type_triple(impl_iri, impl_info, context) do
    type_iri = generate_type_iri(impl_info.for_type, context)
    Helpers.object_property(impl_iri, Structure.forDataType(), type_iri)
  end

  # Generate IRI for target type
  defp generate_type_iri(for_type, context) when is_list(for_type) do
    # Elixir module type (e.g., [:List])
    type_name = module_name_string(for_type)
    IRI.for_module(context.base_iri, type_name)
  end

  defp generate_type_iri(:Any, context) do
    # Special Any type
    IRI.for_module(context.base_iri, "Any")
  end

  defp generate_type_iri(type, context) when is_atom(type) do
    # Built-in type or :__MODULE__
    type_string = Atom.to_string(type) |> String.trim_leading("Elixir.")
    IRI.for_module(context.base_iri, type_string)
  end

  # ===========================================================================
  # Implementation Function Triple Generation
  # ===========================================================================

  # Build triples for implementation functions
  defp build_implementation_function_triples(impl_iri, impl_info, _context) do
    impl_info.functions
    |> Enum.flat_map(fn func ->
      # Generate IRI for implementation function
      impl_func_iri = generate_impl_function_iri(impl_iri, func)

      [
        # rdf:type struct:Function
        Helpers.type_triple(impl_func_iri, Structure.Function),
        # Link implementation to function
        Helpers.object_property(impl_iri, Structure.containsFunction(), impl_func_iri)
      ]
    end)
  end

  # Generate IRI for implementation function
  defp generate_impl_function_iri(impl_iri, func) do
    # Pattern: Implementation/function_name/arity
    RDF.iri("#{impl_iri}/#{func.name}/#{func.arity}")
  end

  # ===========================================================================
  # Documentation Triple Generation
  # ===========================================================================

  # Build struct:docstring triple for protocol (if present)
  defp build_docstring_triple(subject_iri, info) do
    case info.doc do
      nil ->
        []

      false ->
        # @doc false - intentionally hidden
        []

      doc when is_binary(doc) ->
        [Helpers.datatype_property(subject_iri, Structure.docstring(), doc, RDF.XSD.String)]
    end
  end

  # ===========================================================================
  # Source Location Triple Generation
  # ===========================================================================

  # Build core:hasSourceLocation triple if location available
  defp build_location_triple(subject_iri, info, context) do
    case {info.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)
        end_line = location.end_line || location.start_line
        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(subject_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Convert module name list to string
  defp module_name_string(name) when is_list(name) do
    Enum.join(name, ".")
  end

  # Convert type name to string
  defp type_name_string(type) when is_list(type) do
    module_name_string(type)
  end

  defp type_name_string(:Any), do: "Any"

  defp type_name_string(type) when is_atom(type) do
    Atom.to_string(type) |> String.trim_leading("Elixir.")
  end
end
