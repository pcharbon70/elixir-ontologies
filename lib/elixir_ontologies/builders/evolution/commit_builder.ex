defmodule ElixirOntologies.Builders.Evolution.CommitBuilder do
  @moduledoc """
  Builds RDF triples for Git commits.

  This module transforms `ElixirOntologies.Extractors.Evolution.Commit` results
  into RDF triples following the elixir-evolution.ttl ontology. It handles:

  - Commit classification (Commit vs MergeCommit)
  - Commit hash and message properties
  - Author and committer timestamps
  - Parent commit relationships
  - PROV-O integration for provenance tracking

  ## Usage

      alias ElixirOntologies.Builders.Evolution.CommitBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.Evolution.Commit

      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      context = Context.new(base_iri: "https://example.org/code#")

      {commit_iri, triples} = CommitBuilder.build(commit, context)

      # commit_iri => ~I<https://example.org/code#commit/abc123...>
      # triples => [
      #   {commit_iri, RDF.type(), Evolution.Commit},
      #   {commit_iri, Evolution.commitHash(), "abc123..."},
      #   ...
      # ]

  ## RDF Output

  For a typical commit:

      commit:abc123 a evo:Commit ;
          evo:commitHash "abc123def456789..." ;
          evo:shortHash "abc123d" ;
          evo:commitMessage "Fix bug in user authentication" ;
          evo:commitSubject "Fix bug in user authentication" ;
          evo:authoredAt "2025-01-15T10:30:00Z"^^xsd:dateTime ;
          evo:committedAt "2025-01-15T10:30:00Z"^^xsd:dateTime ;
          evo:parentCommit commit:def456 .

  For a merge commit:

      commit:abc123 a evo:MergeCommit ;
          evo:commitHash "abc123..." ;
          evo:parentCommit commit:parent1 ;
          evo:parentCommit commit:parent2 .

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.CommitBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = %Commit{
      ...>   sha: "abc123def456abc123def456abc123def456abc1",
      ...>   short_sha: "abc123d",
      ...>   message: "Test commit",
      ...>   subject: "Test commit",
      ...>   body: nil,
      ...>   author_name: "Test",
      ...>   author_email: "test@example.com",
      ...>   author_date: nil,
      ...>   committer_name: "Test",
      ...>   committer_email: "test@example.com",
      ...>   commit_date: nil,
      ...>   parents: [],
      ...>   is_merge: false,
      ...>   tree_sha: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {commit_iri, triples} = CommitBuilder.build(commit, context)
      iex> to_string(commit_iri) |> String.contains?("abc123def456abc123def456abc123def456abc1")
      true
      iex> length(triples) >= 3
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a commit.

  Takes a commit extraction result and builder context, returns the commit IRI
  and a list of RDF triples representing the commit in the ontology.

  ## Parameters

  - `commit` - Commit struct from `Extractors.Evolution.Commit`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{commit_iri, triples}` where:
  - `commit_iri` - The IRI of the commit
  - `triples` - List of RDF triples describing the commit

  ## Options in Context

  The context can include:
  - `:repo_iri` in metadata - Use repo-based commit IRI instead of standalone

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.CommitBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Commit
      iex> commit = %Commit{
      ...>   sha: "abc123def456abc123def456abc123def456abc1",
      ...>   short_sha: "abc123d",
      ...>   message: "Fix bug",
      ...>   subject: "Fix bug",
      ...>   body: nil,
      ...>   parents: [],
      ...>   is_merge: false
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {commit_iri, triples} = CommitBuilder.build(commit, context)
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(Commit.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%Commit{} = commit, %Context{} = context) do
    # Generate commit IRI
    commit_iri = generate_commit_iri(commit, context)

    # Build all triples
    triples =
      [
        build_type_triple(commit_iri, commit)
      ] ++
        build_hash_triples(commit_iri, commit) ++
        build_message_triples(commit_iri, commit) ++
        build_timestamp_triples(commit_iri, commit) ++
        build_parent_triples(commit_iri, commit, context)

    # Flatten and filter nils
    triples =
      triples
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    {commit_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple commits.

  ## Parameters

  - `commits` - List of Commit structs
  - `context` - Builder context

  ## Returns

  A list of `{commit_iri, triples}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.CommitBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> results = CommitBuilder.build_all([], context)
      iex> results
      []
  """
  @spec build_all([Commit.t()], Context.t()) :: [{RDF.IRI.t(), [RDF.Triple.t()]}]
  def build_all(commits, context) when is_list(commits) do
    Enum.map(commits, &build(&1, context))
  end

  @doc """
  Builds RDF triples for multiple commits and collects all triples.

  Returns a flat list of all triples from all commits.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.CommitBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = CommitBuilder.build_all_triples([], context)
      iex> triples
      []
  """
  @spec build_all_triples([Commit.t()], Context.t()) :: [RDF.Triple.t()]
  def build_all_triples(commits, context) when is_list(commits) do
    commits
    |> build_all(context)
    |> Enum.flat_map(fn {_iri, triples} -> triples end)
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  defp generate_commit_iri(commit, context) do
    base = to_string(context.base_iri)

    # Check if repo_iri is provided in metadata
    case Map.get(context.metadata, :repo_iri) do
      nil ->
        # Standalone commit IRI: base#commit/sha
        RDF.iri("#{base}commit/#{commit.sha}")

      repo_iri ->
        # Repo-based commit IRI: repo_iri/commit/sha
        RDF.iri("#{to_string(repo_iri)}/commit/#{commit.sha}")
    end
  end

  # ===========================================================================
  # Type Triple Generation
  # ===========================================================================

  defp build_type_triple(commit_iri, commit) do
    class =
      if commit.is_merge do
        Evolution.MergeCommit
      else
        Evolution.Commit
      end

    Helpers.type_triple(commit_iri, class)
  end

  # ===========================================================================
  # Hash Triples Generation
  # ===========================================================================

  defp build_hash_triples(commit_iri, commit) do
    [
      Helpers.datatype_property(commit_iri, Evolution.commitHash(), commit.sha, RDF.XSD.String),
      Helpers.datatype_property(
        commit_iri,
        Evolution.shortHash(),
        commit.short_sha,
        RDF.XSD.String
      )
    ]
  end

  # ===========================================================================
  # Message Triples Generation
  # ===========================================================================

  defp build_message_triples(commit_iri, commit) do
    triples = []

    # Full message
    triples =
      if commit.message do
        [
          Helpers.datatype_property(
            commit_iri,
            Evolution.commitMessage(),
            commit.message,
            RDF.XSD.String
          )
          | triples
        ]
      else
        triples
      end

    # Subject (first line)
    triples =
      if commit.subject do
        [
          Helpers.datatype_property(
            commit_iri,
            Evolution.commitSubject(),
            commit.subject,
            RDF.XSD.String
          )
          | triples
        ]
      else
        triples
      end

    # Body (lines after subject)
    triples =
      if commit.body do
        [
          Helpers.datatype_property(
            commit_iri,
            Evolution.commitBody(),
            commit.body,
            RDF.XSD.String
          )
          | triples
        ]
      else
        triples
      end

    triples
  end

  # ===========================================================================
  # Timestamp Triples Generation
  # ===========================================================================

  defp build_timestamp_triples(commit_iri, commit) do
    triples = []

    # Author date
    triples =
      if commit.author_date do
        [
          Helpers.datatype_property(
            commit_iri,
            Evolution.authoredAt(),
            DateTime.to_iso8601(commit.author_date),
            RDF.XSD.DateTime
          )
          | triples
        ]
      else
        triples
      end

    # Commit date
    triples =
      if commit.commit_date do
        [
          Helpers.datatype_property(
            commit_iri,
            Evolution.committedAt(),
            DateTime.to_iso8601(commit.commit_date),
            RDF.XSD.DateTime
          )
          | triples
        ]
      else
        triples
      end

    # Add PROV-O timestamps as well
    triples =
      if commit.author_date do
        [
          Helpers.datatype_property(
            commit_iri,
            PROV.startedAtTime(),
            DateTime.to_iso8601(commit.author_date),
            RDF.XSD.DateTime
          )
          | triples
        ]
      else
        triples
      end

    triples =
      if commit.commit_date do
        [
          Helpers.datatype_property(
            commit_iri,
            PROV.endedAtTime(),
            DateTime.to_iso8601(commit.commit_date),
            RDF.XSD.DateTime
          )
          | triples
        ]
      else
        triples
      end

    triples
  end

  # ===========================================================================
  # Parent Commit Triples Generation
  # ===========================================================================

  defp build_parent_triples(commit_iri, commit, context) do
    Enum.map(commit.parents, fn parent_sha ->
      parent_iri = generate_parent_iri(parent_sha, context)
      Helpers.object_property(commit_iri, Evolution.parentCommit(), parent_iri)
    end)
  end

  defp generate_parent_iri(parent_sha, context) do
    base = to_string(context.base_iri)

    case Map.get(context.metadata, :repo_iri) do
      nil ->
        RDF.iri("#{base}commit/#{parent_sha}")

      repo_iri ->
        RDF.iri("#{to_string(repo_iri)}/commit/#{parent_sha}")
    end
  end
end
