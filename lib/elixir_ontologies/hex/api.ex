defmodule ElixirOntologies.Hex.Api do
  @moduledoc """
  Hex.pm API client for package listing and metadata retrieval.

  Provides functions to list packages, fetch individual package metadata,
  and stream through all packages with automatic pagination.

  ## Usage

      client = ElixirOntologies.Hex.HttpClient.new()

      # List a single page of packages
      {:ok, packages, rate_limit} = Api.list_packages(client, page: 1)

      # Stream all packages
      client
      |> Api.stream_all_packages()
      |> Stream.each(&IO.inspect/1)
      |> Stream.run()

      # Get a single package
      {:ok, package} = Api.get_package(client, "phoenix")
  """

  alias ElixirOntologies.Hex.HttpClient

  @hex_api_url "https://hex.pm/api"
  @hex_repo_url "https://repo.hex.pm"
  @default_page_size 100

  defmodule Package do
    @moduledoc """
    Represents a Hex.pm package with its metadata.
    """

    alias ElixirOntologies.Hex.Utils

    @type t :: %__MODULE__{
            name: String.t(),
            latest_version: String.t() | nil,
            latest_stable_version: String.t() | nil,
            releases: [map()],
            meta: map(),
            downloads: map(),
            inserted_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil
          }

    defstruct [
      :name,
      :latest_version,
      :latest_stable_version,
      :releases,
      :meta,
      :downloads,
      :inserted_at,
      :updated_at
    ]

    @doc """
    Parses a package from JSON API response.
    """
    @spec from_json(map()) :: t()
    def from_json(json) when is_map(json) do
      %__MODULE__{
        name: json["name"],
        latest_version: get_in(json, ["latest_version"]),
        latest_stable_version: get_in(json, ["latest_stable_version"]),
        releases: json["releases"] || [],
        meta: json["meta"] || %{},
        downloads: json["downloads"] || %{},
        inserted_at: Utils.parse_datetime(json["inserted_at"]),
        updated_at: Utils.parse_datetime(json["updated_at"])
      }
    end

  end

  # ===========================================================================
  # API Functions
  # ===========================================================================

  @doc """
  Lists packages from a single page.

  ## Options

    * `:page` - Page number (default: 1)
    * `:sort` - Sort order: "name", "recent_downloads", "total_downloads", "inserted_at", "updated_at" (default: "name")

  ## Returns

    * `{:ok, [%Package{}], rate_limit_info | nil}` on success
    * `{:error, reason}` on failure
  """
  @spec list_packages(Req.Request.t(), keyword()) ::
          {:ok, [Package.t()], map() | nil} | {:error, term()}
  def list_packages(client, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    sort = Keyword.get(opts, :sort, "name")

    url = "#{@hex_api_url}/packages?page=#{page}&sort=#{sort}"

    case HttpClient.get(client, url) do
      {:ok, response} ->
        packages = Enum.map(response.body, &Package.from_json/1)
        rate_limit = HttpClient.extract_rate_limit(response)
        {:ok, packages, rate_limit}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a lazy stream that fetches all packages across pages.

  The stream will automatically paginate through all packages,
  applying a delay between page fetches to respect rate limits.

  ## Options

    * `:delay_ms` - Delay between page fetches in milliseconds (default: 1000)
    * `:start_page` - Page to start from (default: 1)

  ## Returns

  A `Stream.t()` of `%Package{}` structs.

  ## Example

      client
      |> Api.stream_all_packages(delay_ms: 1000)
      |> Enum.take(100)
  """
  @spec stream_all_packages(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_all_packages(client, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 500)
    start_page = Keyword.get(opts, :start_page, 1)

    Stream.resource(
      fn -> {client, start_page, delay_ms, :continue} end,
      &do_stream_page/1,
      fn _ -> :ok end
    )
  end

  defp do_stream_page({_client, _page, _delay_ms, :halt}) do
    {:halt, nil}
  end

  defp do_stream_page({client, page, delay_ms, :continue}) do
    # Apply delay between pages (except for first page)
    if page > 1, do: Process.sleep(delay_ms)

    case list_packages(client, page: page) do
      {:ok, [], _rate_limit} ->
        # Empty page means we've reached the end
        {:halt, nil}

      {:ok, packages, rate_limit} ->
        # Check if we need additional delay due to rate limiting
        additional_delay = HttpClient.rate_limit_delay(rate_limit)
        if additional_delay > 0, do: Process.sleep(additional_delay)

        {packages, {client, page + 1, delay_ms, :continue}}

      {:error, :rate_limited} ->
        # Wait and retry the same page
        Process.sleep(delay_ms * 10)
        do_stream_page({client, page, delay_ms, :continue})

      {:error, reason} ->
        # Log error and halt the stream
        require Logger
        Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
        {:halt, nil}
    end
  end

  @doc """
  Fetches metadata for a single package.

  ## Returns

    * `{:ok, %Package{}}` on success
    * `{:error, :not_found}` if package doesn't exist
    * `{:error, reason}` on other failures
  """
  @spec get_package(Req.Request.t(), String.t()) :: {:ok, Package.t()} | {:error, term()}
  def get_package(client, name) when is_binary(name) do
    url = "#{@hex_api_url}/packages/#{URI.encode(name)}"

    case HttpClient.get(client, url) do
      {:ok, response} ->
        package = Package.from_json(response.body)
        {:ok, package}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches release metadata for a specific package version.

  Returns build tools, elixir version requirement, and other release metadata.

  ## Returns

    * `{:ok, release_meta}` on success
    * `{:error, reason}` on failure

  ## Examples

      {:ok, meta} = Api.get_release_meta(client, "phoenix", "1.7.14")
      # => %{"build_tools" => ["mix"], "elixir" => "~> 1.11", "app" => "phoenix"}
  """
  @spec get_release_meta(Req.Request.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_release_meta(client, name, version) when is_binary(name) and is_binary(version) do
    url = "#{@hex_api_url}/packages/#{URI.encode(name)}/releases/#{version}"

    case HttpClient.get(client, url) do
      {:ok, response} ->
        {:ok, response.body["meta"] || %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a package version is an Elixir package based on release metadata.

  Returns `true` if the package uses Mix as a build tool or has an Elixir version requirement.
  """
  @spec elixir_package?(Req.Request.t(), String.t(), String.t()) :: boolean()
  def elixir_package?(client, name, version) do
    case get_release_meta(client, name, version) do
      {:ok, meta} ->
        build_tools = meta["build_tools"] || []
        elixir_version = meta["elixir"]

        "mix" in build_tools or not is_nil(elixir_version)

      {:error, _} ->
        # On error, assume it might be Elixir (fail open)
        true
    end
  end

  @doc """
  Returns the tarball download URL for a package version.

  Delegates to `ElixirOntologies.Hex.Utils.tarball_url/2`.
  """
  @spec tarball_url(String.t(), String.t()) :: String.t()
  defdelegate tarball_url(name, version), to: ElixirOntologies.Hex.Utils

  # ===========================================================================
  # Version Selection
  # ===========================================================================

  @doc """
  Returns the latest stable version for a package.

  Prefers explicit `latest_stable_version` field, falls back to
  finding the first non-prerelease in releases, then falls back
  to the latest version even if it's a prerelease.
  """
  @spec latest_stable_version(Package.t()) :: String.t() | nil
  def latest_stable_version(%Package{} = package) do
    cond do
      # Prefer explicit latest_stable_version
      not is_nil(package.latest_stable_version) ->
        package.latest_stable_version

      # Find first non-prerelease in releases
      stable = find_first_stable(package.releases) ->
        stable

      # Fall back to latest_version
      not is_nil(package.latest_version) ->
        package.latest_version

      # Fall back to first release
      package.releases != [] ->
        List.first(package.releases)["version"]

      true ->
        nil
    end
  end

  defp find_first_stable(releases) do
    releases
    |> Enum.find(fn release -> not is_prerelease?(release["version"]) end)
    |> case do
      nil -> nil
      release -> release["version"]
    end
  end

  @doc """
  Checks if a version string indicates a prerelease.

  Prereleases are identified by suffixes like `-alpha`, `-beta`, `-rc`, `-dev`.

  ## Examples

      iex> ElixirOntologies.Hex.Api.is_prerelease?("1.0.0")
      false

      iex> ElixirOntologies.Hex.Api.is_prerelease?("1.0.0-alpha.1")
      true

      iex> ElixirOntologies.Hex.Api.is_prerelease?("2.0.0-rc.1")
      true
  """
  @spec is_prerelease?(String.t() | nil) :: boolean()
  def is_prerelease?(nil), do: false

  def is_prerelease?(version) when is_binary(version) do
    String.contains?(version, "-")
  end

  # ===========================================================================
  # Download Statistics
  # ===========================================================================

  @doc """
  Returns the recent download count for a package.

  Recent downloads typically represent the last 7 days.
  """
  @spec recent_downloads(Package.t()) :: non_neg_integer()
  def recent_downloads(%Package{downloads: downloads}) when is_map(downloads) do
    # Hex API uses "recent" or "week" for recent downloads
    downloads["recent"] || downloads["week"] || 0
  end

  def recent_downloads(%Package{}), do: 0

  @doc """
  Returns the total download count for a package.
  """
  @spec total_downloads(Package.t()) :: non_neg_integer()
  def total_downloads(%Package{downloads: downloads}) when is_map(downloads) do
    downloads["all"] || 0
  end

  def total_downloads(%Package{}), do: 0

  # ===========================================================================
  # Sorted Package Fetching
  # ===========================================================================

  @doc """
  Fetches all packages and returns them sorted by popularity.

  Sort order: recent downloads (desc), total downloads (desc), name (asc).

  This fetches all packages into memory before returning, which allows
  for compound sorting that the Hex API doesn't support natively.

  ## Options

    * `:delay_ms` - Delay between page fetches in milliseconds (default: 1000)
    * `:on_page` - Callback function called with page number after each fetch

  ## Returns

  A list of `%Package{}` structs sorted by popularity.

  ## Example

      packages = Api.fetch_all_packages_by_popularity(client)
  """
  @spec fetch_all_packages_by_popularity(Req.Request.t(), keyword()) :: [Package.t()]
  def fetch_all_packages_by_popularity(client, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 1000)
    on_page = Keyword.get(opts, :on_page, fn _ -> :ok end)

    # Fetch all packages using API's default sorting (faster pagination)
    packages = fetch_all_packages(client, delay_ms, on_page)

    # Sort by: recent_downloads DESC, total_downloads DESC, name ASC
    Enum.sort(packages, &popularity_comparator/2)
  end

  @doc """
  Streams all packages sorted by popularity.

  This fetches all packages first, sorts them, then streams the result.
  Use this when you need compound sorting by popularity.

  ## Options

    * `:delay_ms` - Delay between page fetches in milliseconds (default: 1000)
    * `:on_page` - Callback function called with page number after each fetch

  ## Returns

  A `Stream.t()` of `%Package{}` structs sorted by popularity.
  """
  @spec stream_all_packages_by_popularity(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_all_packages_by_popularity(client, opts \\ []) do
    # Fetch and sort all packages, then convert to stream
    client
    |> fetch_all_packages_by_popularity(opts)
    |> Stream.map(& &1)
  end

  defp fetch_all_packages(client, delay_ms, on_page, page \\ 1, acc \\ []) do
    on_page.(page)

    if page > 1, do: Process.sleep(delay_ms)

    case list_packages(client, page: page) do
      {:ok, [], _rate_limit} ->
        # Empty page means we've reached the end
        Enum.reverse(acc)

      {:ok, packages, rate_limit} ->
        # Check if we need additional delay due to rate limiting
        additional_delay = HttpClient.rate_limit_delay(rate_limit)
        if additional_delay > 0, do: Process.sleep(additional_delay)

        fetch_all_packages(client, delay_ms, on_page, page + 1, Enum.reverse(packages) ++ acc)

      {:error, :rate_limited} ->
        # Wait and retry the same page
        Process.sleep(delay_ms * 10)
        fetch_all_packages(client, delay_ms, on_page, page, acc)

      {:error, reason} ->
        require Logger
        Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
        Enum.reverse(acc)
    end
  end

  @doc """
  Comparator function for sorting packages by popularity.

  Sort order: recent downloads (desc), total downloads (desc), name (asc).
  Returns true if `a` should come before `b`.
  """
  @spec popularity_comparator(Package.t(), Package.t()) :: boolean()
  def popularity_comparator(%Package{} = a, %Package{} = b) do
    a_recent = recent_downloads(a)
    b_recent = recent_downloads(b)

    cond do
      a_recent > b_recent -> true
      a_recent < b_recent -> false
      true ->
        # Recent downloads equal, compare total downloads
        a_total = total_downloads(a)
        b_total = total_downloads(b)

        cond do
          a_total > b_total -> true
          a_total < b_total -> false
          true ->
            # Total downloads also equal, compare by name (ascending)
            a.name <= b.name
        end
    end
  end

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns the Hex.pm API base URL.
  """
  @spec api_url() :: String.t()
  def api_url, do: @hex_api_url

  @doc """
  Returns the Hex.pm repository URL.
  """
  @spec repo_url() :: String.t()
  def repo_url, do: @hex_repo_url

  @doc """
  Returns the default page size for package listings.
  """
  @spec default_page_size() :: pos_integer()
  def default_page_size, do: @default_page_size
end
