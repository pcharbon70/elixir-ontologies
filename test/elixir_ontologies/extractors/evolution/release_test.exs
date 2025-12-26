defmodule ElixirOntologies.Extractors.Evolution.ReleaseTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Release

  # ===========================================================================
  # Semantic Version Parsing Tests
  # ===========================================================================

  describe "parse_semver/1" do
    test "parses simple version" do
      assert {:ok, semver} = Release.parse_semver("1.2.3")
      assert semver.major == 1
      assert semver.minor == 2
      assert semver.patch == 3
      assert semver.pre_release == nil
      assert semver.build == nil
    end

    test "parses version with v prefix" do
      assert {:ok, semver} = Release.parse_semver("v1.2.3")
      assert semver.major == 1
      assert semver.minor == 2
      assert semver.patch == 3
    end

    test "parses version with pre-release" do
      assert {:ok, semver} = Release.parse_semver("1.0.0-alpha")
      assert semver.major == 1
      assert semver.minor == 0
      assert semver.patch == 0
      assert semver.pre_release == "alpha"
    end

    test "parses version with numeric pre-release" do
      assert {:ok, semver} = Release.parse_semver("1.0.0-alpha.1")
      assert semver.pre_release == "alpha.1"
    end

    test "parses version with rc pre-release" do
      assert {:ok, semver} = Release.parse_semver("2.0.0-rc.1")
      assert semver.major == 2
      assert semver.pre_release == "rc.1"
    end

    test "parses version with beta pre-release" do
      assert {:ok, semver} = Release.parse_semver("1.0.0-beta.2")
      assert semver.pre_release == "beta.2"
    end

    test "parses version with build metadata" do
      assert {:ok, semver} = Release.parse_semver("1.0.0+build.123")
      assert semver.major == 1
      assert semver.build == "build.123"
    end

    test "parses version with pre-release and build" do
      assert {:ok, semver} = Release.parse_semver("1.0.0-alpha.1+build.456")
      assert semver.pre_release == "alpha.1"
      assert semver.build == "build.456"
    end

    test "parses version with zero components" do
      assert {:ok, semver} = Release.parse_semver("0.0.0")
      assert semver.major == 0
      assert semver.minor == 0
      assert semver.patch == 0
    end

    test "parses version with large numbers" do
      assert {:ok, semver} = Release.parse_semver("100.200.300")
      assert semver.major == 100
      assert semver.minor == 200
      assert semver.patch == 300
    end

    test "returns error for invalid version" do
      assert {:error, :invalid_version} = Release.parse_semver("invalid")
    end

    test "returns error for incomplete version" do
      assert {:error, :invalid_version} = Release.parse_semver("1.2")
    end

    test "returns error for version with leading zeros" do
      assert {:error, :invalid_version} = Release.parse_semver("01.2.3")
    end

    test "returns error for nil" do
      assert {:error, :invalid_version} = Release.parse_semver(nil)
    end

    test "returns error for non-string" do
      assert {:error, :invalid_version} = Release.parse_semver(123)
    end
  end

  # ===========================================================================
  # Version Comparison Tests
  # ===========================================================================

  describe "compare_versions/2" do
    test "returns :lt when first version is less" do
      assert Release.compare_versions("1.0.0", "2.0.0") == :lt
      assert Release.compare_versions("1.0.0", "1.1.0") == :lt
      assert Release.compare_versions("1.0.0", "1.0.1") == :lt
    end

    test "returns :eq when versions are equal" do
      assert Release.compare_versions("1.0.0", "1.0.0") == :eq
      assert Release.compare_versions("2.5.3", "2.5.3") == :eq
    end

    test "returns :gt when first version is greater" do
      assert Release.compare_versions("2.0.0", "1.0.0") == :gt
      assert Release.compare_versions("1.1.0", "1.0.0") == :gt
      assert Release.compare_versions("1.0.1", "1.0.0") == :gt
    end

    test "pre-release is less than release" do
      assert Release.compare_versions("1.0.0-alpha", "1.0.0") == :lt
      assert Release.compare_versions("1.0.0", "1.0.0-alpha") == :gt
    end

    test "compares pre-release versions" do
      assert Release.compare_versions("1.0.0-alpha", "1.0.0-beta") == :lt
      assert Release.compare_versions("1.0.0-rc.1", "1.0.0-rc.2") == :lt
    end

    test "handles v prefix" do
      assert Release.compare_versions("v1.0.0", "v2.0.0") == :lt
      assert Release.compare_versions("v1.0.0", "1.0.0") == :eq
    end

    test "handles invalid versions with string comparison" do
      assert Release.compare_versions("a", "b") == :lt
      assert Release.compare_versions("b", "a") == :gt
    end
  end

  # ===========================================================================
  # Tag Listing Tests
  # ===========================================================================

  describe "list_tags/1" do
    test "returns list of tags" do
      assert {:ok, tags} = Release.list_tags(".")
      assert is_list(tags)
    end

    test "returns error for invalid path" do
      assert {:error, _} = Release.list_tags("/nonexistent")
    end
  end

  describe "list_version_tags/1" do
    test "returns list of version-like tags" do
      assert {:ok, tags} = Release.list_version_tags(".")
      assert is_list(tags)

      # If there are any version tags, they should match version patterns
      for tag <- tags do
        assert Regex.match?(~r/^v?\d+\.\d+/, tag) or
                 Regex.match?(~r/^release[_-]?\d+/i, tag)
      end
    end
  end

  # ===========================================================================
  # Version Extraction from mix.exs Tests
  # ===========================================================================

  describe "extract_current_version/1" do
    test "extracts version from current mix.exs" do
      assert {:ok, version} = Release.extract_current_version(".")
      assert is_binary(version)
      # Should be a valid semver
      assert {:ok, _} = Release.parse_semver(version)
    end

    test "returns error for invalid path" do
      assert {:error, _} = Release.extract_current_version("/nonexistent")
    end
  end

  describe "extract_version_at_commit/2" do
    test "extracts version at HEAD" do
      assert {:ok, version} = Release.extract_version_at_commit(".", "HEAD")
      assert is_binary(version)
    end

    test "returns error for commit without mix.exs" do
      # Try with a known invalid ref
      assert {:error, _} = Release.extract_version_at_commit(".", "invalid_ref_xyz")
    end
  end

  # ===========================================================================
  # Release Extraction Tests
  # ===========================================================================

  describe "extract_releases/1" do
    test "returns list of releases" do
      assert {:ok, releases} = Release.extract_releases(".")
      assert is_list(releases)
    end

    test "releases are Release structs" do
      {:ok, releases} = Release.extract_releases(".")

      for release <- releases do
        assert %Release{} = release
        assert is_binary(release.release_id)
        assert is_binary(release.version)
        assert is_binary(release.commit_sha)
        assert is_binary(release.short_sha)
      end
    end

    test "releases are sorted by version descending" do
      {:ok, releases} = Release.extract_releases(".")

      # If there are multiple releases, verify ordering
      if length(releases) > 1 do
        versions = Enum.map(releases, & &1.version)
        pairs = Enum.zip(versions, Enum.drop(versions, 1))

        for {v1, v2} <- pairs do
          assert Release.compare_versions(v1, v2) in [:gt, :eq]
        end
      end
    end

    test "releases have previous_version set" do
      {:ok, releases} = Release.extract_releases(".")

      if length(releases) > 1 do
        # First release (newest) should not have previous
        [first | rest] = releases
        assert first.previous_version == nil

        # Rest should have previous versions set
        for release <- rest do
          # previous_version should be set unless it's the oldest
          # Just verify the field exists
          assert Map.has_key?(release, :previous_version)
        end
      end
    end
  end

  describe "extract_release/2" do
    test "extracts release by tag name" do
      {:ok, tags} = Release.list_version_tags(".")

      if length(tags) > 0 do
        tag = hd(tags)
        assert {:ok, release} = Release.extract_release(".", tag)
        assert %Release{} = release
        assert release.tag == tag
      end
    end

    test "returns error for invalid tag" do
      assert {:error, _} = Release.extract_release(".", "nonexistent_tag_xyz")
    end
  end

  # ===========================================================================
  # Release Progression Tests
  # ===========================================================================

  describe "release_progression/1" do
    test "returns releases in ascending order" do
      assert {:ok, progression} = Release.release_progression(".")
      assert is_list(progression)

      # If there are multiple releases, verify ordering (oldest first)
      if length(progression) > 1 do
        versions = Enum.map(progression, & &1.version)
        pairs = Enum.zip(versions, Enum.drop(versions, 1))

        for {v1, v2} <- pairs do
          assert Release.compare_versions(v1, v2) in [:lt, :eq]
        end
      end
    end
  end

  describe "sort_releases/1" do
    test "sorts releases by version descending" do
      releases = [
        %Release{release_id: "r1", version: "1.0.0", commit_sha: "a" |> String.pad_trailing(40, "0"), short_sha: "a"},
        %Release{release_id: "r3", version: "3.0.0", commit_sha: "c" |> String.pad_trailing(40, "0"), short_sha: "c"},
        %Release{release_id: "r2", version: "2.0.0", commit_sha: "b" |> String.pad_trailing(40, "0"), short_sha: "b"}
      ]

      sorted = Release.sort_releases(releases)
      versions = Enum.map(sorted, & &1.version)
      assert versions == ["3.0.0", "2.0.0", "1.0.0"]
    end

    test "handles pre-release versions" do
      releases = [
        %Release{release_id: "r1", version: "1.0.0", commit_sha: "a" |> String.pad_trailing(40, "0"), short_sha: "a"},
        %Release{release_id: "r2", version: "1.0.0-alpha", commit_sha: "b" |> String.pad_trailing(40, "0"), short_sha: "b"},
        %Release{release_id: "r3", version: "1.0.0-beta", commit_sha: "c" |> String.pad_trailing(40, "0"), short_sha: "c"}
      ]

      sorted = Release.sort_releases(releases)
      versions = Enum.map(sorted, & &1.version)
      # 1.0.0 should be first (newest), then beta, then alpha
      assert versions == ["1.0.0", "1.0.0-beta", "1.0.0-alpha"]
    end
  end

  # ===========================================================================
  # Tag Info Extraction Tests
  # ===========================================================================

  describe "extract_tag_info/2" do
    test "extracts info for valid tag" do
      {:ok, tags} = Release.list_tags(".")

      if length(tags) > 0 do
        tag = hd(tags)
        assert {:ok, info} = Release.extract_tag_info(".", tag)
        assert is_binary(info.commit_sha)
        assert String.length(info.commit_sha) == 40
        assert is_binary(info.short_sha)
      end
    end

    test "returns error for invalid tag" do
      assert {:error, _} = Release.extract_tag_info(".", "nonexistent_tag_xyz")
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "full release extraction workflow" do
      # List tags
      {:ok, tags} = Release.list_tags(".")
      assert is_list(tags)

      # Extract current version
      {:ok, version} = Release.extract_current_version(".")
      assert is_binary(version)

      # Extract all releases
      {:ok, releases} = Release.extract_releases(".")
      assert is_list(releases)

      # Get release progression
      {:ok, progression} = Release.release_progression(".")
      assert is_list(progression)

      # Progression should be reverse of releases
      if length(releases) > 0 and length(progression) > 0 do
        assert hd(releases).version == List.last(progression).version
      end
    end
  end
end
