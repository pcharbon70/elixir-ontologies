defmodule ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder do
  @moduledoc """
  Builds RDF triples for codebase snapshots and releases.

  This module transforms `ElixirOntologies.Extractors.Evolution.Snapshot` and
  `ElixirOntologies.Extractors.Evolution.Release` results into RDF triples
  following the elixir-evolution.ttl ontology.

  ## Usage

      alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.Evolution.{Snapshot, Release}

      {:ok, snapshot} = Snapshot.extract_snapshot(".")
      context = Context.new(base_iri: "https://example.org/code#")
      {snapshot_iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)

      {:ok, releases} = Release.extract_releases(".")
      all_triples = SnapshotReleaseBuilder.build_all_triples(releases, context)

  ## Snapshot RDF Output

      snapshot:abc123d a evo:CodebaseSnapshot, prov:Entity ;
          evo:snapshotId "snapshot:abc123d" ;
          evo:commitHash "abc123..." ;
          evo:projectName "elixir_ontologies" ;
          evo:moduleCount 42 ;
          prov:generatedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime .

  ## Release RDF Output

      release:v1.2.3 a evo:Release, prov:Entity ;
          evo:releaseId "release:v1.2.3" ;
          evo:releaseVersion "1.2.3" ;
          evo:releaseTag "v1.2.3" ;
          evo:hasSemanticVersion [
              a evo:SemanticVersion ;
              evo:majorVersion 1 ;
              evo:minorVersion 2 ;
              evo:patchVersion 3
          ] ;
          prov:generatedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime .

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> snapshot = %Snapshot{
      ...>   snapshot_id: "snapshot:abc123d",
      ...>   commit_sha: "abc123def456789012345678901234567890abcd",
      ...>   short_sha: "abc123d",
      ...>   project_name: :my_app,
      ...>   stats: %{module_count: 10, function_count: 50, macro_count: 2,
      ...>           protocol_count: 1, behaviour_count: 1, line_count: 1000, file_count: 10}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)
      iex> length(triples) > 0
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.Evolution.{Snapshot, Release}
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a Snapshot or Release struct.

  Takes a snapshot or release struct and builder context, returns the entity IRI
  and a list of RDF triples representing it in the ontology.

  ## Parameters

  - `entity` - Snapshot or Release struct
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{entity_iri, triples}` where:
  - `entity_iri` - The IRI of the snapshot or release
  - `triples` - List of RDF triples describing the entity

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.Snapshot
      iex> snapshot = %Snapshot{
      ...>   snapshot_id: "snapshot:def456e",
      ...>   commit_sha: "def456e789012345678901234567890abcdef01",
      ...>   short_sha: "def456e",
      ...>   stats: %{module_count: 5, function_count: 20, macro_count: 0,
      ...>           protocol_count: 0, behaviour_count: 0, line_count: 500, file_count: 5}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(Snapshot.t() | Release.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%Snapshot{} = snapshot, %Context{} = context) do
    build_snapshot(snapshot, context)
  end

  def build(%Release{} = release, %Context{} = context) do
    build_release(release, context)
  end

  @doc """
  Builds RDF triples for multiple snapshots or releases.

  ## Parameters

  - `entities` - List of Snapshot or Release structs
  - `context` - Builder context

  ## Returns

  A list of `{entity_iri, triples}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> results = SnapshotReleaseBuilder.build_all([], context)
      iex> results
      []
  """
  @spec build_all([Snapshot.t() | Release.t()], Context.t()) ::
          [{RDF.IRI.t(), [RDF.Triple.t()]}]
  def build_all(entities, context) when is_list(entities) do
    Enum.map(entities, &build(&1, context))
  end

  @doc """
  Builds RDF triples for multiple entities and collects all triples.

  Returns a flat list of all triples from all entities.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = SnapshotReleaseBuilder.build_all_triples([], context)
      iex> triples
      []
  """
  @spec build_all_triples([Snapshot.t() | Release.t()], Context.t()) :: [RDF.Triple.t()]
  def build_all_triples(entities, context) when is_list(entities) do
    entities
    |> build_all(context)
    |> Enum.flat_map(fn {_iri, triples} -> triples end)
  end

  # ===========================================================================
  # Snapshot Building
  # ===========================================================================

  defp build_snapshot(snapshot, context) do
    snapshot_iri = generate_snapshot_iri(snapshot, context)

    triples =
      [
        build_snapshot_type_triples(snapshot_iri),
        build_snapshot_id_triples(snapshot_iri, snapshot),
        build_snapshot_hash_triples(snapshot_iri, snapshot),
        build_snapshot_project_triples(snapshot_iri, snapshot),
        build_snapshot_stats_triples(snapshot_iri, snapshot),
        build_snapshot_timestamp_triple(snapshot_iri, snapshot)
      ]
      |> Helpers.finalize_triples()

    {snapshot_iri, triples}
  end

  defp generate_snapshot_iri(snapshot, context) do
    base = to_string(context.base_iri)
    encoded_id = URI.encode(snapshot.short_sha, &URI.char_unreserved?/1)
    RDF.iri("#{base}snapshot/#{encoded_id}")
  end

  defp build_snapshot_type_triples(snapshot_iri) do
    Helpers.dual_type_triples(snapshot_iri, PROV.Entity, Evolution.CodebaseSnapshot)
  end

  defp build_snapshot_id_triples(snapshot_iri, snapshot) do
    [
      # Use versionString to store the snapshot ID
      Helpers.datatype_property(
        snapshot_iri,
        Evolution.versionString(),
        snapshot.snapshot_id,
        RDF.XSD.String
      )
    ]
  end

  defp build_snapshot_hash_triples(snapshot_iri, snapshot) do
    [
      Helpers.datatype_property(
        snapshot_iri,
        Evolution.commitHash(),
        snapshot.commit_sha,
        RDF.XSD.String
      ),
      Helpers.datatype_property(
        snapshot_iri,
        Evolution.shortHash(),
        snapshot.short_sha,
        RDF.XSD.String
      )
    ]
  end

  defp build_snapshot_project_triples(snapshot_iri, snapshot) do
    [
      build_project_name_triple(snapshot_iri, snapshot.project_name),
      build_project_version_triple(snapshot_iri, snapshot.project_version)
    ]
  end

  defp build_project_name_triple(_iri, nil), do: nil

  defp build_project_name_triple(iri, name) when is_atom(name) do
    # Use repositoryName for project name
    Helpers.datatype_property(iri, Evolution.repositoryName(), to_string(name), RDF.XSD.String)
  end

  defp build_project_name_triple(iri, name) when is_binary(name) do
    Helpers.datatype_property(iri, Evolution.repositoryName(), name, RDF.XSD.String)
  end

  defp build_project_version_triple(_iri, nil), do: nil

  defp build_project_version_triple(iri, version) when is_binary(version) do
    # Use versionString for project version info (different from snapshot ID)
    # We use a separate IRI for project-level version
    Helpers.datatype_property(iri, RDF.iri("https://w3id.org/elixir-code/evolution#projectVersion"), version, RDF.XSD.String)
  end

  defp build_project_version_triple(_iri, _version), do: nil

  # Evolution namespace base for custom properties not in the ontology
  @evo_base "https://w3id.org/elixir-code/evolution#"

  defp build_snapshot_stats_triples(snapshot_iri, snapshot) do
    stats = snapshot.stats || %{}

    # These are custom properties not defined in the ontology
    # We use raw IRIs for snapshot-specific statistics
    [
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}moduleCount"), stats[:module_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}functionCount"), stats[:function_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}macroCount"), stats[:macro_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}protocolCount"), stats[:protocol_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}behaviourCount"), stats[:behaviour_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}lineCount"), stats[:line_count]),
      build_stat_triple(snapshot_iri, RDF.iri("#{@evo_base}fileCount"), stats[:file_count])
    ]
  end

  defp build_stat_triple(_iri, _predicate, nil), do: nil

  defp build_stat_triple(iri, predicate, value) when is_integer(value) do
    Helpers.datatype_property(iri, predicate, value, RDF.XSD.Integer)
  end

  defp build_snapshot_timestamp_triple(snapshot_iri, snapshot) do
    Helpers.optional_datetime_property(
      snapshot_iri,
      PROV.generatedAtTime(),
      snapshot.timestamp
    )
  end

  # ===========================================================================
  # Release Building
  # ===========================================================================

  defp build_release(release, context) do
    release_iri = generate_release_iri(release, context)

    triples =
      [
        build_release_type_triples(release_iri),
        build_release_id_triples(release_iri, release),
        build_release_version_triples(release_iri, release),
        build_release_tag_triple(release_iri, release),
        build_release_hash_triples(release_iri, release),
        build_release_project_triple(release_iri, release),
        build_release_semver_triples(release_iri, release),
        build_release_previous_triple(release_iri, release, context),
        build_release_timestamp_triple(release_iri, release)
      ]
      |> Helpers.finalize_triples()

    {release_iri, triples}
  end

  defp generate_release_iri(release, context) do
    base = to_string(context.base_iri)
    # Use tag if available, otherwise version
    id = release.tag || release.version
    encoded_id = URI.encode(id, &URI.char_unreserved?/1)
    RDF.iri("#{base}release/#{encoded_id}")
  end

  defp build_release_type_triples(release_iri) do
    Helpers.dual_type_triples(release_iri, PROV.Entity, Evolution.Release)
  end

  defp build_release_id_triples(release_iri, release) do
    [
      # Use versionString for release ID
      Helpers.datatype_property(
        release_iri,
        Evolution.versionString(),
        release.release_id,
        RDF.XSD.String
      )
    ]
  end

  defp build_release_version_triples(release_iri, release) do
    [
      # Use raw IRI for release version
      Helpers.datatype_property(
        release_iri,
        RDF.iri("#{@evo_base}releaseVersion"),
        release.version,
        RDF.XSD.String
      )
    ]
  end

  defp build_release_tag_triple(_release_iri, %{tag: nil}), do: nil

  defp build_release_tag_triple(release_iri, release) do
    # Use tagName from the ontology
    Helpers.datatype_property(
      release_iri,
      Evolution.tagName(),
      release.tag,
      RDF.XSD.String
    )
  end

  defp build_release_hash_triples(release_iri, release) do
    [
      Helpers.datatype_property(
        release_iri,
        Evolution.commitHash(),
        release.commit_sha,
        RDF.XSD.String
      ),
      Helpers.datatype_property(
        release_iri,
        Evolution.shortHash(),
        release.short_sha,
        RDF.XSD.String
      )
    ]
  end

  defp build_release_project_triple(_release_iri, %{project_name: nil}), do: nil

  defp build_release_project_triple(release_iri, release) do
    name =
      if is_atom(release.project_name),
        do: to_string(release.project_name),
        else: release.project_name

    Helpers.datatype_property(release_iri, Evolution.repositoryName(), name, RDF.XSD.String)
  end

  defp build_release_semver_triples(_release_iri, %{semver: nil}), do: []

  defp build_release_semver_triples(release_iri, release) do
    # Create a blank node for the semantic version
    semver_node = RDF.bnode()
    semver = release.semver

    [
      # Link release to semver blank node - use raw IRI since hasSemanticVersion may not exist
      {release_iri, RDF.iri("#{@evo_base}hasSemanticVersion"), semver_node},
      # Type the blank node
      Helpers.type_triple(semver_node, Evolution.SemanticVersion),
      # Add version components
      Helpers.datatype_property(semver_node, Evolution.majorVersion(), semver.major, RDF.XSD.Integer),
      Helpers.datatype_property(semver_node, Evolution.minorVersion(), semver.minor, RDF.XSD.Integer),
      Helpers.datatype_property(semver_node, Evolution.patchVersion(), semver.patch, RDF.XSD.Integer),
      build_prerelease_triple(semver_node, semver.pre_release),
      build_build_triple(semver_node, semver.build)
    ]
  end

  defp build_prerelease_triple(_node, nil), do: nil

  defp build_prerelease_triple(node, pre_release) do
    # Use prereleaseLabel from ontology
    Helpers.datatype_property(node, Evolution.prereleaseLabel(), pre_release, RDF.XSD.String)
  end

  defp build_build_triple(_node, nil), do: nil

  defp build_build_triple(node, build) do
    Helpers.datatype_property(node, Evolution.buildMetadata(), build, RDF.XSD.String)
  end

  defp build_release_previous_triple(_release_iri, %{previous_version: nil}, _context), do: nil

  defp build_release_previous_triple(release_iri, release, context) do
    base = to_string(context.base_iri)
    # Generate IRI for previous release based on version
    encoded_version = URI.encode(release.previous_version, &URI.char_unreserved?/1)
    previous_iri = RDF.iri("#{base}release/#{encoded_version}")

    # Use hasPreviousVersion from ontology
    {release_iri, Evolution.hasPreviousVersion(), previous_iri}
  end

  defp build_release_timestamp_triple(release_iri, release) do
    Helpers.optional_datetime_property(
      release_iri,
      PROV.generatedAtTime(),
      release.timestamp
    )
  end
end
