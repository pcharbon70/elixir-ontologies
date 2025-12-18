defmodule ElixirOntologies.Builders.OTP.GenServerBuilder do
  @moduledoc """
  Builds RDF triples for OTP GenServer implementations.

  This module transforms `ElixirOntologies.Extractors.OTP.GenServer` results into RDF
  triples following the elixir-otp.ttl ontology. It handles:

  - GenServer implementations (use GenServer vs @behaviour GenServer)
  - GenServer callbacks (init, handle_call, handle_cast, etc.)
  - Use options (restart strategy, shutdown, etc.)
  - Callback annotations (@impl)

  ## GenServer Patterns

  **GenServer Implementation**: A module implementing the GenServer behaviour
  - Detection via `use GenServer` or `@behaviour GenServer`
  - Optional use options for OTP supervision
  - Eight standard callbacks with specific arities

  **GenServer Callbacks**: Functions implementing GenServer behaviour
  - init/1 - Initialize server state
  - handle_call/3 - Synchronous request/reply
  - handle_cast/2 - Asynchronous message
  - handle_info/2 - Generic message handling
  - handle_continue/2 - Continuation after init
  - terminate/2 - Cleanup on shutdown
  - code_change/3 - Hot code upgrade
  - format_status/1 - Status formatting

  ## Usage

      alias ElixirOntologies.Builders.OTP.{GenServerBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.GenServer

      # Build GenServer implementation
      genserver_info = %GenServer{
        detection_method: :use,
        use_options: [restart: :transient],
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#Counter>
      context = Context.new(base_iri: "https://example.org/code#")
      {genserver_iri, triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Build GenServer callback
      callback_info = %GenServer.Callback{
        type: :init,
        name: :init,
        arity: 1,
        clauses: 1,
        has_impl: true,
        location: nil,
        metadata: %{}
      }
      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.GenServerBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.GenServer
      iex> genserver_info = %GenServer{
      ...>   detection_method: :use,
      ...>   use_options: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestServer")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {genserver_iri, _triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)
      iex> to_string(genserver_iri)
      "https://example.org/code#TestServer"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.GenServer
  alias NS.{OTP, Core}

  # ===========================================================================
  # Public API - GenServer Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a GenServer implementation.

  Takes a GenServer extraction result and builder context, returns the GenServer IRI
  and a list of RDF triples representing the GenServer implementation.

  ## Parameters

  - `genserver_info` - GenServer extraction result from `Extractors.OTP.GenServer.extract/1`
  - `module_iri` - The IRI of the module implementing GenServer
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{genserver_iri, triples}` where:
  - `genserver_iri` - The IRI of the GenServer (same as module_iri)
  - `triples` - List of RDF triples describing the GenServer

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.GenServerBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.GenServer
      iex> genserver_info = %GenServer{
      ...>   detection_method: :use,
      ...>   use_options: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestServer")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {genserver_iri, triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^genserver_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_genserver(GenServer.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_genserver(genserver_info, module_iri, context) do
    # GenServer IRI is the same as module IRI (GenServer implementation IS a module)
    genserver_iri = module_iri

    # Build all triples
    triples =
      [
        # Core GenServer triples
        build_type_triple(genserver_iri),
        build_implements_otp_behaviour_triple(genserver_iri)
      ] ++
        build_location_triple(genserver_iri, genserver_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {genserver_iri, triples}
  end

  # ===========================================================================
  # Public API - GenServer Callback Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a GenServer callback.

  Takes a GenServer callback extraction result and builder context, returns the callback IRI
  and a list of RDF triples representing the callback.

  ## Parameters

  - `callback_info` - Callback extraction result from `Extractors.OTP.GenServer.extract_callbacks/1`
  - `module_iri` - The IRI of the module containing this callback
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{callback_iri, triples}` where:
  - `callback_iri` - The IRI of the callback (function IRI pattern)
  - `triples` - List of RDF triples describing the callback

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.GenServerBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.GenServer
      iex> callback_info = %GenServer.Callback{
      ...>   type: :init,
      ...>   name: :init,
      ...>   arity: 1,
      ...>   clauses: 1,
      ...>   has_impl: true,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestServer")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {callback_iri, _triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)
      iex> to_string(callback_iri)
      "https://example.org/code#TestServer/init/1"
  """
  @spec build_callback(GenServer.Callback.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_callback(callback_info, module_iri, context) do
    # Generate callback IRI using function IRI pattern
    module_name = extract_module_name(module_iri)
    callback_iri = IRI.for_function(context.base_iri, module_name, callback_info.name, callback_info.arity)

    # Determine callback-specific class
    callback_class = determine_callback_class(callback_info.type)

    # Build all triples
    triples =
      [
        # Type triples (specific callback class + GenServerCallback)
        build_callback_type_triple(callback_iri, callback_class),
        build_generic_callback_type_triple(callback_iri),
        # Link to GenServer implementation
        build_has_callback_triple(module_iri, callback_iri)
      ] ++
        build_callback_location_triple(callback_iri, callback_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {callback_iri, triples}
  end

  # ===========================================================================
  # GenServer Implementation Triple Generation
  # ===========================================================================

  # Build rdf:type otp:GenServerImplementation triple
  defp build_type_triple(genserver_iri) do
    Helpers.type_triple(genserver_iri, OTP.GenServerImplementation)
  end

  # Build otp:implementsOTPBehaviour triple
  defp build_implements_otp_behaviour_triple(genserver_iri) do
    # Link to the GenServer behaviour class
    Helpers.object_property(genserver_iri, OTP.implementsOTPBehaviour(), OTP.GenServer)
  end

  # Build location triple if present
  defp build_location_triple(_genserver_iri, nil, _context), do: []
  defp build_location_triple(_genserver_iri, _location, %Context{file_path: nil}), do: []

  defp build_location_triple(genserver_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(genserver_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # GenServer Callback Triple Generation
  # ===========================================================================

  # Build rdf:type for specific callback class
  defp build_callback_type_triple(callback_iri, callback_class) do
    Helpers.type_triple(callback_iri, callback_class)
  end

  # Build rdf:type otp:GenServerCallback triple
  defp build_generic_callback_type_triple(callback_iri) do
    Helpers.type_triple(callback_iri, OTP.GenServerCallback)
  end

  # Build otp:hasGenServerCallback triple
  defp build_has_callback_triple(genserver_iri, callback_iri) do
    Helpers.object_property(genserver_iri, OTP.hasGenServerCallback(), callback_iri)
  end

  # Build callback location triple if present
  defp build_callback_location_triple(_callback_iri, nil, _context), do: []
  defp build_callback_location_triple(_callback_iri, _location, %Context{file_path: nil}), do: []

  defp build_callback_location_triple(callback_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(callback_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Determine the specific callback class based on callback type
  defp determine_callback_class(:init), do: OTP.InitCallback
  defp determine_callback_class(:handle_call), do: OTP.HandleCallCallback
  defp determine_callback_class(:handle_cast), do: OTP.HandleCastCallback
  defp determine_callback_class(:handle_info), do: OTP.HandleInfoCallback
  defp determine_callback_class(:handle_continue), do: OTP.HandleContinueCallback
  defp determine_callback_class(:terminate), do: OTP.TerminateCallback
  defp determine_callback_class(:code_change), do: OTP.CodeChangeCallback
  defp determine_callback_class(:format_status), do: OTP.FormatStatusCallback

  # Extract module name from module IRI
  defp extract_module_name(module_iri) do
    module_iri
    |> to_string()
    |> String.split("#")
    |> List.last()
    |> URI.decode()
  end
end
