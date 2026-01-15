# Phase 27.3: Anonymous Function (Fn) Block Expression Extraction

**Feature Branch:** `feature/phase-27-3-fn-block-expression`
**Created:** 2026-01-15
**Based On:** Phase 27 Expressions Plan (Section 27.3)

---

## Problem Statement

The ExpressionBuilder currently can detect fn blocks (Phase 27.1) and extract do blocks (Phase 27.2), but cannot extract RDF triples for anonymous function blocks (`fn...end`). Fn blocks are fundamental to Elixir's functional programming paradigm - they appear as:

- Anonymous functions passed to higher-order functions (Enum.map, etc.)
- Callbacks and event handlers
- Closures capturing variables from outer scope
- Pattern-matching function clauses

Without fn block extraction, we cannot represent:
- Anonymous functions with their parameter patterns
- Multi-clause pattern matching in anonymous functions
- Function bodies with guards
- The structure of closures and their clauses

---

## Solution Overview

Implement RDF triple extraction for fn blocks (`{:fn, _, clauses}`):

1. **Add `build_fn_block/5`** - Extract fn blocks as `Core.FnBlock`
2. **Handle multi-clause functions** - Each clause gets its own IRI via `Core.hasClause`
3. **Extract parameter patterns** - Use existing `build_pattern/4` for pattern extraction
4. **Extract guards** - Use existing guard extraction mechanisms
5. **Extract clause bodies** - Use existing `build_expression_triples/3` for bodies

---

## Technical Details

### Ontology Usage

From `ontology/elixir-core.ttl`:
- **Type:** `Core.FnBlock` (already exists, line 428)
- **Clause linking:** `Core.hasClause` (already exists, line 652)
- **Parameter linking:** `Core.hasParameter` (check if exists)
- **Body linking:** `Core.hasBody` (check if exists)
- **Guard linking:** `Core.hasGuard` (check if exists)

### Elixir AST Fn Block Representation

**Single clause fn:**
```elixir
# Source:
fn x -> x + 1 end

# AST:
{:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
```

**Multi-clause fn:**
```elixir
# Source:
fn
  x -> x + 1
  y -> y * 2
end

# AST:
{:fn, [], [
  {:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]},
  {:->, [], [[{:y, [], nil}], {:*, [], [{:y, [], nil}, 2]}]}
]}
```

**Fn with guard:**
```elixir
# Source:
fn x when is_integer(x) -> x + 1 end

# AST:
{:fn, [], [{:->, [], [[{:x, [], nil}], [when: {:is_integer, [], [{:x, [], nil}]}], {:+, [], [{:x, [], nil}, 1]}]}]}
```

**Fn with multiple parameters:**
```elixir
# Source:
fn x, y -> x + y end

# AST:
{:fn, [], [{:->, [], [[{:x, [], nil}, {:y, [], nil}], {:+, [], [{:x, [], nil}, {:y, [], nil}]}]}]}
```

### IRI Generation Pattern

For a fn block at `https://example.org/code#expr/0`:
- Fn block IRI: `https://example.org/code#expr/0`
- Clause IRIs: `expr/0/clause/0`, `expr/0/clause/1`, etc.
- Parameter IRIs: `expr/0/clause/0/param/0`, etc.
- Body IRI: `expr/0/clause/0/body`

### Clause Structure

Each clause in the list has the structure:
```elixir
{:->, meta, [params, guards_and_body]}
```

Where:
- `params` is a list of parameter patterns (single param or multiple params)
- `guards_and_body` is either:
  - Just the body expression (no guard)
  - A list starting with `when:` keyword followed by guard expression and body

### Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add fn block builder and dispatch |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add fn block extraction tests |

---

## Implementation Plan

### Step 1: Add `build_fn_block/5` Helper

**Location:** `lib/elixir_ontologies/builders/expression_builder.ex`

**Signature:**
```elixir
@spec build_fn_block(list(), RDF.IRI.t(), Context.t(), non_neg_integer(), non_neg_integer()) :: [RDF.Triple.t()]
defp build_fn_block(clauses, fn_iri, context, depth \\ 0, max_depth \\ 100)
```

