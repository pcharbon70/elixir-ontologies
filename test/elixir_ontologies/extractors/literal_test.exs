defmodule ElixirOntologies.Extractors.LiteralTest do
  @moduledoc """
  Tests for the Literal extractor module.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Literal

  doctest Literal

  # ============================================================================
  # Atom Extraction Tests
  # ============================================================================

  describe "extract_atom/1" do
    test "extracts simple atoms" do
      result = Literal.extract_atom(:ok)
      assert result.type == :atom
      assert result.value == :ok
      assert result.metadata.special_atom == false
    end

    test "extracts error atom" do
      result = Literal.extract_atom(:error)
      assert result.type == :atom
      assert result.value == :error
    end

    test "extracts true as special atom" do
      result = Literal.extract_atom(true)
      assert result.type == :atom
      assert result.value == true
      assert result.metadata.special_atom == true
      assert result.metadata.atom_kind == :boolean
    end

    test "extracts false as special atom" do
      result = Literal.extract_atom(false)
      assert result.type == :atom
      assert result.value == false
      assert result.metadata.special_atom == true
      assert result.metadata.atom_kind == :boolean
    end

    test "extracts nil as special atom" do
      result = Literal.extract_atom(nil)
      assert result.type == :atom
      assert result.value == nil
      assert result.metadata.special_atom == true
      assert result.metadata.atom_kind == nil
    end

    test "extracts atom with special characters" do
      result = Literal.extract_atom(:"hello world")
      assert result.type == :atom
      assert result.value == :"hello world"
    end
  end

  # ============================================================================
  # Integer Extraction Tests
  # ============================================================================

  describe "extract_integer/1" do
    test "extracts positive integer" do
      result = Literal.extract_integer(42)
      assert result.type == :integer
      assert result.value == 42
    end

    test "extracts negative integer" do
      result = Literal.extract_integer(-100)
      assert result.type == :integer
      assert result.value == -100
    end

    test "extracts zero" do
      result = Literal.extract_integer(0)
      assert result.type == :integer
      assert result.value == 0
    end

    test "extracts large integer" do
      result = Literal.extract_integer(1_000_000_000)
      assert result.type == :integer
      assert result.value == 1_000_000_000
    end

    test "extracts hex notation value" do
      # 0xFF parses to 255
      result = Literal.extract_integer(255)
      assert result.type == :integer
      assert result.value == 255
    end
  end

  # ============================================================================
  # Float Extraction Tests
  # ============================================================================

  describe "extract_float/1" do
    test "extracts simple float" do
      result = Literal.extract_float(3.14)
      assert result.type == :float
      assert result.value == 3.14
    end

    test "extracts negative float" do
      result = Literal.extract_float(-2.5)
      assert result.type == :float
      assert result.value == -2.5
    end

    test "extracts scientific notation" do
      result = Literal.extract_float(1.0e10)
      assert result.type == :float
      assert result.value == 1.0e10
    end

    test "extracts small float" do
      result = Literal.extract_float(1.0e-10)
      assert result.type == :float
      assert result.value == 1.0e-10
    end
  end

  # ============================================================================
  # String Extraction Tests
  # ============================================================================

  describe "extract_string/1" do
    test "extracts simple string" do
      result = Literal.extract_string("hello")
      assert result.type == :string
      assert result.value == "hello"
      assert result.metadata.interpolated == false
    end

    test "extracts empty string" do
      result = Literal.extract_string("")
      assert result.type == :string
      assert result.value == ""
    end

    test "extracts string with escapes" do
      result = Literal.extract_string("hello\nworld")
      assert result.type == :string
      assert result.value == "hello\nworld"
    end

    test "extracts string with interpolation from AST" do
      # AST for "hello #{world}"
      ast =
        {:<<>>, [],
         [
           "hello ",
           {:"::", [],
            [
              {{:., [], [Kernel, :to_string]}, [from_interpolation: true],
               [{:world, [], Elixir}]},
              {:binary, [], Elixir}
            ]}
         ]}

      result = Literal.extract_string(ast)
      assert result.type == :string
      assert result.metadata.interpolated == true
      assert is_list(result.metadata.parts)
    end
  end

  # ============================================================================
  # List Extraction Tests
  # ============================================================================

  describe "extract_list/1" do
    test "extracts empty list" do
      result = Literal.extract_list([])
      assert result.type == :list
      assert result.value == []
      assert result.metadata.cons_cell == false
      assert result.metadata.length == 0
    end

    test "extracts simple list" do
      result = Literal.extract_list([1, 2, 3])
      assert result.type == :list
      assert result.value == [1, 2, 3]
      assert result.metadata.cons_cell == false
      assert result.metadata.length == 3
    end

    test "extracts nested list" do
      result = Literal.extract_list([[1, 2], [3, 4]])
      assert result.type == :list
      assert result.value == [[1, 2], [3, 4]]
      assert result.metadata.length == 2
    end

    test "extracts cons cell notation" do
      # AST for [head | tail]
      ast = [{:|, [], [1, {:rest, [], Elixir}]}]

      result = Literal.extract_list(ast)
      assert result.type == :list
      assert result.metadata.cons_cell == true
      assert result.metadata.length == nil
    end
  end

  # ============================================================================
  # Tuple Extraction Tests
  # ============================================================================

  describe "extract_tuple/1" do
    test "extracts 2-element tuple" do
      result = Literal.extract_tuple({1, 2})
      assert result.type == :tuple
      assert result.value == {1, 2}
      assert result.metadata.size == 2
    end

    test "extracts tuple with atom" do
      result = Literal.extract_tuple({:ok, "value"})
      assert result.type == :tuple
      assert result.value == {:ok, "value"}
      assert result.metadata.size == 2
    end

    test "extracts explicit tuple AST form" do
      # AST for {1, 2, 3, 4}
      ast = {:{}, [], [1, 2, 3, 4]}

      result = Literal.extract_tuple(ast)
      assert result.type == :tuple
      assert result.value == {1, 2, 3, 4}
      assert result.metadata.size == 4
      assert result.metadata.ast_form == :explicit
    end

    test "extracts empty tuple" do
      ast = {:{}, [], []}
      result = Literal.extract_tuple(ast)
      assert result.type == :tuple
      assert result.value == {}
      assert result.metadata.size == 0
    end
  end

  # ============================================================================
  # Map Extraction Tests
  # ============================================================================

  describe "extract_map/1" do
    test "extracts empty map" do
      ast = {:%{}, [], []}

      result = Literal.extract_map(ast)
      assert result.type == :map
      assert result.value == []
      assert result.metadata.pair_count == 0
    end

    test "extracts map with atom keys" do
      ast = {:%{}, [], [a: 1, b: 2]}

      result = Literal.extract_map(ast)
      assert result.type == :map
      assert result.value == [a: 1, b: 2]
      assert result.metadata.pair_count == 2
      assert :atom in result.metadata.key_types
    end

    test "extracts map with string keys" do
      ast = {:%{}, [], [{"key", "value"}]}

      result = Literal.extract_map(ast)
      assert result.type == :map
      assert result.value == [{"key", "value"}]
      assert :string in result.metadata.key_types
    end

    test "extracts map with mixed keys" do
      ast = {:%{}, [], [{:atom_key, 1}, {"string_key", 2}]}

      result = Literal.extract_map(ast)
      assert result.type == :map
      assert :atom in result.metadata.key_types
      assert :string in result.metadata.key_types
    end
  end

  # ============================================================================
  # Keyword List Extraction Tests
  # ============================================================================

  describe "extract_keyword_list/1" do
    test "extracts keyword list" do
      result = Literal.extract_keyword_list(name: "John", age: 30)
      assert result.type == :keyword_list
      assert result.value == [name: "John", age: 30]
      assert result.metadata.keys == [:name, :age]
      assert result.metadata.length == 2
    end

    test "extracts single-element keyword list" do
      result = Literal.extract_keyword_list(key: "value")
      assert result.type == :keyword_list
      assert result.metadata.keys == [:key]
    end

    test "extracts keyword list with duplicate keys" do
      result = Literal.extract_keyword_list(a: 1, a: 2)
      assert result.type == :keyword_list
      assert result.metadata.keys == [:a, :a]
    end
  end

  # ============================================================================
  # Binary Extraction Tests
  # ============================================================================

  describe "extract_binary/1" do
    test "extracts simple binary" do
      ast = {:<<>>, [], [1, 2, 3]}

      result = Literal.extract_binary(ast)
      assert result.type == :binary
      assert result.metadata.segments == [1, 2, 3]
      assert result.metadata.has_size_specs == false
    end

    test "extracts binary with string content" do
      ast = {:<<>>, [], ["hello"]}

      result = Literal.extract_binary(ast)
      assert result.type == :binary
      assert result.metadata.segments == ["hello"]
    end

    test "extracts binary with size specs" do
      # AST for <<x::size(8)>>
      ast = {:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:size, [], [8]}]}]}

      result = Literal.extract_binary(ast)
      assert result.type == :binary
      assert result.metadata.has_size_specs == true
    end

    test "extracts empty binary" do
      ast = {:<<>>, [], []}

      result = Literal.extract_binary(ast)
      assert result.type == :binary
      assert result.metadata.segments == []
    end
  end

  # ============================================================================
  # Charlist Extraction Tests
  # ============================================================================

  describe "extract_charlist/1" do
    test "extracts charlist" do
      ast = {:sigil_c, [delimiter: "\""], [{:<<>>, [], ["hello"]}, []]}

      result = Literal.extract_charlist(ast)
      assert result.type == :charlist
      assert result.value == ~c"hello"
      assert result.metadata.content == "hello"
      assert result.metadata.delimiter == "\""
    end

    test "extracts charlist with different delimiter" do
      ast = {:sigil_c, [delimiter: "("], [{:<<>>, [], ["test"]}, []]}

      result = Literal.extract_charlist(ast)
      assert result.type == :charlist
      assert result.metadata.delimiter == "("
    end
  end

  # ============================================================================
  # Sigil Extraction Tests
  # ============================================================================

  describe "extract_sigil/1" do
    test "extracts regex sigil" do
      ast = {:sigil_r, [delimiter: "/"], [{:<<>>, [], ["pattern"]}, []]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "r"
      assert result.metadata.content == "pattern"
      assert result.metadata.modifiers == []
    end

    test "extracts regex sigil with modifiers" do
      ast = {:sigil_r, [delimiter: "/"], [{:<<>>, [], ["pattern"]}, ~c"i"]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.modifiers == ~c"i"
    end

    test "extracts string sigil" do
      ast = {:sigil_s, [delimiter: "("], [{:<<>>, [], ["string"]}, []]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "s"
      assert result.metadata.content == "string"
    end

    test "extracts word list sigil" do
      ast = {:sigil_w, [delimiter: "("], [{:<<>>, [], ["word list"]}, []]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "w"
      assert result.metadata.content == "word list"
    end

    test "extracts date sigil" do
      ast = {:sigil_D, [delimiter: "["], [{:<<>>, [], ["2024-01-01"]}, []]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "D"
      assert result.metadata.content == "2024-01-01"
    end

    test "extracts uppercase sigil" do
      ast = {:sigil_W, [delimiter: "("], [{:<<>>, [], ["words"]}, []]}

      result = Literal.extract_sigil(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "W"
    end
  end

  # ============================================================================
  # Range Extraction Tests
  # ============================================================================

  describe "extract_range/1" do
    test "extracts simple range" do
      ast = {:.., [], [1, 10]}

      result = Literal.extract_range(ast)
      assert result.type == :range
      assert result.value == 1..10
      assert result.metadata.range_start == 1
      assert result.metadata.range_end == 10
      assert result.metadata.range_step == nil
    end

    test "extracts range with step" do
      ast = {:..//, [], [1, 10, 2]}

      result = Literal.extract_range(ast)
      assert result.type == :range
      assert result.value == 1..10//2
      assert result.metadata.range_start == 1
      assert result.metadata.range_end == 10
      assert result.metadata.range_step == 2
    end

    test "extracts descending range" do
      ast = {:.., [], [10, 1]}

      result = Literal.extract_range(ast)
      assert result.type == :range
      assert result.metadata.range_start == 10
      assert result.metadata.range_end == 1
    end

    test "extracts range with negative step" do
      ast = {:..//, [], [10, 1, -1]}

      result = Literal.extract_range(ast)
      assert result.type == :range
      assert result.metadata.range_step == -1
    end
  end

  # ============================================================================
  # Type Detection Tests
  # ============================================================================

  describe "literal_type/1" do
    test "identifies atom" do
      assert Literal.literal_type(:ok) == :atom
      assert Literal.literal_type(true) == :atom
      assert Literal.literal_type(nil) == :atom
    end

    test "identifies integer" do
      assert Literal.literal_type(42) == :integer
      assert Literal.literal_type(-1) == :integer
    end

    test "identifies float" do
      assert Literal.literal_type(3.14) == :float
    end

    test "identifies string" do
      assert Literal.literal_type("hello") == :string
    end

    test "identifies list" do
      assert Literal.literal_type([1, 2, 3]) == :list
    end

    test "identifies keyword list" do
      assert Literal.literal_type(a: 1, b: 2) == :keyword_list
    end

    test "identifies tuple" do
      assert Literal.literal_type({1, 2}) == :tuple
    end

    test "identifies map AST" do
      assert Literal.literal_type({:%{}, [], [a: 1]}) == :map
    end

    test "identifies sigil AST" do
      assert Literal.literal_type({:sigil_r, [], [{:<<>>, [], ["pattern"]}, []]}) == :sigil
    end

    test "identifies charlist AST" do
      assert Literal.literal_type({:sigil_c, [], [{:<<>>, [], ["hello"]}, []]}) == :charlist
    end

    test "identifies range AST" do
      assert Literal.literal_type({:.., [], [1, 10]}) == :range
      assert Literal.literal_type({:..//, [], [1, 10, 2]}) == :range
    end

    test "returns nil for non-literals" do
      assert Literal.literal_type({:def, [], [{:foo, [], nil}]}) == nil
      assert Literal.literal_type({:defmodule, [], [nil]}) == nil
    end
  end

  # ============================================================================
  # Guard Function Tests
  # ============================================================================

  describe "literal?/1" do
    test "returns true for literals" do
      assert Literal.literal?(:ok)
      assert Literal.literal?(42)
      assert Literal.literal?(3.14)
      assert Literal.literal?("hello")
      assert Literal.literal?([1, 2, 3])
      assert Literal.literal?({1, 2})
      assert Literal.literal?(a: 1)
      assert Literal.literal?({:%{}, [], [a: 1]})
      assert Literal.literal?({:.., [], [1, 10]})
    end

    test "returns false for non-literals" do
      assert not Literal.literal?({:def, [], [{:foo, [], nil}]})
      assert not Literal.literal?({:defmodule, [], [nil]})
      assert not Literal.literal?({:if, [], [true, [do: 1]]})
    end
  end

  # ============================================================================
  # Main Extract Function Tests
  # ============================================================================

  describe "extract/1" do
    test "returns {:ok, result} for valid literal" do
      assert {:ok, %Literal{type: :atom}} = Literal.extract(:ok)
    end

    test "returns {:error, _} for non-literal" do
      assert {:error, _} = Literal.extract({:def, [], [{:foo, [], nil}]})
    end

    test "dispatches to correct extractor" do
      assert {:ok, %Literal{type: :atom}} = Literal.extract(:ok)
      assert {:ok, %Literal{type: :integer}} = Literal.extract(42)
      assert {:ok, %Literal{type: :float}} = Literal.extract(3.14)
      assert {:ok, %Literal{type: :string}} = Literal.extract("hello")
      assert {:ok, %Literal{type: :list}} = Literal.extract([1, 2])
      assert {:ok, %Literal{type: :keyword_list}} = Literal.extract(a: 1)
      assert {:ok, %Literal{type: :tuple}} = Literal.extract({1, 2})
      assert {:ok, %Literal{type: :map}} = Literal.extract({:%{}, [], []})
      assert {:ok, %Literal{type: :range}} = Literal.extract({:.., [], [1, 10]})
    end
  end

  describe "extract!/1" do
    test "returns result for valid literal" do
      result = Literal.extract!(:ok)
      assert result.type == :atom
    end

    test "raises for non-literal" do
      assert_raise ArgumentError, fn ->
        Literal.extract!({:def, [], [{:foo, [], nil}]})
      end
    end
  end

  # ============================================================================
  # Edge Case Tests
  # ============================================================================

  describe "edge cases" do
    test "empty collections" do
      assert {:ok, %Literal{type: :list, value: []}} = Literal.extract([])
      assert {:ok, %Literal{type: :map}} = Literal.extract({:%{}, [], []})
      assert {:ok, %Literal{type: :binary}} = Literal.extract({:<<>>, [], []})
    end

    test "distinguishes keyword list from regular list" do
      # Keyword list
      assert {:ok, %Literal{type: :keyword_list}} = Literal.extract(a: 1)

      # Regular list with tuples (not keyword list because keys aren't atoms in correct position)
      assert {:ok, %Literal{type: :list}} = Literal.extract([{1, :a}])
    end

    test "empty keyword list is a list" do
      # Empty list is not a keyword list
      assert {:ok, %Literal{type: :list}} = Literal.extract([])
    end

    test "handles unicode strings" do
      result = Literal.extract_string("hello 世界")
      assert result.type == :string
      assert result.value == "hello 世界"
    end
  end
end
