# Phase 17.2.2: Case and With Expression Extraction - Summary

## Completed

Implemented extraction of case and with expressions from Elixir AST, creating a new extractor module with specialized structs for pattern matching constructs.

## Changes Made

### 1. New Module Created

Created `lib/elixir_ontologies/extractors/case_with.ex` with:

**CaseClause struct:**
```elixir
%CaseClause{
  index: non_neg_integer(),       # 0-based position in case
  pattern: Macro.t(),             # The pattern to match
  guard: Macro.t() | nil,         # Guard expression if present
  body: Macro.t(),                # The clause body
  has_guard: boolean(),           # Whether clause has a guard
  location: SourceLocation.t() | nil
}
```

**CaseExpression struct:**
```elixir
%CaseExpression{
  subject: Macro.t(),             # Expression being matched
  clauses: [CaseClause.t()],      # Pattern matching clauses
  location: SourceLocation.t() | nil,
  metadata: map()                 # clause_count, has_guards
}
```

**WithClause struct:**
```elixir
%WithClause{
  index: non_neg_integer(),       # 0-based position in with
  type: :match | :bare_match,     # <- vs =
  pattern: Macro.t(),             # The pattern to match
  expression: Macro.t(),          # The expression being matched
  location: SourceLocation.t() | nil
}
```

**WithExpression struct:**
```elixir
%WithExpression{
  clauses: [WithClause.t()],      # Match clauses
  body: Macro.t(),                # The do block body
  else_clauses: [CaseClause.t()], # Else clauses (reuses CaseClause)
  has_else: boolean(),            # Whether with has else block
  location: SourceLocation.t() | nil,
  metadata: map()                 # clause_count, else_clause_count, has_bare_match
}
```

### 2. Functions Implemented

- `case_expression?/1` - Predicate for case expressions
- `with_expression?/1` - Predicate for with expressions
- `extract_case/2` - Extract case expression
- `extract_case!/2` - Raising version
- `extract_with/2` - Extract with expression
- `extract_with!/2` - Raising version
- `extract_case_expressions/2` - Bulk extraction from AST
- `extract_with_expressions/2` - Bulk extraction from AST

### 3. Key Design Decisions

1. **Unified module** - Both case and with in same module due to shared clause structure
2. **Separate clause structs** - CaseClause for case, WithClause for with match clauses
3. **Guard extraction** - Case clauses can have guards, extracted separately
4. **Clause type tracking** - With clauses distinguish `<-` (:match) from `=` (:bare_match)
5. **Else clause reuse** - With else clauses use CaseClause struct

## Test Results

- 19 doctests pass
- 60 unit tests pass
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` shows only pre-existing refactoring suggestions

## Files Created/Modified

### New Files
1. `lib/elixir_ontologies/extractors/case_with.ex` - Case/with extractor module
2. `test/elixir_ontologies/extractors/case_with_test.exs` - 79 tests
3. `notes/features/phase-17-2-2-case-with-extraction.md` - Planning document
4. `notes/summaries/phase-17-2-2-case-with-extraction.md` - This summary

### Modified Files
1. `notes/planning/extractors/phase-17.md` - Marked task 17.2.2 as complete

## Test Coverage

| Category | Tests |
|----------|-------|
| `case_expression?/1` predicate | 6 tests |
| `with_expression?/1` predicate | 6 tests |
| `extract_case/2` | 10 tests |
| `extract_case!/2` | 2 tests |
| `extract_with/2` | 10 tests |
| `extract_with!/2` | 2 tests |
| `extract_case_expressions/2` | 7 tests |
| `extract_with_expressions/2` | 5 tests |
| Struct field tests | 8 tests |
| Integration tests | 5 tests |
| Doctests | 19 tests |
| **Total** | **79 tests** |

## Case Expression AST Pattern

```elixir
# case with clauses
{:case, meta, [subject, [do: clauses]]}

# Each clause
{:->, clause_meta, [[pattern], body]}

# Clause with guard
{:->, clause_meta, [[{:when, [], [pattern, guard]}], body]}
```

## With Expression AST Pattern

```elixir
# Basic with
{:with, meta, [clause1, clause2, ..., [do: body]]}

# With else
{:with, meta, [clause1, ..., [do: body, else: else_clauses]]}

# Match clause (<-)
{:<-, meta, [pattern, expression]}

# Bare match clause (=)
{:=, meta, [pattern, expression]}
```

## Key Features

1. **Subject extraction** - Case subject expression captured
2. **Pattern extraction** - Each clause pattern available
3. **Guard separation** - Guards extracted separately from patterns
4. **Clause indexing** - 0-based indices for ordering
5. **Clause type tracking** - Distinguishes match vs bare_match for with
6. **Else clause handling** - With else uses same structure as case clauses
7. **Nested extraction** - Finds expressions in clause bodies
8. **Metadata tracking** - clause_count, has_guards, has_bare_match

## Next Task

**Task 17.2.3: Receive Expression Extraction**
- Extract receive expressions with message patterns
- Extract `after` timeout clause
- Define `%ReceiveExpression{clauses: [...], after: ..., location: ...}`
- Track receive as potential blocking point
