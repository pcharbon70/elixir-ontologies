defmodule ElixirOntologies.Extractors.ParameterTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Parameter

  doctest Parameter

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "parameter?/1" do
    test "returns true for simple variable" do
      assert Parameter.parameter?({:x, [], nil})
    end

    test "returns true for ignored variable" do
      assert Parameter.parameter?({:_, [], nil})
      assert Parameter.parameter?({:_unused, [], nil})
    end

    test "returns true for default parameter" do
      ast = {:\\, [], [{:x, [], nil}, 10]}
      assert Parameter.parameter?(ast)
    end

    test "returns true for pin expression" do
      ast = {:^, [], [{:x, [], nil}]}
      assert Parameter.parameter?(ast)
    end

    test "returns true for tuple pattern" do
      ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}]}
      assert Parameter.parameter?(ast)
    end

    test "returns true for map pattern" do
      ast = {:%{}, [], [key: {:value, [], nil}]}
      assert Parameter.parameter?(ast)
    end

    test "returns true for list pattern" do
      assert Parameter.parameter?([{:a, [], nil}, {:b, [], nil}])
    end

    test "returns false for nil" do
      refute Parameter.parameter?(nil)
    end
  end

  # ===========================================================================
  # Simple Variable Extraction Tests
  # ===========================================================================

  describe "extract/2 simple variables" do
    test "extracts simple variable parameter" do
      ast = {:x, [], nil}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :x
      assert result.type == :simple
      assert result.position == 0
    end

    test "extracts variable with context" do
      ast = {:name, [line: 1], Elixir}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :name
      assert result.type == :simple
    end

    test "respects position option" do
      ast = {:y, [], nil}

      assert {:ok, result} = Parameter.extract(ast, position: 2)
      assert result.position == 2
    end

    test "extracts ignored variable" do
      ast = {:_unused, [], nil}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :_unused
      assert result.metadata.is_ignored == true
    end

    test "extracts underscore" do
      ast = {:_, [], nil}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :_
      assert result.metadata.is_ignored == true
    end
  end

  # ===========================================================================
  # Default Parameter Tests
  # ===========================================================================

  describe "extract/2 default parameters" do
    test "extracts default parameter with integer" do
      ast = {:\\, [], [{:timeout, [], nil}, 5000]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :timeout
      assert result.type == :default
      assert result.default_value == 5000
      assert result.metadata.has_default == true
    end

    test "extracts default parameter with string" do
      ast = {:\\, [], [{:name, [], nil}, "default"]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :name
      assert result.default_value == "default"
    end

    test "extracts default parameter with nil" do
      ast = {:\\, [], [{:opts, [], nil}, nil]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :opts
      assert result.default_value == nil
      assert result.type == :default
    end

    test "extracts default parameter with list" do
      ast = {:\\, [], [{:items, [], nil}, []]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :items
      assert result.default_value == []
    end

    test "extracts default parameter with expression" do
      default_expr = {:+, [], [1, 2]}
      ast = {:\\, [], [{:value, [], nil}, default_expr]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :value
      assert result.default_value == default_expr
    end
  end

  # ===========================================================================
  # Pin Expression Tests
  # ===========================================================================

  describe "extract/2 pin expressions" do
    test "extracts pin expression" do
      ast = {:^, [], [{:x, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.name == :x
      assert result.type == :pin
    end

    test "pin expression has no default" do
      ast = {:^, [], [{:value, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.default_value == nil
      assert result.metadata.has_default == false
    end
  end

  # ===========================================================================
  # Pattern Parameter Tests
  # ===========================================================================

  describe "extract/2 tuple patterns" do
    test "extracts 3-tuple pattern" do
      ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.name == nil
      assert result.metadata.pattern_type == :tuple
    end

    test "extracts 2-tuple pattern" do
      ast = {{:a, [], nil}, {:b, [], nil}}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :tuple
    end
  end

  describe "extract/2 map patterns" do
    test "extracts map pattern" do
      ast = {:%{}, [], [key: {:value, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :map
    end

    test "extracts empty map pattern" do
      ast = {:%{}, [], []}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :map
    end
  end

  describe "extract/2 struct patterns" do
    test "extracts struct pattern" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:name, [], nil}]}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :struct
    end
  end

  describe "extract/2 list patterns" do
    test "extracts list literal pattern" do
      ast = [{:a, [], nil}, {:b, [], nil}]

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :list
    end

    test "extracts cons pattern" do
      ast = {:|, [], [{:head, [], nil}, {:tail, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :cons
    end
  end

  describe "extract/2 binary patterns" do
    test "extracts binary pattern" do
      ast = {:<<>>, [], [{:bytes, [], nil}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :binary
    end
  end

  describe "extract/2 match patterns" do
    test "extracts match pattern" do
      # pattern = value in parameter
      ast = {:=, [], [{:result, [], nil}, {:ok, {:data, [], nil}}]}

      assert {:ok, result} = Parameter.extract(ast)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :match
    end
  end

  describe "extract/2 literal patterns" do
    test "extracts atom literal" do
      assert {:ok, result} = Parameter.extract(:ok)
      assert result.type == :pattern
      assert result.name == nil
      assert result.metadata.pattern_type == :literal
    end

    test "extracts integer literal" do
      assert {:ok, result} = Parameter.extract(42)
      assert result.type == :pattern
      assert result.metadata.pattern_type == :literal
    end

    test "extracts string literal" do
      assert {:ok, result} = Parameter.extract("hello")
      assert result.type == :pattern
      assert result.metadata.pattern_type == :literal
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all parameters with positions" do
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]

      results = Parameter.extract_all(params)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:a, :b, :c]
      assert Enum.map(results, & &1.position) == [0, 1, 2]
    end

    test "handles mixed parameter types" do
      params = [
        {:x, [], nil},
        {:\\, [], [{:y, [], nil}, 10]},
        {:{}, [], [{:a, [], nil}, {:b, [], nil}]}
      ]

      results = Parameter.extract_all(params)
      assert length(results) == 3
      assert Enum.map(results, & &1.type) == [:simple, :default, :pattern]
    end

    test "returns empty list for nil" do
      assert Parameter.extract_all(nil) == []
    end

    test "returns empty list for empty list" do
      assert Parameter.extract_all([]) == []
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "has_default?/1" do
    test "returns true for default parameter" do
      ast = {:\\, [], [{:x, [], nil}, 10]}
      {:ok, param} = Parameter.extract(ast)
      assert Parameter.has_default?(param)
    end

    test "returns false for simple parameter" do
      ast = {:x, [], nil}
      {:ok, param} = Parameter.extract(ast)
      refute Parameter.has_default?(param)
    end
  end

  describe "is_pattern_param?/1" do
    test "returns true for pattern parameter" do
      ast = {:{}, [], [{:a, [], nil}]}
      {:ok, param} = Parameter.extract(ast)
      assert Parameter.is_pattern_param?(param)
    end

    test "returns false for simple parameter" do
      ast = {:x, [], nil}
      {:ok, param} = Parameter.extract(ast)
      refute Parameter.is_pattern_param?(param)
    end
  end

  describe "is_ignored?/1" do
    test "returns true for underscore" do
      ast = {:_, [], nil}
      {:ok, param} = Parameter.extract(ast)
      assert Parameter.is_ignored?(param)
    end

    test "returns true for _prefixed" do
      ast = {:_unused, [], nil}
      {:ok, param} = Parameter.extract(ast)
      assert Parameter.is_ignored?(param)
    end

    test "returns false for regular variable" do
      ast = {:x, [], nil}
      {:ok, param} = Parameter.extract(ast)
      refute Parameter.is_ignored?(param)
    end

    test "works with atom directly" do
      assert Parameter.is_ignored?(:_)
      assert Parameter.is_ignored?(:_unused)
      refute Parameter.is_ignored?(:x)
    end
  end

  describe "param_id/1" do
    test "returns name@position for named parameter" do
      ast = {:foo, [], nil}
      {:ok, param} = Parameter.extract(ast, position: 2)
      assert Parameter.param_id(param) == "foo@2"
    end

    test "returns pattern@position for pattern parameter" do
      ast = {:{}, [], [{:a, [], nil}]}
      {:ok, param} = Parameter.extract(ast, position: 0)
      assert Parameter.param_id(param) == "pattern@0"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    # Most expressions can be interpreted as parameters in Elixir,
    # so we mainly test edge cases here
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:x, [], nil}
      result = Parameter.extract!(ast)
      assert result.name == :x
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts parameters from quoted function" do
      {:def, _, [{:foo, _, params}, _]} =
        quote do
          def foo(a, b, c), do: {a, b, c}
        end

      results = Parameter.extract_all(params)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:a, :b, :c]
    end

    test "extracts default parameter from quoted function" do
      {:def, _, [{:bar, _, params}, _]} =
        quote do
          def bar(x, y \\ 10), do: x + y
        end

      results = Parameter.extract_all(params)
      assert length(results) == 2

      [first, second] = results
      assert first.name == :x
      assert first.type == :simple
      assert second.name == :y
      assert second.type == :default
      assert second.default_value == 10
    end

    test "extracts pattern parameter from quoted function" do
      {:def, _, [{:process, _, params}, _]} =
        quote do
          def process({:ok, data}), do: data
        end

      # Note: 2-tuples like {:ok, data} become {:ok, var_ast} which is a tagged tuple
      results = Parameter.extract_all(params)
      assert length(results) == 1

      [param] = results
      assert param.type == :pattern
      # 2-element tuple with atom first is a tagged tuple pattern
      assert param.metadata.pattern_type == :tagged_tuple
    end

    test "extracts map pattern from quoted function" do
      {:def, _, [{:handle, _, params}, _]} =
        quote do
          def handle(%{action: action, data: data}), do: {action, data}
        end

      results = Parameter.extract_all(params)
      assert length(results) == 1

      [param] = results
      assert param.type == :pattern
      assert param.metadata.pattern_type == :map
    end
  end
end
