defmodule ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.Evolution.SnapshotReleaseBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Evolution.{Snapshot, Release}
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Test Setup
  # ===========================================================================

  @base_iri "https://example.org/code#"

  defp default_context do
    Context.new(base_iri: @base_iri)
  end

  defp sample_snapshot do
    %Snapshot{
      snapshot_id: "snapshot:abc123d",
      commit_sha: "abc123def456789012345678901234567890abcd",
      short_sha: "abc123d",
      timestamp: ~U[2025-01-15 10:30:00Z],
      project_name: :elixir_ontologies,
      project_version: "0.1.0",
      modules: ["MyApp.User", "MyApp.Repo"],
      files: ["lib/my_app/user.ex", "lib/my_app/repo.ex"],
      stats: %{
        module_count: 42,
        function_count: 156,
        macro_count: 5,
        protocol_count: 2,
        behaviour_count: 3,
        line_count: 5234,
        file_count: 42
      },
      metadata: %{}
    }
  end

  defp sample_release do
    %Release{
      release_id: "release:v1.2.3",
      version: "1.2.3",
      tag: "v1.2.3",
      commit_sha: "abc123def456789012345678901234567890abcd",
      short_sha: "abc123d",
      timestamp: ~U[2025-01-15 10:30:00Z],
      semver: %{
        major: 1,
        minor: 2,
        patch: 3,
        pre_release: nil,
        build: nil
      },
      previous_version: "1.2.2",
      project_name: :elixir_ontologies,
      metadata: %{}
    }
  end

  # ===========================================================================
  # Snapshot Building Tests
  # ===========================================================================

  describe "build/2 with Snapshot" do
    test "returns IRI and triples tuple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates correct snapshot IRI" do
      {iri, _triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      assert to_string(iri) == "#{@base_iri}snapshot/abc123d"
    end

    test "generates type triples" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      # Should have prov:Entity type
      assert Enum.any?(triples, fn triple ->
        triple == {iri, RDF.type(), PROV.Entity}
      end)

      # Should have evo:CodebaseSnapshot type
      assert Enum.any?(triples, fn triple ->
        triple == {iri, RDF.type(), Evolution.CodebaseSnapshot}
      end)
    end

    test "generates snapshot ID triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      # Uses versionString for snapshot ID
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "snapshot:abc123d"}}} ->
          pred == Evolution.versionString()
        _ -> false
      end)
    end

    test "generates commit hash triple" do
      snapshot = sample_snapshot()
      {iri, triples} = SnapshotReleaseBuilder.build(snapshot, default_context())

      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: value}}} ->
          pred == Evolution.commitHash() and value == snapshot.commit_sha
        _ -> false
      end)
    end

    test "generates short hash triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "abc123d"}}} ->
          pred == Evolution.shortHash()
        _ -> false
      end)
    end

    test "generates project name triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      # Uses repositoryName for project name
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "elixir_ontologies"}}} ->
          pred == Evolution.repositoryName()
        _ -> false
      end)
    end

    test "generates project version triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      # Uses raw IRI for project version
      project_version_iri = RDF.iri("https://w3id.org/elixir-code/evolution#projectVersion")
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "0.1.0"}}} ->
          pred == project_version_iri
        _ -> false
      end)
    end

    test "generates statistics triples" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      # Module count - uses raw IRI
      module_count_iri = RDF.iri("https://w3id.org/elixir-code/evolution#moduleCount")
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 42}}} ->
          pred == module_count_iri
        _ -> false
      end)

      # Function count - uses raw IRI
      function_count_iri = RDF.iri("https://w3id.org/elixir-code/evolution#functionCount")
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 156}}} ->
          pred == function_count_iri
        _ -> false
      end)

      # Line count - uses raw IRI
      line_count_iri = RDF.iri("https://w3id.org/elixir-code/evolution#lineCount")
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 5234}}} ->
          pred == line_count_iri
        _ -> false
      end)
    end

    test "generates timestamp triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_snapshot(), default_context())

      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.DateTime{}}} ->
          pred == PROV.generatedAtTime()
        _ -> false
      end)
    end

    test "handles nil project name" do
      snapshot = %{sample_snapshot() | project_name: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(snapshot, default_context())

      # Should not crash, should not have project name triple
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == Evolution.repositoryName()
      end)
    end

    test "handles nil project version" do
      snapshot = %{sample_snapshot() | project_version: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(snapshot, default_context())

      project_version_iri = RDF.iri("https://w3id.org/elixir-code/evolution#projectVersion")
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == project_version_iri
      end)
    end

    test "handles nil timestamp" do
      snapshot = %{sample_snapshot() | timestamp: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(snapshot, default_context())

      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == PROV.generatedAtTime()
      end)
    end
  end

  # ===========================================================================
  # Release Building Tests
  # ===========================================================================

  describe "build/2 with Release" do
    test "returns IRI and triples tuple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      assert %RDF.IRI{} = iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates correct release IRI" do
      {iri, _triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      assert to_string(iri) == "#{@base_iri}release/v1.2.3"
    end

    test "generates type triples" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      assert Enum.any?(triples, fn triple ->
        triple == {iri, RDF.type(), PROV.Entity}
      end)

      assert Enum.any?(triples, fn triple ->
        triple == {iri, RDF.type(), Evolution.Release}
      end)
    end

    test "generates release ID triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      # Uses versionString for release ID
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "release:v1.2.3"}}} ->
          pred == Evolution.versionString()
        _ -> false
      end)
    end

    test "generates version triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      release_version_iri = RDF.iri("https://w3id.org/elixir-code/evolution#releaseVersion")
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "1.2.3"}}} ->
          pred == release_version_iri
        _ -> false
      end)
    end

    test "generates tag triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      # Uses tagName from ontology
      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "v1.2.3"}}} ->
          pred == Evolution.tagName()
        _ -> false
      end)
    end

    test "generates semantic version triples" do
      {_iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      # Should have SemanticVersion type on blank node
      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, class} ->
          pred == RDF.type() and class == Evolution.SemanticVersion
        _ -> false
      end)

      # Should have major version
      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 1}}} ->
          pred == Evolution.majorVersion()
        _ -> false
      end)

      # Should have minor version
      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 2}}} ->
          pred == Evolution.minorVersion()
        _ -> false
      end)

      # Should have patch version
      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, %RDF.Literal{literal: %RDF.XSD.Integer{value: 3}}} ->
          pred == Evolution.patchVersion()
        _ -> false
      end)
    end

    test "generates previous release link" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      expected_previous_iri = RDF.iri("#{@base_iri}release/1.2.2")

      # Uses hasPreviousVersion from ontology
      assert Enum.any?(triples, fn
        {^iri, pred, ^expected_previous_iri} ->
          pred == Evolution.hasPreviousVersion()
        _ -> false
      end)
    end

    test "generates timestamp triple" do
      {iri, triples} = SnapshotReleaseBuilder.build(sample_release(), default_context())

      assert Enum.any?(triples, fn
        {^iri, pred, %RDF.Literal{literal: %RDF.XSD.DateTime{}}} ->
          pred == PROV.generatedAtTime()
        _ -> false
      end)
    end

    test "handles nil tag" do
      release = %{sample_release() | tag: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(release, default_context())

      # Uses tagName from ontology
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == Evolution.tagName()
      end)
    end

    test "handles nil semver" do
      release = %{sample_release() | semver: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(release, default_context())

      # Uses raw IRI for hasSemanticVersion
      has_semver_iri = RDF.iri("https://w3id.org/elixir-code/evolution#hasSemanticVersion")
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == has_semver_iri
      end)
    end

    test "handles nil previous version" do
      release = %{sample_release() | previous_version: nil}
      {_iri, triples} = SnapshotReleaseBuilder.build(release, default_context())

      # Uses hasPreviousVersion from ontology
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == Evolution.hasPreviousVersion()
      end)
    end

    test "handles pre-release version" do
      semver = %{major: 1, minor: 0, patch: 0, pre_release: "alpha.1", build: nil}
      release = %{sample_release() | semver: semver}
      {_iri, triples} = SnapshotReleaseBuilder.build(release, default_context())

      # Uses prereleaseLabel from ontology
      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "alpha.1"}}} ->
          pred == Evolution.prereleaseLabel()
        _ -> false
      end)
    end

    test "handles build metadata" do
      semver = %{major: 1, minor: 0, patch: 0, pre_release: nil, build: "build.123"}
      release = %{sample_release() | semver: semver}
      {_iri, triples} = SnapshotReleaseBuilder.build(release, default_context())

      assert Enum.any?(triples, fn
        {%RDF.BlankNode{}, pred, %RDF.Literal{literal: %RDF.XSD.String{value: "build.123"}}} ->
          pred == Evolution.buildMetadata()
        _ -> false
      end)
    end
  end

  # ===========================================================================
  # Batch Operation Tests
  # ===========================================================================

  describe "build_all/2" do
    test "returns empty list for empty input" do
      assert [] == SnapshotReleaseBuilder.build_all([], default_context())
    end

    test "builds multiple snapshots" do
      snapshots = [
        sample_snapshot(),
        %{sample_snapshot() | snapshot_id: "snapshot:def456e", short_sha: "def456e"}
      ]

      results = SnapshotReleaseBuilder.build_all(snapshots, default_context())

      assert length(results) == 2
      assert Enum.all?(results, fn {iri, triples} ->
        %RDF.IRI{} = iri
        is_list(triples) and length(triples) > 0
      end)
    end

    test "builds multiple releases" do
      releases = [
        sample_release(),
        %{sample_release() | release_id: "release:v1.2.2", version: "1.2.2", tag: "v1.2.2"}
      ]

      results = SnapshotReleaseBuilder.build_all(releases, default_context())

      assert length(results) == 2
    end

    test "builds mixed snapshots and releases" do
      entities = [sample_snapshot(), sample_release()]

      results = SnapshotReleaseBuilder.build_all(entities, default_context())

      assert length(results) == 2
    end
  end

  describe "build_all_triples/2" do
    test "returns empty list for empty input" do
      assert [] == SnapshotReleaseBuilder.build_all_triples([], default_context())
    end

    test "returns flat list of triples" do
      entities = [sample_snapshot(), sample_release()]

      triples = SnapshotReleaseBuilder.build_all_triples(entities, default_context())

      assert is_list(triples)
      assert length(triples) > 0
      # All items should be triples
      assert Enum.all?(triples, fn
        {_, _, _} -> true
        _ -> false
      end)
    end
  end

  # ===========================================================================
  # IRI Stability Tests
  # ===========================================================================

  describe "IRI stability" do
    test "snapshot IRI is deterministic" do
      snapshot = sample_snapshot()
      context = default_context()

      {iri1, _} = SnapshotReleaseBuilder.build(snapshot, context)
      {iri2, _} = SnapshotReleaseBuilder.build(snapshot, context)

      assert iri1 == iri2
    end

    test "release IRI is deterministic" do
      release = sample_release()
      context = default_context()

      {iri1, _} = SnapshotReleaseBuilder.build(release, context)
      {iri2, _} = SnapshotReleaseBuilder.build(release, context)

      assert iri1 == iri2
    end

    test "release IRI uses tag when available" do
      release = sample_release()
      {iri, _} = SnapshotReleaseBuilder.build(release, default_context())

      assert String.contains?(to_string(iri), "v1.2.3")
    end

    test "release IRI uses version when tag is nil" do
      release = %{sample_release() | tag: nil}
      {iri, _} = SnapshotReleaseBuilder.build(release, default_context())

      assert String.contains?(to_string(iri), "1.2.3")
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "builds snapshot from real extraction" do
      case Snapshot.extract_snapshot(".") do
        {:ok, snapshot} ->
          context = default_context()
          {iri, triples} = SnapshotReleaseBuilder.build(snapshot, context)

          assert %RDF.IRI{} = iri
          assert length(triples) > 0

          # Verify has expected predicates
          predicates = Enum.map(triples, fn {_, p, _} -> p end) |> Enum.uniq()
          assert RDF.type() in predicates
          assert Evolution.versionString() in predicates
          assert Evolution.commitHash() in predicates

        {:error, _} ->
          # Skip if can't extract
          :ok
      end
    end

    @tag :integration
    test "builds releases from real extraction" do
      case Release.extract_releases(".") do
        {:ok, releases} when releases != [] ->
          context = default_context()
          triples = SnapshotReleaseBuilder.build_all_triples(releases, context)

          assert is_list(triples)
          # Should have at least type triples for each release
          assert length(triples) >= length(releases) * 2

        _ ->
          # Skip if no releases
          :ok
      end
    end
  end
end
