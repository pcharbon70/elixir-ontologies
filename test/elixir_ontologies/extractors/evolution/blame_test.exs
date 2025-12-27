defmodule ElixirOntologies.Extractors.Evolution.BlameTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Blame
  alias ElixirOntologies.Extractors.Evolution.Blame.BlameInfo

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "BlameInfo struct" do
    test "has all required fields" do
      info = %BlameInfo{
        line_number: 1,
        commit_sha: "abc123def456abc123def456abc123def456abc1"
      }

      assert info.line_number == 1
      assert info.commit_sha == "abc123def456abc123def456abc123def456abc1"
      assert info.content == nil
      assert info.author_name == nil
      assert info.author_email == nil
      assert info.author_time == nil
      assert info.author_date == nil
      assert info.is_uncommitted == false
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(BlameInfo, [])
      end
    end
  end

  describe "FileBlame struct" do
    test "has all required fields" do
      blame = %Blame{path: "test.ex"}

      assert blame.path == "test.ex"
      assert blame.lines == []
      assert blame.line_count == 0
      assert blame.commit_count == 0
      assert blame.author_count == 0
      assert blame.oldest_line == nil
      assert blame.newest_line == nil
      assert blame.has_uncommitted == false
      assert blame.metadata == %{}
    end

    test "enforces path as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Blame, [])
      end
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "is_uncommitted?/1" do
    test "returns true for uncommitted lines" do
      line = %BlameInfo{
        line_number: 1,
        commit_sha: "0000000000000000000000000000000000000000",
        is_uncommitted: true
      }

      assert Blame.is_uncommitted?(line)
    end

    test "returns false for committed lines" do
      line = %BlameInfo{
        line_number: 1,
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        is_uncommitted: false
      }

      refute Blame.is_uncommitted?(line)
    end
  end

  describe "line_age/1" do
    test "returns age in seconds" do
      line = %BlameInfo{
        line_number: 1,
        commit_sha: "abc123",
        line_age_seconds: 3600
      }

      assert Blame.line_age(line) == 3600
    end

    test "returns nil for uncommitted lines" do
      line = %BlameInfo{
        line_number: 1,
        commit_sha: "0000000000000000000000000000000000000000",
        is_uncommitted: true,
        line_age_seconds: nil
      }

      assert Blame.line_age(line) == nil
    end
  end

  describe "commits_in_blame/1" do
    test "returns unique commits" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{line_number: 1, commit_sha: "aaa"},
          %BlameInfo{line_number: 2, commit_sha: "bbb"},
          %BlameInfo{line_number: 3, commit_sha: "aaa"}
        ]
      }

      commits = Blame.commits_in_blame(blame)
      assert length(commits) == 2
      assert "aaa" in commits
      assert "bbb" in commits
    end
  end

  describe "authors_in_blame/1" do
    test "returns unique author tuples" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{
            line_number: 1,
            commit_sha: "aaa",
            author_name: "Alice",
            author_email: "alice@example.com"
          },
          %BlameInfo{
            line_number: 2,
            commit_sha: "bbb",
            author_name: "Bob",
            author_email: "bob@example.com"
          },
          %BlameInfo{
            line_number: 3,
            commit_sha: "ccc",
            author_name: "Alice",
            author_email: "alice@example.com"
          }
        ]
      }

      authors = Blame.authors_in_blame(blame)
      assert length(authors) == 2
      assert {"Alice", "alice@example.com"} in authors
      assert {"Bob", "bob@example.com"} in authors
    end

    test "excludes lines without author info" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{line_number: 1, commit_sha: "aaa", author_name: nil, author_email: nil}
        ]
      }

      assert Blame.authors_in_blame(blame) == []
    end
  end

  describe "lines_by_commit/1" do
    test "groups lines by commit SHA" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{line_number: 1, commit_sha: "aaa"},
          %BlameInfo{line_number: 2, commit_sha: "bbb"},
          %BlameInfo{line_number: 3, commit_sha: "aaa"}
        ]
      }

      by_commit = Blame.lines_by_commit(blame)
      assert map_size(by_commit) == 2
      assert length(by_commit["aaa"]) == 2
      assert length(by_commit["bbb"]) == 1
    end
  end

  describe "lines_by_author/1" do
    test "groups lines by author email" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{
            line_number: 1,
            commit_sha: "aaa",
            author_email: "alice@example.com"
          },
          %BlameInfo{line_number: 2, commit_sha: "bbb", author_email: "bob@example.com"},
          %BlameInfo{
            line_number: 3,
            commit_sha: "ccc",
            author_email: "alice@example.com"
          }
        ]
      }

      by_author = Blame.lines_by_author(blame)
      assert map_size(by_author) == 2
      assert length(by_author["alice@example.com"]) == 2
      assert length(by_author["bob@example.com"]) == 1
    end
  end

  describe "oldest_line/1" do
    test "returns oldest line accessor" do
      oldest = %BlameInfo{line_number: 5, commit_sha: "old", author_time: 1000}

      blame = %Blame{
        path: "test.ex",
        oldest_line: oldest
      }

      assert Blame.oldest_line(blame) == oldest
    end
  end

  describe "newest_line/1" do
    test "returns newest line accessor" do
      newest = %BlameInfo{line_number: 10, commit_sha: "new", author_time: 9999}

      blame = %Blame{
        path: "test.ex",
        newest_line: newest
      }

      assert Blame.newest_line(blame) == newest
    end
  end

  describe "line_count_for_commit/2" do
    test "counts lines for a specific commit" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{line_number: 1, commit_sha: "aaa"},
          %BlameInfo{line_number: 2, commit_sha: "bbb"},
          %BlameInfo{line_number: 3, commit_sha: "aaa"},
          %BlameInfo{line_number: 4, commit_sha: "aaa"}
        ]
      }

      assert Blame.line_count_for_commit(blame, "aaa") == 3
      assert Blame.line_count_for_commit(blame, "bbb") == 1
      assert Blame.line_count_for_commit(blame, "ccc") == 0
    end
  end

  describe "line_count_for_author/2" do
    test "counts lines for a specific author" do
      blame = %Blame{
        path: "test.ex",
        lines: [
          %BlameInfo{
            line_number: 1,
            commit_sha: "aaa",
            author_email: "alice@example.com"
          },
          %BlameInfo{line_number: 2, commit_sha: "bbb", author_email: "bob@example.com"},
          %BlameInfo{
            line_number: 3,
            commit_sha: "ccc",
            author_email: "alice@example.com"
          }
        ]
      }

      assert Blame.line_count_for_author(blame, "alice@example.com") == 2
      assert Blame.line_count_for_author(blame, "bob@example.com") == 1
      assert Blame.line_count_for_author(blame, "charlie@example.com") == 0
    end
  end

  # ===========================================================================
  # Extraction Tests (require git repository)
  # ===========================================================================

  describe "extract_blame/2" do
    test "extracts blame for existing file" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      assert blame.path == "mix.exs"
      assert is_list(blame.lines)
      assert blame.line_count > 0
      assert blame.commit_count > 0
      assert blame.author_count > 0
    end

    test "lines have proper structure" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      Enum.each(blame.lines, fn line ->
        assert %BlameInfo{} = line
        assert is_integer(line.line_number)
        assert line.line_number > 0
        assert is_binary(line.commit_sha)
        assert String.length(line.commit_sha) == 40
      end)
    end

    test "lines have author information" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # At least some lines should have author info
      lines_with_author = Enum.filter(blame.lines, &(&1.author_name != nil))
      assert length(lines_with_author) > 0

      Enum.each(lines_with_author, fn line ->
        assert is_binary(line.author_name)
        assert is_binary(line.author_email)
        assert is_integer(line.author_time)
        assert %DateTime{} = line.author_date
      end)
    end

    test "lines have content" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # Check first line has expected content
      first_line = List.first(blame.lines)
      assert first_line.line_number == 1
      assert is_binary(first_line.content)
    end

    test "returns error for non-existent file" do
      result = Blame.extract_blame(".", "definitely_not_a_real_file_xyz.ex")

      assert {:error, :file_not_found} = result
    end

    test "returns error for non-existent repository" do
      result = Blame.extract_blame("/nonexistent/path", "file.ex")

      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end

    test "line numbers are sequential" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      line_numbers = Enum.map(blame.lines, & &1.line_number)
      expected = Enum.to_list(1..length(blame.lines))
      assert line_numbers == expected
    end

    test "oldest and newest lines are set" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      assert blame.oldest_line != nil
      assert blame.newest_line != nil
      assert blame.oldest_line.author_time <= blame.newest_line.author_time
    end

    test "line age is calculated" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      committed_lines = Enum.filter(blame.lines, &(not &1.is_uncommitted))

      Enum.each(committed_lines, fn line ->
        assert line.line_age_seconds != nil
        assert line.line_age_seconds >= 0
      end)
    end
  end

  describe "extract_blame!/2" do
    test "returns blame for valid file" do
      blame = Blame.extract_blame!(".", "mix.exs")

      assert %Blame{} = blame
      assert blame.path == "mix.exs"
    end

    test "raises for non-existent file" do
      assert_raise ArgumentError, ~r/Failed to extract blame/, fn ->
        Blame.extract_blame!(".", "nonexistent_file_xyz.ex")
      end
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration with repository" do
    test "can extract blame for lib files" do
      {:ok, blame} = Blame.extract_blame(".", "lib/elixir_ontologies.ex")

      assert blame.path == "lib/elixir_ontologies.ex"
      assert blame.line_count > 0
    end

    test "can extract blame for test files" do
      {:ok, blame} = Blame.extract_blame(".", "test/test_helper.exs")

      assert blame.path == "test/test_helper.exs"
      assert blame.line_count > 0
    end

    test "commit and author counts are consistent" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      unique_commits = blame.lines |> Enum.map(& &1.commit_sha) |> Enum.uniq() |> length()
      unique_authors = blame.lines |> Enum.map(& &1.author_email) |> Enum.uniq() |> length()

      assert blame.commit_count == unique_commits
      assert blame.author_count == unique_authors
    end

    test "summaries contain commit messages" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      lines_with_summary = Enum.filter(blame.lines, &(&1.summary != nil))
      assert length(lines_with_summary) > 0

      Enum.each(lines_with_summary, fn line ->
        assert is_binary(line.summary)
        assert String.length(line.summary) > 0
      end)
    end
  end

  # ===========================================================================
  # Boundary Tests
  # ===========================================================================

  describe "boundary conditions" do
    test "handles empty file gracefully" do
      # Create a temp file
      temp_path = Path.join(System.tmp_dir!(), "empty_test_#{:rand.uniform(10000)}.ex")
      File.write!(temp_path, "")

      on_exit(fn ->
        File.rm(temp_path)
      end)

      # Empty file won't be tracked by git, so should fail
      result = Blame.extract_blame(".", temp_path)
      assert {:error, _} = result
    end

    test "handles files with special characters in content" do
      {:ok, blame} = Blame.extract_blame(".", "mix.exs")

      # mix.exs has various special characters
      assert is_list(blame.lines)
    end
  end
end
