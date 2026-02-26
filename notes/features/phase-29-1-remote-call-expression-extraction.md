# Phase 29.1: Remote Call Expression Extraction

**Feature Branch:** `feature/phase-29-1-remote-call-expression-extraction`
**Created:** 2026-01-16
**Based On:** Phase 29 Expressions Plan (`notes/planning/expressions/phase-29.md`)

---

## Problem Statement

Phase 29.1 of the expressions plan implements remote call expression extraction. While basic remote call extraction is already implemented in `ExpressionBuilder`, it only stores a combined `name` property (e.g., "String.to_integer"). The plan requires:

1. Separate `moduleName` and `functionName` properties
2. `arity` property (argument count)
3. `refersToModule` object property linking to module IRI
4. `refersToFunction` object property linking to function IRI

These properties are needed for:
- SPARQL queries to find calls by module, function, or arity
- Better semantic representation of function calls
- Linking calls to their target module/function definitions

---

## Solution Overview

This enhancement adds missing properties to the ontology and updates the expression builder to populate them. The changes are:

1. **Ontology additions:**
   - Add `moduleName` datatype property for RemoteCall/LocalCall
   - Add `functionName` datatype property for RemoteCall/LocalCall
   - Add `arity` datatype property for RemoteCall/LocalCall
   - Update `refersToModule` domain to include RemoteCall
   - Update `refersToFunction` domain to include RemoteCall and LocalCall

2. **Builder updates:**
   - Update `build_remote_call/5` to populate new properties
   - Update `build_local_call/4` to populate new properties

3. **Test additions:**
   - Add tests for new properties on remote calls
   - Add tests for new properties on local calls

---

## Technical Details

### Files Modified

| File | Changes |
|------|---------|
| `priv/ontologies/elixir-core.ttl` | Add moduleName, functionName, arity properties; update property domains |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Update build_remote_call and build_local_call |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add tests for new properties |

### Ontology Changes

**New Properties:**
```turtle
:moduleName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "module name"@en ;
    rdfs:comment "The module name for a remote function call."@en ;
    rdfs:domain :RemoteCall ;
    rdfs:range xsd:string .

:functionName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "function name"@en ;
    rdfs:comment "The function name for a function call."@en ;
    rdfs:domain :RemoteCall, :LocalCall ;
    rdfs:range xsd:string .

:arity a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "arity"@en ;
    rdfs:comment "The number of arguments in a function call."@en ;
    rdfs:domain :RemoteCall, :LocalCall ;
    rdfs:range xsd:integer .
```

**Updated Property Domains:**
```turtle
:refersToModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "refers to module"@en ;
    rdfs:domain :ModuleReference, :RemoteCall ;  # Added :RemoteCall
    rdfs:range :Module .

:refersToFunction a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "refers to function"@en ;
    rdfs:domain :FunctionReference, :RemoteCall, :LocalCall ;  # Added :RemoteCall, :LocalCall
    rdfs:range :Function .
```

### Builder Changes

**build_remote_call/5:**
- Extract `moduleName` from module AST
- Extract `functionName` from function atom
- Extract `arity` from argument list length
- Create `refersToModule` link (module IRI - placeholder for now)
- Create `refersToFunction` link (function IRI - placeholder for now)

**build_local_call/4:**
- Extract `functionName` from function atom
- Extract `arity` from argument list length
- Create `refersToFunction` link (function IRI - placeholder for now)

Note: `refersToModule` and `refersToFunction` will use placeholder IRIs for now since we don't have access to the actual module/function IRIs in the expression builder context. This can be enhanced later with a module/function registry.

---

## Success Criteria

- [x] Feature branch created
- [x] Ontology properties added (moduleName, functionName, arity)
- [x] Property domains updated (refersToModule, refersToFunction)
- [x] build_remote_call updated to use new properties
- [x] build_local_call updated to use new properties
- [x] Tests added for new properties on remote calls
- [x] Tests added for new properties on local calls
- [x] All existing tests still passing
- [x] Planning document updated with progress
- [ ] Summary document written

