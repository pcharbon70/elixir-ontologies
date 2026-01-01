defmodule ElixirOntologies.Builders.Evolution.VersionBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.Evolution.VersionBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Evolution.EntityVersion.{ModuleVersion, FunctionVersion}
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_module_version(opts \\ []) do
    defaults = %{
      module_name: "MyApp.UserController",
      version_id: "MyApp.UserController@abc123d",
      commit_sha: "abc123def456789012345678901234567890abcd",
      short_sha: "abc123d",
      previous_version: nil,
      file_path: "lib/my_app/user_controller.ex",
      content_hash: "sha256:abc123def456",
      functions: ["create/1", "update/2"],
      line_count: 150,
      timestamp: nil,
      metadata: %{}
    }

    struct(ModuleVersion, Map.merge(defaults, Map.new(opts)))
  end

  defp create_function_version(opts \\ []) do
    defaults = %{
      module_name: "MyApp.UserController",
      function_name: :create,
      arity: 1,
      version_id: "MyApp.UserController.create/1@abc123d",
      commit_sha: "abc123def456789012345678901234567890abcd",
      short_sha: "abc123d",
      previous_version: nil,
      content_hash: "sha256:func123def456",
      line_range: {10, 25},
      clause_count: 2,
      timestamp: nil,
      metadata: %{}
    }

    struct(FunctionVersion, Map.merge(defaults, Map.new(opts)))
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
  # Basic Build Tests - ModuleVersion
  # ===========================================================================

  describe "build/2 with ModuleVersion" do
    test "returns version IRI and triples" do
      version = create_module_version()
      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates stable IRI from version_id" do
      version = create_module_version(version_id: "MyApp.User@def456e")
      context = create_context()

      {version_iri, _triples} = VersionBuilder.build(version, context)

      assert to_string(version_iri) == "https://example.org/code#version/MyApp.User%40def456e"
    end

    test "same version produces same IRI" do
      version = create_module_version()
      context = create_context()

      {iri1, _} = VersionBuilder.build(version, context)
      {iri2, _} = VersionBuilder.build(version, context)

      assert iri1 == iri2
    end
  end

  # ===========================================================================
  # Basic Build Tests - FunctionVersion
  # ===========================================================================

  describe "build/2 with FunctionVersion" do
    test "returns version IRI and triples" do
      version = create_function_version()
      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates URL-encoded IRI from version_id with slash" do
      version = create_function_version(version_id: "MyApp.User.create/1@def456e")
      context = create_context()

      {version_iri, _triples} = VersionBuilder.build(version, context)

      # The / should be URL-encoded as %2F
      assert to_string(version_iri) ==
               "https://example.org/code#version/MyApp.User.create%2F1%40def456e"
    end

    test "same function version produces same IRI" do
      version = create_function_version()
      context = create_context()

      {iri1, _} = VersionBuilder.build(version, context)
      {iri2, _} = VersionBuilder.build(version, context)

      assert iri1 == iri2
    end
  end

  # ===========================================================================
  # Type Triple Tests
  # ===========================================================================

  describe "type triples" do
    test "generates prov:Entity type for ModuleVersion" do
      version = create_module_version()
      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      type_triples = find_triples(triples, RDF.type())
      assert length(type_triples) == 2

      types = Enum.map(type_triples, fn {^version_iri, _, o} -> o end)
      assert PROV.Entity in types
      assert RDF.iri(Evolution.ModuleVersion) in types
    end

    test "generates prov:Entity type for FunctionVersion" do
      version = create_function_version()
      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      type_triples = find_triples(triples, RDF.type())
      assert length(type_triples) == 2

      types = Enum.map(type_triples, fn {^version_iri, _, o} -> o end)
      assert PROV.Entity in types
      assert RDF.iri(Evolution.FunctionVersion) in types
    end
  end

  # ===========================================================================
  # version_type_to_class Tests
  # ===========================================================================

  describe "version_type_to_class/1" do
    test "maps :module to Evolution.ModuleVersion" do
      assert VersionBuilder.version_type_to_class(:module) == RDF.iri(Evolution.ModuleVersion)
    end

    test "maps :function to Evolution.FunctionVersion" do
      assert VersionBuilder.version_type_to_class(:function) == RDF.iri(Evolution.FunctionVersion)
    end

    test "maps :type to Evolution.TypeVersion" do
      assert VersionBuilder.version_type_to_class(:type) == RDF.iri(Evolution.TypeVersion)
    end

    test "maps unknown types to Evolution.CodeVersion" do
      assert VersionBuilder.version_type_to_class(:unknown) == RDF.iri(Evolution.CodeVersion)
      assert VersionBuilder.version_type_to_class(:other) == RDF.iri(Evolution.CodeVersion)
    end
  end

  # ===========================================================================
  # Version String Triple Tests
  # ===========================================================================

  describe "version string triples" do
    test "generates versionString for ModuleVersion" do
      version = create_module_version(version_id: "MyApp.User@abc123d")
      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      version_string_value = get_object(triples, Evolution.versionString())
      assert version_string_value != nil
      assert RDF.Literal.value(version_string_value) == "MyApp.User@abc123d"
    end

    test "generates versionString for FunctionVersion" do
      version = create_function_version(version_id: "MyApp.User.create/1@abc123d")
      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      version_string_value = get_object(triples, Evolution.versionString())
      assert version_string_value != nil
      assert RDF.Literal.value(version_string_value) == "MyApp.User.create/1@abc123d"
    end
  end

  # ===========================================================================
  # Previous Version Triple Tests
  # ===========================================================================

  describe "previous version triples" do
    test "generates hasPreviousVersion for ModuleVersion with previous" do
      version =
        create_module_version(
          version_id: "MyApp.User@abc123d",
          previous_version: "MyApp.User@def456e"
        )

      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      prev_triple = find_triple(triples, Evolution.hasPreviousVersion())
      assert prev_triple != nil

      {_, _, prev_iri} = prev_triple
      assert to_string(prev_iri) =~ "MyApp.User%40def456e"
    end

    test "generates hasPreviousVersion for FunctionVersion with previous" do
      version =
        create_function_version(
          version_id: "MyApp.User.create/1@abc123d",
          previous_version: "MyApp.User.create/1@def456e"
        )

      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      prev_triple = find_triple(triples, Evolution.hasPreviousVersion())
      assert prev_triple != nil

      {_, _, prev_iri} = prev_triple
      assert to_string(prev_iri) =~ "MyApp.User.create%2F1%40def456e"
    end

    test "omits hasPreviousVersion when previous_version is nil" do
      version = create_module_version(previous_version: nil)
      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      prev_triple = find_triple(triples, Evolution.hasPreviousVersion())
      assert prev_triple == nil
    end
  end

  # ===========================================================================
  # Timestamp Triple Tests
  # ===========================================================================

  describe "timestamp triples" do
    test "generates prov:generatedAtTime when timestamp present" do
      timestamp = ~U[2025-01-15 10:30:00Z]
      version = create_module_version(timestamp: timestamp)
      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      timestamp_value = get_object(triples, PROV.generatedAtTime())
      assert timestamp_value != nil
      assert RDF.Literal.value(timestamp_value) == timestamp
    end

    test "omits prov:generatedAtTime when timestamp is nil" do
      version = create_module_version(timestamp: nil)
      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      timestamp_triple = find_triple(triples, PROV.generatedAtTime())
      assert timestamp_triple == nil
    end
  end

  # ===========================================================================
  # Build All Tests
  # ===========================================================================

  describe "build_all/2" do
    test "builds multiple versions" do
      versions = [
        create_module_version(version_id: "MyApp.User@abc123d"),
        create_function_version(version_id: "MyApp.User.create/1@abc123d")
      ]

      context = create_context()

      results = VersionBuilder.build_all(versions, context)

      assert length(results) == 2

      Enum.each(results, fn {iri, triples} ->
        assert %RDF.IRI{} = iri
        assert is_list(triples)
      end)
    end

    test "returns empty list for empty input" do
      context = create_context()
      results = VersionBuilder.build_all([], context)
      assert results == []
    end
  end

  describe "build_all_triples/2" do
    test "returns flat list of all triples" do
      versions = [
        create_module_version(version_id: "MyApp.User@abc123d"),
        create_function_version(version_id: "MyApp.User.create/1@abc123d")
      ]

      context = create_context()

      triples = VersionBuilder.build_all_triples(versions, context)

      assert is_list(triples)
      # Each version should have at least 2 type triples + 1 version string
      assert length(triples) >= 6
    end

    test "returns empty list for empty input" do
      context = create_context()
      triples = VersionBuilder.build_all_triples([], context)
      assert triples == []
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles minimal ModuleVersion with only required fields" do
      version = %ModuleVersion{
        module_name: "Minimal",
        version_id: "Minimal@abc123d",
        commit_sha: "abc123def456789012345678901234567890abcd",
        short_sha: "abc123d",
        file_path: "lib/minimal.ex",
        content_hash: "sha256:minimal"
      }

      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      # Should have at least type triples + version string
      assert length(triples) >= 3
    end

    test "handles minimal FunctionVersion with only required fields" do
      version = %FunctionVersion{
        module_name: "Minimal",
        function_name: :foo,
        arity: 0,
        version_id: "Minimal.foo/0@abc123d",
        commit_sha: "abc123def456789012345678901234567890abcd",
        short_sha: "abc123d",
        content_hash: "sha256:minimal"
      }

      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      # Should have at least type triples + version string
      assert length(triples) >= 3
    end

    test "handles ModuleVersion with all fields populated" do
      version =
        create_module_version(
          previous_version: "MyApp.User@def456e",
          timestamp: ~U[2025-01-15 10:30:00Z],
          metadata: %{branch: "main"}
        )

      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      # type + version string + previous + timestamp
      assert length(triples) >= 5
    end

    test "handles special characters in module name" do
      version =
        create_module_version(
          module_name: "MyApp.Users.External",
          version_id: "MyApp.Users.External@abc123d"
        )

      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      assert length(triples) >= 3
    end

    test "handles unicode in module name" do
      version =
        create_module_version(
          module_name: "MyApp.ユーザー",
          version_id: "MyApp.ユーザー@abc123d"
        )

      context = create_context()

      {_version_iri, triples} = VersionBuilder.build(version, context)

      version_string_value = get_object(triples, Evolution.versionString())
      assert RDF.Literal.value(version_string_value) == "MyApp.ユーザー@abc123d"
    end

    test "handles high arity function version" do
      version =
        create_function_version(
          function_name: :complex_function,
          arity: 10,
          version_id: "MyApp.Complex.complex_function/10@abc123d"
        )

      context = create_context()

      {version_iri, triples} = VersionBuilder.build(version, context)

      assert %RDF.IRI{} = version_iri
      version_string_value = get_object(triples, Evolution.versionString())
      assert RDF.Literal.value(version_string_value) =~ "/10@"
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "builds from real module version extraction" do
      alias ElixirOntologies.Extractors.Evolution.EntityVersion

      case EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD") do
        {:ok, version} ->
          context = create_context()

          {version_iri, triples} = VersionBuilder.build(version, context)

          assert %RDF.IRI{} = version_iri
          assert length(triples) > 0

          # Verify type triples
          type_triples = find_triples(triples, RDF.type())
          assert length(type_triples) == 2

          # Verify version string
          version_string_value = get_object(triples, Evolution.versionString())
          assert version_string_value != nil

        {:error, _reason} ->
          # Module might not exist in test environment
          :ok
      end
    end
  end
end