**Implementation:**
1. Check depth limit for nested fn blocks
2. Create type triple: `fn_iri a Core.FnBlock`
3. For each clause:
   - Generate clause IRI: `fresh_iri(fn_iri, "clause/#{index}")`
   - Create clause type triple
   - Extract parameter patterns using `build_pattern/4`
   - Extract guard if present
   - Extract body using `build_expression_triples/3`
   - Link clause to fn via `Core.hasClause`
4. Return all triples

### Step 2: Add `{:fn, _, _}` Dispatch

**Location:** In `build_expression_triples/3`

Add pattern match before the catch-all clause (after `{:__block__, _, _}`):
```elixir
# Fn blocks: {:fn, meta, clauses}
# Anonymous functions with fn...end syntax
# Must come before local call handler
def build_expression_triples({:fn, _meta, clauses}, expr_iri, context) do
  build_fn_block(clauses, expr_iri, context)
end
```

### Step 3: Add Unit Tests

**Tests to add:**
1. Test fn block extraction for single clause
2. Test fn block extraction for multiple clauses
3. Test fn block extraction with parameters
4. Test fn block extraction with guards
5. Test fn block extraction with multiple body expressions
6. Test fn block extraction preserves clause order
7. Test fn block extraction handles pattern parameters
8. Test fn block extraction handles empty parameter list
9. Test fn block extraction handles nested fn blocks

---

## Success Criteria

- [x] `build_fn_block/5` extracts fn blocks as `Core.FnBlock`
- [x] Clauses linked via `Core.hasClause`
- [x] Parameter patterns extracted using `build_pattern/4`
- [x] Guards extracted when present
- [x] Clause bodies extracted recursively
- [x] Clause order preserved via index-based IRIs
- [x] Multi-clause fns handled correctly
- [x] Empty parameter list handled
- [x] Nested fn blocks handled (with depth limit)
- [x] All unit tests passing

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
1. Added `build_fn_block/5` helper function (lines 361-389)
   - Three clauses: depth limit check, empty clause list check, and main implementation
   - Creates `Core.FnBlock` type triple
   - Generates clause IRIs using `fresh_iri(fn_iri, "clause/#{index}")` pattern

2. Added `build_fn_clause/5` helper function (lines 392-446)
   - Parses params list to extract actual parameter patterns
   - Extracts guard from `:when` pattern if present
   - Builds parameter pattern triples using `build_pattern/4`
   - Builds guard triples with `inGuardContext` property
   - Builds body expression triples recursively

3. Added `parse_fn_params/2` helper function (lines 449-475)
   - Extracts parameters and optional guard from parameter patterns
   - Handles `{:when, _, [param1, param2, ..., guard_ast]}` pattern
   - Returns `{parameters, guard_ast | nil}`

4. Added `{:fn, _, _}` dispatch to `build_expression_triples/3` (lines 744-749)
   - Placed **before** the local call handler to avoid being matched as `:fn` function call

5. Added 8 unit tests for fn block extraction (lines 4896-5148)
   - Single clause fn block
   - Multiple clauses fn block
   - Parameters extraction
   - Guards extraction
   - Multiple body expressions (do block)
   - Clause order preservation
   - Empty parameter list
   - Nested fn blocks

**Test Results:**
```
9 doctests, 358 tests, 0 failures
```
- Previous test count: 350 tests (9 doctests)
- New test count: 358 tests (9 doctests)
- Tests added: 8
- All expression builder tests passing

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run only fn block tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs --only fn_blocks
```

---

## Design Notes

1. **Placement before local call handler:** The `{:fn, _, _}` pattern must come before the local call handler (`{function, meta, args}`) because `{:fn, [], clauses}` also matches the pattern where `function = :fn`, `meta = []`, and `args = clauses`.

2. **Parameter list structure:** The fn clause AST has params wrapped in an extra list level: `{:->, meta, [[param_patterns], body]}`. We use `List.flatten(params)` to extract the actual parameter patterns.

3. **Guard syntax in fn blocks:** Guards in fn blocks use the `{:when, meta, [param1, param2, ..., guard_ast]}` pattern embedded in the parameter patterns list. This differs from function definition guards.

4. **Child linking:** Both parameters and bodies are linked via `Core.hasChild()` property, with IRIs using `param/{index}` and `body` suffixes respectively.

5. **Depth limiting:** The function accepts optional `depth` and `max_depth` parameters (defaulting to 0 and 100) to prevent infinite recursion in deeply nested fn blocks.

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-27-3-fn-block-expression
