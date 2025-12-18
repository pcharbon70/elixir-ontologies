defmodule ElixirOntologies.Extractors.PatternTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Pattern

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "pattern?/1" do
    test "returns true for variable pattern" do
      assert Pattern.pattern?({:x, [], Elixir})
    end

    test "returns true for wildcard pattern" do
      assert Pattern.pattern?({:_, [], Elixir})
    end

    test "returns true for pin pattern" do
      assert Pattern.pattern?({:^, [], [{:x, [], Elixir}]})
    end

    test "returns true for literal patterns" do
      assert Pattern.pattern?(:ok)
      assert Pattern.pattern?(42)
      assert Pattern.pattern?(3.14)
      assert Pattern.pattern?("hello")
    end

    test "returns true for tuple pattern" do
      assert Pattern.pattern?({{:a, [], nil}, {:b, [], nil}})
    end

    test "returns true for list pattern" do
      assert Pattern.pattern?([{:a, [], nil}, {:b, [], nil}])
    end

    test "returns true for map pattern" do
      assert Pattern.pattern?({:%{}, [], [a: {:v, [], nil}]})
    end

    test "returns true for struct pattern" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      assert Pattern.pattern?(ast)
    end

    test "returns true for binary pattern" do
      assert Pattern.pattern?({:<<>>, [], [{:a, [], nil}]})
    end

    test "returns true for as pattern" do
      ast = {:=, [], [{:ok, {:_, [], nil}}, {:result, [], nil}]}
      assert Pattern.pattern?(ast)
    end

    test "returns true for guard pattern" do
      ast = {:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}
      assert Pattern.pattern?(ast)
    end

    test "returns false for non-pattern nodes" do
      refute Pattern.pattern?({:def, [], [{:foo, [], nil}]})
      refute Pattern.pattern?({:defmodule, [], [{:__aliases__, [], [:Foo]}, []]})
    end
  end

  describe "pattern_type/1" do
    test "returns :variable for variable pattern" do
      assert Pattern.pattern_type({:x, [], Elixir}) == :variable
      assert Pattern.pattern_type({:name, [], nil}) == :variable
    end

    test "returns :wildcard for wildcard pattern" do
      assert Pattern.pattern_type({:_, [], Elixir}) == :wildcard
      assert Pattern.pattern_type({:_, [], nil}) == :wildcard
    end

    test "returns :pin for pin pattern" do
      assert Pattern.pattern_type({:^, [], [{:x, [], Elixir}]}) == :pin
    end

    test "returns :literal for literals" do
      assert Pattern.pattern_type(:ok) == :literal
      assert Pattern.pattern_type(42) == :literal
      assert Pattern.pattern_type(3.14) == :literal
      assert Pattern.pattern_type("string") == :literal
      assert Pattern.pattern_type(true) == :literal
      assert Pattern.pattern_type(false) == :literal
      assert Pattern.pattern_type(nil) == :literal
    end

    test "returns :tuple for tuple patterns" do
      assert Pattern.pattern_type({{:a, [], nil}, {:b, [], nil}}) == :tuple

      assert Pattern.pattern_type({:{}, [], [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]}) ==
               :tuple
    end

    test "returns :list for list patterns" do
      assert Pattern.pattern_type([{:a, [], nil}]) == :list
      assert Pattern.pattern_type([]) == :list
    end

    test "returns :map for map patterns" do
      assert Pattern.pattern_type({:%{}, [], []}) == :map
      assert Pattern.pattern_type({:%{}, [], [a: {:v, [], nil}]}) == :map
    end

    test "returns :struct for struct patterns" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      assert Pattern.pattern_type(ast) == :struct
    end

    test "returns :binary for binary patterns" do
      assert Pattern.pattern_type({:<<>>, [], []}) == :binary
      assert Pattern.pattern_type({:<<>>, [], [{:x, [], nil}]}) == :binary
    end

    test "returns :as for as patterns" do
      ast = {:=, [], [{:left, [], nil}, {:right, [], nil}]}
      assert Pattern.pattern_type(ast) == :as
    end

    test "returns :guard for guard patterns" do
      ast = {:when, [], [{:x, [], nil}, true]}
      assert Pattern.pattern_type(ast) == :guard
    end

    test "returns nil for non-patterns" do
      assert Pattern.pattern_type({:def, [], nil}) == nil
    end
  end

  # ===========================================================================
  # Variable Pattern Tests
  # ===========================================================================

  describe "extract_variable/1" do
    test "extracts simple variable" do
      result = Pattern.extract_variable({:x, [], Elixir})

      assert result.type == :variable
      assert result.metadata.variable_name == :x
      assert result.bindings == [:x]
    end

    test "extracts variable with nil context" do
      result = Pattern.extract_variable({:name, [], nil})

      assert result.type == :variable
      assert result.metadata.variable_name == :name
      assert result.bindings == [:name]
    end

    test "preserves variable AST as value" do
      ast = {:x, [], Elixir}
      result = Pattern.extract_variable(ast)

      assert result.value == ast
    end
  end

  # ===========================================================================
  # Wildcard Pattern Tests
  # ===========================================================================

  describe "extract_wildcard/1" do
    test "extracts wildcard pattern" do
      result = Pattern.extract_wildcard({:_, [], Elixir})

      assert result.type == :wildcard
      assert result.bindings == []
    end

    test "wildcard with nil context" do
      result = Pattern.extract_wildcard({:_, [], nil})

      assert result.type == :wildcard
      assert result.bindings == []
    end
  end

  # ===========================================================================
  # Pin Pattern Tests
  # ===========================================================================

  describe "extract_pin/1" do
    test "extracts pinned variable" do
      result = Pattern.extract_pin({:^, [], [{:x, [], Elixir}]})

      assert result.type == :pin
      assert result.metadata.pinned_variable == :x
      assert result.bindings == []
    end

    test "pin does not create bindings" do
      result = Pattern.extract_pin({:^, [], [{:existing, [], nil}]})

      assert result.bindings == []
    end
  end

  # ===========================================================================
  # Literal Pattern Tests
  # ===========================================================================

  describe "extract_literal/1" do
    test "extracts atom literal" do
      result = Pattern.extract_literal(:ok)

      assert result.type == :literal
      assert result.value == :ok
      assert result.metadata.literal_type == :atom
      assert result.bindings == []
    end

    test "extracts boolean literals" do
      true_result = Pattern.extract_literal(true)
      false_result = Pattern.extract_literal(false)

      assert true_result.metadata.literal_type == :boolean
      assert false_result.metadata.literal_type == :boolean
    end

    test "extracts nil literal" do
      result = Pattern.extract_literal(nil)

      assert result.value == nil
      assert result.metadata.literal_type == nil
    end

    test "extracts integer literal" do
      result = Pattern.extract_literal(42)

      assert result.type == :literal
      assert result.value == 42
      assert result.metadata.literal_type == :integer
    end

    test "extracts float literal" do
      result = Pattern.extract_literal(3.14)

      assert result.type == :literal
      assert result.value == 3.14
      assert result.metadata.literal_type == :float
    end

    test "extracts string literal" do
      result = Pattern.extract_literal("hello")

      assert result.type == :literal
      assert result.value == "hello"
      assert result.metadata.literal_type == :string
    end
  end

  # ===========================================================================
  # Tuple Pattern Tests
  # ===========================================================================

  describe "extract_tuple/1" do
    test "extracts 2-element tuple pattern" do
      ast = {{:a, [], nil}, {:b, [], nil}}
      result = Pattern.extract_tuple(ast)

      assert result.type == :tuple
      assert result.metadata.size == 2
      assert :a in result.bindings
      assert :b in result.bindings
    end

    test "extracts 3+ element tuple pattern" do
      ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]}
      result = Pattern.extract_tuple(ast)

      assert result.type == :tuple
      assert result.metadata.size == 3
      assert :a in result.bindings
      assert :b in result.bindings
      assert :c in result.bindings
    end

    test "extracts tuple with literal and variable" do
      # {:ok, value}
      ast = {:ok, {:value, [], nil}}
      result = Pattern.extract_tuple(ast)

      assert result.type == :tuple
      assert :value in result.bindings
    end

    test "extracts nested tuple pattern" do
      # {{a, b}, c}
      inner = {{:a, [], nil}, {:b, [], nil}}
      ast = {inner, {:c, [], nil}}
      result = Pattern.extract_tuple(ast)

      assert result.type == :tuple
      assert :a in result.bindings
      assert :b in result.bindings
      assert :c in result.bindings
    end

    test "extracts empty tuple pattern" do
      ast = {:{}, [], []}
      result = Pattern.extract_tuple(ast)

      assert result.type == :tuple
      assert result.metadata.size == 0
      assert result.bindings == []
    end
  end

  # ===========================================================================
  # List Pattern Tests
  # ===========================================================================

  describe "extract_list/1" do
    test "extracts simple list pattern" do
      ast = [{:a, [], nil}, {:b, [], nil}]
      result = Pattern.extract_list(ast)

      assert result.type == :list
      assert result.metadata.has_cons_cell == false
      assert result.metadata.length == 2
      assert :a in result.bindings
      assert :b in result.bindings
    end

    test "extracts empty list pattern" do
      result = Pattern.extract_list([])

      assert result.type == :list
      assert result.metadata.has_cons_cell == false
      assert result.metadata.length == 0
      assert result.bindings == []
    end

    test "extracts list cons pattern [h | t]" do
      # [h | t]
      ast = [{:|, [], [{:h, [], nil}, {:t, [], nil}]}]
      result = Pattern.extract_list(ast)

      assert result.type == :list
      assert result.metadata.has_cons_cell == true
      assert result.metadata.length == nil
      assert :h in result.bindings
      assert :t in result.bindings
    end

    test "extracts list with fixed head and tail" do
      # [a, b | rest]
      ast = [{:a, [], nil}, {:|, [], [{:b, [], nil}, {:rest, [], nil}]}]
      result = Pattern.extract_list(ast)

      assert result.type == :list
      assert result.metadata.has_cons_cell == true
      assert :a in result.bindings
      assert :b in result.bindings
      assert :rest in result.bindings
    end

    test "extracts nested list pattern" do
      # [[a], b]
      inner = [{:a, [], nil}]
      ast = [inner, {:b, [], nil}]
      result = Pattern.extract_list(ast)

      assert result.type == :list
      assert :a in result.bindings
      assert :b in result.bindings
    end
  end

  # ===========================================================================
  # Map Pattern Tests
  # ===========================================================================

  describe "extract_map/1" do
    test "extracts empty map pattern" do
      ast = {:%{}, [], []}
      result = Pattern.extract_map(ast)

      assert result.type == :map
      assert result.metadata.pair_count == 0
      assert result.bindings == []
    end

    test "extracts map with atom keys" do
      # %{a: v}
      ast = {:%{}, [], [a: {:v, [], nil}]}
      result = Pattern.extract_map(ast)

      assert result.type == :map
      assert result.metadata.pair_count == 1
      assert :v in result.bindings
    end

    test "extracts map with multiple pairs" do
      # %{a: x, b: y}
      ast = {:%{}, [], [a: {:x, [], nil}, b: {:y, [], nil}]}
      result = Pattern.extract_map(ast)

      assert result.type == :map
      assert result.metadata.pair_count == 2
      assert :x in result.bindings
      assert :y in result.bindings
    end

    test "extracts map with nested patterns" do
      # %{nested: {a, b}}
      inner = {{:a, [], nil}, {:b, [], nil}}
      ast = {:%{}, [], [nested: inner]}
      result = Pattern.extract_map(ast)

      assert result.type == :map
      assert :a in result.bindings
      assert :b in result.bindings
    end
  end

  # ===========================================================================
  # Struct Pattern Tests
  # ===========================================================================

  describe "extract_struct/1" do
    test "extracts named struct pattern" do
      # %User{}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      result = Pattern.extract_struct(ast)

      assert result.type == :struct
      assert result.metadata.struct_name == [:User]
      assert result.metadata.is_any_struct == false
      assert result.bindings == []
    end

    test "extracts struct with field patterns" do
      # %User{name: name}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:name, [], nil}]}]}
      result = Pattern.extract_struct(ast)

      assert result.type == :struct
      assert result.metadata.struct_name == [:User]
      assert :name in result.bindings
    end

    test "extracts any struct pattern %_" do
      # %_{field: val}
      ast = {:%, [], [{:_, [], nil}, {:%{}, [], [field: {:val, [], nil}]}]}
      result = Pattern.extract_struct(ast)

      assert result.type == :struct
      assert result.metadata.struct_name == :any
      assert result.metadata.is_any_struct == true
      assert :val in result.bindings
    end

    test "extracts namespaced struct pattern" do
      # %MyApp.User{}
      ast = {:%, [], [{:__aliases__, [], [:MyApp, :User]}, {:%{}, [], []}]}
      result = Pattern.extract_struct(ast)

      assert result.type == :struct
      assert result.metadata.struct_name == [:MyApp, :User]
    end
  end

  # ===========================================================================
  # Binary Pattern Tests
  # ===========================================================================

  describe "extract_binary/1" do
    test "extracts empty binary pattern" do
      ast = {:<<>>, [], []}
      result = Pattern.extract_binary(ast)

      assert result.type == :binary
      assert result.metadata.has_specifiers == false
      assert result.bindings == []
    end

    test "extracts simple binary pattern" do
      # <<a, b>>
      ast = {:<<>>, [], [{:a, [], nil}, {:b, [], nil}]}
      result = Pattern.extract_binary(ast)

      assert result.type == :binary
      assert :a in result.bindings
      assert :b in result.bindings
    end

    test "extracts binary with specifiers" do
      # <<x::binary-size(4)>>
      ast = {:<<>>, [], [{:"::", [], [{:x, [], nil}, {:binary, [], nil}]}]}
      result = Pattern.extract_binary(ast)

      assert result.type == :binary
      assert result.metadata.has_specifiers == true
      assert :x in result.bindings
    end

    test "extracts binary with multiple segments" do
      # <<a::8, b::binary>>
      segment1 = {:"::", [], [{:a, [], nil}, 8]}
      segment2 = {:"::", [], [{:b, [], nil}, {:binary, [], nil}]}
      ast = {:<<>>, [], [segment1, segment2]}
      result = Pattern.extract_binary(ast)

      assert result.type == :binary
      assert result.metadata.has_specifiers == true
      assert :a in result.bindings
      assert :b in result.bindings
    end
  end

  # ===========================================================================
  # As Pattern Tests
  # ===========================================================================

  describe "extract_as/1" do
    test "extracts as pattern with variable on right" do
      # {:ok, _} = result
      left = {:ok, {:_, [], nil}}
      ast = {:=, [], [left, {:result, [], nil}]}
      result = Pattern.extract_as(ast)

      assert result.type == :as
      assert :result in result.bindings
      assert result.metadata.left_pattern == left
      assert result.metadata.right_pattern == {:result, [], nil}
    end

    test "extracts as pattern bindings from both sides" do
      # {a, b} = {c, d}
      left = {{:a, [], nil}, {:b, [], nil}}
      right = {{:c, [], nil}, {:d, [], nil}}
      ast = {:=, [], [left, right]}
      result = Pattern.extract_as(ast)

      assert result.type == :as
      assert :a in result.bindings
      assert :b in result.bindings
      assert :c in result.bindings
      assert :d in result.bindings
    end

    test "extracts nested as patterns" do
      # {:ok, value} = x
      left = {:ok, {:value, [], nil}}
      ast = {:=, [], [left, {:x, [], nil}]}
      result = Pattern.extract_as(ast)

      assert result.type == :as
      assert :value in result.bindings
      assert :x in result.bindings
    end
  end

  # ===========================================================================
  # Guard Pattern Tests
  # ===========================================================================

  describe "extract_guard/1" do
    test "extracts simple guard" do
      # x when is_integer(x)
      ast = {:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}
      result = Pattern.extract_guard(ast)

      assert result.type == :guard
      assert :x in result.bindings
      assert result.metadata.pattern == {:x, [], nil}
      assert result.metadata.guard_expression == {:is_integer, [], [{:x, [], nil}]}
    end

    test "extracts guard with tuple pattern" do
      # {a, b} when a > 0
      pattern = {{:a, [], nil}, {:b, [], nil}}
      guard = {:>, [], [{:a, [], nil}, 0]}
      ast = {:when, [], [pattern, guard]}
      result = Pattern.extract_guard(ast)

      assert result.type == :guard
      assert :a in result.bindings
      assert :b in result.bindings
      assert result.metadata.guard_expression == guard
    end

    test "extracts guard with compound guard expression" do
      # x when is_integer(x) and x > 0
      pattern = {:x, [], nil}
      guard = {:and, [], [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}
      ast = {:when, [], [pattern, guard]}
      result = Pattern.extract_guard(ast)

      assert result.type == :guard
      assert result.metadata.guard_expression == guard
    end
  end

  # ===========================================================================
  # Main Extraction Tests
  # ===========================================================================

  describe "extract/1" do
    test "returns {:ok, result} for valid patterns" do
      assert {:ok, %Pattern{type: :variable}} = Pattern.extract({:x, [], Elixir})
      assert {:ok, %Pattern{type: :literal}} = Pattern.extract(:ok)
      assert {:ok, %Pattern{type: :list}} = Pattern.extract([1, 2, 3])
    end

    test "returns {:error, reason} for non-patterns" do
      assert {:error, _} = Pattern.extract({:def, [], nil})
    end
  end

  describe "extract!/1" do
    test "returns result for valid patterns" do
      result = Pattern.extract!({:x, [], Elixir})
      assert result.type == :variable
    end

    test "raises ArgumentError for non-patterns" do
      assert_raise ArgumentError, fn ->
        Pattern.extract!({:def, [], nil})
      end
    end
  end

  # ===========================================================================
  # Binding Collection Tests
  # ===========================================================================

  describe "collect_bindings/1" do
    test "collects variable bindings" do
      bindings = Pattern.collect_bindings([{:x, [], nil}, {:y, [], nil}])
      assert :x in bindings
      assert :y in bindings
    end

    test "ignores wildcard" do
      bindings = Pattern.collect_bindings([{:_, [], nil}])
      assert bindings == []
    end

    test "ignores pinned variables" do
      bindings = Pattern.collect_bindings([{:^, [], [{:x, [], nil}]}])
      assert bindings == []
    end

    test "collects from nested structures" do
      # [{a, b}, c]
      nested = {{:a, [], nil}, {:b, [], nil}}
      bindings = Pattern.collect_bindings([[nested, {:c, [], nil}]])

      assert :a in bindings
      assert :b in bindings
      assert :c in bindings
    end

    test "deduplicates bindings" do
      # [x, x]
      bindings = Pattern.collect_bindings([{:x, [], nil}, {:x, [], nil}])
      assert bindings == [:x]
    end

    test "collects from cons cell" do
      # [h | t]
      cons = {:|, [], [{:h, [], nil}, {:t, [], nil}]}
      bindings = Pattern.collect_bindings([[cons]])

      assert :h in bindings
      assert :t in bindings
    end

    test "collects from map values" do
      # %{a: x, b: y}
      map = {:%{}, [], [a: {:x, [], nil}, b: {:y, [], nil}]}
      bindings = Pattern.collect_bindings([map])

      assert :x in bindings
      assert :y in bindings
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles deeply nested patterns" do
      # {{{{a}}}}
      inner = {:a, [], nil}
      level1 = {inner, {:b, [], nil}}
      level2 = {level1, {:c, [], nil}}
      {:ok, result} = Pattern.extract(level2)

      assert result.type == :tuple
      assert :a in result.bindings
      assert :b in result.bindings
      assert :c in result.bindings
    end

    test "handles mixed pattern types" do
      # %{list: [a | b], tuple: {c, d}}
      list = [{:|, [], [{:a, [], nil}, {:b, [], nil}]}]
      tuple = {{:c, [], nil}, {:d, [], nil}}
      ast = {:%{}, [], [list: list, tuple: tuple]}
      {:ok, result} = Pattern.extract(ast)

      assert result.type == :map
      assert :a in result.bindings
      assert :b in result.bindings
      assert :c in result.bindings
      assert :d in result.bindings
    end

    test "handles pattern with all binding types" do
      # {x, _, ^y, z}
      elements = [{:x, [], nil}, {:_, [], nil}, {:^, [], [{:y, [], nil}]}, {:z, [], nil}]
      ast = {:{}, [], elements}
      {:ok, result} = Pattern.extract(ast)

      assert :x in result.bindings
      assert :z in result.bindings
      # _ and ^y don't create bindings
      refute :_ in result.bindings
      refute :y in result.bindings
    end

    test "handles struct with nested struct pattern" do
      # %Outer{inner: %Inner{value: v}}
      inner_struct = {:%, [], [{:__aliases__, [], [:Inner]}, {:%{}, [], [value: {:v, [], nil}]}]}
      ast = {:%, [], [{:__aliases__, [], [:Outer]}, {:%{}, [], [inner: inner_struct]}]}
      {:ok, result} = Pattern.extract(ast)

      assert result.type == :struct
      assert :v in result.bindings
    end
  end
end
