defmodule ElixirOntologies.Extractors.Evolution.DelegationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Delegation
  alias ElixirOntologies.Extractors.Evolution.Delegation.{CodeOwner, Team, ReviewApproval}
  alias ElixirOntologies.Extractors.Evolution.Commit

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts \\ []) do
    %Commit{
      sha: Keyword.get(opts, :sha, "abc123def456abc123def456abc123def456abc1"),
      short_sha: Keyword.get(opts, :short_sha, "abc123d"),
      message: Keyword.get(opts, :message),
      subject: Keyword.get(opts, :subject),
      body: Keyword.get(opts, :body),
      author_name: Keyword.get(opts, :author_name, "Test Author"),
      author_email: Keyword.get(opts, :author_email, "test@example.com"),
      author_date: Keyword.get(opts, :author_date, DateTime.utc_now()),
      committer_name: Keyword.get(opts, :committer_name, "Test Committer"),
      committer_email: Keyword.get(opts, :committer_email, "test@example.com"),
      commit_date: Keyword.get(opts, :commit_date, DateTime.utc_now()),
      parents: Keyword.get(opts, :parents, ["def456abc123def456abc123def456abc123def4"]),
      is_merge: Keyword.get(opts, :is_merge, false),
      tree_sha: Keyword.get(opts, :tree_sha),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "Delegation struct" do
    test "enforces required keys" do
      delegation = %Delegation{
        delegation_id: "delegation:abc123",
        delegate: "agent:abc",
        delegator: "agent:def"
      }

      assert delegation.delegation_id == "delegation:abc123"
      assert delegation.delegate == "agent:abc"
      assert delegation.delegator == "agent:def"
    end

    test "has default values" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b"
      }

      assert delegation.activity == nil
      assert delegation.reason == nil
      assert delegation.scope == []
      assert delegation.metadata == %{}
    end
  end

  describe "CodeOwner struct" do
    test "enforces required keys" do
      owner = %CodeOwner{
        pattern: "*.ex",
        owners: ["@alice", "@bob"]
      }

      assert owner.pattern == "*.ex"
      assert owner.owners == ["@alice", "@bob"]
    end

    test "has default values" do
      owner = %CodeOwner{
        pattern: "*",
        owners: ["@team"]
      }

      assert owner.source == nil
      assert owner.line_number == nil
    end
  end

  describe "Team struct" do
    test "enforces required keys" do
      team = %Team{
        team_id: "team:core",
        name: "Core Team"
      }

      assert team.team_id == "team:core"
      assert team.name == "Core Team"
    end

    test "has default values" do
      team = %Team{
        team_id: "team:test",
        name: "Test"
      }

      assert team.members == []
      assert team.leads == []
      assert team.metadata == %{}
    end
  end

  describe "ReviewApproval struct" do
    test "enforces required keys" do
      approval = %ReviewApproval{
        approval_id: "approval:abc",
        reviewer: "agent:abc",
        activity: "activity:def"
      }

      assert approval.approval_id == "approval:abc"
      assert approval.reviewer == "agent:abc"
      assert approval.activity == "activity:def"
    end

    test "has default values" do
      approval = %ReviewApproval{
        approval_id: "a:1",
        reviewer: "r",
        activity: "a"
      }

      assert approval.approved_at == nil
      assert approval.metadata == %{}
    end
  end

  # ===========================================================================
  # Delegation ID Tests
  # ===========================================================================

  describe "build_delegation_id/2" do
    test "builds delegation ID from delegate and delegator" do
      id = Delegation.build_delegation_id("agent:abc", "agent:def")
      assert String.starts_with?(id, "delegation:")
      assert String.length(id) == 23  # "delegation:" (11) + hash (12)
    end

    test "produces stable IDs" do
      id1 = Delegation.build_delegation_id("agent:abc", "agent:def")
      id2 = Delegation.build_delegation_id("agent:abc", "agent:def")
      assert id1 == id2
    end

    test "produces different IDs for different pairs" do
      id1 = Delegation.build_delegation_id("agent:abc", "agent:def")
      id2 = Delegation.build_delegation_id("agent:def", "agent:abc")
      assert id1 != id2
    end
  end

  describe "build_delegation_id/3" do
    test "includes activity context" do
      id = Delegation.build_delegation_id("agent:abc", "agent:def", "activity:xyz")
      assert String.starts_with?(id, "delegation:")
    end

    test "different activity produces different ID" do
      id1 = Delegation.build_delegation_id("agent:abc", "agent:def", "activity:1")
      id2 = Delegation.build_delegation_id("agent:abc", "agent:def", "activity:2")
      assert id1 != id2
    end
  end

  # ===========================================================================
  # CODEOWNERS Parsing Tests
  # ===========================================================================

  describe "parse_codeowners_content/2" do
    test "parses simple patterns" do
      content = """
      *.ex @elixir-team
      lib/** @alice
      """

      {:ok, owners} = Delegation.parse_codeowners_content(content)

      assert length(owners) == 2

      [first, second] = owners
      assert first.pattern == "*.ex"
      assert first.owners == ["@elixir-team"]
      assert second.pattern == "lib/**"
      assert second.owners == ["@alice"]
    end

    test "ignores comments" do
      content = """
      # This is a comment
      *.ex @team
      # Another comment
      """

      {:ok, owners} = Delegation.parse_codeowners_content(content)

      assert length(owners) == 1
    end

    test "ignores empty lines" do
      content = """
      *.ex @team

      lib/** @other
      """

      {:ok, owners} = Delegation.parse_codeowners_content(content)

      assert length(owners) == 2
    end

    test "parses multiple owners" do
      content = "lib/** @alice @bob @charlie"

      {:ok, [owner]} = Delegation.parse_codeowners_content(content)

      assert owner.owners == ["@alice", "@bob", "@charlie"]
    end

    test "parses team owners" do
      content = "*.ex @org/elixir-team"

      {:ok, [owner]} = Delegation.parse_codeowners_content(content)

      assert owner.owners == ["@org/elixir-team"]
    end

    test "tracks line numbers" do
      content = """
      # Comment
      *.ex @team
      lib/** @other
      """

      {:ok, owners} = Delegation.parse_codeowners_content(content, "CODEOWNERS")

      assert length(owners) == 2
      [first, second] = owners
      assert first.line_number == 2
      assert second.line_number == 3
    end

    test "tracks source file" do
      content = "*.ex @team"

      {:ok, [owner]} = Delegation.parse_codeowners_content(content, ".github/CODEOWNERS")

      assert owner.source == ".github/CODEOWNERS"
    end
  end

  # ===========================================================================
  # Pattern Matching Tests
  # ===========================================================================

  describe "find_owners/2" do
    test "matches exact file extension" do
      owners = [
        %CodeOwner{pattern: "*.ex", owners: ["@elixir"]}
      ]

      {:ok, result} = Delegation.find_owners(owners, "lib/foo.ex")
      assert result.owners == ["@elixir"]
    end

    test "matches directory wildcard" do
      owners = [
        %CodeOwner{pattern: "lib/**", owners: ["@lib-team"]}
      ]

      {:ok, result} = Delegation.find_owners(owners, "lib/foo/bar.ex")
      assert result.owners == ["@lib-team"]
    end

    test "last match wins" do
      owners = [
        %CodeOwner{pattern: "*.ex", owners: ["@general"]},
        %CodeOwner{pattern: "lib/**", owners: ["@lib-team"]}
      ]

      {:ok, result} = Delegation.find_owners(owners, "lib/foo.ex")
      assert result.owners == ["@lib-team"]
    end

    test "returns error when no match" do
      owners = [
        %CodeOwner{pattern: "*.ex", owners: ["@elixir"]}
      ]

      assert {:error, :no_match} = Delegation.find_owners(owners, "README.md")
    end

    test "matches root pattern" do
      owners = [
        %CodeOwner{pattern: "/mix.exs", owners: ["@core"]}
      ]

      {:ok, result} = Delegation.find_owners(owners, "mix.exs")
      assert result.owners == ["@core"]
    end

    test "matches directory prefix" do
      owners = [
        %CodeOwner{pattern: "docs/", owners: ["@docs"]}
      ]

      {:ok, result} = Delegation.find_owners(owners, "docs/README.md")
      assert result.owners == ["@docs"]
    end
  end

  describe "find_owners_for_files/2" do
    test "returns map of file to owners" do
      owners = [
        %CodeOwner{pattern: "*.ex", owners: ["@elixir"]},
        %CodeOwner{pattern: "*.md", owners: ["@docs"]}
      ]

      result = Delegation.find_owners_for_files(owners, ["lib/foo.ex", "README.md"])

      assert Map.has_key?(result, "lib/foo.ex")
      assert Map.has_key?(result, "README.md")
      assert result["lib/foo.ex"].owners == ["@elixir"]
      assert result["README.md"].owners == ["@docs"]
    end

    test "excludes files with no match" do
      owners = [
        %CodeOwner{pattern: "*.ex", owners: ["@elixir"]}
      ]

      result = Delegation.find_owners_for_files(owners, ["lib/foo.ex", "README.md"])

      assert Map.has_key?(result, "lib/foo.ex")
      refute Map.has_key?(result, "README.md")
    end
  end

  # ===========================================================================
  # Review Trailer Parsing Tests
  # ===========================================================================

  describe "parse_review_trailers/3" do
    test "parses Reviewed-by trailer" do
      message = "Fix bug\n\nReviewed-by: Alice <alice@example.com>"

      approvals = Delegation.parse_review_trailers(message, "activity:abc")

      assert length(approvals) == 1
      [approval] = approvals
      assert approval.activity == "activity:abc"
      assert approval.metadata.reviewer_name == "Alice"
      assert approval.metadata.reviewer_email == "alice@example.com"
    end

    test "parses Approved-by trailer" do
      message = "Add feature\n\nApproved-by: Bob <bob@example.com>"

      approvals = Delegation.parse_review_trailers(message, "activity:def")

      assert length(approvals) == 1
    end

    test "parses Acked-by trailer" do
      message = "Update\n\nAcked-by: Charlie <charlie@example.com>"

      approvals = Delegation.parse_review_trailers(message, "activity:xyz")

      assert length(approvals) == 1
    end

    test "parses Signed-off-by trailer" do
      message = "Commit\n\nSigned-off-by: Developer <dev@example.com>"

      approvals = Delegation.parse_review_trailers(message, "activity:123")

      assert length(approvals) == 1
    end

    test "parses multiple trailers" do
      message = """
      Fix issue

      Reviewed-by: Alice <alice@example.com>
      Approved-by: Bob <bob@example.com>
      """

      approvals = Delegation.parse_review_trailers(message, "activity:abc")

      assert length(approvals) == 2
    end

    test "parses trailer without email" do
      message = "Fix\n\nReviewed-by: Alice"

      approvals = Delegation.parse_review_trailers(message, "activity:abc")

      assert length(approvals) == 1
      [approval] = approvals
      assert approval.metadata.reviewer_name == "Alice"
    end

    test "includes timestamp when provided" do
      now = DateTime.utc_now()
      message = "Fix\n\nReviewed-by: Alice <alice@example.com>"

      approvals = Delegation.parse_review_trailers(message, "activity:abc", now)

      [approval] = approvals
      assert approval.approved_at == now
    end
  end

  # ===========================================================================
  # Team Membership Tests
  # ===========================================================================

  describe "parse_team_file/1" do
    test "parses team definition" do
      content = """
      team: Core Team
      leads: @alice @bob
      members: @charlie @david @eve
      """

      {:ok, team} = Delegation.parse_team_file(content)

      assert team.name == "Core Team"
      assert team.leads == ["@alice", "@bob"]
      assert team.members == ["@charlie", "@david", "@eve"]
      assert team.team_id == "team:core-team"
    end

    test "handles minimal team" do
      content = """
      team: Minimal
      leads: @lead
      members: @member
      """

      {:ok, team} = Delegation.parse_team_file(content)

      assert team.name == "Minimal"
    end

    test "returns error for invalid format" do
      content = "not a team file"

      assert {:error, :invalid_format} = Delegation.parse_team_file(content)
    end
  end

  describe "build_team_delegations/1" do
    test "creates delegations from members to leads" do
      team = %Team{
        team_id: "team:core",
        name: "Core",
        leads: ["agent:lead1", "agent:lead2"],
        members: ["agent:member1", "agent:member2"]
      }

      delegations = Delegation.build_team_delegations(team)

      # Each member delegates to each lead: 2 members * 2 leads = 4
      assert length(delegations) == 4

      Enum.each(delegations, fn d ->
        assert d.reason == :team_membership
        assert d.metadata.team_id == "team:core"
      end)
    end

    test "excludes self-delegation" do
      team = %Team{
        team_id: "team:small",
        name: "Small",
        leads: ["agent:alice"],
        members: ["agent:alice", "agent:bob"]  # alice is both lead and member
      }

      delegations = Delegation.build_team_delegations(team)

      # Only bob delegates to alice, not alice to herself
      assert length(delegations) == 1
      [d] = delegations
      assert d.delegate == "agent:bob"
      assert d.delegator == "agent:alice"
    end
  end

  # ===========================================================================
  # Delegation Extraction Tests
  # ===========================================================================

  describe "extract_delegations/3" do
    @tag :integration
    test "extracts delegations from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      assert is_list(delegations)
    end

    test "extracts bot delegation" do
      commit = create_commit(
        author_email: "dependabot[bot]@users.noreply.github.com"
      )

      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      bot_delegations = Enum.filter(delegations, &(&1.reason == :bot_config))
      assert length(bot_delegations) == 1
    end

    test "extracts review delegations" do
      commit = create_commit(
        message: "Fix bug\n\nReviewed-by: Alice <alice@example.com>"
      )

      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      review_delegations = Enum.filter(delegations, &(&1.reason == :review_approval))
      assert length(review_delegations) == 1
    end

    test "can exclude code owners" do
      commit = create_commit()
      {:ok, delegations} = Delegation.extract_delegations(".", commit, include_code_owners: false)

      code_owner_delegations = Enum.filter(delegations, &(&1.reason == :code_ownership))
      assert length(code_owner_delegations) == 0
    end

    test "can exclude bot delegation" do
      commit = create_commit(
        author_email: "dependabot[bot]@users.noreply.github.com"
      )

      {:ok, delegations} = Delegation.extract_delegations(".", commit, include_bot_delegation: false)

      bot_delegations = Enum.filter(delegations, &(&1.reason == :bot_config))
      assert length(bot_delegations) == 0
    end

    test "can exclude review approvals" do
      commit = create_commit(
        message: "Fix\n\nReviewed-by: Alice <alice@example.com>"
      )

      {:ok, delegations} = Delegation.extract_delegations(".", commit, include_review_approvals: false)

      review_delegations = Enum.filter(delegations, &(&1.reason == :review_approval))
      assert length(review_delegations) == 0
    end
  end

  describe "extract_delegations!/3" do
    @tag :integration
    test "returns delegations on success" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      delegations = Delegation.extract_delegations!(".", commit)

      assert is_list(delegations)
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "delegates_to?/2" do
    test "returns true when delegation matches" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "agent:member",
        delegator: "agent:lead"
      }

      assert Delegation.delegates_to?(delegation, "agent:lead")
    end

    test "returns false when delegation doesn't match" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "agent:member",
        delegator: "agent:lead"
      }

      refute Delegation.delegates_to?(delegation, "agent:other")
    end
  end

  describe "reason?/2" do
    test "returns true for matching reason" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b",
        reason: :code_ownership
      }

      assert Delegation.reason?(delegation, :code_ownership)
    end

    test "returns false for non-matching reason" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b",
        reason: :code_ownership
      }

      refute Delegation.reason?(delegation, :team_membership)
    end
  end

  describe "applies_to_file?/2" do
    test "returns true when scope is empty" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b",
        scope: []
      }

      assert Delegation.applies_to_file?(delegation, "any/file.ex")
    end

    test "returns true when file matches scope" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b",
        scope: ["lib/**"]
      }

      assert Delegation.applies_to_file?(delegation, "lib/foo.ex")
    end

    test "returns false when file doesn't match scope" do
      delegation = %Delegation{
        delegation_id: "d:1",
        delegate: "a",
        delegator: "b",
        scope: ["lib/**"]
      }

      refute Delegation.applies_to_file?(delegation, "test/foo_test.exs")
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "full workflow integration" do
    @tag :integration
    test "can extract complete delegation model from commits" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      Enum.each(delegations, fn d ->
        assert d.delegation_id != nil
        assert d.delegate != nil
        assert d.delegator != nil
      end)
    end

    test "delegation chain for bot with reviewer" do
      commit = create_commit(
        author_email: "dependabot[bot]@users.noreply.github.com",
        message: "Update deps\n\nReviewed-by: Alice <alice@example.com>"
      )

      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      # Should have both bot delegation and review delegation
      reasons = Enum.map(delegations, & &1.reason) |> Enum.uniq()
      assert :bot_config in reasons
      assert :review_approval in reasons
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles commit with no trailers" do
      commit = create_commit(message: "Simple commit with no trailers")

      {:ok, delegations} = Delegation.extract_delegations(".", commit,
        include_code_owners: false,
        include_bot_delegation: false
      )

      assert delegations == []
    end

    test "handles nil message" do
      commit = create_commit(message: nil)

      {:ok, delegations} = Delegation.extract_delegations(".", commit)

      # Should not crash, just return empty or bot delegation
      assert is_list(delegations)
    end

    test "handles empty CODEOWNERS" do
      {:ok, owners} = Delegation.parse_codeowners_content("")

      assert owners == []
    end

    test "handles malformed CODEOWNERS line" do
      content = """
      pattern_only_no_owners
      *.ex @valid
      """

      {:ok, owners} = Delegation.parse_codeowners_content(content)

      # Should skip malformed line
      assert length(owners) == 1
      assert hd(owners).pattern == "*.ex"
    end
  end
end
