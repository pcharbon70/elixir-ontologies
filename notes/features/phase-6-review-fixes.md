# Feature: Phase 6 Review Fixes

## Problem Statement

The Phase 6 review identified several concerns and suggestions for improvement:

1. **Missing Tests** - code_change/3, format_status/1 callbacks, map-based child specs, extract_children!/2, heir option
2. **AgentTask Module** - Should be split into agent.ex and task.ex (single responsibility)
3. **Code Duplication** - Generic use/behaviour helpers should be in Helpers module
4. **Error Handling** - Should use Helpers.format_error/2 consistently
5. **Struct Patterns** - Should follow existing patterns with :field for required fields
6. **Nested Cases** - Should use `with` statements
7. **Long Lines** - Some lines exceed 100 characters

## Solution Overview

Systematically address all review findings in order of priority.

## Implementation Plan

### High Priority

- [ ] 1. Add missing tests for `code_change/3` callback
- [ ] 2. Add missing tests for `format_status/1` callback
- [ ] 3. Add test for map-based child spec extraction
- [ ] 4. Add test for `extract_children!/2` function
- [ ] 5. Add test for ETS `heir` option

### Medium Priority

- [ ] 6. Split `agent_task.ex` into `agent.ex` and `task.ex`
- [ ] 7. Extract generic helpers to Helpers module:
  - [ ] 7.1 `use_module?/2`
  - [ ] 7.2 `behaviour_module?/2`
  - [ ] 7.3 `extract_use_options/1`
  - [ ] 7.4 `extract_location_from_meta/2`
- [ ] 8. Update error handling to use `Helpers.format_error/2`
- [ ] 9. Add nil/empty body tests for Agent/Task

### Low Priority

- [ ] 10. Standardize struct default patterns
- [ ] 11. Use `with` statements for nested cases in Supervisor
- [ ] 12. Fix long lines (>100 chars)

### Final

- [ ] 13. Run all tests and dialyzer
- [ ] 14. Update integration tests if needed

## Current Status

- **What works:** Phase 6 review fixes complete with 467 tests passing (374 OTP tests + 93 doctests)
- **What's implemented:**
  - Added 14 missing tests for callbacks and edge cases
  - Split agent_task.ex into agent.ex and task.ex with backward compatibility
  - Added generic helpers (use_module?/2, behaviour_module?/2, extract_use_options/1) to Helpers
  - Fixed map-based child spec extraction in Supervisor
  - Fixed heir option extraction in ETS
  - Fixed dialyzer warnings
- **What's deferred (low priority style improvements):**
  - Standardize struct default patterns
  - Use with statements for nested cases
  - Fix long lines (>100 chars)
  - Error handling consistency
- **How to run:** `mix test test/elixir_ontologies/extractors/otp/`

## Success Criteria

- [x] All new tests pass
- [x] No functionality broken
- [x] Dialyzer clean
- [x] Code duplication reduced (agent_task.ex split, generic helpers extracted)
- [ ] Consistent error handling (deferred - low priority)
