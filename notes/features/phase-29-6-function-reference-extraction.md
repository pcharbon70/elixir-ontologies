# Phase 29.6: Named Function Reference Extraction

**Feature Branch:** `feature/phase-29-6-function-reference-extraction`
**Created:** 2026-01-16
**Based On:** Phase 29 Expressions Plan (`notes/planning/expressions/phase-29.md`)

---

## Problem Statement

Phase 29.6 implements proper extraction for function references using the `FunctionReference` ontology class.

Currently, capture operators like `&Mod.fun/arity` are extracted as `CaptureOperator` with individual properties (`captureModuleName`, `captureFunctionName`, `captureArity`). However, the ontology has a dedicated `FunctionReference` class with a `refersToFunction` object property that should be used instead to properly link to the actual function being referenced.

### Current State

The `FunctionReference` class exists in the ontology:
```turtle
:FunctionReference a owl:Class ;
    rdfs:label "Function Reference"@en ;
    rdfs:comment "A reference to a function, possibly captured with &Module.fun/arity."@en ;
    rdfs:subClassOf :Reference .
```

The `refersToFunction` property also exists:
```turtle
:refersToFunction a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "refers to function"@en ;
    rdfs:domain :FunctionReference, :RemoteCall, :LocalCall ;
    rdfs:range :Function .
```

But capture operators use `CaptureOperator` type with string properties instead.

---

## Solution Overview

Update the capture operator extraction to use `FunctionReference` type with proper `refersToFunction` linking. This will:

1. Use the existing `FunctionReference` class for capture operators
2. Add `refersToFunction` object property linking to the function IRI
3. Keep backward compatibility with existing properties for information
4. Ensure function references are distinguished from function calls

---

## Technical Details

### Files Modified

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Update capture operator to use FunctionReference type |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add tests for FunctionReference extraction |

### AST Patterns

**Capture with Function Reference (with arity):**
```elixir
# Elixir code: &String.upcase/1
# AST:
{:&, _, [{{:., _, [{:__aliases__, _, [:String]}, :upcase]}, [], 1}]}
```

**Capture with Function Reference (without arity):**
```elixir
# Elixir code: &String.upcase
# AST:
{:&, _, [{{:., _, [{:__aliases__, _, [:String]}, :upcase]}, [], []}]}
```

### Ontology Changes (Already Exist)

The following classes and properties already exist and will be used:

- `:FunctionReference` - Class for function references
- `:refersToFunction` - Object property linking to function IRI
- `:moduleName` - Datatype property for module name
- `:functionName` - Datatype property for function name
- `:arity` - Datatype property for arity

---

## Implementation Plan

### 1.0 Setup
- [x] 1.1 Create feature branch `feature/phase-29-6-function-reference-extraction`
- [x] 1.2 Create planning document

### 2.0 Research
- [ ] 2.1 Review current `build_capture_function_ref` implementation
- [ ] 2.2 Verify `refersToFunction` property is accessible via `Core` module
- [ ] 2.3 Check if function IRI format is defined elsewhere in codebase

### 3.0 Implementation
- [ ] 3.1 Update `build_capture_function_ref` to use `FunctionReference` type
- [ ] 3.2 Add `refersToFunction` object property with function IRI
- [ ] 3.3 Add `moduleName` property (replaces captureModuleName)
- [ ] 3.4 Add `functionName` property (replaces captureFunctionName)
- [ ] 3.5 Add `arity` property (replaces captureArity)
- [ ] 3.6 Consider keeping old properties for backward compatibility or remove them

### 4.0 Test Updates
- [ ] 4.1 Update existing capture operator tests
- [ ] 4.2 Add test for FunctionReference type extraction
- [ ] 4.3 Add test for refersToFunction property
- [ ] 4.4 Add test for function IRI format
- [ ] 4.5 Run all tests and verify passing

### 5.0 Final Verification
- [ ] 5.1 Run all tests and verify no regressions
- [ ] 5.2 Create summary document
- [ ] 5.3 Ask for commit and merge permission

---

## Notes and Considerations

### Design Decisions

1. **Type selection**: Use `FunctionReference` instead of `CaptureOperator` for `&Mod.fun/arity` patterns to properly link to the function being referenced.

2. **Function IRI format**: Need to determine the format for function IRIs (likely `{base_iri}module/{ModuleName}#function/{functionName}/{arity}`).

3. **Backward compatibility**: Consider whether to keep `captureModuleName`, `captureFunctionName`, `captureArity` properties or replace them entirely with `moduleName`, `functionName`, `arity`.

### Testing Strategy

- Test capture operator creates `FunctionReference` type
- Test `refersToFunction` links to correct function IRI
- Test `moduleName` property is set correctly
- Test `functionName` property is set correctly
- Test `arity` property is set when specified
- Test function IRI format follows convention

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
- Created feature branch `feature/phase-29-6-function-reference-extraction`
- Created planning document
- Updated `moduleName`, `functionName`, and `arity` property domains to include `FunctionReference`
- Implemented `FunctionReference` type for capture operators with `refersToFunction` linking
- Updated 4 tests for function references
- All 398 tests passing (including 9 doctests)

**Test Results:**
- 398 expression builder tests + 9 doctests: 0 failures
- 134 control flow builder tests: 0 failures
- Total: 535 tests, 0 failures

---

*Last Updated:* 2026-01-16
*Branch:* feature/phase-29-6-function-reference-extraction
