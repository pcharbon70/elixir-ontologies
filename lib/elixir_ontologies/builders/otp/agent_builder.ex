defmodule ElixirOntologies.Builders.OTP.AgentBuilder do
  @moduledoc """
  Builds RDF triples for OTP Agent implementations.

  This module transforms `ElixirOntologies.Extractors.OTP.Agent` results into RDF
  triples following the elixir-otp.ttl ontology. It handles:

  - Agent implementations (use Agent vs @behaviour Agent)
  - Agent detection via function calls only
  - Use options (restart strategy, shutdown, etc.)
  - Detection methods (use, behaviour, function_call)

  ## Agent Patterns

  **Agent**: Simple state wrapper around GenServer
  - Lightweight state management
  - get/update/get_and_update operations
  - Built atop GenServer

  ## Usage

      alias ElixirOntologies.Builders.OTP.{AgentBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.Agent

      # Build Agent implementation
      agent_info = %Agent{
        detection_method: :use,
        use_options: [],
        function_calls: [],
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#Counter>
      context = Context.new(base_iri: "https://example.org/code#")
      {agent_iri, triples} = AgentBuilder.build_agent(agent_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Agent
      iex> agent_info = %Agent{
      ...>   detection_method: :use,
      ...>   use_options: [],
      ...>   function_calls: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestAgent")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {agent_iri, _triples} = AgentBuilder.build_agent(agent_info, module_iri, context)
      iex> to_string(agent_iri)
      "https://example.org/code#TestAgent"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.Agent
  alias NS.{OTP, Core}

  # ===========================================================================
  # Public API - Agent Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for an Agent implementation.

  Takes an Agent extraction result and builder context, returns the Agent IRI
  and a list of RDF triples representing the Agent implementation.

  ## Parameters

  - `agent_info` - Agent extraction result from `Extractors.OTP.Agent.extract/1`
  - `module_iri` - The IRI of the module implementing Agent
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{agent_iri, triples}` where:
  - `agent_iri` - The IRI of the Agent (same as module_iri)
  - `triples` - List of RDF triples describing the Agent

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Agent
      iex> agent_info = %Agent{
      ...>   detection_method: :use,
      ...>   use_options: [],
      ...>   function_calls: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestAgent")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {agent_iri, triples} = AgentBuilder.build_agent(agent_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^agent_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_agent(Agent.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_agent(agent_info, module_iri, context) do
    # Agent IRI is the same as module IRI (Agent implementation IS a module)
    agent_iri = module_iri

    # Build all triples
    triples =
      [
        # Core Agent triples
        build_type_triple(agent_iri),
        build_implements_otp_behaviour_triple(agent_iri)
      ] ++
        build_location_triple(agent_iri, agent_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {agent_iri, triples}
  end

  # ===========================================================================
  # Agent Implementation Triple Generation
  # ===========================================================================

  # Build rdf:type otp:Agent triple
  defp build_type_triple(agent_iri) do
    Helpers.type_triple(agent_iri, OTP.Agent)
  end

  # Build otp:implementsOTPBehaviour triple
  defp build_implements_otp_behaviour_triple(agent_iri) do
    # Link to the Agent behaviour class
    Helpers.object_property(agent_iri, OTP.implementsOTPBehaviour(), OTP.Agent)
  end

  # Build location triple if present
  defp build_location_triple(_agent_iri, nil, _context), do: []
  defp build_location_triple(_agent_iri, _location, %Context{file_path: nil}), do: []

  defp build_location_triple(agent_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(agent_iri, Core.hasSourceLocation(), location_iri)]
  end
end
