defmodule ElixirOntologies.Hex.HttpClientTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.HttpClient

  # ===========================================================================
  # Client Creation Tests
  # ===========================================================================

  describe "new/0 and new/1" do
    test "creates client with default options" do
      client = HttpClient.new()

      assert %Req.Request{} = client
    end

    test "creates client with custom timeout" do
      client = HttpClient.new(timeout: 60_000)

      assert %Req.Request{} = client
      assert client.options.receive_timeout == 60_000
    end

    test "creates client with custom retry count" do
      client = HttpClient.new(retries: 5)

      assert %Req.Request{} = client
      assert client.options.max_retries == 5
    end

    test "User-Agent header is properly formatted" do
      user_agent = HttpClient.user_agent()

      assert user_agent =~ ~r/^ElixirOntologies\/[\d.]+/
      assert user_agent =~ ~r/\(Elixir\/[\d.]+\)$/
    end
  end

  # ===========================================================================
  # Rate Limit Header Parsing Tests
  # ===========================================================================

  describe "extract_rate_limit/1" do
    test "parses rate limit headers correctly" do
      response = %Req.Response{
        status: 200,
        headers: %{
          "x-ratelimit-limit" => ["100"],
          "x-ratelimit-remaining" => ["50"],
          "x-ratelimit-reset" => ["1704067200"]
        },
        body: ""
      }

      result = HttpClient.extract_rate_limit(response)

      assert result == %{limit: 100, remaining: 50, reset: 1_704_067_200}
    end

    test "returns nil when headers are missing" do
      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["application/json"]},
        body: ""
      }

      assert HttpClient.extract_rate_limit(response) == nil
    end

    test "returns nil when headers have non-integer values" do
      response = %Req.Response{
        status: 200,
        headers: %{
          "x-ratelimit-limit" => ["not-a-number"],
          "x-ratelimit-remaining" => ["50"],
          "x-ratelimit-reset" => ["1704067200"]
        },
        body: ""
      }

      assert HttpClient.extract_rate_limit(response) == nil
    end

    test "returns nil when only some headers present" do
      response = %Req.Response{
        status: 200,
        headers: %{
          "x-ratelimit-limit" => ["100"]
        },
        body: ""
      }

      assert HttpClient.extract_rate_limit(response) == nil
    end
  end

  # ===========================================================================
  # Rate Limit Delay Calculation Tests
  # ===========================================================================

  describe "rate_limit_delay/1" do
    test "returns 0 when remaining > 10% of limit" do
      rate_limit = %{
        limit: 100,
        remaining: 50,
        reset: System.system_time(:second) + 60
      }

      assert HttpClient.rate_limit_delay(rate_limit) == 0
    end

    test "returns 0 when exactly at 10% threshold" do
      rate_limit = %{
        limit: 100,
        remaining: 11,
        reset: System.system_time(:second) + 60
      }

      assert HttpClient.rate_limit_delay(rate_limit) == 0
    end

    test "returns delay when below 10% threshold" do
      rate_limit = %{
        limit: 100,
        remaining: 5,
        reset: System.system_time(:second) + 60
      }

      delay = HttpClient.rate_limit_delay(rate_limit)

      # Should return a positive delay
      assert delay > 0
      # Should be reasonable (not more than time until reset)
      assert delay <= 60_000
    end

    test "returns 0 for nil rate limit" do
      assert HttpClient.rate_limit_delay(nil) == 0
    end

    test "handles remaining at 0" do
      rate_limit = %{
        limit: 100,
        remaining: 0,
        reset: System.system_time(:second) + 60
      }

      delay = HttpClient.rate_limit_delay(rate_limit)

      # Should return minimum delay
      assert delay >= 100
    end

    test "handles past reset time" do
      rate_limit = %{
        limit: 100,
        remaining: 5,
        reset: System.system_time(:second) - 10
      }

      delay = HttpClient.rate_limit_delay(rate_limit)

      # Should still return reasonable delay
      assert delay >= 100
    end
  end

  # ===========================================================================
  # Utility Function Tests
  # ===========================================================================

  describe "rate_limit_headers/0" do
    test "returns expected header names" do
      headers = HttpClient.rate_limit_headers()

      assert "x-ratelimit-limit" in headers
      assert "x-ratelimit-remaining" in headers
      assert "x-ratelimit-reset" in headers
    end
  end

  # ===========================================================================
  # GET Request Tests (with Bypass)
  # ===========================================================================

  describe "get/2 and get/3" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
    end

    test "returns {:ok, response} for 200 status", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "GET", "/test", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"status": "ok"}))
      end)

      client = HttpClient.new()
      {:ok, response} = HttpClient.get(client, "#{base_url}/test")

      assert response.status == 200
    end

    test "returns {:error, :not_found} for 404 status", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "GET", "/missing", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      client = HttpClient.new()
      result = HttpClient.get(client, "#{base_url}/missing")

      assert result == {:error, :not_found}
    end

    test "returns {:error, :rate_limited} for 429 status", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "GET", "/limited", fn conn ->
        Plug.Conn.resp(conn, 429, "Rate Limited")
      end)

      client = HttpClient.new()
      result = HttpClient.get(client, "#{base_url}/limited")

      assert result == {:error, :rate_limited}
    end

    test "returns {:error, {:http_error, status}} for other errors", %{
      bypass: bypass,
      base_url: base_url
    } do
      Bypass.expect(bypass, "GET", "/error", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      client = HttpClient.new(retries: 0)
      result = HttpClient.get(client, "#{base_url}/error")

      assert result == {:error, {:http_error, 500}}
    end

    test "passes custom headers", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "GET", "/headers", fn conn ->
        case Plug.Conn.get_req_header(conn, "x-custom") do
          ["test-value"] ->
            Plug.Conn.resp(conn, 200, "OK")

          _ ->
            Plug.Conn.resp(conn, 400, "Missing header")
        end
      end)

      client = HttpClient.new()
      {:ok, response} = HttpClient.get(client, "#{base_url}/headers", headers: [{"x-custom", "test-value"}])

      assert response.status == 200
    end

    test "handles connection failure", %{bypass: bypass, base_url: base_url} do
      Bypass.down(bypass)

      client = HttpClient.new(retries: 0)
      result = HttpClient.get(client, "#{base_url}/fail")

      assert {:error, _reason} = result
    end
  end

  # ===========================================================================
  # Download Tests (with Bypass)
  # ===========================================================================

  describe "download/3 and download/4" do
    setup do
      bypass = Bypass.open()
      tmp_dir = System.tmp_dir!()
      tmp_file = Path.join(tmp_dir, "test_download_#{:rand.uniform(100_000)}.bin")

      on_exit(fn ->
        File.rm(tmp_file)
      end)

      {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}", tmp_file: tmp_file}
    end

    test "downloads file successfully", %{bypass: bypass, base_url: base_url, tmp_file: tmp_file} do
      content = "test file content"

      Bypass.expect(bypass, "GET", "/file.txt", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.resp(200, content)
      end)

      client = HttpClient.new()
      result = HttpClient.download(client, "#{base_url}/file.txt", tmp_file)

      assert {:ok, ^tmp_file} = result
      assert File.exists?(tmp_file)
      assert File.read!(tmp_file) == content
    end

    test "returns error for 404 response", %{bypass: bypass, base_url: base_url, tmp_file: tmp_file} do
      Bypass.expect(bypass, "GET", "/missing.txt", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      client = HttpClient.new()
      result = HttpClient.download(client, "#{base_url}/missing.txt", tmp_file)

      assert {:error, :not_found} = result
      refute File.exists?(tmp_file)
    end

    test "returns error for server errors", %{bypass: bypass, base_url: base_url, tmp_file: tmp_file} do
      Bypass.expect(bypass, "GET", "/error.txt", fn conn ->
        Plug.Conn.resp(conn, 500, "Error")
      end)

      client = HttpClient.new(retries: 0)
      result = HttpClient.download(client, "#{base_url}/error.txt", tmp_file)

      assert {:error, {:http_error, 500}} = result
    end

    test "creates parent directories", %{bypass: bypass, base_url: base_url} do
      content = "nested file"
      tmp_dir = System.tmp_dir!()
      nested_path = Path.join([tmp_dir, "test_nested_#{:rand.uniform(100_000)}", "subdir", "file.txt"])

      on_exit(fn ->
        File.rm_rf!(Path.dirname(Path.dirname(nested_path)))
      end)

      Bypass.expect(bypass, "GET", "/nested.txt", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      client = HttpClient.new()
      result = HttpClient.download(client, "#{base_url}/nested.txt", nested_path)

      assert {:ok, ^nested_path} = result
      assert File.exists?(nested_path)
      assert File.read!(nested_path) == content
    end
  end
end
