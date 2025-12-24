# Phase 19.1.3: Restart Strategy Extraction

## Overview

Implement structured extraction of restart strategy options from child specifications with a dedicated RestartStrategy struct.

## Current State

The supervisor extractor already has:
- `restart_type` type: `:permanent | :temporary | :transient`
- `restart` field in ChildSpec struct (defaults to `:permanent`)
- `permanent?/1`, `temporary?/1`, `transient?/1` helper functions
- Basic extraction of restart atom from map/tuple formats

## Task Requirements (from phase-19.md)

- [ ] 19.1.3.1 Implement `extract_restart_strategy/1` for restart options
- [ ] 19.1.3.2 Define `%RestartStrategy{type: :permanent|:temporary|:transient}` struct
- [ ] 19.1.3.3 Extract `restart: :permanent` (default)
- [ ] 19.1.3.4 Extract `restart: :temporary` (never restart)
- [ ] 19.1.3.5 Extract `restart: :transient` (restart only on abnormal exit)
- [ ] 19.1.3.6 Add restart strategy tests

## Implementation Plan

### Step 1: Define RestartStrategy Struct
Create `%RestartStrategy{}` struct with:
- `type` - The restart type atom (:permanent, :temporary, :transient)
- `is_default` - Whether this is the default value
- `metadata` - Additional information

### Step 2: Add extract_restart_strategy/1 Function
- Takes a ChildSpec and returns a RestartStrategy
- Tracks whether the value was explicitly set or defaulted

### Step 3: Add Convenience Functions
- `restart_strategy_type/1` - Get type from RestartStrategy
- `default_restart?/1` - Check if using default restart

### Step 4: Add Comprehensive Tests
- Test all three restart types
- Test default detection
- Test extraction from different child spec formats

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add RestartStrategy struct
   - Add extract_restart_strategy/1
   - Add convenience functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add RestartStrategy tests
   - Add extraction tests

## Success Criteria

1. RestartStrategy struct captures restart configuration
2. All restart types correctly extracted
3. Default vs explicit restart tracked
4. All existing tests continue to pass
5. New tests cover all requirements
6. Code compiles without warnings

## Progress

- [x] Step 1: Define RestartStrategy struct
- [x] Step 2: Add extract_restart_strategy/1
- [x] Step 3: Add convenience functions (restart_strategy_type/1, default_restart?/1, restart_description/1)
- [x] Step 4: Add comprehensive tests (22 new tests)
- [x] Quality checks pass (534 OTP tests, no warnings)
