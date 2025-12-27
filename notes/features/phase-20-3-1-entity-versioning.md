# Phase 20.3.1: Entity Versioning

## Overview

Model code elements as PROV-O entities with version relationships. This module tracks how modules and functions evolve across commits, implementing the `prov:wasDerivedFrom` relationship chain.

## Requirements

From phase-20.md task 20.3.1:

- [x] 20.3.1.1 Create `lib/elixir_ontologies/extractors/evolution/entity_version.ex`
- [x] 20.3.1.2 Define `%EntityVersion{entity: ..., version: ..., commit: ..., previous: ...}` struct
- [x] 20.3.1.3 Track module versions across commits
- [x] 20.3.1.4 Track function versions across commits
- [x] 20.3.1.5 Implement `prov:wasDerivedFrom` relationships
- [x] 20.3.1.6 Add entity versioning tests (40 tests)

## Design

### PROV-O Alignment

The elixir-evolution.ttl ontology defines key concepts:

- `evolution:CodeVersion` - A versioned snapshot of code (subclass of `prov:Entity`)
- `evolution:ModuleVersion` - A specific version of a module
- `evolution:FunctionVersion` - A specific version of a function
- `evolution:wasRevisionOf` - Links versions (subproperty of `prov:wasRevisionOf`)
- `evolution:hasPreviousVersion` - Functional property for version chain
- `evolution:wasGeneratedBy` - Links version to creating activity

### Struct Design

```elixir
defmodule EntityVersion do
  @type entity_type :: :module | :function | :type | :macro

  @type t :: %__MODULE__{
    entity_type: entity_type(),
    entity_name: String.t(),
    version_id: String.t(),
    commit_sha: String.t(),
    previous_version: String.t() | nil,
    content_hash: String.t(),
    file_path: String.t(),
    line_range: {pos_integer(), pos_integer()} | nil,
    metadata: map()
  }
end

defmodule ModuleVersion do
  @type t :: %__MODULE__{
    module_name: String.t(),
    version_id: String.t(),
    commit_sha: String.t(),
    previous_version: String.t() | nil,
    file_path: String.t(),
    content_hash: String.t(),
    functions: [String.t()],
    metadata: map()
  }
end

defmodule FunctionVersion do
  @type t :: %__MODULE__{
    module_name: String.t(),
    function_name: atom(),
    arity: non_neg_integer(),
    version_id: String.t(),
    commit_sha: String.t(),
    previous_version: String.t() | nil,
    content_hash: String.t(),
    line_range: {pos_integer(), pos_integer()},
    metadata: map()
  }
end

defmodule Derivation do
  @type derivation_type :: :revision | :quotation | :primary_source

  @type t :: %__MODULE__{
    derived_entity: String.t(),
    source_entity: String.t(),
    derivation_type: derivation_type(),
    activity: String.t() | nil,
    metadata: map()
  }
end
```

### Version Identification

Version IDs are computed as: `{entity_name}@{commit_sha[0..6]}`

For example:
- `MyApp.UserController@abc123d`
- `MyApp.UserController.create/1@abc123d`

### Content Hashing

To detect actual changes (not just commits that touched the file), we compute a content hash of the entity's source code. Two versions with the same content hash are considered identical even if in different commits.

### Implementation Approach

1. Use `git show {commit}:{file}` to get file content at a commit
2. Parse the file to extract module/function boundaries
3. Hash the extracted content for change detection
4. Build version chains by walking commit history

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/entity_version.ex`
- [x] Define EntityVersion base struct
- [x] Define ModuleVersion struct
- [x] Define FunctionVersion struct
- [x] Define Derivation struct
- [x] Add type specs and moduledoc

### Step 2: Content Extraction
- [x] Implement `extract_file_at_commit/3` using git show
- [x] Implement `compute_content_hash/1` for change detection
- [x] Implement `extract_module_source/2` to get module source code
- [x] Implement `extract_function_source/3` to get function source code

### Step 3: Module Version Tracking
- [x] Implement `extract_module_version/3` for single commit
- [x] Implement `track_module_versions/3` across commit range
- [x] Build version chain with previous version links
- [x] Handle module renames

### Step 4: Function Version Tracking
- [x] Implement `extract_function_version/4` for single commit
- [x] Implement `track_function_versions/4` across commit range
- [x] Build version chain with previous version links
- [x] Handle function renames and arity changes

### Step 5: Derivation Relationships
- [x] Implement `build_derivation/3` for version pairs
- [x] Implement `build_derivation_chain/2` for version list
- [x] Support revision, quotation, and primary_source types

### Step 6: Testing
- [x] Add module version extraction tests
- [x] Add function version extraction tests
- [x] Add version chain building tests
- [x] Add derivation relationship tests
- [x] Add content hash change detection tests

## Success Criteria

1. All 6 subtasks completed
2. Can extract module versions from commits
3. Can extract function versions from commits
4. Version chains correctly linked
5. Content-based change detection works
6. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/entity_version.ex`
- `test/elixir_ontologies/extractors/evolution/entity_version_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
