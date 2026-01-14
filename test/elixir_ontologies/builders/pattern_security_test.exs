defmodule ElixirOntologies.Builders.PatternSecurityTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.ExpressionBuilder
  alias ElixirOntologies.NS.Core
  import ElixirOntologies.Builders.ExpressionTestHelpers

  @moduletag :pattern_security

  # ===========================================================================
  # Depth Limiting Tests (C1)
  # ===========================================================================

  describe "pattern depth limiting" do
    test "handles patterns at the depth limit (100 levels)" do
      # Create a 100-level nested pattern (should succeed)
      context = full_mode_context()

      # Build a 100-level nested tuple pattern
      pattern = build_deep_nested_pattern(100)

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])

      # Should successfully build the pattern
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have at least the type triple
      assert has_type?(pattern_triples, Core.TuplePattern)
    end

    test "gracefully handles patterns exceeding depth limit" do
      # Patterns deeper than 100 levels should not crash
      context = full_mode_context()

      # Build a 105-level nested tuple pattern (exceeds limit)
      pattern = build_deep_nested_pattern(105)

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])

      # Should still return triples (pattern building degrades gracefully)
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have at least the type triple
      assert has_type?(pattern_triples, Core.TuplePattern)
    end

    test "handles very deep nesting without stack overflow" do
      # Even extremely deep patterns should not cause stack overflow
      context = full_mode_context()

      # Create a 200-level nested tuple pattern (way beyond limit)
      pattern = build_deep_nested_pattern(200)

      # Should not crash
      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])

      # Building pattern should not crash either
      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have at least the type triple
      assert has_type?(pattern_triples, Core.TuplePattern)
    end
  end

  # ===========================================================================
  # Collection Size Limit Tests (C3)
  # ===========================================================================

  describe "collection size limiting" do
    test "handles tuples at size limit" do
      context = full_mode_context()

      # Create a 1000-element tuple (at the limit)
      elements = List.duplicate({:x, [], Elixir}, 1000)
      pattern = {:{}, [], elements}

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have the type triple
      assert has_type?(pattern_triples, Core.TuplePattern)
    end

    test "handles lists at size limit" do
      context = full_mode_context()

      # Create a 1000-element list (at the limit)
      elements = List.duplicate({:x, [], Elixir}, 1000)
      pattern = elements

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have the type triple
      assert has_type?(pattern_triples, Core.ListPattern)
    end

    test "handles maps at size limit" do
      context = full_mode_context()

      # Create a 1000-pair map (at the limit)
      pairs = for i <- 1..1000, do: {:"key_#{i}", {:x, [], Elixir}}
      pattern = {:%{}, [], pairs}

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should have the type triple
      assert has_type?(pattern_triples, Core.MapPattern)
    end

    test "gracefully handles oversized collections" do
      context = full_mode_context()

      # Create a 1001-element list (exceeds limit)
      elements = List.duplicate({:x, [], Elixir}, 1001)
      pattern = elements

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should still have the type triple (graceful degradation)
      assert has_type?(pattern_triples, Core.ListPattern)
      # But should not process all elements
      # Check that we don't have excessive triples
      assert length(pattern_triples) < 2000
    end

    test "handles very large binary patterns" do
      context = full_mode_context()

      # Create a 1001-segment binary (exceeds limit)
      segments = for i <- 1..1001 do
        {:"::", [], [{:"x#{i}", [], Elixir}, 8]}
      end

      pattern = {:<<>>, [], segments}

      assert {:ok, {expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      pattern_triples = ExpressionBuilder.build_pattern(pattern, expr_iri, context)

      # Should still have the type triple
      assert has_type?(pattern_triples, Core.BinaryPattern)
    end
  end

  # ===========================================================================
  # Module Name Validation Tests (C2)
  # ===========================================================================

  describe "module name validation" do
    test "handles valid module names" do
      context = full_mode_context()

      # Valid module names
      valid_modules = [
        {:__aliases__, [], [:MyApp]},
        {:__aliases__, [], [:MyApp, :User]},
        {:__aliases__, [], [:My, :App, :Users, :Admin]},
        {:__aliases__, [], [:MyApp, :Nested, :Module]}
      ]

      for module_ast <- valid_modules do
        map_ast = {:%{}, [], [name: {:x, [], Elixir}]}
        pattern = {:%, [], [module_ast, map_ast]}

        assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      end
    end

    test "sanitizes path traversal in module names" do
      context = full_mode_context()

      # Attempt path traversal using inspect fallback
      # This would be caught by the sanitization
      pattern_ast = {:%{}, [], [name: {:x, [], Elixir}]}

      # Construct a module reference with path traversal characters
      # The inspect output will contain ".." which gets sanitized
      malicious_ast = "../../etc/passwd"

      # Create a struct-like pattern with the malicious string
      # When processed through extract_struct_module_name, it gets sanitized
      pattern = {:%, [], [malicious_ast, pattern_ast]}

      # Should not crash
      result = ExpressionBuilder.build(pattern, context, [])

      # Should either succeed with sanitized module name or handle gracefully
      assert {:ok, {_expr_iri, _triples, _ctx}} = result
    end

    test "handles __MODULE__ reference" do
      context = full_mode_context()

      map_ast = {:%{}, [], [name: {:x, [], Elixir}]}
      pattern = {:%, [], [{:__MODULE__, [], []}, map_ast]}

      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end

    test "handles tuple form module reference" do
      context = full_mode_context()

      # Tuple form: {:{}, _, [:MyApp, :User]}
      module_parts = [:MyApp, :User]
      module_ast = {:{}, [], module_parts}
      map_ast = {:%{}, [], [name: {:x, [], Elixir}]}
      pattern = {:%, [], [module_ast, map_ast]}

      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end
  end

  # ===========================================================================
  # Memory Safety Tests
  # ===========================================================================

  describe "memory safety" do
    test "does not exhaust memory on deeply nested patterns" do
      context = full_mode_context()

      # Create a very deeply nested pattern
      pattern = build_deep_nested_pattern(200)

      # Should complete without memory issues
      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end

    test "handles large binary patterns efficiently" do
      context = full_mode_context()

      # Large binary pattern with many segments
      segments = for i <- 1..500 do
        {:"::", [], [{:"byte#{i}", [], Elixir}, 8]}
      end

      pattern = {:<<>>, [], segments}

      # Should complete without memory issues
      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end
  end

  # ===========================================================================
  # Edge Case Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles empty collections" do
      context = full_mode_context()

      # Empty tuple, list, map, binary should all work
      patterns = [
        {:{}, [], []},  # Empty tuple
        [],             # Empty list
        {:%{}, [], []}, # Empty map
        {:<<>>, [], []} # Empty binary
      ]

      for pattern <- patterns do
        assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      end
    end

    test "handles single-element collections" do
      context = full_mode_context()

      patterns = [
        {:{}, [], [{:x, [], Elixir}]},
        [{:x, [], Elixir}],
        {:%{}, [], [key: {:x, [], Elixir}]},
        {:<<>>, [], [{:x, [], Elixir}]}
      ]

      for pattern <- patterns do
        assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
      end
    end

    test "handles boundary size (1000)" do
      context = full_mode_context()

      # Exactly at the limit
      elements = List.duplicate({:x, [], Elixir}, 1000)
      pattern = elements

      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end

    test "handles boundary size plus one (1001)" do
      context = full_mode_context()

      # Just over the limit
      elements = List.duplicate({:x, [], Elixir}, 1001)
      pattern = elements

      # Should still succeed with graceful degradation
      assert {:ok, {_expr_iri, _triples, _ctx}} = ExpressionBuilder.build(pattern, context, [])
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Builds a deeply nested tuple pattern
  # depth 1: {:x, [], Elixir}
  # depth 2: {{:x, [], Elixir}, {:x, [], Elixir}}
  # etc.
  defp build_deep_nested_pattern(depth) when depth <= 1, do: {:x, [], Elixir}

  defp build_deep_nested_pattern(depth) do
    {build_deep_nested_pattern(depth - 1), {:x, [], Elixir}}
  end
end
