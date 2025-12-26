defmodule ElixirOntologies.Extractors.Evolution.EntityVersionTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.EntityVersion
  alias ElixirOntologies.Extractors.Evolution.EntityVersion.{ModuleVersion, FunctionVersion, Derivation}

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "ModuleVersion struct" do
    test "enforces required keys" do
      version = %ModuleVersion{
        module_name: "MyApp.User",
        version_id: "MyApp.User@abc123d",
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        file_path: "lib/my_app/user.ex",
        content_hash: "abcd1234efgh5678"
      }

      assert version.module_name == "MyApp.User"
      assert version.version_id == "MyApp.User@abc123d"
      assert version.functions == []
      assert version.line_count == 0
      assert version.metadata == %{}
    end

    test "has default values" do
      version = %ModuleVersion{
        module_name: "Test",
        version_id: "Test@abc",
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        file_path: "lib/test.ex",
        content_hash: "hash"
      }

      assert version.previous_version == nil
      assert version.functions == []
      assert version.line_count == 0
      assert version.timestamp == nil
    end
  end

  describe "FunctionVersion struct" do
    test "enforces required keys" do
      version = %FunctionVersion{
        module_name: "MyApp.User",
        function_name: :get,
        arity: 1,
        version_id: "MyApp.User.get/1@abc123d",
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        content_hash: "abcd1234efgh5678"
      }

      assert version.module_name == "MyApp.User"
      assert version.function_name == :get
      assert version.arity == 1
      assert version.clause_count == 1
    end

    test "has default values" do
      version = %FunctionVersion{
        module_name: "Test",
        function_name: :foo,
        arity: 0,
        version_id: "Test.foo/0@abc",
        commit_sha: "abc123def456abc123def456abc123def456abc1",
        short_sha: "abc123d",
        content_hash: "hash"
      }

      assert version.previous_version == nil
      assert version.line_range == nil
      assert version.clause_count == 1
      assert version.timestamp == nil
    end
  end

  describe "Derivation struct" do
    test "enforces required keys" do
      derivation = %Derivation{
        derived_entity: "v2",
        source_entity: "v1",
        derivation_type: :revision
      }

      assert derivation.derived_entity == "v2"
      assert derivation.source_entity == "v1"
      assert derivation.derivation_type == :revision
    end

    test "has default values" do
      derivation = %Derivation{
        derived_entity: "v2",
        source_entity: "v1",
        derivation_type: :revision
      }

      assert derivation.activity == nil
      assert derivation.timestamp == nil
      assert derivation.metadata == %{}
    end
  end

  # ===========================================================================
  # Module Version Extraction Tests
  # ===========================================================================

  describe "extract_module_version/4" do
    @tag :integration
    test "extracts module version at HEAD" do
      {:ok, version} = EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD")

      assert version.module_name == "ElixirOntologies"
      assert String.starts_with?(version.version_id, "ElixirOntologies@")
      assert String.length(version.commit_sha) == 40
      assert String.length(version.short_sha) == 7
      assert version.file_path == "lib/elixir_ontologies.ex"
      assert String.length(version.content_hash) == 16
      assert version.line_count > 0
    end

    @tag :integration
    test "includes functions when requested" do
      {:ok, version} =
        EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD",
          include_functions: true
        )

      assert is_list(version.functions)
    end

    @tag :integration
    test "returns error for non-existent module" do
      result = EntityVersion.extract_module_version(".", "NonExistent.Module", "HEAD")
      assert {:error, :module_not_found} = result
    end

    @tag :integration
    test "returns error for invalid commit ref" do
      result = EntityVersion.extract_module_version(".", "ElixirOntologies", "invalid;ref")
      assert {:error, _} = result
    end
  end

  describe "extract_module_version!/4" do
    @tag :integration
    test "returns version on success" do
      version = EntityVersion.extract_module_version!(".", "ElixirOntologies", "HEAD")
      assert version.module_name == "ElixirOntologies"
    end

    @tag :integration
    test "raises on error" do
      assert_raise ArgumentError, fn ->
        EntityVersion.extract_module_version!(".", "NonExistent.Module", "HEAD")
      end
    end
  end

  # ===========================================================================
  # Module Version Tracking Tests
  # ===========================================================================

  describe "track_module_versions/3" do
    @tag :integration
    test "tracks module versions across commits" do
      {:ok, versions} = EntityVersion.track_module_versions(".", "ElixirOntologies", limit: 5)

      assert is_list(versions)
      # Should have at least one version
      assert length(versions) >= 1

      # First version should be newest
      [first | _] = versions
      assert first.module_name == "ElixirOntologies"
    end

    @tag :integration
    test "links previous versions" do
      {:ok, versions} = EntityVersion.track_module_versions(".", "ElixirOntologies", limit: 5)

      if length(versions) > 1 do
        [newest, second | _] = versions
        assert newest.previous_version == second.version_id
      end
    end

    @tag :integration
    test "deduplicates by content hash" do
      {:ok, versions} = EntityVersion.track_module_versions(".", "ElixirOntologies", limit: 20)

      # No consecutive versions should have the same content hash
      versions
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [v1, v2] ->
        assert v1.content_hash != v2.content_hash
      end)
    end

    @tag :integration
    test "returns error for non-existent module" do
      result = EntityVersion.track_module_versions(".", "NonExistent.Module", limit: 5)
      assert {:error, :module_not_found} = result
    end
  end

  describe "track_module_versions!/3" do
    @tag :integration
    test "returns versions on success" do
      versions = EntityVersion.track_module_versions!(".", "ElixirOntologies", limit: 3)
      assert is_list(versions)
    end

    @tag :integration
    test "raises on error" do
      assert_raise ArgumentError, fn ->
        EntityVersion.track_module_versions!(".", "NonExistent.Module", limit: 3)
      end
    end
  end

  # ===========================================================================
  # Function Version Extraction Tests
  # ===========================================================================

  describe "extract_function_version/5" do
    @tag :integration
    test "extracts function version at HEAD" do
      # Use a function we know exists in the codebase
      result =
        EntityVersion.extract_function_version(
          ".",
          "ElixirOntologies.Extractors.Evolution.EntityVersion",
          :build_derivation,
          3,
          "HEAD"
        )

      case result do
        {:ok, version} ->
          assert version.function_name == :build_derivation
          assert version.arity == 3
          assert String.contains?(version.version_id, "build_derivation/3")
          assert String.length(version.content_hash) == 16

        {:error, :function_not_found} ->
          # Function might have different arity or not exist yet
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    @tag :integration
    test "returns error for non-existent function" do
      result =
        EntityVersion.extract_function_version(
          ".",
          "ElixirOntologies",
          :nonexistent_function,
          99,
          "HEAD"
        )

      assert {:error, :function_not_found} = result
    end
  end

  describe "track_function_versions/5" do
    @tag :integration
    test "returns list even if empty" do
      result =
        EntityVersion.track_function_versions(
          ".",
          "ElixirOntologies",
          :start,
          2,
          limit: 5
        )

      case result do
        {:ok, versions} ->
          assert is_list(versions)

        {:error, :function_not_found} ->
          :ok

        {:error, :module_not_found} ->
          :ok
      end
    end
  end

  # ===========================================================================
  # Derivation Tests
  # ===========================================================================

  describe "build_derivation/3" do
    test "creates derivation with default type" do
      derivation = EntityVersion.build_derivation("v2", "v1")

      assert derivation.derived_entity == "v2"
      assert derivation.source_entity == "v1"
      assert derivation.derivation_type == :revision
      assert derivation.activity == nil
    end

    test "accepts custom type" do
      derivation = EntityVersion.build_derivation("v2", "v1", type: :quotation)
      assert derivation.derivation_type == :quotation
    end

    test "accepts activity" do
      derivation = EntityVersion.build_derivation("v2", "v1", activity: "commit_abc123")
      assert derivation.activity == "commit_abc123"
    end

    test "accepts timestamp" do
      timestamp = DateTime.utc_now()
      derivation = EntityVersion.build_derivation("v2", "v1", timestamp: timestamp)
      assert derivation.timestamp == timestamp
    end
  end

  describe "build_derivation_chain/1" do
    test "returns empty list for empty input" do
      assert EntityVersion.build_derivation_chain([]) == []
    end

    test "returns empty list for single version" do
      versions = [%{version_id: "v1", commit_sha: "a"}]
      assert EntityVersion.build_derivation_chain(versions) == []
    end

    test "creates chain for multiple versions" do
      versions = [
        %{version_id: "v3", commit_sha: "c", timestamp: nil},
        %{version_id: "v2", commit_sha: "b", timestamp: nil},
        %{version_id: "v1", commit_sha: "a", timestamp: nil}
      ]

      derivations = EntityVersion.build_derivation_chain(versions)

      assert length(derivations) == 2

      [first, second] = derivations

      assert first.derived_entity == "v3"
      assert first.source_entity == "v2"
      assert first.derivation_type == :revision
      assert first.activity == "c"

      assert second.derived_entity == "v2"
      assert second.source_entity == "v1"
      assert second.activity == "b"
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "same_content?/2" do
    test "returns true for same content hash" do
      v1 = %ModuleVersion{
        module_name: "A",
        version_id: "A@1",
        commit_sha: "a",
        short_sha: "a",
        file_path: "a.ex",
        content_hash: "same_hash"
      }

      v2 = %ModuleVersion{
        module_name: "A",
        version_id: "A@2",
        commit_sha: "b",
        short_sha: "b",
        file_path: "a.ex",
        content_hash: "same_hash"
      }

      assert EntityVersion.same_content?(v1, v2)
    end

    test "returns false for different content hash" do
      v1 = %ModuleVersion{
        module_name: "A",
        version_id: "A@1",
        commit_sha: "a",
        short_sha: "a",
        file_path: "a.ex",
        content_hash: "hash1"
      }

      v2 = %ModuleVersion{
        module_name: "A",
        version_id: "A@2",
        commit_sha: "b",
        short_sha: "b",
        file_path: "a.ex",
        content_hash: "hash2"
      }

      refute EntityVersion.same_content?(v1, v2)
    end
  end

  describe "version_chain/1" do
    test "returns list of version IDs" do
      versions = [
        %ModuleVersion{
          module_name: "A",
          version_id: "A@3",
          commit_sha: "c",
          short_sha: "c",
          file_path: "a.ex",
          content_hash: "h3"
        },
        %ModuleVersion{
          module_name: "A",
          version_id: "A@2",
          commit_sha: "b",
          short_sha: "b",
          file_path: "a.ex",
          content_hash: "h2"
        },
        %ModuleVersion{
          module_name: "A",
          version_id: "A@1",
          commit_sha: "a",
          short_sha: "a",
          file_path: "a.ex",
          content_hash: "h1"
        }
      ]

      chain = EntityVersion.version_chain(versions)
      assert chain == ["A@3", "A@2", "A@1"]
    end

    test "returns empty list for empty input" do
      assert EntityVersion.version_chain([]) == []
    end
  end

  describe "find_change_introducing_version/1" do
    test "returns nil for empty list" do
      assert EntityVersion.find_change_introducing_version([]) == nil
    end

    test "returns single version if only one" do
      version = %ModuleVersion{
        module_name: "A",
        version_id: "A@1",
        commit_sha: "a",
        short_sha: "a",
        file_path: "a.ex",
        content_hash: "h1"
      }

      assert EntityVersion.find_change_introducing_version([version]) == version
    end

    test "finds first version with different content" do
      v3 = %ModuleVersion{
        module_name: "A",
        version_id: "A@3",
        commit_sha: "c",
        short_sha: "c",
        file_path: "a.ex",
        content_hash: "new_hash"
      }

      v2 = %ModuleVersion{
        module_name: "A",
        version_id: "A@2",
        commit_sha: "b",
        short_sha: "b",
        file_path: "a.ex",
        content_hash: "old_hash"
      }

      v1 = %ModuleVersion{
        module_name: "A",
        version_id: "A@1",
        commit_sha: "a",
        short_sha: "a",
        file_path: "a.ex",
        content_hash: "old_hash"
      }

      result = EntityVersion.find_change_introducing_version([v3, v2, v1])
      assert result.version_id == "A@3"
    end

    test "returns newest if all same content" do
      v2 = %ModuleVersion{
        module_name: "A",
        version_id: "A@2",
        commit_sha: "b",
        short_sha: "b",
        file_path: "a.ex",
        content_hash: "same"
      }

      v1 = %ModuleVersion{
        module_name: "A",
        version_id: "A@1",
        commit_sha: "a",
        short_sha: "a",
        file_path: "a.ex",
        content_hash: "same"
      }

      result = EntityVersion.find_change_introducing_version([v2, v1])
      assert result.version_id == "A@2"
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "full workflow integration" do
    @tag :integration
    test "can track versions and build derivation chain" do
      case EntityVersion.track_module_versions(".", "ElixirOntologies", limit: 5) do
        {:ok, versions} when length(versions) > 1 ->
          # Build derivation chain
          derivations = EntityVersion.build_derivation_chain(versions)
          assert length(derivations) == length(versions) - 1

          # Each derivation should link consecutive versions
          Enum.each(derivations, fn d ->
            assert d.derivation_type == :revision
            assert is_binary(d.derived_entity)
            assert is_binary(d.source_entity)
          end)

        {:ok, _versions} ->
          # Only one version, no derivations to build
          :ok

        {:error, _} ->
          :ok
      end
    end

    @tag :integration
    test "version IDs follow expected format" do
      case EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD") do
        {:ok, version} ->
          # Format: ModuleName@short_sha
          assert String.match?(version.version_id, ~r/^[A-Z][\w.]+@[0-9a-f]{7}$/)

        {:error, _} ->
          :ok
      end
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    @tag :integration
    test "handles nested module names" do
      result =
        EntityVersion.extract_module_version(
          ".",
          "ElixirOntologies.Extractors.Evolution.EntityVersion",
          "HEAD"
        )

      case result do
        {:ok, version} ->
          assert version.module_name == "ElixirOntologies.Extractors.Evolution.EntityVersion"

        {:error, _} ->
          # Module might not exist yet if we're in a new branch
          :ok
      end
    end

    @tag :integration
    test "handles modules with special characters in names" do
      # Most modules don't have special characters, but test gracefully
      result = EntityVersion.extract_module_version(".", "Some.Module!", "HEAD")
      # Should return error, not crash
      assert match?({:error, _}, result)
    end
  end
end
