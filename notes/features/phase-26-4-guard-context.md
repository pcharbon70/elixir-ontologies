# Phase 26.4: Guard Context and Semantics

**Feature Branch:** `feature/phase-26-4-guard-context`
**Created:** 2026-01-15
**Based On:** Phase 26 Section 26.4 of expressions plan
**Status:** ✅ COMPLETE

---

## Problem Statement

Section 26.4 requires ensuring that guard expressions preserve their semantic meaning and can be distinguished from regular expressions.

---

## Implementation Summary

**Decision:** Implement full `inGuardContext` property marking for explicit guard context identification.

**Rationale:** While IRI suffix `/guard` and `hasGuard` property already provide guard context, the `inGuardContext` boolean property provides:
1. Explicit semantic marking - no need to parse IRI strings in SPARQL queries
2. Clearer distinction when expressions are queried independently
3. Easier SPARQL filtering: `?expr :inGuardContext true`

---

## Technical Details

### Files Modified

| File | Changes |
|------|---------|
| `ontology/elixir-core.ttl` | Added `inGuardContext` property |
| `priv/ontologies/elixir-core.ttl` | Added `inGuardContext` property |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Added guard context marking logic |
| `lib/elixir_ontologies/builders/clause_builder.ex` | Pass `guard_context?: true` option |
| `test/elixir_ontologies/builders/clause_builder_test.exs` | Added 4 new tests |

### Ontology Addition

Added `inGuardContext` property to `elixir-core.ttl`:

```turtle
:inGuardContext a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "in guard context"@en ;
    rdfs:comment "Marks an expression as being within a guard clause. Guard expressions have restricted semantics - only certain operations and functions are allowed."@en ;
    rdfs:domain :Expression ;
    rdfs:range xsd:boolean .
```

### Implementation

**ExpressionBuilder** (`lib/elixir_ontologies/builders/expression_builder.ex:171-190`):
- Added guard context marking in `do_build/3`
- Checks for `guard_context?: true` option
- Adds `inGuardContext` property with value `true` when in guard context

**ClauseBuilder** (`lib/elixir_ontologies/builders/clause_builder.ex:282`):
- Passes `guard_context?: true` when calling `ExpressionBuilder.build/3` for guard expressions

### Example RDF Output

**Guard expression:**
```turtle
<https://example.org/code#expr/0/guard> a Core.RemoteCall ;
    Core:name "Kernel.is_integer" ;
    Core:inGuardContext true ;
    Core:hasArgument <https://example.org/code#expr/0/guard/arg-0> .
```

**Regular expression (no inGuardContext):**
```turtle
<https://example.org/code#expr/1> a Core.ComparisonOperator ;
    Core:operatorSymbol "==" ;
    Core:hasLeftOperand <https://example.org/code#expr/1/left> ;
    Core:hasRightOperand <https://example.org/code#expr/1/right> .
```

---

## Success Criteria

### 26.4.1 Guard Context Marking

- [x] 26.4.1.1 Guard expressions are marked with `inGuardContext` property
- [x] 26.4.1.2 Property is boolean (`xsd:boolean`) set to `true` for guards
- [x] 26.4.1.3 Guards distinguished from body expressions via property
- [x] 26.4.1.4 Document guard limitations (compiler enforces)
- [x] 26.4.1.5 Note that guard-friendly expressions are subset of all expressions

### 26.4.2 Guard Expression Validation

- [x] 26.4.2.6 Document that Elixir compiler validates guards
- **Skipped:** 26.4.2.1-26.4.2.5 - `guard_safe?/1` validation not implemented (compiler already validates)

**Rationale for skipping validation:**
1. Elixir compiler validates guards - any guard that compiles is guard-safe
2. Redundant validation would duplicate compiler work
3. Our validation might not track Elixir's exact guard rules
4. Maintenance burden tracking Elixir releases' guard changes

### Section 26.4 Unit Tests

- [x] Test guard context marking works correctly
- [x] Test guard expressions are distinguished from body expressions
- [x] Test guard with and/or operators has inGuardContext
- [x] Test guard with remote calls has inGuardContext

---

## Test Results

```bash
$ mix test test/elixir_ontologies/builders/clause_builder_test.exs
Finished in 0.7 seconds (0.7s async, 0.00s sync)
2 doctests, 46 tests, 0 failures

$ mix test test/elixir_ontologies/builders/expression_builder_test.exs
Finished in 2.3 seconds (2.3s async, 0.00s sync)
4 doctests, 331 tests, 0 failures
```

**New tests added:**
1. `guard expression has inGuardContext property`
2. `guard expression with and/or has inGuardContext property`
3. `regular expression does not have inGuardContext property`
4. `guard with remote call has inGuardContext property on call`

---

## SPARQL Query Examples

With `inGuardContext` property, guard expressions can be queried directly:

```sparql
# Find all guard expressions
PREFIX core: <https://w3id.org/elixir-code#>

SELECT ?guardExpr
WHERE {
  ?guardExpr core:inGuardContext true .
}
```

```sparql
# Find guard expressions using is_integer
PREFIX core: <https://w3id.org/elixir-code#>

SELECT ?guardExpr
WHERE {
  ?guardExpr core:inGuardContext true ;
             core:name "Kernel.is_integer" .
}
```

```sparql
# Compare guard vs body expressions
PREFIX core: <https://w3id.org/elixir-code#>

SELECT ?guardExpr ?bodyExpr
WHERE {
  ?guardExpr core:inGuardContext true .
  ?bodyExpr a core:Expression .
  FILTER NOT EXISTS { ?bodyExpr core:inGuardContext true }
}
```

---

## Current Status

**Status:** ✅ COMPLETE

**What works:**
- Guards are linked via `hasGuard` property
- Guards have unique IRI suffix `/guard`
- Guards are explicitly marked with `inGuardContext` boolean property
- Regular expressions do NOT have `inGuardContext` property
- Elixir compiler validates guard safety

**Test coverage:**
- 46 clause builder tests pass (4 new tests for guard context)
- 331 expression builder tests pass

**How to run tests:**
```bash
# Run clause builder tests (includes guard tests)
mix test test/elixir_ontologies/builders/clause_builder_test.exs

# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs
```

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-26-4-guard-context
*Status:* ✅ COMPLETE
