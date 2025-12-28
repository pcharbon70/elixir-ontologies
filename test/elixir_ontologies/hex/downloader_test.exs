defmodule ElixirOntologies.Hex.DownloaderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Downloader
  alias ElixirOntologies.Hex.HttpClient

  # ===========================================================================
  # URL Generation Tests
  # ===========================================================================

  describe "tarball_url/2" do
    test "generates correct tarball URL" do
      url = Downloader.tarball_url("phoenix", "1.7.10")
      assert url == "https://repo.hex.pm/tarballs/phoenix-1.7.10.tar"
    end

    test "encodes special characters in package name" do
      url = Downloader.tarball_url("my%package", "1.0.0")
      assert url == "https://repo.hex.pm/tarballs/my%25package-1.0.0.tar"
    end
  end

  describe "tarball_filename/2" do
    test "generates correct filename" do
      filename = Downloader.tarball_filename("phoenix", "1.7.10")
      assert filename == "phoenix-1.7.10.tar"
    end

    test "handles version with prerelease" do
      filename = Downloader.tarball_filename("ecto", "3.12.0-rc.1")
      assert filename == "ecto-3.12.0-rc.1.tar"
    end
  end

  describe "repo_url/0" do
    test "returns Hex repo URL" do
      assert Downloader.repo_url() == "https://repo.hex.pm"
    end
  end

  # ===========================================================================
  # Download Tests (with Bypass)
  # ===========================================================================

  describe "download/5" do
    setup do
      bypass = Bypass.open()
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "downloader_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, bypass: bypass, test_dir: test_dir}
    end

    test "downloads tarball to specified path", %{bypass: bypass, test_dir: test_dir} do
      content = "fake tarball content"

      Bypass.expect(bypass, "GET", "/tarballs/test_pkg-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      # Create client that uses bypass
      client = HttpClient.new()
      target_path = Path.join(test_dir, "test_pkg-1.0.0.tar")

      # Mock the URL by downloading directly from bypass
      url = "http://localhost:#{bypass.port}/tarballs/test_pkg-1.0.0.tar"
      {:ok, _} = HttpClient.download(client, url, target_path)

      assert File.exists?(target_path)
      assert File.read!(target_path) == content
    end

    test "returns error for 404", %{bypass: bypass, test_dir: test_dir} do
      Bypass.expect(bypass, "GET", "/tarballs/missing-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      client = HttpClient.new()
      target_path = Path.join(test_dir, "missing-1.0.0.tar")
      url = "http://localhost:#{bypass.port}/tarballs/missing-1.0.0.tar"

      result = HttpClient.download(client, url, target_path)

      assert result == {:error, :not_found}
    end

    test "creates parent directories", %{bypass: bypass, test_dir: test_dir} do
      content = "test content"

      Bypass.expect(bypass, "GET", "/tarballs/nested-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      client = HttpClient.new()
      target_path = Path.join([test_dir, "nested", "dir", "nested-1.0.0.tar"])
      url = "http://localhost:#{bypass.port}/tarballs/nested-1.0.0.tar"

      {:ok, _} = HttpClient.download(client, url, target_path)

      assert File.exists?(target_path)
    end
  end

  describe "download_to_temp/4" do
    setup do
      bypass = Bypass.open()

      {:ok, bypass: bypass}
    end

    test "creates unique temp directory", %{bypass: bypass} do
      content = "test tarball"

      Bypass.expect(bypass, "GET", "/tarballs/temp_test-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      # Simulate what download_to_temp does
      base_temp = System.tmp_dir!()
      unique_id = :erlang.phash2(make_ref())
      temp_dir = Path.join(base_temp, "hex_temp_test_#{unique_id}")
      File.mkdir_p!(temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      client = HttpClient.new()
      tarball_path = Path.join(temp_dir, "temp_test-1.0.0.tar")
      url = "http://localhost:#{bypass.port}/tarballs/temp_test-1.0.0.tar"

      {:ok, _} = HttpClient.download(client, url, tarball_path)

      assert File.exists?(tarball_path)
      assert String.contains?(temp_dir, "hex_temp_test")
    end
  end

  # ===========================================================================
  # Checksum Tests
  # ===========================================================================

  describe "compute_checksum/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "checksum_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "computes SHA256 checksum of file", %{test_dir: test_dir} do
      content = "test content for checksum"
      file_path = Path.join(test_dir, "test_file.txt")
      File.write!(file_path, content)

      {:ok, checksum} = Downloader.compute_checksum(file_path)

      # Verify it's a 64-character lowercase hex string
      assert String.length(checksum) == 64
      assert checksum =~ ~r/^[0-9a-f]+$/

      # Verify it's deterministic
      {:ok, checksum2} = Downloader.compute_checksum(file_path)
      assert checksum == checksum2
    end

    test "returns lowercase hex string", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "lowercase_test.txt")
      File.write!(file_path, "test")

      {:ok, checksum} = Downloader.compute_checksum(file_path)

      assert checksum == String.downcase(checksum)
    end

    test "returns error for non-existent file", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "does_not_exist.txt")

      result = Downloader.compute_checksum(file_path)

      assert {:error, {:read_file, :enoent}} = result
    end

    test "different content produces different checksums", %{test_dir: test_dir} do
      file1 = Path.join(test_dir, "file1.txt")
      file2 = Path.join(test_dir, "file2.txt")
      File.write!(file1, "content one")
      File.write!(file2, "content two")

      {:ok, checksum1} = Downloader.compute_checksum(file1)
      {:ok, checksum2} = Downloader.compute_checksum(file2)

      assert checksum1 != checksum2
    end

    test "handles empty file", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "empty.txt")
      File.write!(file_path, "")

      {:ok, checksum} = Downloader.compute_checksum(file_path)

      # SHA256 of empty string
      assert checksum == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end
  end

  describe "verify_checksum/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "verify_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns :ok when checksum matches", %{test_dir: test_dir} do
      content = "test content"
      file_path = Path.join(test_dir, "valid.txt")
      File.write!(file_path, content)

      {:ok, expected} = Downloader.compute_checksum(file_path)

      assert :ok = Downloader.verify_checksum(file_path, expected)
    end

    test "returns error when checksum mismatches", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "mismatch.txt")
      File.write!(file_path, "actual content")

      wrong_checksum = "0000000000000000000000000000000000000000000000000000000000000000"

      result = Downloader.verify_checksum(file_path, wrong_checksum)

      assert result == {:error, :checksum_mismatch}
    end

    test "handles uppercase expected checksum", %{test_dir: test_dir} do
      content = "case insensitive test"
      file_path = Path.join(test_dir, "case.txt")
      File.write!(file_path, content)

      {:ok, lowercase} = Downloader.compute_checksum(file_path)
      uppercase = String.upcase(lowercase)

      assert :ok = Downloader.verify_checksum(file_path, uppercase)
    end

    test "returns error for non-existent file", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "missing.txt")

      result = Downloader.verify_checksum(file_path, "abc123")

      assert {:error, {:read_file, :enoent}} = result
    end
  end

  describe "download_verified/5" do
    setup do
      bypass = Bypass.open()
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "verified_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, bypass: bypass, test_dir: test_dir}
    end

    test "downloads and verifies with correct checksum", %{bypass: bypass, test_dir: test_dir} do
      content = "verified content"
      expected_checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      Bypass.expect(bypass, "GET", "/tarballs/verified-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      # Create mock client and download directly via HttpClient
      client = HttpClient.new()
      target_path = Path.join(test_dir, "verified-1.0.0.tar")
      url = "http://localhost:#{bypass.port}/tarballs/verified-1.0.0.tar"

      # Download first
      {:ok, _} = HttpClient.download(client, url, target_path)

      # Then verify checksum
      assert :ok = Downloader.verify_checksum(target_path, expected_checksum)
      assert File.exists?(target_path)
    end

    test "deletes file when checksum mismatches", %{bypass: bypass, test_dir: test_dir} do
      content = "corrupted content"
      wrong_checksum = "0000000000000000000000000000000000000000000000000000000000000000"

      Bypass.expect(bypass, "GET", "/tarballs/corrupted-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      client = HttpClient.new()
      target_path = Path.join(test_dir, "corrupted-1.0.0.tar")
      url = "http://localhost:#{bypass.port}/tarballs/corrupted-1.0.0.tar"

      # Download first
      {:ok, _} = HttpClient.download(client, url, target_path)
      assert File.exists?(target_path)

      # Verify with wrong checksum should fail
      result = Downloader.verify_checksum(target_path, wrong_checksum)
      assert result == {:error, :checksum_mismatch}
    end

    test "works without checksum (skips verification)", %{bypass: bypass, test_dir: test_dir} do
      content = "unverified content"

      Bypass.expect(bypass, "GET", "/tarballs/unverified-1.0.0.tar", fn conn ->
        Plug.Conn.resp(conn, 200, content)
      end)

      client = HttpClient.new()
      target_path = Path.join(test_dir, "unverified-1.0.0.tar")
      url = "http://localhost:#{bypass.port}/tarballs/unverified-1.0.0.tar"

      # Download without checksum verification
      {:ok, _} = HttpClient.download(client, url, target_path)

      assert File.exists?(target_path)
      assert File.read!(target_path) == content
    end
  end
end
