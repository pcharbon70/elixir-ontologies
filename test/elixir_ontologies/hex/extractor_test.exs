defmodule ElixirOntologies.Hex.ExtractorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Extractor

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_test_tarball(dir, contents) do
    # Create a minimal Hex-style tarball structure
    tarball_path = Path.join(dir, "test.tar")

    # Create temporary files
    version_file = Path.join(dir, "VERSION")
    checksum_file = Path.join(dir, "CHECKSUM")
    metadata_file = Path.join(dir, "metadata.config")
    contents_file = Path.join(dir, "contents.tar.gz")

    File.write!(version_file, "3")
    File.write!(checksum_file, "abc123")
    File.write!(metadata_file, ~s({<<"name">>, <<"test_pkg">>}.\n{<<"version">>, <<"1.0.0">>}.\n))

    # Create contents.tar.gz
    create_contents_tarball(contents_file, contents)

    # Create outer tar
    files = [~c"VERSION", ~c"CHECKSUM", ~c"metadata.config", ~c"contents.tar.gz"]

    :ok =
      :erl_tar.create(
        to_charlist(tarball_path),
        Enum.map(files, fn f -> {f, to_charlist(Path.join(dir, to_string(f)))} end)
      )

    tarball_path
  end

  defp create_contents_tarball(path, contents) do
    # Create a temp directory with the contents
    tmp_dir = Path.join(Path.dirname(path), "contents_tmp")
    File.mkdir_p!(tmp_dir)

    # Write contents to files
    for {filename, content} <- contents do
      file_path = Path.join(tmp_dir, filename)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, content)
    end

    # Create the tar
    tar_path = Path.join(Path.dirname(path), "contents.tar")

    files =
      for {filename, _} <- contents do
        {to_charlist(filename), to_charlist(Path.join(tmp_dir, filename))}
      end

    :ok = :erl_tar.create(to_charlist(tar_path), files)

    # Gzip it
    tar_content = File.read!(tar_path)
    gzipped = :zlib.gzip(tar_content)
    File.write!(path, gzipped)

    # Cleanup
    File.rm!(tar_path)
    File.rm_rf!(tmp_dir)
  end

  # ===========================================================================
  # Outer Extraction Tests
  # ===========================================================================

  describe "extract_outer/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_outer_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "extracts valid outer tar", %{test_dir: test_dir} do
      tarball_path =
        create_test_tarball(test_dir, [
          {"mix.exs", "defmodule Test.MixProject do end"},
          {"lib/test.ex", "defmodule Test do end"}
        ])

      target_dir = Path.join(test_dir, "extracted")

      {:ok, result_dir} = Extractor.extract_outer(tarball_path, target_dir)

      assert result_dir == target_dir
      assert File.exists?(Path.join(target_dir, "VERSION"))
      assert File.exists?(Path.join(target_dir, "contents.tar.gz"))
    end

    test "returns error for invalid tarball", %{test_dir: test_dir} do
      invalid_tar = Path.join(test_dir, "invalid.tar")
      File.write!(invalid_tar, "not a tar file")

      target_dir = Path.join(test_dir, "extracted")
      result = Extractor.extract_outer(invalid_tar, target_dir)

      assert {:error, {:tar_extract, _}} = result
    end
  end

  # ===========================================================================
  # Contents Extraction Tests
  # ===========================================================================

  describe "extract_contents/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_contents_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "extracts contents.tar.gz", %{test_dir: test_dir} do
      # Create outer structure
      outer_dir = Path.join(test_dir, "outer")
      File.mkdir_p!(outer_dir)

      contents_path = Path.join(outer_dir, "contents.tar.gz")

      create_contents_tarball(contents_path, [
        {"mix.exs", "defmodule Test.MixProject do end"},
        {"lib/test.ex", "defmodule Test do end"}
      ])

      target_dir = Path.join(test_dir, "source")

      {:ok, result_dir} = Extractor.extract_contents(outer_dir, target_dir)

      assert result_dir == target_dir
      assert File.exists?(Path.join(target_dir, "mix.exs"))
      assert File.exists?(Path.join(target_dir, "lib/test.ex"))
    end

    test "returns error when contents.tar.gz missing", %{test_dir: test_dir} do
      outer_dir = Path.join(test_dir, "empty_outer")
      File.mkdir_p!(outer_dir)

      target_dir = Path.join(test_dir, "source")
      result = Extractor.extract_contents(outer_dir, target_dir)

      assert result == {:error, :no_contents}
    end
  end

  # ===========================================================================
  # Full Extraction Tests
  # ===========================================================================

  describe "extract/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_full_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "extracts complete package", %{test_dir: test_dir} do
      tarball_path =
        create_test_tarball(test_dir, [
          {"mix.exs", "defmodule Test.MixProject do end"},
          {"lib/test.ex", "defmodule Test do end"},
          {"lib/test/helper.ex", "defmodule Test.Helper do end"}
        ])

      target_dir = Path.join(test_dir, "source")

      {:ok, result_dir} = Extractor.extract(tarball_path, target_dir)

      assert result_dir == target_dir
      assert File.exists?(Path.join(target_dir, "mix.exs"))
      assert File.exists?(Path.join(target_dir, "lib/test.ex"))
      assert File.exists?(Path.join(target_dir, "lib/test/helper.ex"))
    end

    test "cleans up outer temp directory", %{test_dir: test_dir} do
      tarball_path =
        create_test_tarball(test_dir, [
          {"mix.exs", "defmodule Test.MixProject do end"}
        ])

      target_dir = Path.join(test_dir, "source")

      {:ok, _} = Extractor.extract(tarball_path, target_dir)

      # Should not leave any outer_* directories
      remaining_dirs =
        test_dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "outer_"))

      assert remaining_dirs == []
    end
  end

  # ===========================================================================
  # Metadata Extraction Tests
  # ===========================================================================

  describe "extract_metadata/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_meta_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "parses metadata.config", %{test_dir: test_dir} do
      metadata_content = """
      {<<"name">>, <<"phoenix">>}.
      {<<"version">>, <<"1.7.10">>}.
      {<<"description">>, <<"A web framework">>}.
      """

      File.write!(Path.join(test_dir, "metadata.config"), metadata_content)

      {:ok, metadata} = Extractor.extract_metadata(test_dir)

      assert metadata["name"] == "phoenix"
      assert metadata["version"] == "1.7.10"
      assert metadata["description"] == "A web framework"
    end

    test "returns error when metadata.config missing", %{test_dir: test_dir} do
      result = Extractor.extract_metadata(test_dir)
      assert result == {:error, :no_metadata}
    end
  end

  # ===========================================================================
  # Cleanup Tests
  # ===========================================================================

  describe "cleanup/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_cleanup_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      {:ok, test_dir: test_dir}
    end

    test "removes directory and contents", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "file.txt"), "content")
      File.mkdir_p!(Path.join(test_dir, "subdir"))
      File.write!(Path.join(test_dir, "subdir/nested.txt"), "nested")

      assert :ok = Extractor.cleanup(test_dir)
      refute File.exists?(test_dir)
    end

    test "handles missing directory", %{test_dir: test_dir} do
      File.rm_rf!(test_dir)

      # Should not raise
      result = Extractor.cleanup(test_dir)
      assert result == :ok
    end
  end

  describe "cleanup_tarball/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "test_tarball_#{:rand.uniform(100_000)}.tar")

      {:ok, test_file: test_file}
    end

    test "removes tarball file", %{test_file: test_file} do
      File.write!(test_file, "content")

      assert :ok = Extractor.cleanup_tarball(test_file)
      refute File.exists?(test_file)
    end

    test "handles missing file", %{test_file: test_file} do
      # File doesn't exist
      assert :ok = Extractor.cleanup_tarball(test_file)
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "has_mix_exs?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "has_mix_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when mix.exs exists", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "mix.exs"), "defmodule Test.MixProject do end")

      assert Extractor.has_mix_exs?(test_dir)
    end

    test "returns false when mix.exs missing", %{test_dir: test_dir} do
      refute Extractor.has_mix_exs?(test_dir)
    end
  end

  # ===========================================================================
  # Security Tests - Path Traversal Prevention
  # ===========================================================================

  describe "path traversal protection" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "extractor_security_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "rejects paths with .. traversal", %{test_dir: test_dir} do
      # Create a malicious tar with path traversal
      outer_dir = Path.join(test_dir, "outer")
      File.mkdir_p!(outer_dir)

      contents_path = Path.join(outer_dir, "contents.tar.gz")
      malicious_tar = create_malicious_tar_with_traversal(test_dir)

      # Gzip the malicious tar
      gzipped = :zlib.gzip(File.read!(malicious_tar))
      File.write!(contents_path, gzipped)

      target_dir = Path.join(test_dir, "source")

      result = Extractor.extract_contents(outer_dir, target_dir)

      assert {:error, {:path_traversal, _}} = result
    end

    test "rejects absolute paths in tar", %{test_dir: test_dir} do
      outer_dir = Path.join(test_dir, "outer")
      File.mkdir_p!(outer_dir)

      contents_path = Path.join(outer_dir, "contents.tar.gz")
      malicious_tar = create_tar_with_absolute_path(test_dir)

      gzipped = :zlib.gzip(File.read!(malicious_tar))
      File.write!(contents_path, gzipped)

      target_dir = Path.join(test_dir, "source")

      result = Extractor.extract_contents(outer_dir, target_dir)

      # Should fail validation
      assert {:error, _} = result
    end

    test "allows valid nested paths", %{test_dir: test_dir} do
      outer_dir = Path.join(test_dir, "outer")
      File.mkdir_p!(outer_dir)

      contents_path = Path.join(outer_dir, "contents.tar.gz")

      create_contents_tarball(contents_path, [
        {"lib/deeply/nested/file.ex", "defmodule Nested do end"},
        {"test/unit/some_test.exs", "defmodule SomeTest do end"}
      ])

      target_dir = Path.join(test_dir, "source")

      {:ok, _} = Extractor.extract_contents(outer_dir, target_dir)

      assert File.exists?(Path.join(target_dir, "lib/deeply/nested/file.ex"))
      assert File.exists?(Path.join(target_dir, "test/unit/some_test.exs"))
    end
  end

  # Helper to create tar with path traversal
  defp create_malicious_tar_with_traversal(test_dir) do
    tmp_dir = Path.join(test_dir, "malicious_tmp")
    File.mkdir_p!(tmp_dir)

    # Create a file that we'll include with a malicious path
    safe_file = Path.join(tmp_dir, "safe.txt")
    File.write!(safe_file, "malicious content")

    tar_path = Path.join(test_dir, "malicious.tar")

    # Create tar with a traversal path manually
    # Use :erl_tar.add with explicit name
    {:ok, tar} = :erl_tar.open(to_charlist(tar_path), [:write])
    :ok = :erl_tar.add(tar, to_charlist(safe_file), ~c"../../../tmp/escape.txt", [])
    :ok = :erl_tar.close(tar)

    tar_path
  end

  # Helper to create tar with absolute path
  defp create_tar_with_absolute_path(test_dir) do
    tmp_dir = Path.join(test_dir, "absolute_tmp")
    File.mkdir_p!(tmp_dir)

    safe_file = Path.join(tmp_dir, "safe.txt")
    File.write!(safe_file, "content")

    tar_path = Path.join(test_dir, "absolute.tar")

    {:ok, tar} = :erl_tar.open(to_charlist(tar_path), [:write])
    :ok = :erl_tar.add(tar, to_charlist(safe_file), ~c"/etc/passwd", [])
    :ok = :erl_tar.close(tar)

    tar_path
  end
end
