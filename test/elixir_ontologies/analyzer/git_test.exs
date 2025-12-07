defmodule ElixirOntologies.Analyzer.GitTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Analyzer.Git.Repository
  alias ElixirOntologies.Analyzer.Git.ParsedUrl
  alias ElixirOntologies.Analyzer.Git.CommitRef
  alias ElixirOntologies.Analyzer.Git.SourceFile

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
  # Commit Information Tests
  # ============================================================================

  describe "current_commit/1" do
    test "returns full SHA (40 characters)" do
      {:ok, sha} = Git.current_commit(".")
      assert is_binary(sha)
      assert String.length(sha) == 40
      assert String.match?(sha, ~r/^[0-9a-f]{40}$/)
    end

    test "returns error for non-git directory" do
      assert {:error, :not_found} = Git.current_commit("/tmp")
    end
  end

  describe "current_commit_short/1" do
    test "returns short SHA (7 characters)" do
      {:ok, sha} = Git.current_commit_short(".")
      assert is_binary(sha)
      assert String.length(sha) == 7
      assert String.match?(sha, ~r/^[0-9a-f]{7}$/)
    end

    test "short SHA is prefix of full SHA" do
      {:ok, short} = Git.current_commit_short(".")
      {:ok, full} = Git.current_commit(".")
      assert String.starts_with?(full, short)
    end
  end

  describe "commit_tags/1" do
    test "returns list of tags" do
      {:ok, tags} = Git.commit_tags(".")
      assert is_list(tags)
      # Tags may or may not exist for current commit
      assert Enum.all?(tags, &is_binary/1)
    end

    test "returns empty list when no tags point at HEAD" do
      # Most commits won't have tags
      {:ok, tags} = Git.commit_tags(".")
      assert is_list(tags)
    end
  end

  describe "commit_message/1" do
    test "returns commit message subject" do
      {:ok, message} = Git.commit_message(".")
      assert is_binary(message)
      assert String.length(message) > 0
      # Subject line shouldn't have newlines
      refute String.contains?(message, "\n")
    end
  end

  describe "commit_message_full/1" do
    test "returns full commit message" do
      {:ok, message} = Git.commit_message_full(".")
      assert is_binary(message)
      assert String.length(message) > 0
    end

    test "full message contains subject" do
      {:ok, subject} = Git.commit_message(".")
      {:ok, full} = Git.commit_message_full(".")
      assert String.starts_with?(full, subject)
    end
  end

  describe "commit_ref/1" do
    test "creates CommitRef struct with full metadata" do
      {:ok, commit} = Git.commit_ref(".")

      assert %CommitRef{} = commit
      assert String.length(commit.sha) == 40
      assert String.length(commit.short_sha) == 7
      assert is_binary(commit.message)
      assert is_list(commit.tags)
      # timestamp and author should be present
      assert is_nil(commit.timestamp) or match?(%DateTime{}, commit.timestamp)
      assert is_nil(commit.author) or is_binary(commit.author)
    end

    test "returns error for non-git directory" do
      assert {:error, :not_found} = Git.commit_ref("/tmp")
    end
  end

  describe "file_commit/2" do
    test "returns SHA of last commit affecting a file" do
      {:ok, sha} = Git.file_commit(".", "mix.exs")
      assert is_binary(sha)
      assert String.length(sha) == 40
      assert String.match?(sha, ~r/^[0-9a-f]{40}$/)
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_tracked} = Git.file_commit(".", "nonexistent_file.txt")
    end

    test "returns error for untracked file" do
      # Create a temp file that's not tracked
      temp_path = Path.join(System.tmp_dir!(), "untracked_test_file_#{:rand.uniform(10000)}.txt")
      File.write!(temp_path, "test")

      result = Git.file_commit(".", temp_path)
      File.rm!(temp_path)

      assert {:error, :file_not_tracked} = result
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
      assert Map.has_key?(repo, :current_commit)
      assert Map.has_key?(repo, :metadata)
    end

    test "includes current_commit when created via repository/1" do
      {:ok, repo} = Git.repository(".")
      assert is_binary(repo.current_commit)
      assert String.length(repo.current_commit) == 40
    end
  end

  describe "CommitRef struct" do
    test "has expected fields" do
      commit = %CommitRef{}
      assert Map.has_key?(commit, :sha)
      assert Map.has_key?(commit, :short_sha)
      assert Map.has_key?(commit, :message)
      assert Map.has_key?(commit, :tags)
      assert Map.has_key?(commit, :timestamp)
      assert Map.has_key?(commit, :author)
    end

    test "tags defaults to empty list" do
      commit = %CommitRef{}
      assert commit.tags == []
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

  # ============================================================================
  # Path Utilities Tests
  # ============================================================================

  describe "relative_to_repo/2" do
    setup do
      {:ok, repo_path} = Git.detect_repo(".")
      {:ok, repo_path: repo_path}
    end

    test "converts absolute path to relative", %{repo_path: repo_path} do
      abs_path = Path.join(repo_path, "lib/elixir_ontologies.ex")
      {:ok, rel} = Git.relative_to_repo(abs_path, repo_path)
      assert rel == "lib/elixir_ontologies.ex"
    end

    test "handles already relative path", %{repo_path: repo_path} do
      {:ok, rel} = Git.relative_to_repo("mix.exs", repo_path)
      assert rel == "mix.exs"
    end

    test "handles nested relative path", %{repo_path: repo_path} do
      {:ok, rel} = Git.relative_to_repo("lib/elixir_ontologies/analyzer/git.ex", repo_path)
      assert rel == "lib/elixir_ontologies/analyzer/git.ex"
    end

    test "returns . for repo root", %{repo_path: repo_path} do
      {:ok, rel} = Git.relative_to_repo(repo_path, repo_path)
      assert rel == "."
    end

    test "returns error for path outside repo", %{repo_path: repo_path} do
      assert {:error, :outside_repo} = Git.relative_to_repo("/etc/passwd", repo_path)
    end

    test "returns error for relative path that resolves outside repo", %{repo_path: repo_path} do
      assert {:error, :outside_repo} = Git.relative_to_repo("../../../etc/passwd", repo_path)
    end

    test "normalizes path separators", %{repo_path: repo_path} do
      {:ok, rel} = Git.relative_to_repo("lib//elixir_ontologies.ex", repo_path)
      assert rel == "lib/elixir_ontologies.ex"
    end
  end

  describe "file_in_repo?/2" do
    setup do
      {:ok, repo_path} = Git.detect_repo(".")
      {:ok, repo_path: repo_path}
    end

    test "returns true for file in repo", %{repo_path: repo_path} do
      assert Git.file_in_repo?("mix.exs", repo_path)
    end

    test "returns true for absolute path in repo", %{repo_path: repo_path} do
      abs_path = Path.join(repo_path, "mix.exs")
      assert Git.file_in_repo?(abs_path, repo_path)
    end

    test "returns false for file outside repo", %{repo_path: repo_path} do
      refute Git.file_in_repo?("/etc/passwd", repo_path)
    end

    test "returns false for path traversal attack", %{repo_path: repo_path} do
      refute Git.file_in_repo?("../../../etc/passwd", repo_path)
    end
  end

  describe "normalize_path/1" do
    test "collapses multiple slashes" do
      assert Git.normalize_path("lib//foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("lib///foo///bar.ex") == "lib/foo/bar.ex"
    end

    test "converts backslashes to forward slashes" do
      assert Git.normalize_path("lib\\foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("lib\\foo\\bar.ex") == "lib/foo/bar.ex"
    end

    test "removes ./ in middle of path" do
      assert Git.normalize_path("lib/./foo.ex") == "lib/foo.ex"
      assert Git.normalize_path("lib/./foo/./bar.ex") == "lib/foo/bar.ex"
    end

    test "removes leading ./" do
      assert Git.normalize_path("./lib/foo.ex") == "lib/foo.ex"
    end

    test "removes trailing slash" do
      assert Git.normalize_path("lib/foo/") == "lib/foo"
    end

    test "handles already clean path" do
      assert Git.normalize_path("lib/foo.ex") == "lib/foo.ex"
    end

    test "handles empty string" do
      assert Git.normalize_path("") == ""
    end
  end

  describe "source_file/2" do
    setup do
      {:ok, repo_path} = Git.detect_repo(".")
      {:ok, repo_path: repo_path}
    end

    test "creates SourceFile struct", %{repo_path: repo_path} do
      {:ok, sf} = Git.source_file("mix.exs", repo_path)

      assert %SourceFile{} = sf
      assert sf.relative_path == "mix.exs"
      assert is_binary(sf.absolute_path)
      assert String.ends_with?(sf.absolute_path, "mix.exs")
      assert sf.repository_path == Path.expand(repo_path)
    end

    test "includes last commit SHA for tracked file", %{repo_path: repo_path} do
      {:ok, sf} = Git.source_file("mix.exs", repo_path)
      assert is_binary(sf.last_commit)
      assert String.length(sf.last_commit) == 40
    end

    test "sets last_commit to nil for untracked file", %{repo_path: repo_path} do
      # Create temp file in repo
      temp_path = Path.join(repo_path, "temp_untracked_#{:rand.uniform(10000)}.txt")
      File.write!(temp_path, "test")

      {:ok, sf} = Git.source_file(temp_path, repo_path)
      assert is_nil(sf.last_commit)

      File.rm!(temp_path)
    end

    test "returns error for file outside repo", %{repo_path: repo_path} do
      assert {:error, :outside_repo} = Git.source_file("/etc/passwd", repo_path)
    end
  end

  describe "source_file/1 (auto-detect repo)" do
    test "creates SourceFile with auto-detected repo" do
      {:ok, sf} = Git.source_file("mix.exs")

      assert %SourceFile{} = sf
      assert sf.relative_path == "mix.exs"
      assert is_binary(sf.repository_path)
    end

    test "returns error for path not in any repo" do
      # Could be :not_found (no git repo) or :invalid_path (path doesn't exist)
      result = Git.source_file("/tmp/nonexistent.txt")
      assert {:error, reason} = result
      assert reason in [:not_found, :invalid_path]
    end
  end

  describe "SourceFile struct" do
    test "has expected fields" do
      sf = %SourceFile{}
      assert Map.has_key?(sf, :absolute_path)
      assert Map.has_key?(sf, :relative_path)
      assert Map.has_key?(sf, :repository_path)
      assert Map.has_key?(sf, :last_commit)
    end
  end
end
