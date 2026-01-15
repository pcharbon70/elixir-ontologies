# Phase 27.1: Block Detection and Structure

**Feature Branch:** `feature/phase-27-1-block-detection`
**Created:** 2026-01-15
**Based On:** Phase 27 Expressions Plan (Section 27.1)

---

## Problem Statement

The ExpressionBuilder currently handles operators, literals, and function calls, but lacks support for block expressions. Blocks are fundamental to Elixir code structure:

- **Do blocks**: Multi-line blocks after `do` keyword in function definitions and control flow
- **Fn blocks**: Anonymous functions with `fn...end`
- **Begin blocks**: Explicit `begin...end` expression sequences
- **__block__ nodes**: Internal AST representation for multi-expression blocks

Without block detection and structure analysis, we cannot extract:
- Function bodies with multiple expressions
- Anonymous function definitions
- Complex control flow structures
- Expression sequences with ordered statements

---

## Solution Overview

Implement block type detection and structure analysis in ExpressionBuilder:

1. **Block Type Detection** (`detect_block_type/1`): Analyze AST to determine block type
2. **Block Structure Analysis** (`analyze_block_structure/1`): Extract block metadata and content
3. **Unit Tests**: Verify detection works for all block types

This is a foundational step before implementing full block extraction (27.2-27.4).

---

## Technical Details

### Elixir AST Block Representation

**Do Block (multi-expression):**
```elixir
# Source:
def foo do
  x = 1
  x + 2
end

# AST:
{:__block__, _, [{:=, _, [{:x, [], nil}, 1]}, {:+, _, [{:x, [], nil}, 2]}]}
```

**Fn Block (anonymous function):**
```elixir
# Source:
fn x -> x + 1 end

# AST:
{:fn, _, [{:->, _, [[{:x, [], nil}], {:+, _, [{:x, [], nil}, 1]}]}]}
```

**Begin Block:**
```elixir
# Source:
begin
  :a
  :b
end

# AST:
{:__block__, _, [:a, :b]}  # Same representation as do block internally
```

**Single Expression (not a block):**
```elixir
# Source:
x + 1

# AST:
{:+, _, [{:x, [], nil}, 1]}  # No __block__ wrapper
```

### Block Type Detection Logic

| AST Pattern | Block Type | Description |
|-------------|------------|-------------|
| `{:fn, _, clauses}` | `:fn_block` | Anonymous function |
| `{:__block__, _, exprs}` | `:do_block` | Multi-expression block |
| Single expression | `:single_expr` | Not a block |

**Note:** `begin..end` blocks compile to `{:__block__, _, ...}` same as do blocks.
Differentiation requires source context (line/column metadata).

### Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add block detection helpers |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add block detection tests |

---

## Implementation Plan

### Step 1: Implement `detect_block_type/1`

**Location:** `lib/elixir_ontologies/builders/expression_builder.ex`

**Function:**
```elixir
@spec detect_block_type(Macro.t()) :: :do_block | :fn_block | :single_expr
defp detect_block_type(ast)
```

**Pattern Matching:**
- `{:fn, _, _}` → `:fn_block`
- `{:__block__, _, expressions}` → `:do_block`
- `_` → `:single_expr`

### Step 2: Implement `analyze_block_structure/1`

**Function:**
```elixir
@spec analyze_block_structure(Macro.t()) :: %{type: atom(), expressions: list(), metadata: map()}
defp analyze_block_structure(ast)
```

**Extract:**
- Block type (via `detect_block_type/1`)
- Expression list
- Metadata (line numbers from AST metadata)
- Empty block detection

### Step 3: Add Unit Tests

**Test file:** `test/elixir_ontologies/builders/expression_builder_test.exs`

**Tests to add:**
1. Test block type detection for do blocks
2. Test block type detection for fn blocks
3. Test block type detection for begin blocks
4. Test block type detection for single expressions
5. Test block structure analysis captures metadata
6. Test empty block detection

---

## Success Criteria

- [x] `detect_block_type/1` correctly identifies all block types
- [x] `analyze_block_structure/1` extracts block metadata
- [x] All unit tests passing
- [x] Code follows existing ExpressionBuilder patterns
- [x] @spec annotations added

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
1. Implemented `detect_block_type/1` - Public function that identifies block type:
   - `:fn_block` for anonymous functions `{:fn, _, _}`
   - `:do_block` for multi-expression blocks `{:__block__, _, _}`
   - `:single_expr` for single expressions (everything else)

2. Implemented `analyze_block_structure/1` - Public function that extracts:
   - Block type (via `detect_block_type/1`)
   - Expression list
   - Empty block detection
   - AST metadata (line numbers, column info)

3. Added 13 unit tests:
   - 6 tests for `detect_block_type/1`
   - 7 tests for `analyze_block_structure/1`

**Test Results:**
```
9 doctests, 344 tests, 0 failures (was 331 tests, added 13)
```

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run only block detection tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs:4579
```

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-27-1-block-detection
