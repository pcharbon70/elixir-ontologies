defmodule ElixirOntologies.Analyzer.FileReaderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.FileReader
  alias ElixirOntologies.Analyzer.FileReader.Result

  # ============================================================================
  # read/1 Tests
  # ============================================================================

  describe "read/1" do
    test "reads valid Elixir file" do
      {:ok, result} = FileReader.read("lib/elixir_ontologies.ex")

      assert %Result{} = result
      assert is_binary(result.source)
      assert String.contains?(result.source, "defmodule")
      assert result.size > 0
      assert %NaiveDateTime{} = result.mtime
    end

    test "returns absolute path" do
      {:ok, result} = FileReader.read("lib/elixir_ontologies.ex")

      assert Path.type(result.path) == :absolute
      assert String.ends_with?(result.path, "lib/elixir_ontologies.ex")
    end

    test "returns error for nonexistent file" do
      assert {:error, :enoent} = FileReader.read("/nonexistent/path/file.ex")
    end

    test "returns error for directory" do
      assert {:error, :not_regular_file} = FileReader.read("lib")
    end

    @tag :tmp_dir
    test "strips UTF-8 BOM from file content", %{tmp_dir: tmp_dir} do
      # Create file with BOM
      bom_content = <<0xEF, 0xBB, 0xBF, "defmodule Test do\nend\n">>
      path = Path.join(tmp_dir, "with_bom.ex")
      File.write!(path, bom_content)

      {:ok, result} = FileReader.read(path)

      # BOM should be stripped
      refute String.starts_with?(result.source, <<0xEF, 0xBB, 0xBF>>)
      assert String.starts_with?(result.source, "defmodule")
    end

    @tag :tmp_dir
    test "handles file without BOM", %{tmp_dir: tmp_dir} do
      content = "defmodule Test do\nend\n"
      path = Path.join(tmp_dir, "no_bom.ex")
      File.write!(path, content)

      {:ok, result} = FileReader.read(path)

      assert result.source == content
    end

    @tag :tmp_dir
    test "tracks correct file size", %{tmp_dir: tmp_dir} do
      content = "defmodule Test do\nend\n"
      path = Path.join(tmp_dir, "size_test.ex")
      File.write!(path, content)

      {:ok, result} = FileReader.read(path)

      assert result.size == byte_size(content)
    end

    @tag :tmp_dir
    test "tracks modification time", %{tmp_dir: tmp_dir} do
      content = "defmodule Test do\nend\n"
      path = Path.join(tmp_dir, "mtime_test.ex")
      File.write!(path, content)

      {:ok, result} = FileReader.read(path)

      assert %NaiveDateTime{} = result.mtime
      # mtime should be recent (within last minute)
      diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), result.mtime, :second)
      assert diff < 60
    end

    @tag :tmp_dir
    test "returns error for invalid UTF-8 content", %{tmp_dir: tmp_dir} do
      # Invalid UTF-8 byte sequence
      invalid_content = <<0xFF, 0xFE, "hello">>
      path = Path.join(tmp_dir, "invalid_utf8.ex")
      File.write!(path, invalid_content)

      assert {:error, {:encoding_error, _message}} = FileReader.read(path)
    end
  end

  # ============================================================================
  # read!/1 Tests
  # ============================================================================

  describe "read!/1" do
    test "returns result for valid file" do
      result = FileReader.read!("lib/elixir_ontologies.ex")

      assert %Result{} = result
      assert is_binary(result.source)
    end

    test "raises File.Error for nonexistent file" do
      assert_raise File.Error, fn ->
        FileReader.read!("/nonexistent/path/file.ex")
      end
    end

    test "raises File.Error for directory" do
      assert_raise File.Error, fn ->
        FileReader.read!("lib")
      end
    end
  end

  # ============================================================================
  # exists?/1 Tests
  # ============================================================================

  describe "exists?/1" do
    test "returns true for existing file" do
      assert FileReader.exists?("lib/elixir_ontologies.ex")
    end

    test "returns true for existing directory" do
      assert FileReader.exists?("lib")
    end

    test "returns false for nonexistent path" do
      refute FileReader.exists?("/nonexistent/path/file.ex")
    end
  end

  # ============================================================================
  # elixir_file?/1 Tests
  # ============================================================================

  describe "elixir_file?/1" do
    test "returns true for .ex files" do
      assert FileReader.elixir_file?("lib/my_module.ex")
      assert FileReader.elixir_file?("/full/path/to/module.ex")
    end

    test "returns true for .exs files" do
      assert FileReader.elixir_file?("test/my_test.exs")
      assert FileReader.elixir_file?("mix.exs")
    end

    test "returns false for non-Elixir files" do
      refute FileReader.elixir_file?("README.md")
      refute FileReader.elixir_file?("lib/module.erl")
      refute FileReader.elixir_file?("Makefile")
      refute FileReader.elixir_file?("file.txt")
    end

    test "returns false for files without extension" do
      refute FileReader.elixir_file?("Dockerfile")
      refute FileReader.elixir_file?("LICENSE")
    end
  end

  # ============================================================================
  # has_bom?/1 Tests
  # ============================================================================

  describe "has_bom?/1" do
    test "returns true for content with UTF-8 BOM" do
      assert FileReader.has_bom?(<<0xEF, 0xBB, 0xBF, "content">>)
      assert FileReader.has_bom?(<<0xEF, 0xBB, 0xBF>>)
    end

    test "returns false for content without BOM" do
      refute FileReader.has_bom?("regular content")
      refute FileReader.has_bom?("")
    end

    test "returns false for partial BOM" do
      refute FileReader.has_bom?(<<0xEF, 0xBB>>)
      refute FileReader.has_bom?(<<0xEF>>)
    end
  end

  # ============================================================================
  # Doctest
  # ============================================================================

  doctest ElixirOntologies.Analyzer.FileReader
end
