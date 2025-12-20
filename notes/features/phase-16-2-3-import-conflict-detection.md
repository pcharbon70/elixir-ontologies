# Phase 16.2.3: Import Conflict Detection

## Overview

Implement detection of potential import conflicts where multiple imports bring the same function into scope.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.2.3.1 Implement `detect_import_conflicts/1` analyzing all imports
- 16.2.3.2 Track function names imported from each module
- 16.2.3.3 Identify overlapping function definitions
- 16.2.3.4 Create `%ImportConflict{function: ..., modules: [...]}` struct
- 16.2.3.5 Report conflicts with their locations
- 16.2.3.6 Add conflict detection tests

## Understanding Import Conflicts

Import conflicts occur when:
1. Two full imports (`import A` and `import B`) both export a function with the same name/arity
2. An import with `only:` specifies a function that's also imported from another module
3. Type-based imports (`:functions`, `:macros`) overlap with other imports

Note: For static analysis, we can only detect *potential* conflicts since we don't have access to what functions each module actually exports. However, we can detect:
- Explicit conflicts: Two `only:` clauses specify the same function/arity
- Potential conflicts: Two full imports where we cannot rule out overlap

## Technical Design

### ImportConflict Struct

```elixir
defmodule ImportConflict do
  @type t :: %__MODULE__{
          function: {atom(), non_neg_integer()},
          imports: [ImportDirective.t()],
          conflict_type: :explicit | :potential,
          location: SourceLocation.t() | nil
        }

  defstruct [:function, imports: [], conflict_type: :potential, location: nil]
end
```

### Functions to Implement

```elixir
# Detect conflicts in a list of import directives
@spec detect_import_conflicts([ImportDirective.t()]) :: [ImportConflict.t()]

# Get explicitly imported functions from directive
@spec explicit_imports(ImportDirective.t()) :: [{atom(), non_neg_integer()}]
```

## Implementation Plan

### Step 1: Add ImportConflict Struct
- [x] Define ImportConflict struct in import.ex
- [x] Add typespec

### Step 2: Implement explicit_imports/1
- [x] Extract function list from `only:` option
- [x] Return empty for full imports and type-based imports

### Step 3: Implement detect_import_conflicts/1
- [x] Collect all explicitly imported functions with their sources
- [x] Group by function name/arity
- [x] Report conflicts where same function imported from multiple modules

### Step 4: Write Tests
- [x] Test no conflicts with disjoint imports
- [x] Test explicit conflict detection
- [x] Test no false positives for full imports
- [x] Test conflict with location information

## Success Criteria

- [x] ImportConflict struct defined with proper typespec
- [x] `detect_import_conflicts/1` identifies explicit conflicts
- [x] Location information preserved in conflicts
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
