# Phase 29.2 and 29.4: Not Implemented as Separate Phases

**Date:** 2026-01-16
**Related Phase:** 29 - Function Call and Reference Expression Extraction

---

## Overview

Phase 29.2 (Local Call Expression Extraction) and Phase 29.4 (Capture Operator Extraction) were **not implemented as separate phases**. Instead, their functionality was merged into other phases:

- **Phase 29.2 (Local Call)** functionality was merged into **Phase 29.1 (Remote Call)**
- **Phase 29.4 (Capture Operator)** functionality was merged into **Phase 29.6 (Function Reference)**

---

## Why These Were Not Separate Phases

### Phase 29.2: Local Call Expression Extraction

**Reason for Merging:**
Local call extraction is inherently similar to remote call extraction. Both involve:
- Building a call expression with function name, arity, and arguments
- Creating `refersToFunction` references
- Building argument expressions recursively

The only differences are:
- Remote calls have `moduleName` and `refersToModule` properties
- Local calls omit these (module is unknown at extraction time)

**Implementation Location:**
The `build_local_call/4` function was implemented alongside `build_remote_call/5` in Phase 29.1 at `lib/elixir_ontologies/builders/expression_builder.ex:1022-1052`.

**Test Coverage:**
Local call extraction is tested in `test/elixir_ontologies/builders/expression_builder_test.exs` starting around line 1496 with 10 dedicated tests.

### Phase 29.4: Capture Operator Extraction

**Reason for Merging:**
The capture operator (`&`) has two distinct use cases that are better handled separately:

1. **Argument Index Captures** (`&1`, `&2`, etc.)
   - Creates `CaptureOperator` type
   - Uses `captureIndex` property
   - Implemented in `build_capture_index/2`

2. **Function Reference Captures** (`&Module.fun/arity`)
   - Creates `FunctionReference` type
   - Uses `moduleName`, `functionName`, `arity` properties
   - Implemented in `build_capture_function_ref/4`

The argument index capture functionality is simple and self-contained. The function reference capture is more complex and fits naturally with Phase 29.6 (Named Function Reference Extraction).

**Implementation Locations:**
- `build_capture_index/2` - Implemented in Phase 29.1 at `lib/elixir_ontologies/builders/expression_builder.ex:1572-1578`
- `build_capture_function_ref/4` - Implemented in Phase 29.6 at `lib/elixir_ontologies/builders/expression_builder.ex:1583-1612`

**Test Coverage:**
- Argument index captures are tested in `test/elixir_ontologies/builders/expression_builder_test.exs` starting around line 970 with 15+ tests
- Function reference captures are tested in the same section

---

## Functionality Summary

### Local Call Extraction (Phase 29.2)

**What Was Implemented:**
- Local call detection: `function_name(args)`
- Function name property extraction
- Arity calculation
- Argument extraction (single, multiple, complex)
- Distinction from remote calls
- `refersToFunction` property (placeholder for same-module function)

**AST Pattern:**
```elixir
{function_name, _, args}
# Example: {:process_item, [], [{:item, [], Elixir}]}
```

**Example Code:**
```elixir
# Local call
process_item(item)

# Extracted as LocalCall with:
# - functionName: "process_item"
# - arity: 1
# - hasArgument: [Variable for 'item']
```

### Capture Operator Extraction (Phase 29.4)

**What Was Implemented:**
- Argument index captures: `&1`, `&2`, `&3`, etc.
- Function reference captures: `&Module.fun/arity`
- Function reference captures without arity: `&Module.fun`
- Local function references: `&local_function/arity`
- Type distinction between `CaptureOperator` and `FunctionReference`

**AST Patterns:**
```elixir
# Argument index capture
{:&, [], [1]}  # &1

# Function reference capture
{:&, [], [{:/, [], [function_ref, 2]}]}  # &Module.fun/2

# Function reference without arity
{:&, [], [function_ref]}  # &Module.fun
```

**Example Code:**
```elixir
# Argument index capture
Enum.map(list, &(&1 + 1))  # &1 creates CaptureOperator

# Function reference capture
Enum.map(list, &String.upcase/1)  # &String.upcase/1 creates FunctionReference
```

---

## Documentation References

| Feature | Implemented In | Summary Document | Planning Document |
|---------|---------------|-----------------|-------------------|
| Local Call Extraction | Phase 29.1 | `phase-29-1-remote-call-expression-extraction.md` | `phase-29-1-remote-call-expression-extraction.md` |
| Argument Index Capture | Phase 29.1 | `phase-29-1-remote-call-expression-extraction.md` | `phase-29-1-remote-call-expression-extraction.md` |
| Function Reference Capture | Phase 29.6 | `phase-29-6-function-reference-extraction.md` | `phase-29-6-function-reference-extraction.md` |

---

## Test Coverage

Both features have comprehensive test coverage:

**Local Call Tests (10 tests):**
- `test "dispatches local function call to LocalCall"`
- `test "extracts function name from local call"`
- `test "calculates arity for local calls"`
- `test "builds argument expressions for local calls"`
- `test "builds complex argument expressions for local calls"`
- And 5 more...

**Capture Operator Tests (15+ tests):**
- `test "dispatches &1 to CaptureOperator"`
- `test "dispatches &2 to CaptureOperator"`
- `test "dispatches &Mod.fun/arity to FunctionReference"`
- `test "dispatches &Mod.fun to FunctionReference"`
- And 11 more...

---

## Conclusion

Phase 29.2 and 29.4 were **not skipped** - their functionality was fully implemented and tested. The decision to merge them into other phases was made for:

1. **Code Organization**: Related functionality is grouped together
2. **Maintainability**: Fewer, more cohesive files
3. **Test Organization**: Tests for related functionality are co-located

All functionality that would have been in Phase 29.2 and 29.4 is present and working as described in this document.

---

**Document Date:** 2026-01-16
**Related Review:** Phase 29 Comprehensive Review
