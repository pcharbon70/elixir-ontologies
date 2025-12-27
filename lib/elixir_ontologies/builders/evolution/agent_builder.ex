defmodule ElixirOntologies.Builders.Evolution.AgentBuilder do
  @moduledoc """
  Builds RDF triples for development agents using PROV-O Agent class.

  This module transforms `ElixirOntologies.Extractors.Evolution.Agent`
  results into RDF triples following the elixir-evolution.ttl ontology. It handles:

  - Agent type classification (Developer, Bot, CISystem, LLMAgent)
  - Agent properties (name, email)
  - Temporal tracking (first_seen, last_seen)

  ## Usage

      alias ElixirOntologies.Builders.Evolution.AgentBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}

      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, agents} = Agent.extract_agents(".", commit)
      context = Context.new(base_iri: "https://example.org/code#")

      {agent_iri, triples} = AgentBuilder.build(hd(agents), context)

  ## RDF Output

  For a developer agent:

      agent:abc123 a evo:Developer, prov:Agent ;
          evo:developerName "Jane Doe" ;
          evo:developerEmail "jane@example.com" .

  For a bot agent:

      agent:xyz789 a evo:Bot, prov:Agent ;
          evo:botName "dependabot[bot]" .

  ## Agent Type Mapping

  | Agent Type | Ontology Class |
  |------------|----------------|
  | `:developer` | `evolution:Developer` |
  | `:bot` | `evolution:Bot` |
  | `:ci` | `evolution:CISystem` |
  | `:llm` | `evolution:LLMAgent` |

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{
      ...>   agent_id: "agent:abc123",
      ...>   agent_type: :developer,
      ...>   name: "Jane Doe",
      ...>   email: "jane@example.com",
      ...>   identity: "jane@example.com"
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {agent_iri, triples} = AgentBuilder.build(agent, context)
      iex> to_string(agent_iri) |> String.contains?("abc123")
      true
      iex> length(triples) >= 2
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.Evolution.Agent
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an agent.

  Takes an Agent struct and builder context, returns the agent IRI
  and a list of RDF triples representing the agent in the ontology.

  ## Parameters

  - `agent` - Agent struct from `Extractors.Evolution.Agent`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{agent_iri, triples}` where:
  - `agent_iri` - The IRI of the agent
  - `triples` - List of RDF triples describing the agent

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{
      ...>   agent_id: "agent:def456",
      ...>   agent_type: :bot,
      ...>   name: "dependabot[bot]",
      ...>   email: "dependabot[bot]@users.noreply.github.com",
      ...>   identity: "dependabot[bot]@users.noreply.github.com"
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {agent_iri, triples} = AgentBuilder.build(agent, context)
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(Agent.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%Agent{} = agent, %Context{} = context) do
    # Generate agent IRI
    agent_iri = generate_agent_iri(agent, context)

    # Build all triples using list of lists pattern
    triples =
      [
        build_type_triples(agent_iri, agent),
        build_name_triple(agent_iri, agent),
        build_email_triple(agent_iri, agent)
      ]
      |> Helpers.finalize_triples()

    {agent_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple agents.

  ## Parameters

  - `agents` - List of Agent structs
  - `context` - Builder context

  ## Returns

  A list of `{agent_iri, triples}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> results = AgentBuilder.build_all([], context)
      iex> results
      []
  """
  @spec build_all([Agent.t()], Context.t()) :: [{RDF.IRI.t(), [RDF.Triple.t()]}]
  def build_all(agents, context) when is_list(agents) do
    Enum.map(agents, &build(&1, context))
  end

  @doc """
  Builds RDF triples for multiple agents and collects all triples.

  Returns a flat list of all triples from all agents.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = AgentBuilder.build_all_triples([], context)
      iex> triples
      []
  """
  @spec build_all_triples([Agent.t()], Context.t()) :: [RDF.Triple.t()]
  def build_all_triples(agents, context) when is_list(agents) do
    agents
    |> build_all(context)
    |> Enum.flat_map(fn {_iri, triples} -> triples end)
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  defp generate_agent_iri(agent, context) do
    base = to_string(context.base_iri)

    # Agent IDs are in format "agent:abc123"
    # We extract the ID part and create a proper IRI
    case agent.agent_id do
      "agent:" <> id ->
        RDF.iri("#{base}agent/#{id}")

      id ->
        # Fallback if not prefixed
        RDF.iri("#{base}agent/#{id}")
    end
  end

  # ===========================================================================
  # Type Triple Generation
  # ===========================================================================

  defp build_type_triples(agent_iri, agent) do
    # Dual-typing: prov:Agent + specific evolution class
    evolution_class = agent_type_to_class(agent.agent_type)
    Helpers.dual_type_triples(agent_iri, PROV.Agent, evolution_class)
  end

  @doc """
  Maps an agent type atom to its corresponding ontology class.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> AgentBuilder.agent_type_to_class(:developer) == Evolution.Developer
      true

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> AgentBuilder.agent_type_to_class(:bot) == Evolution.Bot
      true

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> AgentBuilder.agent_type_to_class(:ci) == Evolution.CISystem
      true

      iex> alias ElixirOntologies.Builders.Evolution.AgentBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> AgentBuilder.agent_type_to_class(:llm) == Evolution.LLMAgent
      true
  """
  @spec agent_type_to_class(atom()) :: RDF.IRI.t()
  def agent_type_to_class(:developer), do: Evolution.Developer
  def agent_type_to_class(:bot), do: Evolution.Bot
  def agent_type_to_class(:ci), do: Evolution.CISystem
  def agent_type_to_class(:llm), do: Evolution.LLMAgent
  # Catch-all with guard for unknown atom types
  def agent_type_to_class(type) when is_atom(type), do: Evolution.DevelopmentAgent

  # ===========================================================================
  # Name Triple Generation
  # ===========================================================================

  defp build_name_triple(_agent_iri, %{name: nil}), do: []

  defp build_name_triple(agent_iri, %{agent_type: :developer, name: name}) do
    [Helpers.datatype_property(agent_iri, Evolution.developerName(), name, RDF.XSD.String)]
  end

  defp build_name_triple(agent_iri, %{agent_type: :bot, name: name}) do
    [Helpers.datatype_property(agent_iri, Evolution.botName(), name, RDF.XSD.String)]
  end

  defp build_name_triple(agent_iri, %{agent_type: :ci, name: name}) do
    # CI systems use botName as they are a subclass of Bot
    [Helpers.datatype_property(agent_iri, Evolution.botName(), name, RDF.XSD.String)]
  end

  defp build_name_triple(agent_iri, %{agent_type: :llm, name: name}) do
    # LLM agents use botName as they are a subclass of Bot
    [Helpers.datatype_property(agent_iri, Evolution.botName(), name, RDF.XSD.String)]
  end

  defp build_name_triple(agent_iri, %{name: name}) do
    # Fallback - use developerName
    [Helpers.datatype_property(agent_iri, Evolution.developerName(), name, RDF.XSD.String)]
  end

  # ===========================================================================
  # Email Triple Generation
  # ===========================================================================

  defp build_email_triple(_agent_iri, %{email: nil}), do: []

  defp build_email_triple(agent_iri, %{agent_type: :developer, email: email}) do
    [Helpers.datatype_property(agent_iri, Evolution.developerEmail(), email, RDF.XSD.String)]
  end

  # Only developers have email in the ontology schema
  defp build_email_triple(_agent_iri, _agent), do: []
end
