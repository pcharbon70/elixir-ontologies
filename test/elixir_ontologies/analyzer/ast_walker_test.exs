defmodule ElixirOntologies.Analyzer.ASTWalkerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.ASTWalker
  alias ElixirOntologies.Analyzer.ASTWalker.Context

  # ============================================================================
  # Context Tests
  # ============================================================================

  describe "Context.new/0" do
    test "creates context with depth 0" do
      ctx = Context.new()

      assert ctx.depth == 0
    end

    test "creates context with nil parent" do
      ctx = Context.new()

      assert ctx.parent == nil
    end

    test "creates context with empty path" do
      ctx = Context.new()

      assert ctx.path == []
    end

    test "creates context with empty parents list" do
      ctx = Context.new()

      assert ctx.parents == []
    end
  end

  describe "Context.descend/2" do
    test "increments depth" do
      ctx = Context.new()
      child = Context.descend(ctx, {:def, [], []})

      assert child.depth == 1
    end

    test "sets parent to current node" do
      ctx = Context.new()
      node = {:def, [], []}
      child = Context.descend(ctx, node)

      assert child.parent == node
    end

    test "adds node to path" do
      ctx = Context.new()
      child = Context.descend(ctx, {:def, [], []})

      assert child.path == [:def]
    end

    test "accumulates parents" do
      ctx = Context.new()
      node1 = {:defmodule, [], []}
      node2 = {:def, [], []}

      child1 = Context.descend(ctx, node1)
      child2 = Context.descend(child1, node2)

      assert child2.parents == [node2, node1]
    end

    test "handles atoms" do
      ctx = Context.new()
      child = Context.descend(ctx, :ok)

      assert child.path == [:atom]
    end

    test "handles lists" do
      ctx = Context.new()
      child = Context.descend(ctx, [1, 2, 3])

      assert child.path == [:list]
    end
  end

  # ============================================================================
  # walk/3 Tests
  # ============================================================================

  describe "walk/3" do
    test "visits all nodes in simple expression" do
      ast = quote do: 1 + 2

      {_ast, count} =
        ASTWalker.walk(ast, 0, fn _node, _ctx, acc ->
          {:cont, acc + 1}
        end)

      # :+, 1, 2, and potentially metadata
      assert count >= 3
    end

    test "accumulates values correctly" do
      ast = quote do: 1 + 2

      {_ast, sum} =
        ASTWalker.walk(ast, 0, fn
          num, _ctx, acc when is_integer(num) -> {:cont, acc + num}
          _node, _ctx, acc -> {:cont, acc}
        end)

      assert sum == 3
    end

    test "provides context with depth" do
      ast = quote(do: def(foo, do: :ok))

      {_ast, depths} =
        ASTWalker.walk(ast, [], fn _node, ctx, acc ->
          {:cont, [ctx.depth | acc]}
        end)

      assert 0 in depths
      assert Enum.max(depths) > 0
    end

    test "supports skip action" do
      ast =
        quote do
          def foo do
            :skipped
          end

          :not_skipped
        end

      {_ast, nodes} =
        ASTWalker.walk(ast, [], fn
          {:def, _, _} = node, _ctx, acc ->
            {:skip, [node | acc]}

          node, _ctx, acc when is_atom(node) and node != :do ->
            {:cont, [node | acc]}

          _node, _ctx, acc ->
            {:cont, acc}
        end)

      # :skipped should not be in list because we skipped def's children
      refute :skipped in nodes
      assert :not_skipped in nodes
    end

    test "supports halt action" do
      # Use a structure where :second comes AFTER :first in traversal
      ast =
        quote do
          [:first, :second, :third]
        end

      {_ast, found} =
        ASTWalker.walk(ast, [], fn
          :second, _ctx, acc -> {:halt, [:second | acc]}
          atom, _ctx, acc when is_atom(atom) -> {:cont, [atom | acc]}
          _node, _ctx, acc -> {:cont, acc}
        end)

      assert :first in found
      assert :second in found
      # :third should NOT be in list because we halted at :second
      refute :third in found
    end

    test "tracks parent chain" do
      ast = quote(do: def(foo, do: :ok))

      {_ast, parents_at_ok} =
        ASTWalker.walk(ast, nil, fn
          :ok, ctx, _acc -> {:cont, ctx.parents}
          _node, _ctx, acc -> {:cont, acc}
        end)

      assert is_list(parents_at_ok)
      assert length(parents_at_ok) > 0
    end
  end

  # ============================================================================
  # walk/4 Tests
  # ============================================================================

  describe "walk/4 with options" do
    test "calls pre callback before children" do
      ast = quote(do: def(foo, do: :ok))

      {_ast, events} =
        ASTWalker.walk(ast, [],
          pre: fn node, _ctx, acc ->
            case node do
              {:def, _, _} -> {:cont, [{:pre, :def} | acc]}
              :ok -> {:cont, [{:pre, :ok} | acc]}
              _ -> {:cont, acc}
            end
          end,
          post: fn node, _ctx, acc ->
            case node do
              {:def, _, _} -> {:cont, [{:post, :def} | acc]}
              :ok -> {:cont, [{:post, :ok} | acc]}
              _ -> {:cont, acc}
            end
          end
        )

      events = Enum.reverse(events)

      # pre :def should come before pre :ok
      pre_def_idx = Enum.find_index(events, &(&1 == {:pre, :def}))
      pre_ok_idx = Enum.find_index(events, &(&1 == {:pre, :ok}))
      post_ok_idx = Enum.find_index(events, &(&1 == {:post, :ok}))
      post_def_idx = Enum.find_index(events, &(&1 == {:post, :def}))

      assert pre_def_idx < pre_ok_idx
      assert pre_ok_idx < post_ok_idx
      assert post_ok_idx < post_def_idx
    end

    test "post callback sees children results" do
      ast = quote do: 1 + 2

      {_ast, sum} =
        ASTWalker.walk(ast, 0,
          pre: fn
            num, _ctx, acc when is_integer(num) -> {:cont, acc + num}
            _node, _ctx, acc -> {:cont, acc}
          end
        )

      assert sum == 3
    end

    test "raises without pre or post" do
      ast = quote do: 1 + 2

      assert_raise ArgumentError, ~r/at least one of :pre or :post/, fn ->
        ASTWalker.walk(ast, 0, [])
      end
    end
  end

  # ============================================================================
  # find_all/2 Tests
  # ============================================================================

  describe "find_all/2" do
    test "finds all matching nodes" do
      ast =
        quote do
          def foo, do: :ok
          def bar, do: :error
        end

      defs =
        ASTWalker.find_all(ast, fn
          {:def, _, _} -> true
          _ -> false
        end)

      assert length(defs) == 2
    end

    test "returns empty list when no matches" do
      ast = quote do: 1 + 2

      matches =
        ASTWalker.find_all(ast, fn
          {:defmodule, _, _} -> true
          _ -> false
        end)

      assert matches == []
    end

    test "finds nested nodes" do
      ast =
        quote do
          defmodule Outer do
            defmodule Inner do
            end
          end
        end

      modules =
        ASTWalker.find_all(ast, fn
          {:defmodule, _, _} -> true
          _ -> false
        end)

      assert length(modules) == 2
    end

    test "preserves order of matches" do
      ast =
        quote do
          def a, do: 1
          def b, do: 2
          def c, do: 3
        end

      names =
        ASTWalker.find_all(ast, fn
          {:def, _, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:def, _, [{name, _, _} | _]} -> name end)

      assert names == [:a, :b, :c]
    end
  end

  describe "find_all/3 with context predicate" do
    test "can filter by depth" do
      ast =
        quote do
          defmodule Outer do
            defmodule Inner do
            end
          end
        end

      # Find modules at specific depth
      shallow_modules =
        ASTWalker.find_all(
          ast,
          fn
            {:defmodule, _, _}, ctx -> ctx.depth < 2
            _, _ctx -> false
          end,
          []
        )

      assert length(shallow_modules) == 1
    end
  end

  # ============================================================================
  # collect/3 Tests
  # ============================================================================

  describe "collect/3" do
    test "transforms matching nodes" do
      ast =
        quote do
          def foo, do: :ok
          def bar, do: :error
        end

      names =
        ASTWalker.collect(
          ast,
          fn
            {:def, _, _} -> true
            _ -> false
          end,
          fn {:def, _, [{name, _, _} | _]} -> name end
        )

      assert :foo in names
      assert :bar in names
    end

    test "returns empty list when no matches" do
      ast = quote do: 1 + 2

      values =
        ASTWalker.collect(
          ast,
          fn _ -> false end,
          fn node -> node end
        )

      assert values == []
    end
  end

  # ============================================================================
  # depth_of/2 Tests
  # ============================================================================

  describe "depth_of/2" do
    test "finds depth of node" do
      ast = quote(do: def(foo, do: :ok))

      {:ok, depth} = ASTWalker.depth_of(ast, :ok)

      assert depth > 0
    end

    test "returns :not_found for missing node" do
      ast = quote do: 1 + 2

      result = ASTWalker.depth_of(ast, :missing)

      assert result == :not_found
    end

    test "returns 0 for root node" do
      ast = {:+, [], [1, 2]}

      {:ok, depth} = ASTWalker.depth_of(ast, ast)

      assert depth == 0
    end
  end

  # ============================================================================
  # count_nodes/1 Tests
  # ============================================================================

  describe "count_nodes/1" do
    test "counts all nodes" do
      ast = quote do: 1 + 2

      count = ASTWalker.count_nodes(ast)

      assert count >= 3
    end

    test "counts nodes in complex AST" do
      ast =
        quote do
          defmodule Foo do
            def bar, do: :ok
          end
        end

      count = ASTWalker.count_nodes(ast)

      assert count > 5
    end
  end

  # ============================================================================
  # max_depth/1 Tests
  # ============================================================================

  describe "max_depth/1" do
    test "returns maximum depth" do
      ast = quote(do: def(foo, do: :ok))

      max = ASTWalker.max_depth(ast)

      assert max >= 2
    end

    test "returns 0 for single node" do
      ast = :atom

      max = ASTWalker.max_depth(ast)

      assert max == 0
    end
  end

  # ============================================================================
  # Doctest
  # ============================================================================

  doctest ElixirOntologies.Analyzer.ASTWalker
  doctest ElixirOntologies.Analyzer.ASTWalker.Context
end
