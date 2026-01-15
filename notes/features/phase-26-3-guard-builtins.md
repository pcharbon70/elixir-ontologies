# Phase 26.3: Guard Built-in Function Extraction

**Feature Branch:** `feature/phase-26-3-guard-builtins`
**Created:** 2026-01-15
**Based On:** Phase 26 Section 26.3 of expressions plan
**Status:** ✅ COMPLETE

---

## Problem Statement

Phase 26.3 requires extracting full expression trees for guard built-in functions like `is_binary/1`, `is_integer/1`, `is_list/1`, etc. Previously, the `build_remote_call/5` function in `ExpressionBuilder` only recorded the function call identity but did not recursively build argument ASTs into expression triples.

**Previous behavior:**
```turtle
<#expr/guard> a Core.RemoteCall ;
    Core:name "Kernel.is_integer" .
```

**Current behavior:**
```turtle
<#expr/guard> a Core.RemoteCall ;
    Core:name "Kernel.is_integer" ;
    Core:hasArgument <#expr/arg-0> .
<#expr/arg-0> a Core.Variable ;
    Core:name "x" .
```

---

## Solution Overview

Updated `build_remote_call/5` and `build_local_call/4` to:
1. Use context parameter for recursive expression building
2. Build each argument as a nested expression
3. Link arguments via `Core.hasArgument` property
4. Generate child IRIs for each argument (`expr/arg-0`, `expr/arg-1`, etc.)
5. Handle variable-length argument lists

---

## Technical Details

### Files Modified

| File | Changes |
|------|---------|
| `ontology/elixir-core.ttl` | Added `hasArgument` property |
| `priv/ontologies/elixir-core.ttl` | Added `hasArgument` property |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Updated `build_remote_call/5` and `build_local_call/4` |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Added 12 new tests |

### Ontology Addition

Added `hasArgument` property to `elixir-core.ttl`:

```turtle
:hasArgument a owl:ObjectProperty ;
    rdfs:label "has argument"@en ;
    rdfs:comment "Links a function call (RemoteCall or LocalCall) to its argument expressions."@en ;
    rdfs:subPropertyOf :hasChild ;
    rdfs:domain :Expression ;
    rdfs:range :Expression .
```

### Implementation

**Location:** `lib/elixir_ontologies/builders/expression_builder.ex:598-639`

```elixir
defp build_remote_call(module, function, args, expr_iri, context) do
  # Extract module name from aliases AST
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

Also updated `build_local_call/4` with the same pattern.

---

## Success Criteria

- [x] 26.3.1.1 Detect remote calls starting with `is_` prefix
- [x] 26.3.1.2 Match `{{:., _, [{:is_, _, _}, function]}` pattern
- [x] 26.3.1.3 Match other allowed guard functions
- [x] 26.3.1.4 Identify function name: `is_binary`, `is_integer`, etc.
- [x] 26.3.1.5 Identify arity (number of arguments)
- [x] 26.3.1.6 Extract function arguments as expressions

- [x] 26.3.2.1 Create type triple: `expr_iri a Core.RemoteCall`
- [x] 26.3.2.2 Extract function name and store in `name` property
- [x] 26.3.2.3 Extract module name (often implicit as `:erlang` or `Kernel`)
- [x] 26.3.2.4 Link module via `name` property (e.g., "Kernel.is_binary")
- [x] 26.3.2.5 Extract each argument recursively
- [x] 26.3.2.6 Link arguments via `hasArgument` property
- [x] 26.3.2.7 Handle common guard functions

- [x] 26.3.3.1 Detect comparison operators within guards
- [x] 26.3.3.2 Extract using existing comparison operator builder
- [x] 26.3.3.3 Ensure operator type is `Core.ComparisonOperator`
- [x] 26.3.3.4 Link operands correctly

**Section 26.3 Unit Tests:**
- [x] Test guard extraction for is_binary/1
- [x] Test guard extraction for is_integer/1
- [x] Test guard extraction for is_list/1
- [x] Test guard extraction for is_atom/1
- [x] Test guard extraction for is_map/1
- [x] Test guard extraction for is_tuple/1
- [x] Test guard extraction for remote calls with arguments
- [x] Test guard extraction for complex guard with built-ins
- [x] Test guard extraction for guard with multiple arguments
- [x] Test local calls with arguments

---

## Current Status

**Status:** ✅ COMPLETE

**What works:**
- Remote call detection (pattern matching)
- Module name extraction
- Function name extraction
- Type assignment (`Core.RemoteCall`)
- **Recursive argument expression building**
- **Argument linking via `Core.hasArgument`**
- Local call argument extraction
- Complex nested argument expressions (e.g., `is_integer(x + 1)`)
- Multiple arguments (e.g., `func(a, b)`)

**Test Results:**
```bash
# All 331 expression builder tests pass
mix test test/elixir_ontologies/builders/expression_builder_test.exs
# 4 doctests, 331 tests, 0 failures

# All 42 clause builder tests pass
mix test test/elixir_ontologies/builders/clause_builder_test.exs
# 2 doctests, 42 tests, 0 failures
```

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run clause builder tests (includes guard tests)
mix test test/elixir_ontologies/builders/clause_builder_test.exs
```

---

## Files Modified

1. **Ontology:**
   - `ontology/elixir-core.ttl` - Added `hasArgument` property
   - `priv/ontologies/elixir-core.ttl` - Added `hasArgument` property

2. **Implementation:**
   - `lib/elixir_ontologies/builders/expression_builder.ex` - Updated `build_remote_call/5` and `build_local_call/4`

3. **Tests:**
   - `test/elixir_ontologies/builders/expression_builder_test.exs` - Added 12 new tests:
     - `builds argument expressions for remote calls`
     - `builds multiple argument expressions`
     - `builds complex argument expressions`
     - `guard built-in: is_binary/1 with variable argument`
     - `guard built-in: is_list/1 with variable argument`
     - `guard built-in: is_atom/1`
     - `guard built-in: is_map/1`
     - `guard built-in: is_tuple/1`
     - `builds argument expressions for local calls`
     - `builds multiple argument expressions for local calls`
     - `builds complex argument expressions for local calls`

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-26-3-guard-builtins
*Status:* ✅ COMPLETE
