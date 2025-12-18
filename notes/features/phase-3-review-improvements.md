# Feature: Phase 3 Review Improvements

## Overview

Address all findings from the Phase 3 code review: fix concerns (Dialyzer warnings, underscore variable detection, unbounded recursion, error formatting) and implement suggested improvements (centralize special forms, add property-based testing, add benchmarks).

## Findings to Address

### Concerns (Must Fix)

1. **Dialyzer Type Specification Warnings**
   - Files: `literal.ex:58`, `operator.ex:93`, `pattern.ex:115`
   - Issue: `Unknown type: Location.SourceLocation.t/0`
   - Fix: Use fully qualified type `ElixirOntologies.Analyzer.Location.SourceLocation.t()`

2. **Underscore Variable Detection**
   - File: `reference.ex:105`
   - Issue: Excludes all `_`-prefixed variables, but `_reason` etc. are valid bindings
   - Fix: Make this configurable with `:include_underscored` option

3. **Unbounded Recursion**
   - Files: `location.ex`, `pattern.ex`, `reference.ex`
   - Issue: Recursive functions lack depth limits
   - Fix: Add depth tracking using `Helpers.depth_exceeded?/1` (already exists!)

4. **Error Message Formatting Inconsistency**
   - Some modules use `Helpers.format_error/2`, others use inline `inspect`
   - Fix: Standardize on `Helpers.format_error/2` across all extractors

### Suggestions (Implement)

5. **Centralize Special Forms List**
   - Files: `reference.ex:38-46`, `pattern.ex:45-96`
   - Issue: `@special_forms` list duplicated
   - Fix: Move to `Helpers` module

6. **Property-Based Testing with StreamData**
   - Add `stream_data` dependency
   - Create property tests for edge cases

7. **Performance Benchmarks**
   - Add `benchee` dependency (dev only)
   - Create benchmark suite for common extraction patterns

## Implementation Plan

### Step 1: Fix Dialyzer Type Warnings
- [x] Update `literal.ex` to use fully qualified type
- [x] Update `operator.ex` to use fully qualified type
- [x] Update `pattern.ex` to use fully qualified type
- [x] Update `control_flow.ex` to use fully qualified type
- [x] Update `comprehension.ex` to use fully qualified type
- [x] Update `block.ex` to use fully qualified type
- [x] Update `reference.ex` to use fully qualified type
- [x] Verify Dialyzer passes with no type warnings

### Step 2: Centralize Special Forms List
- [x] Add `@special_forms` to `Helpers` module
- [x] Add `special_forms/0` function to expose the list
- [x] Update `reference.ex` to use `Helpers.special_forms()`
- [x] Update `pattern.ex` to use `Helpers.special_forms()`
- [x] Remove duplicate definitions

### Step 3: Fix Underscore Variable Detection
- [x] Add `:include_underscored` option to `Reference.variable?/2`
- [x] Update `Reference.extract/2` to pass options
- [x] Add tests for underscored variables
- [x] Document the behavior change

### Step 4: Add Depth Limits for Recursion
- [x] `location.ex:find_last_position/2` - add depth parameter
- [x] `pattern.ex:collect_bindings_from_node/1` - add depth parameter
- [x] `reference.ex:extract_bound_name/1` - add depth parameter
- [x] Return error or stop when max depth exceeded
- [x] Add tests for deeply nested structures

### Step 5: Standardize Error Message Formatting
- [x] `pattern.ex:252` - use `Helpers.format_error/2`
- [x] Review all extractors for consistent error formatting
- [x] Ensure all error messages follow pattern: "Description: #{inspect(node)}"

### Step 6: Add Property-Based Testing
- [x] Add `stream_data` to deps
- [x] Create `test/elixir_ontologies/extractors/property_test.exs`
- [x] Add generators for AST nodes
- [x] Test extractors with random valid inputs
- [x] Test extractors handle invalid inputs gracefully

### Step 7: Add Performance Benchmarks
- [x] Add `benchee` to deps (dev only)
- [x] Create `benchmarks/extractors_bench.exs`
- [x] Benchmark each extractor type
- [x] Document baseline performance

### Step 8: Also Fix Parser Dialyzer Warnings
- [x] Fix `parser.ex:412` pattern match coverage
- [x] Fix `parser.ex:416` pattern match coverage

## Success Criteria

- [x] `mix dialyzer` passes with no warnings
- [x] All existing tests pass (1402+)
- [x] Property tests pass
- [x] Benchmark suite runs successfully
- [x] Documentation updated for new options

## Files to Modify

- `lib/elixir_ontologies/extractors/helpers.ex` - Add special_forms, verify depth helpers
- `lib/elixir_ontologies/extractors/literal.ex` - Fix type
- `lib/elixir_ontologies/extractors/operator.ex` - Fix type
- `lib/elixir_ontologies/extractors/pattern.ex` - Fix type, use helpers, add depth
- `lib/elixir_ontologies/extractors/control_flow.ex` - Fix type
- `lib/elixir_ontologies/extractors/comprehension.ex` - Fix type
- `lib/elixir_ontologies/extractors/block.ex` - Fix type
- `lib/elixir_ontologies/extractors/reference.ex` - Fix type, use helpers, add depth, fix underscore
- `lib/elixir_ontologies/analyzer/location.ex` - Add depth limit
- `lib/elixir_ontologies/analyzer/parser.ex` - Fix pattern match warnings
- `mix.exs` - Add stream_data and benchee deps

## Files to Create

- `test/elixir_ontologies/extractors/property_test.exs` - Property-based tests
- `benchmarks/extractors_bench.exs` - Benchmark suite

## Status

- **Current Step:** Complete - All improvements implemented
- **Tests:** 1435 tests (363 doctests + 23 properties + 1049 tests), 0 failures
- **Dialyzer:** Passes with no type warnings
- **Benchmarks:** All extractors perform in 30-650ns range
