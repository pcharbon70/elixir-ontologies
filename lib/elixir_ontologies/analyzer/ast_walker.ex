defmodule ElixirOntologies.Analyzer.ASTWalker do
  @moduledoc """
  Generic AST walker for traversing Elixir abstract syntax trees.

  This module provides utilities for walking AST structures with support for
  pre-order and post-order traversal, context tracking (depth, parent chain),
  and selective traversal (skipping subtrees).

  ## Features

  - Pre-order and post-order visitor callbacks
  - Context tracking with depth and parent chain
  - Skip and halt control for selective traversal
  - Pattern-based node collection utilities

  ## Usage

      alias ElixirOntologies.Analyzer.ASTWalker

      # Simple walk collecting all function names
      {:ok, ast} = Code.string_to_quoted("def foo, do: :ok")

      {_ast, names} = ASTWalker.walk(ast, [], fn
        {:def, _, [{name, _, _} | _]}, _ctx, acc -> {:cont, [name | acc]}
        _node, _ctx, acc -> {:cont, acc}
      end)

      # Find all nodes matching a predicate
      modules = ASTWalker.find_all(ast, fn
        {:defmodule, _, _} -> true
        _ -> false
      end)

      # Walk with pre and post callbacks
      {_ast, acc} = ASTWalker.walk(ast, %{},
        pre: fn node, ctx, acc ->
          {:cont, Map.put(acc, ctx.depth, node)}
        end,
        post: fn _node, _ctx, acc ->
          {:cont, acc}
        end
      )

  ## Visitor Return Values

  The visitor function should return one of:

  - `{:cont, new_acc}` - Continue traversal with updated accumulator
  - `{:skip, new_acc}` - Skip children of current node, continue with siblings
  - `{:halt, new_acc}` - Stop entire traversal immediately

  ## Context

  The context struct provides traversal information:

  - `depth` - Current depth in tree (0 = root)
  - `path` - Path of node types from root to current
  - `parent` - Immediate parent node (nil at root)
  - `parents` - Full parent chain from root to current
  """

  # ============================================================================
  # Context Struct
  # ============================================================================

  defmodule Context do
    @moduledoc """
    Traversal context providing information about the current position in the AST.

    ## Fields

    - `depth` - Current depth in tree (0 = root)
    - `path` - Path of node types from root to current node
    - `parent` - Immediate parent node (nil at root)
    - `parents` - Full parent chain from root to current (most recent first)
    """

    defstruct depth: 0, path: [], parent: nil, parents: []

    @type t :: %__MODULE__{
            depth: non_neg_integer(),
            path: [atom()],
            parent: Macro.t() | nil,
            parents: [Macro.t()]
          }

    @doc """
    Creates a new context for the root node.

    ## Examples

        iex> ctx = ASTWalker.Context.new()
        iex> ctx.depth
        0
        iex> ctx.parent
        nil

    """
    @spec new() :: t()
    def new, do: %__MODULE__{}

    @doc """
    Creates a child context for descending into a child node.

    ## Parameters

    - `ctx` - Current context
    - `parent_node` - The node being descended from

    ## Examples

        iex> ctx = ASTWalker.Context.new()
        iex> child_ctx = ASTWalker.Context.descend(ctx, {:def, [], []})
        iex> child_ctx.depth
        1
        iex> child_ctx.parent
        {:def, [], []}

    """
    @spec descend(t(), Macro.t()) :: t()
    def descend(%__MODULE__{} = ctx, parent_node) do
      node_type = extract_node_type(parent_node)

      %__MODULE__{
        depth: ctx.depth + 1,
        path: ctx.path ++ [node_type],
        parent: parent_node,
        parents: [parent_node | ctx.parents]
      }
    end

    defp extract_node_type({type, _meta, _args}) when is_atom(type), do: type
    defp extract_node_type(atom) when is_atom(atom), do: :atom
    defp extract_node_type(list) when is_list(list), do: :list
    defp extract_node_type({_, _}), do: :tuple
    defp extract_node_type(num) when is_number(num), do: :number
    defp extract_node_type(bin) when is_binary(bin), do: :string
    defp extract_node_type(_), do: :unknown
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Walks an AST with a visitor function.

  The visitor function receives each node, the current context, and the
  accumulator. It should return `{:cont, acc}`, `{:skip, acc}`, or `{:halt, acc}`.

  ## Parameters

  - `ast` - The AST to traverse
  - `acc` - Initial accumulator value
  - `visitor` - Function `(node, context, acc) -> {:cont | :skip | :halt, acc}`

  ## Returns

  - `{transformed_ast, final_acc}` - The (potentially modified) AST and final accumulator

  When using options, you can specify pre and post callbacks:

  - `:pre` - Pre-order visitor function (called before children)
  - `:post` - Post-order visitor function (called after children)

  At least one of `:pre` or `:post` must be provided when using option syntax.

  ## Examples

      iex> ast = quote(do: 1 + 2)
      iex> {_ast, sum} = ASTWalker.walk(ast, 0, fn
      ...>   num, _ctx, acc when is_integer(num) -> {:cont, acc + num}
      ...>   _node, _ctx, acc -> {:cont, acc}
      ...> end)
      iex> sum
      3

  """
  @spec walk(Macro.t(), acc, visitor_or_opts) :: {Macro.t(), acc}
        when acc: any(),
             visitor_or_opts:
               (Macro.t(), Context.t(), acc -> {:cont | :skip | :halt, acc}) | keyword()
  def walk(ast, acc, visitor) when is_function(visitor, 3) do
    walk(ast, acc, pre: visitor)
  end

  def walk(ast, acc, opts) when is_list(opts) do
    pre_fn = Keyword.get(opts, :pre)
    post_fn = Keyword.get(opts, :post)

    if is_nil(pre_fn) and is_nil(post_fn) do
      raise ArgumentError, "at least one of :pre or :post must be provided"
    end

    ctx = Context.new()
    do_walk_entry(ast, acc, ctx, pre_fn, post_fn)
  end

  @doc """
  Finds all nodes in the AST matching a predicate.

  ## Parameters

  - `ast` - The AST to search
  - `predicate` - Function `(node) -> boolean()`

  ## Returns

  List of nodes matching the predicate.

  ## Examples

      iex> ast = quote do
      ...>   def foo, do: :ok
      ...>   def bar, do: :error
      ...> end
      iex> defs = ASTWalker.find_all(ast, fn
      ...>   {:def, _, _} -> true
      ...>   _ -> false
      ...> end)
      iex> length(defs)
      2

  """
  @spec find_all(Macro.t(), (Macro.t() -> boolean())) :: [Macro.t()]
  def find_all(ast, predicate) when is_function(predicate, 1) do
    find_all(ast, predicate, [])
  end

  @doc """
  Finds all nodes in the AST matching a predicate, with options.

  ## Parameters

  - `ast` - The AST to search
  - `predicate` - Function `(node) -> boolean()` or `(node, context) -> boolean()`
  - `opts` - Options (reserved for future use)

  ## Returns

  List of nodes matching the predicate.

  ## Examples

      iex> ast = quote(do: def(foo, do: :ok))
      iex> nodes = ASTWalker.find_all(ast, fn
      ...>   {:def, _, _} -> true
      ...>   _ -> false
      ...> end, [])
      iex> length(nodes) >= 1
      true

  """
  @spec find_all(Macro.t(), predicate, keyword()) :: [Macro.t()]
        when predicate: (Macro.t() -> boolean()) | (Macro.t(), Context.t() -> boolean())
  def find_all(ast, predicate, _opts) when is_function(predicate, 1) do
    {_ast, nodes} =
      walk(ast, [], fn node, _ctx, acc ->
        if predicate.(node) do
          {:cont, [node | acc]}
        else
          {:cont, acc}
        end
      end)

    Enum.reverse(nodes)
  end

  def find_all(ast, predicate, _opts) when is_function(predicate, 2) do
    {_ast, nodes} =
      walk(ast, [], fn node, ctx, acc ->
        if predicate.(node, ctx) do
          {:cont, [node | acc]}
        else
          {:cont, acc}
        end
      end)

    Enum.reverse(nodes)
  end

  @doc """
  Collects transformed values from nodes matching a predicate.

  ## Parameters

  - `ast` - The AST to search
  - `predicate` - Function `(node) -> boolean()`
  - `transformer` - Function `(node) -> value` to transform matching nodes

  ## Returns

  List of transformed values from matching nodes.

  ## Examples

      iex> ast = quote do
      ...>   def foo, do: :ok
      ...>   def bar, do: :error
      ...> end
      iex> names = ASTWalker.collect(ast,
      ...>   fn {:def, _, _} -> true; _ -> false end,
      ...>   fn {:def, _, [{name, _, _} | _]} -> name end
      ...> )
      iex> :foo in names and :bar in names
      true

  """
  @spec collect(Macro.t(), (Macro.t() -> boolean()), (Macro.t() -> any())) :: [any()]
  def collect(ast, predicate, transformer)
      when is_function(predicate, 1) and is_function(transformer, 1) do
    {_ast, values} =
      walk(ast, [], fn node, _ctx, acc ->
        if predicate.(node) do
          {:cont, [transformer.(node) | acc]}
        else
          {:cont, acc}
        end
      end)

    Enum.reverse(values)
  end

  @doc """
  Returns the depth of a node in the AST.

  This walks the AST to find the first occurrence of the target node
  and returns its depth.

  ## Parameters

  - `ast` - The AST to search
  - `target` - The node to find

  ## Returns

  - `{:ok, depth}` - Depth of the node
  - `:not_found` - Node not found in AST

  ## Examples

      iex> ast = quote(do: def(foo, do: :ok))
      iex> {:ok, depth} = ASTWalker.depth_of(ast, :ok)
      iex> depth > 0
      true

  """
  @spec depth_of(Macro.t(), Macro.t()) :: {:ok, non_neg_integer()} | :not_found
  def depth_of(ast, target) do
    {_ast, result} =
      walk(ast, :not_found, fn node, ctx, acc ->
        if node == target and acc == :not_found do
          {:halt, {:ok, ctx.depth}}
        else
          {:cont, acc}
        end
      end)

    result
  end

  @doc """
  Counts all nodes in the AST.

  ## Parameters

  - `ast` - The AST to count

  ## Returns

  Total number of nodes visited.

  ## Examples

      iex> ast = quote(do: 1 + 2)
      iex> count = ASTWalker.count_nodes(ast)
      iex> count >= 3
      true

  """
  @spec count_nodes(Macro.t()) :: non_neg_integer()
  def count_nodes(ast) do
    {_ast, count} =
      walk(ast, 0, fn _node, _ctx, acc ->
        {:cont, acc + 1}
      end)

    count
  end

  @doc """
  Returns the maximum depth of the AST.

  ## Parameters

  - `ast` - The AST to measure

  ## Returns

  Maximum depth reached during traversal.

  ## Examples

      iex> ast = quote(do: def(foo, do: :ok))
      iex> max_depth = ASTWalker.max_depth(ast)
      iex> max_depth >= 1
      true

  """
  @spec max_depth(Macro.t()) :: non_neg_integer()
  def max_depth(ast) do
    {_ast, max} =
      walk(ast, 0, fn _node, ctx, acc ->
        {:cont, max(ctx.depth, acc)}
      end)

    max
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  # State contains {:cont | :halt, acc}
  defp do_walk(ast, {:halt, acc}, _ctx, _pre_fn, _post_fn) do
    # Already halted, don't process further
    {ast, {:halt, acc}}
  end

  defp do_walk(ast, {:cont, acc}, ctx, pre_fn, post_fn) do
    # Pre-order callback
    {action, acc} = call_visitor(pre_fn, ast, ctx, acc)

    case action do
      :halt ->
        {ast, {:halt, acc}}

      :skip ->
        # Skip children, but still call post callback
        {_action, acc} = call_visitor(post_fn, ast, ctx, acc)
        {ast, {:cont, acc}}

      :cont ->
        # Traverse children
        child_ctx = Context.descend(ctx, ast)
        {new_ast, state} = traverse_children(ast, {:cont, acc}, child_ctx, pre_fn, post_fn)

        # Post-order callback (only if not halted)
        case state do
          {:halt, acc} ->
            {new_ast, {:halt, acc}}

          {:cont, acc} ->
            {post_action, acc} = call_visitor(post_fn, new_ast, ctx, acc)

            case post_action do
              :halt -> {new_ast, {:halt, acc}}
              _ -> {new_ast, {:cont, acc}}
            end
        end
    end
  end

  # Entry point wrapper that handles state
  defp do_walk_entry(ast, acc, ctx, pre_fn, post_fn) do
    {new_ast, state} = do_walk(ast, {:cont, acc}, ctx, pre_fn, post_fn)

    case state do
      {:halt, final_acc} -> {new_ast, final_acc}
      {:cont, final_acc} -> {new_ast, final_acc}
    end
  end

  defp call_visitor(nil, _node, _ctx, acc), do: {:cont, acc}

  defp call_visitor(visitor, node, ctx, acc) do
    case visitor.(node, ctx, acc) do
      {:cont, new_acc} -> {:cont, new_acc}
      {:skip, new_acc} -> {:skip, new_acc}
      {:halt, new_acc} -> {:halt, new_acc}
    end
  end

  defp traverse_children({form, meta, args}, state, ctx, pre_fn, post_fn)
       when is_atom(form) and is_list(args) do
    {new_args, state} = traverse_list(args, state, ctx, pre_fn, post_fn)
    {{form, meta, new_args}, state}
  end

  defp traverse_children({left, right}, state, ctx, pre_fn, post_fn) do
    {new_left, state} = do_walk(left, state, ctx, pre_fn, post_fn)
    {new_right, state} = do_walk(right, state, ctx, pre_fn, post_fn)
    {{new_left, new_right}, state}
  end

  defp traverse_children(list, state, ctx, pre_fn, post_fn) when is_list(list) do
    traverse_list(list, state, ctx, pre_fn, post_fn)
  end

  defp traverse_children(other, state, _ctx, _pre_fn, _post_fn) do
    {other, state}
  end

  defp traverse_list(list, state, ctx, pre_fn, post_fn) do
    Enum.reduce_while(list, {[], state}, fn item, {processed, state} ->
      case state do
        {:halt, _} ->
          {:halt, {Enum.reverse(processed) ++ [item | tl_or_empty(list, item)], state}}

        {:cont, _} ->
          {new_item, new_state} = do_walk(item, state, ctx, pre_fn, post_fn)

          case new_state do
            {:halt, _} ->
              # Include current item but stop processing rest
              remaining = remaining_items(list, item)
              {:halt, {Enum.reverse([new_item | processed]) ++ remaining, new_state}}

            {:cont, _} ->
              {:cont, {[new_item | processed], new_state}}
          end
      end
    end)
    |> then(fn {processed, state} ->
      case processed do
        list when is_list(list) -> {Enum.reverse(list), state}
        other -> {other, state}
      end
    end)
  end

  defp tl_or_empty([], _item), do: []

  defp tl_or_empty(list, item) do
    case Enum.drop_while(list, fn x -> x != item end) do
      [^item | rest] -> rest
      _ -> []
    end
  end

  defp remaining_items(list, current_item) do
    list
    |> Enum.drop_while(fn x -> x != current_item end)
    |> case do
      [^current_item | rest] -> rest
      _ -> []
    end
  end
end
