# Phase 19.3: Supervision Tree Relationships - Planning Review

**Review Date:** 2025-12-25
**Status:** Not yet implemented (all tasks pending)
**Scope:** Review of planning document for Phase 19.3

## Overview

Phase 19.3 focuses on extracting supervision tree relationships including child ordering, nested supervisor detection, and application supervisor configuration. This review analyzes the proposed plan before implementation begins.

---

## Task 19.3.1: Child Ordering Extraction

### Plan Analysis

**Proposed Work:**
- Track child position in children list
- Create ordered list of child specs
- Preserve original definition order
- Handle dynamic children markers
- Create `%ChildOrder{position: ..., child_spec: ...}` struct

### ✅ Good Practices

- **Ordering is critical for `:rest_for_one`** - The plan correctly identifies that child order matters for restart strategies
- **Dedicated struct** - Creating `%ChildOrder{}` follows established patterns from earlier phases

### 💡 Suggestions

1. **Consider enriching the struct** - The proposed `%ChildOrder{position: ..., child_spec: ...}` is minimal. Consider:
   ```elixir
   %ChildOrder{
     position: non_neg_integer(),
     child_spec: ChildSpec.t(),
     id: term(),
     is_dynamic: boolean(),
     metadata: map()
   }
   ```

2. **Integration with existing extraction** - The `extract_children/1` function already extracts children. Consider whether to:
   - Extend it to include ordering info, or
   - Create a separate `extract_ordered_children/1` function

3. **Dynamic children handling** - DynamicSupervisor children are added at runtime. The plan mentions "handle dynamic children markers" but needs clarification on what this means (placeholder? annotation?).

### ⚠️ Concerns

- **No mention of extracting from `children/0` callback** - Some supervisors define children in a separate callback rather than inline in `init/1`

---

## Task 19.3.2: Nested Supervisor Detection

### Plan Analysis

**Proposed Work:**
- Identify children that are themselves supervisors
- Track `type: :supervisor` child specs
- Link parent supervisor to child supervisor
- Build hierarchical tree structure
- Handle supervisor references across modules

### ✅ Good Practices

- **Leverages existing `type: :supervisor` field** - Already extracted in child specs
- **Cross-module linking** - Important for understanding full supervision trees

### 💡 Suggestions

1. **Distinguish detection methods**:
   - Explicit `type: :supervisor` in child spec
   - Module implements Supervisor behaviour
   - Module name ends with `Supervisor` (heuristic)

2. **Consider a tree structure representation**:
   ```elixir
   %SupervisionTree{
     root: module(),
     children: [%SupervisionNode{}],
     depth: non_neg_integer()
   }
   ```

3. **Handle circular references** - Though rare, guard against potential cycles

### ⚠️ Concerns

- **Cross-module analysis complexity** - Linking supervisors across modules requires analyzing multiple files. This may be beyond single-module extraction scope.
- **Runtime vs compile-time** - Some supervisor relationships are only determinable at runtime

---

## Task 19.3.3: Application Supervisor Extraction

### Plan Analysis

**Proposed Work:**
- Detect `Application.start/2` callback
- Extract root supervisor module
- Track application → supervisor relationship
- Handle `:mod` option in `mix.exs`
- Create `%ApplicationSupervisor{app: ..., supervisor: ...}` struct

### ✅ Good Practices

- **Links OTP application to supervision tree** - Important for understanding application structure
- **Considers `mix.exs` configuration** - Complete extraction requires both sources

### 💡 Suggestions

1. **Consider different Application patterns**:
   ```elixir
   # Pattern 1: Direct supervisor start
   def start(_type, _args) do
     MySupervisor.start_link([])
   end

   # Pattern 2: Supervisor.start_link with children
   def start(_type, _args) do
     Supervisor.start_link(children, opts)
   end

   # Pattern 3: Using Application module
   def start(_type, _args) do
     Application.start(:my_app)
   end
   ```

2. **Extract application environment** - Some supervisor config comes from `Application.get_env/3`

### ⚠️ Concerns

- **Separate extractor needed** - Application extraction is different from Supervisor extraction. Consider whether this belongs in a new `Application` extractor module.
- **Mix.exs parsing** - Parsing `mix.exs` is a different kind of extraction than parsing module code

---

## Architecture Considerations

### 🚨 Potential Blockers

1. **Cross-module analysis** - Tasks 19.3.2 and 19.3.3 require analyzing relationships across multiple files. The current extraction architecture is single-module focused. This needs architectural decision:
   - Option A: Add multi-module coordination to Pipeline/Orchestrator
   - Option B: Create a separate "linking" phase that runs after extraction
   - Option C: Defer cross-module linking to RDF layer (use SPARQL queries)

### 💡 Architectural Suggestions

1. **Two-phase approach**:
   - Phase 1: Extract local information (ordering, type detection) within each module
   - Phase 2: Link relationships across modules in a separate pass

2. **Consider scope boundaries**:
   - 19.3.1 (ordering) - Single module, fits current architecture
   - 19.3.2 (nested detection) - Local detection fits, cross-linking may not
   - 19.3.3 (application) - Needs new Application extractor

---

## Testing Strategy Review

### Proposed Unit Tests
- Test child ordering extraction
- Test nested supervisor detection
- Test application root supervisor
- Test supervision tree hierarchy
- Test cross-module supervisor references
- Test dynamic children handling
- Test `type: :supervisor` detection
- Test multi-level supervision trees

### 💡 Suggestions

1. **Add integration tests** for:
   - Real-world supervision tree patterns (Phoenix app structure)
   - Complex nested supervisors (3+ levels deep)
   - Mixed static and dynamic children

2. **Add property-based tests** for:
   - Ordering preservation
   - Tree structure validity

---

## Dependency Analysis

### Prerequisites from Earlier Phases
- ✅ 19.1.x Child Spec extraction - Complete
- ✅ 19.2.x Strategy extraction - Complete
- ✅ `child_type/1` function exists - Can detect `:worker` vs `:supervisor`
- ✅ `extract_children/1` exists - Returns child specs list

### Ready to Implement
- 19.3.1 Child Ordering - Ready (local extraction)
- 19.3.2 Nested Detection (local) - Ready
- 19.3.2 Nested Detection (cross-module) - Needs architecture decision
- 19.3.3 Application Supervisor - Needs new extractor design

---

## Recommendations

### Recommended Implementation Order

1. **19.3.1 Child Ordering** - Start here, straightforward extension
2. **19.3.2 Nested Detection (local only)** - Detect `type: :supervisor` in child specs
3. **Defer cross-module linking** - Add to Phase 19.4 or create new phase
4. **19.3.3 Application Supervisor** - Consider as separate Phase 20

### Scope Adjustments Suggested

1. **Split 19.3.2** into:
   - 19.3.2a: Local nested supervisor detection (in-module)
   - 19.3.2b: Cross-module supervisor linking (separate phase)

2. **Move 19.3.3** to Phase 20 - Application extraction is architecturally different

---

## Summary

| Task | Readiness | Recommendation |
|------|-----------|----------------|
| 19.3.1 | ✅ Ready | Implement as planned |
| 19.3.2 | ⚠️ Partial | Split local vs cross-module |
| 19.3.3 | ❌ Needs redesign | Move to separate phase |

**Overall Assessment:** Phase 19.3.1 is ready for implementation. Tasks 19.3.2 and 19.3.3 need architectural clarification before proceeding.
