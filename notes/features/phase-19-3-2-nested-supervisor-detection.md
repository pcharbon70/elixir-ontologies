# Phase 19.3.2: Nested Supervisor Detection

## Overview

Detect and track nested supervisor relationships within a single module. This phase focuses on local (in-module) detection only, deferring cross-module linking to a separate phase per review recommendations.

## Review Recommendations Addressed

From `notes/reviews/phase-19-3-planning-review.md`:

1. **Local detection only** - Focus on in-module detection; cross-module linking deferred
2. **Detection methods** - Use multiple methods to identify nested supervisors:
   - Explicit `type: :supervisor` in child spec
   - Module name heuristics (ends with `Supervisor`)
   - Module behaviour detection (if available in spec)
3. **Guard against cycles** - Though rare, handle potential circular references
4. **Tree structure representation** - Consider `%NestedSupervisor{}` struct

## Task Requirements (from phase-19.md)

- [ ] 19.3.2.1 Identify children that are themselves supervisors
- [ ] 19.3.2.2 Track `type: :supervisor` child specs
- [ ] 19.3.2.3 Link parent supervisor to child supervisor
- [ ] 19.3.2.4 Build hierarchical tree structure
- [ ] 19.3.2.5 Handle supervisor references across modules (LOCAL ONLY - defer cross-module)
- [ ] 19.3.2.6 Add nested supervisor tests

## Scope Clarification

Per review recommendations, this phase is split:
- **19.3.2a (this phase)**: Local nested supervisor detection within a single module
- **19.3.2b (future phase)**: Cross-module supervisor linking

## Implementation Plan

### Step 1: Define NestedSupervisor Struct

Create `%NestedSupervisor{}` struct to represent detected nested supervisors:
- `child_spec` - The ChildSpec that is a supervisor
- `module` - The module name of the nested supervisor
- `position` - Position in children list (from ChildOrder)
- `detection_method` - How it was detected (:explicit_type, :name_heuristic, :behaviour_hint)
- `is_confirmed` - Whether detection is definitive (explicit type) or heuristic
- `metadata` - Additional information

### Step 2: Add Detection Functions

1. `extract_nested_supervisors/1` - Main entry point, returns list of NestedSupervisor structs
2. `nested_supervisor?/1` - Predicate to check if ChildSpec is a nested supervisor
3. `supervisor_module?/1` - Check if module name suggests it's a supervisor

### Step 3: Add Analysis Functions

1. `nested_supervisor_count/1` - Count nested supervisors in children
2. `supervisor_children/1` - Filter children to only supervisors
3. `worker_children/1` - Filter children to only workers
4. `supervision_depth/1` - Estimate tree depth (1 if no nested supervisors)
5. `has_nested_supervisors?/1` - Boolean check

### Step 4: Add Description Functions

1. `nested_supervisor_summary/1` - Human-readable summary
2. `supervision_tree_description/1` - Describe the local tree structure

### Step 5: Add Comprehensive Tests

- Test explicit `type: :supervisor` detection
- Test module name heuristic detection
- Test mixed workers and supervisors
- Test empty children list
- Test all analysis functions
- Test edge cases

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add NestedSupervisor struct
   - Add detection and analysis functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add nested supervisor detection tests

## Detection Methods

### Method 1: Explicit Type (Definitive)
```elixir
%{id: MySupervisor, start: {...}, type: :supervisor}
```

### Method 2: Module Name Heuristic (Suggestive)
```elixir
{MySupervisor, []}  # Module name ends with "Supervisor"
{MyAppSupervisor, []}
```

### Method 3: Known Modules (Future Enhancement)
In the future, cross-module linking could confirm supervisors by checking if they implement Supervisor behaviour.

## Success Criteria

1. All existing tests continue to pass
2. Explicit `type: :supervisor` children detected correctly
3. Module name heuristics work for common patterns
4. Detection method correctly identifies definitive vs heuristic
5. Code compiles without warnings

## Progress

- [x] Step 1: Define NestedSupervisor struct
- [x] Step 2: Add detection functions
- [x] Step 3: Add analysis functions
- [x] Step 4: Add description functions
- [x] Step 5: Add comprehensive tests (46 tests)
- [x] Quality checks pass

## Implementation Summary

### NestedSupervisor Struct
Added `%NestedSupervisor{}` struct with:
- `child_spec` - The ChildSpec that is a supervisor
- `module` - The module name of the nested supervisor
- `position` - Position in children list (0-based)
- `detection_method` - How detected (`:explicit_type`, `:name_heuristic`, `:behaviour_hint`)
- `is_confirmed` - Whether detection is definitive (true) or heuristic (false)
- `metadata` - Additional information

### Functions Added
1. `extract_nested_supervisors/1` - Main entry point, returns `{:ok, [NestedSupervisor.t()]}`
2. `extract_nested_supervisors!/1` - Bang variant
3. `nested_supervisor?/1` - Check if ChildOrder is a nested supervisor
4. `supervisor_module?/1` - Check if module name suggests supervisor
5. `nested_supervisor_count/1` - Count nested supervisors
6. `supervisor_children/1` - Filter to only supervisors
7. `worker_children/1` - Filter to only workers
8. `has_nested_supervisors?/1` - Boolean check
9. `supervision_depth/1` - Estimate tree depth
10. `nested_supervisor_summary/1` - Human-readable summary
11. `supervision_tree_description/1` - Describe tree structure
12. `nested_detection_method/1` - Get detection method from NestedSupervisor
13. `detection_method_description/1` - Human-readable detection method description

### Tests Added
46 tests covering:
- NestedSupervisor struct
- nested_supervisor?/1 predicate
- supervisor_module?/1 heuristic
- extract_nested_supervisors/1 main function
- nested_supervisor_count/1
- supervisor_children/1 and worker_children/1
- has_nested_supervisors?/1
- supervision_depth/1
- nested_supervisor_summary/1
- supervision_tree_description/1
- nested_detection_method/1
- detection_method_description/1
- Integration tests from AST
