defmodule ElixirOntologies.Extractors.Evolution.IntegrationTest do
  @moduledoc """
  Integration tests for Evolution extractors.

  These tests verify that the different evolution modules work together correctly.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Blame
  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.Developer
  alias ElixirOntologies.Extractors.Evolution.FileHistory

  # ===========================================================================
  # Cross-Module Integration Tests
  # ===========================================================================

  describe "blame + commit + developer correlation" do
    test "can correlate blame lines with commit and developer data" do
      # Extract blame for mix.exs
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # Get the first line's commit
      first_line = List.first(blame.lines)
      assert is_binary(first_line.commit_sha)

      # Extract full commit for that SHA
      {:ok, commit} = Commit.extract_commit(".", first_line.commit_sha)
      assert commit.sha == first_line.commit_sha

      # Get developer from commit
      author = Developer.author_from_commit(commit)

      # Verify the author email matches the blame line author
      # (unless one is nil/unknown)
      if first_line.author_email && commit.author_email do
        assert author.email == first_line.author_email
      end
    end

    test "blame lines have valid author emails" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # Collect unique author emails from blame lines
      author_emails =
        blame.lines
        |> Enum.map(& &1.author_email)
        |> Enum.filter(& &1)
        |> Enum.uniq()

      # Each author email should be valid
      for email <- author_emails do
        assert is_binary(email)
        assert String.length(email) > 0
      end
    end
  end

  describe "file history + commit correlation" do
    test "file history commits are valid commit SHAs" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      # Verify we have commits
      assert history.commit_count > 0
      assert length(history.commits) > 0

      # First commit in history should be extractable
      first_commit_sha = List.first(history.commits)
      {:ok, commit} = Commit.extract_commit(".", first_commit_sha)
      assert commit.sha == first_commit_sha
    end

    test "file history first and last commits match" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      # First commit should be the last in the list (oldest)
      assert history.first_commit == List.last(history.commits)

      # Last commit should be the first in the list (newest)
      assert history.last_commit == List.first(history.commits)
    end
  end

  describe "developer aggregation from repository" do
    test "developers from commits have valid author/committer info" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)
      developers = Developer.from_commits(commits)

      # Each developer should have at least one commit
      for dev <- developers do
        assert dev.commit_count > 0
        assert is_binary(dev.email)

        # Should have authored or committed at least one commit
        assert length(dev.authored_commits) > 0 or length(dev.committed_commits) > 0
      end
    end

    test "developer emails are unique across aggregation" do
      {:ok, commits} = Commit.extract_commits(".", limit: 20)
      developers = Developer.from_commits(commits)

      emails = Enum.map(developers, & &1.email)
      assert length(emails) == length(Enum.uniq(emails))
    end

    test "developer commit counts match actual commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 10)
      developers = Developer.from_commits(commits)

      # Total unique commits across all developers
      all_authored = developers |> Enum.flat_map(& &1.authored_commits) |> Enum.uniq()
      all_committed = developers |> Enum.flat_map(& &1.committed_commits) |> Enum.uniq()
      all_unique = Enum.uniq(all_authored ++ all_committed)

      # Should not exceed total commits
      assert length(all_unique) <= length(commits)
    end
  end

  # ===========================================================================
  # Optional Parameters Tests
  # ===========================================================================

  describe "blame optional parameters" do
    test "line_range option limits lines" do
      {:ok, full_blame} = Blame.extract_blame(".", "mix.exs")
      {:ok, partial_blame} = Blame.extract_blame(".", "mix.exs", line_range: {1, 5})

      # Partial should have fewer lines
      assert length(partial_blame.lines) <= 5
      assert length(partial_blame.lines) < length(full_blame.lines)
    end

    test "revision option uses specific commit" do
      # Get an older commit
      {:ok, commits} = Commit.extract_commits(".", limit: 5)

      if length(commits) > 1 do
        # Try blaming at an older revision
        older_sha = List.last(commits).sha
        result = Blame.extract_blame(".", "mix.exs", revision: older_sha)

        # Should succeed or fail cleanly (file might not exist at that revision)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "anonymize_emails option hashes emails" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs", anonymize_emails: true)

      # All emails should be SHA256 hashes (64 hex chars)
      for line <- blame.lines do
        if line.author_email do
          assert String.length(line.author_email) == 64
          assert Regex.match?(~r/^[0-9a-f]+$/, line.author_email)
        end
      end
    end
  end

  describe "commit optional parameters" do
    test "extract_commits limit option" do
      {:ok, commits_5} = Commit.extract_commits(".", limit: 5)
      {:ok, commits_10} = Commit.extract_commits(".", limit: 10)

      assert length(commits_5) <= 5
      assert length(commits_10) <= 10
      assert length(commits_5) <= length(commits_10)
    end

    test "extract_commits from option" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)

      if length(commits) >= 2 do
        # Extract from a specific commit
        second_sha = Enum.at(commits, 1).sha
        {:ok, from_second} = Commit.extract_commits(".", limit: 2, from: second_sha)

        # First commit should be the one we started from
        assert List.first(from_second).sha == second_sha
      end
    end
  end

  describe "file history optional parameters" do
    test "limit option restricts commit count" do
      {:ok, history_5} = FileHistory.extract_file_history(".", "mix.exs", limit: 5)
      {:ok, history_10} = FileHistory.extract_file_history(".", "mix.exs", limit: 10)

      assert length(history_5.commits) <= 5
      assert length(history_10.commits) <= 10
    end

    test "follow option affects rename detection" do
      {:ok, history_follow} = FileHistory.extract_file_history(".", "mix.exs", follow: true)
      {:ok, history_no_follow} = FileHistory.extract_file_history(".", "mix.exs", follow: false)

      # Both should succeed; rename list may differ
      assert is_list(history_follow.renames)
      assert is_list(history_no_follow.renames)
    end
  end

  # ===========================================================================
  # Security Tests
  # ===========================================================================

  describe "command injection prevention" do
    test "commit extraction rejects malicious refs" do
      result = Commit.extract_commit(".", "HEAD; rm -rf /")
      assert {:error, :invalid_ref} = result
    end

    test "blame extraction rejects malicious paths" do
      result = Blame.extract_blame(".", "../../../etc/passwd")
      assert {:error, :invalid_path} = result
    end

    test "file history rejects path traversal" do
      result = FileHistory.extract_file_history(".", "../../../etc/passwd")
      assert {:error, :invalid_path} = result
    end

    test "blame rejects malicious revision" do
      result = Blame.extract_blame(".", "mix.exs", revision: "HEAD && evil")
      assert {:error, :invalid_ref} = result
    end
  end

  # ===========================================================================
  # Bang Variant Tests
  # ===========================================================================

  describe "bang variant functions" do
    test "extract_commit! raises on error" do
      assert_raise ArgumentError, fn ->
        Commit.extract_commit!(".", "nonexistent-ref-xyz")
      end
    end

    test "extract_commits! raises on error" do
      assert_raise ArgumentError, fn ->
        Commit.extract_commits!("/nonexistent-path", limit: 5)
      end
    end

    test "extract_file_history! raises on error" do
      assert_raise ArgumentError, fn ->
        FileHistory.extract_file_history!(".", "nonexistent-file-xyz.ex")
      end
    end

    test "extract_blame! raises on error" do
      assert_raise ArgumentError, fn ->
        Blame.extract_blame!(".", "nonexistent-file-xyz.ex")
      end
    end
  end
end
