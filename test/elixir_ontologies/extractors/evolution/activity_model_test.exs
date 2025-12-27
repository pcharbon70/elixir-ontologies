defmodule ElixirOntologies.Extractors.Evolution.ActivityModelTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.ActivityModel, as: AM

  alias ElixirOntologies.Extractors.Evolution.ActivityModel.{
    ActivityModel,
    Usage,
    Generation,
    Communication
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

  describe "ActivityModel struct" do
    test "enforces required keys" do
      activity = %ActivityModel{
        activity_id: "activity:abc123d",
        activity_type: :commit,
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d"
      }

      assert activity.activity_id == "activity:abc123d"
      assert activity.activity_type == :commit
      assert activity.used_entities == []
      assert activity.generated_entities == []
      assert activity.informed_by == []
    end

    test "has default values" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc"
      }

      assert activity.started_at == nil
      assert activity.ended_at == nil
      assert activity.used_entities == []
      assert activity.generated_entities == []
      assert activity.invalidated_entities == []
      assert activity.informed_by == []
      assert activity.informs == []
      assert activity.associated_agents == []
      assert activity.metadata == %{}
    end
  end

  describe "Usage struct" do
    test "enforces required keys" do
      usage = %Usage{
        activity_id: "activity:abc123d",
        entity_id: "lib/foo.ex@def456e"
      }

      assert usage.activity_id == "activity:abc123d"
      assert usage.entity_id == "lib/foo.ex@def456e"
      assert usage.role == nil
    end

    test "has default values" do
      usage = %Usage{
        activity_id: "activity:abc",
        entity_id: "file@sha"
      }

      assert usage.role == nil
      assert usage.timestamp == nil
      assert usage.metadata == %{}
    end
  end

  describe "Generation struct" do
    test "enforces required keys" do
      generation = %Generation{
        entity_id: "lib/foo.ex@abc123d",
        activity_id: "activity:abc123d"
      }

      assert generation.entity_id == "lib/foo.ex@abc123d"
      assert generation.activity_id == "activity:abc123d"
    end

    test "has default values" do
      generation = %Generation{
        entity_id: "file@sha",
        activity_id: "activity:abc"
      }

      assert generation.timestamp == nil
      assert generation.metadata == %{}
    end
  end

  describe "Communication struct" do
    test "enforces required keys" do
      communication = %Communication{
        informed_activity: "activity:abc123d",
        informing_activity: "activity:def456e"
      }

      assert communication.informed_activity == "activity:abc123d"
      assert communication.informing_activity == "activity:def456e"
    end

    test "has default values" do
      communication = %Communication{
        informed_activity: "a",
        informing_activity: "b"
      }

      assert communication.metadata == %{}
    end
  end

  # ===========================================================================
  # Activity ID Tests
  # ===========================================================================

  describe "build_activity_id/1" do
    test "builds activity ID from short SHA" do
      id = AM.build_activity_id("abc123d")
      assert id == "activity:abc123d"
    end
  end

  describe "parse_activity_id/1" do
    test "parses activity ID to extract short SHA" do
      {:ok, sha} = AM.parse_activity_id("activity:abc123d")
      assert sha == "abc123d"
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = AM.parse_activity_id("invalid")
      assert {:error, :invalid_format} = AM.parse_activity_id("commit:abc123d")
    end
  end

  # ===========================================================================
  # Activity Extraction Tests
  # ===========================================================================

  describe "extract_activity/3" do
    @tag :integration
    test "extracts activity from commit at HEAD" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit)

      assert String.starts_with?(activity.activity_id, "activity:")
      assert is_atom(activity.activity_type)
      assert activity.commit_sha == commit.sha
      assert activity.short_sha == commit.short_sha
    end

    @tag :integration
    test "includes temporal information" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit)

      # started_at and ended_at come from author_date and commit_date
      assert activity.started_at != nil or commit.author_date == nil
      assert activity.ended_at != nil or commit.commit_date == nil
    end

    @tag :integration
    test "can exclude entities" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit, include_entities: false)

      assert activity.used_entities == []
      assert activity.generated_entities == []
    end

    @tag :integration
    test "can exclude communications" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit, include_communications: false)

      assert activity.informed_by == []
    end
  end

  describe "extract_activity!/3" do
    @tag :integration
    test "returns activity on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      activity = AM.extract_activity!(".", commit)

      assert String.starts_with?(activity.activity_id, "activity:")
    end
  end

  # ===========================================================================
  # Multiple Activities Tests
  # ===========================================================================

  describe "extract_activities/3" do
    @tag :integration
    test "extracts activities from multiple commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      {:ok, activities} = AM.extract_activities(".", commits)

      assert is_list(activities)
      assert length(activities) == length(commits)
    end

    @tag :integration
    test "links informs relationships" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      {:ok, activities} = AM.extract_activities(".", commits, link_informs: true)

      # Check that informs is populated based on informed_by
      if length(activities) > 1 do
        [newest | _rest] = activities
        # The newest activity's informed_by should point to older activities
        # And those older activities' informs should point back
        Enum.each(activities, fn activity ->
          assert is_list(activity.informs)
        end)
      end
    end
  end

  # ===========================================================================
  # Usage Extraction Tests
  # ===========================================================================

  describe "extract_usages/2" do
    @tag :integration
    test "extracts usages from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, usages} = AM.extract_usages(".", commit)

      assert is_list(usages)

      Enum.each(usages, fn usage ->
        assert %Usage{} = usage
        assert String.starts_with?(usage.activity_id, "activity:")
      end)
    end
  end

  describe "extract_usages!/2" do
    @tag :integration
    test "returns usages on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      usages = AM.extract_usages!(".", commit)

      assert is_list(usages)
    end
  end

  # ===========================================================================
  # Generation Extraction Tests
  # ===========================================================================

  describe "extract_generations/2" do
    @tag :integration
    test "extracts generations from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, generations} = AM.extract_generations(".", commit)

      assert is_list(generations)

      Enum.each(generations, fn generation ->
        assert %Generation{} = generation
        assert String.starts_with?(generation.activity_id, "activity:")
      end)
    end
  end

  describe "extract_generations!/2" do
    @tag :integration
    test "returns generations on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      generations = AM.extract_generations!(".", commit)

      assert is_list(generations)
    end
  end

  # ===========================================================================
  # Communication Extraction Tests
  # ===========================================================================

  describe "extract_communications/2" do
    @tag :integration
    test "extracts communications from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, communications} = AM.extract_communications(".", commit)

      assert is_list(communications)

      Enum.each(communications, fn comm ->
        assert %Communication{} = comm
        assert String.starts_with?(comm.informed_activity, "activity:")
        assert String.starts_with?(comm.informing_activity, "activity:")
      end)
    end

    @tag :integration
    test "links to parent commits" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, communications} = AM.extract_communications(".", commit)

      # Should have one communication per parent
      assert length(communications) == length(commit.parents)
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "generated?/2" do
    test "returns true when entity was generated" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        generated_entities: ["lib/foo.ex@abc"]
      }

      assert AM.generated?(activity, "lib/foo.ex@abc")
    end

    test "returns false when entity was not generated" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        generated_entities: []
      }

      refute AM.generated?(activity, "lib/foo.ex@abc")
    end
  end

  describe "used?/2" do
    test "returns true when entity was used" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        used_entities: ["lib/foo.ex@def"]
      }

      assert AM.used?(activity, "lib/foo.ex@def")
    end

    test "returns false when entity was not used" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        used_entities: []
      }

      refute AM.used?(activity, "lib/foo.ex@def")
    end
  end

  describe "informed_by?/2" do
    test "returns true when informed by activity struct" do
      activity_a = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        informed_by: ["activity:def"]
      }

      activity_b = %ActivityModel{
        activity_id: "activity:def",
        activity_type: :commit,
        commit_sha: "def",
        short_sha: "def"
      }

      assert AM.informed_by?(activity_a, activity_b)
    end

    test "returns true when informed by activity ID string" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        informed_by: ["activity:def"]
      }

      assert AM.informed_by?(activity, "activity:def")
    end

    test "returns false when not informed by" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        informed_by: []
      }

      refute AM.informed_by?(activity, "activity:xyz")
    end
  end

  describe "duration/1" do
    test "returns duration in seconds" do
      started = ~U[2024-01-01 10:00:00Z]
      ended = ~U[2024-01-01 10:05:30Z]

      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        started_at: started,
        ended_at: ended
      }

      assert AM.duration(activity) == 330
    end

    test "returns nil when started_at is nil" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        started_at: nil,
        ended_at: DateTime.utc_now()
      }

      assert AM.duration(activity) == nil
    end

    test "returns nil when ended_at is nil" do
      activity = %ActivityModel{
        activity_id: "activity:abc",
        activity_type: :commit,
        commit_sha: "abc",
        short_sha: "abc",
        started_at: DateTime.utc_now(),
        ended_at: nil
      }

      assert AM.duration(activity) == nil
    end
  end

  # ===========================================================================
  # Activity Type Detection Tests
  # ===========================================================================

  describe "activity type detection" do
    @tag :integration
    test "detects feature commits" do
      commit = create_commit(subject: "feat: add new feature")
      {:ok, activity} = AM.extract_activity(".", commit)
      assert activity.activity_type == :feature
    end

    @tag :integration
    test "detects bugfix commits" do
      commit = create_commit(subject: "fix: resolve crash")
      {:ok, activity} = AM.extract_activity(".", commit)
      assert activity.activity_type == :bugfix
    end

    @tag :integration
    test "detects refactor commits" do
      commit = create_commit(subject: "refactor: improve structure")
      {:ok, activity} = AM.extract_activity(".", commit)
      assert activity.activity_type == :refactor
    end

    @tag :integration
    test "detects docs commits" do
      commit = create_commit(subject: "docs: update readme")
      {:ok, activity} = AM.extract_activity(".", commit)
      assert activity.activity_type == :docs
    end

    @tag :integration
    test "detects merge commits" do
      commit =
        create_commit(
          subject: "Merge branch 'feature'",
          is_merge: true,
          parents: ["abc", "def"]
        )

      {:ok, activity} = AM.extract_activity(".", commit)
      assert activity.activity_type == :merge
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "full workflow integration" do
    @tag :integration
    test "can extract complete activity model" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit)

      # Verify complete structure
      assert activity.activity_id != nil
      assert activity.activity_type != nil
      assert activity.commit_sha == commit.sha
      assert is_list(activity.used_entities)
      assert is_list(activity.generated_entities)
      assert is_list(activity.informed_by)
    end

    @tag :integration
    test "activity chain reflects commit history" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)
      {:ok, activities} = AM.extract_activities(".", commits)

      if length(activities) > 1 do
        # Check that informed_by chain matches parent relationships
        [newest | rest] = activities

        # The newest commit's informed_by should include parent activity IDs
        parent_short = String.slice(List.first(commits).parents |> List.first() || "", 0, 7)

        if parent_short != "" do
          expected_parent_id = "activity:#{parent_short}"
          assert expected_parent_id in newest.informed_by
        end
      end
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    @tag :integration
    test "handles commit with no parents (initial commit)" do
      commit = create_commit(parents: [])
      {:ok, activity} = AM.extract_activity(".", commit)

      assert activity.informed_by == []
      assert activity.used_entities == []
    end

    @tag :integration
    test "handles merge commit with multiple parents" do
      commit =
        create_commit(
          parents: [
            "abc123def456abc123def456abc123def456abc1",
            "def456abc123def456abc123def456abc123def4"
          ],
          is_merge: true
        )

      {:ok, activity} = AM.extract_activity(".", commit)

      assert length(activity.informed_by) == 2
    end
  end
end
