defmodule ElixirOntologies.Extractors.Evolution.GitUtilsTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.GitUtils

  # ===========================================================================
  # Git Command Execution Tests
  # ===========================================================================

  describe "run_git_command/3" do
    test "executes valid git commands" do
      {:ok, output} = GitUtils.run_git_command(".", ["rev-parse", "HEAD"])
      assert String.length(String.trim(output)) == 40
    end

    test "returns error for invalid commands" do
      {:error, reason} = GitUtils.run_git_command(".", ["invalid-command-xyz"])
      assert reason == :command_failed
    end

    test "returns error for invalid directory" do
      {:error, reason} = GitUtils.run_git_command("/nonexistent-path-xyz", ["status"])
      assert reason == :command_failed
    end
  end

  describe "default_timeout/0" do
    test "returns 30 seconds" do
      assert GitUtils.default_timeout() == 30_000
    end
  end

  describe "max_commits/0" do
    test "returns 10000" do
      assert GitUtils.max_commits() == 10_000
    end
  end

  # ===========================================================================
  # SHA Validation Tests
  # ===========================================================================

  describe "valid_sha?/1" do
    test "returns true for valid 40-character SHA" do
      assert GitUtils.valid_sha?("abc123def456abc123def456abc123def456abc1")
      assert GitUtils.valid_sha?("ABC123DEF456ABC123DEF456ABC123DEF456ABC1")
      assert GitUtils.valid_sha?("0000000000000000000000000000000000000000")
    end

    test "returns false for short SHA" do
      refute GitUtils.valid_sha?("abc123d")
      refute GitUtils.valid_sha?("abc123def456")
    end

    test "returns false for invalid characters" do
      refute GitUtils.valid_sha?("ghijklmnopghijklmnopghijklmnopghijklmnop")
      refute GitUtils.valid_sha?("abc123def456abc123def456abc123def456abc!")
    end

    test "returns false for non-strings" do
      refute GitUtils.valid_sha?(nil)
      refute GitUtils.valid_sha?(123)
      refute GitUtils.valid_sha?([])
    end
  end

  describe "valid_short_sha?/1" do
    test "returns true for 7-40 character hex strings" do
      assert GitUtils.valid_short_sha?("abc123d")
      assert GitUtils.valid_short_sha?("abc123def456")
      assert GitUtils.valid_short_sha?("abc123def456abc123def456abc123def456abc1")
    end

    test "returns false for too short strings" do
      refute GitUtils.valid_short_sha?("abc12")
      refute GitUtils.valid_short_sha?("abc")
    end

    test "returns false for non-strings" do
      refute GitUtils.valid_short_sha?(nil)
      refute GitUtils.valid_short_sha?(123)
    end
  end

  describe "uncommitted_sha?/1" do
    test "returns true for the uncommitted SHA" do
      assert GitUtils.uncommitted_sha?("0000000000000000000000000000000000000000")
    end

    test "returns false for other SHAs" do
      refute GitUtils.uncommitted_sha?("abc123def456abc123def456abc123def456abc1")
    end
  end

  describe "uncommitted_sha/0" do
    test "returns the all-zeros SHA" do
      assert GitUtils.uncommitted_sha() == "0000000000000000000000000000000000000000"
    end
  end

  # ===========================================================================
  # Reference Validation Tests
  # ===========================================================================

  describe "valid_ref?/1" do
    test "returns true for HEAD" do
      assert GitUtils.valid_ref?("HEAD")
    end

    test "returns true for HEAD~n notation" do
      assert GitUtils.valid_ref?("HEAD~1")
      assert GitUtils.valid_ref?("HEAD~10")
      assert GitUtils.valid_ref?("HEAD~100")
    end

    test "returns true for HEAD^n notation" do
      assert GitUtils.valid_ref?("HEAD^")
      assert GitUtils.valid_ref?("HEAD^1")
      assert GitUtils.valid_ref?("HEAD^2")
    end

    test "returns true for SHA references" do
      assert GitUtils.valid_ref?("abc123d")
      assert GitUtils.valid_ref?("abc123def456abc123def456abc123def456abc1")
    end

    test "returns true for branch names" do
      assert GitUtils.valid_ref?("main")
      assert GitUtils.valid_ref?("develop")
      assert GitUtils.valid_ref?("feature-branch")
      assert GitUtils.valid_ref?("feature_branch")
    end

    test "returns true for refs/heads paths" do
      assert GitUtils.valid_ref?("refs/heads/main")
      assert GitUtils.valid_ref?("refs/tags/v1.0.0")
      assert GitUtils.valid_ref?("refs/remotes/origin/main")
    end

    test "returns false for command injection attempts" do
      refute GitUtils.valid_ref?("HEAD; rm -rf /")
      refute GitUtils.valid_ref?("HEAD && echo pwned")
      refute GitUtils.valid_ref?("HEAD | cat /etc/passwd")
      refute GitUtils.valid_ref?("$(evil)")
      refute GitUtils.valid_ref?("`evil`")
    end

    test "returns false for non-strings" do
      refute GitUtils.valid_ref?(nil)
      refute GitUtils.valid_ref?(123)
    end
  end

  # ===========================================================================
  # Path Validation Tests
  # ===========================================================================

  describe "safe_path?/1" do
    test "returns true for simple paths" do
      assert GitUtils.safe_path?("lib/module.ex")
      assert GitUtils.safe_path?("test/test_helper.exs")
      assert GitUtils.safe_path?("mix.exs")
    end

    test "returns false for path traversal" do
      refute GitUtils.safe_path?("../etc/passwd")
      refute GitUtils.safe_path?("lib/../../../etc/passwd")
      refute GitUtils.safe_path?("foo/bar/../baz")
    end

    test "returns false for absolute paths" do
      refute GitUtils.safe_path?("/etc/passwd")
      refute GitUtils.safe_path?("/home/user/.ssh/id_rsa")
    end

    test "returns false for null bytes" do
      refute GitUtils.safe_path?("file\x00.ex")
    end

    test "returns false for double slashes" do
      refute GitUtils.safe_path?("lib//module.ex")
    end

    test "returns false for non-strings" do
      refute GitUtils.safe_path?(nil)
      refute GitUtils.safe_path?(123)
    end
  end

  describe "normalize_file_path/2" do
    test "returns ok for valid relative paths" do
      {:ok, path} = GitUtils.normalize_file_path("lib/foo.ex", "/repo")
      assert path == "lib/foo.ex"
    end

    test "returns error for path traversal in relative paths" do
      {:error, :invalid_path} = GitUtils.normalize_file_path("../secret", "/repo")
    end

    test "returns error for absolute paths outside repo" do
      {:error, :outside_repo} = GitUtils.normalize_file_path("/other/path", "/repo")
    end

    test "converts absolute paths inside repo to relative" do
      {:ok, path} = GitUtils.normalize_file_path("/repo/lib/foo.ex", "/repo")
      assert path == "lib/foo.ex"
    end
  end

  # ===========================================================================
  # DateTime Parsing Tests
  # ===========================================================================

  describe "parse_iso8601_datetime/1" do
    test "parses valid ISO 8601 datetime" do
      {:ok, dt} = GitUtils.parse_iso8601_datetime("2024-01-15T10:30:00Z")
      assert dt.year == 2024
      assert dt.month == 1
      assert dt.day == 15
      assert dt.hour == 10
      assert dt.minute == 30
    end

    test "handles whitespace" do
      {:ok, dt} = GitUtils.parse_iso8601_datetime(" 2024-01-15T10:30:00Z ")
      assert dt.year == 2024
    end

    test "returns error for invalid datetime" do
      {:error, :invalid_datetime} = GitUtils.parse_iso8601_datetime("invalid")
      {:error, :invalid_datetime} = GitUtils.parse_iso8601_datetime("2024-13-01")
    end

    test "returns error for non-strings" do
      {:error, :invalid_datetime} = GitUtils.parse_iso8601_datetime(nil)
      {:error, :invalid_datetime} = GitUtils.parse_iso8601_datetime(123)
    end
  end

  describe "parse_iso8601_datetime!/1" do
    test "returns DateTime for valid input" do
      dt = GitUtils.parse_iso8601_datetime!("2024-01-15T10:30:00Z")
      assert dt.year == 2024
    end

    test "returns nil for invalid input" do
      assert is_nil(GitUtils.parse_iso8601_datetime!("invalid"))
    end
  end

  describe "parse_unix_timestamp/1" do
    test "parses valid timestamps" do
      {:ok, dt} = GitUtils.parse_unix_timestamp(1_705_315_800)
      assert dt.year == 2024
    end

    test "returns error for nil" do
      {:error, :invalid_timestamp} = GitUtils.parse_unix_timestamp(nil)
    end

    test "returns error for non-integers" do
      {:error, :invalid_timestamp} = GitUtils.parse_unix_timestamp("123")
    end
  end

  describe "parse_unix_timestamp!/1" do
    test "returns DateTime for valid input" do
      dt = GitUtils.parse_unix_timestamp!(1_705_315_800)
      assert dt.year == 2024
    end

    test "returns nil for invalid input" do
      assert is_nil(GitUtils.parse_unix_timestamp!(nil))
    end
  end

  # ===========================================================================
  # String Utilities Tests
  # ===========================================================================

  describe "empty_to_nil/1" do
    test "returns nil for empty string" do
      assert is_nil(GitUtils.empty_to_nil(""))
    end

    test "returns original string for non-empty" do
      assert GitUtils.empty_to_nil("hello") == "hello"
    end
  end

  # ===========================================================================
  # Email Anonymization Tests
  # ===========================================================================

  describe "anonymize_email/1" do
    test "returns SHA256 hash for email" do
      hash = GitUtils.anonymize_email("user@example.com")
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, hash)
    end

    test "returns consistent hash for same email" do
      hash1 = GitUtils.anonymize_email("user@example.com")
      hash2 = GitUtils.anonymize_email("user@example.com")
      assert hash1 == hash2
    end

    test "returns different hashes for different emails" do
      hash1 = GitUtils.anonymize_email("user1@example.com")
      hash2 = GitUtils.anonymize_email("user2@example.com")
      assert hash1 != hash2
    end

    test "returns nil for nil input" do
      assert is_nil(GitUtils.anonymize_email(nil))
    end
  end

  describe "maybe_anonymize_email/2" do
    test "returns original email when anonymize_emails is false" do
      email = GitUtils.maybe_anonymize_email("user@example.com", anonymize_emails: false)
      assert email == "user@example.com"
    end

    test "returns original email by default" do
      email = GitUtils.maybe_anonymize_email("user@example.com")
      assert email == "user@example.com"
    end

    test "returns hash when anonymize_emails is true" do
      hash = GitUtils.maybe_anonymize_email("user@example.com", anonymize_emails: true)
      assert String.length(hash) == 64
    end
  end

  # ===========================================================================
  # Error Formatting Tests
  # ===========================================================================

  describe "format_error/1" do
    test "formats known error atoms" do
      assert GitUtils.format_error(:repo_not_found) == "Repository not found"
      assert GitUtils.format_error(:invalid_ref) == "Invalid git reference"
      assert GitUtils.format_error(:invalid_path) == "Invalid or unsafe file path"
      assert GitUtils.format_error(:outside_repo) == "Path is outside repository"
      assert GitUtils.format_error(:file_not_found) == "File not found"
      assert GitUtils.format_error(:file_not_tracked) == "File not tracked in git"
      assert GitUtils.format_error(:command_failed) == "Git command failed"
      assert GitUtils.format_error(:parse_error) == "Failed to parse git output"
      assert GitUtils.format_error(:timeout) == "Command timed out"
    end

    test "formats unknown errors with inspect" do
      assert GitUtils.format_error(:unknown_error) == "Unknown error: :unknown_error"
    end
  end
end
