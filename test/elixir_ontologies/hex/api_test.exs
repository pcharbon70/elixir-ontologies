defmodule ElixirOntologies.Hex.ApiTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Api
  alias ElixirOntologies.Hex.Api.Package
  alias ElixirOntologies.Hex.HttpClient

  # ===========================================================================
  # Package Struct Tests
  # ===========================================================================

  describe "Package.from_json/1" do
    test "parses complete package JSON" do
      json = %{
        "name" => "phoenix",
        "latest_version" => "1.7.10",
        "latest_stable_version" => "1.7.10",
        "releases" => [
          %{"version" => "1.7.10"},
          %{"version" => "1.7.9"}
        ],
        "meta" => %{
          "description" => "A framework",
          "links" => %{"GitHub" => "https://github.com/phoenixframework/phoenix"}
        },
        "downloads" => %{"all" => 1_000_000, "week" => 50_000},
        "inserted_at" => "2014-08-13T20:30:25.000Z",
        "updated_at" => "2024-01-15T10:30:00.000Z"
      }

      package = Package.from_json(json)

      assert package.name == "phoenix"
      assert package.latest_version == "1.7.10"
      assert package.latest_stable_version == "1.7.10"
      assert length(package.releases) == 2
      assert package.meta["description"] == "A framework"
      assert package.downloads["all"] == 1_000_000
      assert %DateTime{} = package.inserted_at
      assert %DateTime{} = package.updated_at
    end

    test "handles missing optional fields" do
      json = %{
        "name" => "minimal"
      }

      package = Package.from_json(json)

      assert package.name == "minimal"
      assert package.latest_version == nil
      assert package.releases == []
      assert package.meta == %{}
      assert package.downloads == %{}
      assert package.inserted_at == nil
    end

    test "handles invalid datetime" do
      json = %{
        "name" => "test",
        "inserted_at" => "not-a-date"
      }

      package = Package.from_json(json)

      assert package.inserted_at == nil
    end
  end

  # ===========================================================================
  # Version Selection Tests
  # ===========================================================================

  describe "latest_stable_version/1" do
    test "returns latest_stable_version when present" do
      package = %Package{
        name: "test",
        latest_stable_version: "1.0.0",
        latest_version: "2.0.0-rc.1",
        releases: []
      }

      assert Api.latest_stable_version(package) == "1.0.0"
    end

    test "finds first non-prerelease when latest_stable_version is nil" do
      package = %Package{
        name: "test",
        latest_stable_version: nil,
        latest_version: "2.0.0-rc.1",
        releases: [
          %{"version" => "2.0.0-rc.1"},
          %{"version" => "1.5.0"},
          %{"version" => "1.4.0"}
        ]
      }

      assert Api.latest_stable_version(package) == "1.5.0"
    end

    test "falls back to latest_version when all are prereleases" do
      package = %Package{
        name: "test",
        latest_stable_version: nil,
        latest_version: "1.0.0-alpha.2",
        releases: [
          %{"version" => "1.0.0-alpha.2"},
          %{"version" => "1.0.0-alpha.1"}
        ]
      }

      assert Api.latest_stable_version(package) == "1.0.0-alpha.2"
    end

    test "falls back to first release when no version info" do
      package = %Package{
        name: "test",
        latest_stable_version: nil,
        latest_version: nil,
        releases: [%{"version" => "0.1.0"}]
      }

      assert Api.latest_stable_version(package) == "0.1.0"
    end

    test "returns nil for empty package" do
      package = %Package{
        name: "test",
        latest_stable_version: nil,
        latest_version: nil,
        releases: []
      }

      assert Api.latest_stable_version(package) == nil
    end
  end

  describe "is_prerelease?/1" do
    test "returns false for stable versions" do
      refute Api.is_prerelease?("1.0.0")
      refute Api.is_prerelease?("0.1.0")
      refute Api.is_prerelease?("10.20.30")
    end

    test "returns true for prerelease versions" do
      assert Api.is_prerelease?("1.0.0-alpha")
      assert Api.is_prerelease?("1.0.0-alpha.1")
      assert Api.is_prerelease?("2.0.0-beta")
      assert Api.is_prerelease?("2.0.0-beta.2")
      assert Api.is_prerelease?("3.0.0-rc.1")
      assert Api.is_prerelease?("1.0.0-dev")
    end

    test "returns false for nil" do
      refute Api.is_prerelease?(nil)
    end
  end

  # ===========================================================================
  # URL Generation Tests
  # ===========================================================================

  describe "tarball_url/2" do
    test "generates correct tarball URL" do
      url = Api.tarball_url("phoenix", "1.7.10")

      assert url == "https://repo.hex.pm/tarballs/phoenix-1.7.10.tar"
    end
  end

  describe "utility functions" do
    test "api_url returns API base URL" do
      assert Api.api_url() == "https://hex.pm/api"
    end

    test "repo_url returns repository URL" do
      assert Api.repo_url() == "https://repo.hex.pm"
    end

    test "default_page_size returns 100" do
      assert Api.default_page_size() == 100
    end
  end

  # ===========================================================================
  # API Request Tests (with Bypass)
  # ===========================================================================

  describe "list_packages/2" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
    end

    test "returns page of packages", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "GET", "/api/packages", fn conn ->
        assert conn.query_string =~ "page=1"

        body =
          Jason.encode!([
            %{"name" => "phoenix", "latest_version" => "1.7.10"},
            %{"name" => "ecto", "latest_version" => "3.11.0"}
          ])

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      client = HttpClient.new() |> Req.merge(base_url: "#{base_url}/api")
      # Override the API URL for testing
      {:ok, packages, _rate_limit} = do_list_packages(client, bypass, page: 1)

      assert length(packages) == 2
      assert Enum.at(packages, 0).name == "phoenix"
      assert Enum.at(packages, 1).name == "ecto"
    end

    test "returns rate limit info from headers", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/api/packages", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-limit", "100")
        |> Plug.Conn.put_resp_header("x-ratelimit-remaining", "95")
        |> Plug.Conn.put_resp_header("x-ratelimit-reset", "1704067200")
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "[]")
      end)

      {:ok, _packages, rate_limit} = do_list_packages(HttpClient.new(), bypass, [])

      assert rate_limit.limit == 100
      assert rate_limit.remaining == 95
    end

    test "returns error for 404", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/api/packages", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      result = do_list_packages(HttpClient.new(), bypass, [])

      assert result == {:error, :not_found}
    end

    # Helper to make requests through bypass
    defp do_list_packages(client, bypass, opts) do
      page = Keyword.get(opts, :page, 1)
      sort = Keyword.get(opts, :sort, "name")
      url = "http://localhost:#{bypass.port}/api/packages?page=#{page}&sort=#{sort}"

      case HttpClient.get(client, url) do
        {:ok, response} ->
          packages = Enum.map(response.body, &Package.from_json/1)
          rate_limit = HttpClient.extract_rate_limit(response)
          {:ok, packages, rate_limit}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  describe "get_package/2" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
    end

    test "returns package metadata", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/api/packages/phoenix", fn conn ->
        body =
          Jason.encode!(%{
            "name" => "phoenix",
            "latest_version" => "1.7.10",
            "releases" => [%{"version" => "1.7.10"}]
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      {:ok, package} = do_get_package(HttpClient.new(), bypass, "phoenix")

      assert package.name == "phoenix"
      assert package.latest_version == "1.7.10"
    end

    test "returns error for missing package", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/api/packages/nonexistent", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      result = do_get_package(HttpClient.new(), bypass, "nonexistent")

      assert result == {:error, :not_found}
    end

    defp do_get_package(client, bypass, name) do
      url = "http://localhost:#{bypass.port}/api/packages/#{name}"

      case HttpClient.get(client, url) do
        {:ok, response} ->
          package = Package.from_json(response.body)
          {:ok, package}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ===========================================================================
  # Stream Tests
  # ===========================================================================

  describe "stream_all_packages/2" do
    test "creates a stream" do
      client = HttpClient.new()
      stream = Api.stream_all_packages(client, delay_ms: 0)

      assert is_function(stream, 2)
    end

    # Note: Full stream integration tests would require mocking multiple pages
    # and are better suited for integration tests
  end

  # ===========================================================================
  # Download Statistics Tests
  # ===========================================================================

  describe "recent_downloads/1" do
    test "returns recent downloads from downloads map" do
      package = %Package{
        name: "test",
        downloads: %{"recent" => 5000, "all" => 100_000}
      }

      assert Api.recent_downloads(package) == 5000
    end

    test "falls back to week field" do
      package = %Package{
        name: "test",
        downloads: %{"week" => 3000, "all" => 50_000}
      }

      assert Api.recent_downloads(package) == 3000
    end

    test "returns 0 for missing downloads" do
      package = %Package{name: "test", downloads: %{}}

      assert Api.recent_downloads(package) == 0
    end

    test "returns 0 for nil downloads" do
      package = %Package{name: "test", downloads: nil}

      assert Api.recent_downloads(package) == 0
    end
  end

  describe "total_downloads/1" do
    test "returns total downloads from all field" do
      package = %Package{
        name: "test",
        downloads: %{"all" => 1_000_000}
      }

      assert Api.total_downloads(package) == 1_000_000
    end

    test "returns 0 for missing all field" do
      package = %Package{name: "test", downloads: %{"recent" => 100}}

      assert Api.total_downloads(package) == 0
    end

    test "returns 0 for nil downloads" do
      package = %Package{name: "test", downloads: nil}

      assert Api.total_downloads(package) == 0
    end
  end

  # ===========================================================================
  # Popularity Comparator Tests
  # ===========================================================================

  describe "popularity_comparator/2" do
    test "sorts by recent downloads descending" do
      a = %Package{name: "popular", downloads: %{"recent" => 10_000, "all" => 100_000}}
      b = %Package{name: "less_popular", downloads: %{"recent" => 1_000, "all" => 100_000}}

      assert Api.popularity_comparator(a, b) == true
      assert Api.popularity_comparator(b, a) == false
    end

    test "uses total downloads as secondary sort" do
      a = %Package{name: "more_total", downloads: %{"recent" => 1_000, "all" => 500_000}}
      b = %Package{name: "less_total", downloads: %{"recent" => 1_000, "all" => 100_000}}

      assert Api.popularity_comparator(a, b) == true
      assert Api.popularity_comparator(b, a) == false
    end

    test "uses name as tertiary sort (ascending)" do
      a = %Package{name: "aaa", downloads: %{"recent" => 1_000, "all" => 100_000}}
      b = %Package{name: "zzz", downloads: %{"recent" => 1_000, "all" => 100_000}}

      assert Api.popularity_comparator(a, b) == true
      assert Api.popularity_comparator(b, a) == false
    end

    test "handles equal packages" do
      a = %Package{name: "same", downloads: %{"recent" => 1_000, "all" => 100_000}}
      b = %Package{name: "same", downloads: %{"recent" => 1_000, "all" => 100_000}}

      # Equal items should return true (stable sort)
      assert Api.popularity_comparator(a, b) == true
    end

    test "correctly sorts a list of packages" do
      packages = [
        %Package{name: "low_recent", downloads: %{"recent" => 100, "all" => 1_000_000}},
        %Package{name: "high_recent", downloads: %{"recent" => 50_000, "all" => 500_000}},
        %Package{name: "mid_recent", downloads: %{"recent" => 5_000, "all" => 200_000}}
      ]

      sorted = Enum.sort(packages, &Api.popularity_comparator/2)
      names = Enum.map(sorted, & &1.name)

      assert names == ["high_recent", "mid_recent", "low_recent"]
    end

    test "breaks ties correctly with total downloads" do
      packages = [
        %Package{name: "low_total", downloads: %{"recent" => 1_000, "all" => 10_000}},
        %Package{name: "high_total", downloads: %{"recent" => 1_000, "all" => 1_000_000}},
        %Package{name: "mid_total", downloads: %{"recent" => 1_000, "all" => 100_000}}
      ]

      sorted = Enum.sort(packages, &Api.popularity_comparator/2)
      names = Enum.map(sorted, & &1.name)

      assert names == ["high_total", "mid_total", "low_total"]
    end

    test "breaks ties correctly with name" do
      packages = [
        %Package{name: "charlie", downloads: %{"recent" => 1_000, "all" => 100_000}},
        %Package{name: "alpha", downloads: %{"recent" => 1_000, "all" => 100_000}},
        %Package{name: "bravo", downloads: %{"recent" => 1_000, "all" => 100_000}}
      ]

      sorted = Enum.sort(packages, &Api.popularity_comparator/2)
      names = Enum.map(sorted, & &1.name)

      assert names == ["alpha", "bravo", "charlie"]
    end
  end
end
