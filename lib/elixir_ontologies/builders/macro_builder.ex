defmodule ElixirOntologies.Builders.MacroBuilder do
  @moduledoc """
  Builds RDF triples for macro invocations.

  This module transforms `ElixirOntologies.Extractors.MacroInvocation` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Macro invocation type classification
  - Macro name and module relationships
  - Invocation location tracking
  - Resolution status

  ## Usage

      alias ElixirOntologies.Builders.{MacroBuilder, Context}
      alias ElixirOntologies.Extractors.MacroInvocation

      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel
      }

      context = Context.new(base_iri: "https://example.org/code#")

      # Module is passed via invocation metadata
      invocation = %MacroInvocation{metadata: %{module: [:MyApp, :Users]}}

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.{MacroBuilder, Context}
      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> invocation = %MacroInvocation{
      ...>   macro_module: Kernel,
      ...>   macro_name: :if,
      ...>   arity: 2,
      ...>   category: :control_flow,
      ...>   resolution_status: :kernel,
      ...>   metadata: %{invocation_index: 0, module: [:MyApp]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {invocation_iri, _triples} = MacroBuilder.build(invocation, context)
      iex> to_string(invocation_iri) =~ "invocation"
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.MacroInvocation
  alias NS.Structure

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a macro invocation.

  Takes a macro invocation extraction result and builder context, returns the
  invocation IRI and a list of RDF triples.

  ## Parameters

  - `invocation` - MacroInvocation struct from extraction
  - `context` - Builder context with base IRI and current module

  ## Returns

  A tuple `{invocation_iri, triples}` where:
  - `invocation_iri` - The IRI of the macro invocation
  - `triples` - List of RDF triples describing the invocation

  ## Examples

      iex> alias ElixirOntologies.Builders.{MacroBuilder, Context}
      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> invocation = %MacroInvocation{
      ...>   macro_module: Kernel,
      ...>   macro_name: :def,
      ...>   arity: 2,
      ...>   category: :definition,
      ...>   resolution_status: :kernel,
      ...>   metadata: %{invocation_index: 1, module: [:MyApp]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = MacroBuilder.build(invocation, context)
      iex> length(triples) > 0
      true
  """
  @spec build(MacroInvocation.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(invocation, context) do
    build_macro_invocation(invocation, context)
  end

  @doc """
  Builds RDF triples for a macro invocation with options.

  ## Options

  - `:index` - Override the invocation index (default: from metadata or 0)
  - `:module` - Override the module (default: from metadata.module)

  ## Examples

      iex> alias ElixirOntologies.Builders.{MacroBuilder, Context}
      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> invocation = %MacroInvocation{
      ...>   macro_module: Kernel,
      ...>   macro_name: :unless,
      ...>   arity: 2,
      ...>   category: :control_flow,
      ...>   resolution_status: :kernel,
      ...>   metadata: %{module: [:MyApp]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = MacroBuilder.build_macro_invocation(invocation, context, index: 5)
      iex> to_string(iri) =~ "/5"
      true
  """
  @spec build_macro_invocation(MacroInvocation.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_macro_invocation(invocation, context, opts \\ []) do
    # Generate invocation IRI
    invocation_iri = generate_invocation_iri(invocation, context, opts)

    # Build all triples
    triples =
      [
        build_type_triple(invocation_iri),
        build_macro_name_triple(invocation_iri, invocation),
        build_arity_triple(invocation_iri, invocation),
        build_category_triple(invocation_iri, invocation),
        build_resolution_status_triple(invocation_iri, invocation)
      ] ++
        build_macro_module_triple(invocation_iri, invocation) ++
        build_location_triple(invocation_iri, invocation, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {invocation_iri, triples}
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  defp generate_invocation_iri(invocation, context, opts) do
    # Get module from: options, invocation metadata, or default to "Unknown"
    module_name = get_module_name(invocation, opts)

    # Get index from options, metadata, or location line
    index = get_invocation_index(invocation, opts)

    # Build the macro identifier
    macro_id = build_macro_id(invocation)

    IRI.for_macro_invocation(context.base_iri, module_name, macro_id, index)
  end

  defp get_module_name(invocation, opts) do
    cond do
      # Option takes highest precedence
      Keyword.has_key?(opts, :module) ->
        module_name_string(Keyword.get(opts, :module))

      # Then metadata.module
      Map.has_key?(invocation.metadata, :module) ->
        module_name_string(invocation.metadata.module)

      # Default fallback
      true ->
        "Unknown"
    end
  end

  defp get_invocation_index(invocation, opts) do
    cond do
      Keyword.has_key?(opts, :index) ->
        Keyword.get(opts, :index)

      Map.has_key?(invocation.metadata, :invocation_index) ->
        invocation.metadata.invocation_index

      invocation.location != nil ->
        invocation.location.start_line || 0

      true ->
        0
    end
  end

  defp build_macro_id(invocation) do
    module_part =
      case invocation.macro_module do
        nil -> "unknown"
        mod when is_atom(mod) -> inspect(mod) |> String.replace(".", "_")
      end

    "#{module_part}.#{invocation.macro_name}"
  end

  defp module_name_string(nil), do: "Unknown"
  defp module_name_string([]), do: "Unknown"

  defp module_name_string(module_parts) when is_list(module_parts) do
    Enum.map_join(module_parts, ".", &Atom.to_string/1)
  end

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  # Build rdf:type triple
  defp build_type_triple(invocation_iri) do
    Helpers.type_triple(invocation_iri, Structure.MacroInvocation)
  end

  # Build structure:macroName datatype property
  defp build_macro_name_triple(invocation_iri, invocation) do
    Helpers.datatype_property(
      invocation_iri,
      Structure.macroName(),
      Atom.to_string(invocation.macro_name),
      RDF.XSD.String
    )
  end

  # Build structure:macroArity datatype property
  defp build_arity_triple(invocation_iri, invocation) do
    Helpers.datatype_property(
      invocation_iri,
      Structure.macroArity(),
      invocation.arity,
      RDF.XSD.NonNegativeInteger
    )
  end

  # Build structure:macroCategory datatype property
  defp build_category_triple(invocation_iri, invocation) do
    Helpers.datatype_property(
      invocation_iri,
      Structure.macroCategory(),
      Atom.to_string(invocation.category),
      RDF.XSD.String
    )
  end

  # Build structure:resolutionStatus datatype property
  defp build_resolution_status_triple(invocation_iri, invocation) do
    Helpers.datatype_property(
      invocation_iri,
      Structure.resolutionStatus(),
      Atom.to_string(invocation.resolution_status),
      RDF.XSD.String
    )
  end

  # Build structure:macroModule or structure:invokesMacro
  defp build_macro_module_triple(invocation_iri, invocation) do
    case invocation.macro_module do
      nil ->
        []

      module when is_atom(module) ->
        [
          Helpers.datatype_property(
            invocation_iri,
            Structure.macroModule(),
            inspect(module),
            RDF.XSD.String
          )
        ]
    end
  end

  # Build structure:invokedAt location triple
  defp build_location_triple(_invocation_iri, %{location: nil}, _context), do: []

  defp build_location_triple(invocation_iri, invocation, context) do
    location = invocation.location

    case location do
      %{start_line: line} when is_integer(line) and line > 0 ->
        # Create a location IRI and link to it
        location_iri = generate_location_iri(invocation_iri, location)

        [
          Helpers.object_property(invocation_iri, Structure.invokedAt(), location_iri),
          build_location_line_triple(location_iri, location, context)
        ]

      _ ->
        []
    end
  end

  defp generate_location_iri(invocation_iri, location) do
    line = location.start_line || 0
    end_line = location.end_line || line

    RDF.iri("#{invocation_iri}/L#{line}-#{end_line}")
  end

  defp build_location_line_triple(location_iri, location, _context) do
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
