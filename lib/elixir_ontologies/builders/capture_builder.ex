defmodule ElixirOntologies.Builders.CaptureBuilder do
  @moduledoc """
  Builds RDF triples for Elixir capture operator expressions.

  This module transforms `ElixirOntologies.Extractors.Capture` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Named local captures (`&foo/1`) → `struct:CapturedFunction`
  - Named remote captures (`&Module.func/1`) → `struct:CapturedFunction`
  - Shorthand captures (`&(&1 + 1)`) → `struct:PartialApplication`

  ## Ontology Classes

  | Capture Type | RDF Class | Properties |
  |--------------|-----------|------------|
  | `:named_local` | `CapturedFunction` | arity, refersToFunction |
  | `:named_remote` | `CapturedFunction` | arity, refersToFunction, refersToModule |
  | `:shorthand` | `PartialApplication` | arity |

  ## Usage

      alias ElixirOntologies.Builders.{CaptureBuilder, Context}
      alias ElixirOntologies.Extractors.Capture

      ast = quote do: &String.upcase/1
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(
        base_iri: "https://example.org/code#",
        metadata: %{module: [:MyApp]}
      )

      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

  ## Examples

      iex> alias ElixirOntologies.Builders.{CaptureBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Capture
      iex> ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      iex> {:ok, capture} = Capture.extract(ast)
      iex> context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      iex> {capture_iri, _triples} = CaptureBuilder.build(capture, context, 0)
      iex> to_string(capture_iri)
      "https://example.org/code#MyApp/&/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Capture
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a capture expression.

  Takes a capture extraction result, builder context, and an index for generating
  a unique IRI. Returns the capture IRI and a list of RDF triples.

  ## Parameters

  - `capture_info` - Capture extraction result
  - `context` - Builder context with base IRI and optional module context
  - `index` - Index of the capture within its context (for unique IRI)

  ## Returns

  A tuple `{capture_iri, triples}` where:
  - `capture_iri` - The IRI of the capture expression
  - `triples` - List of RDF triples describing the capture

  ## Examples

      iex> alias ElixirOntologies.Builders.{CaptureBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Capture
      iex> ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      iex> {:ok, capture} = Capture.extract(ast)
      iex> context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      iex> {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^capture_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build(Capture.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(capture_info, context, index) do
    # Generate capture IRI
    capture_iri = generate_capture_iri(context, index)

    # Build triples based on capture type
    triples = build_capture_triples(capture_iri, capture_info, context)

    {capture_iri, triples}
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  # Generate capture IRI based on context
  defp generate_capture_iri(context, index) do
    context_iri = get_context_iri(context)
    IRI.for_capture(context_iri, index)
  end

  # Get the context IRI (module or file-based)
  defp get_context_iri(%Context{metadata: %{module: module}} = context)
       when is_list(module) and module != [] do
    module_name = Enum.join(module, ".")
    IRI.for_module(context.base_iri, module_name)
  end

  defp get_context_iri(%Context{parent_module: parent_module})
       when not is_nil(parent_module) do
    parent_module
  end

  defp get_context_iri(%Context{file_path: file_path} = context)
       when is_binary(file_path) and file_path != "" do
    IRI.for_source_file(context.base_iri, file_path)
  end

  defp get_context_iri(context) do
    # Fallback to base_iri with captures namespace
    RDF.iri("#{context.base_iri}captures")
  end

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  # Build triples based on capture type
  defp build_capture_triples(capture_iri, capture_info, context) do
    case capture_info.type do
      :named_local ->
        build_named_local_triples(capture_iri, capture_info, context)

      :named_remote ->
        build_named_remote_triples(capture_iri, capture_info, context)

      :shorthand ->
        build_shorthand_triples(capture_iri, capture_info)
    end
  end

  # Build triples for named local capture (&foo/1)
  defp build_named_local_triples(capture_iri, capture_info, context) do
    base_triples = [
      # rdf:type struct:CapturedFunction
      Helpers.type_triple(capture_iri, Structure.CapturedFunction),
      # struct:arity
      build_arity_triple(capture_iri, capture_info.arity)
    ]

    # Add refersToFunction if we can build a function IRI
    function_triples = build_local_function_reference(capture_iri, capture_info, context)

    base_triples ++ function_triples
  end

  # Build triples for named remote capture (&Module.func/1)
  defp build_named_remote_triples(capture_iri, capture_info, context) do
    base_triples = [
      # rdf:type struct:CapturedFunction
      Helpers.type_triple(capture_iri, Structure.CapturedFunction),
      # struct:arity
      build_arity_triple(capture_iri, capture_info.arity)
    ]

    # Add module reference
    module_triples = build_module_reference(capture_iri, capture_info, context)

    # Add function reference
    function_triples = build_remote_function_reference(capture_iri, capture_info, context)

    base_triples ++ module_triples ++ function_triples
  end

  # Build triples for shorthand capture (&(&1 + 1))
  defp build_shorthand_triples(capture_iri, capture_info) do
    [
      # rdf:type struct:PartialApplication (subclass of CapturedFunction)
      Helpers.type_triple(capture_iri, Structure.PartialApplication),
      # struct:arity (derived from placeholder analysis)
      build_arity_triple(capture_iri, capture_info.arity)
    ]
  end

  # ===========================================================================
  # Property Triples
  # ===========================================================================

  # Build struct:arity triple
  defp build_arity_triple(capture_iri, arity) do
    Helpers.datatype_property(
      capture_iri,
      Structure.arity(),
      arity,
      RDF.XSD.NonNegativeInteger
    )
  end

  # Build core:refersToModule triple
  defp build_module_reference(capture_iri, capture_info, context) do
    if capture_info.module do
      module_name = module_to_string(capture_info.module)
      module_iri = IRI.for_module(context.base_iri, module_name)

      [Helpers.object_property(capture_iri, Core.refersToModule(), module_iri)]
    else
      []
    end
  end

  # Build core:refersToFunction triple for local captures
  defp build_local_function_reference(capture_iri, capture_info, context) do
    # For local captures, we need the module from context
    module = get_context_module(context)

    if module && capture_info.function do
      function_name = Atom.to_string(capture_info.function)
      function_iri = IRI.for_function(context.base_iri, module, function_name, capture_info.arity)

      [Helpers.object_property(capture_iri, Core.refersToFunction(), function_iri)]
    else
      []
    end
  end

  # Build core:refersToFunction triple for remote captures
  defp build_remote_function_reference(capture_iri, capture_info, context) do
    if capture_info.module && capture_info.function do
      module_name = module_to_string(capture_info.module)
      function_name = Atom.to_string(capture_info.function)
      function_iri = IRI.for_function(context.base_iri, module_name, function_name, capture_info.arity)

      [Helpers.object_property(capture_iri, Core.refersToFunction(), function_iri)]
    else
      []
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Convert module to string representation
  defp module_to_string(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_leading("Elixir.", "")
  end

  defp module_to_string(module) when is_binary(module), do: module

  # Get module name from context
  defp get_context_module(%Context{metadata: %{module: module}})
       when is_list(module) and module != [] do
    Enum.join(module, ".")
  end

  defp get_context_module(%Context{parent_module: parent_module})
       when not is_nil(parent_module) do
    # Extract module name from IRI if available
    parent_module
    |> to_string()
    |> extract_module_from_iri()
  end

  defp get_context_module(_context), do: nil

  # Extract module name from an IRI string
  defp extract_module_from_iri(iri_string) do
    # Match pattern like "https://example.org/code#ModuleName" or "...#ModuleName/func/1"
    case Regex.run(~r/#([A-Z][A-Za-z0-9_.]*)(?:\/|$)/, iri_string) do
      [_, module_name] -> module_name
      nil -> nil
    end
  end
end
