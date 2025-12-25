defmodule ElixirOntologies.Extractors.Evolution.DeveloperTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Developer
  alias ElixirOntologies.Extractors.Evolution.Commit

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts \\ []) do
    %Commit{
      sha: Keyword.get(opts, :sha, "abc123def456abc123def456abc123def456abc1"),
      short_sha: Keyword.get(opts, :short_sha, "abc123d"),
      author_name: Keyword.get(opts, :author_name, "Author Name"),
      author_email: Keyword.get(opts, :author_email, "author@example.com"),
      author_date: Keyword.get(opts, :author_date, ~U[2024-01-15 10:00:00Z]),
      committer_name: Keyword.get(opts, :committer_name, "Author Name"),
      committer_email: Keyword.get(opts, :committer_email, "author@example.com"),
      commit_date: Keyword.get(opts, :commit_date, ~U[2024-01-15 10:00:00Z]),
      message: Keyword.get(opts, :message, "Test commit"),
      subject: Keyword.get(opts, :subject, "Test commit"),
      parents: Keyword.get(opts, :parents, [])
    }
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "Developer struct" do
    test "has all required fields" do
      dev = %Developer{email: "dev@example.com"}

      assert dev.email == "dev@example.com"
      assert dev.name == nil
      assert dev.names == MapSet.new()
      assert dev.authored_commits == []
      assert dev.committed_commits == []
      assert dev.commit_count == 0
    end

    test "enforces email as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Developer, [])
      end
    end
  end

  # ===========================================================================
  # Single Commit Extraction Tests
  # ===========================================================================

  describe "author_from_commit/1" do
    test "extracts author information" do
      commit = create_commit(
        author_name: "John Doe",
        author_email: "john@example.com",
        author_date: ~U[2024-06-01 12:00:00Z],
        sha: "abc123"
      )

      author = Developer.author_from_commit(commit)

      assert author.email == "john@example.com"
      assert author.name == "John Doe"
      assert "John Doe" in author.names
      assert "abc123" in author.authored_commits
      assert author.committed_commits == []
      assert author.first_authored == ~U[2024-06-01 12:00:00Z]
      assert author.last_authored == ~U[2024-06-01 12:00:00Z]
      assert author.commit_count == 1
    end

    test "handles nil author name" do
      commit = create_commit(author_name: nil, author_email: "test@example.com")

      author = Developer.author_from_commit(commit)

      assert author.name == nil
      assert MapSet.size(author.names) == 0
    end

    test "uses unique fallback for nil email" do
      commit = create_commit(author_email: nil, sha: "abc123def456abc123def456abc123def456abc1")

      author = Developer.author_from_commit(commit)

      # Uses unique fallback per commit to avoid aggregating unrelated commits
      assert String.starts_with?(author.email, "unknown-abc123d@unknown")
    end
  end

  describe "committer_from_commit/1" do
    test "extracts committer information" do
      commit = create_commit(
        committer_name: "Jane Smith",
        committer_email: "jane@example.com",
        commit_date: ~U[2024-06-02 14:00:00Z],
        sha: "def456"
      )

      committer = Developer.committer_from_commit(commit)

      assert committer.email == "jane@example.com"
      assert committer.name == "Jane Smith"
      assert "Jane Smith" in committer.names
      assert committer.authored_commits == []
      assert "def456" in committer.committed_commits
      assert committer.first_committed == ~U[2024-06-02 14:00:00Z]
      assert committer.last_committed == ~U[2024-06-02 14:00:00Z]
      assert committer.commit_count == 1
    end

    test "handles nil committer name" do
      commit = create_commit(committer_name: nil, committer_email: "test@example.com")

      committer = Developer.committer_from_commit(commit)

      assert committer.name == nil
      assert MapSet.size(committer.names) == 0
    end
  end

  describe "from_commit/1" do
    test "returns single developer when author == committer" do
      commit = create_commit(
        author_email: "same@example.com",
        committer_email: "same@example.com"
      )

      developers = Developer.from_commit(commit)

      assert length(developers) == 1
      [dev] = developers
      assert dev.email == "same@example.com"
      assert length(dev.authored_commits) == 1
      assert length(dev.committed_commits) == 1
    end

    test "returns two developers when author != committer" do
      commit = create_commit(
        author_email: "author@example.com",
        committer_email: "committer@example.com"
      )

      developers = Developer.from_commit(commit)

      assert length(developers) == 2
      emails = Enum.map(developers, & &1.email)
      assert "author@example.com" in emails
      assert "committer@example.com" in emails
    end
  end

  # ===========================================================================
  # Merge Tests
  # ===========================================================================

  describe "merge_developers/2" do
    test "combines authored commits" do
      dev1 = %Developer{
        email: "dev@example.com",
        name: "Dev",
        names: MapSet.new(["Dev"]),
        authored_commits: ["abc"],
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        name: "Dev",
        names: MapSet.new(["Dev"]),
        authored_commits: ["def"],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert length(merged.authored_commits) == 2
      assert "abc" in merged.authored_commits
      assert "def" in merged.authored_commits
    end

    test "combines committed commits" do
      dev1 = %Developer{
        email: "dev@example.com",
        name: "Dev",
        names: MapSet.new(["Dev"]),
        committed_commits: ["abc"],
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        name: "Dev",
        names: MapSet.new(["Dev"]),
        committed_commits: ["def"],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert length(merged.committed_commits) == 2
    end

    test "combines name variations" do
      dev1 = %Developer{
        email: "dev@example.com",
        name: "John Doe",
        names: MapSet.new(["John Doe"]),
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        name: "J. Doe",
        names: MapSet.new(["J. Doe"]),
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert MapSet.size(merged.names) == 2
      assert "John Doe" in merged.names
      assert "J. Doe" in merged.names
    end

    test "tracks earliest first_authored" do
      dev1 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        first_authored: ~U[2024-01-01 00:00:00Z],
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        first_authored: ~U[2024-06-01 00:00:00Z],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert merged.first_authored == ~U[2024-01-01 00:00:00Z]
    end

    test "tracks latest last_authored" do
      dev1 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        last_authored: ~U[2024-01-01 00:00:00Z],
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        last_authored: ~U[2024-06-01 00:00:00Z],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert merged.last_authored == ~U[2024-06-01 00:00:00Z]
    end

    test "calculates correct commit count for unique commits" do
      dev1 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        authored_commits: ["abc", "def"],
        committed_commits: ["abc"],  # Same as authored
        commit_count: 2
      }

      dev2 = %Developer{
        email: "dev@example.com",
        names: MapSet.new(),
        authored_commits: ["ghi"],
        committed_commits: [],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      # abc, def, ghi = 3 unique commits
      assert merged.commit_count == 3
    end

    test "uses most recent name as primary" do
      dev1 = %Developer{
        email: "dev@example.com",
        name: "Old Name",
        names: MapSet.new(["Old Name"]),
        last_authored: ~U[2024-01-01 00:00:00Z],
        commit_count: 1
      }

      dev2 = %Developer{
        email: "dev@example.com",
        name: "New Name",
        names: MapSet.new(["New Name"]),
        last_authored: ~U[2024-06-01 00:00:00Z],
        commit_count: 1
      }

      merged = Developer.merge_developers(dev1, dev2)

      assert merged.name == "New Name"
    end
  end

  # ===========================================================================
  # Aggregation Tests
  # ===========================================================================

  describe "from_commits/1" do
    test "aggregates developers from multiple commits" do
      commits = [
        create_commit(
          sha: "abc1",
          author_email: "dev1@example.com",
          committer_email: "dev1@example.com"
        ),
        create_commit(
          sha: "abc2",
          author_email: "dev1@example.com",
          committer_email: "dev1@example.com"
        ),
        create_commit(
          sha: "abc3",
          author_email: "dev2@example.com",
          committer_email: "dev2@example.com"
        )
      ]

      developers = Developer.from_commits(commits)

      assert length(developers) == 2
      dev1 = Enum.find(developers, &(&1.email == "dev1@example.com"))
      dev2 = Enum.find(developers, &(&1.email == "dev2@example.com"))

      assert dev1.commit_count == 2
      assert dev2.commit_count == 1
    end

    test "sorts by commit count descending" do
      commits = [
        create_commit(sha: "a1", author_email: "prolific@example.com", committer_email: "prolific@example.com"),
        create_commit(sha: "a2", author_email: "prolific@example.com", committer_email: "prolific@example.com"),
        create_commit(sha: "a3", author_email: "prolific@example.com", committer_email: "prolific@example.com"),
        create_commit(sha: "b1", author_email: "occasional@example.com", committer_email: "occasional@example.com")
      ]

      developers = Developer.from_commits(commits)

      assert hd(developers).email == "prolific@example.com"
    end

    test "handles empty commit list" do
      developers = Developer.from_commits([])

      assert developers == []
    end

    test "tracks different author and committer from same commit" do
      commits = [
        create_commit(
          sha: "abc1",
          author_email: "author@example.com",
          committer_email: "committer@example.com"
        )
      ]

      developers = Developer.from_commits(commits)

      assert length(developers) == 2
      author = Enum.find(developers, &(&1.email == "author@example.com"))
      committer = Enum.find(developers, &(&1.email == "committer@example.com"))

      assert length(author.authored_commits) == 1
      assert author.committed_commits == []
      assert committer.authored_commits == []
      assert length(committer.committed_commits) == 1
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "author?/1" do
    test "returns true when developer has authored commits" do
      dev = %Developer{email: "dev@example.com", authored_commits: ["abc"]}
      assert Developer.author?(dev)
    end

    test "returns false when developer has no authored commits" do
      dev = %Developer{email: "dev@example.com", authored_commits: []}
      refute Developer.author?(dev)
    end
  end

  describe "committer?/1" do
    test "returns true when developer has committed commits" do
      dev = %Developer{email: "dev@example.com", committed_commits: ["abc"]}
      assert Developer.committer?(dev)
    end

    test "returns false when developer has no committed commits" do
      dev = %Developer{email: "dev@example.com", committed_commits: []}
      refute Developer.committer?(dev)
    end
  end

  describe "authored_count/1" do
    test "returns count of authored commits" do
      dev = %Developer{email: "dev@example.com", authored_commits: ["a", "b", "c"]}
      assert Developer.authored_count(dev) == 3
    end
  end

  describe "committed_count/1" do
    test "returns count of committed commits" do
      dev = %Developer{email: "dev@example.com", committed_commits: ["a", "b"]}
      assert Developer.committed_count(dev) == 2
    end
  end

  describe "has_name_variations?/1" do
    test "returns true when developer has multiple names" do
      dev = %Developer{email: "dev@example.com", names: MapSet.new(["John Doe", "J. Doe"])}
      assert Developer.has_name_variations?(dev)
    end

    test "returns false when developer has single name" do
      dev = %Developer{email: "dev@example.com", names: MapSet.new(["John Doe"])}
      refute Developer.has_name_variations?(dev)
    end

    test "returns false when developer has no names" do
      dev = %Developer{email: "dev@example.com", names: MapSet.new()}
      refute Developer.has_name_variations?(dev)
    end
  end

  # ===========================================================================
  # Repository-Level Extraction Tests (require git repository)
  # ===========================================================================

  describe "extract_developers/2" do
    test "extracts developers from current repository" do
      {:ok, developers} = Developer.extract_developers(".", limit: 10)

      assert is_list(developers)
      # At least one developer should exist
      assert length(developers) >= 1

      Enum.each(developers, fn dev ->
        assert is_binary(dev.email)
        assert is_integer(dev.commit_count)
      end)
    end

    test "returns error for non-existent repository" do
      result = Developer.extract_developers("/nonexistent/path")

      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end
  end

  describe "extract_developer/3" do
    test "returns error when developer not found" do
      result = Developer.extract_developer(".", "nonexistent@invalid.email.test", limit: 5)

      assert {:error, :not_found} = result
    end
  end
end
