defmodule ElixirOntologies.Builders.Evolution.CommitBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.Evolution.CommitBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts \\ []) do
    defaults = %{
      sha: "abc123def456abc123def456abc123def456abc1",
      short_sha: "abc123d",
      message: "Test commit message",
      subject: "Test commit message",
      body: nil,
      author_name: "Test Author",
      author_email: "author@example.com",
      author_date: ~U[2025-01-15 10:30:00Z],
      committer_name: "Test Committer",
      committer_email: "committer@example.com",
      commit_date: ~U[2025-01-15 10:35:00Z],
      parents: [],
      is_merge: false,
      tree_sha: "tree123abc",
      metadata: %{}
    }

    struct(Commit, Map.merge(defaults, Map.new(opts)))
  end

  defp create_context(opts \\ []) do
    defaults = [base_iri: "https://example.org/code#"]
    Context.new(Keyword.merge(defaults, opts))
  end

  defp find_triple(triples, predicate) do
    Enum.find(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp find_triples(triples, predicate) do
    Enum.filter(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp get_object(triples, predicate) do
    case find_triple(triples, predicate) do
      {_s, _p, o} -> o
      nil -> nil
    end
  end

  # ===========================================================================
  # Basic Build Tests
  # ===========================================================================

  describe "build/2" do
    test "returns commit IRI and triples" do
      commit = create_commit()
      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      assert %RDF.IRI{} = commit_iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates stable IRI from SHA" do
      commit = create_commit(sha: "deadbeef123456789012345678901234567890ab")
      context = create_context()

      {commit_iri, _triples} = CommitBuilder.build(commit, context)

      assert to_string(commit_iri) ==
               "https://example.org/code#commit/deadbeef123456789012345678901234567890ab"
    end

    test "same commit produces same IRI" do
      commit = create_commit()
      context = create_context()

      {iri1, _} = CommitBuilder.build(commit, context)
      {iri2, _} = CommitBuilder.build(commit, context)

      assert iri1 == iri2
    end
  end

  # ===========================================================================
  # Type Triple Tests
  # ===========================================================================

  describe "type triple" do
    test "generates Commit type for non-merge commit" do
      commit = create_commit(is_merge: false)
      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      type_triple = find_triple(triples, RDF.type())
      assert type_triple != nil
      {^commit_iri, _, object} = type_triple
      assert object == Evolution.Commit
    end

    test "generates MergeCommit type for merge commit" do
      commit = create_commit(is_merge: true, parents: ["parent1", "parent2"])
      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      type_triple = find_triple(triples, RDF.type())
      assert type_triple != nil
      {^commit_iri, _, object} = type_triple
      assert object == Evolution.MergeCommit
    end
  end

  # ===========================================================================
  # Hash Triples Tests
  # ===========================================================================

  describe "hash triples" do
    test "generates commitHash triple" do
      sha = "abc123def456abc123def456abc123def456abc1"
      commit = create_commit(sha: sha)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      hash_value = get_object(triples, Evolution.commitHash())
      assert hash_value != nil
      assert RDF.Literal.value(hash_value) == sha
    end

    test "generates shortHash triple" do
      commit = create_commit(short_sha: "abc123d")
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      short_hash_value = get_object(triples, Evolution.shortHash())
      assert short_hash_value != nil
      assert RDF.Literal.value(short_hash_value) == "abc123d"
    end
  end

  # ===========================================================================
  # Message Triples Tests
  # ===========================================================================

  describe "message triples" do
    test "generates commitMessage triple" do
      message = "Fix critical bug in authentication"
      commit = create_commit(message: message)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      message_value = get_object(triples, Evolution.commitMessage())
      assert message_value != nil
      assert RDF.Literal.value(message_value) == message
    end

    test "generates commitSubject triple" do
      subject = "Fix bug"
      commit = create_commit(subject: subject)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      subject_value = get_object(triples, Evolution.commitSubject())
      assert subject_value != nil
      assert RDF.Literal.value(subject_value) == subject
    end

    test "generates commitBody triple when body exists" do
      body = "This fixes issue #123\n\nDetailed explanation here."
      commit = create_commit(body: body)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      body_value = get_object(triples, Evolution.commitBody())
      assert body_value != nil
      assert RDF.Literal.value(body_value) == body
    end

    test "omits commitBody triple when body is nil" do
      commit = create_commit(body: nil)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      body_triple = find_triple(triples, Evolution.commitBody())
      assert body_triple == nil
    end

    test "omits commitMessage when nil" do
      commit = create_commit(message: nil, subject: nil)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      message_triple = find_triple(triples, Evolution.commitMessage())
      assert message_triple == nil
    end
  end

  # ===========================================================================
  # Timestamp Triples Tests
  # ===========================================================================

  describe "timestamp triples" do
    test "generates authoredAt triple" do
      author_date = ~U[2025-01-15 10:30:00Z]
      commit = create_commit(author_date: author_date)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      authored_value = get_object(triples, Evolution.authoredAt())
      assert authored_value != nil
      # RDF.XSD.DateTime returns DateTime struct from RDF.Literal.value
      assert RDF.Literal.value(authored_value) == ~U[2025-01-15 10:30:00Z]
    end

    test "generates committedAt triple" do
      commit_date = ~U[2025-01-15 10:35:00Z]
      commit = create_commit(commit_date: commit_date)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      committed_value = get_object(triples, Evolution.committedAt())
      assert committed_value != nil
      assert RDF.Literal.value(committed_value) == ~U[2025-01-15 10:35:00Z]
    end

    test "generates PROV-O startedAtTime triple" do
      author_date = ~U[2025-01-15 10:30:00Z]
      commit = create_commit(author_date: author_date)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      started_value = get_object(triples, PROV.startedAtTime())
      assert started_value != nil
      assert RDF.Literal.value(started_value) == ~U[2025-01-15 10:30:00Z]
    end

    test "generates PROV-O endedAtTime triple" do
      commit_date = ~U[2025-01-15 10:35:00Z]
      commit = create_commit(commit_date: commit_date)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      ended_value = get_object(triples, PROV.endedAtTime())
      assert ended_value != nil
      assert RDF.Literal.value(ended_value) == ~U[2025-01-15 10:35:00Z]
    end

    test "omits timestamp triples when nil" do
      commit = create_commit(author_date: nil, commit_date: nil)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      assert find_triple(triples, Evolution.authoredAt()) == nil
      assert find_triple(triples, Evolution.committedAt()) == nil
      assert find_triple(triples, PROV.startedAtTime()) == nil
      assert find_triple(triples, PROV.endedAtTime()) == nil
    end
  end

  # ===========================================================================
  # Parent Commit Triples Tests
  # ===========================================================================

  describe "parent commit triples" do
    test "generates parentCommit triple for single parent" do
      parent_sha = "parent123abc456def789012345678901234567890"
      commit = create_commit(parents: [parent_sha])
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      parent_triples = find_triples(triples, Evolution.parentCommit())
      assert length(parent_triples) == 1

      {_, _, parent_iri} = hd(parent_triples)
      assert to_string(parent_iri) =~ parent_sha
    end

    test "generates multiple parentCommit triples for merge commit" do
      parent1 = "parent1abc456def789012345678901234567890ab"
      parent2 = "parent2abc456def789012345678901234567890cd"
      commit = create_commit(is_merge: true, parents: [parent1, parent2])
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      parent_triples = find_triples(triples, Evolution.parentCommit())
      assert length(parent_triples) == 2

      parent_iris = Enum.map(parent_triples, fn {_, _, o} -> to_string(o) end)
      assert Enum.any?(parent_iris, &(&1 =~ parent1))
      assert Enum.any?(parent_iris, &(&1 =~ parent2))
    end

    test "no parentCommit triples for root commit" do
      commit = create_commit(parents: [])
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      parent_triples = find_triples(triples, Evolution.parentCommit())
      assert parent_triples == []
    end
  end

  # ===========================================================================
  # Context Options Tests
  # ===========================================================================

  describe "context options" do
    test "uses repo_iri from metadata when provided" do
      commit = create_commit()
      repo_iri = RDF.iri("https://example.org/code#repo/abc123")
      context = create_context(metadata: %{repo_iri: repo_iri})

      {commit_iri, _triples} = CommitBuilder.build(commit, context)

      assert to_string(commit_iri) =~ "repo/abc123/commit/"
    end

    test "parent commits use same repo_iri pattern" do
      parent_sha = "parent123abc456def789012345678901234567890"
      commit = create_commit(parents: [parent_sha])
      repo_iri = RDF.iri("https://example.org/code#repo/abc123")
      context = create_context(metadata: %{repo_iri: repo_iri})

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      parent_triples = find_triples(triples, Evolution.parentCommit())
      {_, _, parent_iri} = hd(parent_triples)
      assert to_string(parent_iri) =~ "repo/abc123/commit/"
    end
  end

  # ===========================================================================
  # Build All Tests
  # ===========================================================================

  describe "build_all/2" do
    test "builds multiple commits" do
      commits = [
        create_commit(sha: "commit1" <> String.duplicate("0", 33)),
        create_commit(sha: "commit2" <> String.duplicate("0", 33))
      ]

      context = create_context()

      results = CommitBuilder.build_all(commits, context)

      assert length(results) == 2

      Enum.each(results, fn {iri, triples} ->
        assert %RDF.IRI{} = iri
        assert is_list(triples)
      end)
    end

    test "returns empty list for empty input" do
      context = create_context()
      results = CommitBuilder.build_all([], context)
      assert results == []
    end
  end

  describe "build_all_triples/2" do
    test "returns flat list of all triples" do
      commits = [
        create_commit(sha: "commit1" <> String.duplicate("0", 33)),
        create_commit(sha: "commit2" <> String.duplicate("0", 33))
      ]

      context = create_context()

      triples = CommitBuilder.build_all_triples(commits, context)

      assert is_list(triples)
      # Each commit should have at least type + hash triples
      assert length(triples) >= 6
    end

    test "returns empty list for empty input" do
      context = create_context()
      triples = CommitBuilder.build_all_triples([], context)
      assert triples == []
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles minimal commit with only required fields" do
      commit = %Commit{
        sha: "minimal123abc456def789012345678901234567",
        short_sha: "minimal1"
      }

      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      assert %RDF.IRI{} = commit_iri
      # Should have at least type and hash triples
      assert length(triples) >= 3
    end

    test "handles commit with all fields populated" do
      commit =
        create_commit(
          body: "Detailed body\n\nWith multiple lines",
          tree_sha: "tree123",
          metadata: %{branch: "main", tags: ["v1.0.0"]}
        )

      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      assert %RDF.IRI{} = commit_iri
      # Should have many triples
      assert length(triples) >= 8
    end

    test "handles special characters in commit message" do
      message = "Fix issue with \"quotes\" and <brackets> & ampersands"
      commit = create_commit(message: message, subject: message)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      message_value = get_object(triples, Evolution.commitMessage())
      assert RDF.Literal.value(message_value) == message
    end

    test "handles unicode in commit message" do
      message = "修复 bug 🐛 in authentication"
      commit = create_commit(message: message, subject: message)
      context = create_context()

      {_commit_iri, triples} = CommitBuilder.build(commit, context)

      message_value = get_object(triples, Evolution.commitMessage())
      assert RDF.Literal.value(message_value) == message
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "builds from real commit extraction" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      context = create_context()

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      assert %RDF.IRI{} = commit_iri
      assert to_string(commit_iri) =~ commit.sha
      assert length(triples) > 0

      # Verify type triple
      type_triple = find_triple(triples, RDF.type())
      assert type_triple != nil

      # Verify hash triple
      hash_value = get_object(triples, Evolution.commitHash())
      assert hash_value != nil
      assert RDF.Literal.value(hash_value) == commit.sha
    end
  end
end
