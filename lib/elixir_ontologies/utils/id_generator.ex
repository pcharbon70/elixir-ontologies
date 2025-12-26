defmodule ElixirOntologies.Utils.IdGenerator do
  @moduledoc """
  Centralized utility for generating deterministic SHA256-based identifiers.

  This module provides consistent ID generation across the codebase, replacing
  duplicated patterns for creating hash-based identifiers. All IDs are:

  - Deterministic: Same input always produces same output
  - Collision-resistant: SHA256 provides strong hash distribution
  - Configurable: Slice length can be adjusted per use case

  ## Common Slice Lengths

  | Length | Use Case | Collision Probability |
  |--------|----------|----------------------|
  | 8 | Repository identifiers | 1 in 4.3 billion |
  | 12 | Agent/delegation IDs | 1 in 281 trillion |
  | 16 | Entity content hashes | 1 in 18 quintillion |
  | 64 | Full hash (no slice) | Cryptographic strength |

  ## Usage

      alias ElixirOntologies.Utils.IdGenerator

      # Basic usage with default 12-character slice
      IdGenerator.generate_id("user@example.com")
      #=> "a1b2c3d4e5f6"

      # Custom slice length
      IdGenerator.generate_id("content", length: 16)
      #=> "a1b2c3d4e5f6g7h8"

      # From multiple components
      IdGenerator.generate_id(["delegate", "delegator", "activity"])
      #=> "x9y8z7w6v5u4"

      # Convenience functions
      IdGenerator.short_id("input")    # 8 chars
      IdGenerator.agent_id("email")    # 12 chars
      IdGenerator.content_id("text")   # 16 chars
      IdGenerator.full_hash("input")   # 64 chars

  ## Security Note

  These IDs are suitable for identification purposes but should not be used
  for security-critical operations like authentication tokens.
  """

  # Default slice length for most identifiers
  @default_length 12

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Generates a deterministic SHA256-based identifier.

  ## Parameters

  - `input` - String or list of strings to hash
  - `opts` - Options keyword list

  ## Options

  - `:length` - Number of hex characters to return (default: 12, max: 64)
  - `:normalize` - Apply normalization (`:downcase`, `:trim`, or `nil`)

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.generate_id("test@example.com")
      iex> String.length(id)
      12

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.generate_id("test", length: 16)
      iex> String.length(id)
      16

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id1 = IdGenerator.generate_id("test")
      iex> id2 = IdGenerator.generate_id("test")
      iex> id1 == id2
      true

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.generate_id(["a", "b", "c"])
      iex> String.length(id)
      12
  """
  @spec generate_id(String.t() | [String.t()], keyword()) :: String.t()
  def generate_id(input, opts \\ [])

  def generate_id(components, opts) when is_list(components) do
    components
    |> Enum.join(":")
    |> generate_id(opts)
  end

  def generate_id(input, opts) when is_binary(input) do
    length = Keyword.get(opts, :length, @default_length)
    normalize = Keyword.get(opts, :normalize)

    normalized_input = apply_normalization(input, normalize)

    :crypto.hash(:sha256, normalized_input)
    |> Base.encode16(case: :lower)
    |> maybe_slice(length)
  end

  @doc """
  Generates a short 8-character identifier.

  Useful for repository identifiers and short references.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.short_id("https://github.com/user/repo")
      iex> String.length(id)
      8
  """
  @spec short_id(String.t() | [String.t()]) :: String.t()
  def short_id(input) do
    generate_id(input, length: 8)
  end

  @doc """
  Generates a 12-character agent identifier.

  Standard length for agent and delegation IDs.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.agent_id("user@example.com")
      iex> String.length(id)
      12

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.agent_id("USER@EXAMPLE.COM")
      iex> id2 = IdGenerator.agent_id("user@example.com")
      iex> id == id2
      true
  """
  @spec agent_id(String.t()) :: String.t()
  def agent_id(email) when is_binary(email) do
    generate_id(email, length: 12, normalize: :downcase)
  end

  @doc """
  Generates a 16-character content hash identifier.

  Used for entity content hashes and version identifiers.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.content_id("defmodule Foo do\\nend")
      iex> String.length(id)
      16
  """
  @spec content_id(String.t()) :: String.t()
  def content_id(content) when is_binary(content) do
    generate_id(content, length: 16)
  end

  @doc """
  Generates a full 64-character SHA256 hash.

  Used when full hash strength is required, such as email anonymization.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> hash = IdGenerator.full_hash("sensitive@email.com")
      iex> String.length(hash)
      64
  """
  @spec full_hash(String.t()) :: String.t()
  def full_hash(input) when is_binary(input) do
    :crypto.hash(:sha256, input)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a delegation identifier from delegate and delegator.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.delegation_id("delegate@example.com", "delegator@example.com")
      iex> String.length(id)
      12
  """
  @spec delegation_id(String.t(), String.t()) :: String.t()
  def delegation_id(delegate, delegator) do
    generate_id([delegate, delegator], length: 12)
  end

  @doc """
  Generates a delegation identifier with activity context.

  ## Examples

      iex> alias ElixirOntologies.Utils.IdGenerator
      iex> id = IdGenerator.delegation_id("delegate", "delegator", "activity:123")
      iex> String.length(id)
      12
  """
  @spec delegation_id(String.t(), String.t(), String.t()) :: String.t()
  def delegation_id(delegate, delegator, activity) do
    generate_id([delegate, delegator, activity], length: 12)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_normalization(input, nil), do: input
  defp apply_normalization(input, :downcase), do: String.downcase(input)
  defp apply_normalization(input, :trim), do: String.trim(input)

  defp maybe_slice(hash, length) when length >= 64, do: hash
  defp maybe_slice(hash, length), do: String.slice(hash, 0, length)
end
