defmodule ElixirOntologies.Builders.StructBuilder do
  @moduledoc """
  Builds RDF triples for Elixir struct and exception definitions.

  This module transforms `ElixirOntologies.Extractors.Struct` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Struct definitions (defstruct)
  - Struct fields with default values
  - Enforced keys (@enforce_keys)
  - Protocol derivation (@derive)
  - Exception definitions (defexception)
  - Exception messages (default and custom)

  ## Struct vs Exception

  **Structs** define data structures:
  - Use module IRI pattern: `base#User`
  - Define fields with optional defaults
  - Can enforce required keys
  - Can derive protocol implementations
  - Module-scoped data containers

  **Exceptions** are special structs:
  - Inherit all struct properties
  - Additional: message handling
  - Can define custom message/1 function
  - Used for error handling

  ## Usage

      alias ElixirOntologies.Builders.{StructBuilder, Context}
      alias ElixirOntologies.Extractors.Struct

      # Build struct definition
      struct_info = %Struct{
        fields: [
          %{name: :name, has_default: false, default_value: nil},
          %{name: :age, has_default: true, default_value: 0}
        ],
        enforce_keys: [:name],
        derives: []
      }
      module_iri = ~I<https://example.org/code#User>
      context = Context.new(base_iri: "https://example.org/code#")
      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Build exception definition
      exception_info = %Struct.Exception{
        fields: [%{name: :message, has_default: true, default_value: "error occurred"}],
        enforce_keys: [],
        derives: [],
        has_custom_message: false,
        default_message: "error occurred"
      }
      module_iri = ~I<https://example.org/code#MyError>
      {exception_iri, triples} = StructBuilder.build_exception(exception_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.{StructBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Struct
      iex> struct_info = %Struct{
      ...>   fields: [],
      ...>   enforce_keys: [],
      ...>   derives: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MyStruct")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {struct_iri, _triples} = StructBuilder.build_struct(struct_info, module_iri, context)
      iex> to_string(struct_iri)
      "https://example.org/code#MyStruct"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Struct
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Struct Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a struct definition.

  Takes a struct extraction result and builder context, returns the struct IRI
  and a list of RDF triples representing the struct and its fields.

  ## Parameters

  - `struct_info` - Struct extraction result from `Extractors.Struct.extract_from_body/1`
  - `module_iri` - The IRI of the module defining this struct
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{struct_iri, triples}` where:
  - `struct_iri` - The IRI of the struct (same as module_iri)
  - `triples` - List of RDF triples describing the struct

  ## Examples

      iex> alias ElixirOntologies.Builders.{StructBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Struct
      iex> struct_info = %Struct{
      ...>   fields: [],
      ...>   enforce_keys: [],
      ...>   derives: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestStruct")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^struct_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_struct(Struct.t(), RDF.IRI.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_struct(struct_info, module_iri, context) do
    # Struct IRI is the same as module IRI
    struct_iri = module_iri

    # Build all triples
    triples =
      [
        # Core struct triples
        build_type_triple(struct_iri, :struct),
        build_module_contains_struct_triple(struct_iri)
      ] ++
        build_field_triples(struct_iri, struct_info, context) ++
        build_enforced_key_triples(struct_iri, struct_info, context) ++
        build_derives_triples(struct_iri, struct_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {struct_iri, triples}
  end

  # ===========================================================================
  # Public API - Exception Building
  # ===========================================================================

  @doc """
  Builds RDF triples for an exception definition.

  Takes an exception extraction result and builder context, returns the exception IRI
  and a list of RDF triples representing the exception and its properties.

  ## Parameters

  - `exception_info` - Exception extraction result from `Struct.extract_exception_from_body/1`
  - `module_iri` - The IRI of the module defining this exception
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{exception_iri, triples}` where:
  - `exception_iri` - The IRI of the exception (same as module_iri)
  - `triples` - List of RDF triples describing the exception

  ## Examples

      iex> alias ElixirOntologies.Builders.{StructBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Struct
      iex> exception_info = %Struct.Exception{
      ...>   fields: [],
      ...>   enforce_keys: [],
      ...>   derives: [],
      ...>   has_custom_message: false,
      ...>   default_message: nil,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MyError")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {exception_iri, _triples} = StructBuilder.build_exception(exception_info, module_iri, context)
      iex> exception_iri == module_iri
      true
  """
  @spec build_exception(Struct.Exception.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_exception(exception_info, module_iri, context) do
    # Exception IRI is the same as module IRI
    exception_iri = module_iri

    # Build all triples
    triples =
      [
        # Core exception triples
        build_type_triple(exception_iri, :exception),
        build_module_contains_struct_triple(exception_iri)
      ] ++
        build_field_triples(exception_iri, exception_info, context) ++
        build_enforced_key_triples(exception_iri, exception_info, context) ++
        build_derives_triples(exception_iri, exception_info, context) ++
        build_exception_specific_triples(exception_iri, exception_info)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {exception_iri, triples}
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Build rdf:type triple
  defp build_type_triple(subject_iri, :struct) do
    Helpers.type_triple(subject_iri, Structure.Struct)
  end

  defp build_type_triple(subject_iri, :exception) do
    Helpers.type_triple(subject_iri, Structure.Exception)
  end

  # Build struct:containsStruct triple from module to struct
  defp build_module_contains_struct_triple(struct_iri) do
    # Struct IRI is the module IRI, so this triple links module to itself as struct
    Helpers.object_property(struct_iri, Structure.containsStruct(), struct_iri)
  end

  # ===========================================================================
  # Field Triple Generation
  # ===========================================================================

  # Build triples for struct fields
  defp build_field_triples(struct_iri, struct_info, context) do
    struct_info.fields
    |> Enum.with_index()
    |> Enum.flat_map(fn {field, _index} ->
      field_iri = generate_field_iri(struct_iri, field)

      [
        # rdf:type struct:StructField
        Helpers.type_triple(field_iri, Structure.StructField),
        # struct:fieldName
        Helpers.datatype_property(
          field_iri,
          Structure.fieldName(),
          Atom.to_string(field.name),
          RDF.XSD.String
        ),
        # struct:hasField
        Helpers.object_property(struct_iri, Structure.hasField(), field_iri)
      ] ++
        build_field_default_triple(field_iri, field) ++
        build_field_location_triple(field_iri, field, context)
    end)
  end

  # Generate IRI for field
  defp generate_field_iri(struct_iri, field) do
    # Pattern: Struct/field/field_name
    RDF.iri("#{struct_iri}/field/#{field.name}")
  end

  # Build field default value triple if present
  defp build_field_default_triple(field_iri, field) do
    if field.has_default do
      # Convert default value to string representation
      default_string = inspect(field.default_value)

      [
        Helpers.datatype_property(
          field_iri,
          Structure.hasDefaultFieldValue(),
          default_string,
          RDF.XSD.String
        )
      ]
    else
      []
    end
  end

  # Build field source location triple if present
  defp build_field_location_triple(field_iri, field, context) do
    case {field.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)
        end_line = location.end_line || location.start_line
        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(field_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # ===========================================================================
  # Enforced Key Triple Generation
  # ===========================================================================

  # Build triples for enforced keys
  defp build_enforced_key_triples(struct_iri, struct_info, _context) do
    struct_info.enforce_keys
    |> Enum.flat_map(fn key_name ->
      # Generate enforced key IRI (same as field IRI)
      enforced_key_iri = RDF.iri("#{struct_iri}/field/#{key_name}")

      [
        # rdf:type struct:EnforcedKey (subclass of StructField)
        Helpers.type_triple(enforced_key_iri, Structure.EnforcedKey),
        # struct:hasEnforcedKey
        Helpers.object_property(struct_iri, Structure.hasEnforcedKey(), enforced_key_iri)
      ]
    end)
  end

  # ===========================================================================
  # Protocol Derivation Triple Generation
  # ===========================================================================

  # Build triples for protocol derivation (@derive)
  defp build_derives_triples(struct_iri, struct_info, context) do
    struct_info.derives
    |> Enum.flat_map(fn derive_info ->
      derive_info.protocols
      |> Enum.flat_map(fn protocol_spec ->
        # Generate protocol IRI
        protocol_iri = generate_protocol_iri(protocol_spec.protocol, context)

        [
          # struct:derivesProtocol
          Helpers.object_property(struct_iri, Structure.derivesProtocol(), protocol_iri)
        ]
      end)
    end)
  end

  # Generate IRI for protocol in @derive
  defp generate_protocol_iri(protocol, context) when is_list(protocol) do
    # Protocol name as module list: [:Inspect]
    protocol_name = Enum.map_join(protocol, ".", &Atom.to_string/1)
    IRI.for_module(context.base_iri, protocol_name)
  end

  defp generate_protocol_iri(protocol, context) when is_atom(protocol) do
    # Protocol name as atom: :Inspect
    protocol_name = Atom.to_string(protocol) |> String.trim_leading("Elixir.")
    IRI.for_module(context.base_iri, protocol_name)
  end

  # ===========================================================================
  # Exception-Specific Triple Generation
  # ===========================================================================

  # Build exception-specific triples
  defp build_exception_specific_triples(exception_iri, exception_info) do
    build_exception_message_triple(exception_iri, exception_info)
  end

  # Build exceptionMessage triple if present
  defp build_exception_message_triple(exception_iri, exception_info) do
    case exception_info.default_message do
      nil ->
        []

      message when is_binary(message) ->
        [
          Helpers.datatype_property(
            exception_iri,
            Structure.exceptionMessage(),
            message,
            RDF.XSD.String
          )
        ]
    end
  end
end
