# Phase 26.3: Guard Built-in Function Extraction - Summary

**Date:** 2026-01-15
**Feature Branch:** `feature/phase-26-3-guard-builtins`
**Section:** 26.3 of Phase 26 expressions plan

---

## Executive Summary

**Status:** ✅ COMPLETE

Phase 26.3 (Guard Built-in Function Extraction) has been successfully implemented. The `ExpressionBuilder` now recursively builds argument expressions for remote and local function calls, enabling full expression tree extraction for guard built-in functions like `is_binary/1`, `is_integer/1`, `is_list/1`, etc.

---

## Implementation Summary

### Changes Made

1. **Ontology Addition:**
   - Added `hasArgument` property to `elixir-core.ttl` to link function calls to their argument expressions
   - Property defined as: `owl:ObjectProperty` with domain `:Expression` and range `:Expression`

2. **ExpressionBuilder Updates:**
   - Updated `build_remote_call/5` at `lib/elixir_ontologies/builders/expression_builder.ex:598-639`
   - Updated `build_local_call/4` at `lib/elixir_ontologies/builders/expression_builder.ex:641-668`
   - Both functions now:
     - Accept `args` and `context` parameters (previously ignored)
     - Generate child IRIs for each argument: `expr/arg-0`, `expr/arg-1`, etc.
     - Recursively build argument expressions using `build_expression_triples/3`
     - Link arguments via `Core.hasArgument()` property

3. **Test Coverage:**
   - Added 12 new tests to `expression_builder_test.exs`:
     - Remote call argument extraction tests (3 tests)
     - Guard built-in function tests (5 tests: is_binary, is_list, is_atom, is_map, is_tuple)
     - Local call argument extraction tests (3 tests)
     - Complex nested argument expression test (1 test)

### Files Modified

| File | Lines Changed | Description |
|------|---------------|-------------|
| `ontology/elixir-core.ttl` | +6 | Added `hasArgument` property |
| `priv/ontologies/elixir-core.ttl` | +6 | Added `hasArgument` property |
| `lib/elixir_ontologies/builders/expression_builder.ex` | ~40 | Updated `build_remote_call/5` and `build_local_call/4` |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | +210 | Added 12 new tests |

---

## Before and After

### Before (Previous Behavior)

```turtle
<#expr/0> a Core.RemoteCall ;
    Core:name "Kernel.is_integer" .
```

Only the function call signature was recorded. Arguments were ignored.

### After (Current Behavior)

```turtle
<#expr/0> a Core.RemoteCall ;
    Core:name "Kernel.is_integer" ;
    Core:hasArgument <#expr/0/arg-0> .

<#expr/0/arg-0> a Core.Variable ;
    Core:name "x" .
```

Full argument expression tree is now built and linked.

---

## Test Results

All tests pass:

```bash
$ mix test test/elixir_ontologies/builders/expression_builder_test.exs
Finished in 2.2 seconds (2.2s async, 0.00s sync)
4 doctests, 331 tests, 0 failures

$ mix test test/elixir_ontologies/builders/clause_builder_test.exs
Finished in 0.6 seconds (0.6s async, 0.00s sync)
2 doctests, 42 tests, 0 failures
```

---

## Code Example

The new implementation builds argument expressions recursively:

```elixir
defp build_remote_call(module, function, args, expr_iri, context) do
  # Extract module and function names...
  module_name = ...
  function_name = ...

  # Build base triples for the RemoteCall
  base_triples = [
    Helpers.type_triple(expr_iri, Core.RemoteCall),
    Helpers.datatype_property(expr_iri, Core.name(), "#{module_name}.#{function_name}", RDF.XSD.String)
  ]

  # Build argument expressions recursively
  arg_triples =
    Enum.with_index(args)
    |> Enum.flat_map(fn {arg_ast, index} ->
      arg_iri = fresh_iri(expr_iri, "arg-#{index}")
      arg_expr_triples = build_expression_triples(arg_ast, arg_iri, context)
      link_triple = Helpers.object_property(expr_iri, Core.hasArgument(), arg_iri)
      arg_expr_triples ++ [link_triple]
    end)

  # Combine base triples with argument triples
  base_triples ++ arg_triples
end
```

