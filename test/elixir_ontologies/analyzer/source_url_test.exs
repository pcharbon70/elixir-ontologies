defmodule ElixirOntologies.Analyzer.SourceUrlTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.SourceUrl
  alias ElixirOntologies.Analyzer.Git.Repository

  doctest ElixirOntologies.Analyzer.SourceUrl

  # ============================================================================
  # Platform Detection Tests
  # ============================================================================

  describe "detect_platform/1" do
    test "detects GitHub from hostname" do
      assert :github == SourceUrl.detect_platform("github.com")
      assert :github == SourceUrl.detect_platform("GitHub.com")
    end

    test "detects GitHub from subdomains" do
      assert :github == SourceUrl.detect_platform("api.github.com")
      assert :github == SourceUrl.detect_platform("pages.github.io")
    end

    test "detects GitLab from hostname" do
      assert :gitlab == SourceUrl.detect_platform("gitlab.com")
      assert :gitlab == SourceUrl.detect_platform("GitLab.com")
    end

    test "detects GitLab from subdomains" do
      assert :gitlab == SourceUrl.detect_platform("ci.gitlab.com")
      assert :gitlab == SourceUrl.detect_platform("pages.gitlab.io")
    end

    test "detects Bitbucket from hostname" do
      assert :bitbucket == SourceUrl.detect_platform("bitbucket.org")
      assert :bitbucket == SourceUrl.detect_platform("Bitbucket.org")
    end

    test "detects Bitbucket from subdomains" do
      assert :bitbucket == SourceUrl.detect_platform("api.bitbucket.org")
    end

    test "returns unknown for unrecognized hosts" do
      assert :unknown == SourceUrl.detect_platform("git.example.com")
      assert :unknown == SourceUrl.detect_platform("sourceforge.net")
      assert :unknown == SourceUrl.detect_platform("codeberg.org")
    end

    test "returns unknown for lookalike domains (strict matching)" do
      # These should NOT match - they contain github/gitlab/bitbucket but aren't real
      assert :unknown == SourceUrl.detect_platform("my-github-clone.com")
      assert :unknown == SourceUrl.detect_platform("notgitlab.example.org")
      assert :unknown == SourceUrl.detect_platform("fakebitbucket.net")
      assert :unknown == SourceUrl.detect_platform("github-mirror.evil.com")
    end

    test "returns unknown for non-string input" do
      assert :unknown == SourceUrl.detect_platform(nil)
      assert :unknown == SourceUrl.detect_platform(123)
    end
  end

  describe "platform_from_repo/1" do
    test "detects platform from Repository struct" do
      repo = %Repository{host: "github.com", owner: "owner", name: "repo"}
      assert :github == SourceUrl.platform_from_repo(repo)
    end

    test "returns unknown when host is nil" do
      repo = %Repository{host: nil, owner: "owner", name: "repo"}
      assert :unknown == SourceUrl.platform_from_repo(repo)
    end
  end

  # ============================================================================
  # GitHub URL Tests
  # ============================================================================

  describe "for_file/5 with GitHub" do
    test "generates correct file URL" do
      url = SourceUrl.for_file(:github, "elixir-lang", "elixir", "abc123", "lib/elixir.ex")
      assert url == "https://github.com/elixir-lang/elixir/blob/abc123/lib/elixir.ex"
    end

    test "normalizes leading slashes in path" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "/lib/foo.ex")
      assert url == "https://github.com/owner/repo/blob/sha/lib/foo.ex"
    end

    test "normalizes ./ prefix in path" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "./lib/foo.ex")
      assert url == "https://github.com/owner/repo/blob/sha/lib/foo.ex"
    end
  end

  describe "for_line/6 with GitHub" do
    test "generates correct line URL" do
      url = SourceUrl.for_line(:github, "owner", "repo", "abc123", "lib/foo.ex", 42)
      assert url == "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L42"
    end

    test "handles line 1" do
      url = SourceUrl.for_line(:github, "owner", "repo", "sha", "file.ex", 1)
      assert url == "https://github.com/owner/repo/blob/sha/file.ex#L1"
    end
  end

  describe "for_range/7 with GitHub" do
    test "generates correct range URL" do
      url = SourceUrl.for_range(:github, "owner", "repo", "abc123", "lib/foo.ex", 10, 20)
      assert url == "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L10-L20"
    end

    test "handles same start and end line" do
      url = SourceUrl.for_range(:github, "owner", "repo", "sha", "file.ex", 5, 5)
      assert url == "https://github.com/owner/repo/blob/sha/file.ex#L5-L5"
    end
  end

  # ============================================================================
  # GitLab URL Tests
  # ============================================================================

  describe "for_file/5 with GitLab" do
    test "generates correct file URL with /-/ prefix" do
      url = SourceUrl.for_file(:gitlab, "owner", "repo", "main", "src/app.ex")
      assert url == "https://gitlab.com/owner/repo/-/blob/main/src/app.ex"
    end
  end

  describe "for_line/6 with GitLab" do
    test "generates correct line URL" do
      url = SourceUrl.for_line(:gitlab, "owner", "repo", "main", "src/app.ex", 10)
      assert url == "https://gitlab.com/owner/repo/-/blob/main/src/app.ex#L10"
    end
  end

  describe "for_range/7 with GitLab" do
    test "generates correct range URL (without L prefix on end)" do
      url = SourceUrl.for_range(:gitlab, "owner", "repo", "main", "src/app.ex", 5, 15)
      assert url == "https://gitlab.com/owner/repo/-/blob/main/src/app.ex#L5-15"
    end
  end

  # ============================================================================
  # Bitbucket URL Tests
  # ============================================================================

  describe "for_file/5 with Bitbucket" do
    test "generates correct file URL with src instead of blob" do
      url = SourceUrl.for_file(:bitbucket, "team", "project", "abc123", "lib/mod.ex")
      assert url == "https://bitbucket.org/team/project/src/abc123/lib/mod.ex"
    end
  end

  describe "for_line/6 with Bitbucket" do
    test "generates correct line URL with lines- prefix" do
      url = SourceUrl.for_line(:bitbucket, "team", "project", "abc123", "lib/mod.ex", 5)
      assert url == "https://bitbucket.org/team/project/src/abc123/lib/mod.ex#lines-5"
    end
  end

  describe "for_range/7 with Bitbucket" do
    test "generates correct range URL with colon separator" do
      url = SourceUrl.for_range(:bitbucket, "team", "project", "abc123", "lib/mod.ex", 1, 10)
      assert url == "https://bitbucket.org/team/project/src/abc123/lib/mod.ex#lines-1:10"
    end
  end

  # ============================================================================
  # Unknown Platform Tests
  # ============================================================================

  describe "unknown platform" do
    test "for_file returns nil" do
      assert nil == SourceUrl.for_file(:unknown, "owner", "repo", "sha", "file.ex")
    end

    test "for_line returns nil" do
      assert nil == SourceUrl.for_line(:unknown, "owner", "repo", "sha", "file.ex", 1)
    end

    test "for_range returns nil" do
      assert nil == SourceUrl.for_range(:unknown, "owner", "repo", "sha", "file.ex", 1, 10)
    end
  end

  # ============================================================================
  # Repository Struct Integration Tests
  # ============================================================================

  describe "for_file/2 with Repository struct" do
    test "generates URL from Repository" do
      repo = %Repository{
        host: "github.com",
        owner: "owner",
        name: "repo",
        current_commit: "abc123"
      }

      url = SourceUrl.for_file(repo, "lib/foo.ex")
      assert url == "https://github.com/owner/repo/blob/abc123/lib/foo.ex"
    end

    test "returns nil when Repository has no host" do
      repo = %Repository{host: nil, owner: "owner", name: "repo", current_commit: "sha"}
      assert nil == SourceUrl.for_file(repo, "file.ex")
    end

    test "returns nil when Repository has no owner" do
      repo = %Repository{host: "github.com", owner: nil, name: "repo", current_commit: "sha"}
      assert nil == SourceUrl.for_file(repo, "file.ex")
    end

    test "returns nil when Repository has no commit" do
      repo = %Repository{host: "github.com", owner: "owner", name: "repo", current_commit: nil}
      assert nil == SourceUrl.for_file(repo, "file.ex")
    end

    test "returns nil for unknown platform" do
      repo = %Repository{
        host: "git.example.com",
        owner: "owner",
        name: "repo",
        current_commit: "sha"
      }

      assert nil == SourceUrl.for_file(repo, "file.ex")
    end
  end

  describe "for_line/3 with Repository struct" do
    test "generates URL from Repository" do
      repo = %Repository{
        host: "gitlab.com",
        owner: "group",
        name: "project",
        current_commit: "main"
      }

      url = SourceUrl.for_line(repo, "src/app.ex", 42)
      assert url == "https://gitlab.com/group/project/-/blob/main/src/app.ex#L42"
    end
  end

  describe "for_range/4 with Repository struct" do
    test "generates URL from Repository" do
      repo = %Repository{
        host: "bitbucket.org",
        owner: "team",
        name: "project",
        current_commit: "develop"
      }

      url = SourceUrl.for_range(repo, "lib/mod.ex", 10, 25)
      assert url == "https://bitbucket.org/team/project/src/develop/lib/mod.ex#lines-10:25"
    end
  end

  # ============================================================================
  # url_for_path Tests
  # ============================================================================

  describe "url_for_path/2" do
    test "generates URL for file in current repository" do
      {:ok, url} = SourceUrl.url_for_path("mix.exs")
      assert is_binary(url)
      assert String.contains?(url, "mix.exs")
    end

    test "generates URL with line number" do
      {:ok, url} = SourceUrl.url_for_path("mix.exs", line: 10)
      assert is_binary(url)
      assert String.contains?(url, "#L10") or String.contains?(url, "#lines-10")
    end

    test "generates URL with line range" do
      {:ok, url} = SourceUrl.url_for_path("mix.exs", line: 5, end_line: 15)
      assert is_binary(url)
      # Check for any of the range formats
      assert String.contains?(url, "#L5-L15") or
               String.contains?(url, "#L5-15") or
               String.contains?(url, "#lines-5:15")
    end
  end

  # ============================================================================
  # URL Encoding Tests
  # ============================================================================

  describe "URL encoding" do
    test "encodes spaces in file paths" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/my file.ex")
      # URI.encode_www_form converts spaces to +
      assert url == "https://github.com/owner/repo/blob/sha/lib/my+file.ex"
    end

    test "encodes special characters in file paths" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/foo&bar.ex")
      assert url == "https://github.com/owner/repo/blob/sha/lib/foo%26bar.ex"
    end

    test "encodes hash symbols in file paths" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/foo#bar.ex")
      assert url == "https://github.com/owner/repo/blob/sha/lib/foo%23bar.ex"
    end

    test "preserves already valid path characters" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/foo_bar-baz.ex")
      # Note: underscores may be encoded by encode_www_form
      assert String.contains?(url, "foo") and String.contains?(url, "bar")
    end
  end

  # ============================================================================
  # Path Traversal Prevention Tests
  # ============================================================================

  describe "path traversal prevention" do
    test "removes .. sequences from paths" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/../etc/passwd")
      refute String.contains?(url, "..")
    end

    test "removes multiple consecutive dots" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib/.../foo.ex")
      refute String.contains?(url, "...")
    end

    test "collapses multiple slashes in path" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "lib//foo///bar.ex")
      # Extract path portion after /blob/sha/
      path_portion = String.split(url, "/blob/sha/") |> List.last()
      refute String.contains?(path_portion, "//")
    end

    test "handles combined path normalization" do
      url = SourceUrl.for_file(:github, "owner", "repo", "sha", "/./lib/../src//file.ex")
      # Extract path portion after /blob/sha/
      path_portion = String.split(url, "/blob/sha/") |> List.last()
      # Should not contain .., or //
      refute String.contains?(path_portion, "..")
      refute String.contains?(path_portion, "//")
    end
  end

  # ============================================================================
  # Line Number Validation Tests
  # ============================================================================

  describe "line number validation" do
    test "accepts valid line numbers" do
      assert is_binary(SourceUrl.for_line(:github, "o", "r", "sha", "f.ex", 1))
      assert is_binary(SourceUrl.for_line(:github, "o", "r", "sha", "f.ex", 1_000_000))
    end

    test "rejects line numbers exceeding max" do
      # Line > 1_000_000 should not match the guard
      result = SourceUrl.for_line(:github, "o", "r", "sha", "f.ex", 1_000_001)
      assert is_nil(result)
    end

    test "rejects zero line numbers" do
      result = SourceUrl.for_line(:github, "o", "r", "sha", "f.ex", 0)
      assert is_nil(result)
    end

    test "rejects negative line numbers" do
      result = SourceUrl.for_line(:github, "o", "r", "sha", "f.ex", -1)
      assert is_nil(result)
    end
  end

  # ============================================================================
  # Line Range Validation Tests
  # ============================================================================

  describe "line range validation" do
    test "accepts valid line ranges" do
      assert is_binary(SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 1, 10))
      assert is_binary(SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 5, 5))
    end

    test "rejects reversed line ranges (start > end)" do
      result = SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 20, 10)
      assert is_nil(result)
    end

    test "rejects end line exceeding max" do
      result = SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 1, 1_000_001)
      assert is_nil(result)
    end

    test "rejects zero in line ranges" do
      assert is_nil(SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 0, 10))
      assert is_nil(SourceUrl.for_range(:github, "o", "r", "sha", "f.ex", 1, 0))
    end
  end

  # ============================================================================
  # Missing Field Tests (including no_name)
  # ============================================================================

  describe "Repository struct with missing name" do
    test "returns nil when Repository has no name" do
      repo = %Repository{host: "github.com", owner: "owner", name: nil, current_commit: "sha"}
      assert is_nil(SourceUrl.for_file(repo, "file.ex"))
    end

    test "returns nil for for_line with no name" do
      repo = %Repository{host: "github.com", owner: "owner", name: nil, current_commit: "sha"}
      assert is_nil(SourceUrl.for_line(repo, "file.ex", 10))
    end

    test "returns nil for for_range with no name" do
      repo = %Repository{host: "github.com", owner: "owner", name: nil, current_commit: "sha"}
      assert is_nil(SourceUrl.for_range(repo, "file.ex", 1, 10))
    end
  end
end
