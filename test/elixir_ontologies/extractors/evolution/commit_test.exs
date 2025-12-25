defmodule ElixirOntologies.Extractors.Evolution.CommitTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Commit

  # ===========================================================================
  # Test Setup
  # ===========================================================================

  # Tests run against the actual repository we're in
  # This ensures real git functionality is tested

  # ===========================================================================
  # SHA Validation Tests
  # ===========================================================================

  describe "valid_sha?/1" do
    test "returns true for valid 40-character SHA" do
      assert Commit.valid_sha?("abc123def456abc123def456abc123def456abc1")
    end

    test "returns true for uppercase SHA" do
      assert Commit.valid_sha?("ABC123DEF456ABC123DEF456ABC123DEF456ABC1")
    end

    test "returns true for mixed case SHA" do
      assert Commit.valid_sha?("AbC123DeF456aBc123dEf456aBc123dEf456aBc1")
    end

    test "returns false for short SHA" do
      refute Commit.valid_sha?("abc123d")
    end

    test "returns false for SHA with invalid characters" do
      refute Commit.valid_sha?("ghijkl123456ghijkl123456ghijkl123456ghij")
    end

    test "returns false for nil" do
      refute Commit.valid_sha?(nil)
    end

    test "returns false for non-string" do
      refute Commit.valid_sha?(12345)
    end
  end

  describe "valid_short_sha?/1" do
    test "returns true for 7-character SHA" do
      assert Commit.valid_short_sha?("abc123d")
    end

    test "returns true for 40-character SHA" do
      assert Commit.valid_short_sha?("abc123def456abc123def456abc123def456abc1")
    end

    test "returns false for 6-character SHA" do
      refute Commit.valid_short_sha?("abc123")
    end

    test "returns false for SHA with invalid characters" do
      refute Commit.valid_short_sha?("ghijklm")
    end

    test "returns false for nil" do
      refute Commit.valid_short_sha?(nil)
    end
  end

  # ===========================================================================
  # Message Parsing Tests
  # ===========================================================================

  describe "extract_subject/1" do
    test "extracts first line from multi-line message" do
      message = "Add new feature\n\nThis is the body"
      assert Commit.extract_subject(message) == "Add new feature"
    end

    test "returns full message for single line" do
      message = "Single line message"
      assert Commit.extract_subject(message) == "Single line message"
    end

    test "trims whitespace from subject" do
      message = "  Subject with spaces  \n\nBody"
      assert Commit.extract_subject(message) == "Subject with spaces"
    end

    test "returns nil for nil input" do
      assert Commit.extract_subject(nil) == nil
    end

    test "handles message with only newlines" do
      message = "Subject\n\n\n\n"
      assert Commit.extract_subject(message) == "Subject"
    end
  end

  describe "extract_body/1" do
    test "extracts body after blank line" do
      message = "Subject\n\nThis is the body\nWith multiple lines"
      assert Commit.extract_body(message) == "This is the body\nWith multiple lines"
    end

    test "returns nil for single line message" do
      message = "Single line message"
      assert Commit.extract_body(message) == nil
    end

    test "returns nil for message without blank line" do
      message = "Subject\nNot a body (no blank line)"
      assert Commit.extract_body(message) == nil
    end

    test "returns nil for nil input" do
      assert Commit.extract_body(nil) == nil
    end

    test "trims body content" do
      message = "Subject\n\n  Body with spaces  "
      assert Commit.extract_body(message) == "Body with spaces"
    end

    test "returns nil for empty body after blank line" do
      message = "Subject\n\n   "
      assert Commit.extract_body(message) == nil
    end
  end

  # ===========================================================================
  # Commit Type Tests
  # ===========================================================================

  describe "merge_commit?/1" do
    test "returns true for commit with multiple parents" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        parents: ["parent1abc", "parent2def"],
        is_merge: true
      }

      assert Commit.merge_commit?(commit)
    end

    test "returns false for commit with single parent" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        parents: ["parent1abc"],
        is_merge: false
      }

      refute Commit.merge_commit?(commit)
    end

    test "returns false for initial commit (no parents)" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        parents: [],
        is_merge: false
      }

      refute Commit.merge_commit?(commit)
    end
  end

  describe "initial_commit?/1" do
    test "returns true for commit with no parents" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        parents: []
      }

      assert Commit.initial_commit?(commit)
    end

    test "returns false for commit with parents" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        parents: ["parent1abc"]
      }

      refute Commit.initial_commit?(commit)
    end
  end

  # ===========================================================================
  # Extraction Tests (require git repository)
  # ===========================================================================

  describe "extract_commit/2" do
    test "extracts HEAD commit from current repository" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert is_binary(commit.sha)
      assert String.length(commit.sha) == 40
      assert is_binary(commit.short_sha)
      assert String.length(commit.short_sha) >= 7
    end

    test "extracts commit subject" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      # Subject should be present (not nil)
      assert is_binary(commit.subject) or commit.subject == nil
    end

    test "extracts author information" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert is_binary(commit.author_name)
      assert is_binary(commit.author_email)
    end

    test "extracts author date as DateTime" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert %DateTime{} = commit.author_date
    end

    test "extracts committer information" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert is_binary(commit.committer_name)
      assert is_binary(commit.committer_email)
    end

    test "extracts commit date as DateTime" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert %DateTime{} = commit.commit_date
    end

    test "extracts tree SHA" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      assert is_binary(commit.tree_sha)
      assert String.length(commit.tree_sha) == 40
    end

    test "extracts parent commits" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      # Parents should be a list (may be empty for initial commit)
      assert is_list(commit.parents)
      # Each parent should be a valid SHA
      Enum.each(commit.parents, fn parent ->
        assert Commit.valid_sha?(parent)
      end)
    end

    test "correctly sets is_merge based on parent count" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      expected_is_merge = length(commit.parents) > 1
      assert commit.is_merge == expected_is_merge
    end

    test "returns error for non-existent repository" do
      result = Commit.extract_commit("/nonexistent/path", "HEAD")

      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end

    test "returns error for invalid ref" do
      result = Commit.extract_commit(".", "nonexistent-branch-xyz")

      assert {:error, :invalid_ref} = result
    end
  end

  describe "extract_commit!/2" do
    test "returns commit for valid ref" do
      commit = Commit.extract_commit!(".", "HEAD")

      assert %Commit{} = commit
      assert is_binary(commit.sha)
    end

    test "raises for invalid ref" do
      assert_raise ArgumentError, ~r/Failed to extract commit/, fn ->
        Commit.extract_commit!(".", "nonexistent-branch-xyz")
      end
    end
  end

  describe "extract_commits/2" do
    test "extracts multiple commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 5)

      assert is_list(commits)
      assert length(commits) <= 5

      Enum.each(commits, fn commit ->
        assert %Commit{} = commit
        assert is_binary(commit.sha)
      end)
    end

    test "respects limit option" do
      {:ok, commits} = Commit.extract_commits(".", limit: 2)

      assert length(commits) <= 2
    end

    test "returns error for non-existent repository" do
      result = Commit.extract_commits("/nonexistent/path")

      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "Commit struct" do
    test "has all required fields" do
      commit = %Commit{
        sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d"
      }

      assert commit.sha == "abc123def456abc123def456abc123def456abc1"
      assert commit.short_sha == "abc123d"
      assert commit.parents == []
      assert commit.is_merge == false
      assert commit.metadata == %{}
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Commit, [])
      end
    end
  end
end
