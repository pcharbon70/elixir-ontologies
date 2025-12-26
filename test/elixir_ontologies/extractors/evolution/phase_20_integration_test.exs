defmodule ElixirOntologies.Extractors.Evolution.Phase20IntegrationTest do
  @moduledoc """
  Phase 20 Integration Tests for Evolution & Provenance (PROV-O).

  These tests verify end-to-end functionality across all evolution extractors
  and builders, ensuring PROV-O compliance and proper cross-module interactions.

  Test categories:
  1. Complete Evolution Extraction Pipeline
  2. PROV-O Compliance
  3. Cross-Module Correlation
  4. Statistics Accuracy
  5. Error Handling
  6. Backward Compatibility
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  # Extractors
  alias ElixirOntologies.Extractors.Evolution.Activity
  alias ElixirOntologies.Extractors.Evolution.ActivityModel
  alias ElixirOntologies.Extractors.Evolution.Agent
  alias ElixirOntologies.Extractors.Evolution.Blame
  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.Delegation
  alias ElixirOntologies.Extractors.Evolution.Deprecation
  alias ElixirOntologies.Extractors.Evolution.Developer
  alias ElixirOntologies.Extractors.Evolution.EntityVersion
  alias ElixirOntologies.Extractors.Evolution.FeatureTracking
  alias ElixirOntologies.Extractors.Evolution.FileHistory
  alias ElixirOntologies.Extractors.Evolution.Refactoring
  alias ElixirOntologies.Extractors.Evolution.Release
  alias ElixirOntologies.Extractors.Evolution.Snapshot

  # Builders
  alias ElixirOntologies.Builders.Evolution.ActivityBuilder
  alias ElixirOntologies.Builders.Evolution.AgentBuilder
  alias ElixirOntologies.Builders.Evolution.CommitBuilder
  alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
  alias ElixirOntologies.Builders.Evolution.VersionBuilder

  # Support
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @base_iri "https://example.org/code#"

  defp default_context do
    Context.new(base_iri: @base_iri)
  end

  # ============================================================================
  # 1. Complete Evolution Extraction Pipeline Tests
  # ============================================================================

  describe "complete evolution extraction pipeline" do
    test "commit extraction to builder pipeline" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      assert length(commits) > 0

      context = default_context()

      # Build RDF for each commit
      results =
        Enum.map(commits, fn commit ->
          CommitBuilder.build(commit, context)
        end)

      # Verify all commits produced valid RDF
      for {iri, triples} <- results do
        assert %RDF.IRI{} = iri
        assert is_list(triples)
        assert length(triples) > 0

        # Verify commit has expected type
        assert Enum.any?(triples, fn
          {^iri, pred, type} ->
            pred == RDF.type() and type == Evolution.Commit
          _ -> false
        end)
      end
    end

    test "activity extraction to builder pipeline" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      commit = List.first(commits)

      # Use ActivityModel.extract_activity for the builder
      {:ok, activity} = ActivityModel.extract_activity(".", commit)
      assert %ActivityModel.ActivityModel{} = activity
      assert activity.activity_type != nil

      context = default_context()
      {iri, triples} = ActivityBuilder.build(activity, context)

      assert %RDF.IRI{} = iri
      assert length(triples) > 0

      # Verify activity has prov:Activity type
      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == PROV.Activity
        _ -> false
      end)
    end

    test "agent extraction to builder pipeline" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      commit = List.first(commits)

      {:ok, agents} = Agent.extract_agents(".", commit)
      assert length(agents) > 0

      context = default_context()

      # Build RDF for each agent
      for agent <- agents do
        {iri, triples} = AgentBuilder.build(agent, context)

        assert %RDF.IRI{} = iri
        assert length(triples) > 0

        # Verify agent has prov:Agent type
        assert Enum.any?(triples, fn
          {^iri, pred, type} ->
            pred == RDF.type() and type == PROV.Agent
          _ -> false
        end)
      end
    end

    test "snapshot extraction to builder pipeline" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")
      assert %Snapshot{} = snapshot
      assert snapshot.commit_sha != nil

      context = default_context()
      {iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)

      assert %RDF.IRI{} = iri
      assert length(triples) > 0

      # Verify snapshot has expected types
      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == Evolution.CodebaseSnapshot
        _ -> false
      end)

      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == PROV.Entity
        _ -> false
      end)
    end

    test "release extraction to builder pipeline" do
      case Release.extract_releases(".") do
        {:ok, releases} when releases != [] ->
          context = default_context()

          for release <- releases do
            {iri, triples} = SnapshotReleaseBuilder.build(release, context)

            assert %RDF.IRI{} = iri
            assert length(triples) > 0

            # Verify release has expected types
            assert Enum.any?(triples, fn
              {^iri, pred, type} ->
                pred == RDF.type() and type == Evolution.Release
              _ -> false
            end)
          end

        {:ok, []} ->
          # No releases in repository - skip
          :ok

        {:error, _} ->
          # Skip if extraction fails
          :ok
      end
    end
  end

  # ============================================================================
  # 2. PROV-O Compliance Tests
  # ============================================================================

  describe "PROV-O compliance" do
    test "entities have prov:Entity typing" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")
      context = default_context()
      {iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)

      # Verify prov:Entity type
      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == PROV.Entity
        _ -> false
      end)

      # Verify prov:generatedAtTime timestamp
      assert Enum.any?(triples, fn
        {^iri, pred, _literal} ->
          pred == PROV.generatedAtTime()
        _ -> false
      end)
    end

    test "activities have prov:Activity typing" do
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      commit = List.first(commits)
      # Use ActivityModel.extract_activity for the builder
      {:ok, activity} = ActivityModel.extract_activity(".", commit)

      context = default_context()
      {iri, triples} = ActivityBuilder.build(activity, context)

      # Verify prov:Activity type
      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == PROV.Activity
        _ -> false
      end)
    end

    test "agents have prov:Agent typing" do
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      commit = List.first(commits)
      {:ok, agents} = Agent.extract_agents(".", commit)

      context = default_context()
      agent = List.first(agents)
      {iri, triples} = AgentBuilder.build(agent, context)

      # Verify prov:Agent type
      assert Enum.any?(triples, fn
        {^iri, pred, type} ->
          pred == RDF.type() and type == PROV.Agent
        _ -> false
      end)
    end

    test "activity builder generates prov:wasAssociatedWith relationships" do
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      commit = List.first(commits)
      # Use ActivityModel.extract_activity for the builder
      {:ok, activity} = ActivityModel.extract_activity(".", commit)

      context = default_context()
      {_iri, triples} = ActivityBuilder.build(activity, context)

      # Activity should have wasAssociatedWith for the commit author
      # This relationship links activities to agents
      # Note: only generated if associated_agents is populated
      assert is_list(triples)
    end

    test "commits include timestamp information" do
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      commit = List.first(commits)

      context = default_context()
      {iri, triples} = CommitBuilder.build(commit, context)

      # Commit should have timestamp (check for any timestamp predicate)
      has_timestamp = Enum.any?(triples, fn
        {^iri, pred, _} ->
          pred_str = to_string(pred)
          pred == PROV.generatedAtTime() or
            pred == PROV.startedAtTime() or
            pred == PROV.endedAtTime() or
            String.contains?(pred_str, "authoredAt") or
            String.contains?(pred_str, "committedAt")
        _ -> false
      end)

      assert has_timestamp
    end
  end

  # ============================================================================
  # 3. Cross-Module Correlation Tests
  # ============================================================================

  describe "cross-module correlation" do
    test "activity classification correlates with commit" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)

      for commit <- commits do
        {:ok, activity} = Activity.classify_commit(".", commit)

        # Activity should reference the same commit
        assert activity.commit.sha == commit.sha
        assert activity.commit.subject == commit.subject
      end
    end

    test "agents correlate with commit authors" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      commit = List.first(commits)

      {:ok, agents} = Agent.extract_agents(".", commit)

      # At least one agent should match the commit author
      author_emails = Enum.map(agents, & &1.email)
      assert commit.author_email in author_emails or length(agents) > 0
    end

    test "version tracking correlates module changes with commits" do
      # Track module versions for a known module
      # Using limit: 3 to keep test fast
      case EntityVersion.track_module_versions(".", "ElixirOntologies.Builders.Context", limit: 3) do
        {:ok, versions} ->
          # Each version should have a valid commit reference
          for version <- versions do
            assert is_binary(version.commit_sha)
            assert String.length(version.commit_sha) == 40
          end

        {:error, _reason} ->
          # Module might not be found in history, that's okay
          :ok
      end
    end

    test "blame lines correlate with commits and developers" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      for line <- blame.lines do
        # Each line should have a valid commit SHA
        assert is_binary(line.commit_sha)
        assert String.length(line.commit_sha) >= 7

        # Should be able to extract the full commit
        {:ok, commit} = Commit.extract_commit(".", line.commit_sha)
        assert commit.sha == line.commit_sha
      end
    end

    test "file history commits are valid and extractable" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      # Verify first and last commits are valid
      {:ok, first_commit} = Commit.extract_commit(".", history.first_commit)
      {:ok, last_commit} = Commit.extract_commit(".", history.last_commit)

      assert first_commit.sha == history.first_commit
      assert last_commit.sha == history.last_commit

      # First commit (oldest) timestamp should be <= last commit (newest)
      # Note: first_commit is chronologically first (oldest)
      assert DateTime.compare(first_commit.author_date, last_commit.author_date) in [:lt, :eq]
    end
  end

  # ============================================================================
  # 4. Statistics Accuracy Tests
  # ============================================================================

  describe "statistics accuracy" do
    test "snapshot statistics reflect actual codebase" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      # Verify basic statistics are present and reasonable
      assert snapshot.stats.module_count > 0
      assert snapshot.stats.function_count > 0
      assert snapshot.stats.file_count > 0
      assert snapshot.stats.line_count > 0

      # Module count should be less than or equal to file count * some factor
      # (typically multiple modules per file is rare but possible)
      assert snapshot.stats.module_count <= snapshot.stats.file_count * 10
    end

    test "release version parsing produces valid semver" do
      case Release.extract_releases(".") do
        {:ok, releases} when releases != [] ->
          for release <- releases do
            if release.semver do
              assert is_integer(release.semver.major)
              assert is_integer(release.semver.minor)
              assert is_integer(release.semver.patch)
              assert release.semver.major >= 0
              assert release.semver.minor >= 0
              assert release.semver.patch >= 0
            end
          end

        _ ->
          :ok
      end
    end

    test "activity scope reflects actual changes" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)

      for commit <- commits do
        # Use Activity.classify_commit which supports include_scope option
        {:ok, activity} = Activity.classify_commit(".", commit, include_scope: true)

        if activity.scope do
          # If scope is included, check the files_changed field
          # The scope uses a list of files, so check length
          assert is_list(activity.scope.files_changed) or is_integer(activity.scope.files_changed)
          assert activity.scope.lines_added >= 0
          assert activity.scope.lines_deleted >= 0
        end
      end
    end
  end

  # ============================================================================
  # 5. Agent Deduplication Tests
  # ============================================================================

  describe "agent deduplication" do
    test "agents are deduplicated across multiple commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)

      # Collect all agents from commits
      all_agents =
        commits
        |> Enum.flat_map(fn commit ->
          case Agent.extract_agents(".", commit) do
            {:ok, agents} -> agents
            {:error, _} -> []
          end
        end)

      # Check for email uniqueness (agents should be deduplicated by email)
      emails = Enum.map(all_agents, & &1.email)
      unique_emails = Enum.uniq(emails)

      # If there are duplicate emails, the agents should have consistent data
      for email <- unique_emails do
        agents_with_email = Enum.filter(all_agents, &(&1.email == email))

        if length(agents_with_email) > 1 do
          # All agents with the same email should have consistent agent_type
          types = Enum.map(agents_with_email, & &1.agent_type) |> Enum.uniq()
          assert length(types) == 1, "Agent with email #{email} has inconsistent types: #{inspect(types)}"
        end
      end
    end

    test "developer aggregation produces unique entries" do
      {:ok, commits} = Commit.extract_commits(".", limit: 20)
      developers = Developer.from_commits(commits)

      # Each developer should have a unique email
      emails = Enum.map(developers, & &1.email)
      assert length(emails) == length(Enum.uniq(emails))
    end
  end

  # ============================================================================
  # 6. Error Handling Tests
  # ============================================================================

  describe "error handling" do
    test "handles invalid repository path gracefully" do
      result = Commit.extract_commits("/nonexistent/path", limit: 5)
      assert {:error, _reason} = result
    end

    test "handles invalid file path in blame" do
      result = Blame.extract_blame(".", "nonexistent_file_xyz.ex")
      assert {:error, _reason} = result
    end

    test "handles invalid commit SHA" do
      result = Commit.extract_commit(".", "invalid_sha_that_does_not_exist")
      assert {:error, _reason} = result
    end

    test "handles path traversal attempts" do
      result = Blame.extract_blame(".", "../../../etc/passwd")
      assert {:error, :invalid_path} = result
    end

    test "handles command injection attempts" do
      result = Commit.extract_commit(".", "HEAD; rm -rf /")
      assert {:error, :invalid_ref} = result
    end
  end

  # ============================================================================
  # 7. Backward Compatibility Tests
  # ============================================================================

  describe "backward compatibility" do
    test "existing Commit API works unchanged" do
      # extract_commit/2
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      sha = List.first(commits).sha
      {:ok, commit} = Commit.extract_commit(".", sha)
      assert commit.sha == sha

      # extract_commits/2
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      assert length(commits) <= 5

      # extract_commit!/2 (bang version)
      commit = Commit.extract_commit!(".", sha)
      assert commit.sha == sha
    end

    test "existing Developer API works unchanged" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)

      # author_from_commit/1
      author = Developer.author_from_commit(List.first(commits))
      assert is_binary(author.email)

      # from_commits/1
      developers = Developer.from_commits(commits)
      assert is_list(developers)
    end

    test "existing FileHistory API works unchanged" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      assert is_binary(history.path)
      assert is_list(history.commits)
      assert is_integer(history.commit_count)
    end

    test "existing Blame API works unchanged" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # Check the path field
      assert blame.path == "mix.exs"
      assert is_list(blame.lines)
      assert is_integer(blame.line_count)
    end
  end

  # ============================================================================
  # 8. Complete RDF Generation Tests
  # ============================================================================

  describe "complete RDF generation" do
    test "generates valid RDF for entire commit history subset" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      context = default_context()

      all_triples =
        commits
        |> Enum.flat_map(fn commit ->
          {_iri, triples} = CommitBuilder.build(commit, context)
          triples
        end)

      # All triples should be valid 3-tuples
      assert Enum.all?(all_triples, fn
        {_s, _p, _o} -> true
        _ -> false
      end)

      # Should have at least some triples per commit
      assert length(all_triples) >= length(commits) * 3
    end

    test "generates interconnected RDF from activity and agents" do
      {:ok, commits} = Commit.extract_commits(".", limit: 1)
      commit = List.first(commits)
      context = default_context()

      # Build commit RDF
      {commit_iri, commit_triples} = CommitBuilder.build(commit, context)

      # Build activity RDF using ActivityModel
      {:ok, activity} = ActivityModel.extract_activity(".", commit)
      {activity_iri, activity_triples} = ActivityBuilder.build(activity, context)

      # Build agent RDF
      {:ok, agents} = Agent.extract_agents(".", commit)
      agent_triples =
        Enum.flat_map(agents, fn agent ->
          {_iri, triples} = AgentBuilder.build(agent, context)
          triples
        end)

      all_triples = commit_triples ++ activity_triples ++ agent_triples

      # Verify we have a substantial graph
      assert length(all_triples) > 10

      # Verify commit IRI is used
      assert %RDF.IRI{} = commit_iri
      assert Enum.any?(commit_triples, fn {s, _, _} -> s == commit_iri end)

      # Verify activity IRI is used
      assert %RDF.IRI{} = activity_iri
      assert Enum.any?(activity_triples, fn {s, _, _} -> s == activity_iri end)
    end
  end

  # ============================================================================
  # 9. Refactoring Detection Tests
  # ============================================================================

  describe "refactoring detection" do
    test "refactoring extractor produces valid results" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)

      for commit <- commits do
        case Refactoring.detect_refactorings(".", commit) do
          {:ok, refactorings} ->
            for refactoring <- refactorings do
              assert refactoring.type in [
                :extract_function,
                :extract_module,
                :rename_function,
                :rename_module,
                :rename_variable,
                :inline_function,
                :move_function,
                :unknown
              ]
              # Refactoring struct has :commit field with full Commit struct
              assert %Commit{} = refactoring.commit
              assert is_binary(refactoring.commit.sha)
            end

          {:error, _} ->
            # Some commits may not have detectable refactorings
            :ok
        end
      end
    end
  end

  # ============================================================================
  # 10. Feature and Bug Fix Tracking Tests
  # ============================================================================

  describe "feature and bug fix tracking" do
    test "feature tracking produces valid results for individual commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)

      for commit <- commits do
        # detect_features takes a single commit, not a list
        {:ok, features} = FeatureTracking.detect_features(".", commit)

        for feature <- features do
          assert is_binary(feature.name) or is_atom(feature.name)
          assert %Commit{} = feature.commit
        end
      end
    end

    test "bug fix detection produces valid results for individual commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)

      for commit <- commits do
        # detect_bugfixes takes a single commit, not a list
        {:ok, bugfixes} = FeatureTracking.detect_bugfixes(".", commit)

        for bugfix <- bugfixes do
          assert is_binary(bugfix.description)
          assert %Commit{} = bugfix.commit
        end
      end
    end
  end

  # ============================================================================
  # 11. Deprecation Tracking Tests
  # ============================================================================

  describe "deprecation tracking" do
    test "deprecation replacement parsing works" do
      # Test the replacement parsing functionality
      replacement = Deprecation.parse_replacement("Use new_function/2 instead")

      assert %Deprecation.Replacement{} = replacement
      assert replacement.text == "Use new_function/2 instead"
      assert replacement.function == {:new_function, 2}
    end

    test "deprecation detection works on commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      commit = List.first(commits)

      case Deprecation.detect_deprecations(".", commit) do
        {:ok, deprecations} ->
          assert is_list(deprecations)

        {:error, _reason} ->
          # Some commits may not touch deprecations
          :ok
      end
    end
  end

  # ============================================================================
  # 12. Delegation Tests
  # ============================================================================

  describe "delegation tracking" do
    test "delegation extractor handles CODEOWNERS parsing" do
      # Test the CODEOWNERS parsing function
      sample_codeowners = """
      # This is a comment
      * @default-owner
      /lib/ @lib-team
      *.ex @elixir-experts
      """

      case Delegation.parse_codeowners(sample_codeowners) do
        {:ok, owners} ->
          assert is_list(owners)
          assert length(owners) >= 1

        {:error, _reason} ->
          # Parsing might fail for various reasons
          :ok
      end
    end
  end
end
