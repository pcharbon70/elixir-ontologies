# Phase 30.3: Catch Clause Expression Extraction

**Feature Branch:** `feature/phase-30-3-catch-clauses`
**Created:** 2026-01-18
**Based On:** Phase 30 Expressions Plan (`notes/planning/expressions/phase-30.md`)

---

## Problem Statement

Phase 30.3 implements extraction for catch clauses which catch thrown values, errors, exits, and throws in Elixir try expressions. Unlike rescue clauses which handle exceptions, catch clauses handle values thrown via `throw/1`, errors (from Erlang), and exit signals.

### Current State
- Phase 30.1 implemented basic try expression structure with `hasTryBody`
- Phase 30.2 implemented rescue clause extraction
- Try expressions detect catch clauses but don't extract them yet
- CatchClause class does not exist in the ontology
- Catch type and pattern properties don't exist

### Requirements
1. Add CatchClause class to ontology
2. Add catch-related properties: `hasCatchBody`, `hasCatchPattern`, `hasCatchType`
3. Extract catch clause patterns (variables, wildcards, typed catches)
4. Extract catch clause bodies
5. Preserve clause order (important for pattern matching semantics)
6. Support catch types: `:throw`, `:error`, `:exit` (and untyped catches all)

---

## Solution Overview

Implement catch clause extraction in ExpressionBuilder:

### Catch Clause Structure
- Each catch clause becomes a CatchClause instance with its own IRI
- Clauses are linked via `hasCatchClause` property as an ordered list
- Each clause has a catch type, a value pattern, and a catch body
- Catch types distinguish between throw, error, and exit

### IRI Structure
- Catch clause: `{try_iri}/catch/{index}` (0-indexed)
- Catch body: `{catch_clause_iri}/body`

---

## Ontology Changes

### New Class: CatchClause
```turtle
:CatchClause a owl:Class ;
    rdfs:label "Catch Clause"@en ;
    rdfs:comment "A clause in a try expression that catches thrown values, errors, or exits."@en ;
    rdfs:subClassOf :Expression .
```

### New Properties
```turtle
:hasCatchBody a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has catch body"@en ;
    rdfs:comment "Links a catch clause to its handler body expression."@en ;
    rdfs:domain :CatchClause ;
    rdfs:range :Block .

:hasCatchPattern a owl:ObjectProperty ;
    rdfs:label "has catch pattern"@en ;
    rdfs:comment "Links a catch clause to its value matching pattern."@en ;
    rdfs:domain :CatchClause ;
    rdfs:range :Pattern .

:hasCatchType a owl:ObjectProperty ;
    rdfs:label "has catch type"@en ;
    rdfs:comment "Links a catch clause to the type of value being caught (:throw, :error, :exit)."@en ;
    rdfs:domain :CatchClause ;
    rdfs:range :Literal .
```

### New Property: hasCatchClause
```turtle
:hasCatchClause a owl:ObjectProperty ;
    rdfs:label "has catch clause"@en ;
    rdfs:comment "Links a try expression to its catch clauses (ordered)."@en ;
    rdfs:domain :TryExpression ;
    rdfs:range :CatchClause .
```

---

## Technical Details

### Files to Modify

| File | Changes | Purpose |
|------|---------|---------|
| `priv/ontologies/elixir-core.ttl` | Add CatchClause class and properties | Ontology extension |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Implement catch clause extraction | Core functionality |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add catch clause tests | Test coverage |

### AST Pattern for Catch Clauses

```elixir
# Catch clause format in try AST
{:try, [],
 [[
   do: :risky_operation,
   catch: [
     {:->, [], [[{:catch_type, pattern_ast}], body_1]},
     {:->, [], [[pattern_ast]], body_2}  # untyped catch
   ]
 ]]}

# Example patterns:
# Typed throw catch:  [[{:throw, value}]] -> catches thrown values
# Typed error catch:  [[{:error, reason}]] -> catches errors
# Typed exit catch:  [[{:exit, reason}]] -> catches exit signals
# Untyped catch:      [[value]] -> catches all types
# Wildcard catch:     [[_]] -> catches and discards
```

### Catch Clause Examples

```elixir
# Untyped wildcard catch
try do
  risky()
catch
  _ -> :caught
end

# Typed throw catch
try do
  risky()
catch
  :throw, value -> {:thrown, value}
end

# Typed error catch
try do
  risky()
catch
  :error, reason -> {:error, reason}
end

# Typed exit catch
try do
  risky()
catch
  :exit, reason -> {:exit, reason}
end

# Multiple catch clauses
try do
  risky()
catch
  :throw, value -> :handle_throw
  :error, reason -> :handle_error
  :exit, reason -> :handle_exit
end
```

---

## Implementation Plan

### 1.0 Ontology Updates
- [x] 1.1 Create feature branch `feature/phase-30-3-catch-clauses`
- [x] 1.2 Create planning document
- [x] 1.3 Add CatchClause class to elixir-core.ttl
- [x] 1.4 Add hasCatchBody property
- [x] 1.5 Add hasCatchPattern property
- [x] 1.6 Add hasCatchType property
- [x] 1.7 Add hasCatchClause property to ontology

### 2.0 Catch Clause Detection
- [x] 2.1 Update `build_try_expression/3` to call catch extraction
- [x] 2.2 Implement `build_catch_clauses/4` function
- [x] 2.3 Extract catch list from try blocks: `Keyword.get(blocks, :catch, [])`
- [x] 2.4 Handle empty catch list (no catch clauses)
- [x] 2.5 Iterate through catch clauses with index

