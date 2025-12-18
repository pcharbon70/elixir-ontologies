defmodule ElixirOntologies.Analyzer.Phase7IntegrationTest do
  @moduledoc """
  Integration tests for Phase 7: Evolution & Git Integration.

  Tests the complete workflow of:
  - Git repository detection and metadata extraction
  - Source URL generation for code elements
  - File-to-repository linking via SourceFile structs
  - Graceful degradation when git is not available
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Analyzer.Git.{Repository, CommitRef, SourceFile}
  alias ElixirOntologies.Analyzer.SourceUrl

  # ============================================================================
  # Full Git Info Extraction Tests
  # ============================================================================

  describe "full git info extraction in actual repo" do
    test "repository struct has all expected fields populated" do
      {:ok, repo} = Git.repository(".")

      # Core fields populated
      assert is_binary(repo.path)
      assert is_binary(repo.name)
      assert File.dir?(repo.path)

      # Remote information (this repo has a remote)
      assert is_binary(repo.remote_url)
      assert is_binary(repo.host)
      assert is_binary(repo.owner)

      # Branch information
      assert is_binary(repo.current_branch)

      # Commit information
      assert is_binary(repo.current_commit)
      assert String.length(repo.current_commit) == 40

      # Metadata
      assert is_map(repo.metadata)
      assert repo.metadata.has_remote == true
    end

    test "repository detection works from subdirectories" do
      {:ok, repo_from_root} = Git.repository(".")
      {:ok, repo_from_lib} = Git.repository("lib")
      {:ok, repo_from_test} = Git.repository("test")

      # All should find the same repo
      assert repo_from_root.path == repo_from_lib.path
      assert repo_from_root.path == repo_from_test.path
    end

    test "commit_ref provides detailed commit info" do
      {:ok, commit} = Git.commit_ref(".")

      assert %CommitRef{} = commit
      assert String.length(commit.sha) == 40
      assert String.length(commit.short_sha) == 7
      assert String.starts_with?(commit.sha, commit.short_sha)
      assert is_binary(commit.message)
      assert is_list(commit.tags)

      # Timestamp and author should be present
      assert is_nil(commit.timestamp) or match?(%DateTime{}, commit.timestamp)
      assert is_binary(commit.author)
    end

    test "remote URL is parsed correctly for known platforms" do
      {:ok, repo} = Git.repository(".")

      # Should be a known platform
      platform = SourceUrl.detect_platform(repo.host)
      assert platform in [:github, :gitlab, :bitbucket, :unknown]

      # If it's a known platform, we should be able to generate URLs
      if platform != :unknown do
        url = SourceUrl.for_file(repo, "mix.exs")
        assert is_binary(url)
        assert String.contains?(url, repo.owner)
        assert String.contains?(url, repo.name)
      end
    end

    test "branch detection returns current branch name" do
      {:ok, branch} = Git.current_branch(".")

      assert is_binary(branch)
      assert String.length(branch) > 0
      # Should not contain newlines
      refute String.contains?(branch, "\n")
    end

    test "default branch detection works" do
      {:ok, default} = Git.default_branch(".")

      assert is_binary(default)
      # Common default branch names
      assert default in ["main", "master", "develop"] or String.length(default) > 0
    end
  end

  # ============================================================================
  # Source URL Generation Tests
  # ============================================================================

  describe "source URLs generated for actual files" do
    setup do
      {:ok, repo} = Git.repository(".")
      platform = SourceUrl.platform_from_repo(repo)
      {:ok, repo: repo, platform: platform}
    end

    test "generates URL for file using Repository struct", %{repo: repo, platform: platform} do
      if platform != :unknown do
        url = SourceUrl.for_file(repo, "mix.exs")

        assert is_binary(url)
        assert String.starts_with?(url, "https://")
        assert String.contains?(url, "mix.exs")
        assert String.contains?(url, repo.current_commit)
      end
    end

    test "generates URL with line number", %{repo: repo, platform: platform} do
      if platform != :unknown do
        url = SourceUrl.for_line(repo, "mix.exs", 10)

        assert is_binary(url)
        assert String.contains?(url, "mix.exs")
        # Line anchor format varies by platform
        assert String.contains?(url, "#L10") or String.contains?(url, "#lines-10")
      end
    end

    test "generates URL with line range", %{repo: repo, platform: platform} do
      if platform != :unknown do
        url = SourceUrl.for_range(repo, "lib/elixir_ontologies.ex", 1, 20)

        assert is_binary(url)
        assert String.contains?(url, "lib")
        # Range format varies by platform
        assert String.contains?(url, "#L1") or String.contains?(url, "#lines-1")
      end
    end

    test "URL contains correct commit SHA", %{repo: repo, platform: platform} do
      if platform != :unknown do
        url = SourceUrl.for_file(repo, "mix.exs")

        # URL should contain the full commit SHA
        assert String.contains?(url, repo.current_commit)
      end
    end

    test "convenience function url_for_path works" do
      # This auto-detects the repository
      case SourceUrl.url_for_path("mix.exs") do
        {:ok, url} ->
          assert is_binary(url)
          assert String.contains?(url, "mix.exs")

        {:error, :url_generation_failed} ->
          # Unknown platform - that's ok
          :ok
      end
    end

    test "url_for_path with line option" do
      case SourceUrl.url_for_path("mix.exs", line: 5) do
        {:ok, url} ->
          assert is_binary(url)
          assert String.contains?(url, "#L5") or String.contains?(url, "#lines-5")

        {:error, :url_generation_failed} ->
          :ok
      end
    end

    test "url_for_path with line range options" do
      case SourceUrl.url_for_path("mix.exs", line: 1, end_line: 10) do
        {:ok, url} ->
          assert is_binary(url)
          # Should have range format
          assert String.contains?(url, "#")

        {:error, :url_generation_failed} ->
          :ok
      end
    end
  end

  # ============================================================================
  # Repository Linking Tests
  # ============================================================================

  describe "repository linking for source files" do
    setup do
      {:ok, repo_path} = Git.detect_repo(".")
      {:ok, repo_path: repo_path}
    end

    test "SourceFile links file to repository", %{repo_path: repo_path} do
      {:ok, sf} = Git.source_file("mix.exs", repo_path)

      assert %SourceFile{} = sf
      assert sf.relative_path == "mix.exs"
      assert String.ends_with?(sf.absolute_path, "mix.exs")
      assert sf.repository_path == Path.expand(repo_path)
    end

    test "SourceFile includes last commit for tracked file", %{repo_path: repo_path} do
      {:ok, sf} = Git.source_file("mix.exs", repo_path)

      assert is_binary(sf.last_commit)
      assert String.length(sf.last_commit) == 40
      assert String.match?(sf.last_commit, ~r/^[0-9a-f]{40}$/)
    end

    test "SourceFile handles nested paths", %{repo_path: repo_path} do
      {:ok, sf} = Git.source_file("lib/elixir_ontologies/analyzer/git.ex", repo_path)

      assert sf.relative_path == "lib/elixir_ontologies/analyzer/git.ex"
      assert String.contains?(sf.absolute_path, "lib/elixir_ontologies/analyzer/git.ex")
    end

    test "auto-detect repository from file path" do
      {:ok, sf} = Git.source_file("mix.exs")

      assert %SourceFile{} = sf
      assert is_binary(sf.repository_path)
      assert File.dir?(sf.repository_path)
    end

    test "relative path calculated correctly from absolute", %{repo_path: repo_path} do
      abs_path = Path.join(repo_path, "lib/elixir_ontologies.ex")
      {:ok, rel} = Git.relative_to_repo(abs_path, repo_path)

      assert rel == "lib/elixir_ontologies.ex"
    end

    test "file_in_repo? returns true for files in repo", %{repo_path: repo_path} do
      assert Git.file_in_repo?("mix.exs", repo_path)
      assert Git.file_in_repo?("lib/elixir_ontologies.ex", repo_path)
      assert Git.file_in_repo?("test/test_helper.exs", repo_path)
    end

    test "file_in_repo? returns false for external files", %{repo_path: repo_path} do
      refute Git.file_in_repo?("/etc/passwd", repo_path)
      refute Git.file_in_repo?("/tmp/some_file.txt", repo_path)
    end
  end

  # ============================================================================
  # Full Pipeline Integration Tests
  # ============================================================================

  describe "full pipeline: repository → file → URL" do
    test "complete workflow for generating source URL" do
      # Step 1: Detect repository
      {:ok, repo} = Git.repository(".")
      assert %Repository{} = repo

      # Step 2: Create SourceFile
      {:ok, sf} = Git.source_file("lib/elixir_ontologies/analyzer/git.ex", repo.path)
      assert %SourceFile{} = sf

      # Step 3: Generate URL (if platform is known)
      platform = SourceUrl.platform_from_repo(repo)

      if platform != :unknown do
        # Generate file URL
        file_url = SourceUrl.for_file(repo, sf.relative_path)
        assert is_binary(file_url)

        # Generate line URL
        line_url = SourceUrl.for_line(repo, sf.relative_path, 1)
        assert is_binary(line_url)

        # Generate range URL
        range_url = SourceUrl.for_range(repo, sf.relative_path, 1, 50)
        assert is_binary(range_url)

        # All URLs should contain the same base components
        assert String.contains?(file_url, repo.owner)
        assert String.contains?(file_url, repo.name)
        assert String.contains?(file_url, repo.current_commit)
      end
    end

    test "multiple files can be linked to same repository" do
      {:ok, repo} = Git.repository(".")

      files = [
        "mix.exs",
        "lib/elixir_ontologies.ex",
        "lib/elixir_ontologies/analyzer/git.ex",
        "test/test_helper.exs"
      ]

      source_files =
        Enum.map(files, fn path ->
          {:ok, sf} = Git.source_file(path, repo.path)
          sf
        end)

      # All should point to same repository
      repo_paths = Enum.map(source_files, & &1.repository_path) |> Enum.uniq()
      assert length(repo_paths) == 1

      # Each should have correct relative path
      Enum.zip(files, source_files)
      |> Enum.each(fn {expected_rel, sf} ->
        assert sf.relative_path == expected_rel
      end)
    end
  end

  # ============================================================================
  # Graceful Degradation Tests
  # ============================================================================

  describe "graceful degradation without git" do
    test "detect_repo returns error for non-git directory" do
      assert {:error, :not_found} = Git.detect_repo("/tmp")
    end

    test "repository returns error for non-git directory" do
      assert {:error, :not_found} = Git.repository("/tmp")
    end

    test "git_repo? returns false for non-git directory" do
      refute Git.git_repo?("/tmp")
    end

    test "current_commit returns error for non-git directory" do
      assert {:error, :not_found} = Git.current_commit("/tmp")
    end

    test "commit_ref returns error for non-git directory" do
      assert {:error, :not_found} = Git.commit_ref("/tmp")
    end

    test "source_file returns error for file not in any repo" do
      result = Git.source_file("/tmp/nonexistent.txt")
      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end

    test "relative_to_repo returns error for path outside repo" do
      {:ok, repo_path} = Git.detect_repo(".")
      assert {:error, :outside_repo} = Git.relative_to_repo("/etc/passwd", repo_path)
    end

    test "SourceUrl returns nil for unknown platform" do
      assert nil == SourceUrl.for_file(:unknown, "owner", "repo", "sha", "file.ex")
      assert nil == SourceUrl.for_line(:unknown, "owner", "repo", "sha", "file.ex", 1)
      assert nil == SourceUrl.for_range(:unknown, "owner", "repo", "sha", "file.ex", 1, 10)
    end

    test "SourceUrl returns nil for Repository with unknown host" do
      repo = %Repository{
        host: "git.example.com",
        owner: "owner",
        name: "repo",
        current_commit: "abc123"
      }

      assert nil == SourceUrl.for_file(repo, "file.ex")
    end

    test "SourceUrl returns nil for Repository missing fields" do
      # Missing host
      repo1 = %Repository{host: nil, owner: "owner", name: "repo", current_commit: "sha"}
      assert nil == SourceUrl.for_file(repo1, "file.ex")

      # Missing owner
      repo2 = %Repository{host: "github.com", owner: nil, name: "repo", current_commit: "sha"}
      assert nil == SourceUrl.for_file(repo2, "file.ex")

      # Missing name
      repo3 = %Repository{host: "github.com", owner: "owner", name: nil, current_commit: "sha"}
      assert nil == SourceUrl.for_file(repo3, "file.ex")

      # Missing commit
      repo4 = %Repository{host: "github.com", owner: "owner", name: "repo", current_commit: nil}
      assert nil == SourceUrl.for_file(repo4, "file.ex")
    end

    test "file_commit returns error for untracked file" do
      assert {:error, :file_not_tracked} = Git.file_commit(".", "nonexistent_file.txt")
    end

    test "detect_repo returns error for invalid path" do
      assert {:error, :invalid_path} = Git.detect_repo("/nonexistent/path")
    end
  end

  # ============================================================================
  # Edge Cases and Special Scenarios
  # ============================================================================

  describe "edge cases" do
    test "handles files with special characters in name" do
      {:ok, repo} = Git.repository(".")
      platform = SourceUrl.platform_from_repo(repo)

      if platform != :unknown do
        # URL should properly encode special characters
        url = SourceUrl.for_file(repo, "lib/file with spaces.ex")
        assert is_binary(url)
        # Space should be encoded
        assert String.contains?(url, "+") or String.contains?(url, "%20")
      end
    end

    test "handles deeply nested file paths" do
      {:ok, repo_path} = Git.detect_repo(".")
      path = "lib/elixir_ontologies/extractors/otp/supervisor.ex"

      {:ok, rel} = Git.relative_to_repo(path, repo_path)
      assert rel == path
    end

    test "path normalization handles various formats" do
      assert Git.normalize_path("lib//foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("./lib/foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("lib/./foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("lib\\foo.ex") == "lib/foo.ex"
    end

    test "same commit SHA returned consistently" do
      {:ok, commit1} = Git.current_commit(".")
      {:ok, commit2} = Git.current_commit(".")
      {:ok, repo} = Git.repository(".")

      assert commit1 == commit2
      assert commit1 == repo.current_commit
    end
  end
end