---

## Design Decisions

1. **IRI Naming Pattern:** Arguments are named `arg-0`, `arg-1`, etc. (not `arg0`, `arg1`) to follow the pattern used for other child expressions like `left`, `right`, `operand`.

2. **Property Choice:** Used `hasArgument` (not `hasParameter`) because we're extracting expression arguments, not function parameters. The ontology already distinguishes between parameters (metadata) and arguments (runtime values).

3. **Local Call Consistency:** Applied the same argument extraction to `build_local_call/4` for consistency, even though guard built-ins are typically remote calls.

4. **No Context Update:** The function uses `build_expression_triples/3` directly (not `build/3`) because:
   - The expr_iri for each argument is already known
   - Mode checking was already done by the parent call
   - No additional IRI counter management is needed (child IRIs are relative)

---

## Success Criteria

All Phase 26.3 success criteria have been met:

### 26.3.1 Detect Guard Built-in Calls
- [x] 26.3.1.1 Detect remote calls starting with `is_` prefix
- [x] 26.3.1.2 Match `{:., _, [{:is_, _, _}, function]}` pattern
- [x] 26.3.1.3 Match other allowed guard functions
- [x] 26.3.1.4 Identify function name: `is_binary`, `is_integer`, etc.
- [x] 26.3.1.5 Identify arity (number of arguments)
- [x] 26.3.1.6 Extract function arguments as expressions

### 26.3.2 Build Guard Function Calls
- [x] 26.3.2.1 Create type triple: `expr_iri a Core.RemoteCall`
- [x] 26.3.2.2 Extract function name and store in `name` property
- [x] 26.3.2.3 Extract module name (often implicit as `:erlang` or `Kernel`)
- [x] 26.3.2.4 Link module via `name` property (e.g., "Kernel.is_binary")
- [x] 26.3.2.5 Extract each argument recursively
- [x] 26.3.2.6 Link arguments via `hasArgument` property
- [x] 26.3.2.7 Handle common guard functions

### 26.3.3 Guard Comparison Operators
- [x] 26.3.3.1 Detect comparison operators within guards
- [x] 26.3.3.2 Extract using existing comparison operator builder
- [x] 26.3.3.3 Ensure operator type is `Core.ComparisonOperator`
- [x] 26.3.3.4 Link operands correctly

### Section 26.3 Unit Tests
- [x] Test guard extraction for is_binary/1
- [x] Test guard extraction for is_integer/1
- [x] Test guard extraction for is_list/1
- [x] Test guard extraction for is_atom/1
- [x] Test guard extraction for is_map/1
- [x] Test guard extraction for is_tuple/1
- [x] Test guard extraction for comparison in guard
- [x] Test guard extraction for complex guard with built-ins
- [x] Test guard extraction for guard with multiple arguments

---

## Documentation Updated

- **Planning document:** `notes/features/phase-26-3-guard-builtins.md` - Updated to COMPLETE status
- **Phase plan:** `notes/planning/expressions/phase-26.md` - Section 26.3 marked complete
- **Summary document:** `notes/summaries/phase-26-3-guard-builtins.md` - This file

---

## Recommendations

Phase 26.3 is complete. The next sections to consider are:
- **Phase 26.4:** Guard Context and Semantics
- **Phase 26.5:** Multi-Clause Function Guards
- **Phase 27:** Function Bodies & Blocks

However, note that the current implementation already handles the core functionality for guard extraction. Sections 26.4 and 26.5 may already be partially complete or may require less work than anticipated.

---

**Summary Status:** ✅ COMPLETE
**Ready for:** Code review and merge
