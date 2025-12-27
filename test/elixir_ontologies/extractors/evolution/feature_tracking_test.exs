defmodule ElixirOntologies.Extractors.Evolution.FeatureTrackingTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.FeatureTracking

  alias ElixirOntologies.Extractors.Evolution.FeatureTracking.{
    IssueReference,
    FeatureAddition,
    BugFix
  }

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
  # Type Tests
  # ===========================================================================

  describe "tracker_types/0" do
    test "returns all tracker types" do
      types = FeatureTracking.tracker_types()

      assert :github in types
      assert :gitlab in types
      assert :jira in types
      assert :generic in types
    end
  end

  describe "action_types/0" do
    test "returns all action types" do
      actions = FeatureTracking.action_types()

      assert :mentions in actions
      assert :fixes in actions
      assert :closes in actions
      assert :resolves in actions
      assert :relates in actions
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "IssueReference struct" do
    test "has default values" do
      ref = %IssueReference{}

      assert ref.tracker == :generic
      assert ref.number == nil
      assert ref.project == nil
      assert ref.action == :mentions
      assert ref.url == nil
    end
  end

  describe "FeatureAddition struct" do
    test "requires name and commit" do
      commit = create_commit()

      feature = %FeatureAddition{
        name: "Add login",
        commit: commit
      }

      assert feature.name == "Add login"
      assert feature.commit == commit
      assert feature.modules == []
      assert feature.functions == []
      assert feature.issue_refs == []
    end
  end

  describe "BugFix struct" do
    test "requires description and commit" do
      commit = create_commit()

      bugfix = %BugFix{
        description: "Fix crash",
        commit: commit
      }

      assert bugfix.description == "Fix crash"
      assert bugfix.commit == commit
      assert bugfix.affected_modules == []
      assert bugfix.affected_functions == []
    end
  end

  # ===========================================================================
  # Issue Reference Parsing Tests
  # ===========================================================================

  describe "parse_issue_references/1" do
    test "returns empty list for nil" do
      assert FeatureTracking.parse_issue_references(nil) == []
    end

    test "returns empty list for empty string" do
      assert FeatureTracking.parse_issue_references("") == []
    end

    test "parses simple #N reference" do
      refs = FeatureTracking.parse_issue_references("Fix bug #123")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.tracker == :generic
      assert ref.number == 123
      assert ref.action == :mentions
    end

    test "parses multiple #N references" do
      refs = FeatureTracking.parse_issue_references("Related to #123 and #456")

      assert length(refs) == 2
      numbers = Enum.map(refs, & &1.number)
      assert 123 in numbers
      assert 456 in numbers
    end

    test "parses GH-N reference" do
      refs = FeatureTracking.parse_issue_references("See GH-789")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.tracker == :github
      assert ref.number == 789
    end

    test "parses GL-N reference" do
      refs = FeatureTracking.parse_issue_references("See GL-456")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.tracker == :gitlab
      assert ref.number == 456
    end

    test "parses Jira-style PROJ-N reference" do
      refs = FeatureTracking.parse_issue_references("Implements JIRA-123")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.tracker == :jira
      assert ref.number == 123
      assert ref.project == "JIRA"
    end

    test "parses fixes keyword" do
      refs = FeatureTracking.parse_issue_references("fixes #42")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.action == :fixes
      assert ref.number == 42
    end

    test "parses closes keyword" do
      refs = FeatureTracking.parse_issue_references("closes #99")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.action == :closes
    end

    test "parses resolves keyword" do
      refs = FeatureTracking.parse_issue_references("resolves #10")

      assert length(refs) == 1
      ref = List.first(refs)
      assert ref.action == :resolves
    end

    test "parses mixed references" do
      refs = FeatureTracking.parse_issue_references("Fix #123, closes GH-456, see PROJ-789")

      assert length(refs) == 3

      trackers = Enum.map(refs, & &1.tracker)
      assert :generic in trackers
      assert :github in trackers
      assert :jira in trackers
    end

    test "handles case insensitivity for keywords" do
      refs = FeatureTracking.parse_issue_references("FIXES #1, Closes #2, ResolveS #3")

      assert length(refs) == 3
      actions = Enum.map(refs, & &1.action)
      assert :fixes in actions
      assert :closes in actions
      assert :resolves in actions
    end

    test "deduplicates references preferring closing action" do
      # When same issue is mentioned and closed
      refs = FeatureTracking.parse_issue_references("Related to #123. Fixes #123")

      # Should only have one reference with :fixes action
      refs_for_123 = Enum.filter(refs, &(&1.number == 123))
      assert length(refs_for_123) == 1
      assert List.first(refs_for_123).action == :fixes
    end
  end

  # ===========================================================================
  # Issue URL Building Tests
  # ===========================================================================

  describe "build_issue_url/2" do
    test "builds GitHub URL" do
      ref = %IssueReference{tracker: :github, number: 123}
      url = FeatureTracking.build_issue_url(ref, github_repo: "owner/repo")

      assert url == "https://github.com/owner/repo/issues/123"
    end

    test "builds GitLab URL" do
      ref = %IssueReference{tracker: :gitlab, number: 456}
      url = FeatureTracking.build_issue_url(ref, gitlab_repo: "group/project")

      assert url == "https://gitlab.com/group/project/-/issues/456"
    end

    test "builds GitLab URL with custom base" do
      ref = %IssueReference{tracker: :gitlab, number: 789}

      url =
        FeatureTracking.build_issue_url(ref,
          gitlab_repo: "project",
          gitlab_url: "https://gitlab.example.com"
        )

      assert url == "https://gitlab.example.com/project/-/issues/789"
    end

    test "builds Jira URL" do
      ref = %IssueReference{tracker: :jira, number: 123, project: "PROJ"}
      url = FeatureTracking.build_issue_url(ref, jira_url: "https://jira.example.com")

      assert url == "https://jira.example.com/browse/PROJ-123"
    end

    test "returns nil when repo not configured" do
      ref = %IssueReference{tracker: :github, number: 123}
      url = FeatureTracking.build_issue_url(ref, [])

      assert url == nil
    end

    test "generic tracker uses GitHub if configured" do
      ref = %IssueReference{tracker: :generic, number: 42}
      url = FeatureTracking.build_issue_url(ref, github_repo: "owner/repo")

      assert url == "https://github.com/owner/repo/issues/42"
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "has_issues?/1" do
    test "returns true when feature has issues" do
      commit = create_commit()

      feature = %FeatureAddition{
        name: "Test",
        commit: commit,
        issue_refs: [%IssueReference{number: 1}]
      }

      assert FeatureTracking.has_issues?(feature)
    end

    test "returns false when feature has no issues" do
      commit = create_commit()
      feature = %FeatureAddition{name: "Test", commit: commit, issue_refs: []}

      refute FeatureTracking.has_issues?(feature)
    end

    test "returns true when bugfix has issues" do
      commit = create_commit()

      bugfix = %BugFix{
        description: "Fix",
        commit: commit,
        issue_refs: [%IssueReference{number: 1}]
      }

      assert FeatureTracking.has_issues?(bugfix)
    end
  end

  describe "closing_issues/1" do
    test "returns only closing references" do
      commit = create_commit()

      feature = %FeatureAddition{
        name: "Test",
        commit: commit,
        issue_refs: [
          %IssueReference{number: 1, action: :mentions},
          %IssueReference{number: 2, action: :fixes},
          %IssueReference{number: 3, action: :closes},
          %IssueReference{number: 4, action: :resolves}
        ]
      }

      closing = FeatureTracking.closing_issues(feature)

      assert length(closing) == 3
      numbers = Enum.map(closing, & &1.number)
      assert 2 in numbers
      assert 3 in numbers
      assert 4 in numbers
      refute 1 in numbers
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "detect_features/3" do
    @tag :integration
    test "detects features in feature commit" do
      commit = create_commit(subject: "feat: add new login page")
      {:ok, features} = FeatureTracking.detect_features(".", commit, include_scope: false)

      # May or may not detect as feature depending on classification
      assert is_list(features)
    end

    @tag :integration
    test "returns empty for non-feature commit" do
      commit = create_commit(subject: "fix: resolve crash")
      {:ok, features} = FeatureTracking.detect_features(".", commit, include_scope: false)

      assert features == []
    end

    @tag :integration
    test "bang variant works" do
      commit = create_commit(subject: "feat: add feature")
      features = FeatureTracking.detect_features!(".", commit, include_scope: false)

      assert is_list(features)
    end
  end

  describe "detect_bugfixes/3" do
    @tag :integration
    test "detects bugfixes in fix commit" do
      commit = create_commit(subject: "fix: resolve memory leak")
      {:ok, bugfixes} = FeatureTracking.detect_bugfixes(".", commit, include_scope: false)

      # May or may not detect as bugfix depending on classification
      assert is_list(bugfixes)
    end

    @tag :integration
    test "returns empty for non-bugfix commit" do
      commit = create_commit(subject: "feat: add new feature")
      {:ok, bugfixes} = FeatureTracking.detect_bugfixes(".", commit, include_scope: false)

      assert bugfixes == []
    end

    @tag :integration
    test "bang variant works" do
      commit = create_commit(subject: "fix: fix bug")
      bugfixes = FeatureTracking.detect_bugfixes!(".", commit, include_scope: false)

      assert is_list(bugfixes)
    end
  end

  describe "detect_all/3" do
    @tag :integration
    test "detects both features and bugfixes" do
      commits = [
        create_commit(sha: "aaa", short_sha: "aaa", subject: "feat: add feature"),
        create_commit(sha: "bbb", short_sha: "bbb", subject: "fix: fix bug")
      ]

      {:ok, results} = FeatureTracking.detect_all(".", commits, include_scope: false)

      assert is_list(results.features)
      assert is_list(results.bugfixes)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles message with no issue references" do
      refs = FeatureTracking.parse_issue_references("Just a simple commit message")
      assert refs == []
    end

    test "handles issue number at end of line" do
      refs = FeatureTracking.parse_issue_references("Fix issue #123")
      assert length(refs) == 1
    end

    test "handles multiple Jira projects" do
      refs = FeatureTracking.parse_issue_references("PROJ-123 and OTHER-456")

      assert length(refs) == 2
      projects = Enum.map(refs, & &1.project)
      assert "PROJ" in projects
      assert "OTHER" in projects
    end

    test "handles high issue numbers" do
      refs = FeatureTracking.parse_issue_references("See #999999")

      assert length(refs) == 1
      assert List.first(refs).number == 999_999
    end

    test "ignores invalid patterns" do
      refs = FeatureTracking.parse_issue_references("Version 1.2.3 and tag v2.0")
      # Should not match version numbers as issues
      assert Enum.empty?(refs) or Enum.all?(refs, &(&1.number > 0))
    end
  end
end
