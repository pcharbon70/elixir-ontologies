defmodule ElixirOntologies.Analyzer.GitTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Analyzer.Git.Repository
  alias ElixirOntologies.Analyzer.Git.ParsedUrl

  doctest ElixirOntologies.Analyzer.Git

  # ============================================================================
  # Repository Detection Tests
  # ============================================================================

  describe "detect_repo/1" do
    test "detects git repository from current directory" do
      {:ok, repo_path} = Git.detect_repo(".")
      assert File.dir?(Path.join(repo_path, ".git"))
    end

    test "detects git repository from subdirectory" do
      {:ok, repo_path} = Git.detect_repo("lib")
      assert File.dir?(Path.join(repo_path, ".git"))
    end

    test "returns error for non-git directory" do
      assert {:error, :not_found} = Git.detect_repo("/tmp")
    end

    test "returns error for non-existent path" do
      assert {:error, :invalid_path} = Git.detect_repo("/nonexistent/path")
    end
  end

  describe "detect_repo!/1" do
    test "returns path for valid repository" do
      path = Git.detect_repo!(".")
      assert is_binary(path)
      assert File.dir?(Path.join(path, ".git"))
    end

    test "raises for non-git directory" do
      assert_raise RuntimeError, ~r/Failed to detect git repository/, fn ->
        Git.detect_repo!("/tmp")
      end
    end
  end

  describe "git_repo?/1" do
    test "returns true for git repository" do
      assert Git.git_repo?(".")
    end

    test "returns false for non-git directory" do
      refute Git.git_repo?("/tmp")
    end
  end

  # ============================================================================
  # Remote URL Tests
  # ============================================================================

  describe "remote_url/1" do
    test "extracts origin URL from current repository" do
      {:ok, url} = Git.remote_url(".")
      assert is_binary(url)
      # The URL should contain common git hosting patterns
      assert String.contains?(url, "github") or
               String.contains?(url, "gitlab") or
               String.contains?(url, "bitbucket") or
               String.contains?(url, "git")
    end
  end

  describe "parse_remote_url/1" do
    test "parses HTTPS GitHub URL" do
      {:ok, parsed} = Git.parse_remote_url("https://github.com/owner/repo.git")
      assert %ParsedUrl{} = parsed
      assert parsed.host == "github.com"
      assert parsed.owner == "owner"
      assert parsed.repo == "repo"
      assert parsed.protocol == :https
    end

    test "parses HTTPS URL without .git suffix" do
      {:ok, parsed} = Git.parse_remote_url("https://github.com/owner/repo")
      assert parsed.host == "github.com"
      assert parsed.owner == "owner"
      assert parsed.repo == "repo"
    end

    test "parses SSH URL (git@)" do
      {:ok, parsed} = Git.parse_remote_url("git@github.com:owner/repo.git")
      assert parsed.host == "github.com"
      assert parsed.owner == "owner"
      assert parsed.repo == "repo"
      assert parsed.protocol == :ssh
    end

    test "parses SSH URL (ssh://)" do
      {:ok, parsed} = Git.parse_remote_url("ssh://git@gitlab.com/owner/repo.git")
      assert parsed.host == "gitlab.com"
      assert parsed.owner == "owner"
      assert parsed.repo == "repo"
      assert parsed.protocol == :ssh
    end

    test "parses git:// protocol URL" do
      {:ok, parsed} = Git.parse_remote_url("git://github.com/owner/repo.git")
      assert parsed.host == "github.com"
      assert parsed.owner == "owner"
      assert parsed.repo == "repo"
      assert parsed.protocol == :git
    end

    test "parses GitLab URL" do
      {:ok, parsed} = Git.parse_remote_url("https://gitlab.com/group/project.git")
      assert parsed.host == "gitlab.com"
      assert parsed.owner == "group"
      assert parsed.repo == "project"
    end

    test "parses Bitbucket URL" do
      {:ok, parsed} = Git.parse_remote_url("https://bitbucket.org/team/repo.git")
      assert parsed.host == "bitbucket.org"
      assert parsed.owner == "team"
      assert parsed.repo == "repo"
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_url} = Git.parse_remote_url("not a url")
    end
  end

  # ============================================================================
  # Branch Tests
  # ============================================================================

  describe "current_branch/1" do
    test "gets current branch name" do
      {:ok, branch} = Git.current_branch(".")
      assert is_binary(branch)
      assert String.length(branch) > 0
    end
  end

  describe "default_branch/1" do
    test "gets default branch name" do
      {:ok, branch} = Git.default_branch(".")
      assert is_binary(branch)
      # Should be one of common default branch names
      assert branch in ["main", "master", "develop"] or String.length(branch) > 0
    end
  end

  # ============================================================================
  # Full Repository Info Tests
  # ============================================================================

  describe "repository/1" do
    test "creates Repository struct with full metadata" do
      {:ok, repo} = Git.repository(".")

      assert %Repository{} = repo
      assert is_binary(repo.path)
      assert is_binary(repo.name)
      assert File.dir?(Path.join(repo.path, ".git"))
    end

    test "includes remote information when available" do
      {:ok, repo} = Git.repository(".")

      # This repo should have a remote
      assert is_binary(repo.remote_url)
      assert is_binary(repo.host)
      assert is_binary(repo.owner)
    end

    test "includes branch information" do
      {:ok, repo} = Git.repository(".")

      assert is_binary(repo.current_branch)
      # default_branch might be nil if not set
    end

    test "includes metadata" do
      {:ok, repo} = Git.repository(".")

      assert is_map(repo.metadata)
      assert repo.metadata.has_remote == true
      assert repo.metadata.protocol in [:https, :ssh, :git]
    end
  end

  describe "repository!/1" do
    test "returns Repository for valid path" do
      repo = Git.repository!(".")
      assert %Repository{} = repo
    end

    test "raises for non-git directory" do
      assert_raise RuntimeError, ~r/Failed to get repository info/, fn ->
        Git.repository!("/tmp")
      end
    end
  end

  # ============================================================================
  # Struct Tests
  # ============================================================================

  describe "Repository struct" do
    test "has expected fields" do
      repo = %Repository{}
      assert Map.has_key?(repo, :path)
      assert Map.has_key?(repo, :name)
      assert Map.has_key?(repo, :remote_url)
      assert Map.has_key?(repo, :host)
      assert Map.has_key?(repo, :owner)
      assert Map.has_key?(repo, :current_branch)
      assert Map.has_key?(repo, :default_branch)
      assert Map.has_key?(repo, :metadata)
    end
  end

  describe "ParsedUrl struct" do
    test "has expected fields" do
      parsed = %ParsedUrl{}
      assert Map.has_key?(parsed, :host)
      assert Map.has_key?(parsed, :owner)
      assert Map.has_key?(parsed, :repo)
      assert Map.has_key?(parsed, :protocol)
    end
  end
end
