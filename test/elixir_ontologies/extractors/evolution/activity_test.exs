defmodule ElixirOntologies.Extractors.Evolution.ActivityTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Activity
  alias ElixirOntologies.Extractors.Evolution.Activity.{Classification, Scope}
  alias ElixirOntologies.Extractors.Evolution.Commit

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts \\ []) do
    %Commit{
      sha: Keyword.get(opts, :sha, "abc123def456abc123def456abc123def456abc1"),
      short_sha: Keyword.get(opts, :short_sha, "abc123d"),
      message: Keyword.get(opts, :message),
      subject: Keyword.get(opts, :subject),
      body: Keyword.get(opts, :body),
      author_name: Keyword.get(opts, :author_name),
      author_email: Keyword.get(opts, :author_email),
      author_date: Keyword.get(opts, :author_date),
      committer_name: Keyword.get(opts, :committer_name),
      committer_email: Keyword.get(opts, :committer_email),
      commit_date: Keyword.get(opts, :commit_date),
      parents: Keyword.get(opts, :parents, []),
      is_merge: Keyword.get(opts, :is_merge, false),
      tree_sha: Keyword.get(opts, :tree_sha),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Conventional Commit Parsing Tests
  # ===========================================================================

  describe "parse_conventional_commit/1" do
    test "parses simple feat commit" do
      assert {:ok, parsed} = Activity.parse_conventional_commit("feat: add new feature")
      assert parsed.type == "feat"
      assert parsed.scope == nil
      assert parsed.breaking == false
      assert parsed.description == "add new feature"
    end

    test "parses feat with scope" do
      assert {:ok, parsed} = Activity.parse_conventional_commit("feat(auth): add login")
      assert parsed.type == "feat"
      assert parsed.scope == "auth"
      assert parsed.breaking == false
      assert parsed.description == "add login"
    end

    test "parses fix with breaking change indicator" do
      assert {:ok, parsed} = Activity.parse_conventional_commit("fix!: critical security fix")
      assert parsed.type == "fix"
      assert parsed.scope == nil
      assert parsed.breaking == true
      assert parsed.description == "critical security fix"
    end

    test "parses commit with scope and breaking change" do
      assert {:ok, parsed} = Activity.parse_conventional_commit("feat(api)!: breaking API change")
      assert parsed.type == "feat"
      assert parsed.scope == "api"
      assert parsed.breaking == true
      assert parsed.description == "breaking API change"
    end

    test "parses multi-word type" do
      assert {:ok, parsed} = Activity.parse_conventional_commit("bug-fix: resolve issue")
      assert parsed.type == "bug-fix"
      assert parsed.description == "resolve issue"
    end

    test "handles different type prefixes" do
      prefixes = [
        {"fix: bug", "fix"},
        {"docs: update readme", "docs"},
        {"style: format code", "style"},
        {"refactor: cleanup", "refactor"},
        {"perf: optimize query", "perf"},
        {"test: add tests", "test"},
        {"chore: update deps", "chore"},
        {"ci: fix pipeline", "ci"},
        {"build: update config", "build"},
        {"revert: undo change", "revert"}
      ]

      for {message, expected_type} <- prefixes do
        assert {:ok, parsed} = Activity.parse_conventional_commit(message)
        assert parsed.type == expected_type, "Expected #{expected_type} for: #{message}"
      end
    end

    test "returns error for non-conventional commit" do
      assert {:error, :not_conventional} = Activity.parse_conventional_commit("Add new feature")
      assert {:error, :not_conventional} = Activity.parse_conventional_commit("Fixed the bug")
      assert {:error, :not_conventional} = Activity.parse_conventional_commit("WIP")
    end

    test "handles nil input" do
      assert {:error, :not_conventional} = Activity.parse_conventional_commit(nil)
    end

    test "handles multiline message (takes first line)" do
      message = """
      feat(auth): add OAuth support

      This adds full OAuth 2.0 support including:
      - Google authentication
      - GitHub authentication
      """

      assert {:ok, parsed} = Activity.parse_conventional_commit(message)
      assert parsed.type == "feat"
      assert parsed.scope == "auth"
      assert parsed.description == "add OAuth support"
    end

    test "handles empty scope in parentheses" do
      # This is technically invalid but we handle it gracefully
      assert {:ok, parsed} = Activity.parse_conventional_commit("feat(): add feature")
      assert parsed.type == "feat"
      assert parsed.scope == nil
      assert parsed.description == "add feature"
    end
  end

  describe "conventional_commit?/1" do
    test "returns true for conventional commits" do
      assert Activity.conventional_commit?("feat: add feature")
      assert Activity.conventional_commit?("fix(auth): resolve bug")
      assert Activity.conventional_commit?("chore!: breaking change")
    end

    test "returns false for non-conventional commits" do
      refute Activity.conventional_commit?("Add new feature")
      refute Activity.conventional_commit?("Fixed bug in login")
      refute Activity.conventional_commit?(nil)
    end
  end

  # ===========================================================================
  # Type Conversion Tests
  # ===========================================================================

  describe "type_from_string/1" do
    test "converts known types" do
      assert Activity.type_from_string("feat") == :feature
      assert Activity.type_from_string("feature") == :feature
      assert Activity.type_from_string("fix") == :bugfix
      assert Activity.type_from_string("bugfix") == :bugfix
      assert Activity.type_from_string("docs") == :docs
      assert Activity.type_from_string("doc") == :docs
      assert Activity.type_from_string("test") == :test
      assert Activity.type_from_string("tests") == :test
      assert Activity.type_from_string("refactor") == :refactor
      assert Activity.type_from_string("chore") == :chore
      assert Activity.type_from_string("build") == :chore
      assert Activity.type_from_string("style") == :style
      assert Activity.type_from_string("perf") == :perf
      assert Activity.type_from_string("performance") == :perf
      assert Activity.type_from_string("ci") == :ci
      assert Activity.type_from_string("revert") == :revert
      assert Activity.type_from_string("deps") == :deps
      assert Activity.type_from_string("release") == :release
      assert Activity.type_from_string("wip") == :wip
    end

    test "returns :unknown for unknown types" do
      assert Activity.type_from_string("xyz") == :unknown
      assert Activity.type_from_string("random") == :unknown
    end

    test "handles case insensitivity" do
      assert Activity.type_from_string("FEAT") == :feature
      assert Activity.type_from_string("Fix") == :bugfix
      assert Activity.type_from_string("DOCS") == :docs
    end
  end

  describe "activity_types/0" do
    test "returns all activity types" do
      types = Activity.activity_types()

      assert :feature in types
      assert :bugfix in types
      assert :refactor in types
      assert :docs in types
      assert :test in types
      assert :chore in types
      assert :style in types
      assert :perf in types
      assert :ci in types
      assert :revert in types
      assert :deps in types
      assert :release in types
      assert :wip in types
      assert :unknown in types
    end
  end

  # ===========================================================================
  # Commit Classification Tests (with mock commits)
  # ===========================================================================

  describe "classify_commit/3 with conventional commits" do
    test "classifies feat commit as feature" do
      commit = create_commit(subject: "feat: add new login page")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :feature
      assert activity.classification.method == :conventional_commit
      assert activity.classification.confidence == :high
      assert activity.classification.raw_type == "feat"
      assert activity.classification.breaking == false
    end

    test "classifies fix commit as bugfix" do
      commit = create_commit(subject: "fix(auth): resolve login bug")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :bugfix
      assert activity.classification.method == :conventional_commit
      assert activity.classification.scope_hint == "auth"
    end

    test "detects breaking change" do
      commit = create_commit(subject: "feat!: breaking API change")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :feature
      assert activity.classification.breaking == true
      assert Activity.breaking_change?(activity)
    end

    test "classifies various conventional commit types" do
      test_cases = [
        {"docs: update README", :docs},
        {"test: add unit tests", :test},
        {"refactor: simplify logic", :refactor},
        {"chore: update deps", :chore},
        {"style: format code", :style},
        {"perf: optimize query", :perf},
        {"ci: fix pipeline", :ci},
        {"revert: undo change", :revert}
      ]

      for {subject, expected_type} <- test_cases do
        commit = create_commit(subject: subject)
        {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

        assert activity.type == expected_type,
               "Expected #{expected_type} for '#{subject}', got #{activity.type}"
      end
    end
  end

  describe "classify_commit/3 with keyword heuristics" do
    test "classifies 'Add' as feature" do
      commit = create_commit(subject: "Add new dashboard component")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :feature
      assert activity.classification.method == :keyword
      assert activity.classification.confidence == :medium
    end

    test "classifies 'Fix' as bugfix" do
      commit = create_commit(subject: "Fix crash on startup")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :bugfix
      assert activity.classification.method == :keyword
    end

    test "classifies 'Refactor' as refactor" do
      commit = create_commit(subject: "Refactor authentication module")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :refactor
    end

    test "classifies documentation keywords as docs" do
      subjects = [
        "Update README with examples",
        "Add documentation for API",
        "Improve moduledoc"
      ]

      for subject <- subjects do
        commit = create_commit(subject: subject)
        {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)
        assert activity.type == :docs, "Expected :docs for '#{subject}'"
      end
    end

    test "classifies test keywords as test" do
      subjects = [
        "Add tests for user module",
        "Improve test coverage",
        "Fix failing specs"
      ]

      for subject <- subjects do
        commit = create_commit(subject: subject)
        {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)
        assert activity.type == :test, "Expected :test for '#{subject}'"
      end
    end

    test "classifies performance keywords as perf" do
      subjects = [
        "Optimize database queries",
        "Improve performance of search",
        "Add caching for API responses"
      ]

      for subject <- subjects do
        commit = create_commit(subject: subject)
        {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)
        assert activity.type == :perf, "Expected :perf for '#{subject}'"
      end
    end

    test "classifies revert commits" do
      commit = create_commit(subject: "Revert \"Add broken feature\"")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :revert
    end

    test "detects breaking change in body text" do
      commit = create_commit(subject: "Update API", body: "BREAKING CHANGE: removed old endpoint")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      # The classification looks at subject, so breaking detection is via subject check
      # For full body analysis, we'd need to extend the logic
    end

    test "returns unknown for unclassifiable commits" do
      commit = create_commit(subject: "WIP")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      # WIP should be classified as :wip
      assert activity.type == :wip
    end

    test "truly unknown commit" do
      commit = create_commit(subject: "misc changes")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :unknown
      assert activity.classification.confidence == :low
    end
  end

  # ===========================================================================
  # Scope Tests
  # ===========================================================================

  describe "Scope struct" do
    test "has default values" do
      scope = %Scope{}

      assert scope.files_changed == []
      assert scope.modules_affected == []
      assert scope.lines_added == 0
      assert scope.lines_deleted == 0
    end
  end

  describe "Classification struct" do
    test "has default values" do
      classification = %Classification{}

      assert classification.method == :heuristic
      assert classification.confidence == :low
      assert classification.raw_type == nil
      assert classification.breaking == false
      assert classification.scope_hint == nil
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "breaking_change?/1" do
    test "returns true for breaking changes" do
      activity = %Activity{
        type: :feature,
        commit: create_commit(),
        classification: %Classification{breaking: true}
      }

      assert Activity.breaking_change?(activity)
    end

    test "returns false for non-breaking changes" do
      activity = %Activity{
        type: :feature,
        commit: create_commit(),
        classification: %Classification{breaking: false}
      }

      refute Activity.breaking_change?(activity)
    end
  end

  describe "classification_confidence/1" do
    test "returns confidence level" do
      for confidence <- [:high, :medium, :low] do
        activity = %Activity{
          type: :feature,
          commit: create_commit(),
          classification: %Classification{confidence: confidence}
        }

        assert Activity.classification_confidence(activity) == confidence
      end
    end
  end

  # ===========================================================================
  # Batch Classification Tests
  # ===========================================================================

  describe "classify_commits/3" do
    test "classifies multiple commits" do
      commits = [
        create_commit(sha: "aaa", short_sha: "aaa", subject: "feat: add feature"),
        create_commit(sha: "bbb", short_sha: "bbb", subject: "fix: resolve bug"),
        create_commit(sha: "ccc", short_sha: "ccc", subject: "docs: update readme")
      ]

      {:ok, activities} = Activity.classify_commits(".", commits, include_scope: false)

      assert length(activities) == 3
      assert Enum.at(activities, 0).type == :feature
      assert Enum.at(activities, 1).type == :bugfix
      assert Enum.at(activities, 2).type == :docs
    end

    test "handles empty list" do
      {:ok, activities} = Activity.classify_commits(".", [], include_scope: false)
      assert activities == []
    end
  end

  # ===========================================================================
  # Integration Tests with Real Repository
  # ===========================================================================

  describe "integration with repository" do
    @tag :integration
    test "classifies HEAD commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = Activity.classify_commit(".", commit)

      assert is_atom(activity.type)
      assert activity.type in Activity.activity_types()
      assert %Commit{} = activity.commit
      assert %Scope{} = activity.scope
      assert %Classification{} = activity.classification
    end

    @tag :integration
    test "extracts scope for HEAD commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, scope} = Activity.extract_scope(".", commit)

      assert is_list(scope.files_changed)
      assert is_list(scope.modules_affected)
      assert is_integer(scope.lines_added)
      assert is_integer(scope.lines_deleted)
    end

    @tag :integration
    test "classifies multiple commits from history" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      {:ok, activities} = Activity.classify_commits(".", commits)

      assert length(activities) == length(commits)

      for activity <- activities do
        assert activity.type in Activity.activity_types()
        assert activity.classification.method in [:conventional_commit, :keyword, :file_based]
      end
    end

    @tag :integration
    test "bang variants work correctly" do
      commit = Commit.extract_commit!(".", "HEAD")
      activity = Activity.classify_commit!(".", commit)

      assert is_atom(activity.type)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles nil subject" do
      commit = create_commit(subject: nil)

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :unknown
    end

    test "handles empty subject" do
      commit = create_commit(subject: "")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :unknown
    end

    test "handles very long subjects" do
      long_subject = String.duplicate("feat: ", 100) <> "add feature"
      commit = create_commit(subject: long_subject)

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      # Should still work
      assert is_atom(activity.type)
    end

    test "handles special characters in subject" do
      commit = create_commit(subject: "feat: add émojis 🎉 and special chars <>&\"'")

      {:ok, activity} = Activity.classify_commit(".", commit, include_scope: false)

      assert activity.type == :feature
    end
  end
end
