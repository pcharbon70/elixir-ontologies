# Phase 19.2.2: Restart Intensity Extraction

## Overview

Extract restart intensity limits (max_restarts/max_seconds) with comprehensive handling of all supervisor configuration formats.

## Current State

From Phase 19.2.1, the supervisor extractor already has:
- `max_restarts` and `max_seconds` fields in Strategy struct
- `is_default_max_restarts` and `is_default_max_seconds` tracking
- `effective_max_restarts/1` and `effective_max_seconds/1` functions
- `restart_intensity/1` calculating restarts per second ratio
- `default_max_restarts?/1` and `default_max_seconds?/1` predicates
- Extraction from `Supervisor.init/2` keyword options
- Extraction from legacy `{:ok, {{strategy, max_restarts, max_seconds}, children}}` return format

## Task Requirements (from phase-19.md)

- [x] 19.2.2.1 Extract `max_restarts: N` option (default 3) - Done in 19.2.1
- [x] 19.2.2.2 Extract `max_seconds: N` option (default 5) - Done in 19.2.1
- [x] 19.2.2.3 Calculate restart intensity ratio - Done in 19.2.1
- [ ] 19.2.2.4 Handle legacy tuple format `{strategy, max_restarts, max_seconds}`
- [x] 19.2.2.5 Track whether using defaults or explicit values - Done in 19.2.1
- [ ] 19.2.2.6 Add restart intensity tests

## Implementation Plan

Since most functionality already exists, this task focuses on:

### Step 1: Verify Legacy Tuple Format Handling
The legacy OTP supervisor format uses `{strategy, max_restarts, max_seconds}` as the first element in the `init/1` return tuple. Need to verify this is properly extracted.

### Step 2: Add RestartIntensity Struct (Optional Enhancement)
Consider adding a dedicated struct for restart intensity configuration:
- `max_restarts` - Maximum restart attempts
- `max_seconds` - Time window in seconds
- `intensity` - Calculated restarts per second
- `is_default` - Whether using all default values

### Step 3: Add Convenience Functions
- `restart_intensity_description/1` - Human-readable restart intensity description
- `high_restart_intensity?/1` - Check if intensity seems unusually high
- `within_default_intensity?/1` - Check if using default intensity settings

### Step 4: Add Comprehensive Tests
- Test legacy tuple format extraction
- Test restart intensity calculations with various values
- Test default value detection
- Test convenience functions

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add RestartIntensity struct (optional)
   - Add convenience functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add legacy tuple format tests
   - Add restart intensity tests

## Success Criteria

1. All existing tests continue to pass
2. Legacy tuple format properly extracted
3. Restart intensity calculations are comprehensive
4. Code compiles without warnings

## Progress

- [x] Step 1: Verify legacy tuple format handling (already implemented)
- [x] Step 2: Add RestartIntensity struct
- [x] Step 3: Add convenience functions
- [x] Step 4: Add comprehensive tests (22 new tests)
- [x] Quality checks pass (648 OTP tests, no warnings)
