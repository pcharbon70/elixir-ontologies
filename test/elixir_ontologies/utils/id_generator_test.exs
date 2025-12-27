defmodule ElixirOntologies.Utils.IdGeneratorTest do
  @moduledoc """
  Tests for the IdGenerator utility module.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Utils.IdGenerator

  describe "generate_id/2" do
    test "generates a 12-character ID by default" do
      id = IdGenerator.generate_id("test@example.com")
      assert String.length(id) == 12
      assert String.match?(id, ~r/^[0-9a-f]+$/)
    end

    test "generates deterministic IDs" do
      id1 = IdGenerator.generate_id("test@example.com")
      id2 = IdGenerator.generate_id("test@example.com")
      assert id1 == id2
    end

    test "generates different IDs for different inputs" do
      id1 = IdGenerator.generate_id("test1@example.com")
      id2 = IdGenerator.generate_id("test2@example.com")
      refute id1 == id2
    end

    test "respects custom length option" do
      id = IdGenerator.generate_id("test", length: 16)
      assert String.length(id) == 16
    end

    test "handles list input by joining with colons" do
      id1 = IdGenerator.generate_id(["a", "b", "c"])
      id2 = IdGenerator.generate_id("a:b:c")
      assert id1 == id2
    end

    test "applies downcase normalization" do
      id1 = IdGenerator.generate_id("TEST@EXAMPLE.COM", normalize: :downcase)
      id2 = IdGenerator.generate_id("test@example.com", normalize: :downcase)
      assert id1 == id2
    end

    test "applies trim normalization" do
      id1 = IdGenerator.generate_id("  test  ", normalize: :trim)
      id2 = IdGenerator.generate_id("test", normalize: :trim)
      assert id1 == id2
    end

    test "returns full hash when length >= 64" do
      id = IdGenerator.generate_id("test", length: 64)
      assert String.length(id) == 64
    end
  end

  describe "short_id/1" do
    test "generates an 8-character ID" do
      id = IdGenerator.short_id("https://github.com/user/repo")
      assert String.length(id) == 8
    end

    test "accepts list input" do
      id = IdGenerator.short_id(["user", "repo"])
      assert String.length(id) == 8
    end
  end

  describe "agent_id/1" do
    test "generates a 12-character ID" do
      id = IdGenerator.agent_id("user@example.com")
      assert String.length(id) == 12
    end

    test "normalizes email to lowercase" do
      id1 = IdGenerator.agent_id("USER@EXAMPLE.COM")
      id2 = IdGenerator.agent_id("user@example.com")
      assert id1 == id2
    end

    test "generates consistent IDs for same email" do
      id1 = IdGenerator.agent_id("test@example.com")
      id2 = IdGenerator.agent_id("test@example.com")
      assert id1 == id2
    end
  end

  describe "content_id/1" do
    test "generates a 16-character ID" do
      id = IdGenerator.content_id("defmodule Foo do\nend")
      assert String.length(id) == 16
    end

    test "is deterministic for same content" do
      content = "defmodule Bar do\n  def hello, do: :world\nend"
      id1 = IdGenerator.content_id(content)
      id2 = IdGenerator.content_id(content)
      assert id1 == id2
    end

    test "is different for different content" do
      id1 = IdGenerator.content_id("content1")
      id2 = IdGenerator.content_id("content2")
      refute id1 == id2
    end
  end

  describe "full_hash/1" do
    test "generates a 64-character hash" do
      hash = IdGenerator.full_hash("sensitive@email.com")
      assert String.length(hash) == 64
    end

    test "generates lowercase hex" do
      hash = IdGenerator.full_hash("test")
      assert String.match?(hash, ~r/^[0-9a-f]{64}$/)
    end

    test "is deterministic" do
      hash1 = IdGenerator.full_hash("test")
      hash2 = IdGenerator.full_hash("test")
      assert hash1 == hash2
    end
  end

  describe "delegation_id/2" do
    test "generates a 12-character ID" do
      id = IdGenerator.delegation_id("delegate@example.com", "delegator@example.com")
      assert String.length(id) == 12
    end

    test "is deterministic" do
      id1 = IdGenerator.delegation_id("a", "b")
      id2 = IdGenerator.delegation_id("a", "b")
      assert id1 == id2
    end

    test "order matters" do
      id1 = IdGenerator.delegation_id("a", "b")
      id2 = IdGenerator.delegation_id("b", "a")
      refute id1 == id2
    end
  end

  describe "delegation_id/3" do
    test "generates a 12-character ID with activity" do
      id = IdGenerator.delegation_id("delegate", "delegator", "activity:123")
      assert String.length(id) == 12
    end

    test "includes activity in hash" do
      id1 = IdGenerator.delegation_id("d", "dr", "act1")
      id2 = IdGenerator.delegation_id("d", "dr", "act2")
      refute id1 == id2
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      id = IdGenerator.generate_id("")
      assert String.length(id) == 12
    end

    test "handles empty list" do
      id = IdGenerator.generate_id([])
      # Joins to empty string
      assert String.length(id) == 12
    end

    test "handles unicode" do
      id = IdGenerator.generate_id("user@example.com")
      assert String.length(id) == 12
    end

    test "handles very long input" do
      long_input = String.duplicate("a", 10_000)
      id = IdGenerator.generate_id(long_input)
      assert String.length(id) == 12
    end

    test "handles special characters" do
      id = IdGenerator.generate_id("test!@#$%^&*(){}[]")
      assert String.length(id) == 12
    end
  end
end
