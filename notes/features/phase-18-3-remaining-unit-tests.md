# Phase 18.3 Remaining Unit Tests

## Overview

Implement the two remaining Section 18.3 unit tests from the Phase 18 plan:
1. Test closure-to-scope linking
2. Test SHACL validation of anonymous function RDF

## Source

From `notes/planning/extractors/phase-18.md`, Section 18.3 Unit Tests (incomplete):
- [ ] Test closure-to-scope linking
- [ ] Test SHACL validation of anonymous function RDF

## Analysis

### 1. Closure-to-Scope Linking

The Closure extractor (`lib/elixir_ontologies/extractors/closure.ex`) provides:
- `analyze_closure/1` - Detects free variables in anonymous functions
- `build_scope_chain/1` - Builds a chain of scopes from outermost to innermost
- `analyze_closure_scope/2` - Analyzes which scope provides each captured variable

The ClosureBuilder currently uses `analyze_closure/1` but doesn't generate RDF for scope information. The test should verify:
- Scope chain can be built and analyzed
- Variable sources are correctly identified
- Integration between Closure extractor and ClosureBuilder works for scope scenarios

### 2. SHACL Validation of Anonymous Function RDF

Looking at `priv/ontologies/elixir-shapes.ttl`, there are no dedicated shapes for:
- `AnonymousFunction`
- `Closure`
- `CapturedFunction`
- `PartialApplication`

However, `AnonymousFunction` is a subclass of `core:Closure` and uses `struct:FunctionClause` which does have shapes. Tests should verify:
- Generated RDF is valid (no malformed triples)
- Type triples use valid classes from the ontology
- Property triples use valid predicates
- Arity values are valid non-negative integers

## Implementation Steps

### Step 1: Add closure-to-scope linking tests
- [x] Add describe block for scope linking tests
- [x] Test scope chain building with multiple levels
- [x] Test variable source identification
- [x] Test nested closure scope scenarios
- [x] Verify tests pass

### Step 2: Add SHACL/RDF validation tests
- [x] Add describe block for RDF validation tests
- [x] Test that all subjects are valid IRIs
- [x] Test that all predicates are valid IRIs
- [x] Test that type objects reference valid ontology classes
- [x] Test that literal values have correct datatypes
- [x] Verify tests pass

### Step 3: Quality Checks
- [x] Run `mix compile --warnings-as-errors`
- [x] Run `mix credo --strict` on changed files
- [x] Run `mix format`
- [x] Run all Section 18.3 tests

## Success Criteria

1. All new tests pass
2. Tests cover closure-to-scope linking scenarios
3. Tests validate RDF triple correctness
4. No Credo issues
5. Code properly formatted

## Files to Modify

- `test/elixir_ontologies/builders/closure_builder_test.exs`
- `test/elixir_ontologies/builders/anonymous_function_builder_test.exs`
