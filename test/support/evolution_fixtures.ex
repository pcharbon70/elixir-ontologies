defmodule ElixirOntologies.Test.EvolutionFixtures do
  @moduledoc """
  Test fixtures for evolution and provenance layer tests.

  This module provides common test data and helpers for Phase 20 tests,
  reducing duplication and ensuring consistent test data across test files.

  ## Usage

      import ElixirOntologies.Test.EvolutionFixtures

      test "works with sample commit" do
        commit = sample_commit()
        assert commit.sha != nil
      end

      test "builds context" do
        context = sample_context()
        assert context.base_iri != nil
      end
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel
  alias ElixirOntologies.Extractors.Evolution.Agent
  alias ElixirOntologies.Builders.Context

  # ===========================================================================
  # Commit Fixtures
  # ===========================================================================

  @doc """
  Creates a sample commit for testing.

  ## Options

  - `:sha` - Override the SHA (default: random 40-char hex)
  - `:message` - Override the message (default: "Test commit")
  - `:author_email` - Override author email
  - `:is_merge` - Set merge commit flag

  ## Examples

      commit = sample_commit()
      commit = sample_commit(message: "feat: add feature")
      commit = sample_commit(is_merge: true, parents: ["abc123", "def456"])
  """
  def sample_commit(opts \\ []) do
    sha = Keyword.get(opts, :sha, random_sha())
    short_sha = String.slice(sha, 0, 7)
    message = Keyword.get(opts, :message, "Test commit")

    %Commit{
      sha: sha,
      short_sha: short_sha,
      message: message,
      subject: message,
      body: Keyword.get(opts, :body),
      author_name: Keyword.get(opts, :author_name, "Test Author"),
      author_email: Keyword.get(opts, :author_email, "test@example.com"),
      author_date: Keyword.get(opts, :author_date),
      committer_name: Keyword.get(opts, :committer_name, "Test Committer"),
      committer_email: Keyword.get(opts, :committer_email, "test@example.com"),
      commit_date: Keyword.get(opts, :commit_date),
      parents: Keyword.get(opts, :parents, []),
      is_merge: Keyword.get(opts, :is_merge, false),
      tree_sha: Keyword.get(opts, :tree_sha),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a sample merge commit for testing.
  """
  def sample_merge_commit(opts \\ []) do
    parents = Keyword.get(opts, :parents, [random_sha(), random_sha()])
    message = Keyword.get(opts, :message, "Merge branch 'feature' into main")

    sample_commit(
      Keyword.merge(opts,
        message: message,
        is_merge: true,
        parents: parents
      )
    )
  end

  @doc """
  Creates a sample feature commit.
  """
  def sample_feature_commit(opts \\ []) do
    message = Keyword.get(opts, :message, "feat: add new feature")
    sample_commit(Keyword.put(opts, :message, message))
  end

  @doc """
  Creates a sample bugfix commit.
  """
  def sample_bugfix_commit(opts \\ []) do
    message = Keyword.get(opts, :message, "fix: resolve issue with user login")
    sample_commit(Keyword.put(opts, :message, message))
  end

  # ===========================================================================
  # Activity Fixtures
  # ===========================================================================

  @doc """
  Creates a sample activity for testing.

  ## Options

  - `:activity_type` - Type of activity (default: :feature)
  - `:commit_sha` - SHA of associated commit
  """
  def sample_activity(opts \\ []) do
    sha = Keyword.get(opts, :commit_sha, random_sha())
    short_sha = String.slice(sha, 0, 7)

    %ActivityModel{
      activity_id: "activity:#{short_sha}",
      activity_type: Keyword.get(opts, :activity_type, :feature),
      commit_sha: sha,
      short_sha: short_sha,
      started_at: Keyword.get(opts, :started_at),
      ended_at: Keyword.get(opts, :ended_at),
      used_entities: Keyword.get(opts, :used_entities, []),
      generated_entities: Keyword.get(opts, :generated_entities, []),
      informed_by: Keyword.get(opts, :informed_by, []),
      associated_agents: Keyword.get(opts, :associated_agents, [])
    }
  end

  # ===========================================================================
  # Agent Fixtures
  # ===========================================================================

  @doc """
  Creates a sample agent for testing.

  ## Options

  - `:email` - Agent email (default: "developer@example.com")
  - `:agent_type` - Type of agent (default: :developer)
  """
  def sample_agent(opts \\ []) do
    email = Keyword.get(opts, :email, "developer@example.com")
    agent_id = Agent.build_agent_id(email)

    %Agent{
      agent_id: agent_id,
      agent_type: Keyword.get(opts, :agent_type, :developer),
      name: Keyword.get(opts, :name, "Test Developer"),
      email: email,
      identity: email,
      associated_activities: Keyword.get(opts, :associated_activities, []),
      attributed_entities: Keyword.get(opts, :attributed_entities, []),
      first_seen: Keyword.get(opts, :first_seen),
      last_seen: Keyword.get(opts, :last_seen),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a sample bot agent.
  """
  def sample_bot_agent(opts \\ []) do
    email = Keyword.get(opts, :email, "dependabot[bot]@users.noreply.github.com")
    sample_agent(Keyword.merge(opts, email: email, agent_type: :bot, name: "dependabot"))
  end

  # ===========================================================================
  # Context Fixtures
  # ===========================================================================

  @doc """
  Creates a sample builder context.

  ## Options

  - `:base_iri` - Base IRI (default: "https://example.org/code#")
  - `:repo_iri` - Optional repository IRI
  """
  def sample_context(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")

    metadata =
      case Keyword.get(opts, :repo_iri) do
        nil -> %{}
        repo_iri -> %{repo_iri: repo_iri}
      end

    Context.new(base_iri: base_iri, metadata: metadata)
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc """
  Generates a random 40-character SHA for testing.
  """
  def random_sha do
    :crypto.strong_rand_bytes(20)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a sample email address.
  """
  def random_email do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "user#{suffix}@example.com"
  end

  @doc """
  Generates sample DateTime for testing.
  """
  def sample_datetime(opts \\ []) do
    days_ago = Keyword.get(opts, :days_ago, 0)

    DateTime.utc_now()
    |> DateTime.add(-days_ago * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end
end
