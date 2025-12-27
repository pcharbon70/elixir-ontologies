defmodule ElixirOntologies.Extractors.Evolution.Activity do
  @moduledoc """
  Classifies commits into development activity types.

  This module analyzes commit messages and changes to classify development
  activities for PROV-O integration. It supports conventional commit format
  and heuristic classification based on keywords and file patterns.

  ## Activity Types

  Supported activity types based on conventional commits and common patterns:

  | Type | Description | Conventional Prefix |
  |------|-------------|---------------------|
  | `:feature` | New functionality | `feat:`, `feature:` |
  | `:bugfix` | Bug fix | `fix:`, `bugfix:` |
  | `:refactor` | Code restructuring | `refactor:` |
  | `:docs` | Documentation | `docs:` |
  | `:test` | Test changes | `test:` |
  | `:chore` | Build/tooling | `chore:`, `build:` |
  | `:style` | Formatting | `style:` |
  | `:perf` | Performance | `perf:` |
  | `:ci` | CI/CD changes | `ci:` |
  | `:revert` | Revert commit | `revert:` |
  | `:deps` | Dependency updates | `deps:` |
  | `:release` | Version release | `release:` |
  | `:wip` | Work in progress | `wip:` |
  | `:unknown` | Cannot classify | (fallback) |

  ## Classification Methods

  1. **Conventional Commit Parsing** (high confidence)
     - Pattern: `type(scope)!?: description`
     - Examples: `feat(auth): add login`, `fix!: critical bug`

  2. **Keyword Heuristics** (medium confidence)
     - Subject keywords: "add", "fix", "refactor", "update docs"
     - Body patterns: "Fixes #123", "BREAKING CHANGE"

  3. **File-Based Heuristics** (low confidence)
     - Only test files changed → `:test`
     - Only markdown files → `:docs`
     - mix.exs with deps → `:deps`

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{Activity, Commit}

      # Classify a single commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = Activity.classify_commit(".", commit)

      activity.type
      # => :feature

      activity.classification.method
      # => :conventional_commit

      # Classify multiple commits
      {:ok, commits} = Commit.extract_commits(".", limit: 10)
      {:ok, activities} = Activity.classify_commits(".", commits)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.parse_conventional_commit("feat(auth): add login")
      {:ok, %{type: "feat", scope: "auth", breaking: false, description: "add login"}}

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.parse_conventional_commit("fix!: critical security issue")
      {:ok, %{type: "fix", scope: nil, breaking: true, description: "critical security issue"}}
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.GitUtils

  # ===========================================================================
  # Type Definitions
  # ===========================================================================

  @type activity_type ::
          :feature
          | :bugfix
          | :refactor
          | :docs
          | :test
          | :chore
          | :style
          | :perf
          | :ci
          | :revert
          | :deps
          | :release
          | :wip
          | :unknown

  @type confidence :: :high | :medium | :low

  @type classification_method :: :conventional_commit | :heuristic | :keyword | :file_based

  # ===========================================================================
  # Scope Struct
  # ===========================================================================

  defmodule Scope do
    @moduledoc """
    Represents the scope of changes in a commit.
    """

    @type t :: %__MODULE__{
            files_changed: [String.t()],
            modules_affected: [String.t()],
            lines_added: non_neg_integer(),
            lines_deleted: non_neg_integer()
          }

    defstruct files_changed: [],
              modules_affected: [],
              lines_added: 0,
              lines_deleted: 0
  end

  # ===========================================================================
  # Classification Struct
  # ===========================================================================

  defmodule Classification do
    @moduledoc """
    Represents how the activity type was determined.
    """

    @type t :: %__MODULE__{
            method: ElixirOntologies.Extractors.Evolution.Activity.classification_method(),
            confidence: ElixirOntologies.Extractors.Evolution.Activity.confidence(),
            raw_type: String.t() | nil,
            breaking: boolean(),
            scope_hint: String.t() | nil
          }

    defstruct method: :heuristic,
              confidence: :low,
              raw_type: nil,
              breaking: false,
              scope_hint: nil
  end

  # ===========================================================================
  # DevelopmentActivity Struct
  # ===========================================================================

  @typedoc """
  Represents a classified development activity.

  ## Fields

  - `:type` - The activity type (feature, bugfix, refactor, etc.)
  - `:commit` - The associated commit
  - `:scope` - Files and modules affected
  - `:classification` - How the type was determined
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          type: activity_type(),
          commit: Commit.t(),
          scope: Scope.t(),
          classification: Classification.t(),
          metadata: map()
        }

  @enforce_keys [:type, :commit]
  defstruct [
    :type,
    :commit,
    :scope,
    :classification,
    metadata: %{}
  ]

  # ===========================================================================
  # Constants
  # ===========================================================================

  # Conventional commit pattern
  # Matches: type(scope)!: description
  # Groups: 1=type, 2=scope (optional, can be empty), 3=breaking (optional), 4=description
  @conventional_commit_regex ~r/^(\w+(?:-\w+)*)(?:\(([^)]*)\))?(!)?\s*:\s*(.+)$/s

  # Map of conventional commit prefixes to activity types
  @type_mapping %{
    "feat" => :feature,
    "feature" => :feature,
    "fix" => :bugfix,
    "bugfix" => :bugfix,
    "refactor" => :refactor,
    "docs" => :docs,
    "doc" => :docs,
    "test" => :test,
    "tests" => :test,
    "chore" => :chore,
    "build" => :chore,
    "style" => :style,
    "perf" => :perf,
    "performance" => :perf,
    "ci" => :ci,
    "revert" => :revert,
    "deps" => :deps,
    "dependency" => :deps,
    "dependencies" => :deps,
    "release" => :release,
    "version" => :release,
    "wip" => :wip
  }

  # Keyword patterns for heuristic classification
  # Order matters! More specific patterns should come before generic ones
  @keyword_patterns [
    # Revert must come first (exact pattern)
    {:revert, ~r/^revert\b/i},
    # Documentation - check before feature because "Add documentation" should be docs
    {:docs, ~r/\b(doc|docs|documentation|readme|comment|comments|javadoc|typedoc|moduledoc)\b/i},
    # Test - check before feature because "Add tests" should be test
    {:test, ~r/\b(test|tests|testing|spec|specs|coverage)\b/i},
    # Performance - check before feature because "Add caching" should be perf
    {:perf,
     ~r/\b(perf|performance|optimize|optimized|optimization|speed|faster|cache|caching)\b/i},
    # Bug fix patterns
    {:bugfix,
     ~r/\b(fix|fixed|fixing|bug|bugfix|repair|resolve|resolved|resolves|closes?|closed)\b/i},
    # Refactor
    {:refactor,
     ~r/\b(refactor|refactored|refactoring|restructure|reorganize|cleanup|clean up|simplify)\b/i},
    # Chore
    {:chore, ~r/\b(chore|build|tooling|config|configure|setup|maintenance)\b/i},
    # Style
    {:style, ~r/\b(style|format|formatting|lint|linting|prettier|credo)\b/i},
    # CI
    {:ci, ~r/\b(ci|cd|pipeline|github actions|travis|circle|jenkins|workflow)\b/i},
    # Dependencies
    {:deps,
     ~r/\b(deps|dependency|dependencies|upgrade|update|bump|version)\s+(mix\.exs|package\.json|gemfile)/i},
    # Release
    {:release, ~r/\b(release|version|v?\d+\.\d+\.\d+|bump version|prepare release)\b/i},
    # WIP
    {:wip, ~r/\b(wip|work in progress|todo|fixme|hack)\b/i},
    # Feature - last, as it's the most generic pattern
    {:feature,
     ~r/\b(add|added|adding|implement|implemented|implementing|new|create|created|introduce|introduced)\b/i}
  ]

  # ===========================================================================
  # Main Classification Functions
  # ===========================================================================

  @doc """
  Classifies a single commit into a development activity.

  ## Parameters

  - `repo_path` - Path to the git repository
  - `commit` - The commit to classify
  - `opts` - Options
    - `:include_scope` - Whether to extract file scope (default: true)

  ## Returns

  - `{:ok, %DevelopmentActivity{}}` - Successfully classified
  - `{:error, reason}` - Failed to classify

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Activity, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, activity} = Activity.classify_commit(".", commit)
      iex> is_atom(activity.type)
      true
  """
  @spec classify_commit(String.t(), Commit.t(), keyword()) ::
          {:ok, t()} | {:error, atom()}
  def classify_commit(repo_path, %Commit{} = commit, opts \\ []) do
    include_scope = Keyword.get(opts, :include_scope, true)

    # Try conventional commit first, then fall back to heuristics
    {type, classification} = classify_message(commit.subject)

    # Extract scope if requested
    scope =
      if include_scope do
        case extract_scope(repo_path, commit) do
          {:ok, s} -> s
          {:error, _} -> %Scope{}
        end
      else
        %Scope{}
      end

    # If classification is still unknown, try file-based heuristics
    {final_type, final_classification} =
      if type == :unknown and include_scope do
        {file_type, file_classification} = classify_by_files(scope.files_changed)

        if file_type != :unknown do
          {file_type, file_classification}
        else
          {type, classification}
        end
      else
        {type, classification}
      end

    {:ok,
     %__MODULE__{
       type: final_type,
       commit: commit,
       scope: scope,
       classification: final_classification,
       metadata: %{}
     }}
  end

  @doc """
  Classifies a commit, raising on error.
  """
  @spec classify_commit!(String.t(), Commit.t(), keyword()) :: t()
  def classify_commit!(repo_path, commit, opts \\ []) do
    {:ok, activity} = classify_commit(repo_path, commit, opts)
    activity
  end

  @doc """
  Classifies multiple commits into development activities.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Activity, Commit}
      iex> {:ok, commits} = Commit.extract_commits(".", limit: 5)
      iex> {:ok, activities} = Activity.classify_commits(".", commits)
      iex> is_list(activities)
      true
  """
  @spec classify_commits(String.t(), [Commit.t()], keyword()) ::
          {:ok, [t()]} | {:error, atom()}
  def classify_commits(repo_path, commits, opts \\ []) when is_list(commits) do
    activities =
      commits
      |> Enum.map(fn commit ->
        {:ok, activity} = classify_commit(repo_path, commit, opts)
        activity
      end)

    {:ok, activities}
  end

  @doc """
  Classifies multiple commits, raising on error.
  """
  @spec classify_commits!(String.t(), [Commit.t()], keyword()) :: [t()]
  def classify_commits!(repo_path, commits, opts \\ []) do
    {:ok, activities} = classify_commits(repo_path, commits, opts)
    activities
  end

  # ===========================================================================
  # Conventional Commit Parsing
  # ===========================================================================

  @doc """
  Parses a conventional commit message.

  Conventional commit format: `type(scope)!: description`

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.parse_conventional_commit("feat(auth): add login")
      {:ok, %{type: "feat", scope: "auth", breaking: false, description: "add login"}}

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.parse_conventional_commit("fix!: critical issue")
      {:ok, %{type: "fix", scope: nil, breaking: true, description: "critical issue"}}

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.parse_conventional_commit("not a conventional commit")
      {:error, :not_conventional}
  """
  @spec parse_conventional_commit(String.t() | nil) ::
          {:ok,
           %{
             type: String.t(),
             scope: String.t() | nil,
             breaking: boolean(),
             description: String.t()
           }}
          | {:error, :not_conventional}
  def parse_conventional_commit(nil), do: {:error, :not_conventional}

  def parse_conventional_commit(message) when is_binary(message) do
    # Take only the first line (subject)
    subject = message |> String.split("\n", parts: 2) |> List.first() |> String.trim()

    case Regex.run(@conventional_commit_regex, subject) do
      [_, type, scope, breaking, description] ->
        {:ok,
         %{
           type: String.downcase(type),
           scope: if(scope && scope != "", do: scope, else: nil),
           breaking: breaking == "!",
           description: String.trim(description)
         }}

      [_, type, nil, breaking, description] ->
        {:ok,
         %{
           type: String.downcase(type),
           scope: nil,
           breaking: breaking == "!",
           description: String.trim(description)
         }}

      [_, type, scope, description] when is_binary(scope) ->
        {:ok,
         %{
           type: String.downcase(type),
           scope: if(scope != "", do: scope, else: nil),
           breaking: false,
           description: String.trim(description)
         }}

      _ ->
        {:error, :not_conventional}
    end
  end

  @doc """
  Checks if a commit message follows conventional commit format.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.conventional_commit?("feat: add feature")
      true

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.conventional_commit?("Add new feature")
      false
  """
  @spec conventional_commit?(String.t() | nil) :: boolean()
  def conventional_commit?(message) do
    case parse_conventional_commit(message) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # ===========================================================================
  # Scope Extraction
  # ===========================================================================

  @doc """
  Extracts the scope of changes for a commit.

  Uses `git diff-tree` to get changed files and line statistics.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Activity, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> {:ok, scope} = Activity.extract_scope(".", commit)
      iex> is_list(scope.files_changed)
      true
  """
  @spec extract_scope(String.t(), Commit.t()) :: {:ok, Scope.t()} | {:error, atom()}
  def extract_scope(repo_path, %Commit{sha: sha}) do
    # Use git diff-tree to get changed files with stats
    args = ["diff-tree", "--no-commit-id", "--numstat", "-r", sha]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        {files, added, deleted} = parse_diff_tree_output(output)
        modules = extract_modules_from_files(files)

        {:ok,
         %Scope{
           files_changed: files,
           modules_affected: modules,
           lines_added: added,
           lines_deleted: deleted
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Returns all supported activity types.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> types = Activity.activity_types()
      iex> :feature in types
      true
  """
  @spec activity_types() :: [activity_type()]
  def activity_types do
    [
      :feature,
      :bugfix,
      :refactor,
      :docs,
      :test,
      :chore,
      :style,
      :perf,
      :ci,
      :revert,
      :deps,
      :release,
      :wip,
      :unknown
    ]
  end

  @doc """
  Converts a conventional commit type string to an activity type atom.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.type_from_string("feat")
      :feature

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> Activity.type_from_string("unknown-type")
      :unknown
  """
  @spec type_from_string(String.t()) :: activity_type()
  def type_from_string(type_string) when is_binary(type_string) do
    Map.get(@type_mapping, String.downcase(type_string), :unknown)
  end

  @doc """
  Checks if an activity represents a breaking change.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> activity = %Activity{type: :feature, commit: %{sha: "abc", short_sha: "abc"}, classification: %Activity.Classification{breaking: true}}
      iex> Activity.breaking_change?(activity)
      true
  """
  @spec breaking_change?(t()) :: boolean()
  def breaking_change?(%__MODULE__{classification: %Classification{breaking: breaking}}),
    do: breaking

  @doc """
  Returns the confidence level of the classification.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Activity
      iex> activity = %Activity{type: :feature, commit: %{sha: "abc", short_sha: "abc"}, classification: %Activity.Classification{confidence: :high}}
      iex> Activity.classification_confidence(activity)
      :high
  """
  @spec classification_confidence(t()) :: confidence()
  def classification_confidence(%__MODULE__{classification: %Classification{confidence: conf}}),
    do: conf

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp classify_message(subject) do
    # Try conventional commit first
    case parse_conventional_commit(subject) do
      {:ok, parsed} ->
        type = type_from_string(parsed.type)

        classification = %Classification{
          method: :conventional_commit,
          confidence: :high,
          raw_type: parsed.type,
          breaking: parsed.breaking,
          scope_hint: parsed.scope
        }

        {type, classification}

      {:error, :not_conventional} ->
        # Fall back to keyword heuristics
        classify_by_keywords(subject)
    end
  end

  defp classify_by_keywords(nil),
    do: {:unknown, %Classification{method: :keyword, confidence: :low}}

  defp classify_by_keywords(subject) when is_binary(subject) do
    # Find the first matching pattern
    result =
      Enum.find_value(@keyword_patterns, fn {type, pattern} ->
        if Regex.match?(pattern, subject) do
          {type, pattern}
        else
          nil
        end
      end)

    case result do
      {type, _pattern} ->
        classification = %Classification{
          method: :keyword,
          confidence: :medium,
          raw_type: nil,
          breaking: check_breaking_change(subject),
          scope_hint: nil
        }

        {type, classification}

      nil ->
        {:unknown, %Classification{method: :keyword, confidence: :low}}
    end
  end

  defp classify_by_files([]) do
    {:unknown, %Classification{method: :file_based, confidence: :low}}
  end

  defp classify_by_files(files) when is_list(files) do
    cond do
      # All test files
      Enum.all?(files, &test_file?/1) ->
        {:test, %Classification{method: :file_based, confidence: :medium}}

      # All documentation files
      Enum.all?(files, &doc_file?/1) ->
        {:docs, %Classification{method: :file_based, confidence: :medium}}

      # Only mix.exs changed (likely deps update)
      files == ["mix.exs"] or files == ["mix.exs", "mix.lock"] ->
        {:deps, %Classification{method: :file_based, confidence: :low}}

      # CI config files
      Enum.all?(files, &ci_file?/1) ->
        {:ci, %Classification{method: :file_based, confidence: :medium}}

      true ->
        {:unknown, %Classification{method: :file_based, confidence: :low}}
    end
  end

  defp test_file?(path) do
    String.contains?(path, "/test/") or
      String.ends_with?(path, "_test.exs") or
      String.ends_with?(path, "_test.ex") or
      String.ends_with?(path, ".test.js") or
      String.ends_with?(path, ".spec.js")
  end

  defp doc_file?(path) do
    String.ends_with?(path, ".md") or
      String.ends_with?(path, ".txt") or
      String.ends_with?(path, ".rst") or
      String.starts_with?(path, "docs/") or
      path == "README" or
      path == "CHANGELOG"
  end

  defp ci_file?(path) do
    String.starts_with?(path, ".github/") or
      String.starts_with?(path, ".circleci/") or
      String.starts_with?(path, ".travis") or
      path == ".gitlab-ci.yml" or
      path == "Jenkinsfile"
  end

  defp check_breaking_change(nil), do: false

  defp check_breaking_change(text) do
    String.contains?(text, "BREAKING CHANGE") or
      String.contains?(text, "BREAKING:") or
      Regex.match?(~r/\bbreaking\b/i, text)
  end

  defp parse_diff_tree_output(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.reduce(lines, {[], 0, 0}, fn line, {files, added, deleted} ->
      case String.split(line, "\t") do
        [add_str, del_str, file] ->
          add = parse_stat(add_str)
          del = parse_stat(del_str)
          {[file | files], added + add, deleted + del}

        _ ->
          {files, added, deleted}
      end
    end)
    |> then(fn {files, added, deleted} -> {Enum.reverse(files), added, deleted} end)
  end

  defp parse_stat("-"), do: 0

  defp parse_stat(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp extract_modules_from_files(files) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.filter(&(not String.ends_with?(&1, "_test.exs")))
    |> Enum.map(&path_to_module/1)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end

  defp path_to_module(path) do
    # Convert lib/foo/bar.ex to Foo.Bar
    cond do
      String.starts_with?(path, "lib/") ->
        path
        |> String.trim_leading("lib/")
        |> String.trim_trailing(".ex")
        |> String.split("/")
        |> Enum.map(&Macro.camelize/1)
        |> Enum.join(".")

      true ->
        nil
    end
  end
end
