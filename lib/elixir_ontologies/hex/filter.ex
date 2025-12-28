defmodule ElixirOntologies.Hex.Filter do
  @moduledoc """
  Package filtering logic to identify Elixir packages.

  Provides heuristics to detect whether a Hex package is likely an Elixir
  package vs an Erlang-only package, using both metadata analysis and
  source file inspection.

  ## Filtering Strategy

  1. **Metadata-based filtering**: Quick checks using package metadata
     (links, licenses, naming conventions) to identify likely Elixir packages.

  2. **Source-based filtering**: Definitive check by inspecting extracted
     source files for `.ex` files or `mix.exs`.

  ## Usage

      # Filter a stream of packages
      packages
      |> Filter.filter_likely_elixir()
      |> Enum.each(&process/1)

      # Check extracted source directory
      Filter.has_elixir_source?("/tmp/extracted/phoenix-1.7.0")
  """

  alias ElixirOntologies.Hex.Api.Package

  @elixir_indicators %{
    # Common Elixir project licenses
    licenses: ["MIT", "Apache-2.0", "Apache 2.0", "BSD", "MPL-2.0"],
    # GitHub paths that suggest Elixir
    github_patterns: ["/elixir", "elixir-", "-ex", "_ex"],
    # Package name patterns common in Elixir
    name_patterns: [~r/^ex_/, ~r/_ex$/, ~r/^phoenix/, ~r/^ecto/, ~r/^plug/, ~r/^nerves/, ~r/^absinthe/]
  }

  @erlang_indicators %{
    # Package name patterns common in Erlang
    name_patterns: [
      ~r/^erl_/,
      ~r/_erl$/,
      ~r/^rebar/,
      ~r/^erlang_/,
      ~r/_nif$/,
      ~r/^gen_/,
      ~r/^lager/,
      ~r/^erlfmt/
    ],
    # Known Erlang-only packages (popular dependencies without Elixir code)
    known_erlang: [
      # HTTP/Network
      "cowboy", "cowlib", "ranch", "gun", "hackney", "ssl_verify_fun",
      "idna", "unicode_util_compat", "mimerl", "certifi", "parse_trans",
      # JSON
      "jsx", "jiffy", "jsone", "jsonx",
      # Testing
      "meck", "proper", "eunit_formatters",
      # Compression
      "ezlib", "zstd",
      # Database drivers
      "epgsql", "eredis", "mysql", "emysql", "mongodb",
      # Parsing
      "leex", "yecc", "neotoma", "abnf",
      # Crypto
      "bcrypt", "pbkdf2", "fast_tls", "p1_utils",
      # Utilities
      "gproc", "poolboy", "worker_pool", "jobs", "recon", "observer_cli",
      "bear", "folsom", "exometer_core", "lager", "goldrush",
      # Misc
      "cf", "edown", "getopt", "uuid", "base64url", "quickrand",
      "erlware_commons", "providers", "relx", "bbmustache",
      # Format/Protocol
      "gpb", "protobuffs", "msgpack", "bert", "erlfmt",
      # NIF wrappers
      "asn1", "crypto", "public_key", "ssl", "inets", "xmerl",
      # OTP apps
      "sasl", "stdlib", "kernel", "compiler"
    ]
  }

  # ===========================================================================
  # Metadata-Based Filtering
  # ===========================================================================

  @doc """
  Checks if a package is likely an Elixir package based on metadata.

  Returns:
    * `true` if strong Elixir indicators are present
    * `false` if strong Erlang indicators are present
    * `:unknown` if no clear indicators (needs source inspection)

  ## Examples

      iex> package = %Package{name: "phoenix", meta: %{"links" => %{"GitHub" => "https://github.com/phoenixframework/phoenix"}}}
      iex> Filter.likely_elixir_package?(package)
      true
  """
  @spec likely_elixir_package?(Package.t()) :: boolean() | :unknown
  def likely_elixir_package?(%Package{} = package) do
    cond do
      has_elixir_indicators?(package) -> true
      has_erlang_indicators?(package) -> false
      true -> :unknown
    end
  end

  defp has_elixir_indicators?(%Package{name: name, meta: meta}) do
    has_elixir_name?(name) or
      has_elixir_github_link?(meta) or
      has_elixir_description?(meta)
  end

  defp has_elixir_name?(name) when is_binary(name) do
    Enum.any?(@elixir_indicators.name_patterns, &Regex.match?(&1, name))
  end

  defp has_elixir_name?(_), do: false

  defp has_elixir_github_link?(%{"links" => links}) when is_map(links) do
    links
    |> Map.values()
    |> Enum.any?(fn url ->
      is_binary(url) and
        Enum.any?(@elixir_indicators.github_patterns, &String.contains?(url, &1))
    end)
  end

  defp has_elixir_github_link?(_), do: false

  defp has_elixir_description?(%{"description" => desc}) when is_binary(desc) do
    desc_lower = String.downcase(desc)
    String.contains?(desc_lower, "elixir") and not String.contains?(desc_lower, "erlang only")
  end

  defp has_elixir_description?(_), do: false

  defp has_erlang_indicators?(%Package{name: name, meta: meta}) do
    has_erlang_name?(name) or is_known_erlang?(name) or has_erlang_only_description?(meta)
  end

  defp has_erlang_only_description?(%{"description" => desc}) when is_binary(desc) do
    desc_lower = String.downcase(desc)
    # Erlang-only if mentions "erlang" but not "elixir"
    (String.contains?(desc_lower, "erlang") and not String.contains?(desc_lower, "elixir")) or
      String.contains?(desc_lower, "erlang only") or
      String.contains?(desc_lower, "erlang library") or
      String.contains?(desc_lower, "pure erlang") or
      String.contains?(desc_lower, "otp application")
  end

  defp has_erlang_only_description?(_), do: false

  defp has_erlang_name?(name) when is_binary(name) do
    Enum.any?(@erlang_indicators.name_patterns, &Regex.match?(&1, name))
  end

  defp has_erlang_name?(_), do: false

  defp is_known_erlang?(name) when is_binary(name) do
    name in @erlang_indicators.known_erlang
  end

  defp is_known_erlang?(_), do: false

  # ===========================================================================
  # Source-Based Filtering
  # ===========================================================================

  @doc """
  Checks if an extracted package directory contains Elixir source files.

  Returns `true` if any `.ex` files are found in the package.

  ## Examples

      iex> Filter.has_elixir_source?("/tmp/extracted/phoenix-1.7.0")
      true
  """
  @spec has_elixir_source?(Path.t()) :: boolean()
  def has_elixir_source?(path) when is_binary(path) do
    path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.any?()
  end

  @doc """
  Checks if an extracted package directory contains a mix.exs file.

  Returns `true` if `mix.exs` exists in the package root.

  ## Examples

      iex> Filter.has_mix_project?("/tmp/extracted/phoenix-1.7.0")
      true
  """
  @spec has_mix_project?(Path.t()) :: boolean()
  def has_mix_project?(path) when is_binary(path) do
    path
    |> Path.join("mix.exs")
    |> File.exists?()
  end

  @doc """
  Checks if an extracted package is Erlang-only (no Elixir source).

  Returns `true` if the package has `.erl` files but no `.ex` files.
  """
  @spec erlang_only?(Path.t()) :: boolean()
  def erlang_only?(path) when is_binary(path) do
    has_erlang = has_erlang_source?(path)
    has_elixir = has_elixir_source?(path)

    has_erlang and not has_elixir
  end

  @doc """
  Checks if an extracted package directory contains Erlang source files.
  """
  @spec has_erlang_source?(Path.t()) :: boolean()
  def has_erlang_source?(path) when is_binary(path) do
    path
    |> Path.join("**/*.erl")
    |> Path.wildcard()
    |> Enum.any?()
  end

  # ===========================================================================
  # Stream Filtering
  # ===========================================================================

  @doc """
  Filters a stream of packages to include likely Elixir packages.

  Packages with clear Erlang indicators are rejected.
  Packages with Elixir indicators or unknown status are passed through.
  Unknown packages should be verified via source inspection after download.

  ## Examples

      packages
      |> Filter.filter_likely_elixir()
      |> Stream.each(&download_and_analyze/1)
      |> Stream.run()
  """
  @spec filter_likely_elixir(Enumerable.t()) :: Enumerable.t()
  def filter_likely_elixir(packages) do
    Stream.filter(packages, fn package ->
      case likely_elixir_package?(package) do
        true -> true
        :unknown -> true
        false -> false
      end
    end)
  end

  @doc """
  Returns the known Erlang package names that should be skipped.
  """
  @spec known_erlang_packages() :: [String.t()]
  def known_erlang_packages, do: @erlang_indicators.known_erlang
end
