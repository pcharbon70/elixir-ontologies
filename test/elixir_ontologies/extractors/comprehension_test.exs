defmodule ElixirOntologies.Extractors.ComprehensionTest do
  @moduledoc """
  Tests for the Comprehension extractor module.

  These tests verify extraction of for comprehensions including generators,
  filters, and options like :into, :reduce, and :uniq.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Comprehension

  doctest Comprehension

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "comprehension?/1" do
    test "returns true for simple for comprehension" do
      ast = quote do: for(x <- [1, 2, 3], do: x)
      assert Comprehension.comprehension?(ast)
    end

    test "returns true for comprehension with multiple generators" do
      ast = quote do: for(x <- [1, 2], y <- [3, 4], do: {x, y})
      assert Comprehension.comprehension?(ast)
    end

    test "returns true for comprehension with filter" do
      ast = quote do: for(x <- [1, 2, 3], x > 1, do: x)
      assert Comprehension.comprehension?(ast)
    end

    test "returns false for if expression" do
      ast = quote do: if(true, do: 1)
      refute Comprehension.comprehension?(ast)
    end

    test "returns false for case expression" do
      ast = quote do: case(x, do: (y -> y))
      refute Comprehension.comprehension?(ast)
    end

    test "returns false for atoms" do
      refute Comprehension.comprehension?(:for)
    end
  end

  describe "generator?/1" do
    test "returns true for generator expression" do
      ast = {:<-, [], [{:x, [], nil}, [1, 2, 3]]}
      assert Comprehension.generator?(ast)
    end

    test "returns false for comparison expression" do
      ast = {:>, [], [{:x, [], nil}, 0]}
      refute Comprehension.generator?(ast)
    end

    test "returns false for bitstring generator" do
      ast = {:<<>>, [], [{:<-, [], [{:c, [], nil}, "hello"]}]}
      refute Comprehension.generator?(ast)
    end
  end

  describe "bitstring_generator?/1" do
    test "returns true for bitstring generator" do
      ast = {:<<>>, [], [{:<-, [], [{:c, [], nil}, "hello"]}]}
      assert Comprehension.bitstring_generator?(ast)
    end

    test "returns false for regular generator" do
      ast = {:<-, [], [{:x, [], nil}, [1, 2, 3]]}
      refute Comprehension.bitstring_generator?(ast)
    end

    test "returns false for regular binary expression" do
      ast = {:<<>>, [], [1, 2, 3]}
      refute Comprehension.bitstring_generator?(ast)
    end
  end

  # ===========================================================================
  # Simple Comprehension Extraction Tests
  # ===========================================================================

  describe "extract/1 with simple comprehension" do
    test "extracts single generator comprehension" do
      ast = quote do: for(x <- [1, 2, 3], do: x * 2)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.type == :for
      assert length(result.generators) == 1

      [gen] = result.generators
      assert gen.type == :generator
      assert {:x, [], _context} = gen.pattern
      assert gen.enumerable == [1, 2, 3]
    end

    test "extracts body expression" do
      ast = quote do: for(x <- [1, 2], do: x + 1)
      assert {:ok, result} = Comprehension.extract(ast)

      # Body should be the expression x + 1
      assert {:+, _, [{:x, [], _}, 1]} = result.body
    end

    test "has correct metadata for simple comprehension" do
      ast = quote do: for(x <- [1, 2, 3], do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.metadata.generator_count == 1
      assert result.metadata.filter_count == 0
      assert result.metadata.has_into == false
      assert result.metadata.has_reduce == false
      assert result.metadata.has_uniq == false
    end
  end

  # ===========================================================================
  # Multiple Generators Tests
  # ===========================================================================

  describe "extract/1 with multiple generators" do
    test "extracts two generators (nested loop)" do
      ast = quote do: for(x <- [1, 2], y <- [3, 4], do: {x, y})
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.generators) == 2
      assert result.metadata.generator_count == 2

      [gen1, gen2] = result.generators
      assert {:x, [], _} = gen1.pattern
      assert {:y, [], _} = gen2.pattern
    end

    test "extracts three generators" do
      ast = quote do: for(x <- [1], y <- [2], z <- [3], do: {x, y, z})
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.generators) == 3
      patterns = Comprehension.generator_patterns(result)
      assert length(patterns) == 3
    end

    test "preserves generator order" do
      ast = quote do: for(a <- [1], b <- [2], c <- [3], do: {a, b, c})
      assert {:ok, result} = Comprehension.extract(ast)

      patterns = Comprehension.generator_patterns(result)
      assert Enum.map(patterns, fn {name, _, _} -> name end) == [:a, :b, :c]
    end
  end

  # ===========================================================================
  # Filter Tests
  # ===========================================================================

  describe "extract/1 with filters" do
    test "extracts single filter" do
      ast = quote do: for(x <- [1, 2, 3, 4], x > 2, do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.filters) == 1
      assert result.metadata.filter_count == 1

      [filter] = result.filters
      assert {:>, _, [{:x, [], _}, 2]} = filter
    end

    test "extracts multiple filters" do
      ast = quote do: for(x <- [1, 2, 3, 4, 5], x > 1, x < 5, do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.filters) == 2
      assert result.metadata.filter_count == 2
    end

    test "extracts mixed generators and filters" do
      ast = quote do: for(x <- [1, 2], x > 0, y <- [3, 4], y > x, do: {x, y})
      assert {:ok, result} = Comprehension.extract(ast)

      # The AST structure may interleave generators and filters
      assert result.metadata.generator_count == 2
      assert result.metadata.filter_count == 2
    end

    test "extracts complex filter expression" do
      ast = quote do: for(x <- [1, 2, 3, 4], rem(x, 2) == 0, do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.filters) == 1
      [filter] = result.filters
      assert {:==, _, _} = filter
    end
  end

  # ===========================================================================
  # Bitstring Generator Tests
  # ===========================================================================

  describe "extract/1 with bitstring generator" do
    test "extracts bitstring generator" do
      ast = quote do: for(<<c <- "hello">>, do: c + 1)
      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.generators) == 1
      [gen] = result.generators
      assert gen.type == :bitstring_generator
      assert {:c, [], _} = gen.pattern
      assert gen.enumerable == "hello"
    end

    test "extracts bitstring generator with variable binary" do
      ast = quote do: for(<<byte <- binary>>, do: byte)
      assert {:ok, result} = Comprehension.extract(ast)

      [gen] = result.generators
      assert gen.type == :bitstring_generator
      assert {:binary, [], _} = gen.enumerable
    end
  end

  # ===========================================================================
  # Options Tests
  # ===========================================================================

  describe "extract/1 with :into option" do
    test "extracts into map" do
      ast = quote do: for({k, v} <- %{a: 1}, into: %{}, do: {k, v * 2})
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.into == {:%{}, [], []}
      assert result.metadata.has_into == true
      assert Comprehension.has_into?(result)
    end

    test "extracts into list" do
      ast = quote do: for(x <- [1, 2], into: [], do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.into == []
      assert Comprehension.has_into?(result)
    end

    test "extracts into string (binary)" do
      ast = quote do: for(c <- ~c"abc", into: "", do: <<c>>)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.into == ""
      assert Comprehension.has_into?(result)
    end
  end

  describe "extract/1 with :reduce option" do
    test "extracts reduce with initial value" do
      ast =
        quote do
          for x <- [1, 2, 3], reduce: 0 do
            acc -> acc + x
          end
        end

      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.reduce == 0
      assert result.metadata.has_reduce == true
      assert Comprehension.has_reduce?(result)
    end

    test "extracts reduce with complex initial value" do
      ast =
        quote do
          for x <- [1, 2], reduce: %{sum: 0, count: 0} do
            acc -> %{acc | sum: acc.sum + x, count: acc.count + 1}
          end
        end

      assert {:ok, result} = Comprehension.extract(ast)

      assert {:%{}, [], [sum: 0, count: 0]} = result.options.reduce
      assert Comprehension.has_reduce?(result)
    end

    test "reduce body contains clauses" do
      ast =
        quote do
          for x <- [1, 2, 3], reduce: 0 do
            acc -> acc + x
          end
        end

      assert {:ok, result} = Comprehension.extract(ast)

      # Body should be the list of arrow clauses
      assert is_list(result.body)
      [{:->, _, [[_acc], _body]}] = result.body
    end
  end

  describe "extract/1 with :uniq option" do
    test "extracts uniq: true" do
      ast = quote do: for(x <- [1, 1, 2, 2, 3], uniq: true, do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.uniq == true
      assert result.metadata.has_uniq == true
      assert Comprehension.has_uniq?(result)
    end

    test "default uniq is false" do
      ast = quote do: for(x <- [1, 2, 3], do: x)
      assert {:ok, result} = Comprehension.extract(ast)

      assert result.options.uniq == false
      assert result.metadata.has_uniq == false
      refute Comprehension.has_uniq?(result)
    end
  end

  # ===========================================================================
  # Pattern Matching in Generators
  # ===========================================================================

  describe "extract/1 with pattern matching" do
    test "extracts tuple pattern in generator" do
      ast = quote do: for({:ok, value} <- results, do: value)
      assert {:ok, result} = Comprehension.extract(ast)

      [gen] = result.generators
      assert {:ok, {:value, [], _}} = gen.pattern
    end

    test "extracts map pattern in generator" do
      ast = quote do: for(%{name: name} <- users, do: name)
      assert {:ok, result} = Comprehension.extract(ast)

      [gen] = result.generators
      assert {:%{}, [], [name: {:name, [], _}]} = gen.pattern
    end

    test "extracts binary pattern in generator" do
      ast = quote do: for(<<a::8, b::8>> <- binaries, do: {a, b})
      assert {:ok, result} = Comprehension.extract(ast)

      [gen] = result.generators
      # The pattern should be a binary match
      assert {:<<>>, _, _} = gen.pattern
    end
  end

  # ===========================================================================
  # Generator Extraction Tests
  # ===========================================================================

  describe "extract_generator/1" do
    test "extracts generator with all fields" do
      ast = {:<-, [line: 1, column: 5], [{:x, [], nil}, [1, 2, 3]]}
      gen = Comprehension.extract_generator(ast)

      assert gen.type == :generator
      assert gen.pattern == {:x, [], nil}
      assert gen.enumerable == [1, 2, 3]
    end
  end

  describe "extract_bitstring_generator/1" do
    test "extracts bitstring generator with all fields" do
      ast = {:<<>>, [], [{:<-, [], [{:c, [], nil}, "test"]}]}
      gen = Comprehension.extract_bitstring_generator(ast)

      assert gen.type == :bitstring_generator
      assert gen.pattern == {:c, [], nil}
      assert gen.enumerable == "test"
    end
  end

  # ===========================================================================
  # Convenience Functions Tests
  # ===========================================================================

  describe "generator_patterns/1" do
    test "returns patterns from all generators" do
      ast = quote do: for(x <- [1], y <- [2], do: {x, y})
      {:ok, result} = Comprehension.extract(ast)

      patterns = Comprehension.generator_patterns(result)
      assert length(patterns) == 2

      # Check pattern names regardless of context
      pattern_names = Enum.map(patterns, fn {name, _, _} -> name end)
      assert :x in pattern_names
      assert :y in pattern_names
    end

    test "returns empty list for non-comprehension" do
      assert Comprehension.generator_patterns(%{}) == []
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/1 error handling" do
    test "returns error for non-comprehension" do
      ast = quote do: if(true, do: 1)
      assert {:error, msg} = Comprehension.extract(ast)
      assert msg =~ "Not a for comprehension"
    end

    test "returns error for atoms" do
      assert {:error, _} = Comprehension.extract(:for)
    end

    test "extract! raises on error" do
      assert_raise ArgumentError, fn ->
        Comprehension.extract!(:not_a_comprehension)
      end
    end
  end

  # ===========================================================================
  # Complex Comprehension Tests
  # ===========================================================================

  describe "extract/1 with complex comprehensions" do
    test "extracts comprehension with all features" do
      ast =
        quote do
          for x <- [1, 2, 3, 4],
              x > 1,
              y <- [10, 20],
              x + y < 25,
              into: %{},
              do: {x, y}
        end

      assert {:ok, result} = Comprehension.extract(ast)

      assert result.metadata.generator_count == 2
      assert result.metadata.filter_count == 2
      assert result.metadata.has_into == true
    end

    test "extracts comprehension from real-world example" do
      # Typical map transformation pattern
      ast =
        quote do
          for {key, value} <- map,
              is_atom(key),
              into: %{},
              do: {key, String.upcase(value)}
        end

      assert {:ok, result} = Comprehension.extract(ast)

      assert length(result.generators) == 1
      assert length(result.filters) == 1
      assert Comprehension.has_into?(result)
    end
  end
end
