defmodule ElixirOntologies.Extractors.Evolution.FeatureTracking do
  @moduledoc """
  Tracks feature additions and bug fixes as distinct activities.

  This module parses commit messages to identify features and bug fixes,
  extracts issue references, and tracks the scope of changes.

  ## Issue Reference Patterns

  Supports common patterns for issue references:

  | Pattern | Example | Tracker |
  |---------|---------|---------|
  | `#N` | `#123` | GitHub/GitLab default |
  | `GH-N` | `GH-456` | GitHub |
  | `GL-N` | `GL-789` | GitLab |
  | `PROJ-N` | `JIRA-123` | Jira-style |
  | `fixes #N` | `fixes #42` | Closing keyword |
  | `closes #N` | `closes #99` | Closing keyword |
  | `resolves #N` | `resolves #10` | Closing keyword |

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{FeatureTracking, Commit}

      # Parse issue references from a message
      refs = FeatureTracking.parse_issue_references("Fix bug #123 and closes #456")

      # Detect features in a commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, features} = FeatureTracking.detect_features(".", commit)

      # Detect bug fixes in a commit
      {:ok, bugfixes} = FeatureTracking.detect_bugfixes(".", commit)
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.Activity
  alias ElixirOntologies.Extractors.Evolution.Activity.Scope

  # ===========================================================================
  # Type Definitions
  # ===========================================================================

  @type tracker :: :github | :gitlab | :jira | :generic
  @type action :: :mentions | :fixes | :closes | :resolves | :relates

  # ===========================================================================
  # Nested Structs
  # ===========================================================================

  defmodule IssueReference do
    @moduledoc """
    Represents a reference to an external issue.
    """

    @type t :: %__MODULE__{
            tracker: atom(),
            number: pos_integer() | String.t(),
            project: String.t() | nil,
            action: atom(),
            url: String.t() | nil
          }

    defstruct tracker: :generic,
              number: nil,
              project: nil,
              action: :mentions,
              url: nil
  end

  defmodule FeatureAddition do
    @moduledoc """
    Represents a feature addition activity.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t() | nil,
            commit: Commit.t(),
            modules: [String.t()],
            functions: [{atom(), non_neg_integer()}],
            issue_refs: [IssueReference.t()],
            scope: Scope.t() | nil,
            metadata: map()
          }

    @enforce_keys [:name, :commit]
    defstruct [
      :name,
      :description,
      :commit,
      modules: [],
      functions: [],
      issue_refs: [],
      scope: nil,
      metadata: %{}
    ]
  end

  defmodule BugFix do
    @moduledoc """
    Represents a bug fix activity.
    """

    @type t :: %__MODULE__{
            description: String.t(),
            commit: Commit.t(),
            affected_modules: [String.t()],
            affected_functions: [{atom(), non_neg_integer()}],
            issue_refs: [IssueReference.t()],
            scope: Scope.t() | nil,
            metadata: map()
          }

    @enforce_keys [:description, :commit]
    defstruct [
      :description,
      :commit,
      affected_modules: [],
      affected_functions: [],
      issue_refs: [],
      scope: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Public API - Issue References
  # ===========================================================================

  @doc """
  Parses issue references from a commit message.

  Extracts issue references in various formats and identifies
  the action (mentions, fixes, closes, resolves).

  ## Examples

      iex> FeatureTracking.parse_issue_references("Fix bug #123")
      [%IssueReference{tracker: :generic, number: 123, action: :mentions}]

      iex> FeatureTracking.parse_issue_references("closes #456, fixes GH-789")
      [
        %IssueReference{tracker: :generic, number: 456, action: :closes},
        %IssueReference{tracker: :github, number: 789, action: :fixes}
      ]
  """
  @spec parse_issue_references(String.t() | nil) :: [IssueReference.t()]
  def parse_issue_references(nil), do: []
  def parse_issue_references(""), do: []

  def parse_issue_references(message) when is_binary(message) do
    # Find all issue references with their actions
    closing_refs = find_closing_references(message)
    plain_refs = find_plain_references(message)

    # Merge, preferring closing refs (they have action context)
    merge_references(closing_refs, plain_refs)
  end

  @doc """
  Builds a URL for an issue reference given tracker configuration.

  ## Options

  - `:github_repo` - GitHub repository (e.g., "owner/repo")
  - `:gitlab_repo` - GitLab repository
  - `:gitlab_url` - GitLab base URL (default: "https://gitlab.com")
  - `:jira_url` - Jira base URL

  ## Examples

      iex> ref = %IssueReference{tracker: :github, number: 123}
      iex> FeatureTracking.build_issue_url(ref, github_repo: "owner/repo")
      "https://github.com/owner/repo/issues/123"
  """
  @spec build_issue_url(IssueReference.t(), keyword()) :: String.t() | nil
  def build_issue_url(%IssueReference{} = ref, opts \\ []) do
    case ref.tracker do
      :github ->
        case Keyword.get(opts, :github_repo) do
          nil -> nil
          repo -> "https://github.com/#{repo}/issues/#{ref.number}"
        end

      :gitlab ->
        case Keyword.get(opts, :gitlab_repo) do
          nil ->
            nil

          repo ->
            base = Keyword.get(opts, :gitlab_url, "https://gitlab.com")
            "#{base}/#{repo}/-/issues/#{ref.number}"
        end

      :jira ->
        case Keyword.get(opts, :jira_url) do
          nil -> nil
          base -> "#{base}/browse/#{ref.project}-#{ref.number}"
        end

      :generic ->
        # Try GitHub if repo is configured
        case Keyword.get(opts, :github_repo) do
          nil -> nil
          repo -> "https://github.com/#{repo}/issues/#{ref.number}"
        end
    end
  end

  @doc """
  Returns all supported tracker types.
  """
  @spec tracker_types() :: [tracker()]
  def tracker_types, do: [:github, :gitlab, :jira, :generic]

  @doc """
  Returns all supported action types.
  """
  @spec action_types() :: [action()]
  def action_types, do: [:mentions, :fixes, :closes, :resolves, :relates]

  # ===========================================================================
  # Public API - Feature Detection
  # ===========================================================================

  @doc """
  Detects feature additions in a commit.

  Analyzes the commit message and changes to identify feature additions.
  Uses the Activity module for classification and scope extraction.

  ## Options

  - `:include_scope` - Include scope information (default: true)
  - `:tracker_opts` - Options for issue URL generation

  ## Examples

      {:ok, features} = FeatureTracking.detect_features(".", commit)
  """
  @spec detect_features(String.t(), Commit.t(), keyword()) ::
          {:ok, [FeatureAddition.t()]} | {:error, term()}
  def detect_features(repo_path, %Commit{} = commit, opts \\ []) do
    include_scope = Keyword.get(opts, :include_scope, true)
    tracker_opts = Keyword.get(opts, :tracker_opts, [])

    # Use Activity module to classify
    {:ok, activity} = Activity.classify_commit(repo_path, commit, include_scope: include_scope)

    if activity.type == :feature do
      feature = build_feature(commit, activity, tracker_opts)
      {:ok, [feature]}
    else
      {:ok, []}
    end
  end

  @doc """
  Detects feature additions in a commit, raising on error.
  """
  @spec detect_features!(String.t(), Commit.t(), keyword()) :: [FeatureAddition.t()]
  def detect_features!(repo_path, commit, opts \\ []) do
    {:ok, features} = detect_features(repo_path, commit, opts)
    features
  end

  # ===========================================================================
  # Public API - Bug Fix Detection
  # ===========================================================================

  @doc """
  Detects bug fixes in a commit.

  Analyzes the commit message and changes to identify bug fixes.
  Uses the Activity module for classification and scope extraction.

  ## Options

  - `:include_scope` - Include scope information (default: true)
  - `:tracker_opts` - Options for issue URL generation

  ## Examples

      {:ok, bugfixes} = FeatureTracking.detect_bugfixes(".", commit)
  """
  @spec detect_bugfixes(String.t(), Commit.t(), keyword()) ::
          {:ok, [BugFix.t()]} | {:error, term()}
  def detect_bugfixes(repo_path, %Commit{} = commit, opts \\ []) do
    include_scope = Keyword.get(opts, :include_scope, true)
    tracker_opts = Keyword.get(opts, :tracker_opts, [])

    # Use Activity module to classify
    {:ok, activity} = Activity.classify_commit(repo_path, commit, include_scope: include_scope)

    if activity.type == :bugfix do
      bugfix = build_bugfix(commit, activity, tracker_opts)
      {:ok, [bugfix]}
    else
      {:ok, []}
    end
  end

  @doc """
  Detects bug fixes in a commit, raising on error.
  """
  @spec detect_bugfixes!(String.t(), Commit.t(), keyword()) :: [BugFix.t()]
  def detect_bugfixes!(repo_path, commit, opts \\ []) do
    {:ok, bugfixes} = detect_bugfixes(repo_path, commit, opts)
    bugfixes
  end

  # ===========================================================================
  # Public API - Batch Detection
  # ===========================================================================

  @doc """
  Detects features and bug fixes across multiple commits.

  Returns a map with `:features` and `:bugfixes` keys.
  """
  @spec detect_all(String.t(), [Commit.t()], keyword()) ::
          {:ok, %{features: [FeatureAddition.t()], bugfixes: [BugFix.t()]}} | {:error, term()}
  def detect_all(repo_path, commits, opts \\ []) do
    results =
      commits
      |> Enum.reduce(%{features: [], bugfixes: []}, fn commit, acc ->
        {:ok, features} = detect_features(repo_path, commit, opts)
        {:ok, bugfixes} = detect_bugfixes(repo_path, commit, opts)

        %{acc | features: acc.features ++ features, bugfixes: acc.bugfixes ++ bugfixes}
      end)

    {:ok, results}
  end

  # ===========================================================================
  # Public API - Query Functions
  # ===========================================================================

  @doc """
  Checks if a feature has associated issue references.
  """
  @spec has_issues?(FeatureAddition.t() | BugFix.t()) :: boolean()
  def has_issues?(%FeatureAddition{issue_refs: refs}), do: length(refs) > 0
  def has_issues?(%BugFix{issue_refs: refs}), do: length(refs) > 0

  @doc """
  Gets all closing issue references (fixes, closes, resolves).
  """
  @spec closing_issues(FeatureAddition.t() | BugFix.t()) :: [IssueReference.t()]
  def closing_issues(%FeatureAddition{issue_refs: refs}), do: filter_closing(refs)
  def closing_issues(%BugFix{issue_refs: refs}), do: filter_closing(refs)

  defp filter_closing(refs) do
    Enum.filter(refs, &(&1.action in [:fixes, :closes, :resolves]))
  end

  # ===========================================================================
  # Private - Issue Reference Parsing
  # ===========================================================================

  defp find_closing_references(message) do
    # Pattern: (fixes|closes|resolves|fix|close|resolve) #N or GH-N etc.
    closing_pattern =
      ~r/\b(fix(?:es)?|close[sd]?|resolve[sd]?)\s+(?:#(\d+)|GH-(\d+)|GL-(\d+)|([A-Z][A-Z0-9]+-\d+))/i

    Regex.scan(closing_pattern, message)
    |> Enum.map(fn match ->
      action = parse_action(Enum.at(match, 1))

      cond do
        # #N pattern
        (num = Enum.at(match, 2)) && num != "" ->
          %IssueReference{
            tracker: :generic,
            number: String.to_integer(num),
            action: action
          }

        # GH-N pattern
        (num = Enum.at(match, 3)) && num != "" ->
          %IssueReference{
            tracker: :github,
            number: String.to_integer(num),
            action: action
          }

        # GL-N pattern
        (num = Enum.at(match, 4)) && num != "" ->
          %IssueReference{
            tracker: :gitlab,
            number: String.to_integer(num),
            action: action
          }

        # PROJ-N pattern (Jira style)
        (proj_num = Enum.at(match, 5)) && proj_num != "" ->
          [project, num] = String.split(proj_num, "-", parts: 2)

          %IssueReference{
            tracker: :jira,
            number: String.to_integer(num),
            project: project,
            action: action
          }

        true ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp find_plain_references(message) do
    # Pattern: standalone #N, GH-N, GL-N, or PROJ-N (not preceded by closing keywords)
    patterns = [
      # #N - but not preceded by closing keywords (handled by negative lookbehind approximation)
      {~r/(?<![a-z])\s*#(\d+)/i, :generic},
      # GH-N
      {~r/\bGH-(\d+)/i, :github},
      # GL-N
      {~r/\bGL-(\d+)/i, :gitlab},
      # PROJ-N (Jira style) - must be uppercase project key
      {~r/\b([A-Z][A-Z0-9]+)-(\d+)/, :jira}
    ]

    patterns
    |> Enum.flat_map(fn {pattern, tracker} ->
      Regex.scan(pattern, message)
      |> Enum.map(fn match ->
        case tracker do
          :jira ->
            project = Enum.at(match, 1)
            num = Enum.at(match, 2)

            # Skip if it looks like GH- or GL-
            if project in ["GH", "GL"] do
              nil
            else
              %IssueReference{
                tracker: :jira,
                number: String.to_integer(num),
                project: project,
                action: :mentions
              }
            end

          _ ->
            num = Enum.at(match, 1)

            %IssueReference{
              tracker: tracker,
              number: String.to_integer(num),
              action: :mentions
            }
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_action(keyword) do
    keyword = String.downcase(keyword)

    cond do
      String.starts_with?(keyword, "fix") -> :fixes
      String.starts_with?(keyword, "close") -> :closes
      String.starts_with?(keyword, "resolve") -> :resolves
      true -> :mentions
    end
  end

  defp merge_references(closing_refs, plain_refs) do
    # Create a set of (tracker, number) from closing refs
    closing_keys =
      closing_refs
      |> Enum.map(fn ref -> {ref.tracker, ref.number, ref.project} end)
      |> MapSet.new()

    # Filter plain refs that aren't already in closing refs
    unique_plain =
      plain_refs
      |> Enum.reject(fn ref ->
        MapSet.member?(closing_keys, {ref.tracker, ref.number, ref.project})
      end)

    closing_refs ++ unique_plain
  end

  # ===========================================================================
  # Private - Feature Building
  # ===========================================================================

  defp build_feature(commit, activity, tracker_opts) do
    message = commit.subject || commit.message || ""
    issue_refs = parse_issue_references(message <> " " <> (commit.body || ""))

    # Add URLs to issue refs
    issue_refs =
      Enum.map(issue_refs, fn ref ->
        %{ref | url: build_issue_url(ref, tracker_opts)}
      end)

    # Extract feature name from message
    name = extract_feature_name(message)

    # Get modules and functions from scope
    {modules, functions} = extract_affected_elements(activity.scope)

    %FeatureAddition{
      name: name,
      description: commit.body,
      commit: commit,
      modules: modules,
      functions: functions,
      issue_refs: issue_refs,
      scope: activity.scope,
      metadata: %{
        classification: activity.classification
      }
    }
  end

  defp extract_feature_name(message) do
    # Try to extract from conventional commit
    case Regex.run(~r/^(?:feat|feature)(?:\([^)]+\))?[!:]?\s*(.+)$/i, message) do
      [_, description] -> String.trim(description)
      nil -> extract_name_from_keywords(message)
    end
  end

  defp extract_name_from_keywords(message) do
    # Try common patterns
    patterns = [
      ~r/^add(?:ed|s|ing)?\s+(.+)/i,
      ~r/^implement(?:ed|s|ing)?\s+(.+)/i,
      ~r/^create(?:d|s|ing)?\s+(.+)/i,
      ~r/^introduce(?:d|s|ing)?\s+(.+)/i
    ]

    Enum.find_value(patterns, message, fn pattern ->
      case Regex.run(pattern, message) do
        [_, name] -> String.trim(name)
        nil -> nil
      end
    end)
  end

  # ===========================================================================
  # Private - Bug Fix Building
  # ===========================================================================

  defp build_bugfix(commit, activity, tracker_opts) do
    message = commit.subject || commit.message || ""
    issue_refs = parse_issue_references(message <> " " <> (commit.body || ""))

    # Add URLs to issue refs
    issue_refs =
      Enum.map(issue_refs, fn ref ->
        %{ref | url: build_issue_url(ref, tracker_opts)}
      end)

    # Extract description
    description = extract_bugfix_description(message)

    # Get affected modules and functions from scope
    {modules, functions} = extract_affected_elements(activity.scope)

    %BugFix{
      description: description,
      commit: commit,
      affected_modules: modules,
      affected_functions: functions,
      issue_refs: issue_refs,
      scope: activity.scope,
      metadata: %{
        classification: activity.classification
      }
    }
  end

  defp extract_bugfix_description(message) do
    # Try to extract from conventional commit
    case Regex.run(~r/^(?:fix|bugfix)(?:\([^)]+\))?[!:]?\s*(.+)$/i, message) do
      [_, description] -> String.trim(description)
      nil -> extract_description_from_keywords(message)
    end
  end

  defp extract_description_from_keywords(message) do
    patterns = [
      ~r/^fix(?:ed|es|ing)?\s+(.+)/i,
      ~r/^resolve(?:d|s|ing)?\s+(.+)/i,
      ~r/^repair(?:ed|s|ing)?\s+(.+)/i,
      ~r/^correct(?:ed|s|ing)?\s+(.+)/i
    ]

    Enum.find_value(patterns, message, fn pattern ->
      case Regex.run(pattern, message) do
        [_, desc] -> String.trim(desc)
        nil -> nil
      end
    end)
  end

  # ===========================================================================
  # Private - Scope Helpers
  # ===========================================================================

  defp extract_affected_elements(nil), do: {[], []}

  defp extract_affected_elements(%Scope{} = scope) do
    modules = scope.modules_affected || []

    # Extract function names from files if available
    functions =
      (scope.files_changed || [])
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.flat_map(&extract_functions_from_path/1)

    {modules, functions}
  end

  defp extract_functions_from_path(_path) do
    # For now, return empty - would need to parse file to get functions
    # This could be enhanced to actually parse the file
    []
  end
end
