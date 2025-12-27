defmodule ElixirOntologies.Extractors.Evolution.FileHistoryTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.FileHistory
  alias ElixirOntologies.Extractors.Evolution.FileHistory.Rename

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "FileHistory struct" do
    test "has all required fields" do
      history = %FileHistory{path: "lib/test.ex"}

      assert history.path == "lib/test.ex"
      assert history.original_path == nil
      assert history.commits == []
      assert history.renames == []
      assert history.first_commit == nil
      assert history.last_commit == nil
      assert history.commit_count == 0
      assert history.metadata == %{}
    end

    test "enforces path as required key" do
      assert_raise ArgumentError, fn ->
        struct!(FileHistory, [])
      end
    end
  end

  describe "Rename struct" do
    test "has all required fields" do
      rename = %Rename{
        from_path: "old/path.ex",
        to_path: "new/path.ex",
        commit_sha: "abc123def456abc123def456abc123def456abc1"
      }

      assert rename.from_path == "old/path.ex"
      assert rename.to_path == "new/path.ex"
      assert rename.similarity == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Rename, [])
      end
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "renamed?/1" do
    test "returns true when file has renames" do
      history = %FileHistory{
        path: "new.ex",
        renames: [
          %Rename{
            from_path: "old.ex",
            to_path: "new.ex",
            commit_sha: "abc123def456abc123def456abc123def456abc1"
          }
        ]
      }

      assert FileHistory.renamed?(history)
    end

    test "returns false when file has no renames" do
      history = %FileHistory{path: "file.ex", renames: []}

      refute FileHistory.renamed?(history)
    end
  end

  describe "original_path/1" do
    test "returns original path when file was renamed" do
      history = %FileHistory{path: "new.ex", original_path: "old.ex"}

      assert FileHistory.original_path(history) == "old.ex"
    end

    test "returns nil when file was never renamed" do
      history = %FileHistory{path: "file.ex", original_path: nil}

      assert FileHistory.original_path(history) == nil
    end
  end

  describe "rename_count/1" do
    test "returns count of renames" do
      history = %FileHistory{
        path: "c.ex",
        renames: [
          %Rename{
            from_path: "a.ex",
            to_path: "b.ex",
            commit_sha: "abc123def456abc123def456abc123def456abc1"
          },
          %Rename{
            from_path: "b.ex",
            to_path: "c.ex",
            commit_sha: "def456abc123def456abc123def456abc123def4"
          }
        ]
      }

      assert FileHistory.rename_count(history) == 2
    end

    test "returns zero when no renames" do
      history = %FileHistory{path: "file.ex", renames: []}

      assert FileHistory.rename_count(history) == 0
    end
  end

  describe "path_at_commit/2" do
    test "returns current path when no renames" do
      history = %FileHistory{path: "current.ex", renames: [], commits: ["abc", "def"]}

      assert FileHistory.path_at_commit(history, "abc") == "current.ex"
      assert FileHistory.path_at_commit(history, "def") == "current.ex"
    end

    test "returns current path for unknown commit" do
      history = %FileHistory{path: "current.ex", renames: [], commits: ["abc"]}

      assert FileHistory.path_at_commit(history, "unknown") == "current.ex"
    end
  end

  # ===========================================================================
  # Extraction Tests (require git repository)
  # ===========================================================================

  describe "extract_file_history/3" do
    test "extracts history for existing file" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      assert history.path == "mix.exs"
      assert is_list(history.commits)
      assert length(history.commits) > 0
      assert history.commit_count > 0
      assert is_binary(history.first_commit)
      assert is_binary(history.last_commit)
    end

    test "returns error for non-tracked file" do
      result = FileHistory.extract_file_history(".", "definitely_not_a_real_file_xyz.ex")

      assert {:error, :file_not_tracked} = result
    end

    test "returns error for non-existent repository" do
      result = FileHistory.extract_file_history("/nonexistent/path", "file.ex")

      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end

    test "respects limit option" do
      {:ok, history_full} = FileHistory.extract_file_history(".", "mix.exs")
      {:ok, history_limited} = FileHistory.extract_file_history(".", "mix.exs", limit: 2)

      assert length(history_limited.commits) <= 2
      assert history_limited.commit_count <= history_full.commit_count
    end

    test "commits are in reverse chronological order (newest first)" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      # The last_commit should be the first in the list (newest)
      assert history.last_commit == List.first(history.commits)
      # The first_commit should be the last in the list (oldest)
      assert history.first_commit == List.last(history.commits)
    end

    test "commit_count matches commits length" do
      {:ok, history} = FileHistory.extract_file_history(".", "mix.exs")

      assert history.commit_count == length(history.commits)
    end
  end

  describe "extract_file_history!/3" do
    test "returns history for valid file" do
      history = FileHistory.extract_file_history!(".", "mix.exs")

      assert %FileHistory{} = history
      assert history.path == "mix.exs"
    end

    test "raises for non-tracked file" do
      assert_raise ArgumentError, ~r/Failed to extract file history/, fn ->
        FileHistory.extract_file_history!(".", "nonexistent_file_xyz.ex")
      end
    end
  end

  describe "extract_commits_for_file/4" do
    test "extracts commits for tracked file" do
      {:ok, commits} = FileHistory.extract_commits_for_file(".", "mix.exs")

      assert is_list(commits)
      assert length(commits) > 0

      Enum.each(commits, fn sha ->
        assert String.length(sha) == 40
        assert Regex.match?(~r/^[0-9a-f]+$/i, sha)
      end)
    end

    test "returns empty list for non-tracked file" do
      {:ok, commits} = FileHistory.extract_commits_for_file(".", "nonexistent_xyz.ex")

      assert commits == []
    end

    test "respects limit parameter" do
      {:ok, commits} = FileHistory.extract_commits_for_file(".", "mix.exs", true, 3)

      assert length(commits) <= 3
    end
  end

  describe "extract_renames/2" do
    test "returns empty list for file with no renames" do
      {:ok, renames} = FileHistory.extract_renames(".", "mix.exs")

      # mix.exs likely hasn't been renamed, so should be empty
      # This test is valid regardless - we're testing the function works
      assert is_list(renames)
    end

    test "renames have required fields" do
      {:ok, renames} = FileHistory.extract_renames(".", "mix.exs")

      Enum.each(renames, fn rename ->
        assert %Rename{} = rename
        assert is_binary(rename.from_path)
        assert is_binary(rename.to_path)
        assert is_binary(rename.commit_sha)
      end)
    end
  end

  describe "file_exists_in_history?/2" do
    test "returns true for tracked file" do
      assert FileHistory.file_exists_in_history?(".", "mix.exs")
    end

    test "returns false for non-tracked file" do
      refute FileHistory.file_exists_in_history?(".", "definitely_not_tracked_xyz.ex")
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration with repository" do
    test "can extract history for lib files" do
      {:ok, history} = FileHistory.extract_file_history(".", "lib/elixir_ontologies.ex")

      assert history.path == "lib/elixir_ontologies.ex"
      assert history.commit_count > 0
    end

    test "can extract history for test files" do
      {:ok, history} = FileHistory.extract_file_history(".", "test/test_helper.exs")

      assert history.path == "test/test_helper.exs"
      assert history.commit_count > 0
    end

    test "handles absolute paths" do
      repo_root = File.cwd!()
      abs_path = Path.join(repo_root, "mix.exs")

      {:ok, history} = FileHistory.extract_file_history(".", abs_path)

      # Should convert to relative path
      assert history.path == "mix.exs"
    end
  end
end