### 3.0 Catch Pattern and Type Extraction
- [x] 3.1 Implement `build_catch_clause/5` function
- [x] 3.2 Generate clause IRI: `fresh_iri(try_iri, "catch/#{index}")`
- [x] 3.3 Create type triple: clause_iri a Core.CatchClause
- [x] 3.4 Extract pattern from `{:->, _, [[pattern_or_type], body]}`
- [x] 3.5 Detect typed catch: `{:catch_type, pattern}` tuple
- [x] 3.6 Handle untyped catch (single pattern)
- [x] 3.7 Handle wildcard pattern: `_`
- [x] 3.8 Handle variable pattern: `value`, `reason`
- [x] 3.9 Link catch type via hasCatchType (for typed catches)
- [x] 3.10 Link pattern via hasCatchPattern

### 4.0 Catch Body Extraction
- [x] 4.1 Extract body from catch clause
- [x] 4.2 Generate body IRI: `{catch_clause_iri}/body`
- [x] 4.3 Build body expression via `build_expression_triples/3`
- [x] 4.4 Link via hasCatchBody property
- [x] 4.5 Handle multi-expression bodies (wrap in block)

### 5.0 Clause Ordering
- [x] 5.1 Link catch clauses via hasCatchClause as RDF list
- [x] 5.2 Preserve original clause order (critical for semantics)
- [x] 5.3 Handle single clause
- [x] 5.4 Handle multiple clauses

### 6.0 Unit Tests
- [x] 6.1 Test untyped wildcard catch extraction
- [x] 6.2 Test untyped variable catch extraction
- [x] 6.3 Test typed throw catch extraction
- [x] 6.4 Test typed error catch extraction
- [x] 6.5 Test typed exit catch extraction
- [x] 6.6 Test multiple catch clauses in order
- [x] 6.7 Test catch body extraction
- [x] 6.8 Test IRI structure for catch clauses

### 7.0 Final Verification
- [x] 7.1 Run all tests
- [x] 7.2 Verify no regressions
- [x] 7.3 Create summary document
- [x] 7.4 Mark tasks complete in plan
- [ ] 7.5 Ask for commit and merge permission

---

## Success Criteria

1. **Catch clause detection** - Correctly identify and extract catch clauses
2. **Type extraction** - Capture catch types (:throw, :error, :exit) or untyped
3. **Pattern extraction** - Capture value patterns (wildcard, variable, complex)
4. **Body extraction** - Extract and link catch bodies
5. **Clause ordering** - Preserve clause order via RDF list
6. **Test coverage** - 8+ unit tests covering all catch patterns
7. **Integration** - Works with existing try expression structure

---

## Notes and Considerations

### Catch Clause Semantics
- Catch clauses are tried in order (first match wins)
- Typed catches only catch values of that specific type
- Untyped catches catch all types (throw, error, exit)
- Catch is primarily used for Erlang interop and non-local control flow
- Rescue is preferred for exception handling in Elixir code

### AST Structure for Catch Clauses
- Typed catch: `{{:throw, value}, body}` - pattern is a 2-tuple
- Untyped catch: `{value, body}` - pattern is just the value
- The pattern array in catch clauses can be: `[[{:throw, value}]]` or `[[value]]`
- Need to detect if pattern is a 2-tuple to extract type

### Integration with Pattern Builder
- Catch value patterns use the existing pattern builder infrastructure
- The pattern is the second element of the catch type tuple: `{:throw, value}`
- Variable patterns: `value` are handled as VariablePattern
- Wildcard patterns: `_` are handled as WildcardPattern

### RDF List for Ordering
- Catch clauses are linked as an RDF list to preserve order
- This follows the same pattern as rescue clauses
- The list structure allows SPARQL queries to find clauses by position

### Difference from Rescue Clauses
- Rescue clauses match on exception structs
- Catch clauses match on thrown values (any term)
- Rescue uses `hasExceptionPattern`, catch uses `hasCatchPattern`
- Rescue uses `refersToExceptionType`, catch uses `hasCatchType`

---

## Current Status

**Status:** ✅ COMPLETE - Ready for commit and merge

**What Works:**
- CatchClause class added to elixir-core.ttl
- All catch-related properties added (hasCatchBody, hasCatchPattern, hasCatchType)
- hasCatchClause changed from boolean to object property for linking individual clauses
- Catch clause extraction fully implemented
- Pattern type detection supports typed catches (:throw, :error, :exit) and untyped catches
- Value pattern extraction supports wildcard, variable, and complex patterns
- Catch body extraction with multi-expression support
- RDF list ordering preserves clause order
- 8 unit tests covering all catch patterns (all passing)
- Tests distinguish between typed and untyped catch clauses

**Test Results:**
- 425 tests total (added 8 catch clause tests)
- 8 catch clause tests: all passing
- 1 pre-existing test failure (unrelated to Phase 30.3)

**Decisions Made:**
- Add CatchClause class to ontology
- Add hasCatchBody, hasCatchPattern, hasCatchType properties
- Change hasCatchClause from boolean to object property for linking individual clauses
- Catch type stored as string literal (":throw", ":error", ":exit")

---

*Last Updated:* 2026-01-18
*Branch:* feature/phase-30-3-catch-clauses
*Status:* COMPLETE
