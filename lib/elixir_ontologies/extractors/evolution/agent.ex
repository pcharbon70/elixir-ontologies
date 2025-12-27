defmodule ElixirOntologies.Extractors.Evolution.Agent do
  @moduledoc """
  Models PROV-O agents for development activities.

  This module represents developers, bots, CI systems, and LLM tools as PROV-O
  agents. It supports agent type detection, activity associations, and entity
  attributions following the W3C PROV-O ontology.

  ## Agent Types

  - `:developer` - Human developer
  - `:bot` - Automated dependency bots (dependabot, renovate, greenkeeper)
  - `:ci` - CI/CD systems (GitHub Actions, GitLab CI)
  - `:llm` - LLM-assisted commits (copilot, claude, cursor)

  ## PROV-O Alignment

  - `prov:Agent` - Represented by the `Agent` struct
  - `prov:wasAssociatedWith` - Tracked via `Association` struct
  - `prov:wasAttributedTo` - Tracked via `Attribution` struct

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}

      # Extract agent from a commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, agents} = Agent.extract_agents(".", commit)

      # Detect agent type
      type = Agent.detect_type("dependabot[bot]@users.noreply.github.com")
      # => :bot

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.detect_type("user@example.com")
      :developer
  """

  alias ElixirOntologies.Extractors.Evolution.{Commit, Developer}
  alias ElixirOntologies.Extractors.Evolution.ActivityModel, as: AM
  alias ElixirOntologies.Utils.IdGenerator

  # ===========================================================================
  # Agent Struct
  # ===========================================================================

  @typedoc """
  Represents a PROV-O agent.

  ## Fields

  - `:agent_id` - Unique identifier (agent:{hash})
  - `:agent_type` - Type of agent (:developer, :bot, :ci, :llm)
  - `:name` - Display name
  - `:email` - Email address (primary identifier)
  - `:identity` - Canonical identity string
  - `:associated_activities` - Activity IDs (wasAssociatedWith)
  - `:attributed_entities` - Entity IDs (wasAttributedTo)
  - `:first_seen` - Earliest activity timestamp
  - `:last_seen` - Most recent activity timestamp
  - `:metadata` - Additional metadata
  """
  @type agent_type :: :developer | :bot | :ci | :llm

  @type t :: %__MODULE__{
          agent_id: String.t(),
          agent_type: agent_type(),
          name: String.t() | nil,
          email: String.t(),
          identity: String.t(),
          associated_activities: [String.t()],
          attributed_entities: [String.t()],
          first_seen: DateTime.t() | nil,
          last_seen: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys [:agent_id, :agent_type, :email]
  defstruct [
    :agent_id,
    :agent_type,
    :name,
    :email,
    :identity,
    :first_seen,
    :last_seen,
    associated_activities: [],
    attributed_entities: [],
    metadata: %{}
  ]

  # ===========================================================================
  # Association Struct (wasAssociatedWith)
  # ===========================================================================

  defmodule Association do
    @moduledoc """
    Represents a prov:wasAssociatedWith relationship.

    Links an activity to an agent with an optional role.
    """

    @type t :: %__MODULE__{
            activity_id: String.t(),
            agent_id: String.t(),
            role: atom() | nil,
            timestamp: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [:activity_id, :agent_id]
    defstruct [
      :activity_id,
      :agent_id,
      :role,
      :timestamp,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Attribution Struct (wasAttributedTo)
  # ===========================================================================

  defmodule Attribution do
    @moduledoc """
    Represents a prov:wasAttributedTo relationship.

    Links an entity to an agent that created or modified it.
    """

    @type t :: %__MODULE__{
            entity_id: String.t(),
            agent_id: String.t(),
            role: atom() | nil,
            timestamp: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [:entity_id, :agent_id]
    defstruct [
      :entity_id,
      :agent_id,
      :role,
      :timestamp,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Agent ID Functions
  # ===========================================================================

  @doc """
  Builds an agent ID from an email address.

  Uses SHA256 hash of the email for privacy-preserving stable IDs.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> id = Agent.build_agent_id("user@example.com")
      iex> String.starts_with?(id, "agent:")
      true
  """
  @spec build_agent_id(String.t()) :: String.t()
  def build_agent_id(email) when is_binary(email) do
    "agent:#{IdGenerator.agent_id(email)}"
  end

  @doc """
  Parses an agent ID to extract the hash.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.parse_agent_id("agent:a1b2c3d4e5f6")
      {:ok, "a1b2c3d4e5f6"}

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.parse_agent_id("invalid")
      {:error, :invalid_format}
  """
  @spec parse_agent_id(String.t()) :: {:ok, String.t()} | {:error, :invalid_format}
  def parse_agent_id("agent:" <> hash), do: {:ok, hash}
  def parse_agent_id(_), do: {:error, :invalid_format}

  # ===========================================================================
  # Agent Type Detection
  # ===========================================================================

  # Bot email patterns
  @bot_patterns [
    ~r/\[bot\]@/i,
    ~r/dependabot/i,
    ~r/renovate/i,
    ~r/greenkeeper/i,
    ~r/snyk-bot/i,
    ~r/semantic-release-bot/i,
    ~r/release-bot/i,
    ~r/mergify/i,
    ~r/codecov/i,
    ~r/coveralls/i,
    ~r/bors\[bot\]/i,
    ~r/allcontributors/i
  ]

  # CI email patterns
  @ci_patterns [
    ~r/action@github\.com/i,
    ~r/noreply@github\.com/i,
    ~r/gitlab-ci@/i,
    ~r/jenkins@/i,
    ~r/travis@/i,
    ~r/circleci@/i,
    ~r/azure-pipelines/i,
    ~r/bitbucket-pipelines/i
  ]

  # LLM email patterns
  @llm_patterns [
    ~r/copilot/i,
    ~r/github-copilot/i,
    ~r/cursor/i,
    ~r/codeium/i,
    ~r/tabnine/i
  ]

  # LLM commit message patterns (for co-authored detection)
  @llm_message_patterns [
    ~r/Co-authored-by:.*copilot/i,
    ~r/Co-authored-by:.*cursor/i,
    ~r/Co-authored-by:.*claude/i,
    ~r/Co-authored-by:.*anthropic/i,
    ~r/Generated by.*AI/i,
    ~r/AI-assisted/i
  ]

  @doc """
  Detects the agent type from an email address.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.detect_type("user@example.com")
      :developer

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.detect_type("dependabot[bot]@users.noreply.github.com")
      :bot

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.detect_type("action@github.com")
      :ci
  """
  @spec detect_type(String.t()) :: agent_type()
  def detect_type(email) when is_binary(email) do
    cond do
      matches_any?(email, @bot_patterns) -> :bot
      matches_any?(email, @ci_patterns) -> :ci
      matches_any?(email, @llm_patterns) -> :llm
      true -> :developer
    end
  end

  @doc """
  Detects agent type with additional context from commit message.

  This can detect LLM-assisted commits via co-author trailers.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.detect_type_with_context("user@example.com", "Fix bug\\n\\nCo-authored-by: github-copilot")
      :llm
  """
  @spec detect_type_with_context(String.t(), String.t() | nil) :: agent_type()
  def detect_type_with_context(email, message) when is_binary(email) do
    base_type = detect_type(email)

    if base_type == :developer and is_binary(message) do
      if matches_any?(message, @llm_message_patterns) do
        :llm
      else
        :developer
      end
    else
      base_type
    end
  end

  @doc """
  Checks if an agent type is automated (not a human developer).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.automated?(:bot)
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> Agent.automated?(:developer)
      false
  """
  @spec automated?(agent_type()) :: boolean()
  def automated?(:developer), do: false
  def automated?(_), do: true

  @doc """
  Checks if an agent is a bot.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :bot, email: "bot@example.com"}
      iex> Agent.bot?(agent)
      true
  """
  @spec bot?(t()) :: boolean()
  def bot?(%__MODULE__{agent_type: :bot}), do: true
  def bot?(_), do: false

  @doc """
  Checks if an agent is a CI system.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :ci, email: "ci@example.com"}
      iex> Agent.ci?(agent)
      true
  """
  @spec ci?(t()) :: boolean()
  def ci?(%__MODULE__{agent_type: :ci}), do: true
  def ci?(_), do: false

  @doc """
  Checks if an agent is an LLM tool.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :llm, email: "llm@example.com"}
      iex> Agent.llm?(agent)
      true
  """
  @spec llm?(t()) :: boolean()
  def llm?(%__MODULE__{agent_type: :llm}), do: true
  def llm?(_), do: false

  @doc """
  Checks if an agent is a developer.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :developer, email: "dev@example.com"}
      iex> Agent.developer?(agent)
      true
  """
  @spec developer?(t()) :: boolean()
  def developer?(%__MODULE__{agent_type: :developer}), do: true
  def developer?(_), do: false

  # ===========================================================================
  # Agent Extraction
  # ===========================================================================

  @doc """
  Extracts agents from a commit.

  Returns separate agents for author and committer if different.

  ## Options

  - `:detect_llm` - Detect LLM from commit message (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, agents} = Agent.extract_agents(".", commit)
      iex> is_list(agents)
      true
  """
  @spec extract_agents(String.t(), Commit.t(), keyword()) ::
          {:ok, [t()]} | {:error, atom()}
  def extract_agents(_repo_path, %Commit{} = commit, opts \\ []) do
    detect_llm = Keyword.get(opts, :detect_llm, true)

    author = build_agent_from_commit(commit, :author, detect_llm)
    committer = build_agent_from_commit(commit, :committer, detect_llm)

    agents =
      if author.agent_id == committer.agent_id do
        [merge_agents(author, committer)]
      else
        [author, committer]
      end

    {:ok, agents}
  end

  @doc """
  Extracts agents from a commit. Raises on error.
  """
  @spec extract_agents!(String.t(), Commit.t(), keyword()) :: [t()]
  def extract_agents!(repo_path, commit, opts \\ []) do
    {:ok, agents} = extract_agents(repo_path, commit, opts)
    agents
  end

  @doc """
  Extracts agents from multiple commits.

  Aggregates agents by email, merging their activity lists.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}
      iex> {:ok, commits} = Commit.extract_commits(".", limit: 3)
      iex> {:ok, agents} = Agent.extract_agents_from_commits(".", commits)
      iex> is_list(agents)
      true
  """
  @spec extract_agents_from_commits(String.t(), [Commit.t()], keyword()) ::
          {:ok, [t()]} | {:error, atom()}
  def extract_agents_from_commits(repo_path, commits, opts \\ []) when is_list(commits) do
    all_agents =
      commits
      |> Enum.flat_map(fn commit ->
        {:ok, agents} = extract_agents(repo_path, commit, opts)
        agents
      end)
      |> aggregate_agents()

    {:ok, all_agents}
  end

  @doc """
  Builds an agent from a Developer record.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Agent, Developer}
      iex> dev = %Developer{email: "user@example.com", name: "User", authored_commits: ["abc"]}
      iex> agent = Agent.from_developer(dev)
      iex> agent.agent_type
      :developer
  """
  @spec from_developer(Developer.t()) :: t()
  def from_developer(%Developer{} = dev) do
    agent_id = build_agent_id(dev.email)
    agent_type = detect_type(dev.email)

    activities =
      (dev.authored_commits ++ dev.committed_commits)
      |> Enum.uniq()
      |> Enum.map(&AM.build_activity_id(String.slice(&1, 0, 7)))

    %__MODULE__{
      agent_id: agent_id,
      agent_type: agent_type,
      name: dev.name,
      email: dev.email,
      identity: dev.email,
      associated_activities: activities,
      attributed_entities: [],
      first_seen: dev.first_authored || dev.first_committed,
      last_seen: dev.last_authored || dev.last_committed,
      metadata: dev.metadata
    }
  end

  # ===========================================================================
  # Association Extraction (wasAssociatedWith)
  # ===========================================================================

  @doc """
  Extracts associations between a commit activity and its agents.

  Creates associations for both author (if present) and committer.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, associations} = Agent.extract_associations(".", commit)
      iex> is_list(associations)
      true
  """
  @spec extract_associations(String.t(), Commit.t(), keyword()) ::
          {:ok, [Association.t()]} | {:error, atom()}
  def extract_associations(_repo_path, %Commit{} = commit, _opts \\ []) do
    activity_id = AM.build_activity_id(commit.short_sha)

    associations = []

    # Author association
    associations =
      if commit.author_email do
        author_agent_id = build_agent_id(commit.author_email)

        [
          %Association{
            activity_id: activity_id,
            agent_id: author_agent_id,
            role: :author,
            timestamp: commit.author_date,
            metadata: %{}
          }
          | associations
        ]
      else
        associations
      end

    # Committer association
    associations =
      if commit.committer_email do
        committer_agent_id = build_agent_id(commit.committer_email)

        [
          %Association{
            activity_id: activity_id,
            agent_id: committer_agent_id,
            role: :committer,
            timestamp: commit.commit_date,
            metadata: %{}
          }
          | associations
        ]
      else
        associations
      end

    {:ok, Enum.reverse(associations)}
  end

  @doc """
  Extracts associations. Raises on error.
  """
  @spec extract_associations!(String.t(), Commit.t(), keyword()) :: [Association.t()]
  def extract_associations!(repo_path, commit, opts \\ []) do
    {:ok, associations} = extract_associations(repo_path, commit, opts)
    associations
  end

  # ===========================================================================
  # Attribution Extraction (wasAttributedTo)
  # ===========================================================================

  @doc """
  Extracts attributions for entities generated by a commit.

  Links generated entity versions to the commit's author.

  ## Options

  - `:include_committer` - Also attribute to committer (default: false)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Agent, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, attributions} = Agent.extract_attributions(".", commit)
      iex> is_list(attributions)
      true
  """
  @spec extract_attributions(String.t(), Commit.t(), keyword()) ::
          {:ok, [Attribution.t()]} | {:error, atom()}
  def extract_attributions(repo_path, %Commit{} = commit, opts \\ []) do
    include_committer = Keyword.get(opts, :include_committer, false)

    # Get generated entities from the activity model
    case AM.extract_generations(repo_path, commit) do
      {:ok, generations} ->
        attributions =
          generations
          |> Enum.flat_map(fn gen ->
            build_attributions_for_entity(gen.entity_id, commit, include_committer)
          end)

        {:ok, attributions}

      {:error, _reason} ->
        # If no generations found, return empty list
        {:ok, []}
    end
  end

  @doc """
  Extracts attributions. Raises on error.
  """
  @spec extract_attributions!(String.t(), Commit.t(), keyword()) :: [Attribution.t()]
  def extract_attributions!(repo_path, commit, opts \\ []) do
    {:ok, attributions} = extract_attributions(repo_path, commit, opts)
    attributions
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Checks if an agent was associated with an activity.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :developer, email: "dev@example.com", associated_activities: ["activity:def"]}
      iex> Agent.associated_with?(agent, "activity:def")
      true
  """
  @spec associated_with?(t(), String.t()) :: boolean()
  def associated_with?(%__MODULE__{associated_activities: activities}, activity_id) do
    activity_id in activities
  end

  @doc """
  Checks if an agent is attributed to an entity.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Agent
      iex> agent = %Agent{agent_id: "agent:abc", agent_type: :developer, email: "dev@example.com", attributed_entities: ["lib/foo.ex@abc"]}
      iex> Agent.attributed_to?(agent, "lib/foo.ex@abc")
      true
  """
  @spec attributed_to?(t(), String.t()) :: boolean()
  def attributed_to?(%__MODULE__{attributed_entities: entities}, entity_id) do
    entity_id in entities
  end

  @doc """
  Returns the number of activities the agent is associated with.
  """
  @spec activity_count(t()) :: non_neg_integer()
  def activity_count(%__MODULE__{associated_activities: activities}) do
    length(activities)
  end

  @doc """
  Returns the number of entities attributed to the agent.
  """
  @spec entity_count(t()) :: non_neg_integer()
  def entity_count(%__MODULE__{attributed_entities: entities}) do
    length(entities)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp matches_any?(text, patterns) do
    Enum.any?(patterns, fn pattern ->
      Regex.match?(pattern, text)
    end)
  end

  defp build_agent_from_commit(commit, role, detect_llm) do
    {email, name, timestamp} =
      case role do
        :author ->
          {commit.author_email || "unknown@unknown", commit.author_name, commit.author_date}

        :committer ->
          {commit.committer_email || "unknown@unknown", commit.committer_name, commit.commit_date}
      end

    agent_type =
      if detect_llm do
        detect_type_with_context(email, commit.message || commit.subject)
      else
        detect_type(email)
      end

    activity_id = AM.build_activity_id(commit.short_sha)

    %__MODULE__{
      agent_id: build_agent_id(email),
      agent_type: agent_type,
      name: name,
      email: email,
      identity: email,
      associated_activities: [activity_id],
      attributed_entities: [],
      first_seen: timestamp,
      last_seen: timestamp,
      metadata: %{role: role}
    }
  end

  defp merge_agents(%__MODULE__{} = agent1, %__MODULE__{} = agent2) do
    # Use most recent name
    name =
      cond do
        is_nil(agent1.last_seen) and is_nil(agent2.last_seen) -> agent1.name || agent2.name
        is_nil(agent1.last_seen) -> agent2.name
        is_nil(agent2.last_seen) -> agent1.name
        DateTime.compare(agent1.last_seen, agent2.last_seen) == :gt -> agent1.name
        true -> agent2.name
      end

    activities =
      (agent1.associated_activities ++ agent2.associated_activities)
      |> Enum.uniq()

    entities =
      (agent1.attributed_entities ++ agent2.attributed_entities)
      |> Enum.uniq()

    %__MODULE__{
      agent_id: agent1.agent_id,
      agent_type: agent1.agent_type,
      name: name,
      email: agent1.email,
      identity: agent1.identity,
      associated_activities: activities,
      attributed_entities: entities,
      first_seen: earliest_date(agent1.first_seen, agent2.first_seen),
      last_seen: latest_date(agent1.last_seen, agent2.last_seen),
      metadata: Map.merge(agent1.metadata, agent2.metadata)
    }
  end

  defp aggregate_agents(agents) do
    agents
    |> Enum.group_by(& &1.agent_id)
    |> Enum.map(fn {_id, group} ->
      Enum.reduce(group, fn agent, acc -> merge_agents(acc, agent) end)
    end)
    |> Enum.sort_by(&length(&1.associated_activities), :desc)
  end

  defp build_attributions_for_entity(entity_id, commit, include_committer) do
    attributions = []

    # Author attribution
    attributions =
      if commit.author_email do
        author_agent_id = build_agent_id(commit.author_email)

        [
          %Attribution{
            entity_id: entity_id,
            agent_id: author_agent_id,
            role: :author,
            timestamp: commit.author_date,
            metadata: %{}
          }
          | attributions
        ]
      else
        attributions
      end

    # Optional committer attribution
    attributions =
      if include_committer and commit.committer_email and
           commit.committer_email != commit.author_email do
        committer_agent_id = build_agent_id(commit.committer_email)

        [
          %Attribution{
            entity_id: entity_id,
            agent_id: committer_agent_id,
            role: :committer,
            timestamp: commit.commit_date,
            metadata: %{}
          }
          | attributions
        ]
      else
        attributions
      end

    Enum.reverse(attributions)
  end

  defp earliest_date(nil, date), do: date
  defp earliest_date(date, nil), do: date

  defp earliest_date(date1, date2) do
    case DateTime.compare(date1, date2) do
      :lt -> date1
      _ -> date2
    end
  end

  defp latest_date(nil, date), do: date
  defp latest_date(date, nil), do: date

  defp latest_date(date1, date2) do
    case DateTime.compare(date1, date2) do
      :gt -> date1
      _ -> date2
    end
  end
end
