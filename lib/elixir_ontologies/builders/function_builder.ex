defmodule ElixirOntologies.Builders.FunctionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir functions.

  This module transforms `ElixirOntologies.Extractors.Function` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Function type classification (Function, PublicFunction, PrivateFunction, GuardFunction, DelegatedFunction)
  - Function identity properties (name, arity, minArity)
  - Module relationships (belongsTo and inverse containsFunction)
  - Function documentation
  - Delegation target (for defdelegate)
  - Source location information

  ## Usage

      alias ElixirOntologies.Builders.{FunctionBuilder, Context}
      alias ElixirOntologies.Extractors.Function

      function_info = %Function{
        type: :function,
        name: :get_user,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        metadata: %{module: [:MyApp, :Users]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # function_iri => ~I<https://example.org/code#MyApp.Users/get_user/1>
      # triples => [
      #   {function_iri, RDF.type(), Structure.PublicFunction},
      #   {function_iri, Structure.functionName(), "get_user"},
      #   {function_iri, Structure.arity(), 1},
      #   ...
      # ]

  ## Examples

      iex> alias ElixirOntologies.Builders.{FunctionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Function
      iex> function_info = %Function{
      ...>   type: :function,
      ...>   name: :hello,
      ...>   arity: 0,
      ...>   min_arity: 0,
      ...>   visibility: :public,
      ...>   docstring: nil,
      ...>   location: nil,
      ...>   metadata: %{module: [:MyApp]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {function_iri, _triples} = FunctionBuilder.build(function_info, context)
      iex> to_string(function_iri)
      "https://example.org/code#MyApp/hello/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Function, as: FunctionExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a function.

  Takes a function extraction result and builder context, returns the function IRI
  and a list of RDF triples representing the function in the ontology.

  ## Parameters

  - `function_info` - Function extraction result from `Extractors.Function.extract/1`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{function_iri, triples}` where:
  - `function_iri` - The IRI of the function
  - `triples` - List of RDF triples describing the function

  ## Examples

      iex> alias ElixirOntologies.Builders.{FunctionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Function
      iex> function_info = %Function{
      ...>   type: :function,
      ...>   name: :test,
      ...>   arity: 1,
      ...>   min_arity: 1,
      ...>   visibility: :private,
      ...>   docstring: nil,
      ...>   location: nil,
      ...>   metadata: %{module: [:MyApp]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {function_iri, triples} = FunctionBuilder.build(function_info, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^function_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build(FunctionExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(function_info, context) do
    # Generate function IRI
    function_iri = generate_function_iri(function_info, context)

    # Build all triples
    triples =
      [
        # Core function triples
        build_type_triple(function_iri, function_info),
        build_name_triple(function_iri, function_info),
        build_arity_triple(function_iri, function_info)
      ] ++
        build_min_arity_triple(function_iri, function_info) ++
        build_belongs_to_triple(function_iri, function_info, context) ++
        build_docstring_triple(function_iri, function_info) ++
        build_delegate_triple(function_iri, function_info, context) ++
        build_location_triple(function_iri, function_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {function_iri, triples}
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Generate function IRI from function information
  defp generate_function_iri(function_info, context) do
    case function_info.metadata.module do
      nil ->
        # Function without module - use function name as module
        # This is an edge case that shouldn't normally happen
        raise "Function #{function_info.name}/#{function_info.arity} has no module context"

      module_name_list ->
        module_name = module_name_string(module_name_list)

        IRI.for_function(
          context.base_iri,
          module_name,
          function_info.name,
          function_info.arity
        )
    end
  end

  # Build rdf:type triple based on function type and visibility
  defp build_type_triple(function_iri, function_info) do
    class = determine_function_class(function_info)
    Helpers.type_triple(function_iri, class)
  end

  # Determine the appropriate RDF class for the function
  defp determine_function_class(function_info) do
    case {function_info.type, function_info.visibility} do
      {:guard, :public} -> Structure.GuardFunction
      {:guard, :private} -> Structure.GuardFunction
      {:delegate, _} -> Structure.DelegatedFunction
      {:function, :public} -> Structure.PublicFunction
      {:function, :private} -> Structure.PrivateFunction
    end
  end

  # Build struct:functionName datatype property
  defp build_name_triple(function_iri, function_info) do
    function_name = Atom.to_string(function_info.name)

    Helpers.datatype_property(
      function_iri,
      Structure.functionName(),
      function_name,
      RDF.XSD.String
    )
  end

  # Build struct:arity datatype property
  defp build_arity_triple(function_iri, function_info) do
    Helpers.datatype_property(
      function_iri,
      Structure.arity(),
      function_info.arity,
      RDF.XSD.NonNegativeInteger
    )
  end

  # Build struct:minArity datatype property (only if different from arity)
  defp build_min_arity_triple(function_iri, function_info) do
    if function_info.min_arity != function_info.arity do
      [
        Helpers.datatype_property(
          function_iri,
          Structure.minArity(),
          function_info.min_arity,
          RDF.XSD.NonNegativeInteger
        )
      ]
    else
      []
    end
  end

  # ===========================================================================
  # Module Relationships
  # ===========================================================================

  # Build struct:belongsTo and inverse struct:containsFunction triples
  defp build_belongs_to_triple(function_iri, function_info, context) do
    case function_info.metadata.module do
      nil ->
        # Function without module context - skip relationship
        []

      module_name_list ->
        module_name = module_name_string(module_name_list)
        module_iri = IRI.for_module(context.base_iri, module_name)

        [
          # function -> module relationship
          Helpers.object_property(function_iri, Structure.belongsTo(), module_iri),
          # module -> function relationship (inverse)
          Helpers.object_property(module_iri, Structure.containsFunction(), function_iri)
        ]
    end
  end

  # ===========================================================================
  # Documentation
  # ===========================================================================

  # Build struct:docstring datatype property (if present)
  defp build_docstring_triple(function_iri, function_info) do
    case function_info.docstring do
      nil ->
        []

      false ->
        # @doc false - intentionally hidden
        []

      doc when is_binary(doc) ->
        [Helpers.datatype_property(function_iri, Structure.docstring(), doc, RDF.XSD.String)]
    end
  end

  # ===========================================================================
  # Delegation Support
  # ===========================================================================

  # Build struct:delegatesTo triple for defdelegate functions
  defp build_delegate_triple(function_iri, function_info, context) do
    case function_info.metadata[:delegates_to] do
      nil ->
        []

      {target_module, target_function, target_arity} ->
        # Generate IRI for the target function
        target_module_name = module_name_from_term(target_module)
        target_iri =
          IRI.for_function(
            context.base_iri,
            target_module_name,
            target_function,
            target_arity
          )

        [Helpers.object_property(function_iri, Structure.delegatesTo(), target_iri)]
    end
  end

  # ===========================================================================
  # Source Location
  # ===========================================================================

  # Build core:hasSourceLocation triple if location information available
  defp build_location_triple(function_iri, function_info, context) do
    case {function_info.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        # Location exists but no file path - skip location triple
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)

        # Need end line - use start line if end not available
        end_line = location.end_line || location.start_line

        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(function_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Convert module name list to string
  defp module_name_string(module) when is_list(module) do
    Enum.join(module, ".")
  end

  # Convert module term (atom or list) to string for IRI generation
  defp module_name_from_term(module) when is_atom(module) do
    # Erlang module or single-segment Elixir module
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name_from_term(module) when is_list(module) do
    module_name_string(module)
  end
end
