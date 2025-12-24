# Phase 19.1.2: Start Function Extraction

## Overview

Enhance start function extraction from child specifications to track function arity and support additional shorthand formats.

## Current State

The supervisor extractor already has:
- `StartSpec` struct with fields: module, function, args, metadata
- Extraction of `{Module, :start_link, [args]}` form from map/tuple child specs
- Module-only shorthand handling (implies `start_link/1`)
- Basic integration with ChildSpec extraction

## Task Requirements (from phase-19.md)

- [ ] 19.1.2.1 Define `%StartSpec{module: ..., function: ..., args: [...]}` struct
- [ ] 19.1.2.2 Extract `start: {Module, :start_link, [args]}` form
- [ ] 19.1.2.3 Extract `start: {Module, :start_link, args}` shorthand
- [ ] 19.1.2.4 Handle module-only shorthand (implies start_link/1)
- [ ] 19.1.2.5 Track start function arity and arguments
- [ ] 19.1.2.6 Add start function extraction tests

## Gap Analysis

After reviewing the current implementation, most of 19.1.2 was already implemented in 19.1.1:

| Subtask | Status | Notes |
|---------|--------|-------|
| 19.1.2.1 | Done | StartSpec exists at lines 95-121 |
| 19.1.2.2 | Done | extract_start_spec handles this |
| 19.1.2.3 | Partial | Need shorthand where args is not wrapped in list |
| 19.1.2.4 | Done | Module-only parsing at lines 1292-1316 |
| 19.1.2.5 | Missing | Need arity field in StartSpec |
| 19.1.2.6 | Partial | Basic tests exist, need enhancement |

## Implementation Plan

### Step 1: Add Arity Field to StartSpec
- Add `arity` field to `%StartSpec{}` struct
- Update type definition
- Calculate arity from args length

### Step 2: Handle Args Shorthand Format
- Support `{Module, :fun, arg}` where arg is not a list
- These should normalize to `args: [arg]` with arity 1

### Step 3: Add Arity Calculation Helper
- Create `calculate_arity/1` for consistent arity tracking
- Handle edge cases (nil args, empty args)

### Step 4: Add Convenience Functions
- `start_function_arity/1` - Get arity from StartSpec
- `start_function_mfa/1` - Get {module, function, arity} tuple

### Step 5: Add Comprehensive Tests
- Test arity tracking for all formats
- Test args shorthand normalization
- Test MFA tuple extraction
- Test edge cases

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add arity field to StartSpec
   - Update extract_start_spec for arity calculation
   - Add convenience functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add arity tracking tests
   - Add shorthand format tests
   - Add convenience function tests

## Success Criteria

1. StartSpec includes arity field
2. All start function formats correctly calculate arity
3. Args shorthand (non-list) is normalized
4. Convenience functions work correctly
5. All existing tests continue to pass
6. New tests cover all requirements
7. Code compiles without warnings

## Progress

- [x] Step 1: Add arity field to StartSpec
- [x] Step 2: Handle args shorthand format (already supported via normalize_args)
- [x] Step 3: Add arity calculation helper (start_function_arity/1)
- [x] Step 4: Add convenience functions (start_function_mfa/1, child_start_mfa/1)
- [x] Step 5: Add comprehensive tests (17 new tests)
- [x] Quality checks pass (503 OTP tests, no warnings)
