# Phase 30.2: Rescue Clause Expression Extraction

**Feature Branch:** `feature/phase-30-2-rescue-clauses`
**Created:** 2026-01-17
**Based On:** Phase 30 Expressions Plan (`notes/planning/expressions/phase-30.md`)

---

## Problem Statement

Phase 30.2 implements extraction for rescue clauses with exception pattern matching. Rescue clauses allow Elixir code to catch and handle exceptions, making them a critical part of exception handling.

### Current State
- Phase 30.1 implemented basic try expression structure with `hasTryBody`
- Try expressions detect rescue clauses but don't extract them yet
- The `hasRescueClause` property is currently a boolean flag
- RescueClause class does not exist in the ontology
- Exception pattern properties don't exist

### Requirements
1. Add RescueClause class to ontology
2. Add rescue-related properties: `hasRescueBody`, `hasExceptionPattern`, `refersToExceptionType`
3. Change `hasRescueClause` from boolean to object property linking to RescueClause instances
4. Extract rescue clause patterns (variables, wildcards, struct patterns)
5. Extract rescue clause bodies
6. Preserve clause order (important for pattern matching semantics)

---

## Solution Overview

Implement rescue clause extraction in ExpressionBuilder:

### Rescue Clause Structure
- Each rescue clause becomes a RescueClause instance with its own IRI
- Clauses are linked via `hasRescueClause` property as an ordered list
- Each clause has an exception pattern and a rescue body
- Exception patterns capture variable bindings and struct types

### IRI Structure
- Rescue clause: `{try_iri}/rescue/{index}` (0-indexed)
- Rescue body: `{rescue_clause_iri}/body`

---

## Ontology Changes

### New Class: RescueClause
```turtle
:RescueClause a owl:Class ;
    rdfs:label "Rescue Clause"@en ;
    rdfs:comment "A clause in a try expression that catches and handles exceptions."@en ;
    rdfs:subClassOf :Expression .
```

### New Properties
```turtle
:hasRescueBody a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has rescue body"@en ;
    rdfs:comment "Links a rescue clause to its handler body expression."@en ;
    rdfs:domain :RescueClause ;
    rdfs:range :Block .

:hasExceptionPattern a owl:ObjectProperty ;
    rdfs:label "has exception pattern"@en ;
    rdfs:comment "Links a rescue clause to its exception matching pattern."@en ;
    rdfs:domain :RescueClause ;
    rdfs:range :Pattern .

:refersToExceptionType a owl:ObjectProperty ;
    rdfs:label "refers to exception type"@en ;
    rdfs:comment "Links a rescue clause pattern to a specific exception type (struct)."@en ;
    rdfs:domain :RescueClause ;
    rdfs:range :Module .
```

### Modified Property: hasRescueClause
Change from boolean to object property:
```turtle
:hasRescueClause a owl:ObjectProperty ;
    rdfs:label "has rescue clause"@en ;
    rdfs:comment "Links a try expression to its rescue clauses (ordered)."@en ;
    rdfs:domain :TryExpression ;
    rdfs:range :RescueClause .
```

---

## Technical Details

### Files to Modify

| File | Changes | Purpose |
|------|---------|---------|
| `priv/ontologies/elixir-core.ttl` | Add RescueClause class and properties | Ontology extension |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Implement rescue clause extraction | Core functionality |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add rescue clause tests | Test coverage |

### AST Pattern for Rescue Clauses

```elixir
# Rescue clause format in try AST
{:try, [],
 [[
   do: :risky_operation,
   rescue: [
     {:->, [], [[pattern_1], body_1]},
     {:->, [], [[pattern_2], body_2]}
   ]
 ]]}

# Example patterns:
# Variable rescue:    [[e]]        -> matches any exception, binds to e
# Wildcard rescue:    [[_]]         -> matches any exception, discards
# Struct rescue:      [[%Error{}]]  -> matches only Error structs
# With field:         [[%Error{msg: m}]]
```

### Rescue Clause Examples

```elixir
# Wildcard rescue
try do
  risky()
rescue
  _ -> :error
end

# Variable rescue
try do
  risky()
rescue
  e -> handle(e)
end

# Typed rescue
try do
  risky()
rescue
  %RuntimeError{} -> :runtime_error
  %ArgumentError{message: msg} -> {:error, msg}
end
```

---

## Implementation Plan

### 1.0 Ontology Updates ✅
- [x] 1.1 Create feature branch `feature/phase-30-2-rescue-clauses`
- [x] 1.2 Create planning document
- [x] 1.3 Add RescueClause class to elixir-core.ttl
- [x] 1.4 Add hasRescueBody property
- [x] 1.5 Add hasExceptionPattern property
- [x] 1.6 Add refersToExceptionType property
- [x] 1.7 Modify hasRescueClause property (object property, not boolean)

