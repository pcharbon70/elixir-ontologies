defmodule ElixirOntologies.Analyzer.LocationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Location
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest Location
  doctest SourceLocation

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  # Parse code with full location metadata
  defp parse(code) do
    {:ok, ast} = Code.string_to_quoted(code, columns: true, token_metadata: true)
    ast
  end

  # ============================================================================
  # extract/1 Tests
  # ============================================================================

  describe "extract/1" do
    test "extracts line and column from def node" do
      ast = parse("def foo, do: :ok")
      assert {:ok, {1, 1}} = Location.extract(ast)
    end

    test "extracts line and column from defmodule node" do
      ast = parse("defmodule Foo do end")
      assert {:ok, {1, 1}} = Location.extract(ast)
    end

    test "extracts correct position for nested node" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      ast = parse(code)
      {:defmodule, _, [_alias, [do: {:def, meta, _}]]} = ast
      nested_ast = {:def, meta, []}
      assert {:ok, {2, 3}} = Location.extract(nested_ast)
    end

    test "extracts position from attribute" do
      ast = parse("@moduledoc \"test\"")
      assert {:ok, {1, 1}} = Location.extract(ast)
    end

    test "extracts position from function call" do
      ast = parse("Enum.map(list, fn x -> x end)")
      # The outer node is the function call, which starts at column 6 (where 'map' begins)
      assert {:ok, {1, 6}} = Location.extract(ast)
    end

    test "returns :no_location for bare atom" do
      assert :no_location = Location.extract(:foo)
    end

    test "returns :no_location for bare integer" do
      assert :no_location = Location.extract(42)
    end

    test "returns :no_location for bare string" do
      assert :no_location = Location.extract("hello")
    end

    test "returns :no_location for tuple without location" do
      assert :no_location = Location.extract({:ok, [], []})
    end

    test "returns :no_location for list" do
      assert :no_location = Location.extract([1, 2, 3])
    end

    test "returns :no_location for nil" do
      assert :no_location = Location.extract(nil)
    end
  end

  # ============================================================================
  # extract!/1 Tests
  # ============================================================================

  describe "extract!/1" do
    test "returns position tuple for valid node" do
      ast = parse("def foo, do: :ok")
      assert {1, 1} = Location.extract!(ast)
    end

    test "raises ArgumentError for node without location" do
      assert_raise ArgumentError, ~r/no location metadata/, fn ->
        Location.extract!(:atom)
      end
    end
  end

  # ============================================================================
  # extract_range/1 Tests
  # ============================================================================

  describe "extract_range/1" do
    test "extracts full range from defmodule with end" do
      code = """
      defmodule Foo do
        :ok
      end
      """

      ast = parse(code)
      assert {:ok, loc} = Location.extract_range(ast)
      assert %SourceLocation{} = loc
      assert loc.start_line == 1
      assert loc.start_column == 1
      assert loc.end_line == 3
      assert loc.end_column == 1
    end

    test "extracts full range from def with end" do
      code = """
      def foo do
        :bar
      end
      """

      ast = parse(code)
      assert {:ok, loc} = Location.extract_range(ast)
      assert loc.start_line == 1
      assert loc.start_column == 1
      assert loc.end_line == 3
      assert loc.end_column == 1
    end

    test "extracts range from single-line def" do
      ast = parse("def foo, do: :ok")
      assert {:ok, loc} = Location.extract_range(ast)
      assert loc.start_line == 1
      assert loc.start_column == 1
      # Single-line def may not have explicit end
    end

    test "extracts range from function call with closing paren" do
      ast = parse("hello(world)")
      assert {:ok, loc} = Location.extract_range(ast)
      assert loc.start_line == 1
      assert loc.start_column == 1
      # closing paren position captured
      assert loc.end_line == 1
      assert loc.end_column == 12
    end

    test "returns :no_location for bare atom" do
      assert :no_location = Location.extract_range(:foo)
    end

    test "returns :no_location for node without line" do
      assert :no_location = Location.extract_range({:foo, [], []})
    end
  end

  # ============================================================================
  # extract_range!/1 Tests
  # ============================================================================

  describe "extract_range!/1" do
    test "returns SourceLocation for valid node" do
      ast = parse("def foo, do: :ok")
      assert %SourceLocation{} = Location.extract_range!(ast)
    end

    test "raises ArgumentError for node without location" do
      assert_raise ArgumentError, ~r/no location metadata/, fn ->
        Location.extract_range!(:atom)
      end
    end
  end

  # ============================================================================
  # span/2 Tests
  # ============================================================================

  describe "span/2" do
    test "calculates span from first to last node" do
      code = """
      defmodule Foo do
        def first, do: :a
        def last, do: :b
      end
      """

      ast = parse(code)
      {:defmodule, _, [_alias, [do: {:__block__, [], [first_def, last_def]}]]} = ast

      assert {:ok, span} = Location.span(first_def, last_def)
      assert span.start_line == 2
      assert span.start_column == 3
      assert span.end_line == 3
    end

    test "calculates span between parsed expressions" do
      start_node = parse("first()")
      end_node = parse("last()")

      assert {:ok, span} = Location.span(start_node, end_node)
      assert span.start_line == 1
    end

    test "returns :no_location when start has no location" do
      assert :no_location = Location.span(:atom, parse(":ok"))
    end

    test "handles end node without location" do
      start_node = parse("start()")
      end_node = :end_atom

      assert {:ok, span} = Location.span(start_node, end_node)
      assert span.start_line == 1
      assert span.end_line == nil
    end
  end

  # ============================================================================
  # span!/2 Tests
  # ============================================================================

  describe "span!/2" do
    test "returns SourceLocation for valid nodes" do
      start_node = parse("start()")
      end_node = parse("finish()")

      assert %SourceLocation{} = Location.span!(start_node, end_node)
    end

    test "raises ArgumentError when start has no location" do
      assert_raise ArgumentError, ~r/no location metadata/, fn ->
        Location.span!(:atom, parse(":ok"))
      end
    end
  end

  # ============================================================================
  # has_location?/1 Tests
  # ============================================================================

  describe "has_location?/1" do
    test "returns true for node with location" do
      ast = parse("def foo, do: :ok")
      assert Location.has_location?(ast)
    end

    test "returns false for bare atom" do
      refute Location.has_location?(:foo)
    end

    test "returns false for integer" do
      refute Location.has_location?(42)
    end

    test "returns false for tuple without metadata" do
      refute Location.has_location?({:ok, [], []})
    end

    test "returns true for parsed expression" do
      ast = parse("foo()")
      assert Location.has_location?(ast)
    end
  end

  # ============================================================================
  # line/1 Tests
  # ============================================================================

  describe "line/1" do
    test "returns line number for node with location" do
      ast = parse("def foo, do: :ok")
      assert Location.line(ast) == 1
    end

    test "returns correct line for multi-line code" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      ast = parse(code)
      {:defmodule, _, [_alias, [do: body]]} = ast

      # For single expression, body is just the def
      # For block, body is {:__block__, [], [...]}
      case body do
        {:def, meta, _} ->
          def_ast = {:def, meta, []}
          assert Location.line(def_ast) == 2

        {:__block__, _, [def_node | _]} ->
          assert Location.line(def_node) == 2
      end
    end

    test "returns nil for bare atom" do
      assert Location.line(:foo) == nil
    end

    test "returns nil for list" do
      assert Location.line([1, 2, 3]) == nil
    end

    test "returns nil for nil" do
      assert Location.line(nil) == nil
    end
  end

  # ============================================================================
  # column/1 Tests
  # ============================================================================

  describe "column/1" do
    test "returns column number for node with location" do
      ast = parse("def foo, do: :ok")
      assert Location.column(ast) == 1
    end

    test "returns correct column for indented code" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      ast = parse(code)
      {:defmodule, _, [_alias, [do: body]]} = ast

      case body do
        {:def, meta, _} ->
          def_ast = {:def, meta, []}
          assert Location.column(def_ast) == 3

        {:__block__, _, [def_node | _]} ->
          assert Location.column(def_node) == 3
      end
    end

    test "returns nil for bare atom" do
      assert Location.column(:foo) == nil
    end

    test "returns nil for tuple without metadata" do
      assert Location.column({:ok, [], []}) == nil
    end
  end

  # ============================================================================
  # SourceLocation Struct Tests
  # ============================================================================

  describe "SourceLocation struct" do
    test "enforces start_line and start_column at runtime" do
      # struct/2 raises at runtime when required keys are missing
      assert_raise ArgumentError, ~r/keys must also be given/, fn ->
        struct!(SourceLocation, [])
      end
    end

    test "allows creation with required fields" do
      loc = %SourceLocation{start_line: 1, start_column: 1}
      assert loc.start_line == 1
      assert loc.start_column == 1
      assert loc.end_line == nil
      assert loc.end_column == nil
    end

    test "allows all fields" do
      loc = %SourceLocation{
        start_line: 1,
        start_column: 5,
        end_line: 10,
        end_column: 3
      }

      assert loc.start_line == 1
      assert loc.start_column == 5
      assert loc.end_line == 10
      assert loc.end_column == 3
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration with real code" do
    test "extracts locations from complex module" do
      code = """
      defmodule MyApp.Calculator do
        @moduledoc "Calculator module"

        @doc "Adds two numbers"
        def add(a, b) do
          a + b
        end

        defp helper(x), do: x * 2
      end
      """

      ast = parse(code)

      # Module location
      assert {:ok, mod_loc} = Location.extract_range(ast)
      assert mod_loc.start_line == 1
      assert mod_loc.end_line == 10

      # Extract nested functions
      {:defmodule, _, [_alias, [do: {:__block__, [], items}]]} = ast

      # Find the def add node
      def_node = Enum.find(items, fn
        {:def, _, _} -> true
        _ -> false
      end)

      assert {:ok, {5, 3}} = Location.extract(def_node)
      assert {:ok, def_loc} = Location.extract_range(def_node)
      assert def_loc.start_line == 5
      assert def_loc.end_line == 7
    end

    test "handles protocol definition" do
      code = """
      defprotocol Printable do
        @doc "Converts to string"
        def to_string(data)
      end
      """

      ast = parse(code)
      assert {:ok, loc} = Location.extract_range(ast)
      assert loc.start_line == 1
      assert loc.end_line == 4
    end

    test "handles case expression" do
      code = """
      case x do
        :a -> 1
        :b -> 2
      end
      """

      ast = parse(code)
      assert {:ok, loc} = Location.extract_range(ast)
      assert loc.start_line == 1
      assert loc.end_line == 4
    end
  end
end
