defmodule ElixirOntologies.Hex.OutputManagerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.OutputManager
  alias ElixirOntologies.Graph

  # ===========================================================================
  # Path Generation Tests
  # ===========================================================================

  describe "output_path/3" do
    test "generates standard path" do
      path = OutputManager.output_path("/output", "phoenix", "1.7.10")

      assert path == "/output/phoenix-1.7.10.ttl"
    end

    test "handles nested output directory" do
      path = OutputManager.output_path("/tmp/hex/output", "ecto", "3.11.0")

      assert path == "/tmp/hex/output/ecto-3.11.0.ttl"
    end

    test "sanitizes package name with slashes" do
      path = OutputManager.output_path("/output", "my/package", "1.0.0")

      assert path == "/output/my_package-1.0.0.ttl"
    end

    test "sanitizes version with special characters" do
      path = OutputManager.output_path("/output", "pkg", "1.0.0-rc.1")

      assert path == "/output/pkg-1.0.0-rc.1.ttl"
    end
  end

  describe "sanitize_name/1" do
    test "returns name unchanged when safe" do
      assert OutputManager.sanitize_name("phoenix") == "phoenix"
    end

    test "replaces forward slashes" do
      assert OutputManager.sanitize_name("my/package") == "my_package"
    end

    test "replaces backslashes" do
      assert OutputManager.sanitize_name("my\\package") == "my_package"
    end

    test "replaces colons" do
      assert OutputManager.sanitize_name("pkg:sub") == "pkg_sub"
    end

    test "replaces asterisks" do
      assert OutputManager.sanitize_name("pkg*name") == "pkg_name"
    end

    test "replaces question marks" do
      assert OutputManager.sanitize_name("pkg?name") == "pkg_name"
    end

    test "replaces quotes" do
      assert OutputManager.sanitize_name(~s(pkg"name)) == "pkg_name"
    end

    test "replaces angle brackets" do
      # Trailing underscore is trimmed
      assert OutputManager.sanitize_name("pkg<name>") == "pkg_name"
    end

    test "replaces pipes" do
      assert OutputManager.sanitize_name("pkg|name") == "pkg_name"
    end

    test "replaces double dots" do
      assert OutputManager.sanitize_name("pkg..name") == "pkg_name"
    end

    test "trims leading and trailing underscores" do
      assert OutputManager.sanitize_name("_pkg_") == "pkg"
    end
  end

  # ===========================================================================
  # Directory Management Tests
  # ===========================================================================

  describe "ensure_output_dir/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "output_test_#{:rand.uniform(100_000)}")

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "creates directory when doesn't exist", %{test_dir: dir} do
      refute File.exists?(dir)

      assert :ok = OutputManager.ensure_output_dir(dir)

      assert File.dir?(dir)
    end

    test "succeeds when directory already exists", %{test_dir: dir} do
      File.mkdir_p!(dir)

      assert :ok = OutputManager.ensure_output_dir(dir)
    end

    test "creates nested directories", %{test_dir: dir} do
      nested = Path.join([dir, "nested", "path"])

      assert :ok = OutputManager.ensure_output_dir(nested)

      assert File.dir?(nested)
    end
  end

  # ===========================================================================
  # Graph Saving Tests
  # ===========================================================================

  describe "save_graph/4" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "graph_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "saves graph to correct path", %{test_dir: dir} do
      graph = Graph.new()

      {:ok, path} = OutputManager.save_graph(graph, dir, "test_pkg", "1.0.0")

      assert path == Path.join(dir, "test_pkg-1.0.0.ttl")
      assert File.exists?(path)
    end

    test "creates file with content", %{test_dir: dir} do
      graph = Graph.new()

      {:ok, path} = OutputManager.save_graph(graph, dir, "test_pkg", "1.0.0")

      {:ok, content} = File.read(path)
      assert is_binary(content)
    end
  end

  # ===========================================================================
  # Output Listing Tests
  # ===========================================================================

  describe "list_outputs/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "list_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns empty list for empty directory", %{test_dir: dir} do
      outputs = OutputManager.list_outputs(dir)

      assert outputs == []
    end

    test "lists existing output files", %{test_dir: dir} do
      File.write!(Path.join(dir, "phoenix-1.7.10.ttl"), "content")
      File.write!(Path.join(dir, "ecto-3.11.0.ttl"), "content")

      outputs = OutputManager.list_outputs(dir)

      assert length(outputs) == 2
      names = Enum.map(outputs, fn {name, _, _} -> name end)
      assert "phoenix" in names
      assert "ecto" in names
    end

    test "returns correct tuple format", %{test_dir: dir} do
      File.write!(Path.join(dir, "phoenix-1.7.10.ttl"), "content")

      [{name, version, path}] = OutputManager.list_outputs(dir)

      assert name == "phoenix"
      assert version == "1.7.10"
      assert path == Path.join(dir, "phoenix-1.7.10.ttl")
    end

    test "ignores non-ttl files", %{test_dir: dir} do
      File.write!(Path.join(dir, "phoenix-1.7.10.ttl"), "content")
      File.write!(Path.join(dir, "readme.md"), "content")

      outputs = OutputManager.list_outputs(dir)

      assert length(outputs) == 1
    end

    test "handles malformed filenames", %{test_dir: dir} do
      File.write!(Path.join(dir, "valid-1.0.0.ttl"), "content")
      File.write!(Path.join(dir, "invalid.ttl"), "content")

      outputs = OutputManager.list_outputs(dir)

      assert length(outputs) == 1
      assert hd(outputs) |> elem(0) == "valid"
    end
  end

  describe "output_exists?/3" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "exists_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when output exists", %{test_dir: dir} do
      File.write!(Path.join(dir, "phoenix-1.7.10.ttl"), "content")

      assert OutputManager.output_exists?(dir, "phoenix", "1.7.10")
    end

    test "returns false when output doesn't exist", %{test_dir: dir} do
      refute OutputManager.output_exists?(dir, "phoenix", "1.7.10")
    end

    test "returns false for different version", %{test_dir: dir} do
      File.write!(Path.join(dir, "phoenix-1.7.10.ttl"), "content")

      refute OutputManager.output_exists?(dir, "phoenix", "1.7.11")
    end
  end

  # ===========================================================================
  # Disk Space Tests
  # ===========================================================================

  describe "check_disk_space/1" do
    test "returns available bytes for valid directory" do
      tmp_dir = System.tmp_dir!()

      {:ok, bytes} = OutputManager.check_disk_space(tmp_dir)

      assert is_integer(bytes)
      assert bytes > 0
    end
  end

  describe "format_bytes/1" do
    test "formats bytes" do
      assert OutputManager.format_bytes(500) == "500 bytes"
    end

    test "formats kilobytes" do
      assert OutputManager.format_bytes(1536) == "1.5 KB"
    end

    test "formats megabytes" do
      assert OutputManager.format_bytes(2_621_440) == "2.5 MB"
    end

    test "formats gigabytes" do
      assert OutputManager.format_bytes(5_368_709_120) == "5.0 GB"
    end
  end

  describe "warn_if_low/2" do
    test "returns :ok when space is sufficient" do
      tmp_dir = System.tmp_dir!()

      # Use very low threshold
      result = OutputManager.warn_if_low(tmp_dir, 1)

      assert result == :ok
    end
  end

  describe "min_disk_space_bytes/0" do
    test "returns threshold in bytes" do
      bytes = OutputManager.min_disk_space_bytes()

      assert bytes == 500 * 1024 * 1024  # 500 MB
    end
  end

  describe "min_disk_space_mb/0" do
    test "returns threshold in megabytes" do
      assert OutputManager.min_disk_space_mb() == 500
    end
  end
end
