# Phase 17.1.1: Local Function Call Extraction - Summary

## Completed

Implemented extraction of local function calls from Elixir AST as the first step of Phase 17 (Call Graph & Control Flow).

## Changes Made

### 1. Call Extractor Module (NEW)
Created `lib/elixir_ontologies/extractors/call.ex` with:

**FunctionCall Struct:**
```elixir
%FunctionCall{
  type: :local | :remote | :dynamic,
  name: atom(),
  arity: non_neg_integer(),
  arguments: [Macro.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

**Key Functions:**
- `local_call?/1` - Predicate to check if AST is a local call
- `extract/2` - Extract single local call with options
- `extract!/2` - Raising version of extract
- `extract_local_calls/2` - Bulk extraction from AST with recursion

### 2. Call vs Variable Distinction
The module correctly distinguishes between:
- **Function calls**: `{:foo, meta, []}` - third element is a list
- **Variable references**: `{:x, meta, nil}` - third element is nil or atom context

### 3. Special Form Exclusion
Uses `Helpers.special_forms()` to exclude non-call forms:
- Definition forms: `def`, `defp`, `defmacro`, etc.
- Control flow: `if`, `unless`, `case`, `cond`, etc.
- Directives: `import`, `require`, `use`, `alias`
- Operators: `+`, `-`, `|>`, `=`, etc.

### 4. AST Walking
Recursive extraction handles:
- Lists of statements
- `__block__` structures
- Nested calls in function arguments
- Calls inside control flow expressions
- Depth limiting to prevent stack overflow

## Test Results

- 15 doctests pass
- 48 unit tests pass
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` shows only pre-existing refactoring suggestions

## Files Created/Modified

### New Files
1. `lib/elixir_ontologies/extractors/call.ex` - Call extractor module
2. `test/elixir_ontologies/extractors/call_test.exs` - 63 tests (48 unit + 15 doctests)
3. `notes/features/phase-17-1-1-local-call-extraction.md` - Planning document
4. `notes/summaries/phase-17-1-1-local-call-extraction.md` - This summary

### Modified Files
1. `notes/planning/extractors/phase-17.md` - Marked task 17.1.1 as complete

## Test Coverage

| Category | Tests |
|----------|-------|
| `local_call?/1` predicate | 20 tests |
| `extract/2` single extraction | 8 tests |
| `extract!/2` raising version | 2 tests |
| `extract_local_calls/2` bulk | 15 tests |
| Integration tests | 3 tests |
| Doctests | 15 tests |
| **Total** | **63 tests** |

## Architecture Notes

The Call extractor follows the established patterns:
- Composable, on-demand extraction
- Not automatically invoked by Pipeline
- Uses shared Helpers for location extraction
- Consistent struct and typespec patterns
- Comprehensive doctests and examples

## Next Task

**Task 17.1.2: Remote Function Call Extraction**
- Implement `extract_remote_calls/1` for `Module.function(args)` pattern
- Handle aliased module calls
- Handle imported function calls
- Track module resolution
