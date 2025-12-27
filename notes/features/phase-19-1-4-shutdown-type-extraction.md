# Phase 19.1.4: Shutdown and Type Extraction

## Overview

Implement structured extraction of shutdown strategy and child type from child specifications with dedicated structs.

## Current State

The supervisor extractor already has:
- `shutdown_type` type: `non_neg_integer() | :infinity | :brutal_kill`
- `child_type` type: `:worker | :supervisor`
- `shutdown` and `type` fields in ChildSpec struct
- Basic extraction from map/tuple/legacy formats

## Task Requirements (from phase-19.md)

- [ ] 19.1.4.1 Implement `extract_shutdown/1` for shutdown options
- [ ] 19.1.4.2 Define `%ShutdownSpec{type: :brutal_kill|:timeout|:infinity, value: ...}` struct
- [ ] 19.1.4.3 Extract `shutdown: :brutal_kill`
- [ ] 19.1.4.4 Extract `shutdown: timeout_ms` (integer)
- [ ] 19.1.4.5 Extract `type: :worker | :supervisor` option
- [ ] 19.1.4.6 Add shutdown/type extraction tests

## Implementation Plan

### Step 1: Define ShutdownSpec Struct
Create `%ShutdownSpec{}` struct with:
- `type` - The shutdown type (`:brutal_kill`, `:timeout`, `:infinity`)
- `value` - The timeout value in ms (nil for brutal_kill/infinity)
- `is_default` - Whether this is the default value
- `metadata` - Additional information

### Step 2: Add extract_shutdown/1 Function
- Takes a ChildSpec and returns a ShutdownSpec
- Categorizes shutdown into type categories
- Tracks whether value was explicitly set

### Step 3: Add Child Type Functions
- `extract_child_type/1` - Get structured child type info
- `worker?/1`, `supervisor_child?/1` - Type check helpers

### Step 4: Add Convenience Functions
- `shutdown_timeout/1` - Get timeout value or nil
- `shutdown_description/1` - Human-readable description

### Step 5: Add Comprehensive Tests
- Test all shutdown types
- Test default detection
- Test child type extraction
- Test extraction from different formats

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add ShutdownSpec struct
   - Add extract_shutdown/1
   - Add child type functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add ShutdownSpec tests
   - Add extraction tests

## Success Criteria

1. ShutdownSpec struct captures shutdown configuration
2. All shutdown types correctly extracted and categorized
3. Child type extraction working
4. All existing tests continue to pass
5. New tests cover all requirements
6. Code compiles without warnings

## Progress

- [x] Step 1: Define ShutdownSpec struct
- [x] Step 2: Add extract_shutdown/1
- [x] Step 3: Add child type functions (worker?/1, supervisor_child?/1, child_type/1)
- [x] Step 4: Add convenience functions (shutdown_timeout/1, shutdown_description/1, child_type_description/1)
- [x] Step 5: Add comprehensive tests (27 new tests)
- [x] Quality checks pass (577 OTP tests, no warnings)
