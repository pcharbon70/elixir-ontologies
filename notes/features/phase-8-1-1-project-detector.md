# Feature: Phase 8.1.1 - Project Detector for Mix Projects

## Problem Statement

Implement a Project Detector module that can identify Mix projects, extract project metadata from mix.exs files, detect umbrella project structures, identify dependencies, and locate source directories. This module serves as the foundation for Phase 8's whole-project analysis capabilities.

The detector must:
- Find mix.exs files by traversing up the directory tree
- Safely parse mix.exs to extract metadata without executing arbitrary code
- Detect umbrella projects by identifying the apps/ directory structure
- Extract project name, version, and dependencies
- Identify standard source directories (lib/, test/)
- Handle edge cases gracefully (missing files, invalid formats, missing fields)

## Solution Overview

Create `lib/elixir_ontologies/analyzer/project.ex` with a clean API following the established patterns from `git.ex` and `source_url.ex`:

1. **Detection Strategy**: Traverse up directory tree to find mix.exs (similar to Git.detect_repo/1)
2. **Parsing Approach**: Use safe AST analysis instead of Code.eval to prevent arbitrary code execution
3. **Umbrella Detection**: Check for apps/ directory in project root
4. **Source Discovery**: Scan standard directories (lib/, test/) with configurable options
5. **Error Handling**: Return {:ok, project} or {:error, reason} tuples consistently
6. **Struct Design**: Create Project struct with all metadata fields

## Technical Details

### File Structure

```
lib/elixir_ontologies/analyzer/
├── project.ex           # New file (main implementation)
└── path_utils.ex        # Existing (for path operations)

test/elixir_ontologies/analyzer/
└── project_test.exs     # New file (comprehensive tests)
```

### API Design

```elixir
defmodule ElixirOntologies.Analyzer.Project do
  defmodule Project do
    @enforce_keys [:path, :name]
    defstruct [
      :path,              # Absolute path to project root
      :name,              # Project name (app atom)
      :version,           # Version string
      :mix_file,          # Path to mix.exs
      umbrella?: false,   # Is this an umbrella project?
      apps: [],           # Umbrella child app paths
      deps: [],           # Dependencies list
      source_dirs: [],    # Source directories (lib/, test/)
      elixir_version: nil,# Elixir version requirement
      metadata: %{}       # Additional metadata
    ]
  end

  # Detection
  @spec detect(String.t()) :: {:ok, Project.t()} | {:error, atom()}
  def detect(path)

  @spec detect!(String.t()) :: Project.t()
  def detect!(path)

  # Helpers
  @spec find_mix_file(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def find_mix_file(path)

  @spec mix_project?(String.t()) :: boolean()
  def mix_project?(path)
end
```

## Implementation Plan

### Step 1: Create Project Struct
- [ ] Define `ElixirOntologies.Analyzer.Project.Project` struct
- [ ] Include all required fields with proper types
- [ ] Add @enforce_keys for critical fields
- [ ] Add @moduledoc and @typedoc

### Step 2: Implement mix.exs Detection
- [ ] `find_mix_file/1` - traverse up directory tree
- [ ] `mix_project?/1` - boolean check helper
- [ ] Handle symlinks, permissions errors
- [ ] Pattern match similar to `Git.find_git_root/1`

### Step 3: Implement Safe mix.exs Parsing
- [ ] `parse_mix_file/1` - read and parse AST
- [ ] `extract_project_config/1` - walk AST to find `def project`
- [ ] `extract_field/2` - safely extract literal values from AST
- [ ] Handle various AST patterns (direct values, variables, function calls)
- [ ] **Critical**: Never use Code.eval or Code.compile

### Step 4: Extract Project Metadata
- [ ] `extract_name/1` - get `:app` field
- [ ] `extract_version/1` - get `:version` field
- [ ] `extract_deps/1` - parse deps list
- [ ] `extract_elixir_version/1` - get `:elixir` field
- [ ] Handle missing fields gracefully (return nil)

### Step 5: Detect Umbrella Projects
- [ ] `detect_umbrella?/2` - check AST + filesystem
- [ ] `find_umbrella_apps/1` - scan apps/ directory
- [ ] Return list of child app paths
- [ ] Handle custom apps_path configurations

### Step 6: Identify Source Directories
- [ ] `find_source_dirs/1` - scan for lib/, test/
- [ ] For umbrella: scan apps/*/lib, apps/*/test
- [ ] Verify directories exist
- [ ] Return absolute paths

### Step 7: Implement Main detect/1 Function
- [ ] Orchestrate all helper functions
- [ ] Build complete Project struct
- [ ] Handle all error cases
- [ ] Add detect!/1 bang variant

### Step 8: Write Comprehensive Tests
- [ ] Detection tests (3 tests)
- [ ] Metadata extraction tests (3 tests)
- [ ] Umbrella detection tests (2 tests)
- [ ] Source directories tests (2 tests)
- [ ] Edge cases tests (3 tests)
- [ ] Integration tests (2 tests)

### Step 9: Add Doctests
- [ ] Add @doc examples for all public functions
- [ ] Enable doctest in test file
- [ ] Verify examples run correctly

### Step 10: Error Handling & Validation
- [ ] Validate all file paths
- [ ] Handle File.read errors
- [ ] Handle Code.string_to_quoted errors
- [ ] Return appropriate error atoms

## Testing Strategy

**Success Criteria** (minimum 10 tests):

1. **Detection Tests** (3 tests)
   - Detect project from current directory
   - Detect project from subdirectory
   - Error for non-mix directory

2. **Metadata Extraction** (3 tests)
   - Extract name and version
   - Extract dependencies list
   - Handle missing optional fields

3. **Umbrella Detection** (2 tests)
   - Detect umbrella project structure
   - Regular project returns umbrella?: false

4. **Source Directories** (2 tests)
   - Find lib/ and test/ directories
   - Find umbrella app directories

5. **Edge Cases** (3 tests)
   - Invalid mix.exs syntax
   - Mix.exs with missing fields
   - Permission errors

6. **Integration** (2 tests)
   - Full detection on current project
   - Detect!/1 raises on error

## Security Considerations

1. **Never execute mix.exs code** - Use AST parsing only
2. **Validate all file paths** - Use PathUtils to prevent directory traversal
3. **Handle malformed input** - Graceful degradation for invalid mix.exs
4. **Limit traversal depth** - Don't traverse infinite directory structures
5. **Check file permissions** - Handle permission denied errors

## Current Status

- **What works:** Planning complete
- **What's next:** Step 1 - Create Project Struct
- **How to run:** `mix test test/elixir_ontologies/analyzer/project_test.exs`

---

## Integration with Existing Code

Follows patterns from:
- `git.ex`: Struct design, directory traversal, error handling
- `source_url.ex`: Documentation, specs, doctests
- `path_utils.ex`: Path normalization and validation