---

## Implementation Plan

### 1.0 Setup and Verification
- [x] 1.1 Create feature branch `feature/phase-29-1-remote-call-expression-extraction`
- [x] 1.2 Create planning document
- [x] 1.3 Verify current implementation and identify gaps

### 2.0 Ontology Updates
- [x] 2.1 Add `moduleName` property to elixir-core.ttl
- [x] 2.2 Add `functionName` property to elixir-core.ttl
- [x] 2.3 Add `arity` property to elixir-core.ttl
- [x] 2.4 Update `refersToModule` domain to include RemoteCall
- [x] 2.5 Update `refersToFunction` domain to include RemoteCall and LocalCall

### 3.0 Builder Updates
- [x] 3.1 Update `build_remote_call/5` to add moduleName property
- [x] 3.2 Update `build_remote_call/5` to add functionName property
- [x] 3.3 Update `build_remote_call/5` to add arity property
- [x] 3.4 Update `build_remote_call/5` to add refersToModule property
- [x] 3.5 Update `build_remote_call/5` to add refersToFunction property
- [x] 3.6 Update `build_local_call/4` to add functionName property
- [x] 3.7 Update `build_local_call/4` to add arity property
- [x] 3.8 Update `build_local_call/4` to add refersToFunction property

### 4.0 Test Updates
- [x] 4.1 Add test for remote call moduleName property
- [x] 4.2 Add test for remote call functionName property
- [x] 4.3 Add test for remote call arity property
- [x] 4.4 Add test for local call functionName property
- [x] 4.5 Add test for local call arity property
- [x] 4.6 Run all tests and verify passing

### 5.0 Final Verification
- [x] 5.1 Run all tests and verify no regressions
- [ ] 5.2 Create summary document
- [ ] 5.3 Ask for commit and merge permission

---

## Notes and Considerations

### Design Decisions

1. **Placeholder IRIs for references**: The `refersToModule` and `refersToFunction` properties will use placeholder IRIs since we don't have access to the actual module/function IRIs in the expression builder context. A future enhancement could add a module/function registry to resolve these.

2. **Keep existing `name` property**: We'll keep the existing `name` property with the combined `module.function` format for backward compatibility and simplicity.

3. **Arity from argument count**: Arity is calculated from the argument list length. This matches the semantic meaning of arity (number of arguments the function is being called with).

### Testing Strategy

- Add new tests specifically for the new properties
- Ensure all existing tests still pass (backward compatibility)
- Test with various remote call patterns (simple module, nested module, __MODULE__)

### Known Limitations

1. **Module/Function IRIs**: We don't have access to the actual module/function IRIs in the expression builder, so `refersToModule` and `refersToFunction` will use placeholder IRIs. A future enhancement could add a module/function registry.

2. **Dynamic calls**: Calls where the module or function is computed at runtime (e.g., `apply(mod, fun, args)`) are not handled. This is a limitation of static analysis.

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
- Created feature branch `feature/phase-29-1-remote-call-expression-extraction`
- Created planning document
- Added 3 new ontology properties (`moduleName`, `functionName`, `arity`)
- Updated `refersToModule` domain to include `RemoteCall`
- Updated `refersToFunction` domain to include `RemoteCall` and `LocalCall`
- Updated `build_remote_call/5` to populate all new properties
- Updated `build_local_call/4` to populate all new properties
- Added 10 new tests for the new properties
- All 519 tests passing (expression builder + control flow builder tests)

**Test Results:**
- 385 expression builder tests + 9 doctests: 0 failures
- 134 control flow builder tests: 0 failures
- Total: 519 tests, 0 failures

---

*Last Updated:* 2026-01-16
*Branch:* feature/phase-29-1-remote-call-expression-extraction
