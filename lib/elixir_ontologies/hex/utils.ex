defmodule ElixirOntologies.Hex.Utils do
  @moduledoc """
  Shared utility functions for Hex.pm batch processing modules.

  Consolidates common functionality to reduce code duplication.
  """

  @doc """
  Parses an ISO8601 datetime string to a DateTime struct.

  Returns `nil` for `nil` input or invalid strings.

  ## Examples

      iex> Utils.parse_datetime("2024-01-15T10:30:00Z")
      ~U[2024-01-15 10:30:00Z]

      iex> Utils.parse_datetime(nil)
      nil
  """
  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  @doc """
  Formats a duration in milliseconds to a human-readable string.

  ## Examples

      iex> Utils.format_duration_ms(500)
      "500ms"

      iex> Utils.format_duration_ms(1500)
      "1.5s"

      iex> Utils.format_duration_ms(90000)
      "1m 30s"
  """
  @spec format_duration_ms(non_neg_integer()) :: String.t()
  def format_duration_ms(ms) when ms >= 60_000 do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  def format_duration_ms(ms) when ms >= 1000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  def format_duration_ms(ms) do
    "#{ms}ms"
  end

  @doc """
  Formats a duration in seconds to a human-readable string.

  ## Examples

      iex> Utils.format_duration_seconds(45)
      "45 seconds"

      iex> Utils.format_duration_seconds(90)
      "1m 30s"

      iex> Utils.format_duration_seconds(3665)
      "1h 1m 5s"
  """
  @spec format_duration_seconds(non_neg_integer()) :: String.t()
  def format_duration_seconds(seconds) when seconds < 60 do
    "#{seconds} seconds"
  end

  def format_duration_seconds(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining = rem(seconds, 60)
    "#{minutes}m #{remaining}s"
  end

  def format_duration_seconds(seconds) do
    hours = div(seconds, 3600)
    remaining = rem(seconds, 3600)
    minutes = div(remaining, 60)
    secs = rem(remaining, 60)
    "#{hours}h #{minutes}m #{secs}s"
  end

  @doc """
  Generates the download URL for a Hex package tarball.

  ## Examples

      iex> Utils.tarball_url("phoenix", "1.7.10")
      "https://repo.hex.pm/tarballs/phoenix-1.7.10.tar"
  """
  @spec tarball_url(String.t(), String.t()) :: String.t()
  def tarball_url(name, version) do
    encoded_name = URI.encode(name)
    "https://repo.hex.pm/tarballs/#{encoded_name}-#{version}.tar"
  end

  @doc """
  Generates the filename for a Hex package tarball.

  ## Examples

      iex> Utils.tarball_filename("phoenix", "1.7.10")
      "phoenix-1.7.10.tar"
  """
  @spec tarball_filename(String.t(), String.t()) :: String.t()
  def tarball_filename(name, version) do
    "#{name}-#{version}.tar"
  end
end
