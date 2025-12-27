defmodule ElixirOntologies.Extractors.Evolution.AgentTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Agent
  alias ElixirOntologies.Extractors.Evolution.Agent.{Association, Attribution}
  alias ElixirOntologies.Extractors.Evolution.{Commit, Developer}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts) do
    %Commit{
      sha: Keyword.get(opts, :sha, "abc123def456abc123def456abc123def456abc1"),
      short_sha: Keyword.get(opts, :short_sha, "abc123d"),
      message: Keyword.get(opts, :message),
      subject: Keyword.get(opts, :subject),
      body: Keyword.get(opts, :body),
      author_name: Keyword.get(opts, :author_name, "Test Author"),
      author_email: Keyword.get(opts, :author_email, "test@example.com"),
      author_date: Keyword.get(opts, :author_date, DateTime.utc_now()),
      committer_name: Keyword.get(opts, :committer_name, "Test Committer"),
      committer_email: Keyword.get(opts, :committer_email, "test@example.com"),
      commit_date: Keyword.get(opts, :commit_date, DateTime.utc_now()),
      parents: Keyword.get(opts, :parents, ["def456abc123def456abc123def456abc123def4"]),
      is_merge: Keyword.get(opts, :is_merge, false),
      tree_sha: Keyword.get(opts, :tree_sha),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "Agent struct" do
    test "enforces required keys" do
      agent = %Agent{
        agent_id: "agent:a1b2c3d4e5f6",
        agent_type: :developer,
        email: "test@example.com"
      }

      assert agent.agent_id == "agent:a1b2c3d4e5f6"
      assert agent.agent_type == :developer
      assert agent.email == "test@example.com"
    end

    test "has default values" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "test@example.com"
      }

      assert agent.name == nil
      assert agent.identity == nil
      assert agent.associated_activities == []
      assert agent.attributed_entities == []
      assert agent.first_seen == nil
      assert agent.last_seen == nil
      assert agent.metadata == %{}
    end
  end

  describe "Association struct" do
    test "enforces required keys" do
      assoc = %Association{
        activity_id: "activity:abc123d",
        agent_id: "agent:a1b2c3d4e5f6"
      }

      assert assoc.activity_id == "activity:abc123d"
      assert assoc.agent_id == "agent:a1b2c3d4e5f6"
    end

    test "has default values" do
      assoc = %Association{
        activity_id: "activity:abc",
        agent_id: "agent:def"
      }

      assert assoc.role == nil
      assert assoc.timestamp == nil
      assert assoc.metadata == %{}
    end
  end

  describe "Attribution struct" do
    test "enforces required keys" do
      attr = %Attribution{
        entity_id: "lib/foo.ex@abc123d",
        agent_id: "agent:a1b2c3d4e5f6"
      }

      assert attr.entity_id == "lib/foo.ex@abc123d"
      assert attr.agent_id == "agent:a1b2c3d4e5f6"
    end

    test "has default values" do
      attr = %Attribution{
        entity_id: "file@sha",
        agent_id: "agent:def"
      }

      assert attr.role == nil
      assert attr.timestamp == nil
      assert attr.metadata == %{}
    end
  end

  # ===========================================================================
  # Agent ID Tests
  # ===========================================================================

  describe "build_agent_id/1" do
    test "builds agent ID from email" do
      id = Agent.build_agent_id("user@example.com")
      assert String.starts_with?(id, "agent:")
      # "agent:" (6) + hash (12) = 18
      assert String.length(id) == 18
    end

    test "produces stable IDs for same email" do
      id1 = Agent.build_agent_id("user@example.com")
      id2 = Agent.build_agent_id("user@example.com")
      assert id1 == id2
    end

    test "produces different IDs for different emails" do
      id1 = Agent.build_agent_id("user1@example.com")
      id2 = Agent.build_agent_id("user2@example.com")
      assert id1 != id2
    end

    test "is case-insensitive" do
      id1 = Agent.build_agent_id("User@Example.com")
      id2 = Agent.build_agent_id("user@example.com")
      assert id1 == id2
    end
  end

  describe "parse_agent_id/1" do
    test "parses valid agent ID" do
      {:ok, hash} = Agent.parse_agent_id("agent:a1b2c3d4e5f6")
      assert hash == "a1b2c3d4e5f6"
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Agent.parse_agent_id("invalid")
      assert {:error, :invalid_format} = Agent.parse_agent_id("developer:abc")
    end
  end

  # ===========================================================================
  # Agent Type Detection Tests
  # ===========================================================================

  describe "detect_type/1" do
    test "detects developer emails" do
      assert Agent.detect_type("user@example.com") == :developer
      assert Agent.detect_type("developer@company.com") == :developer
      assert Agent.detect_type("john.doe@gmail.com") == :developer
    end

    test "detects dependabot" do
      assert Agent.detect_type("dependabot[bot]@users.noreply.github.com") == :bot
      assert Agent.detect_type("49699333+dependabot[bot]@users.noreply.github.com") == :bot
    end

    test "detects renovate" do
      assert Agent.detect_type("renovate[bot]@users.noreply.github.com") == :bot
      assert Agent.detect_type("29139614+renovate[bot]@users.noreply.github.com") == :bot
    end

    test "detects greenkeeper" do
      assert Agent.detect_type("greenkeeper[bot]@users.noreply.github.com") == :bot
    end

    test "detects snyk-bot" do
      assert Agent.detect_type("snyk-bot@snyk.io") == :bot
    end

    test "detects semantic-release-bot" do
      assert Agent.detect_type("semantic-release-bot@martynus.net") == :bot
    end

    test "detects generic bot pattern" do
      assert Agent.detect_type("my-custom[bot]@example.com") == :bot
    end

    test "detects github actions" do
      assert Agent.detect_type("action@github.com") == :ci
      assert Agent.detect_type("41898282+github-actions[bot]@users.noreply.github.com") == :bot
    end

    test "detects github noreply" do
      assert Agent.detect_type("noreply@github.com") == :ci
    end

    test "detects gitlab CI" do
      assert Agent.detect_type("gitlab-ci@example.com") == :ci
    end

    test "detects jenkins" do
      assert Agent.detect_type("jenkins@example.com") == :ci
    end

    test "detects travis" do
      assert Agent.detect_type("travis@travis-ci.org") == :ci
    end

    test "detects circleci" do
      assert Agent.detect_type("circleci@example.com") == :ci
    end

    test "detects copilot" do
      assert Agent.detect_type("copilot@github.com") == :llm
      assert Agent.detect_type("github-copilot@users.noreply.github.com") == :llm
    end

    test "detects cursor" do
      assert Agent.detect_type("cursor@cursor.sh") == :llm
    end
  end

  describe "detect_type_with_context/2" do
    test "detects LLM from co-author trailer" do
      message = "Fix bug\n\nCo-authored-by: github-copilot"
      assert Agent.detect_type_with_context("user@example.com", message) == :llm
    end

    test "detects LLM from claude co-author" do
      message = "Add feature\n\nCo-authored-by: claude <claude@anthropic.com>"
      assert Agent.detect_type_with_context("user@example.com", message) == :llm
    end

    test "detects AI-assisted pattern" do
      message = "AI-assisted code refactoring"
      assert Agent.detect_type_with_context("user@example.com", message) == :llm
    end

    test "returns developer for normal commits" do
      message = "Fix bug in user authentication"
      assert Agent.detect_type_with_context("user@example.com", message) == :developer
    end

    test "handles nil message" do
      assert Agent.detect_type_with_context("user@example.com", nil) == :developer
    end

    test "bot type takes precedence over message" do
      message = "Co-authored-by: github-copilot"

      assert Agent.detect_type_with_context("dependabot[bot]@users.noreply.github.com", message) ==
               :bot
    end
  end

  describe "automated?/1" do
    test "developer is not automated" do
      refute Agent.automated?(:developer)
    end

    test "bot is automated" do
      assert Agent.automated?(:bot)
    end

    test "ci is automated" do
      assert Agent.automated?(:ci)
    end

    test "llm is automated" do
      assert Agent.automated?(:llm)
    end
  end

  describe "type predicates" do
    test "bot?/1" do
      agent = %Agent{agent_id: "agent:abc", agent_type: :bot, email: "bot@example.com"}
      assert Agent.bot?(agent)

      refute Agent.bot?(%Agent{
               agent_id: "agent:abc",
               agent_type: :developer,
               email: "dev@example.com"
             })
    end

    test "ci?/1" do
      agent = %Agent{agent_id: "agent:abc", agent_type: :ci, email: "ci@example.com"}
      assert Agent.ci?(agent)

      refute Agent.ci?(%Agent{
               agent_id: "agent:abc",
               agent_type: :developer,
               email: "dev@example.com"
             })
    end

    test "llm?/1" do
      agent = %Agent{agent_id: "agent:abc", agent_type: :llm, email: "llm@example.com"}
      assert Agent.llm?(agent)

      refute Agent.llm?(%Agent{
               agent_id: "agent:abc",
               agent_type: :developer,
               email: "dev@example.com"
             })
    end

    test "developer?/1" do
      agent = %Agent{agent_id: "agent:abc", agent_type: :developer, email: "dev@example.com"}
      assert Agent.developer?(agent)

      refute Agent.developer?(%Agent{
               agent_id: "agent:abc",
               agent_type: :bot,
               email: "bot@example.com"
             })
    end
  end

  # ===========================================================================
  # Agent Extraction Tests
  # ===========================================================================

  describe "extract_agents/3" do
    @tag :integration
    test "extracts agents from commit at HEAD" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, agents} = Agent.extract_agents(".", commit)

      assert is_list(agents)
      assert length(agents) >= 1

      Enum.each(agents, fn agent ->
        assert %Agent{} = agent
        assert String.starts_with?(agent.agent_id, "agent:")
        assert agent.agent_type in [:developer, :bot, :ci, :llm]
      end)
    end

    test "extracts single agent when author equals committer" do
      commit =
        create_commit(
          author_email: "same@example.com",
          committer_email: "same@example.com"
        )

      {:ok, agents} = Agent.extract_agents(".", commit)

      assert length(agents) == 1
      [agent] = agents
      assert agent.email == "same@example.com"
    end

    test "extracts two agents when author differs from committer" do
      commit =
        create_commit(
          author_email: "author@example.com",
          committer_email: "committer@example.com"
        )

      {:ok, agents} = Agent.extract_agents(".", commit)

      assert length(agents) == 2

      emails = Enum.map(agents, & &1.email) |> Enum.sort()
      assert emails == ["author@example.com", "committer@example.com"]
    end

    test "detects bot agent" do
      commit =
        create_commit(
          author_email: "dependabot[bot]@users.noreply.github.com",
          committer_email: "dependabot[bot]@users.noreply.github.com"
        )

      {:ok, agents} = Agent.extract_agents(".", commit)

      [agent] = agents
      assert agent.agent_type == :bot
    end

    test "detects LLM from commit message" do
      commit =
        create_commit(
          author_email: "user@example.com",
          message: "Fix bug\n\nCo-authored-by: github-copilot"
        )

      {:ok, agents} = Agent.extract_agents(".", commit)

      [agent | _] = agents
      assert agent.agent_type == :llm
    end

    test "can disable LLM detection" do
      commit =
        create_commit(
          author_email: "user@example.com",
          message: "Fix bug\n\nCo-authored-by: github-copilot"
        )

      {:ok, agents} = Agent.extract_agents(".", commit, detect_llm: false)

      [agent | _] = agents
      assert agent.agent_type == :developer
    end
  end

  describe "extract_agents!/3" do
    @tag :integration
    test "returns agents on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      agents = Agent.extract_agents!(".", commit)

      assert is_list(agents)
    end
  end

  describe "extract_agents_from_commits/3" do
    @tag :integration
    test "extracts agents from multiple commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      {:ok, agents} = Agent.extract_agents_from_commits(".", commits)

      assert is_list(agents)
      # Agents are aggregated by email
      assert length(agents) >= 1
    end

    @tag :integration
    test "aggregates activities for same agent" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      {:ok, agents} = Agent.extract_agents_from_commits(".", commits)

      # At least one agent should have multiple activities
      if length(commits) > 1 do
        assert Enum.any?(agents, fn agent ->
                 length(agent.associated_activities) > 1
               end)
      end
    end
  end

  describe "from_developer/1" do
    test "converts Developer to Agent" do
      dev = %Developer{
        email: "user@example.com",
        name: "User Name",
        authored_commits: ["abc123d", "def456e"],
        committed_commits: ["abc123d"],
        first_authored: ~U[2024-01-01 10:00:00Z],
        last_authored: ~U[2024-01-15 10:00:00Z]
      }

      agent = Agent.from_developer(dev)

      assert String.starts_with?(agent.agent_id, "agent:")
      assert agent.agent_type == :developer
      assert agent.name == "User Name"
      assert agent.email == "user@example.com"
      # Unique commits
      assert length(agent.associated_activities) == 2
    end

    test "detects bot from developer" do
      dev = %Developer{
        email: "dependabot[bot]@users.noreply.github.com",
        name: "dependabot[bot]",
        authored_commits: ["abc123d"]
      }

      agent = Agent.from_developer(dev)

      assert agent.agent_type == :bot
    end
  end

  # ===========================================================================
  # Association Tests (wasAssociatedWith)
  # ===========================================================================

  describe "extract_associations/3" do
    @tag :integration
    test "extracts associations from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, associations} = Agent.extract_associations(".", commit)

      assert is_list(associations)
      assert length(associations) >= 1

      Enum.each(associations, fn assoc ->
        assert %Association{} = assoc
        assert String.starts_with?(assoc.activity_id, "activity:")
        assert String.starts_with?(assoc.agent_id, "agent:")
        assert assoc.role in [:author, :committer]
      end)
    end

    test "creates association for author" do
      commit =
        create_commit(
          author_email: "author@example.com",
          committer_email: "author@example.com"
        )

      {:ok, associations} = Agent.extract_associations(".", commit)

      author_assoc = Enum.find(associations, &(&1.role == :author))
      assert author_assoc != nil
      assert author_assoc.activity_id == "activity:abc123d"
    end

    test "creates association for committer" do
      commit =
        create_commit(
          author_email: "author@example.com",
          committer_email: "committer@example.com"
        )

      {:ok, associations} = Agent.extract_associations(".", commit)

      committer_assoc = Enum.find(associations, &(&1.role == :committer))
      assert committer_assoc != nil
    end

    test "includes timestamps" do
      now = DateTime.utc_now()

      commit =
        create_commit(
          author_date: now,
          commit_date: now
        )

      {:ok, associations} = Agent.extract_associations(".", commit)

      Enum.each(associations, fn assoc ->
        assert assoc.timestamp != nil
      end)
    end
  end

  describe "extract_associations!/3" do
    @tag :integration
    test "returns associations on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      associations = Agent.extract_associations!(".", commit)

      assert is_list(associations)
    end
  end

  # ===========================================================================
  # Attribution Tests (wasAttributedTo)
  # ===========================================================================

  describe "extract_attributions/3" do
    @tag :integration
    test "extracts attributions from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, attributions} = Agent.extract_attributions(".", commit)

      assert is_list(attributions)

      Enum.each(attributions, fn attr ->
        assert %Attribution{} = attr
        assert String.starts_with?(attr.agent_id, "agent:")
        assert is_binary(attr.entity_id)
      end)
    end

    test "creates attribution with author role by default" do
      commit = create_commit(author_email: "author@example.com")

      # Note: This depends on AM.extract_generations which may return empty
      # for synthetic commits. Integration tests verify with real commits.
      {:ok, attributions} = Agent.extract_attributions(".", commit)

      if length(attributions) > 0 do
        assert Enum.all?(attributions, &(&1.role == :author))
      end
    end
  end

  describe "extract_attributions!/3" do
    @tag :integration
    test "returns attributions on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      attributions = Agent.extract_attributions!(".", commit)

      assert is_list(attributions)
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "associated_with?/2" do
    test "returns true when agent is associated with activity" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        associated_activities: ["activity:abc123d", "activity:def456e"]
      }

      assert Agent.associated_with?(agent, "activity:abc123d")
      assert Agent.associated_with?(agent, "activity:def456e")
    end

    test "returns false when agent is not associated" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        associated_activities: []
      }

      refute Agent.associated_with?(agent, "activity:xyz")
    end
  end

  describe "attributed_to?/2" do
    test "returns true when agent is attributed to entity" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        attributed_entities: ["lib/foo.ex@abc123d"]
      }

      assert Agent.attributed_to?(agent, "lib/foo.ex@abc123d")
    end

    test "returns false when agent is not attributed" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        attributed_entities: []
      }

      refute Agent.attributed_to?(agent, "lib/bar.ex@def456e")
    end
  end

  describe "activity_count/1" do
    test "returns count of associated activities" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        associated_activities: ["a", "b", "c"]
      }

      assert Agent.activity_count(agent) == 3
    end
  end

  describe "entity_count/1" do
    test "returns count of attributed entities" do
      agent = %Agent{
        agent_id: "agent:abc",
        agent_type: :developer,
        email: "dev@example.com",
        attributed_entities: ["e1", "e2"]
      }

      assert Agent.entity_count(agent) == 2
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "full workflow integration" do
    @tag :integration
    test "can extract complete agent model from commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      {:ok, agents} = Agent.extract_agents_from_commits(".", commits)

      # Verify agents have proper structure
      Enum.each(agents, fn agent ->
        assert agent.agent_id != nil
        assert agent.agent_type != nil
        assert agent.email != nil
        assert is_list(agent.associated_activities)
      end)
    end

    @tag :integration
    test "agents and associations are consistent" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, agents} = Agent.extract_agents(".", commit)
      {:ok, associations} = Agent.extract_associations(".", commit)

      # Each association's agent_id should match an extracted agent
      agent_ids = MapSet.new(Enum.map(agents, & &1.agent_id))

      Enum.each(associations, fn assoc ->
        assert assoc.agent_id in agent_ids
      end)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles commit with missing author email" do
      commit = create_commit(author_email: nil)
      {:ok, agents} = Agent.extract_agents(".", commit)

      # Should still extract with fallback email
      assert length(agents) >= 1
    end

    test "handles commit with missing committer email" do
      commit = create_commit(committer_email: nil)
      {:ok, agents} = Agent.extract_agents(".", commit)

      # Should still extract with fallback email
      assert length(agents) >= 1
    end
  end
end
