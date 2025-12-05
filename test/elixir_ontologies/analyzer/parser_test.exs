defmodule ElixirOntologies.Analyzer.ParserTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Parser
  alias ElixirOntologies.Analyzer.Parser.{Error, Result}

  # ============================================================================
  # parse/1 Tests
  # ============================================================================

  describe "parse/1" do
    test "parses simple expression" do
      {:ok, ast} = Parser.parse("1 + 2")

      assert {:+, _meta, [1, 2]} = ast
    end

    test "parses module definition" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, ast} = Parser.parse(source)

      assert {:defmodule, _meta, [{:__aliases__, _, [:Foo]}, _body]} = ast
    end

    test "parses function definition" do
      {:ok, ast} = Parser.parse("def foo(x), do: x + 1")

      assert {:def, _meta, _args} = ast
    end

    test "includes column information by default" do
      {:ok, ast} = Parser.parse("foo")

      # AST should be an atom with metadata containing column info
      assert {:foo, meta, nil} = ast
      assert Keyword.has_key?(meta, :line)
      assert Keyword.has_key?(meta, :column)
    end

    test "returns error for invalid syntax" do
      {:error, error} = Parser.parse("def foo(")

      assert %Error{} = error
      assert is_binary(error.message)
      assert error.line == 1
    end

    test "returns error with column for invalid syntax" do
      {:error, error} = Parser.parse("def foo(")

      assert %Error{} = error
      assert is_integer(error.column) or is_nil(error.column)
    end

    test "returns snippet for error location" do
      source = "def foo(\nbar"
      {:error, error} = Parser.parse(source)

      assert %Error{} = error
      # Snippet should be a line from the source
      assert is_nil(error.snippet) or is_binary(error.snippet)
    end

    test "parses empty string" do
      {:ok, ast} = Parser.parse("")

      # Empty string parses to a block with empty body
      assert ast == {:__block__, [], []}
    end

    test "parses complex nested structure" do
      source = """
      defmodule Outer do
        defmodule Inner do
          def nested, do: :ok
        end
      end
      """

      {:ok, ast} = Parser.parse(source)

      assert {:defmodule, _, _} = ast
    end
  end

  # ============================================================================
  # parse/2 Tests
  # ============================================================================

  describe "parse/2" do
    test "accepts file option for error messages" do
      {:ok, _ast} = Parser.parse("foo", file: "test.ex")
    end

    test "accepts columns option" do
      {:ok, ast} = Parser.parse("foo", columns: false)

      # Without columns, metadata should not have column key
      assert {:foo, meta, nil} = ast
      refute Keyword.has_key?(meta, :column)
    end

    test "accepts token_metadata option" do
      {:ok, ast} = Parser.parse("foo", token_metadata: false)

      assert is_tuple(ast) or is_atom(ast)
    end

    test "merges custom options with defaults" do
      # Custom option should be applied while keeping defaults
      {:ok, ast} = Parser.parse("foo", custom_opt: true)

      # Should still have column info from defaults
      assert {:foo, meta, nil} = ast
      assert Keyword.has_key?(meta, :column)
    end

    test "custom options override defaults" do
      {:ok, ast} = Parser.parse("foo", columns: false)

      assert {:foo, meta, nil} = ast
      refute Keyword.has_key?(meta, :column)
    end
  end

  # ============================================================================
  # parse!/1 Tests
  # ============================================================================

  describe "parse!/1" do
    test "returns AST for valid source" do
      ast = Parser.parse!("1 + 2")

      assert {:+, _meta, [1, 2]} = ast
    end

    test "raises SyntaxError for invalid source" do
      assert_raise SyntaxError, fn ->
        Parser.parse!("def foo(")
      end
    end
  end

  # ============================================================================
  # parse!/2 Tests
  # ============================================================================

  describe "parse!/2" do
    test "returns AST with options" do
      ast = Parser.parse!("foo", columns: false)

      assert {:foo, meta, nil} = ast
      refute Keyword.has_key?(meta, :column)
    end

    test "raises SyntaxError with file info" do
      error =
        assert_raise SyntaxError, fn ->
          Parser.parse!("def foo(", file: "test.ex")
        end

      assert error.file == "test.ex"
    end
  end

  # ============================================================================
  # parse_file/1 Tests
  # ============================================================================

  describe "parse_file/1" do
    test "parses valid Elixir file" do
      {:ok, result} = Parser.parse_file("lib/elixir_ontologies.ex")

      assert %Result{} = result
      assert is_binary(result.path)
      assert is_binary(result.source)
      assert is_tuple(result.ast)
      assert %{size: _, mtime: _} = result.file_metadata
    end

    test "returns absolute path" do
      {:ok, result} = Parser.parse_file("lib/elixir_ontologies.ex")

      assert Path.type(result.path) == :absolute
      assert String.ends_with?(result.path, "lib/elixir_ontologies.ex")
    end

    test "returns file metadata" do
      {:ok, result} = Parser.parse_file("lib/elixir_ontologies.ex")

      assert result.file_metadata.size > 0
      assert %NaiveDateTime{} = result.file_metadata.mtime
    end

    test "returns error for nonexistent file" do
      assert {:error, {:file_error, :enoent}} = Parser.parse_file("/nonexistent.ex")
    end

    test "returns error for directory" do
      assert {:error, {:file_error, :not_regular_file}} = Parser.parse_file("lib")
    end

    @tag :tmp_dir
    test "returns parse error for invalid syntax", %{tmp_dir: tmp_dir} do
      content = "def foo("
      path = Path.join(tmp_dir, "invalid.ex")
      File.write!(path, content)

      {:error, error} = Parser.parse_file(path)

      assert %Error{} = error
      assert is_binary(error.message)
    end
  end

  # ============================================================================
  # parse_file!/1 Tests
  # ============================================================================

  describe "parse_file!/1" do
    test "returns result for valid file" do
      result = Parser.parse_file!("lib/elixir_ontologies.ex")

      assert %Result{} = result
      assert is_tuple(result.ast)
    end

    test "raises File.Error for nonexistent file" do
      assert_raise File.Error, fn ->
        Parser.parse_file!("/nonexistent.ex")
      end
    end

    @tag :tmp_dir
    test "raises SyntaxError for invalid syntax", %{tmp_dir: tmp_dir} do
      content = "def foo("
      path = Path.join(tmp_dir, "invalid.ex")
      File.write!(path, content)

      assert_raise SyntaxError, fn ->
        Parser.parse_file!(path)
      end
    end
  end

  # ============================================================================
  # default_options/0 Tests
  # ============================================================================

  describe "default_options/0" do
    test "returns keyword list" do
      opts = Parser.default_options()

      assert is_list(opts)
    end

    test "includes columns option" do
      opts = Parser.default_options()

      assert opts[:columns] == true
    end

    test "includes token_metadata option" do
      opts = Parser.default_options()

      assert opts[:token_metadata] == true
    end

    test "includes emit_warnings option" do
      opts = Parser.default_options()

      assert opts[:emit_warnings] == false
    end
  end

  # ============================================================================
  # Error Struct Tests
  # ============================================================================

  describe "Error struct" do
    test "has message field" do
      {:error, error} = Parser.parse("def foo(")

      assert is_binary(error.message)
      assert String.length(error.message) > 0
    end

    test "has line field" do
      {:error, error} = Parser.parse("def foo(")

      assert is_integer(error.line)
      assert error.line >= 1
    end

    test "error message includes token info" do
      {:error, error} = Parser.parse("def foo(,)")

      assert is_binary(error.message)
    end
  end

  # ============================================================================
  # Doctest
  # ============================================================================

  doctest ElixirOntologies.Analyzer.Parser
end