### 2.0 Rescue Clause Detection
- [x] 2.1 Update `build_try_expression/3` to call rescue extraction
- [x] 2.2 Implement `build_rescue_clauses/4` function
- [x] 2.3 Extract rescue list from try blocks: `Keyword.get(blocks, :rescue, [])`
- [x] 2.4 Handle empty rescue list (no rescue clauses)
- [x] 2.5 Iterate through rescue clauses with index

### 3.0 Rescue Pattern Extraction
- [x] 3.1 Implement `build_rescue_clause/5` function
- [x] 3.2 Generate clause IRI: `fresh_iri(try_iri, "rescue/#{index}")`
- [x] 3.3 Create type triple: clause_iri a Core.RescueClause
- [x] 3.4 Extract pattern from `{:->, _, [[pattern], body]}`
- [x] 3.5 Handle wildcard pattern: `_`
- [x] 3.6 Handle variable pattern: `e`
- [x] 3.7 Handle struct pattern: `%ExceptionType{}`
- [x] 3.8 Link pattern via hasExceptionPattern
- [x] 3.9 Link exception type via refersToExceptionType (for struct patterns)

### 4.0 Rescue Body Extraction
- [x] 4.1 Extract body from rescue clause
- [x] 4.2 Generate body IRI: `{clause_iri}/body`
- [x] 4.3 Build body expression via `build_expression_triples/3`
- [x] 4.4 Link via hasRescueBody property
- [x] 4.5 Handle multi-expression bodies (wrap in block)

### 5.0 Clause Ordering
- [x] 5.1 Link rescue clauses via hasRescueClause as RDF list
- [x] 5.2 Preserve original clause order (critical for semantics)
- [x] 5.3 Handle single clause
- [x] 5.4 Handle multiple clauses

### 6.0 Unit Tests
- [x] 6.1 Test wildcard rescue extraction
- [x] 6.2 Test variable rescue extraction
- [x] 6.3 Test typed rescue extraction (struct patterns)
- [x] 6.4 Test rescue with field binding
- [x] 6.5 Test multiple rescue clauses
- [x] 6.6 Test rescue clause ordering
- [x] 6.7 Test rescue body extraction
- [x] 6.8 Test IRI structure for rescue clauses

### 7.0 Final Verification
- [x] 7.1 Run all tests
- [x] 7.2 Verify no regressions
- [x] 7.3 Create summary document
- [x] 7.4 Mark tasks complete in plan
- [ ] 7.5 Ask for commit and merge permission

---

## Success Criteria

1. **Rescue clause detection** - Correctly identify and extract rescue clauses
2. **Pattern extraction** - Capture exception patterns (wildcard, variable, struct)
3. **Body extraction** - Extract and link rescue bodies
4. **Clause ordering** - Preserve clause order via RDF list
5. **Test coverage** - 8+ unit tests covering all rescue patterns
6. **Integration** - Works with existing try expression structure

---

## Notes and Considerations

### Rescue Clause Semantics
- Rescue clauses are tried in order (first match wins)
- Pattern matching follows Elixir's structural matching rules
- Struct patterns can bind fields and optionally match specific types
- Variable patterns bind to any exception
- Wildcard patterns match any exception without binding

### Integration with Pattern Builder
- Exception patterns use the existing pattern builder infrastructure
- Struct patterns: `%Error{}` are handled as StructPattern
- Variable patterns: `e` are handled as VariablePattern
- Wildcard patterns: `_` are handled as WildcardPattern

### RDF List for Ordering
- Rescue clauses are linked as an RDF list to preserve order
- This follows the same pattern as function clauses
- The list structure allows SPARQL queries to find clauses by position

---

## Current Status

**Status:** ✅ COMPLETE - Ready for commit and merge

**What Works:**
- RescueClause class added to elixir-core.ttl
- All rescue-related properties added (hasRescueBody, hasExceptionPattern, refersToExceptionType)
- hasRescueClause changed from boolean to object property
- Rescue clause extraction fully implemented
- Pattern detection supports wildcard, variable, and struct patterns
- Rescue body extraction with multi-expression support
- RDF list ordering preserves clause order
- 8 unit tests covering all rescue patterns (all passing)
- Fixed wildcard pattern detection to work in any module context

**Test Results:**
- 424 tests total (added 7 rescue clause tests)
- 8 rescue clause tests: all passing
- 1 pre-existing test failure (unrelated to Phase 30.2)

**Decisions Made:**
- Add RescueClause class to ontology
- Add hasRescueBody, hasExceptionPattern, refersToExceptionType properties
- Change hasRescueClause from boolean to object property for linking individual clauses
- Removed `@compile {:inline, detect_pattern_type: 1}` directive to allow easier pattern type updates

---

*Last Updated:* 2026-01-17
*Branch:* feature/phase-30-2-rescue-clauses
*Status:* COMPLETE
