defmodule ElixirOntologies.Extractors.Evolution.Delegation do
  @moduledoc """
  Models PROV-O delegation relationships between agents.

  This module implements the `prov:actedOnBehalfOf` relationship to track
  responsibility chains in development activities. It supports code ownership
  from CODEOWNERS files, team membership, and review approval chains.

  ## Delegation Scenarios

  - **Code Ownership**: Contributors act on behalf of code owners
  - **Team Membership**: Team members act on behalf of team leads
  - **Review Approval**: Approvers grant authority to merge
  - **Bot Delegation**: Bots act on behalf of their configuring user/org

  ## PROV-O Alignment

  - `prov:actedOnBehalfOf` - Tracked via `Delegation` struct
  - `prov:Delegation` - Ternary relationship with activity context

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.Delegation

      # Parse CODEOWNERS file
      {:ok, owners} = Delegation.parse_codeowners(".", ".github/CODEOWNERS")

      # Find owners for a file
      {:ok, file_owners} = Delegation.find_owners(owners, "lib/my_module.ex")

      # Extract delegations from commit
      {:ok, delegations} = Delegation.extract_delegations(".", commit)
  """

  alias ElixirOntologies.Extractors.Evolution.{Commit, Agent}
  alias ElixirOntologies.Extractors.Evolution.ActivityModel, as: AM
  alias ElixirOntologies.Analyzer.Git

  alias ElixirOntologies.Extractors.Evolution.GitUtils
  alias ElixirOntologies.Utils.IdGenerator

  # ===========================================================================
  # Delegation Struct
  # ===========================================================================

  @typedoc """
  Represents a prov:actedOnBehalfOf relationship.

  ## Fields

  - `:delegation_id` - Unique identifier
  - `:delegate` - Agent ID doing the work
  - `:delegator` - Agent ID on whose behalf work is done
  - `:activity` - Activity context (optional)
  - `:reason` - Delegation reason
  - `:scope` - File patterns for scope
  - `:metadata` - Additional metadata
  """
  @type delegation_reason :: :code_ownership | :team_membership | :review_approval | :bot_config

  @type t :: %__MODULE__{
          delegation_id: String.t(),
          delegate: String.t(),
          delegator: String.t(),
          activity: String.t() | nil,
          reason: delegation_reason() | nil,
          scope: [String.t()],
          metadata: map()
        }

  @enforce_keys [:delegation_id, :delegate, :delegator]
  defstruct [
    :delegation_id,
    :delegate,
    :delegator,
    :activity,
    :reason,
    scope: [],
    metadata: %{}
  ]

  # ===========================================================================
  # CodeOwner Struct
  # ===========================================================================

  defmodule CodeOwner do
    @moduledoc """
    Represents a code ownership rule from CODEOWNERS file.
    """

    @type t :: %__MODULE__{
            pattern: String.t(),
            owners: [String.t()],
            source: String.t(),
            line_number: non_neg_integer()
          }

    @enforce_keys [:pattern, :owners]
    defstruct [
      :pattern,
      :owners,
      :source,
      :line_number
    ]
  end

  # ===========================================================================
  # Team Struct
  # ===========================================================================

  defmodule Team do
    @moduledoc """
    Represents a development team.
    """

    @type t :: %__MODULE__{
            team_id: String.t(),
            name: String.t(),
            members: [String.t()],
            leads: [String.t()],
            metadata: map()
          }

    @enforce_keys [:team_id, :name]
    defstruct [
      :team_id,
      :name,
      members: [],
      leads: [],
      metadata: %{}
    ]
  end

  # ===========================================================================
  # ReviewApproval Struct
  # ===========================================================================

  defmodule ReviewApproval do
    @moduledoc """
    Represents a review approval for an activity.
    """

    @type t :: %__MODULE__{
            approval_id: String.t(),
            reviewer: String.t(),
            activity: String.t(),
            approved_at: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [:approval_id, :reviewer, :activity]
    defstruct [
      :approval_id,
      :reviewer,
      :activity,
      :approved_at,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Delegation ID Functions
  # ===========================================================================

  @doc """
  Builds a delegation ID from delegate and delegator.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Delegation
      iex> id = Delegation.build_delegation_id("agent:abc", "agent:def")
      iex> String.starts_with?(id, "delegation:")
      true
  """
  @spec build_delegation_id(String.t(), String.t()) :: String.t()
  def build_delegation_id(delegate, delegator) do
    "delegation:#{IdGenerator.delegation_id(delegate, delegator)}"
  end

  @doc """
  Builds a delegation ID with activity context.
  """
  @spec build_delegation_id(String.t(), String.t(), String.t()) :: String.t()
  def build_delegation_id(delegate, delegator, activity) do
    "delegation:#{IdGenerator.delegation_id(delegate, delegator, activity)}"
  end

  # ===========================================================================
  # CODEOWNERS Parsing
  # ===========================================================================

  @doc """
  Parses a CODEOWNERS file.

  Supports GitHub and GitLab CODEOWNERS format with patterns and owner lists.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Delegation
      iex> content = "*.ex @elixir-team\\nlib/** @alice"
      iex> {:ok, owners} = Delegation.parse_codeowners_content(content)
      iex> length(owners)
      2
  """
  @spec parse_codeowners(String.t()) :: {:ok, [CodeOwner.t()]} | {:error, atom()}
  @spec parse_codeowners(String.t(), String.t() | nil) ::
          {:ok, [CodeOwner.t()]} | {:error, atom()}
  def parse_codeowners(repo_path, codeowners_path \\ nil) do
    paths_to_try =
      if codeowners_path do
        [codeowners_path]
      else
        [
          ".github/CODEOWNERS",
          "CODEOWNERS",
          "docs/CODEOWNERS"
        ]
      end

    find_and_parse_codeowners(repo_path, paths_to_try)
  end

  @doc """
  Parses CODEOWNERS content directly.
  """
  @spec parse_codeowners_content(String.t(), String.t()) :: {:ok, [CodeOwner.t()]}
  def parse_codeowners_content(content, source \\ "CODEOWNERS") do
    owners =
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} ->
        line = String.trim(line)
        line != "" and not String.starts_with?(line, "#")
      end)
      |> Enum.map(fn {line, idx} ->
        parse_codeowners_line(line, source, idx)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, owners}
  end

  @doc """
  Finds owners for a given file path.

  Returns owners from the last matching pattern (CODEOWNERS uses last-match-wins).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Delegation
      iex> alias ElixirOntologies.Extractors.Evolution.Delegation.CodeOwner
      iex> owners = [
      ...>   %CodeOwner{pattern: "*.ex", owners: ["@team"]},
      ...>   %CodeOwner{pattern: "lib/**", owners: ["@alice"]}
      ...> ]
      iex> {:ok, result} = Delegation.find_owners(owners, "lib/foo.ex")
      iex> result.owners
      ["@alice"]
  """
  @spec find_owners([CodeOwner.t()], String.t()) :: {:ok, CodeOwner.t()} | {:error, :no_match}
  def find_owners(code_owners, file_path) when is_list(code_owners) do
    # Find last matching pattern (CODEOWNERS uses last-match-wins)
    matching =
      code_owners
      |> Enum.filter(fn owner ->
        pattern_matches?(owner.pattern, file_path)
      end)
      |> List.last()

    case matching do
      nil -> {:error, :no_match}
      owner -> {:ok, owner}
    end
  end

  @doc """
  Finds all owners for a list of file paths.

  Returns a map of file paths to their owners.
  """
  @spec find_owners_for_files([CodeOwner.t()], [String.t()]) :: %{String.t() => CodeOwner.t()}
  def find_owners_for_files(code_owners, file_paths) do
    file_paths
    |> Enum.reduce(%{}, fn path, acc ->
      case find_owners(code_owners, path) do
        {:ok, owner} -> Map.put(acc, path, owner)
        {:error, :no_match} -> acc
      end
    end)
  end

  # ===========================================================================
  # Delegation Extraction
  # ===========================================================================

  @doc """
  Extracts delegations from a commit.

  Builds delegation relationships based on:
  - Code ownership (if CODEOWNERS exists)
  - Bot delegation (if commit is from a bot)
  - Review approvals (from commit trailers)

  ## Options

  - `:include_code_owners` - Include code ownership delegations (default: true)
  - `:include_bot_delegation` - Include bot delegations (default: true)
  - `:include_review_approvals` - Include review approvals (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Delegation, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, delegations} = Delegation.extract_delegations(".", commit)
      iex> is_list(delegations)
      true
  """
  @spec extract_delegations(String.t(), Commit.t(), keyword()) ::
          {:ok, [t()]} | {:error, atom()}
  def extract_delegations(repo_path, %Commit{} = commit, opts \\ []) do
    include_code_owners = Keyword.get(opts, :include_code_owners, true)
    include_bot_delegation = Keyword.get(opts, :include_bot_delegation, true)
    include_review_approvals = Keyword.get(opts, :include_review_approvals, true)

    delegations = []

    # Code ownership delegations
    delegations =
      if include_code_owners do
        case extract_code_owner_delegations(repo_path, commit) do
          {:ok, code_delegations} -> delegations ++ code_delegations
          {:error, _} -> delegations
        end
      else
        delegations
      end

    # Bot delegations
    delegations =
      if include_bot_delegation do
        delegations ++ extract_bot_delegations(commit)
      else
        delegations
      end

    # Review approval delegations
    delegations =
      if include_review_approvals do
        delegations ++ extract_review_delegations(commit)
      else
        delegations
      end

    {:ok, delegations}
  end

  @doc """
  Extracts delegations. Raises on error.
  """
  @spec extract_delegations!(String.t(), Commit.t(), keyword()) :: [t()]
  def extract_delegations!(repo_path, commit, opts \\ []) do
    {:ok, delegations} = extract_delegations(repo_path, commit, opts)
    delegations
  end

  # ===========================================================================
  # Review Approval Extraction
  # ===========================================================================

  @doc """
  Extracts review approvals from commit message trailers.

  Looks for trailers like:
  - Reviewed-by: Name <email>
  - Approved-by: Name <email>
  - Acked-by: Name <email>

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Delegation
      iex> message = "Fix bug\\n\\nReviewed-by: Alice <alice@example.com>"
      iex> approvals = Delegation.parse_review_trailers(message, "activity:abc")
      iex> length(approvals)
      1
  """
  @spec extract_review_approvals(String.t(), Commit.t()) ::
          {:ok, [ReviewApproval.t()]} | {:error, atom()}
  def extract_review_approvals(_repo_path, %Commit{} = commit) do
    activity_id = AM.build_activity_id(commit.short_sha)
    message = commit.message || commit.body || ""

    approvals = parse_review_trailers(message, activity_id, commit.commit_date)

    {:ok, approvals}
  end

  @doc """
  Parses review trailers from commit message.
  """
  @spec parse_review_trailers(String.t(), String.t(), DateTime.t() | nil) :: [ReviewApproval.t()]
  def parse_review_trailers(message, activity_id, timestamp \\ nil) do
    # Patterns for review trailers
    patterns = [
      ~r/Reviewed-by:\s*(.+?)(?:<(.+?)>)?$/im,
      ~r/Approved-by:\s*(.+?)(?:<(.+?)>)?$/im,
      ~r/Acked-by:\s*(.+?)(?:<(.+?)>)?$/im,
      ~r/Signed-off-by:\s*(.+?)(?:<(.+?)>)?$/im
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, message)
    end)
    |> Enum.map(fn match ->
      {name, email} = parse_reviewer_match(match)
      build_review_approval(name, email, activity_id, timestamp)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ===========================================================================
  # Team Membership
  # ===========================================================================

  @doc """
  Builds team membership from a team definition.

  Creates delegations where team members act on behalf of team leads.
  """
  @spec build_team_delegations(Team.t()) :: [t()]
  def build_team_delegations(%Team{} = team) do
    # Each member delegates to each lead
    for member <- team.members,
        lead <- team.leads,
        member != lead do
      %__MODULE__{
        delegation_id: build_delegation_id(member, lead),
        delegate: member,
        delegator: lead,
        activity: nil,
        reason: :team_membership,
        scope: [],
        metadata: %{team_id: team.team_id, team_name: team.name}
      }
    end
  end

  @doc """
  Parses a simple team file format.

  Format:
  ```
  team: Team Name
  leads: @alice @bob
  members: @charlie @david @eve
  ```
  """
  @spec parse_team_file(String.t()) :: {:ok, Team.t()} | {:error, atom()}
  def parse_team_file(content) do
    lines = String.split(content, "\n")

    team_name = find_field(lines, "team")
    leads = find_list_field(lines, "leads")
    members = find_list_field(lines, "members")

    if team_name do
      team_id = build_team_id(team_name)

      {:ok,
       %Team{
         team_id: team_id,
         name: team_name,
         leads: leads,
         members: members,
         metadata: %{}
       }}
    else
      {:error, :invalid_format}
    end
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Checks if an agent delegates to another.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Delegation
      iex> d = %Delegation{delegation_id: "d:1", delegate: "agent:a", delegator: "agent:b"}
      iex> Delegation.delegates_to?(d, "agent:b")
      true
  """
  @spec delegates_to?(t(), String.t()) :: boolean()
  def delegates_to?(%__MODULE__{delegator: delegator}, agent_id) do
    delegator == agent_id
  end

  @doc """
  Checks if delegation is for a specific reason.
  """
  @spec reason?(t(), delegation_reason()) :: boolean()
  def reason?(%__MODULE__{reason: reason}, expected_reason) do
    reason == expected_reason
  end

  @doc """
  Checks if delegation applies to a file path.
  """
  @spec applies_to_file?(t(), String.t()) :: boolean()
  def applies_to_file?(%__MODULE__{scope: []}, _file_path), do: true

  def applies_to_file?(%__MODULE__{scope: scope}, file_path) do
    Enum.any?(scope, fn pattern ->
      pattern_matches?(pattern, file_path)
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_and_parse_codeowners(_repo_path, []), do: {:error, :not_found}

  defp find_and_parse_codeowners(repo_path, [path | rest]) do
    # Validate path to prevent path traversal attacks
    if GitUtils.safe_path?(path) do
      full_path = Path.join(repo_path, path)

      if File.exists?(full_path) do
        case File.read(full_path) do
          {:ok, content} -> parse_codeowners_content(content, path)
          {:error, _} -> find_and_parse_codeowners(repo_path, rest)
        end
      else
        find_and_parse_codeowners(repo_path, rest)
      end
    else
      # Skip unsafe paths
      find_and_parse_codeowners(repo_path, rest)
    end
  end

  defp parse_codeowners_line(line, source, line_number) do
    line = String.trim(line)
    parts = String.split(line, ~r/\s+/)

    case parts do
      [pattern | owners] when owners != [] ->
        %CodeOwner{
          pattern: pattern,
          owners: owners,
          source: source,
          line_number: line_number
        }

      _ ->
        nil
    end
  end

  defp pattern_matches?(pattern, path) do
    # Convert CODEOWNERS pattern to regex
    regex_pattern = codeowners_pattern_to_regex(pattern)

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, path)
      {:error, _} -> false
    end
  end

  defp codeowners_pattern_to_regex(pattern) do
    pattern
    # Escape regex special chars except * and /
    |> String.replace(~r/([.+^${}()|[\]\\])/, "\\\\\\1")
    # ** matches any path
    |> String.replace("**", ".*")
    # * matches anything except /
    |> String.replace("*", "[^/]*")
    # Anchor at start if pattern starts with /
    |> then(fn p ->
      if String.starts_with?(pattern, "/") do
        "^" <> String.trim_leading(p, "/")
      else
        "(^|/)" <> p
      end
    end)
    # Anchor at end or match directory
    |> then(fn p ->
      if String.ends_with?(pattern, "/") do
        p <> ".*"
      else
        p <> "($|/)"
      end
    end)
  end

  defp extract_code_owner_delegations(repo_path, commit) do
    with {:ok, _repo} <- Git.detect_repo(repo_path),
         {:ok, code_owners} <- parse_codeowners(repo_path) do
      # Get changed files in this commit
      changed_files = get_changed_files(repo_path, commit)

      # Find owners for changed files
      file_owners = find_owners_for_files(code_owners, changed_files)

      # Build delegations
      delegate_id = Agent.build_agent_id(commit.author_email || "unknown@unknown")
      activity_id = AM.build_activity_id(commit.short_sha)

      delegations =
        file_owners
        |> Enum.flat_map(fn {file_path, owner} ->
          owner.owners
          |> Enum.map(fn owner_ref ->
            delegator_id = owner_ref_to_agent_id(owner_ref)

            if delegator_id != delegate_id do
              %__MODULE__{
                delegation_id: build_delegation_id(delegate_id, delegator_id, activity_id),
                delegate: delegate_id,
                delegator: delegator_id,
                activity: activity_id,
                reason: :code_ownership,
                scope: [file_path],
                metadata: %{pattern: owner.pattern}
              }
            else
              nil
            end
          end)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn d -> {d.delegate, d.delegator} end)

      {:ok, delegations}
    end
  end

  defp extract_bot_delegations(commit) do
    author_type = Agent.detect_type(commit.author_email || "")

    if author_type == :bot do
      # Bot acts on behalf of the organization (inferred from email domain)
      delegate_id = Agent.build_agent_id(commit.author_email || "unknown@unknown")
      org_email = infer_org_email(commit.author_email)
      delegator_id = Agent.build_agent_id(org_email)
      activity_id = AM.build_activity_id(commit.short_sha)

      [
        %__MODULE__{
          delegation_id: build_delegation_id(delegate_id, delegator_id, activity_id),
          delegate: delegate_id,
          delegator: delegator_id,
          activity: activity_id,
          reason: :bot_config,
          scope: [],
          metadata: %{bot_email: commit.author_email}
        }
      ]
    else
      []
    end
  end

  defp extract_review_delegations(commit) do
    activity_id = AM.build_activity_id(commit.short_sha)
    message = commit.message || commit.body || ""

    # Author is granted authority by reviewers
    delegate_id = Agent.build_agent_id(commit.author_email || "unknown@unknown")

    message
    |> parse_review_trailers(activity_id, commit.commit_date)
    |> Enum.map(fn approval ->
      %__MODULE__{
        delegation_id: build_delegation_id(delegate_id, approval.reviewer, activity_id),
        delegate: delegate_id,
        delegator: approval.reviewer,
        activity: activity_id,
        reason: :review_approval,
        scope: [],
        metadata: %{approval_id: approval.approval_id}
      }
    end)
  end

  defp get_changed_files(repo_path, commit) do
    # Use git diff-tree to get changed files
    args = ["diff-tree", "--no-commit-id", "--name-only", "-r", commit.sha]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)

      {:error, _} ->
        []
    end
  end

  defp owner_ref_to_agent_id(owner_ref) do
    # Convert @username or @org/team to agent ID
    # For now, use the reference as a pseudo-email
    clean_ref = String.trim_leading(owner_ref, "@")

    email =
      if String.contains?(clean_ref, "/") do
        # Team reference: @org/team -> team@org
        [org, team] = String.split(clean_ref, "/", parts: 2)
        "#{team}@#{org}"
      else
        "#{clean_ref}@github"
      end

    Agent.build_agent_id(email)
  end

  defp infer_org_email(bot_email) when is_binary(bot_email) do
    # Extract organization from bot email
    # e.g., dependabot[bot]@users.noreply.github.com -> org@github.com
    cond do
      String.contains?(bot_email, "github.com") ->
        "org@github.com"

      String.contains?(bot_email, "gitlab.com") ->
        "org@gitlab.com"

      true ->
        # Use domain as org
        case String.split(bot_email, "@") do
          [_, domain] -> "org@#{domain}"
          _ -> "org@unknown"
        end
    end
  end

  defp infer_org_email(_), do: "org@unknown"

  defp parse_reviewer_match([_full, name]) do
    {String.trim(name), nil}
  end

  defp parse_reviewer_match([_full, name, email]) do
    {String.trim(name), String.trim(email)}
  end

  defp parse_reviewer_match(_), do: {nil, nil}

  defp build_review_approval(nil, nil, _activity_id, _timestamp), do: nil

  defp build_review_approval(name, email, activity_id, timestamp) do
    reviewer_email = email || "#{String.downcase(String.replace(name, " ", "."))}@reviewer"
    reviewer_id = Agent.build_agent_id(reviewer_email)

    approval_id = IdGenerator.generate_id([reviewer_id, activity_id], length: 12)

    %ReviewApproval{
      approval_id: "approval:#{approval_id}",
      reviewer: reviewer_id,
      activity: activity_id,
      approved_at: timestamp,
      metadata: %{reviewer_name: name, reviewer_email: email}
    }
  end

  defp find_field(lines, field_name) do
    prefix = "#{field_name}:"

    lines
    |> Enum.find_value(fn line ->
      line = String.trim(line)

      if String.starts_with?(String.downcase(line), prefix) do
        line
        |> String.slice(String.length(prefix)..-1//1)
        |> String.trim()
      else
        nil
      end
    end)
  end

  defp find_list_field(lines, field_name) do
    case find_field(lines, field_name) do
      nil -> []
      value -> String.split(value, ~r/\s+/)
    end
  end

  defp build_team_id(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "team:#{slug}"
  end
end
