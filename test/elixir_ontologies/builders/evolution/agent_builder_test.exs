defmodule ElixirOntologies.Builders.Evolution.AgentBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.Evolution.AgentBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Evolution.Agent
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_agent(opts \\ []) do
    defaults = %{
      agent_id: "agent:abc123",
      agent_type: :developer,
      name: "Jane Doe",
      email: "jane@example.com",
      identity: "jane@example.com",
      associated_activities: [],
      attributed_entities: [],
      first_seen: nil,
      last_seen: nil,
      metadata: %{}
    }

    struct(Agent, Map.merge(defaults, Map.new(opts)))
  end

  defp create_context(opts \\ []) do
    defaults = [base_iri: "https://example.org/code#"]
    Context.new(Keyword.merge(defaults, opts))
  end

  defp find_triple(triples, predicate) do
    Enum.find(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp find_triples(triples, predicate) do
    Enum.filter(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp get_object(triples, predicate) do
    case find_triple(triples, predicate) do
      {_s, _p, o} -> o
      nil -> nil
    end
  end

  # ===========================================================================
  # Basic Build Tests
  # ===========================================================================

  describe "build/2" do
    test "returns agent IRI and triples" do
      agent = create_agent()
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      assert %RDF.IRI{} = agent_iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates stable IRI from agent_id" do
      agent = create_agent(agent_id: "agent:def456xyz")
      context = create_context()

      {agent_iri, _triples} = AgentBuilder.build(agent, context)

      assert to_string(agent_iri) == "https://example.org/code#agent/def456xyz"
    end

    test "same agent produces same IRI" do
      agent = create_agent()
      context = create_context()

      {iri1, _} = AgentBuilder.build(agent, context)
      {iri2, _} = AgentBuilder.build(agent, context)

      assert iri1 == iri2
    end

    test "handles agent_id without prefix" do
      agent = create_agent(agent_id: "xyz789")
      context = create_context()

      {agent_iri, _triples} = AgentBuilder.build(agent, context)

      assert to_string(agent_iri) == "https://example.org/code#agent/xyz789"
    end
  end

  # ===========================================================================
  # Type Triple Tests
  # ===========================================================================

  describe "type triples" do
    test "generates prov:Agent type for developer" do
      agent = create_agent(agent_type: :developer)
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      type_triples = find_triples(triples, RDF.type())
      assert length(type_triples) == 2

      types = Enum.map(type_triples, fn {^agent_iri, _, o} -> o end)
      assert PROV.Agent in types
      assert RDF.iri(Evolution.Developer) in types
    end

    test "generates Bot type for bot agent" do
      agent = create_agent(agent_type: :bot, name: "dependabot[bot]")
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      type_triples = find_triples(triples, RDF.type())
      types = Enum.map(type_triples, fn {^agent_iri, _, o} -> o end)

      assert PROV.Agent in types
      assert RDF.iri(Evolution.Bot) in types
    end

    test "generates CISystem type for ci agent" do
      agent = create_agent(agent_type: :ci, name: "github-actions[bot]")
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      type_triples = find_triples(triples, RDF.type())
      types = Enum.map(type_triples, fn {^agent_iri, _, o} -> o end)

      assert PROV.Agent in types
      assert RDF.iri(Evolution.CISystem) in types
    end

    test "generates LLMAgent type for llm agent" do
      agent = create_agent(agent_type: :llm, name: "copilot")
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      type_triples = find_triples(triples, RDF.type())
      types = Enum.map(type_triples, fn {^agent_iri, _, o} -> o end)

      assert PROV.Agent in types
      assert RDF.iri(Evolution.LLMAgent) in types
    end

    test "generates DevelopmentAgent for unknown type" do
      agent = create_agent(agent_type: :unknown)
      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      type_triples = find_triples(triples, RDF.type())
      types = Enum.map(type_triples, fn {^agent_iri, _, o} -> o end)

      assert PROV.Agent in types
      assert RDF.iri(Evolution.DevelopmentAgent) in types
    end
  end

  # ===========================================================================
  # agent_type_to_class Tests
  # ===========================================================================

  describe "agent_type_to_class/1" do
    test "maps :developer to Evolution.Developer" do
      assert AgentBuilder.agent_type_to_class(:developer) == RDF.iri(Evolution.Developer)
    end

    test "maps :bot to Evolution.Bot" do
      assert AgentBuilder.agent_type_to_class(:bot) == RDF.iri(Evolution.Bot)
    end

    test "maps :ci to Evolution.CISystem" do
      assert AgentBuilder.agent_type_to_class(:ci) == RDF.iri(Evolution.CISystem)
    end

    test "maps :llm to Evolution.LLMAgent" do
      assert AgentBuilder.agent_type_to_class(:llm) == RDF.iri(Evolution.LLMAgent)
    end

    test "maps unknown types to Evolution.DevelopmentAgent" do
      assert AgentBuilder.agent_type_to_class(:unknown) == RDF.iri(Evolution.DevelopmentAgent)
      assert AgentBuilder.agent_type_to_class(:other) == RDF.iri(Evolution.DevelopmentAgent)
    end
  end

  # ===========================================================================
  # Name Triple Tests
  # ===========================================================================

  describe "name triples" do
    test "generates developerName for developer" do
      agent = create_agent(agent_type: :developer, name: "Jane Doe")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.developerName())
      assert name_value != nil
      assert RDF.Literal.value(name_value) == "Jane Doe"
    end

    test "generates botName for bot" do
      agent = create_agent(agent_type: :bot, name: "dependabot[bot]")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.botName())
      assert name_value != nil
      assert RDF.Literal.value(name_value) == "dependabot[bot]"
    end

    test "generates botName for ci agent" do
      agent = create_agent(agent_type: :ci, name: "github-actions[bot]")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.botName())
      assert name_value != nil
      assert RDF.Literal.value(name_value) == "github-actions[bot]"
    end

    test "generates botName for llm agent" do
      agent = create_agent(agent_type: :llm, name: "copilot")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.botName())
      assert name_value != nil
      assert RDF.Literal.value(name_value) == "copilot"
    end

    test "omits name triple when name is nil" do
      agent = create_agent(name: nil)
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      assert find_triple(triples, Evolution.developerName()) == nil
      assert find_triple(triples, Evolution.botName()) == nil
    end
  end

  # ===========================================================================
  # Email Triple Tests
  # ===========================================================================

  describe "email triples" do
    test "generates developerEmail for developer" do
      agent = create_agent(agent_type: :developer, email: "jane@example.com")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      email_value = get_object(triples, Evolution.developerEmail())
      assert email_value != nil
      assert RDF.Literal.value(email_value) == "jane@example.com"
    end

    test "omits email for non-developer agents" do
      agent = create_agent(agent_type: :bot, email: "bot@example.com")
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      assert find_triple(triples, Evolution.developerEmail()) == nil
    end

    test "omits email triple when email is nil" do
      agent = create_agent(email: nil)
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      assert find_triple(triples, Evolution.developerEmail()) == nil
    end
  end

  # ===========================================================================
  # Build All Tests
  # ===========================================================================

  describe "build_all/2" do
    test "builds multiple agents" do
      agents = [
        create_agent(agent_id: "agent:dev1", agent_type: :developer),
        create_agent(agent_id: "agent:bot1", agent_type: :bot)
      ]

      context = create_context()

      results = AgentBuilder.build_all(agents, context)

      assert length(results) == 2

      Enum.each(results, fn {iri, triples} ->
        assert %RDF.IRI{} = iri
        assert is_list(triples)
      end)
    end

    test "returns empty list for empty input" do
      context = create_context()
      results = AgentBuilder.build_all([], context)
      assert results == []
    end
  end

  describe "build_all_triples/2" do
    test "returns flat list of all triples" do
      agents = [
        create_agent(agent_id: "agent:dev1", agent_type: :developer),
        create_agent(agent_id: "agent:bot1", agent_type: :bot)
      ]

      context = create_context()

      triples = AgentBuilder.build_all_triples(agents, context)

      assert is_list(triples)
      # Each agent should have at least 2 type triples
      assert length(triples) >= 4
    end

    test "returns empty list for empty input" do
      context = create_context()
      triples = AgentBuilder.build_all_triples([], context)
      assert triples == []
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles minimal agent with only required fields" do
      agent = %Agent{
        agent_id: "agent:minimal",
        agent_type: :developer,
        email: "minimal@example.com"
      }

      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      assert %RDF.IRI{} = agent_iri
      # Should have at least type triples
      assert length(triples) >= 2
    end

    test "handles agent with all fields populated" do
      agent =
        create_agent(
          agent_id: "agent:full",
          agent_type: :developer,
          name: "Full Agent",
          email: "full@example.com",
          identity: "full@example.com",
          associated_activities: ["activity:1", "activity:2"],
          attributed_entities: ["entity:1", "entity:2"],
          first_seen: ~U[2025-01-01 00:00:00Z],
          last_seen: ~U[2025-01-15 00:00:00Z],
          metadata: %{github_username: "fullagent"}
        )

      context = create_context()

      {agent_iri, triples} = AgentBuilder.build(agent, context)

      assert %RDF.IRI{} = agent_iri
      # Should have type + name + email triples
      assert length(triples) >= 4
    end

    test "handles special characters in name" do
      name = "José García-López"
      agent = create_agent(name: name)
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.developerName())
      assert RDF.Literal.value(name_value) == name
    end

    test "handles unicode in email" do
      email = "开发者@example.com"
      agent = create_agent(email: email)
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      email_value = get_object(triples, Evolution.developerEmail())
      assert RDF.Literal.value(email_value) == email
    end

    test "handles bot name with special characters" do
      name = "dependabot[bot]"
      agent = create_agent(agent_type: :bot, name: name)
      context = create_context()

      {_agent_iri, triples} = AgentBuilder.build(agent, context)

      name_value = get_object(triples, Evolution.botName())
      assert RDF.Literal.value(name_value) == name
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "builds from real agent extraction" do
      alias ElixirOntologies.Extractors.Evolution.Commit

      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, agents} = Agent.extract_agents(".", commit)

      context = create_context()

      Enum.each(agents, fn agent ->
        {agent_iri, triples} = AgentBuilder.build(agent, context)

        assert %RDF.IRI{} = agent_iri
        assert length(triples) > 0

        # Verify type triples
        type_triples = find_triples(triples, RDF.type())
        assert length(type_triples) == 2
      end)
    end
  end
end
