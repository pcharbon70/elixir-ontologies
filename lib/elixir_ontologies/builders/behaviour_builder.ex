defmodule ElixirOntologies.Builders.BehaviourBuilder do
  @moduledoc """
  Builds RDF triples for Elixir behaviours and their implementations.

  This module transforms `ElixirOntologies.Extractors.Behaviour` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Behaviour definitions (callbacks and macrocallbacks)
  - Optional vs required callbacks
  - Behaviour implementations (@behaviour declarations)
  - Callback implementation linkage
  - Defoverridable metadata

  ## Behaviour vs Protocol

  **Behaviours** define contract-based polymorphism:
  - Use module IRI pattern: `base#GenServer`
  - Define callback contracts (function signatures with specs)
  - Can have optional callbacks (@optional_callbacks)
  - Module-based: modules implement behaviours
  - Compile-time verification

  **Protocols** use type-based polymorphism:
  - Dispatch on first argument type
  - Runtime consolidation
  - Always dispatched based on data type

  ## Usage

      alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      alias ElixirOntologies.Extractors.Behaviour

      # Build behaviour definition
      behaviour_info = %Behaviour{
        callbacks: [%{name: :init, arity: 1, is_optional: false, ...}],
        macrocallbacks: [],
        optional_callbacks: []
      }
      module_iri = ~I<https://example.org/code#MyBehaviour>
      context = Context.new(base_iri: "https://example.org/code#")
      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Build behaviour implementation
      impl_info = %{
        behaviours: [%{behaviour: GenServer, ...}],
        overridables: [],
        functions: [{:init, 1}, {:handle_call, 3}]
      }
      module_iri = ~I<https://example.org/code#MyServer>
      {impl_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> behaviour_info = %Behaviour{
      ...>   callbacks: [],
      ...>   macrocallbacks: [],
      ...>   optional_callbacks: [],
      ...>   doc: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MyBehaviour")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {behaviour_iri, _triples} = BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)
      iex> to_string(behaviour_iri)
      "https://example.org/code#MyBehaviour"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Behaviour
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Behaviour Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a behaviour definition.

  Takes a behaviour extraction result and builder context, returns the behaviour IRI
  and a list of RDF triples representing the behaviour and its callbacks.

  ## Parameters

  - `behaviour_info` - Behaviour extraction result from `Extractors.Behaviour.extract_from_body/1`
  - `module_iri` - The IRI of the module defining this behaviour
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{behaviour_iri, triples}` where:
  - `behaviour_iri` - The IRI of the behaviour (same as module_iri)
  - `triples` - List of RDF triples describing the behaviour

  ## Examples

      iex> alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> behaviour_info = %Behaviour{
      ...>   callbacks: [],
      ...>   macrocallbacks: [],
      ...>   optional_callbacks: [],
      ...>   doc: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestBehaviour")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^behaviour_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_behaviour(Behaviour.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_behaviour(behaviour_info, module_iri, context) do
    # Behaviour IRI is the same as module IRI
    behaviour_iri = module_iri

    # Build all triples
    triples =
      [
        # Core behaviour triples
        build_type_triple(behaviour_iri, :behaviour),
        build_module_defines_behaviour_triple(behaviour_iri)
      ] ++
        build_callback_triples(behaviour_iri, behaviour_info, context) ++
        build_macrocallback_triples(behaviour_iri, behaviour_info, context) ++
        build_docstring_triple(behaviour_iri, behaviour_info)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {behaviour_iri, triples}
  end

  # ===========================================================================
  # Public API - Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a behaviour implementation.

  Takes an implementation extraction result and builder context, returns the
  module IRI and a list of RDF triples representing the implementation
  relationship between the module and the behaviours it implements.

  ## Parameters

  - `impl_info` - Implementation extraction result from `Behaviour.extract_implementations/1`
  - `module_iri` - The IRI of the implementing module
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{module_iri, triples}` where:
  - `module_iri` - The IRI of the implementing module (unchanged)
  - `triples` - List of RDF triples describing the implementation

  ## Examples

      iex> alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      iex> impl_info = %{
      ...>   behaviours: [],
      ...>   overridables: [],
      ...>   functions: []
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MyModule")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {returned_iri, _triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)
      iex> returned_iri == module_iri
      true
  """
  @spec build_implementation(Behaviour.implementation_result(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_implementation(impl_info, module_iri, context) do
    # Build all triples
    triples =
      build_behaviour_implementation_triples(module_iri, impl_info, context) ++
        build_callback_implementation_triples(module_iri, impl_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {module_iri, triples}
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Build rdf:type triple
  defp build_type_triple(subject_iri, :behaviour) do
    Helpers.type_triple(subject_iri, Structure.Behaviour)
  end

  # Build struct:definesBehaviour triple from module to behaviour
  defp build_module_defines_behaviour_triple(behaviour_iri) do
    # Behaviour IRI is the module IRI, so this triple links module to itself as behaviour
    Helpers.object_property(behaviour_iri, Structure.definesBehaviour(), behaviour_iri)
  end

  # ===========================================================================
  # Callback Triple Generation
  # ===========================================================================

  # Build triples for callback definitions
  defp build_callback_triples(behaviour_iri, behaviour_info, context) do
    behaviour_info.callbacks
    |> Enum.flat_map(fn callback ->
      callback_iri = generate_callback_iri(behaviour_iri, callback)

      # Determine callback class based on optional status
      callback_class =
        if callback.is_optional do
          Structure.OptionalCallback
        else
          Structure.Callback
        end

      [
        # rdf:type struct:Callback or struct:OptionalCallback
        Helpers.type_triple(callback_iri, callback_class),
        # struct:functionName
        Helpers.datatype_property(
          callback_iri,
          Structure.functionName(),
          Atom.to_string(callback.name),
          RDF.XSD.String
        ),
        # struct:arity
        Helpers.datatype_property(
          callback_iri,
          Structure.arity(),
          callback.arity,
          RDF.XSD.NonNegativeInteger
        ),
        # behaviour struct:definesCallback callback
        Helpers.object_property(behaviour_iri, Structure.definesCallback(), callback_iri)
      ] ++
        build_callback_doc_triple(callback_iri, callback) ++
        build_callback_location_triple(callback_iri, callback, context)
    end)
  end

  # Build triples for macrocallback definitions
  defp build_macrocallback_triples(behaviour_iri, behaviour_info, context) do
    behaviour_info.macrocallbacks
    |> Enum.flat_map(fn macrocallback ->
      callback_iri = generate_callback_iri(behaviour_iri, macrocallback)

      [
        # rdf:type struct:MacroCallback
        Helpers.type_triple(callback_iri, Structure.MacroCallback),
        # struct:functionName
        Helpers.datatype_property(
          callback_iri,
          Structure.functionName(),
          Atom.to_string(macrocallback.name),
          RDF.XSD.String
        ),
        # struct:arity
        Helpers.datatype_property(
          callback_iri,
          Structure.arity(),
          macrocallback.arity,
          RDF.XSD.NonNegativeInteger
        ),
        # behaviour struct:definesCallback macrocallback
        Helpers.object_property(behaviour_iri, Structure.definesCallback(), callback_iri)
      ] ++
        build_callback_doc_triple(callback_iri, macrocallback) ++
        build_callback_location_triple(callback_iri, macrocallback, context)
    end)
  end

  # Generate IRI for callback
  defp generate_callback_iri(behaviour_iri, callback) do
    # Pattern: Behaviour/callback_name/arity
    RDF.iri("#{behaviour_iri}/#{callback.name}/#{callback.arity}")
  end

  # Build callback documentation triple if present
  defp build_callback_doc_triple(callback_iri, callback) do
    case callback.doc do
      nil ->
        []

      doc when is_binary(doc) ->
        [Helpers.datatype_property(callback_iri, Structure.docstring(), doc, RDF.XSD.String)]
    end
  end

  # Build callback source location triple if present
  defp build_callback_location_triple(callback_iri, callback, context) do
    case {callback.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)
        end_line = location.end_line || location.start_line
        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(callback_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # ===========================================================================
  # Implementation Triple Generation
  # ===========================================================================

  # Build triples for behaviour implementations
  defp build_behaviour_implementation_triples(module_iri, impl_info, context) do
    impl_info.behaviours
    |> Enum.flat_map(fn behaviour_impl ->
      # Generate behaviour IRI
      behaviour_module = normalize_behaviour_module(behaviour_impl.behaviour)
      behaviour_iri = IRI.for_module(context.base_iri, behaviour_module)

      [
        # module struct:implementsBehaviour behaviour
        Helpers.object_property(module_iri, Structure.implementsBehaviour(), behaviour_iri)
      ] ++ build_impl_location_triple(module_iri, behaviour_impl, context)
    end)
  end

  # Build implementation source location triple if present
  defp build_impl_location_triple(module_iri, behaviour_impl, context) do
    case {behaviour_impl.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)
        end_line = location.end_line || location.start_line
        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(module_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # Normalize behaviour module to string
  defp normalize_behaviour_module(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp normalize_behaviour_module(module) when is_binary(module), do: module

  # ===========================================================================
  # Callback Implementation Triple Generation
  # ===========================================================================

  # Build triples linking implementation functions to behaviour callbacks
  defp build_callback_implementation_triples(module_iri, impl_info, context) do
    # Get list of implemented functions
    implemented_functions = MapSet.new(impl_info.functions)

    # For each behaviour, check which callbacks are implemented
    impl_info.behaviours
    |> Enum.flat_map(fn behaviour_impl ->
      behaviour_module = normalize_behaviour_module(behaviour_impl.behaviour)

      # Only link known OTP behaviours for now
      case get_known_callbacks(behaviour_module) do
        nil ->
          []

        callbacks ->
          callbacks
          |> Enum.filter(fn {name, arity} ->
            MapSet.member?(implemented_functions, {name, arity})
          end)
          |> Enum.map(fn {name, arity} ->
            # Generate function and callback IRIs
            # Extract module name from module IRI
            module_string = module_iri |> to_string() |> String.split("#") |> List.last()
            function_iri = IRI.for_function(context.base_iri, module_string, name, arity)
            behaviour_iri = IRI.for_module(context.base_iri, behaviour_module)
            callback_iri = RDF.iri("#{behaviour_iri}/#{name}/#{arity}")

            # function struct:implementsCallback callback
            Helpers.object_property(function_iri, Structure.implementsCallback(), callback_iri)
          end)
      end
    end)
  end

  # Known OTP behaviour callbacks
  defp get_known_callbacks("GenServer") do
    [
      {:init, 1},
      {:handle_call, 3},
      {:handle_cast, 2},
      {:handle_info, 2},
      {:terminate, 2},
      {:code_change, 3},
      {:format_status, 1},
      {:format_status, 2}
    ]
  end

  defp get_known_callbacks("Supervisor") do
    [{:init, 1}]
  end

  defp get_known_callbacks("Agent") do
    []
  end

  defp get_known_callbacks("Task") do
    []
  end

  defp get_known_callbacks("Application") do
    [{:start, 2}, {:stop, 1}, {:config_change, 3}]
  end

  defp get_known_callbacks(_), do: nil

  # ===========================================================================
  # Documentation Triple Generation
  # ===========================================================================

  # Build struct:docstring triple for behaviour (if present)
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
end
