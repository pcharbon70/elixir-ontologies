defmodule ElixirOntologies.Builders.ExpressionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir AST expression nodes.

  This module converts Elixir AST nodes to their RDF representation
  according to the elixir-core.ttl ontology. Expression extraction is
  opt-in via the `include_expressions` configuration option.

  ## Mode Selection

  Expression extraction only occurs in "full mode" which requires:
  - `include_expressions: true` in the configuration
  - The file being processed is project code (not a dependency)

  When either condition is false, `build/3` returns `:skip`.

  ## Usage

      context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      )
      |> Context.with_expression_counter()

      # Build expression from AST
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples, updated_context}} = ExpressionBuilder.build(ast, context)

      # In light mode or for dependencies
      ExpressionBuilder.build(ast, light_mode_context)
      # => :skip

  ## Public API vs Internal Functions

  This module provides two layers of functions for expression building:

  ### `build/3` - Public API

  Use `build/3` for top-level expression building from external code:
  - Handles mode checking (full vs light mode)
  - Manages IRI counter in the context
  - Returns `{:ok, {expr_iri, triples, updated_context}}` or `:skip`
  - Thread the returned context to subsequent `build/3` calls

  ### `build_expression_triples/3` - Internal Dispatch

  Internal function used by operator builders for recursive expression building:
  - Directly builds triples given an expression IRI
  - Does NOT check mode (assumes caller already validated)
  - Does NOT manage context counter
  - Returns a list of RDF triples
  - Used when the expr_iri is already known (e.g., child expressions)

  ### When to Use Each

  - **Use `build/3`** when building expressions from external code (e.g., processing AST)
  - **Use `build_expression_triples/3`** when implementing operator builders that need to recursively build child expressions

  ## Expression Dispatch

  The builder pattern matches on AST node types and dispatches to
  specialized builders:

  - Comparison operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`)
  - Logical operators (`and`, `or`, `not`, `&&`, `||`, `!`)
  - Arithmetic operators (`+`, `-`, `*`, `/`, `div`, `rem`)
  - Literals (integers, floats, strings, atoms)
  - Variables and wildcards
  - Remote and local function calls
  - Unknown expressions (generic `Expression` type)

  ## Return Values

  - `{:ok, {expr_iri, triples, updated_context}}` - Expression successfully built
  - `:skip` - Expression should not be extracted (light mode or nil AST)

  ## IRI Generation

  Contextual full-mode analysis supplies an explicit source scope and root suffix.
  Descendants use parent-relative semantic roles and indices, such as `/left`,
  `/right`, `/clause/0/body`, and `/child/1`. This is the stable identity contract
  for complete file graphs and remains deterministic across processes and parallel
  execution.

  Standalone callers that omit a suffix retain the compatibility counter pattern
  `{base_iri}expr/expr_{counter}`. Its counter is local to the supplied context and
  must be threaded by callers; it is not the document-scoped full-analysis contract.

  The `expression_iri/3`, `fresh_iri/2`, and `get_or_create_iri/3` functions
  provide flexible IRI generation patterns for different use cases.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.{CaseWith, Comprehension, Conditional}
  alias ElixirOntologies.NS.Core
  alias ElixirOntologies.IRI

  # ===========================================================================
  # Module Attributes
  # ===========================================================================

  @max_expression_depth 100

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an Elixir AST expression node.

  Returns `:skip` when expression extraction is disabled or the AST is nil.
  Returns `{:ok, {expr_iri, triples, updated_context}}` with the expression IRI,
  all triples, and updated context with incremented counter.

  ## Parameters

  - `ast` - The Elixir AST node (3-tuple format or literal)
  - `context` - The builder context containing configuration
  - `opts` - Optional keyword list for IRI generation

  ## Options

  - `:base_iri` - Override IRI base (defaults to `context.base_iri`)
  - `:suffix` - IRI suffix (defaults to generated counter)
  - `:counter` - Counter for unique IRIs (internal use)

  ## Examples

      # Full mode - expression extracted
      context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      )
      |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples, updated_context}} = ExpressionBuilder.build(ast, context)

      # Light mode - expression skipped
      light_context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: false},
        file_path: "lib/my_app/users.ex"
      )

      ExpressionBuilder.build(ast, light_context)
      # => :skip

      # Dependency file - always skipped
      dep_context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "deps/decimal/lib/decimal.ex"
      )

      ExpressionBuilder.build(ast, dep_context)
      # => :skip

  """
  @spec build(Macro.t() | nil, Context.t(), keyword()) ::
          {:ok, {RDF.IRI.t(), [RDF.Triple.t()], Context.t()}} | :skip
  def build(ast, %Context{} = context, opts) do
    # Check if we should extract full expressions for this file
    if Context.full_mode_for_file?(context, context.file_path) do
      do_build(ast, context, opts)
    else
      :skip
    end
  end

  # ===========================================================================
  # Main Build Logic
  # ===========================================================================

  defp do_build(ast, context, opts) do
    # Get base IRI from options or context
    base_iri = Keyword.get(opts, :base_iri, context.base_iri)

    # Generate expression IRI using context-based counter
    {expr_iri, updated_context} = expression_iri_for_build(base_iri, context, opts)

    # Build expression triples
    triples = build_expression_triples(ast, expr_iri, updated_context)

    # Add inGuardContext property if building guard context expression
    triples =
      if Keyword.get(opts, :guard_context?) do
        [
          Helpers.datatype_property(expr_iri, Core.inGuardContext(), true, RDF.XSD.Boolean)
          | triples
        ]
      else
        triples
      end

    {:ok, {expr_iri, triples, updated_context}}
  end

  # Generates an expression IRI for the build/3 flow using context-based counter
  # This replaces the old process dictionary approach with thread-safe context counters
  defp expression_iri_for_build(base_iri, context, opts) do
    {suffix_string, updated_context} =
      cond do
        # Explicit suffix provided (doesn't use counter)
        custom_suffix = Keyword.get(opts, :suffix) ->
          {custom_suffix, context}

        # Explicit counter provided (advanced use)
        counter = Keyword.get(opts, :counter) ->
          {"expr_#{counter}", context}

        # Use context counter for deterministic IRIs (thread-safe)
        true ->
          {counter, new_context} = Context.next_expression_counter(context)
          {"expr_#{counter}", new_context}
      end

    iri_string = "#{base_iri}expr/#{suffix_string}"
    iri = RDF.IRI.new(iri_string)
    {iri, updated_context}
  end

  # ===========================================================================
  # Block Detection Helpers
  # ===========================================================================

  @doc """
  Detects the type of block expression in the AST.

  Returns the block type atom based on AST structure:
  - `:fn_block` - Anonymous function (fn...end)
  - `:do_block` - Multi-expression block ({:__block__, _, ...})
  - `:single_expr` - Single expression (not a block)

  ## Parameters

  - `ast` - The Elixir AST node to analyze

  ## Returns

  Block type atom: `:fn_block`, `:do_block`, or `:single_expr`

  ## Examples

      iex> ExpressionBuilder.detect_block_type({:fn, [], []})
      :fn_block

      iex> ExpressionBuilder.detect_block_type({:__block__, [], [:a, :b]})
      :do_block

      iex> ExpressionBuilder.detect_block_type({:+, [], [1, 2]})
      :single_expr

  """
  @spec detect_block_type(Macro.t()) :: :fn_block | :do_block | :single_expr
  def detect_block_type({:fn, _, _}), do: :fn_block
  def detect_block_type({:__block__, _, _}), do: :do_block
  def detect_block_type(_), do: :single_expr

  @doc """
  Analyzes the structure of a block expression.

  Extracts block type, expression list, and metadata from the AST.

  ## Parameters

  - `ast` - The Elixir AST node to analyze

  ## Returns

  A map containing:
  - `:type` - Block type atom (`:fn_block`, `:do_block`, `:single_expr`)
  - `:expressions` - List of expressions in the block
  - `:empty?` - Boolean indicating if block is empty
  - `:metadata` - AST metadata (line numbers, context)

  ## Examples

      iex> ast = {:__block__, [], [:a, :b]}
      ...> ExpressionBuilder.analyze_block_structure(ast)
      %{
        type: :do_block,
        expressions: [:a, :b],
        empty?: false,
        metadata: []
      }

      iex> ast = {:+, [], [1, 2]}
      ...> ExpressionBuilder.analyze_block_structure(ast)
      %{
        type: :single_expr,
        expressions: [{:+, [], [1, 2]}],
        empty?: false,
        metadata: []
      }

  """
  @spec analyze_block_structure(Macro.t()) :: %{
          type: atom(),
          expressions: list(),
          empty?: boolean(),
          metadata: list()
        }
  def analyze_block_structure(ast) do
    type = detect_block_type(ast)

    {expressions, metadata} =
      case ast do
        {:__block__, meta, exprs} when is_list(exprs) ->
          {exprs, meta}

        {:fn, meta, clauses} ->
          {clauses, meta}

        _ ->
          {[ast], []}
      end

    %{
      type: type,
      expressions: expressions,
      empty?: expressions == [],
      metadata: metadata
    }
  end

  @spec build_do_block(list(), RDF.IRI.t(), Context.t(), non_neg_integer(), non_neg_integer()) ::
          [RDF.Triple.t()]
  defp build_do_block(
         expressions,
         block_iri,
         context,
         depth \\ 0,
         max_depth \\ @max_expression_depth
       )

  defp build_do_block(_expressions, block_iri, _context, depth, max_depth)
       when depth >= max_depth do
    # Block too deep - return only type triple
    [Helpers.type_triple(block_iri, Core.DoBlock)]
  end

  defp build_do_block([], block_iri, _context, _depth, _max_depth) do
    # Empty block - return only type triple
    [Helpers.type_triple(block_iri, Core.DoBlock)]
  end

  defp build_do_block(expressions, block_iri, context, _depth, _max_depth) do
    # Create type triple for the DoBlock
    type_triple = Helpers.type_triple(block_iri, Core.DoBlock)

    # Build child expression triples and collect link triples separately
    # Each child gets a relative IRI: block_iri/child/{index}
    # Using Enum.reduce with accumulator for O(n) performance instead of O(n²)
    {child_triples, link_triples} =
      expressions
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {expr_ast, index}, {expr_acc, link_acc} ->
        child_iri = fresh_iri(block_iri, "child/#{index}")

        # Use build_expression_triples recursively for child expressions
        # We don't use build/3 here to avoid managing IRI counters
        expr_triples = build_expression_triples(expr_ast, child_iri, context)

        # Link child to block via hasChild property
        link_triple = Helpers.object_property(block_iri, Core.hasChild(), child_iri)

        # Accumulate both expression and link triples
        {expr_acc ++ expr_triples, link_acc ++ [link_triple]}
      end)

    # Link the last expression as the return value
    return_triple =
      case expressions do
        [] ->
          []

        _ ->
          last_child_iri = fresh_iri(block_iri, "child/#{length(expressions) - 1}")
          Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
      end

    # Combine all triples efficiently
    [type_triple | child_triples] ++ link_triples ++ [return_triple]
  end

  @spec build_fn_block(list(), RDF.IRI.t(), Context.t(), non_neg_integer(), non_neg_integer()) ::
          [RDF.Triple.t()]
  defp build_fn_block(clauses, fn_iri, context, depth \\ 0, max_depth \\ @max_expression_depth)

  defp build_fn_block(_clauses, fn_iri, _context, depth, max_depth)
       when depth >= max_depth do
    # Fn block too deep - return only type triple
    [Helpers.type_triple(fn_iri, Core.FnBlock)]
  end

  defp build_fn_block([], fn_iri, _context, _depth, _max_depth) do
    # Empty fn block (no clauses) - return only type triple
    [Helpers.type_triple(fn_iri, Core.FnBlock)]
  end

  defp build_fn_block(clauses, fn_iri, context, _depth, _max_depth) do
    # Create type triple for the FnBlock
    type_triple = Helpers.type_triple(fn_iri, Core.FnBlock)

    # Build clause triples
    # Each clause gets a relative IRI: fn_iri/clause/{index}
    clause_triples =
      clauses
      |> Enum.with_index()
      |> Enum.flat_map(fn {clause_ast, index} ->
        build_fn_clause(clause_ast, fn_iri, index, context)
      end)

    # Combine type triple with all clause triples
    [type_triple | clause_triples]
  end

  # Build a single fn clause
  # Clause AST: {:->, meta, [params, body]}
  # Params is a list containing one element which is a list of parameter patterns
  # Examples:
  #   - Single param: [[{:x, [], ctx}]]
  #   - Multiple params: [[{:x, [], ctx}, {:y, [], ctx}]]
  #   - With guard: [[{:when, [], [{:x, [], ctx}, {:y, [], ctx}, guard_ast]}]]
  defp build_fn_clause({:->, _meta, [params, body]}, fn_iri, clause_index, context) do
    clause_iri = fresh_iri(fn_iri, "clause/#{clause_index}")

    # Extract the actual parameter patterns from the wrapper list
    # params is [[...]] so we need to flatten one level
    param_patterns = List.flatten(params)

    # Parse params to extract parameters and optional guard
    {parameters, guard} = parse_fn_params(param_patterns)

    # Build parameter pattern triples efficiently using Enum.reduce
    {param_triples, param_link_triples} =
      parameters
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {param_ast, param_index}, {expr_acc, link_acc} ->
        param_iri = fresh_iri(clause_iri, "param/#{param_index}")
        pattern_triples = build_pattern(param_ast, param_iri, context)
        link_triple = Helpers.object_property(clause_iri, Core.hasChild(), param_iri)
        {expr_acc ++ pattern_triples, link_acc ++ [link_triple]}
      end)

    # Build guard triples if present
    guard_triples =
      if guard do
        guard_iri = fresh_iri(clause_iri, "guard")
        # Mark guard context
        guard_context_triple =
          Helpers.datatype_property(guard_iri, Core.inGuardContext(), true, RDF.XSD.Boolean)

        guard_expr_triples = build_expression_triples(guard, guard_iri, context)
        guard_link_triple = Helpers.object_property(clause_iri, Core.hasGuard(), guard_iri)

        [guard_context_triple | guard_expr_triples] ++ [guard_link_triple]
      else
        []
      end

    # Build body triples
    body_iri = fresh_iri(clause_iri, "body")
    body_triples = build_expression_triples(body, body_iri, context)
    body_link_triple = Helpers.object_property(clause_iri, Core.hasChild(), body_iri)

    # Link body as return expression for the clause
    return_link_triple = Helpers.object_property(clause_iri, Core.hasReturnExpression(), body_iri)

    # Link clause to fn block
    clause_link_triple = Helpers.object_property(fn_iri, Core.hasClause(), clause_iri)

    # Combine all triples efficiently
    param_triples ++
      param_link_triples ++
      guard_triples ++
      body_triples ++
      [body_link_triple, return_link_triple, clause_link_triple]
  end

  # Parse fn parameters to extract parameters and optional guard
  # Returns: {parameters_list, guard_ast | nil}
  # The input is a flat list of parameter patterns
  # If there's a guard, one of the patterns will be {:when, meta, [param1, param2, ..., guard_ast]}
  defp parse_fn_params(param_patterns) do
    # Find if any param is a :when pattern (contains guard)
    case Enum.find_index(param_patterns, fn
           {:when, _, _} -> true
           _ -> false
         end) do
      nil ->
        # No guard
        {param_patterns, nil}

      index ->
        # Found guard in param at index
        {:when, _, when_args} = Enum.at(param_patterns, index)
        # when_args is [param1, param2, ..., guard_ast]
        {guard_ast, params_without_guard} = List.pop_at(when_args, -1)

        # Build the full params list: params before guard + params after guard
        before_guard = Enum.take(param_patterns, index)
        after_guard = Enum.drop(param_patterns, index + 1)

        {before_guard ++ params_without_guard ++ after_guard, guard_ast}
    end
  end

  # ===========================================================================
  # Try Expression Builder
  # ===========================================================================

  # Builds RDF triples for a try expression with rescue, catch, after, and else blocks.
  #
  # ## AST Pattern
  #
  # {:try, _, [[do: body], [rescue: rescue_clauses], [catch: catch_clauses],
  #            [after: after_block], [else: else_block]]}
  #
  # Each clause is a separate keyword list element. The order may vary.
  #
  # ## Phase 30.1 Scope
  #
  # This implementation (Phase 30.1) handles:
  # - Try body extraction and linking via `hasTryBody`
  # - Detection of optional blocks (rescue, catch, after, else)
  #
  # Full extraction of these blocks will be implemented in later phases:
  # - Phase 30.2: Rescue clauses
  # - Phase 30.3: Catch clauses
  # - Phase 30.4: After blocks
  # - Phase 30.5: Else blocks
  @spec build_try_expression(list(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_try_expression(blocks, try_iri, context) do
    # Extract the try body (required)
    # The do block is identified by keyword :do
    do_block = Keyword.get(blocks, :do)

    # Create type triple for TryExpression
    type_triple = Helpers.type_triple(try_iri, Core.TryExpression)

    # Build try body expression
    body_iri = fresh_iri(try_iri, "body")
    body_triples = build_try_body(do_block, body_iri, context)
    has_try_body_triple = Helpers.object_property(try_iri, Core.hasTryBody(), body_iri)

    # Phase 30.1: Only detect optional blocks, don't extract them yet
    # Their full extraction will be in phases 30.2-30.5
    optional_blocks_triples =
      detect_optional_blocks(blocks, try_iri, context)

    # Combine all triples
    [type_triple] ++ body_triples ++ [has_try_body_triple] ++ optional_blocks_triples
  end

  # Builds the try body expression
  # The do block may be a single expression or a list of expressions
  defp build_try_body(do_block, body_iri, context) when is_list(do_block) do
    # Multiple expressions - wrap in a block
    build_do_block(do_block, body_iri, context)
  end

  defp build_try_body(do_block, body_iri, context) do
    # Single expression - build directly
    build_expression_triples(do_block, body_iri, context)
  end

  # Detects and extracts optional blocks in try expression
  # Phase 30.2: Rescue clauses
  # Phase 30.3: Catch clauses
  # Phase 30.4: After block
  # Phase 30.5: Else block
  defp detect_optional_blocks(blocks, try_iri, context) do
    # Extract rescue clauses if present
    rescue_clauses_triples = build_rescue_clauses(blocks, try_iri, context)

    # Extract catch clauses if present
    catch_clauses_triples = build_catch_clauses(blocks, try_iri, context)

    # Extract after block if present
    after_triples = build_after_block(blocks, try_iri, context)

    # Extract else block if present
    else_triples = build_else_block(blocks, try_iri, context)

    rescue_clauses_triples ++ catch_clauses_triples ++ after_triples ++ else_triples
  end

  # Builds RDF triples for rescue clauses
  # Rescue clauses are in the format: [{:->, _, [[pattern], body]}, ...]
  @spec build_rescue_clauses(keyword(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_rescue_clauses(blocks, try_iri, context) do
    case Keyword.get(blocks, :rescue) do
      nil ->
        []

      rescue_clauses when is_list(rescue_clauses) ->
        # Build each rescue clause
        {clause_triples, clause_iris} =
          rescue_clauses
          |> Enum.with_index()
          |> Enum.reduce({[], []}, fn {clause_ast, index}, {triples_acc, iris_acc} ->
            clause_iri = fresh_iri(try_iri, "rescue/#{index}")

            clause_triples =
              build_rescue_clause(clause_ast, clause_iri, context, index)

            {triples_acc ++ clause_triples, [clause_iri | iris_acc]}
          end)

        # Link clauses via hasRescueClause as an RDF list (preserves order)
        link_triples = link_rescue_clauses(try_iri, Enum.reverse(clause_iris))

        clause_triples ++ link_triples
    end
  end

  # Builds RDF triples for a single rescue clause
  # Clause format: {:->, _, [[pattern], body]}
  @spec build_rescue_clause(Macro.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          [RDF.Triple.t()]
  defp build_rescue_clause({:->, _meta, [[pattern_ast], body_ast]}, clause_iri, context, _index) do
    # Create type triple for RescueClause
    type_triple = Helpers.type_triple(clause_iri, Core.RescueClause)

    # In rescue clauses, a module alias (e.g., RuntimeError) is shorthand for
    # %RuntimeError{}. Convert to struct pattern for consistent handling.
    pattern_ast = normalize_rescue_pattern(pattern_ast)

    # Build exception pattern
    pattern_iri = fresh_iri(clause_iri, "pattern")
    pattern_triples = build_pattern(pattern_ast, pattern_iri, context)

    has_exception_pattern_triple =
      Helpers.object_property(clause_iri, Core.hasExceptionPattern(), pattern_iri)

    # Add refersToExceptionType if it's a struct pattern
    exception_type_triples = extract_exception_type(pattern_ast, clause_iri, context)

    # Build rescue body
    body_iri = fresh_iri(clause_iri, "body")
    body_triples = build_rescue_body(body_ast, body_iri, context)
    has_rescue_body_triple = Helpers.object_property(clause_iri, Core.hasRescueBody(), body_iri)

    # Combine all triples
    [type_triple] ++
      pattern_triples ++
      [has_exception_pattern_triple] ++
      exception_type_triples ++ body_triples ++ [has_rescue_body_triple]
  end

  # Normalizes rescue clause patterns:
  # - Module alias (RuntimeError) -> struct pattern (%RuntimeError{})
  # - Other patterns remain unchanged
  defp normalize_rescue_pattern({:__aliases__, _meta, _name_parts} = alias_ast) do
    {:%, [], [alias_ast, {:%{}, [], []}]}
  end

  defp normalize_rescue_pattern(pattern), do: pattern

  # Extracts exception type from struct pattern
  # Returns triples with refersToExceptionType property
  # Handles both struct patterns (%RuntimeError{}) and module alias patterns (RuntimeError)
  defp extract_exception_type({:%, _meta, [module_ast, {:%{}, _, _pairs}]}, clause_iri, context) do
    module_name = extract_struct_module_name(module_ast)
    module_iri_string = "#{context.base_iri}module/#{module_name}"
    module_iri = RDF.IRI.new(module_iri_string)
    [Helpers.object_property(clause_iri, Core.refersToExceptionType(), module_iri)]
  end

  # In rescue clauses, a module alias alone (e.g., RuntimeError -> ...) is shorthand
  # for catching any exception of that type. Extract the exception type from the alias.
  defp extract_exception_type({:__aliases__, _meta, _name_parts} = alias_ast, clause_iri, context) do
    module_name = extract_struct_module_name(alias_ast)
    module_iri_string = "#{context.base_iri}module/#{module_name}"
    module_iri = RDF.IRI.new(module_iri_string)
    [Helpers.object_property(clause_iri, Core.refersToExceptionType(), module_iri)]
  end

  defp extract_exception_type(_pattern_ast, _clause_iri, _context), do: []

  # Builds the rescue body expression
  defp build_rescue_body(body_ast, body_iri, context) do
    build_clause_body(body_ast, body_iri, context)
  end

  # Links rescue clauses via hasRescueClause property as an RDF list
  # Preserves clause order (important for pattern matching semantics)
  defp link_rescue_clauses(try_iri, clause_iris) do
    link_clauses(try_iri, clause_iris, Core.hasRescueClause())
  end

  # Unified helper for building clause bodies (rescue/catch/after/else)
  # Handles both single expressions and multi-expression blocks
  defp build_clause_body(body_ast, body_iri, context) when is_list(body_ast) do
    build_do_block(body_ast, body_iri, context)
  end

  defp build_clause_body(body_ast, body_iri, context) do
    build_expression_triples(body_ast, body_iri, context)
  end

  # Unified helper for linking clauses via RDF list
  # Preserves clause order for rescue/catch clauses
  defp link_clauses(_parent_iri, [], _property), do: []

  defp link_clauses(parent_iri, clause_iris, property) do
    {list_head, list_triples} = Helpers.build_rdf_list(clause_iris)
    link_triple = Helpers.object_property(parent_iri, property, list_head)
    [link_triple | list_triples]
  end

  # ===========================================================================
  # Phase 30.3: Catch Clauses
  # ===========================================================================

  # Builds RDF triples for catch clauses
  # Catch clauses are in the format: [{:->, _, [[catch_type, pattern] | [pattern]], body}, ...]
  # Typed catch: [{:->, _, [[:throw, pattern]], body}]
  # Untyped catch: [{:->, _, [[pattern]], body}]
  @spec build_catch_clauses(keyword(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_catch_clauses(blocks, try_iri, context) do
    case Keyword.get(blocks, :catch) do
      nil ->
        []

      catch_clauses when is_list(catch_clauses) ->
        # Build each catch clause
        {clause_triples, clause_iris} =
          catch_clauses
          |> Enum.with_index()
          |> Enum.reduce({[], []}, fn {clause_ast, index}, {triples_acc, iris_acc} ->
            clause_iri = fresh_iri(try_iri, "catch/#{index}")

            clause_triples =
              build_catch_clause(clause_ast, clause_iri, context, index)

            {triples_acc ++ clause_triples, [clause_iri | iris_acc]}
          end)

        # Link clauses via hasCatchClause as an RDF list (preserves order)
        link_triples = link_catch_clauses(try_iri, Enum.reverse(clause_iris))

        clause_triples ++ link_triples
    end
  end

  # Builds RDF triples for a single catch clause
  # Clause format: {:->, _, [pattern_list, body]}
  # where pattern_list is:
  #   - [:throw, pattern] or [:error, pattern] or [:exit, pattern] (typed catch)
  #   - [pattern] (untyped catch with single variable)
  #   - [var1, var2] (catch kind and value as two separate variables)
  @spec build_catch_clause(Macro.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          [RDF.Triple.t()]
  defp build_catch_clause({:->, _meta, [pattern_list, body_ast]}, clause_iri, context, _index) do
    case pattern_list do
      [catch_type | [value_pattern]]
      when is_atom(catch_type) and catch_type in [:throw, :error, :exit] ->
        # This is a typed catch: [:throw, pattern] or [:error, pattern] or [:exit, pattern]
        build_catch_clause_with_type(clause_iri, catch_type, value_pattern, body_ast, context)

      [pattern_ast] ->
        # This is an untyped catch: [pattern]
        build_catch_clause_untyped(clause_iri, pattern_ast, body_ast, context)

      [kind_var, value_var] when is_tuple(kind_var) and is_tuple(value_var) ->
        # This catches pattern like: kind, value -> body
        # The catch type is not specified, so we capture both kind and value as variables
        build_catch_clause_with_two_vars(clause_iri, kind_var, value_var, body_ast, context)

      _ ->
        # Fallback for any other pattern (shouldn't happen in valid Elixir code)
        build_catch_clause_untyped(clause_iri, hd(pattern_list), body_ast, context)
    end
  end

  # Builds a typed catch clause (catches :throw, :error, or :exit)
  defp build_catch_clause_with_type(clause_iri, catch_type, value_pattern, body_ast, context) do
    # Create type triple for CatchClause
    type_triple = Helpers.type_triple(clause_iri, Core.CatchClause)

    # Create catch type literal (atom value stored as string)
    catch_type_value = ":" <> Atom.to_string(catch_type)

    catch_type_triple =
      Helpers.datatype_property(
        clause_iri,
        Core.hasCatchType(),
        catch_type_value,
        RDF.XSD.String
      )

    # Build catch value pattern
    pattern_iri = fresh_iri(clause_iri, "pattern")
    pattern_triples = build_pattern(value_pattern, pattern_iri, context)

    has_catch_pattern_triple =
      Helpers.object_property(clause_iri, Core.hasCatchPattern(), pattern_iri)

    # Build catch body
    body_iri = fresh_iri(clause_iri, "body")
    body_triples = build_catch_body(body_ast, body_iri, context)
    has_catch_body_triple = Helpers.object_property(clause_iri, Core.hasCatchBody(), body_iri)

    # Combine all triples
    [type_triple] ++
      [catch_type_triple] ++
      pattern_triples ++
      [has_catch_pattern_triple] ++
      body_triples ++ [has_catch_body_triple]
  end

  # Builds an untyped catch clause (catches all types)
  defp build_catch_clause_untyped(clause_iri, pattern_ast, body_ast, context) do
    # Create type triple for CatchClause
    type_triple = Helpers.type_triple(clause_iri, Core.CatchClause)

    # Build catch value pattern
    pattern_iri = fresh_iri(clause_iri, "pattern")
    pattern_triples = build_pattern(pattern_ast, pattern_iri, context)

    has_catch_pattern_triple =
      Helpers.object_property(clause_iri, Core.hasCatchPattern(), pattern_iri)

    # Build catch body
    body_iri = fresh_iri(clause_iri, "body")
    body_triples = build_catch_body(body_ast, body_iri, context)
    has_catch_body_triple = Helpers.object_property(clause_iri, Core.hasCatchBody(), body_iri)

    # Combine all triples
    [type_triple] ++
      pattern_triples ++
      [has_catch_pattern_triple] ++
      body_triples ++ [has_catch_body_triple]
  end

  # Builds a catch clause with two variables (kind, value)
  # This handles pattern like: catch kind, value -> body
  # The catch type is not specified, so we capture both as separate variables
  defp build_catch_clause_with_two_vars(clause_iri, kind_var, value_var, body_ast, context) do
    # Create type triple for CatchClause
    type_triple = Helpers.type_triple(clause_iri, Core.CatchClause)

    # Build kind pattern (first variable)
    kind_pattern_iri = fresh_iri(clause_iri, "kind_pattern")
    kind_pattern_triples = build_pattern(kind_var, kind_pattern_iri, context)

    has_kind_pattern_triple =
      Helpers.object_property(clause_iri, Core.hasCatchPattern(), kind_pattern_iri)

    # Build value pattern (second variable)
    value_pattern_iri = fresh_iri(clause_iri, "value_pattern")
    value_pattern_triples = build_pattern(value_var, value_pattern_iri, context)
    # We link the value pattern to the kind pattern or the clause
    # For simplicity, we'll link both patterns to the clause
    has_value_pattern_triple =
      Helpers.object_property(clause_iri, Core.hasCatchPattern(), value_pattern_iri)

    # Build catch body
    body_iri = fresh_iri(clause_iri, "body")
    body_triples = build_catch_body(body_ast, body_iri, context)
    has_catch_body_triple = Helpers.object_property(clause_iri, Core.hasCatchBody(), body_iri)

    # Combine all triples
    [type_triple] ++
      kind_pattern_triples ++
      [has_kind_pattern_triple] ++
      value_pattern_triples ++
      [has_value_pattern_triple] ++
      body_triples ++ [has_catch_body_triple]
  end

  # Builds the catch body expression
  defp build_catch_body(body_ast, body_iri, context) do
    build_clause_body(body_ast, body_iri, context)
  end

  # Links catch clauses via hasCatchClause property as an RDF list
  # Preserves clause order (important for pattern matching semantics)
  defp link_catch_clauses(try_iri, clause_iris) do
    link_clauses(try_iri, clause_iris, Core.hasCatchClause())
  end

  # ===========================================================================
  # Phase 30.4: After Block
  # ===========================================================================

  # Builds RDF triples for the after block in try expression
  # After block is a single expression that always executes
  # The compiler wraps multiple expressions in a {:__block__, [], [...]} tuple
  @spec build_after_block(keyword(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_after_block(blocks, try_iri, context) do
    case Keyword.get(blocks, :after) do
      nil ->
        []

      after_ast ->
        # Generate after IRI
        after_iri = fresh_iri(try_iri, "after")

        # Build after block expression
        after_triples = build_expression_triples(after_ast, after_iri, context)

        # Link via hasAfterClause property
        link_triple = Helpers.object_property(try_iri, Core.hasAfterClause(), after_iri)

        after_triples ++ [link_triple]
    end
  end

  # ===========================================================================
  # Phase 30.5: Else Block
  # ===========================================================================

  # Builds RDF triples for the else block in try expression
  # Else block is a single expression that only executes when no exception occurs
  # The compiler wraps multiple expressions in a {:__block__, [], [...]} tuple
  @spec build_else_block(keyword(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_else_block(blocks, try_iri, context) do
    case Keyword.get(blocks, :else) do
      nil ->
        []

      else_ast ->
        # Generate else IRI
        else_iri = fresh_iri(try_iri, "else")

        # Build else block expression
        else_triples = build_expression_triples(else_ast, else_iri, context)

        # Link via hasElseClause property
        link_triple = Helpers.object_property(try_iri, Core.hasElseClause(), else_iri)

        else_triples ++ [link_triple]
    end
  end

  # ===========================================================================
  # Phase 30.6: Raise Expression
  # ===========================================================================

  # Builds RDF triples for a raise expression
  # raise/1: raise "message" -> raises RuntimeError with message
  # raise/2: raise Exception, "message" -> raises Exception with message
  # raise/2: raise Exception, [keyword: value] -> raises with attributes
  # raise/1: raise Exception -> raises Exception with default message
  @spec build_raise(term(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_raise(args, expr_iri, context) do
    normalized_args = normalize_raise_args(args)

    # Create type triple for RaiseExpression
    type_triple = Helpers.type_triple(expr_iri, Core.RaiseExpression)

    # Process the args based on their structure
    {exception_triples, message_triples, argument_triples} =
      process_raise_args(normalized_args, expr_iri, context)

    # Combine all triples
    [type_triple] ++ exception_triples ++ message_triples ++ argument_triples
  end

  # Processes raise expression arguments
  # Returns {exception_triples, message_triples, argument_triples}
  # Order matters - more specific patterns must come first

  # Helper: builds exception type triple for raise expression
  defp build_exception_type_triple(alias_ast, expr_iri, context) do
    exception_module_name = extract_module_name(alias_ast)
    exception_module_iri = RDF.iri("#{context.base_iri}module/#{exception_module_name}")
    Helpers.object_property(expr_iri, Core.refersToExceptionType(), exception_module_iri)
  end

  # Helper: builds default RuntimeError exception triple
  defp build_default_exception_triple(expr_iri, context) do
    exception_module_iri = RDF.iri("#{context.base_iri}module/Elixir.RuntimeError")
    Helpers.object_property(expr_iri, Core.refersToExceptionType(), exception_module_iri)
  end

  # Helper: builds message triples for raise expression
  defp build_message_triples(message_ast, expr_iri, context) do
    message_iri = fresh_iri(expr_iri, "message")
    message_triples = build_expression_triples(message_ast, message_iri, context)
    message_link_triple = Helpers.object_property(expr_iri, Core.hasMessage(), message_iri)
    message_triples ++ [message_link_triple]
  end

  # raise/0 in some AST forms may be represented with non-list args.
  # Treat these as "re-raise" shape with no explicit arguments.
  defp normalize_raise_args(args) when is_list(args), do: args
  defp normalize_raise_args(_), do: []

  defp process_raise_args([], _expr_iri, _context) do
    {[], [], []}
  end

  defp process_raise_args([{:__aliases__, _, _module_path} = alias_ast], expr_iri, context) do
    # raise Exception - raises specific exception with default message
    exception_triple = build_exception_type_triple(alias_ast, expr_iri, context)
    {[exception_triple], [], []}
  end

  defp process_raise_args([message_ast], expr_iri, context)
       when is_binary(message_ast) or is_tuple(message_ast) do
    # raise "message" - raises RuntimeError with message
    # Default exception is RuntimeError
    # Note: This clause must come after the __aliases__ clause to avoid matching module aliases
    exception_triple = build_default_exception_triple(expr_iri, context)
    message_triples = build_message_triples(message_ast, expr_iri, context)
    {[exception_triple], message_triples, []}
  end

  defp process_raise_args(
         [{:__aliases__, _, _module_path} = alias_ast, keyword_args],
         expr_iri,
         context
       )
       when is_list(keyword_args) do
    # raise Exception, [key: value] - raises with keyword arguments
    exception_triple = build_exception_type_triple(alias_ast, expr_iri, context)
    # Process keyword arguments
    argument_triples = process_raise_keywords(keyword_args, expr_iri, 1, [])
    {[exception_triple], [], argument_triples}
  end

  defp process_raise_args(
         [{:__aliases__, _, _module_path} = alias_ast, message_ast],
         expr_iri,
         context
       ) do
    # raise Exception, "message" - raises specific exception with message
    exception_triple = build_exception_type_triple(alias_ast, expr_iri, context)
    message_triples = build_message_triples(message_ast, expr_iri, context)
    {[exception_triple], message_triples, []}
  end

  # Processes keyword arguments for raise expression
  defp process_raise_keywords([], _expr_iri, _index, acc), do: Enum.reverse(acc)

  defp process_raise_keywords([{_key, value_ast} | rest], expr_iri, index, acc) do
    # Get the value as a string literal (for keyword arguments)
    arg_value = normalize_keyword_value(value_ast)

    arg_triple =
      Helpers.datatype_property(expr_iri, Core.hasArgument(), arg_value, RDF.XSD.String)

    # Add key annotation (we can't directly store the key, so we'll use a comment or skip)
    # For now, we'll just store the value with hasArgument
    process_raise_keywords(rest, expr_iri, index + 1, [arg_triple | acc])
  end

  # Normalizes keyword value to string
  defp normalize_keyword_value(value_ast) when is_binary(value_ast), do: value_ast
  defp normalize_keyword_value(value_ast) when is_atom(value_ast), do: Atom.to_string(value_ast)
  defp normalize_keyword_value(value_ast) when is_number(value_ast), do: to_string(value_ast)
  defp normalize_keyword_value(_), do: ""

  # ===========================================================================
  # Phase 30.7: Throw Expression
  # ===========================================================================

  # Builds RDF triples for a throw expression
  # throw/1: throw value - throws any value to be caught by a catch clause
  # Used for non-local returns, distinct from raise (exception handling)
  @spec build_throw(any(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  defp build_throw(value_ast, expr_iri, context) do
    # Create type triple for ThrowExpression
    type_triple = Helpers.type_triple(expr_iri, Core.ThrowExpression)

    # Create IRI for thrown value expression
    value_iri = fresh_iri(expr_iri, "value")

    # Recursively build the thrown value expression
    value_triples = build_expression_triples(value_ast, value_iri, context)

    # Link throw expression to its thrown value
    has_thrown_value_triple = Helpers.object_property(expr_iri, Core.hasThrownValue(), value_iri)

    # Combine all triples
    List.wrap(type_triple) ++ value_triples ++ [has_thrown_value_triple]
  end

  # ===========================================================================
  # Expression Dispatch
  # ===========================================================================

  @doc """
  Builds RDF triples for an expression given its IRI.

  This is the internal dispatch function that pattern matches on AST nodes
  and generates the appropriate RDF triples. Unlike `build/3`, this function:

  - Does NOT check mode (assumes caller validated)
  - Does NOT manage context counter
  - Returns a list of triples directly (not wrapped in {:ok, ...})
  - Requires an explicit expr_iri parameter

  ## Parameters

  - `ast` - The Elixir AST node (3-tuple format or literal)
  - `expr_iri` - The IRI to use for this expression
  - `context` - The builder context (for configuration, not counter management)

  ## Returns

  A list of RDF triples representing the expression.

  ## When to Use

  Use this function when implementing operator builders that need to
  recursively build child expressions. For top-level expression building,
  use `build/3` instead.
  """
  @spec build_expression_triples(Macro.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_expression_triples(ast, expr_iri, context) do
    do_build_expression_triples(ast, expr_iri, context) ++
      source_location_triples(ast, expr_iri, context)
  end

  defp do_build_expression_triples(ast, expr_iri, context)

  # Comparison operators
  defp do_build_expression_triples({:==, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:==, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:!=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:!=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:===, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:===, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:!==, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:!==, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:<, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:>, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:<=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  defp do_build_expression_triples({:>=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:>=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  # Logical operators
  defp do_build_expression_triples({:and, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:and, left, right, expr_iri, context, Core.LogicalOperator)
  end

  defp do_build_expression_triples({:or, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:or, left, right, expr_iri, context, Core.LogicalOperator)
  end

  defp do_build_expression_triples({:&&, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:&&, left, right, expr_iri, context, Core.LogicalOperator)
  end

  defp do_build_expression_triples({:||, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:||, left, right, expr_iri, context, Core.LogicalOperator)
  end

  # Unary operators (not, !, +, -)
  defp do_build_expression_triples({:not, _, [arg]}, expr_iri, context) do
    build_unary(:not, arg, expr_iri, context)
  end

  defp do_build_expression_triples({:!, _, [arg]}, expr_iri, context) do
    build_unary(:!, arg, expr_iri, context)
  end

  # Unary arithmetic operators (must come before binary to match single-argument case)
  defp do_build_expression_triples({:-, _, [operand]}, expr_iri, context) do
    build_unary_arithmetic(:-, operand, expr_iri, context)
  end

  defp do_build_expression_triples({:+, _, [operand]}, expr_iri, context) do
    build_unary_arithmetic(:+, operand, expr_iri, context)
  end

  # Arithmetic operators
  defp do_build_expression_triples({:+, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:+, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  defp do_build_expression_triples({:-, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:-, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  defp do_build_expression_triples({:*, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:*, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  defp do_build_expression_triples({:/, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:/, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  defp do_build_expression_triples({:div, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:div, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  defp do_build_expression_triples({:rem, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:rem, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  # Pipe operator
  defp do_build_expression_triples({:|>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:|>, left, right, expr_iri, context, Core.PipeOperator)
  end

  # String concatenation
  defp do_build_expression_triples({:<>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<>, left, right, expr_iri, context, Core.StringConcatOperator)
  end

  # List operators
  defp do_build_expression_triples({:++, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:++, left, right, expr_iri, context, Core.ListOperator)
  end

  defp do_build_expression_triples({:--, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:--, left, right, expr_iri, context, Core.ListOperator)
  end

  # Match operator
  defp do_build_expression_triples({:=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:=, left, right, expr_iri, context, Core.MatchOperator)
  end

  # Capture operator (&)
  # Matches: &1, &2, &3 (argument capture)
  # Matches: &Mod.fun/arity, &Mod.fun (function reference)
  defp do_build_expression_triples({:&, _, [arg]}, expr_iri, _context) when is_integer(arg) do
    build_capture_index(arg, expr_iri)
  end

  defp do_build_expression_triples({:&, _, [{:/, _, [function_ref, arity]}]}, expr_iri, context) do
    build_capture_function_ref(function_ref, arity, expr_iri, context)
  end

  defp do_build_expression_triples({:&, _, [function_ref]}, expr_iri, context) do
    build_capture_function_ref(function_ref, nil, expr_iri, context)
  end

  # In operator
  defp do_build_expression_triples({:in, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:in, left, right, expr_iri, context, Core.InOperator)
  end

  # Module alias reference: MyApp, MyApp.Users, etc.
  # AST: {:__aliases__, _, parts} where parts is [:MyApp] or [:MyApp, :Users]
  # Must come BEFORE literal handlers (atoms would also match some aliases)
  defp do_build_expression_triples({:__aliases__, _, parts}, expr_iri, context) do
    build_module_reference(parts, expr_iri, context)
  end

  # Integer literals
  defp do_build_expression_triples(int, expr_iri, _context) when is_integer(int) do
    build_literal(int, expr_iri, Core.IntegerLiteral, Core.integerValue(), RDF.XSD.Integer)
  end

  # Float literals
  defp do_build_expression_triples(float, expr_iri, _context) when is_float(float) do
    build_literal(float, expr_iri, Core.FloatLiteral, Core.floatValue(), RDF.XSD.Double)
  end

  # String literals (binaries)
  defp do_build_expression_triples(str, expr_iri, _context) when is_binary(str) do
    build_literal(str, expr_iri, Core.StringLiteral, Core.stringValue(), RDF.XSD.String)
  end

  # List literals and charlist literals (lists of integers representing UTF-8 codepoints)
  # Must come before generic handlers that might match lists
  defp do_build_expression_triples(list, expr_iri, context) when is_list(list) do
    cond do
      # Check for keyword list: all elements are 2-tuples with atom first elements
      # Must come before cons pattern check (cons lists are also lists)
      Keyword.keyword?(list) and list != [] ->
        build_keyword_list(list, expr_iri, context)

      # Check for cons pattern: [{:|, _, [head, tail]}]
      cons_pattern?(list) ->
        build_cons_list(list, expr_iri, context)

      # Check for regular list (non-charlist):
      # - Contains non-integer elements
      # - Contains integers outside Unicode range
      # - Is a nested list structure
      not charlist?(list) ->
        build_list_literal(list, expr_iri, context)

      # Otherwise, it's a charlist (all elements are valid Unicode codepoints)
      true ->
        string_value = List.to_string(list)

        build_literal(
          string_value,
          expr_iri,
          Core.CharlistLiteral,
          Core.charlistValue(),
          RDF.XSD.String
        )
    end
  end

  # Binary literals (<<>>)
  # Matches binary construction patterns like <<65>> or <<x::8>>
  # Note: Literal binaries like <<"hello">> compile to plain binaries and are caught by is_binary/1
  defp do_build_expression_triples({:<<>>, _meta, segments}, expr_iri, _context) do
    if binary_literal?(segments) do
      # All segments are literal integers - we can construct the binary
      binary_value = construct_binary_from_literals(segments)
      # RDF.XSD.Base64Binary handles base64 encoding internally
      build_literal(
        binary_value,
        expr_iri,
        Core.BinaryLiteral,
        Core.binaryValue(),
        RDF.XSD.Base64Binary
      )
    else
      # Binary contains variables or complex type specs
      # For now, treat as generic expression
      # Full pattern support deferred to pattern phase
      build_generic_expression(expr_iri)
    end
  end

  # Atom literals (including true, false, nil)
  defp do_build_expression_triples(atom, expr_iri, _context) when is_atom(atom) do
    build_atom_literal(atom, expr_iri)
  end

  # Tuple literals - must come before local call handler
  # General tuple form: {:{}, meta, elements} - covers empty tuple and 3+ tuples
  defp do_build_expression_triples({:{}, _meta, elements}, expr_iri, context) do
    build_tuple_literal(elements, expr_iri, context)
  end

  # 2-tuple: {left, right} - special form, not a 3-tuple AST node
  defp do_build_expression_triples({left, right}, expr_iri, context) do
    build_tuple_literal([left, right], expr_iri, context)
  end

  # Struct literals - must come before map handler (both start with :%)
  # Struct pattern: {:%, meta, [module_ast, map_ast]}
  defp do_build_expression_triples({:%, _meta, [module_ast, map_ast]}, expr_iri, context) do
    build_struct_literal(module_ast, map_ast, expr_iri, context)
  end

  # Map literals
  # Map pattern: {:%{}, meta, pairs}
  defp do_build_expression_triples({:%{}, _meta, pairs}, expr_iri, context) do
    build_map_literal(pairs, expr_iri, context)
  end

  # Range literals: 1..10, 1..10//2, a..b, etc.
  # Simple range pattern: {:.., meta, [first, last]}
  # Step range pattern: {:"..//", meta, [first, last, step]}
  defp do_build_expression_triples({:.., _meta, [first, last]}, expr_iri, context) do
    build_range_literal(first, last, expr_iri, context)
  end

  defp do_build_expression_triples({:..//, _meta, [first, last, step]}, expr_iri, context) do
    build_range_literal(first, last, step, expr_iri, context)
  end

  # Do blocks: {:__block__, meta, expressions}
  # Multi-expression blocks from do..end or begin..end
  # Must come before local call handler to avoid being matched as :__block__ call
  defp do_build_expression_triples({:__block__, _meta, expressions}, expr_iri, context) do
    build_do_block(expressions, expr_iri, context)
  end

  # Fn blocks: {:fn, meta, clauses}
  # Anonymous functions with fn...end syntax
  # Must come before local call handler to avoid being matched as :fn call
  defp do_build_expression_triples({:fn, _meta, clauses}, expr_iri, context) do
    build_fn_block(clauses, expr_iri, context)
  end

  # Control-flow forms must be represented at the rooted structural IRI. The
  # module-wide ControlFlowBuilder cannot provide that ownership because it
  # analyzes a complete module body rather than an individual function clause.
  defp do_build_expression_triples({kind, _meta, _args} = ast, expr_iri, context)
       when kind in [:if, :unless, :cond] do
    case Conditional.extract_conditional(ast) do
      {:ok, conditional} -> build_conditional_expression(conditional, expr_iri, context)
      {:error, _reason} -> raise ArgumentError, "invalid conditional AST"
    end
  end

  defp do_build_expression_triples({:case, _meta, _args} = ast, expr_iri, context) do
    case CaseWith.extract_case(ast) do
      {:ok, case_expression} -> build_case_expression(case_expression, expr_iri, context)
      {:error, _reason} -> raise ArgumentError, "invalid case AST"
    end
  end

  defp do_build_expression_triples({:with, _meta, _args} = ast, expr_iri, context) do
    case CaseWith.extract_with(ast) do
      {:ok, with_expression} -> build_with_expression(with_expression, expr_iri, context)
      {:error, _reason} -> raise ArgumentError, "invalid with AST"
    end
  end

  defp do_build_expression_triples({:receive, _meta, _args} = ast, expr_iri, context) do
    case CaseWith.extract_receive(ast) do
      {:ok, receive_expression} ->
        build_receive_expression(receive_expression, expr_iri, context)

      {:error, _reason} ->
        raise ArgumentError, "invalid receive AST"
    end
  end

  defp do_build_expression_triples({:for, _meta, _args} = ast, expr_iri, context) do
    case Comprehension.extract(ast) do
      {:ok, comprehension} -> build_comprehension_expression(comprehension, expr_iri, context)
      {:error, _reason} -> raise ArgumentError, "invalid comprehension AST"
    end
  end

  defp do_build_expression_triples({:exit, _meta, [reason]}, expr_iri, context) do
    child_expression(
      expr_iri,
      "reason",
      reason,
      Core.hasExitReason(),
      context,
      Core.ExitExpression
    )
  end

  # Raise expressions: {:raise, _, args}
  # Phase 30.6: Raise Expression Extraction
  # Args can be:
  # - [message] - raises RuntimeError with message
  # - [exception] - raises specific exception with no message
  # - [exception, message] - raises specific exception with message
  # - [exception, [keyword: value]] - raises with keyword arguments
  defp do_build_expression_triples({:raise, _meta, args}, expr_iri, context) do
    build_raise(args, expr_iri, context)
  end

  # Throw expressions: {:throw, _, [value]}
  # Phase 30.7: Throw Expression Extraction
  # Throws any value to be caught by a catch clause (non-local return)
  # The args list contains exactly one element: the value being thrown
  defp do_build_expression_triples({:throw, _meta, [value_ast]}, expr_iri, context) do
    build_throw(value_ast, expr_iri, context)
  end

  # Try expressions: {:try, _, [blocks]}
  # Exception handling with rescue, catch, after, and else blocks
  # The blocks are in a single keyword list: [do: body, rescue: ..., ...]
  defp do_build_expression_triples({:try, _meta, [blocks]}, expr_iri, context) do
    build_try_expression(blocks, expr_iri, context)
  end

  # Local call: function(args) - must come before variable pattern
  # Note: This handler also checks for sigil atoms (sigil_c, sigil_r, sigil_s, sigil_w)
  # and dispatches them to the sigil literal handler
  defp do_build_expression_triples({function, meta, args}, expr_iri, context)
       when is_atom(function) and is_list(meta) and is_list(args) do
    # Check if this is a sigil literal (pattern: {:sigil_CHAR, meta, [content_ast, modifiers_ast]})
    # Sigils have exactly 2 elements in args list: [content_ast, modifiers_ast]
    # We check if the atom name starts with "sigil_"
    if is_sigil_atom?(function) and length(args) == 2 do
      build_sigil_literal(function, Enum.at(args, 0), Enum.at(args, 1), expr_iri, context)
    else
      build_local_call(function, args, expr_iri, context)
    end
  end

  # Anonymous function call: variable.(args)
  # Must come BEFORE remote call handler to match the more specific pattern
  # AST: {{:., _, [{var, [], Elixir}], _, args}
  # The key identifier is ctx = Elixir (not nil) in the variable tuple
  # This is distinct from remote calls which have [module, function] as 2 elements
  defp do_build_expression_triples(
         {{:., _, [{var, [], Elixir}]}, _, args},
         expr_iri,
         context
       ) do
    # Reconstruct the variable tuple for build_variable
    var_ast = {var, [], Elixir}
    build_anon_call(var_ast, args, expr_iri, context)
  end

  # Remote call: Module.function(args)
  defp do_build_expression_triples(
         {{:., _, [module, function]}, _, args},
         expr_iri,
         context
       ) do
    build_remote_call(module, function, args, expr_iri, context)
  end

  # Variable pattern: {name, meta, ctx} where ctx is nil or an atom
  # This must come after calls to avoid matching function calls
  defp do_build_expression_triples({name, meta, ctx} = var, expr_iri, build_context)
       when is_atom(name) and is_list(meta) and (is_nil(ctx) or is_atom(ctx)) do
    build_variable(var, expr_iri, build_context)
  end

  # Wildcard pattern
  defp do_build_expression_triples({:_}, expr_iri, _context) do
    build_wildcard(expr_iri)
  end

  # Fallback for unknown expressions
  defp do_build_expression_triples(_ast, expr_iri, _context) do
    build_generic_expression(expr_iri)
  end

  defp source_location_triples({_form, metadata, _args}, expr_iri, context)
       when is_list(metadata) do
    positions =
      [
        {Core.startLine(), Keyword.get(metadata, :line)},
        {Core.startColumn(), Keyword.get(metadata, :column)},
        {Core.endLine(), metadata_end_value(metadata, :line)},
        {Core.endColumn(), metadata_end_value(metadata, :column)}
      ]
      |> Enum.filter(fn {_predicate, value} -> is_integer(value) and value > 0 end)

    if positions == [] do
      []
    else
      location_iri = fresh_iri(expr_iri, "location")

      position_triples =
        Enum.map(positions, fn {predicate, value} ->
          Helpers.datatype_property(location_iri, predicate, value, RDF.XSD.PositiveInteger)
        end)

      file_triples =
        case context.file_path do
          path when is_binary(path) and path != "" ->
            file_iri = IRI.for_source_file(context.base_iri, path)
            [Helpers.object_property(location_iri, Core.inSourceFile(), file_iri)]

          _other ->
            []
        end

      [
        Helpers.object_property(expr_iri, Core.hasSourceLocation(), location_iri),
        Helpers.type_triple(location_iri, Core.SourceLocation)
        | position_triples ++ file_triples
      ]
    end
  end

  defp source_location_triples(_ast, _expr_iri, _context), do: []

  defp metadata_end_value(metadata, key) do
    [:end, :closing, :end_of_expression]
    |> Enum.find_value(fn metadata_key ->
      case Keyword.get(metadata, metadata_key) do
        nested when is_list(nested) -> Keyword.get(nested, key)
        _other -> nil
      end
    end)
  end

  defp build_conditional_expression(%{type: type} = conditional, expr_iri, context)
       when type in [:if, :unless] do
    expression_type = if(type == :if, do: Core.IfExpression, else: Core.UnlessExpression)

    condition_triples =
      expression_link(expr_iri, "condition", conditional.condition, Core.hasCondition(), context)

    branch_triples =
      Enum.flat_map(conditional.branches, fn branch ->
        case branch.type do
          :then -> expression_link(expr_iri, "then", branch.body, Core.hasThenBranch(), context)
          :else -> expression_link(expr_iri, "else", branch.body, Core.hasElseBranch(), context)
        end
      end)

    [Helpers.type_triple(expr_iri, expression_type) | condition_triples ++ branch_triples]
  end

  defp build_conditional_expression(%{type: :cond, clauses: clauses}, expr_iri, context) do
    clause_triples =
      clauses
      |> Enum.with_index()
      |> Enum.flat_map(fn {clause, index} ->
        clause_iri = fresh_iri(expr_iri, "clause/#{index}")

        [
          Helpers.type_triple(clause_iri, Core.Expression),
          Helpers.object_property(expr_iri, Core.hasClause(), clause_iri)
          | expression_link(
              clause_iri,
              "condition",
              clause.condition,
              Core.hasCondition(),
              context
            ) ++
              expression_link(
                clause_iri,
                "body",
                clause.body,
                Core.hasThenBranch(),
                context
              )
        ]
      end)

    [Helpers.type_triple(expr_iri, Core.CondExpression) | clause_triples]
  end

  defp build_case_expression(case_expression, expr_iri, context) do
    subject_triples =
      expression_link(
        expr_iri,
        "subject",
        case_expression.subject,
        Core.hasCondition(),
        context
      )

    clause_triples =
      build_pattern_clauses(case_expression.clauses, expr_iri, "clause", context)

    [Helpers.type_triple(expr_iri, Core.CaseExpression) | subject_triples ++ clause_triples]
  end

  defp build_with_expression(with_expression, expr_iri, context) do
    match_triples =
      with_expression.clauses
      |> Enum.with_index()
      |> Enum.flat_map(fn {clause, index} ->
        clause_iri = fresh_iri(expr_iri, "clause/#{index}")

        [
          Helpers.type_triple(clause_iri, Core.Expression),
          Helpers.object_property(expr_iri, Core.hasClause(), clause_iri)
          | pattern_link(clause_iri, "pattern", clause.pattern, context) ++
              expression_link(
                clause_iri,
                "expression",
                clause.expression,
                Core.hasCondition(),
                context
              )
        ]
      end)

    body_triples =
      expression_link(expr_iri, "body", with_expression.body, Core.hasThenBranch(), context)

    else_triples = build_with_else_clauses(with_expression.else_clauses, expr_iri, context)

    [
      Helpers.type_triple(expr_iri, Core.WithExpression)
      | match_triples ++ body_triples ++ else_triples
    ]
  end

  defp build_with_else_clauses([], _expr_iri, _context), do: []

  defp build_with_else_clauses(clauses, expr_iri, context) do
    else_iri = fresh_iri(expr_iri, "else")

    [
      Helpers.type_triple(else_iri, Core.DoBlock),
      Helpers.object_property(expr_iri, Core.hasElseBranch(), else_iri)
      | build_pattern_clauses(clauses, else_iri, "clause", context)
    ]
  end

  defp build_receive_expression(receive_expression, expr_iri, context) do
    clause_triples =
      build_pattern_clauses(receive_expression.clauses, expr_iri, "clause", context)

    after_triples =
      case receive_expression.after_clause do
        nil ->
          []

        after_clause ->
          after_iri = fresh_iri(expr_iri, "after")

          [
            Helpers.type_triple(after_iri, Core.Expression),
            Helpers.object_property(expr_iri, Core.hasAfterTimeout(), after_iri)
            | expression_link(
                after_iri,
                "timeout",
                after_clause.timeout,
                Core.hasCondition(),
                context
              ) ++
                expression_link(
                  after_iri,
                  "body",
                  after_clause.body,
                  Core.hasThenBranch(),
                  context
                )
          ]
      end

    [Helpers.type_triple(expr_iri, Core.ReceiveExpression) | clause_triples ++ after_triples]
  end

  defp build_comprehension_expression(comprehension, expr_iri, context) do
    generator_triples =
      comprehension.generators
      |> Enum.with_index()
      |> Enum.flat_map(fn {generator, index} ->
        generator_iri = fresh_iri(expr_iri, "generator/#{index}")

        generator_type =
          if generator.type == :bitstring_generator,
            do: Core.BitstringGenerator,
            else: Core.Generator

        [
          Helpers.type_triple(generator_iri, generator_type),
          Helpers.object_property(expr_iri, Core.hasGenerator(), generator_iri)
          | pattern_link(generator_iri, "pattern", generator.pattern, context) ++
              expression_link(
                generator_iri,
                "enumerable",
                generator.enumerable,
                Core.hasEnumerable(),
                context
              )
        ]
      end)

    filter_triples =
      comprehension.filters
      |> Enum.with_index()
      |> Enum.flat_map(fn {filter, index} ->
        filter_iri = fresh_iri(expr_iri, "filter/#{index}")

        [
          Helpers.type_triple(filter_iri, Core.Filter),
          Helpers.object_property(expr_iri, Core.hasFilter(), filter_iri)
          | expression_link(
              filter_iri,
              "expression",
              filter.expression,
              Core.hasFilterExpression(),
              context
            )
        ]
      end)

    body_triples =
      expression_link(
        expr_iri,
        "collect",
        comprehension.body,
        Core.hasCollectExpression(),
        context
      )

    option_triples = comprehension_option_triples(comprehension.options, expr_iri, context)

    [
      Helpers.type_triple(expr_iri, Core.ForComprehension)
      | generator_triples ++ filter_triples ++ body_triples ++ option_triples
    ]
  end

  defp comprehension_option_triples(options, expr_iri, context) do
    into =
      if options.into == nil,
        do: [],
        else: expression_link(expr_iri, "into", options.into, Core.hasIntoOption(), context)

    reduce =
      if options.reduce == nil,
        do: [],
        else: expression_link(expr_iri, "reduce", options.reduce, Core.hasReduceOption(), context)

    uniq =
      if options.uniq,
        do: [Helpers.datatype_property(expr_iri, Core.hasUniqOption(), true, RDF.XSD.Boolean)],
        else: []

    into ++ reduce ++ uniq
  end

  defp build_pattern_clauses(
         clauses,
         parent_iri,
         role,
         context,
         link_predicate \\ Core.hasClause()
       ) do
    clauses
    |> Enum.with_index()
    |> Enum.flat_map(fn {clause, index} ->
      clause_iri = fresh_iri(parent_iri, "#{role}/#{index}")

      guard_triples =
        if clause.guard == nil,
          do: [],
          else: expression_link(clause_iri, "guard", clause.guard, Core.hasGuard(), context)

      [
        Helpers.type_triple(clause_iri, Core.Expression),
        Helpers.object_property(parent_iri, link_predicate, clause_iri)
        | pattern_link(clause_iri, "pattern", clause.pattern, context) ++
            guard_triples ++
            expression_link(
              clause_iri,
              "body",
              clause.body,
              Core.hasThenBranch(),
              context
            )
      ]
    end)
  end

  defp child_expression(parent_iri, role, ast, predicate, context, parent_type) do
    [
      Helpers.type_triple(parent_iri, parent_type)
      | expression_link(parent_iri, role, ast, predicate, context)
    ]
  end

  defp expression_link(parent_iri, role, ast, predicate, context) do
    child_iri = fresh_iri(parent_iri, role)

    [
      Helpers.object_property(parent_iri, predicate, child_iri)
      | build_expression_triples(ast, child_iri, context)
    ]
  end

  defp pattern_link(parent_iri, role, ast, context) do
    pattern_iri = fresh_iri(parent_iri, role)

    [
      Helpers.object_property(parent_iri, Core.hasPattern(), pattern_iri)
      | build_pattern(ast, pattern_iri, context)
    ]
  end

  # ===========================================================================
  # Builder Functions
  # ===========================================================================

  # Unary operators (not, !)
  defp build_unary(op, arg, expr_iri, context) do
    build_unary_operator(op, arg, expr_iri, context, Core.LogicalOperator)
  end

  # Unary arithmetic operators (+, -)
  defp build_unary_arithmetic(op, operand, expr_iri, context) do
    build_unary_operator(op, operand, expr_iri, context, Core.ArithmeticOperator)
  end

  # ===========================================================================
  # Core Expression Builders
  # ===========================================================================

  # Builds a binary operator with left and right operands
  @spec build_binary_operator(atom(), term(), term(), RDF.IRI.t(), Context.t(), module()) ::
          list()
  defp build_binary_operator(op, left_ast, right_ast, expr_iri, context, type_class) do
    # Generate relative IRIs for child expressions
    left_iri = fresh_iri(expr_iri, "left")
    right_iri = fresh_iri(expr_iri, "right")

    # Recursively build operand triples using build_expression_triples/3 directly.
    # We use build_expression_triples/3 instead of build/3 here because:
    # 1. The expr_iri for each operand is already known (left_iri, right_iri)
    # 2. Mode checking was already done by the parent build/3 call
    # 3. We don't need additional IRI counter management (child IRIs are relative)
    # 4. We need direct access to the triples list for concatenation
    left_triples = build_expression_triples(left_ast, left_iri, context)
    right_triples = build_expression_triples(right_ast, right_iri, context)

    # Build operator triples
    operator_triples = [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String),
      Helpers.object_property(expr_iri, Core.hasLeftOperand(), left_iri),
      Helpers.object_property(expr_iri, Core.hasRightOperand(), right_iri)
    ]

    # Combine all triples
    operator_triples ++ left_triples ++ right_triples
  end

  # Builds a unary operator with a single operand
  @spec build_unary_operator(atom(), term(), RDF.IRI.t(), Context.t(), module()) :: list()
  defp build_unary_operator(op, operand_ast, expr_iri, context, type_class) do
    # Generate relative IRI for child expression
    operand_iri = fresh_iri(expr_iri, "operand")

    # Recursively build operand triples using build_expression_triples/3 directly.
    # We use build_expression_triples/3 instead of build/3 here because:
    # 1. The expr_iri for the operand is already known (operand_iri)
    # 2. Mode checking was already done by the parent build/3 call
    # 3. We don't need additional IRI counter management (child IRIs are relative)
    # 4. We need direct access to the triples list for concatenation
    operand_triples = build_expression_triples(operand_ast, operand_iri, context)

    # Build operator triples
    operator_triples = [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String),
      Helpers.object_property(expr_iri, Core.hasOperand(), operand_iri)
    ]

    # Combine all triples
    operator_triples ++ operand_triples
  end

  # Builds argument expression triples for function calls
  # We use build_expression_triples/3 instead of build/3 here because:
  # 1. The expr_iri for each argument is already known (generated below)
  # 2. Mode checking was already done by the parent build/3 call
  # 3. We don't need additional IRI counter management (child IRIs are relative)
  # 4. We need direct access to the triples list for concatenation
  @spec build_call_arguments(list(), RDF.IRI.t(), Context.t()) :: list()
  defp build_call_arguments(args, parent_iri, context) do
    Enum.with_index(args)
    |> Enum.flat_map(fn {arg_ast, index} ->
      arg_iri = fresh_iri(parent_iri, "arg-#{index}")

      arg_expr_triples = build_expression_triples(arg_ast, arg_iri, context)
      link_triple = Helpers.object_property(parent_iri, Core.hasArgument(), arg_iri)

      arg_expr_triples ++ [link_triple]
    end)
  end

  # Remote call: Module.function(args)
  @spec build_remote_call(term(), term(), list(), RDF.IRI.t(), Context.t()) :: list()
  defp build_remote_call(module, function, args, expr_iri, context) do
    # Extract module name from aliases AST
    module_name =
      case module do
        {:__aliases__, _, parts} -> Enum.join(parts, ".")
        {:@, _, [{:__, _, [:module]}]} -> :__MODULE__
        {:__MODULE__, [], []} -> :__MODULE__
        _ -> inspect(module)
      end

    function_name =
      case function do
        fun when is_atom(fun) -> fun
        _ -> inspect(function)
      end

    arity = length(args)

    # Build base triples for the RemoteCall
    base_triples = [
      Helpers.type_triple(expr_iri, Core.RemoteCall),
      Helpers.datatype_property(
        expr_iri,
        Core.name(),
        "#{module_name}.#{function_name}",
        RDF.XSD.String
      ),
      Helpers.datatype_property(
        expr_iri,
        Core.moduleName(),
        to_string(module_name),
        RDF.XSD.String
      ),
      Helpers.datatype_property(
        expr_iri,
        Core.functionName(),
        to_string(function_name),
        RDF.XSD.String
      ),
      Helpers.datatype_property(expr_iri, Core.arity(), arity, RDF.XSD.Integer)
    ]

    # Add refersToModule with placeholder IRI
    module_iri = RDF.iri("#{context.base_iri}module/#{module_name}")
    refers_to_module_triple = Helpers.object_property(expr_iri, Core.refersToModule(), module_iri)

    # Add refersToFunction with placeholder IRI
    function_iri = RDF.iri("#{module_iri.value}#function/#{function_name}/#{arity}")

    refers_to_function_triple =
      Helpers.object_property(expr_iri, Core.refersToFunction(), function_iri)

    # Build argument expressions recursively
    arg_triples = build_call_arguments(args, expr_iri, context)

    # Combine all triples
    base_triples ++ [refers_to_module_triple, refers_to_function_triple] ++ arg_triples
  end

  # Local call: function(args)
  @spec build_local_call(term(), list(), RDF.IRI.t(), Context.t()) :: list()
  defp build_local_call(function, args, expr_iri, context) do
    arity = length(args)

    # Build base triples for the LocalCall
    base_triples = [
      Helpers.type_triple(expr_iri, Core.LocalCall),
      Helpers.datatype_property(expr_iri, Core.name(), to_string(function), RDF.XSD.String),
      Helpers.datatype_property(
        expr_iri,
        Core.functionName(),
        to_string(function),
        RDF.XSD.String
      ),
      Helpers.datatype_property(expr_iri, Core.arity(), arity, RDF.XSD.Integer)
    ]

    # Add refersToFunction with placeholder IRI
    # For local calls, we don't know the module at this point, so use a generic placeholder
    function_iri = RDF.iri("#{context.base_iri}function/#{function}/#{arity}")

    refers_to_function_triple =
      Helpers.object_property(expr_iri, Core.refersToFunction(), function_iri)

    # Build argument expressions recursively
    arg_triples = build_call_arguments(args, expr_iri, context)

    # Combine all triples
    base_triples ++ [refers_to_function_triple] ++ arg_triples
  end

  # Anonymous function call: variable.(args)
  @spec build_anon_call(term(), list(), RDF.IRI.t(), Context.t()) :: list()
  defp build_anon_call(var_ast, args, expr_iri, context) do
    # Generate IRI for the function variable expression
    fun_var_iri = fresh_iri(expr_iri, "fun_var")

    # Build the function variable as a Variable expression
    fun_var_triples = build_variable(var_ast, fun_var_iri, context)

    # Build base triples for the AnonymousFunctionCall
    base_triples = [
      Helpers.type_triple(expr_iri, Core.AnonymousFunctionCall)
    ]

    # Link to the function variable expression
    has_function_triple =
      Helpers.object_property(expr_iri, Core.hasFunctionExpression(), fun_var_iri)

    # Build argument expressions recursively
    arg_triples = build_call_arguments(args, expr_iri, context)

    # Combine all triples
    base_triples ++ fun_var_triples ++ [has_function_triple] ++ arg_triples
  end

  # Variable: {name, meta, ctx}
  defp build_variable({name, _meta, _ctx}, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.Variable),
      Helpers.datatype_property(expr_iri, Core.name(), to_string(name), RDF.XSD.String)
    ]
  end

  # Wildcard pattern: _
  defp build_wildcard(expr_iri) do
    [Helpers.type_triple(expr_iri, Core.WildcardPattern)]
  end

  # Module reference: MyApp, MyApp.Users, etc.
  @spec build_module_reference(list(), RDF.IRI.t(), Context.t()) :: list()
  defp build_module_reference(parts, expr_iri, context) do
    # Extract module name from alias parts
    module_name = Enum.join(parts, ".")

    # Build base triples for the ModuleReference
    base_triples = [
      Helpers.type_triple(expr_iri, Core.ModuleReference),
      Helpers.datatype_property(expr_iri, Core.moduleName(), module_name, RDF.XSD.String)
    ]

    # Create refersToModule with module IRI
    module_iri = RDF.iri("#{context.base_iri}module/#{module_name}")
    refers_to_module_triple = Helpers.object_property(expr_iri, Core.refersToModule(), module_iri)

    # Combine all triples
    base_triples ++ [refers_to_module_triple]
  end

  # ===========================================================================
  # Literal Builders
  # ===========================================================================

  # Builds a typed literal (integer, float, string)
  defp build_literal(value, expr_iri, literal_type, value_property, xsd_type) do
    [
      Helpers.type_triple(expr_iri, literal_type),
      Helpers.datatype_property(expr_iri, value_property, value, xsd_type)
    ]
  end

  # Builds an atom literal (including :true, :false, :nil)
  # Uses specific types for booleans and nil: BooleanLiteral and NilLiteral
  defp build_atom_literal(atom_value, expr_iri) do
    type_class =
      case atom_value do
        true -> Core.BooleanLiteral
        false -> Core.BooleanLiteral
        nil -> Core.NilLiteral
        _ -> Core.AtomLiteral
      end

    [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(
        expr_iri,
        Core.atomValue(),
        atom_to_string(atom_value),
        RDF.XSD.String
      )
    ]
  end

  # Converts atom to string representation
  # Handles special atoms (true, false, nil) and custom atoms
  defp atom_to_string(true), do: "true"
  defp atom_to_string(false), do: "false"
  defp atom_to_string(nil), do: "nil"
  defp atom_to_string(atom) when is_atom(atom), do: ":" <> Atom.to_string(atom)

  # Check if a list represents a charlist (all elements are valid UTF-8 codepoints)
  # A charlist is a list of integers where each integer is a valid Unicode codepoint (0x0 to 0x10FFFF)
  defp charlist?(list) when is_list(list) do
    Enum.all?(list, fn
      x when is_integer(x) -> x >= 0 and x <= 0x10FFFF
      _ -> false
    end)
  end

  # Check if binary segments are all literal integers (no variables, no type specs)
  # This allows us to construct a binary value from literals like <<65, 66, 67>>
  defp binary_literal?(segments) when is_list(segments) do
    Enum.all?(segments, fn
      x when is_integer(x) -> x >= 0 and x <= 255
      _ -> false
    end)
  end

  # Construct a binary from a list of literal integer segments
  # Each integer should be a byte value (0-255)
  defp construct_binary_from_literals(segments) when is_list(segments) do
    # Use IO.iodata_to_binary for O(n) performance instead of O(n²) string concatenation
    IO.iodata_to_binary(segments)
  end

  # Check if a list is a cons pattern: [head | tail]
  # Accept both canonical list-wrapped and direct tuple shapes.
  defp cons_pattern?({:|, _, [_head, _tail]}), do: true
  defp cons_pattern?([{:|, _, [_head, _tail]}]), do: true
  defp cons_pattern?(_), do: false

  # Build child expressions from a collection, threading context through
  # Returns {flat_triples_list, final_context}
  # A mapper function can be provided to transform items before building
  defp build_child_expressions(items, parent_iri, context, mapper \\ fn item -> item end) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      child_iri = fresh_iri(parent_iri, "child/#{index}")

      [
        Helpers.object_property(parent_iri, Core.hasChild(), child_iri)
        | build_expression_triples(mapper.(item), child_iri, context)
      ]
    end)
  end

  # Build a list literal from a list of elements
  defp build_list_literal(list, expr_iri, context) do
    # Create the ListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.ListLiteral)

    # Build child expressions for each element
    child_triples = build_child_expressions(list, expr_iri, context)

    # Include type triple and all child triples
    [type_triple | child_triples]
  end

  # Build a cons pattern [head | tail]
  defp build_cons_list([{:|, _, [head, tail]}], expr_iri, context) do
    # Create the ListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.ListLiteral)

    # Build head expression
    head_iri = fresh_iri(expr_iri, "head")
    tail_iri = fresh_iri(expr_iri, "tail")

    head_triples = build_expression_triples(head, head_iri, context)
    tail_triples = build_expression_triples(tail, tail_iri, context)

    [
      type_triple,
      Helpers.object_property(expr_iri, Core.hasChild(), head_iri),
      Helpers.object_property(expr_iri, Core.hasChild(), tail_iri)
      | head_triples ++ tail_triples
    ]
  end

  # Build a keyword list from a list of {atom, value} tuples
  defp build_keyword_list(pairs, expr_iri, context) do
    # Create the KeywordListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.KeywordListLiteral)

    entry_triples = build_key_value_entries(pairs, expr_iri, context)

    [type_triple | entry_triples]
  end

  # Build a tuple literal from a list of elements
  defp build_tuple_literal(elements, expr_iri, context) do
    # Create the TupleLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.TupleLiteral)

    # Build child expressions for each element
    child_triples = build_child_expressions(elements, expr_iri, context)

    # Include type triple and all child triples
    [type_triple | child_triples]
  end

  # Build a struct literal from module AST and map AST
  defp build_struct_literal(module_ast, map_ast, expr_iri, context) do
    # Extract module name from {:__aliases__, _, parts}
    module_name =
      case module_ast do
        {:__aliases__, _meta, parts} -> Enum.join(parts, ".")
        _ -> inspect(module_ast)
      end

    # Create the StructLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.StructLiteral)

    # Create refersToModule property
    # refersToModule expects an IRI, so we create a module IRI
    module_iri_string = "#{context.base_iri}module/#{module_name}"
    module_iri = RDF.IRI.new(module_iri_string)
    refers_to_triple = {expr_iri, Core.refersToModule(), module_iri}

    # Extract map entries from the map part of the struct
    # The map_ast is {:%{}, meta, pairs}
    map_triples =
      case map_ast do
        {:%{}, _meta, pairs} ->
          build_map_entries(pairs, expr_iri, context)

        _ ->
          []
      end

    [type_triple, refers_to_triple | map_triples]
  end

  # Build a map literal from a list of key-value pairs
  defp build_map_literal(pairs, expr_iri, context) do
    # Create the MapLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.MapLiteral)

    # Build map entries
    entry_triples = build_map_entries(pairs, expr_iri, context)

    [type_triple | entry_triples]
  end

  # Build map entries from a list of key-value pairs
  # Pairs can be:
  # - Keyword tuples: {:a, 1} (for atom keys using a: 1 syntax)
  # - 2-tuples: {"a", 1} (for other keys using "a" => 1 syntax)
  # - 2-element lists: [[key_ast, value_ast], ...] (for complex keys like pin patterns)
  defp build_map_entries(pairs, _expr_iri, _context) when pairs == [], do: []

  defp build_map_entries(pairs, expr_iri, context) do
    pairs
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:|, _metadata, [source, updates]}, index} when is_list(updates) ->
        update_iri = fresh_iri(expr_iri, "update/#{index}")

        [
          Helpers.type_triple(update_iri, Core.Expression),
          Helpers.object_property(expr_iri, Core.hasChild(), update_iri)
          | expression_link(update_iri, "source", source, Core.hasChild(), context) ++
              build_key_value_entries(updates, update_iri, context)
        ]

      {pair, index} ->
        case key_value_pair(pair) do
          {:ok, key, value} -> build_key_value_entry(expr_iri, index, key, value, context)
          :error -> expression_link(expr_iri, "child/#{index}", pair, Core.hasChild(), context)
        end
    end)
  end

  defp build_key_value_entries(pairs, expr_iri, context) do
    pairs
    |> Enum.with_index()
    |> Enum.flat_map(fn {pair, index} ->
      case key_value_pair(pair) do
        {:ok, key, value} -> build_key_value_entry(expr_iri, index, key, value, context)
        :error -> expression_link(expr_iri, "entry/#{index}", pair, Core.hasChild(), context)
      end
    end)
  end

  defp build_key_value_entry(parent_iri, index, key, value, context) do
    entry_iri = fresh_iri(parent_iri, "entry/#{index}")

    [
      Helpers.type_triple(entry_iri, Core.Expression),
      Helpers.object_property(parent_iri, Core.hasChild(), entry_iri)
      | expression_link(entry_iri, "key", key, Core.hasChild(), context) ++
          expression_link(entry_iri, "value", value, Core.hasChild(), context)
    ]
  end

  defp key_value_pair({key, value}), do: {:ok, key, value}
  defp key_value_pair([key, value]), do: {:ok, key, value}
  defp key_value_pair(_pair), do: :error

  # Generic expression for unknown AST nodes
  defp build_generic_expression(expr_iri) do
    [Helpers.type_triple(expr_iri, Core.Expression)]
  end

  # ===========================================================================
  # Sigil Literal Builders
  # ===========================================================================

  @doc false
  defp build_sigil_literal(sigil_atom, content_ast, modifiers_ast, expr_iri, _context) do
    # Extract sigil character from atom name (e.g., :sigil_w -> "w")
    sigil_char = extract_sigil_char(sigil_atom)

    # Extract content from binary construction
    sigil_content = extract_sigil_content(content_ast)

    # Convert modifiers from charlist to string
    sigil_modifiers = extract_sigil_modifiers(modifiers_ast)

    # Build the RDF triples
    type_triple = Helpers.type_triple(expr_iri, Core.SigilLiteral)
    char_triple = {expr_iri, Core.sigilChar(), RDF.XSD.String.new(sigil_char)}
    content_triple = {expr_iri, Core.sigilContent(), RDF.XSD.String.new(sigil_content)}

    # Only add modifiers triple if non-empty
    modifiers_triples =
      if sigil_modifiers != "" do
        [{expr_iri, Core.sigilModifiers(), RDF.XSD.String.new(sigil_modifiers)}]
      else
        []
      end

    [type_triple, char_triple, content_triple | modifiers_triples]
  end

  @doc false
  defp extract_sigil_char(sigil_atom) do
    sigil_name = Atom.to_string(sigil_atom)
    # Remove "sigil_" prefix to get the character
    String.replace_prefix(sigil_name, "sigil_", "")
  end

  @doc false
  defp extract_sigil_content({:<<>>, _meta, [content]}) when is_binary(content) do
    content
  end

  # Fallback for unexpected content format
  defp extract_sigil_content(_other) do
    ""
  end

  @doc false
  defp extract_sigil_modifiers([]), do: ""

  defp extract_sigil_modifiers(modifiers) when is_list(modifiers) do
    # Convert charlist to string
    List.to_string(modifiers)
  end

  # Fallback for unexpected modifier format
  defp extract_sigil_modifiers(_other), do: ""

  @doc false
  defp is_sigil_atom?(atom) when is_atom(atom) do
    atom_name = Atom.to_string(atom)
    String.starts_with?(atom_name, "sigil_")
  end

  # ===========================================================================
  # Range Literal Builders
  # ===========================================================================

  @doc false
  defp build_range_literal(first, last, expr_iri, context) do
    first_iri = fresh_iri(expr_iri, "start")
    last_iri = fresh_iri(expr_iri, "end")
    first_triples = build_expression_triples(first, first_iri, context)
    last_triples = build_expression_triples(last, last_iri, context)

    # Create the RangeLiteral type and property triples
    type_triple = Helpers.type_triple(expr_iri, Core.RangeLiteral)
    start_triple = {expr_iri, Core.rangeStart(), first_iri}
    end_triple = {expr_iri, Core.rangeEnd(), last_iri}

    [type_triple, start_triple, end_triple | first_triples ++ last_triples]
  end

  defp build_range_literal(first, last, step, expr_iri, context) do
    first_iri = fresh_iri(expr_iri, "start")
    last_iri = fresh_iri(expr_iri, "end")
    step_iri = fresh_iri(expr_iri, "step")
    first_triples = build_expression_triples(first, first_iri, context)
    last_triples = build_expression_triples(last, last_iri, context)
    step_triples = build_expression_triples(step, step_iri, context)

    # Create the RangeLiteral type and property triples
    type_triple = Helpers.type_triple(expr_iri, Core.RangeLiteral)
    start_triple = {expr_iri, Core.rangeStart(), first_iri}
    end_triple = {expr_iri, Core.rangeEnd(), last_iri}
    step_triple = {expr_iri, Core.rangeStep(), step_iri}

    [
      type_triple,
      start_triple,
      end_triple,
      step_triple | first_triples ++ last_triples ++ step_triples
    ]
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  @doc """
  Generates an expression IRI with deterministic counter-based suffix.

  ## Parameters

  - `base_iri` - The base IRI string (e.g., "https://example.org/code#")
  - `context` - The builder context (for counter access)
  - `opts` - Optional keywords:
    - `:suffix` - Custom suffix (overrides counter generation)
    - `:counter` - Specific counter value (advanced use)

  ## Returns

  `{iri, updated_context}` - The expression IRI and context with incremented counter

  ## Examples

      # Using context counter (recommended)
      {iri, context} = expression_iri("https://example.org/code#", context)
      # => {~I<https://example.org/code#expr/0>, %Context{metadata: %{expression_counter: 1}}}

      # With custom suffix
      {iri, context} = expression_iri("https://example.org/code#", context, suffix: "my_expr")
      # => {~I<https://example.org/code#expr/my_expr>, %Context{}}

  """
  @spec expression_iri(String.t(), Context.t(), keyword()) :: {RDF.IRI.t(), Context.t()}
  def expression_iri(base_iri, context, opts \\ []) do
    {suffix, updated_context} =
      cond do
        # Explicit suffix provided (doesn't consume counter)
        custom_suffix = Keyword.get(opts, :suffix) ->
          {custom_suffix, context}

        # Explicit counter provided (advanced use)
        counter = Keyword.get(opts, :counter) ->
          {"expr_#{counter}", context}

        # Use context counter for deterministic IRIs
        true ->
          {counter, new_context} = Context.next_expression_counter(context)
          {"expr_#{counter}", new_context}
      end

    iri_string = "#{base_iri}expr/#{suffix}"
    iri = RDF.IRI.new(iri_string)

    {iri, updated_context}
  end

  @doc """
  Generates a relative IRI for child expressions.

  Child expressions (like left/right operands) get IRIs relative to their
  parent expression for clear hierarchy in the RDF graph.

  ## Parameters

  - `parent_iri` - The parent expression's IRI
  - `child_name` - The child relationship name (e.g., "left", "right", "condition")

  ## Returns

  A new IRI that is relative to the parent

  ## Examples

      parent = ~I<https://example.org/code#expr/0>
      fresh_iri(parent, "left")
      # => ~I<https://example.org/code#expr/0/left>

      fresh_iri(parent, "right")
      # => ~I<https://example.org/code#expr/0/right>

  """
  @spec fresh_iri(RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def fresh_iri(parent_iri, child_name) when is_binary(child_name) do
    parent_string = RDF.IRI.to_string(parent_iri)
    iri_string = "#{parent_string}/#{child_name}"
    RDF.IRI.new(iri_string)
  end

  @doc """
  Gets or creates an IRI from a cache, supporting expression deduplication.

  This pattern allows sharing the same IRI for identical sub-expressions
  that appear multiple times in a graph, reducing redundancy.

  ## Parameters

  - `cache` - A map cache (can be `nil` to skip caching)
  - `key` - Cache key (typically AST hash or structure signature)
  - `generator` - A zero-arity function that generates a new IRI

  ## Returns

  `{iri, updated_cache}` - The IRI (cached or new) and updated cache map

  ## Examples

      # First call - creates new IRI
      cache = %{}
      {iri1, cache1} = get_or_create_iri(cache, :some_key, fn -> ~I<https://example.org/expr/0> end)

      # Second call with same key - reuses cached IRI
      {iri2, cache2} = get_or_create_iri(cache1, :some_key, fn -> ~I<https://example.org/expr/1> end)
      iri1 == iri2  # => true

      # Different key - creates new IRI
      {iri3, cache3} = get_or_create_iri(cache2, :other_key, fn -> ~I<https://example.org/expr/2> end)
      iri1 == iri3  # => false

  """
  @spec get_or_create_iri(map() | nil, term(), function()) :: {RDF.IRI.t(), map()}
  def get_or_create_iri(nil, _key, generator), do: {generator.(), %{}}

  def get_or_create_iri(cache, key, generator) when is_map(cache) do
    case Map.get(cache, key) do
      nil ->
        iri = generator.()
        {iri, Map.put(cache, key, iri)}

      cached_iri ->
        {cached_iri, cache}
    end
  end

  # ===========================================================================
  # Capture Operator Helpers
  # ===========================================================================

  @doc false
  # Build capture operator for argument index (&1, &2, etc.)
  # Uses dedicated captureIndex property from the ontology
  defp build_capture_index(index, expr_iri) do
    [
      {expr_iri, RDF.type(), Core.CaptureOperator},
      {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
      {expr_iri, Core.captureIndex(), RDF.Literal.new(index)}
    ]
  end

  # Build capture operator for function reference (&Mod.fun/arity)
  # Uses FunctionReference type with moduleName, functionName, arity, and refersToFunction
  defp build_capture_function_ref(function_ref, arity, expr_iri, context) do
    # Extract module and function name from function_ref AST
    {module, function} = extract_function_ref_parts(function_ref)

    # Build base triples for the FunctionReference
    base_triples = [
      {expr_iri, RDF.type(), Core.FunctionReference},
      {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
      {expr_iri, Core.moduleName(), RDF.Literal.new(module)},
      {expr_iri, Core.functionName(), RDF.Literal.new(function)}
    ]

    # Add arity if specified
    triples_with_arity =
      if arity do
        base_triples ++ [{expr_iri, Core.arity(), RDF.Literal.new(arity)}]
      else
        base_triples
      end

    # Add refersToFunction with function IRI if we have arity
    # Function IRI requires module, function name, and arity
    if arity do
      function_iri = IRI.for_function(context.base_iri, module, function, arity)
      refers_to_function_triple = {expr_iri, Core.refersToFunction(), function_iri}
      triples_with_arity ++ [refers_to_function_triple]
    else
      triples_with_arity
    end
  end

  @doc false
  # Extract module and function name from a function reference AST
  # Handles: {{:., _, [module, function]}, _, args}
  defp extract_function_ref_parts({{:., _, [module_ast, function_ast]}, _meta, _args}) do
    module = extract_module_name(module_ast)
    function = extract_function_name(function_ast)
    {module, function}
  end

  defp extract_function_ref_parts({:., _, [module_ast, function_ast]}) do
    module = extract_module_name(module_ast)
    function = extract_function_name(function_ast)
    {module, function}
  end

  # Fallback for other patterns
  defp extract_function_ref_parts(other), do: {inspect(other), "unknown"}

  @doc false
  # Extract module name from AST
  defp extract_module_name({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  defp extract_module_name({:@, _, [{:__MODULE__, _, []}]}), do: "__MODULE__"
  defp extract_module_name({:__MODULE__, [], []}), do: "__MODULE__"
  defp extract_module_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp extract_module_name(other), do: inspect(other)

  @doc false
  # Extract function name from AST
  defp extract_function_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp extract_function_name(other), do: inspect(other)

  # ===========================================================================
  # Pattern Detection and Dispatch
  # ===========================================================================

  @doc """
  Detects the type of pattern from an Elixir AST node.

  ## Parameters

  - `ast` - The Elixir AST node to analyze

  ## Returns

  An atom representing the pattern type:
  - `:literal_pattern` - Literal values (integers, floats, strings, atoms)
  - `:variable_pattern` - Variable binding patterns
  - `:wildcard_pattern` - Underscore wildcard patterns
  - `:pin_pattern` - Pin operator patterns (^var)
  - `:tuple_pattern` - Tuple destructuring patterns
  - `:list_pattern` - List destructuring patterns
  - `:map_pattern` - Map pattern matching
  - `:struct_pattern` - Struct pattern matching
  - `:binary_pattern` - Binary/bitstring patterns
  - `:as_pattern` - Pattern aliasing (pattern = var)
  - `:unknown` - Unrecognized pattern

  ## Security Limits

  Pattern extraction is subject to the following limits to prevent
  denial-of-service attacks and excessive resource consumption:

  - `@max_pattern_depth` - Maximum nesting level (default: 100)
  - `@max_pattern_size` - Maximum elements in collection patterns (default: 1000)
  - `@module_name_regex` - Valid module name pattern for struct patterns

  These limits are applied during pattern building. Patterns exceeding
  these limits will return an empty list of triples, effectively skipping
  the problematic pattern while allowing extraction to continue.

  ## Examples

      iex> ExpressionBuilder.detect_pattern_type({:_})
      :wildcard_pattern

      iex> ExpressionBuilder.detect_pattern_type({:x, [], Elixir})
      :variable_pattern

      iex> ExpressionBuilder.detect_pattern_type(42)
      :literal_pattern
  """

  # ===========================================================================
  # Security Limits
  # ===========================================================================

  @max_pattern_depth 100
  @max_pattern_size 1000

  # ===========================================================================
  # Pattern Type Detection
  # ===========================================================================

  # Note: Removed inline directive to allow for easier updates
  # @compile {:inline, detect_pattern_type: 1}

  @spec detect_pattern_type(Macro.t()) :: atom()
  def detect_pattern_type({:_}), do: :wildcard_pattern
  # Note: Wildcard with metadata must come BEFORE variable pattern
  # because variable pattern also matches {name, meta, ctx} format
  def detect_pattern_type({:_, _, ctx}) when is_atom(ctx), do: :wildcard_pattern
  def detect_pattern_type({:^, _, [{_var, _, _}]}), do: :pin_pattern
  def detect_pattern_type({:=, _, [_, _]}), do: :as_pattern
  def detect_pattern_type({:{}, _, _}), do: :tuple_pattern
  def detect_pattern_type({:%, _, [{:{}, _, _}, {:%{}, _, _}]}), do: :struct_pattern
  def detect_pattern_type({:%, _, [{:__aliases__, _, _}, {:%{}, _, _}]}), do: :struct_pattern
  def detect_pattern_type({:%, _, [{:__MODULE__, [], []}, {:%{}, _, _}]}), do: :struct_pattern
  def detect_pattern_type({:%{}, _, _}), do: :map_pattern
  def detect_pattern_type({:<<>>, _, _}), do: :binary_pattern
  def detect_pattern_type({:|, _, [_head, _tail]}), do: :list_pattern
  def detect_pattern_type(list) when is_list(list), do: :list_pattern
  # Preserve the historical quoted-atom representation used by direct builder
  # callers. Parser-produced variables carry source metadata and fall through
  # to the variable clause below.
  def detect_pattern_type({name, [], nil}) when is_atom(name), do: :literal_pattern
  # Variable pattern must come after all other tuple-based patterns
  # because {name, _, ctx} also matches {:{}, [], []}
  # Parser-produced variables commonly use nil as their context; atom literal
  # patterns are represented by plain atoms rather than AST triples.
  def detect_pattern_type({name, _, _ctx}) when is_atom(name) and name != :{} and name != :_,
    do: :variable_pattern

  # 2-tuple is a special case: {left, right} without the {:{}, _, _} wrapper
  # Must come after variable pattern to avoid conflicts
  # The guard checks that left is not an n-tuple's {:{}, _, _} marker
  def detect_pattern_type({left, _right})
      when not (is_tuple(left) and tuple_size(left) == 3 and elem(left, 0) == :{}),
      do: :tuple_pattern

  def detect_pattern_type(value) when is_integer(value), do: :literal_pattern
  def detect_pattern_type(value) when is_float(value), do: :literal_pattern
  def detect_pattern_type(value) when is_binary(value), do: :literal_pattern
  def detect_pattern_type(value) when is_atom(value), do: :literal_pattern
  def detect_pattern_type(nil), do: :literal_pattern
  def detect_pattern_type(_), do: :unknown

  @doc """
  Builds RDF triples for a pattern expression.

  Uses `detect_pattern_type/1` to identify the pattern type and dispatches
  to the appropriate builder function.

  ## Parameters

  - `ast` - The Elixir AST pattern node
  - `expr_iri` - The IRI for this pattern expression
  - `context` - The builder context

  ## Returns

  A list of RDF triples representing the pattern.

  ## Examples

      iex> ast = {:x, [], Elixir}
      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/test#", config: %{include_expressions: true}, file_path: "lib/my_app/users.ex") |> ElixirOntologies.Builders.Context.with_expression_counter()
      iex> {:ok, {iri, _triples, ctx}} = ExpressionBuilder.build(ast, context, [])
      iex> pattern_triples = ExpressionBuilder.build_pattern(ast, iri, ctx)
      iex> Enum.any?(pattern_triples, fn {_s, p, o} -> p == RDF.type() and o == Core.VariablePattern end)
      true
  """
  @spec build_pattern(Macro.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  @spec build_pattern(Macro.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) :: [RDF.Triple.t()]
  def build_pattern(ast, expr_iri, context, depth \\ 0) do
    do_build_pattern(ast, expr_iri, context, depth) ++
      source_location_triples(ast, expr_iri, context)
  end

  defp do_build_pattern(ast, expr_iri, context, depth) do
    case detect_pattern_type(ast) do
      :literal_pattern -> build_literal_pattern(ast, expr_iri, context)
      :variable_pattern -> build_variable_pattern(ast, expr_iri, context)
      :wildcard_pattern -> build_wildcard_pattern(ast, expr_iri, context)
      :pin_pattern -> build_pin_pattern(ast, expr_iri, context)
      :tuple_pattern -> build_tuple_pattern(ast, expr_iri, context, depth)
      :list_pattern -> build_list_pattern(ast, expr_iri, context, depth)
      :map_pattern -> build_map_pattern(ast, expr_iri, context, depth)
      :struct_pattern -> build_struct_pattern(ast, expr_iri, context, depth)
      :binary_pattern -> build_binary_pattern(ast, expr_iri, context, depth)
      :as_pattern -> build_as_pattern(ast, expr_iri, context, depth)
      :unknown -> build_generic_expression(expr_iri)
    end
  end

  # Placeholder builder functions for individual pattern types
  # Full implementations will be added in later sections (24.2-24.6)

  @doc false
  defp build_literal_pattern(ast, expr_iri, _context) do
    {value_property, xsd_type, value} = literal_value_info(ast)

    [
      Helpers.type_triple(expr_iri, Core.LiteralPattern),
      Helpers.datatype_property(expr_iri, value_property, value, xsd_type)
    ]
  end

  defp literal_value_info({atom, _meta, nil}) when is_atom(atom),
    do: {Core.atomValue(), RDF.XSD.String, atom_to_string(atom)}

  defp literal_value_info(int) when is_integer(int),
    do: {Core.integerValue(), RDF.XSD.Integer, int}

  defp literal_value_info(float) when is_float(float),
    do: {Core.floatValue(), RDF.XSD.Double, float}

  defp literal_value_info(str) when is_binary(str), do: {Core.stringValue(), RDF.XSD.String, str}

  defp literal_value_info(atom) when is_atom(atom),
    do: {Core.atomValue(), RDF.XSD.String, atom_to_string(atom)}

  defp build_variable_pattern({name, _meta, _ctx}, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.VariablePattern),
      Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)
    ]
  end

  defp build_wildcard_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.WildcardPattern)]
  end

  defp build_pin_pattern(ast, expr_iri, _context) do
    {:^, _, [{var, _, _}]} = ast

    [
      Helpers.type_triple(expr_iri, Core.PinPattern),
      Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(var), RDF.XSD.String)
    ]
  end

  defp build_tuple_pattern(ast, expr_iri, context, depth) do
    # Extract elements from tuple AST
    elements = extract_tuple_elements(ast)

    # Check size limit to prevent memory exhaustion
    if length(elements) > @max_pattern_size do
      # Return only type triple for oversized patterns
      [Helpers.type_triple(expr_iri, Core.TuplePattern)]
    else
      # Create the TuplePattern type triple
      type_triple = Helpers.type_triple(expr_iri, Core.TuplePattern)

      # Build child patterns for each element with depth tracking
      {child_triples, _final_context} = build_child_patterns(elements, context, depth)

      # Include type triple and all child pattern triples
      [type_triple | child_triples]
    end
  end

  defp build_list_pattern(ast, expr_iri, context, depth) do
    # Create the ListPattern type triple
    type_triple = Helpers.type_triple(expr_iri, Core.ListPattern)

    # Check for cons pattern vs flat list
    child_triples =
      cond do
        cons_pattern?(ast) ->
          build_cons_list_pattern(ast, context, depth)

        is_list(ast) ->
          if length(ast) > @max_pattern_size do
            []
          else
            {triples, _ctx} = build_child_patterns(ast, context, depth)
            triples
          end

        true ->
          []
      end

    # Include type triple and all child pattern triples
    [type_triple | child_triples]
  end

  # Helper to extract elements from tuple AST
  # Handles both {:{}, _, elements} (n-tuple) and {left, right} (2-tuple) forms
  defp extract_tuple_elements({:{}, _meta, elements}), do: elements
  defp extract_tuple_elements({left, right}), do: [left, right]

  # Helper to build child patterns from a collection
  # Similar to build_child_expressions but uses build_pattern/3
  # Returns {flat_triples_list, final_context}
  # Depth parameter tracks nesting level to prevent DoS attacks
  defp build_child_patterns(items, context, depth)

  defp build_child_patterns(_items, context, depth) when depth >= @max_pattern_depth do
    # Pattern too deep - return empty triples and unchanged context
    # This prevents stack overflow from maliciously deep nesting
    {[], context}
  end

  defp build_child_patterns(items, context, depth) do
    {triples_list, final_ctx} =
      Enum.map_reduce(items, context, fn item, ctx ->
        # Use build/3 to get IRI, then build_pattern/3 for pattern context
        case build(item, ctx, []) do
          {:ok, {child_iri, _expression_triples, new_ctx}} ->
            pattern_triples = build_pattern(item, child_iri, ctx, depth + 1)
            {pattern_triples, new_ctx}

          # Skip items that can't be built as expressions
          _ ->
            {[], ctx}
        end
      end)

    {List.flatten(triples_list), final_ctx}
  end

  # Helper to build cons pattern [head | tail]
  # Builds head and tail as separate child patterns
  defp build_cons_list_pattern({:|, _, [head, tail]}, context, depth) do
    # Build head pattern
    head_triples =
      case build(head, context, []) do
        {:ok, {head_iri, _head_expr_triples, context_after_head}} ->
          build_pattern(head, head_iri, context_after_head, depth)

        _ ->
          []
      end

    # Build tail pattern
    tail_triples =
      case build(tail, context, []) do
        {:ok, {tail_iri, _tail_expr_triples, _context_after_tail}} ->
          build_pattern(tail, tail_iri, context, depth)

        _ ->
          []
      end

    # Combine head and tail pattern triples
    head_triples ++ tail_triples
  end

  defp build_cons_list_pattern([{:|, _, [head, tail]}], context, depth) do
    build_cons_list_pattern({:|, [], [head, tail]}, context, depth)
  end

  defp build_map_pattern({:%{}, _meta, pairs}, expr_iri, context, depth) do
    # Create the MapPattern type triple
    type_triple = Helpers.type_triple(expr_iri, Core.MapPattern)

    # Check size limit to prevent memory exhaustion
    if length(pairs) > @max_pattern_size do
      # Return only type triple for oversized patterns
      [type_triple]
    else
      # Extract both complex keys and values from key-value pairs
      # Simple keys (atoms, strings) are literals and don't need pattern triples
      # Complex keys (pin patterns, etc.) need to be built as child patterns
      {complex_keys, value_patterns} = extract_map_pattern_pairs(pairs)

      # Build child patterns for complex keys and values with depth tracking
      all_patterns = complex_keys ++ value_patterns
      {child_triples, _final_context} = build_child_patterns(all_patterns, context, depth)

      # Include type triple and all child pattern triples
      [type_triple | child_triples]
    end
  end

  defp build_struct_pattern(
         {:%, _meta, [module_ast, {:%{}, _map_meta, pairs}]},
         expr_iri,
         context,
         depth
       ) do
    # Extract and validate module name from module AST
    module_name = extract_struct_module_name(module_ast)

    # Create the StructPattern type triple
    type_triple = Helpers.type_triple(expr_iri, Core.StructPattern)

    # Create refersToModule property with validated module name
    module_iri_string = "#{context.base_iri}module/#{module_name}"
    module_iri = RDF.IRI.new(module_iri_string)
    refers_to_triple = {expr_iri, Core.refersToModule(), module_iri}

    # Extract field value patterns from the map portion
    field_patterns = extract_map_pattern_values(pairs)

    # Build child patterns for each field value with depth tracking
    {child_triples, _final_context} = build_child_patterns(field_patterns, context, depth)

    # Include type triple, module reference, and all child pattern triples
    [type_triple, refers_to_triple | child_triples]
  end

  # Extract complex keys and value patterns from map pattern pairs
  # Returns {[complex_keys], [value_patterns]}
  # Pairs are keyword list format: [key1: value1_ast, key2: value2_ast, ...]
  # Or for string keys: [{"key1", value1_ast}, {"key2", value2_ast}]
  # Or for complex keys (like pin patterns): [[key_ast, value_ast], ...]
  defp extract_map_pattern_pairs(pairs) when is_list(pairs) do
    {keys_list, values_list} =
      Enum.reduce(pairs, {[], []}, fn pair, {keys_acc, values_acc} ->
        case pair do
          # 2-element list format for complex keys: [key_ast, value_ast]
          # where key_ast is a tuple (complex key like pin pattern)
          [key_ast, value_ast] when is_tuple(key_ast) and tuple_size(key_ast) == 3 ->
            # Include the complex key in the patterns list
            {[key_ast | keys_acc], [value_ast | values_acc]}

          # Tuple format for simple keys: {key, value_ast}
          # Simple keys (atoms, strings) are literals, not patterns
          {_key, value_ast} ->
            {keys_acc, [value_ast | values_acc]}

          # Handle non-tuple/non-list values (literals like integers, strings, etc.)
          value ->
            {keys_acc, [value | values_acc]}
        end
      end)

    # Reverse the accumulated lists to maintain original order
    {Enum.reverse(keys_list), Enum.reverse(values_list)}
  end

  # Extract value patterns from map pattern pairs
  # Pairs are keyword list format: [key1: value1_ast, key2: value2_ast, ...]
  # Or for string keys: [{"key1", value1_ast}, {"key2", value2_ast}]
  # Or for complex keys (like pin patterns): [[key_ast, value_ast], ...]
  defp extract_map_pattern_values(pairs) when is_list(pairs) do
    Enum.map(pairs, fn
      # 2-element list format for complex keys: [key_ast, value_ast]
      # where key_ast is a tuple like {:^, ..., [var]}
      # Must come before tuple pattern to avoid matching [_, _] as {_, _}
      entry when is_list(entry) and length(entry) == 2 ->
        [_key_ast, value_ast] = entry
        value_ast

      # Keyword list or string key tuple format: {key, value_ast}
      {_key, value_ast} ->
        value_ast

      # Handle non-tuple/non-list values (literals like integers, strings, etc.)
      value ->
        value
    end)
  end

  # Extract module name from struct pattern module AST
  # Applies validation to prevent IRI injection attacks
  defp extract_struct_module_name({:__aliases__, _meta, parts}) when is_list(parts) do
    module_name = Enum.join(parts, ".")
    validate_and_sanitize_module_name(module_name)
  end

  defp extract_struct_module_name({:__MODULE__, [], []}) do
    "__MODULE__"
  end

  defp extract_struct_module_name({:{}, _meta, parts}) when is_list(parts) do
    # Handle tuple form module reference
    module_name =
      Enum.map_join(parts, ".", fn
        part when is_atom(part) -> Atom.to_string(part)
        part -> inspect(part, limit: 50)
      end)

    validate_and_sanitize_module_name(module_name)
  end

  defp extract_struct_module_name(other) do
    # For unknown forms, use inspect but sanitize
    module_name = inspect(other, limit: 50)
    validate_and_sanitize_module_name(module_name)
  end

  # Validates and sanitizes module names to prevent IRI injection
  # Returns a safe module name string
  defp validate_and_sanitize_module_name(module_name) when is_binary(module_name) do
    # Check for path traversal attempts
    if String.contains?(module_name, ["..", "\\", "\0", "\n"]) do
      # Return a safe fallback
      "InvalidModule"
    else
      # Ensure length is reasonable
      if String.length(module_name) > 256 do
        String.slice(module_name, 0, 256) <> "..."
      else
        module_name
      end
    end
  end

  defp build_binary_pattern({:<<>>, _meta, segments}, expr_iri, context, depth) do
    # Create the BinaryPattern type triple
    type_triple = Helpers.type_triple(expr_iri, Core.BinaryPattern)

    # Check size limit to prevent memory exhaustion
    if length(segments) > @max_pattern_size do
      # Return only type triple for oversized patterns
      [type_triple]
    else
      # Extract segment patterns (variables or literals within the binary)
      segment_patterns = extract_binary_segment_patterns(segments)

      # Build child patterns for each segment with depth tracking
      {child_triples, _final_context} = build_child_patterns(segment_patterns, context, depth)

      # Include type triple and all segment pattern triples
      [type_triple | child_triples]
    end
  end

  # Extract patterns from binary segments
  # Segments can be simple variables or complex with :: specifiers
  defp extract_binary_segment_patterns(segments) when is_list(segments) do
    Enum.map(segments, fn
      # Segment with specifier: {:"::", _, [pattern, _specifier]}
      {:"::", _meta, [pattern, _specifier]} -> pattern
      # Simple segment without specifier
      pattern -> pattern
    end)
  end

  defp build_as_pattern({:=, _meta, [left, right]}, expr_iri, context, depth) do
    # Create the AsPattern type triple
    type_triple = Helpers.type_triple(expr_iri, Core.AsPattern)

    # Build the left pattern (destructure pattern) with depth tracking
    {:ok, {left_iri, _left_expr_triples, context_after_left}} = build(left, context, [])
    left_pattern_triples = build_pattern(left, left_iri, context_after_left, depth)

    # Link to the inner pattern via hasPattern
    has_pattern_triple = {expr_iri, Core.hasPattern(), left_iri}

    # Build the right variable (binding variable) with depth tracking
    {:ok, {_right_iri, _right_expr_triples, _context_after_right}} =
      build(right, context_after_left, [])

    right_pattern_triples = build_pattern(right, left_iri, context_after_left, depth)

    # Combine all triples: type, hasPattern link, left patterns, right patterns
    [type_triple, has_pattern_triple | left_pattern_triples] ++ right_pattern_triples
  end
end
