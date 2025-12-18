# Feature: Phase 8 Integration Tests

## Problem Statement

Create comprehensive integration tests for Phase 8 (Project Analysis) that verify end-to-end workflows for whole-project analysis, incremental updates, umbrella projects, and git integration. While individual components (Project Detector, File Analyzer, Project Analyzer, Change Tracker, Incremental Analyzer) have unit tests, integration tests are needed to verify complete workflows on realistic project structures.

The integration tests must verify:
1. Full project analysis on sample projects produces correct, complete RDF graphs
2. Incremental updates correctly handle file modifications, additions, and deletions
3. Umbrella project analysis correctly discovers and analyzes all child apps
4. Git integration properly adds provenance information to analyzed code
5. Cross-module relationships are correctly built and maintained
6. Error handling works gracefully in real-world scenarios

## Solution Overview

Create comprehensive integration test suite `test/elixir_ontologies/analyzer/phase_8_integration_test.exs` that:

1. **Full Project Analysis**: Tests complete project analysis workflow on sample projects
2. **Incremental Updates**: Tests change detection and incremental graph updates
3. **Umbrella Projects**: Tests multi-app umbrella project analysis
4. **Git Integration**: Tests source file provenance and URL generation
5. **Cross-Module Analysis**: Tests relationship building across multiple modules
6. **Error Scenarios**: Tests graceful degradation and error handling

## Test Fixtures

### Fixture Strategy

Create temporary test projects in `test/fixtures/` or using ExUnit's `tmp_dir` feature:

1. **Simple Project** - Single app with 3-5 modules
2. **Multi-Module Project** - Project with cross-module dependencies
3. **Umbrella Project** - Umbrella with 2-3 child apps
4. **Git Repository Project** - Project with git history for provenance testing

### Fixture Files

```
test/fixtures/
├── sample_project/
│   ├── mix.exs
│   ├── lib/
│   │   ├── sample.ex              # Main module
│   │   ├── sample/worker.ex       # GenServer worker
│   │   └── sample/supervisor.ex   # Supervisor
│   └── test/
│       └── sample_test.exs
│
├── multi_module/
│   ├── mix.exs
│   └── lib/
│       ├── foo.ex                 # Defines Foo module with functions
│       ├── bar.ex                 # Uses Foo via alias
│       └── baz.ex                 # Uses both Foo and Bar
│
└── umbrella_project/
    ├── mix.exs                    # Umbrella config
    └── apps/
        ├── app_one/
        │   ├── mix.exs
        │   └── lib/app_one.ex
        └── app_two/
            ├── mix.exs
            └── lib/app_two.ex
```

## Technical Details

### Test Categories

#### 1. Full Project Analysis Tests (6 tests)

**Test: analyze simple project successfully**
- Analyze sample_project with 3 modules
- Verify project metadata (name, version)
- Verify all modules are found (Sample, Sample.Worker, Sample.Supervisor)
- Verify graph contains expected triples (module definitions, functions)
- Verify file results contain all analyzed files
- Verify no errors in result

**Test: analyze project excludes tests by default**
- Analyze sample_project
- Verify test files are not in file results
- Verify exclude_tests: false includes test files

**Test: analyze project handles missing files gracefully**
- Create project with invalid file reference
- Verify analysis continues (continue_on_error: true)
- Verify errors are collected in result.errors

**Test: analyze project produces valid RDF graph**
- Analyze sample_project
- Verify graph is valid RDF (no duplicate statements)
- Verify namespaces are correct
- Verify module IRIs are properly formed

**Test: analyze project with OTP patterns**
- Analyze project with GenServer and Supervisor
- Verify OTP patterns are detected (use GenServer, use Supervisor)
- Verify callbacks are extracted (init/1, handle_call/3, etc.)
- Verify supervision strategies are captured

**Test: analyze project metadata is comprehensive**
- Analyze sample_project
- Verify metadata contains file_count, triple_count
- Verify metadata contains file_paths list
- Verify metadata contains analysis_state (ChangeTracker.State)
- Verify metadata contains last_analysis timestamp

#### 2. Incremental Update Tests (7 tests)

**Test: incremental update with no changes**
- Analyze project, then immediately update
- Verify changes.unchanged contains all files
- Verify changes.changed, changes.new, changes.deleted are empty
- Verify graph is identical (or functionally equivalent)
- Verify update is fast (< 100ms)

**Test: incremental update with modified file**
- Analyze project
- Modify one source file (change function body)
- Run incremental update
- Verify changes.changed contains modified file
- Verify file is re-analyzed
- Verify graph is updated with new content
- Verify other files' triples remain unchanged

**Test: incremental update with new file**
- Analyze project
- Add new source file
- Run incremental update
- Verify changes.new contains new file
- Verify new file is analyzed
- Verify new file's triples are added to graph
- Verify existing files' triples remain unchanged

**Test: incremental update with deleted file**
- Analyze project
- Delete one source file
- Run incremental update
- Verify changes.deleted contains deleted file
- Verify deleted file's triples are removed from graph
- Verify other files' triples remain unchanged

**Test: incremental update with mixed changes**
- Analyze project
- Modify one file, add one file, delete one file
- Run incremental update
- Verify all change types are detected correctly
- Verify graph reflects all changes
- Verify unchanged files' triples remain

**Test: incremental update falls back when state missing**
- Analyze project
- Remove analysis_state from result.metadata
- Run incremental update
- Verify falls back to full analysis
- Verify result is correct (no errors)

**Test: incremental update performance**
- Analyze project with 20 files
- Modify 1 file
- Run incremental update
- Verify update time < full analysis time / 5
- Verify only 1 file is re-analyzed

#### 3. Umbrella Project Tests (5 tests)

**Test: detect umbrella project structure**
- Use umbrella_project fixture
- Verify project.umbrella? is true
- Verify project.apps contains child app paths
- Verify apps/ directory is detected

**Test: analyze umbrella project finds all apps**
- Analyze umbrella_project
- Verify files from all child apps are analyzed
- Verify apps/app_one/lib/app_one.ex is found
- Verify apps/app_two/lib/app_two.ex is found

**Test: umbrella project modules have correct IRIs**
- Analyze umbrella_project
- Verify AppOne module IRI is correct
- Verify AppTwo module IRI is correct
- Verify IRIs use app-specific namespaces

**Test: incremental update works on umbrella projects**
- Analyze umbrella_project
- Modify file in one child app
- Run incremental update
- Verify only modified app's file is re-analyzed
- Verify other app's files remain unchanged

**Test: umbrella project metadata includes all apps**
- Analyze umbrella_project
- Verify metadata includes apps information
- Verify file counts are correct across all apps

#### 4. Git Integration Tests (5 tests)

**Test: analysis includes git info when available**
- Create temp project with git repo
- Initialize git, create commit
- Analyze project with include_git_info: true
- Verify source files have repository info
- Verify commit SHA is captured
- Verify file URLs are generated

**Test: analysis without git info**
- Analyze project with include_git_info: false
- Verify source files don't have repository info
- Verify analysis still succeeds

**Test: git provenance in RDF graph**
- Analyze git-enabled project
- Verify graph contains provenance triples (PROV-O)
- Verify source URLs are included
- Verify commit information is linked to files

**Test: git info for specific file revisions**
- Create git repo with multiple commits
- Modify file, commit
- Analyze project
- Verify latest commit info is used
- Verify file modification timestamps are correct

**Test: graceful degradation without git**
- Analyze non-git project
- Verify analysis succeeds
- Verify no git-related errors
- Verify source files still have file paths

#### 5. Cross-Module Relationship Tests (4 tests)

**Note**: Cross-module relationship building is deferred in Phase 8.2.1. These tests verify the current behavior and prepare for future implementation.

**Test: multiple modules in single file**
- Create file with 2 modules (defmodule Foo, defmodule Bar)
- Analyze file
- Verify both modules are extracted
- Verify both have separate IRIs
- Verify both are in the graph

**Test: modules across multiple files**
- Analyze multi_module project
- Verify all modules are found (Foo, Bar, Baz)
- Verify graph contains all module definitions
- Verify file-to-module mappings are correct

**Test: alias usage detection** (future enhancement)
- Analyze file with alias
- Verify alias usage is detected in AST
- (Implementation deferred: relationship building)

**Test: import/require detection** (future enhancement)
- Analyze file with import/require
- Verify import/require is detected in AST
- (Implementation deferred: relationship building)

#### 6. Error Handling Tests (5 tests)

**Test: malformed file in project**
- Create project with syntax error in one file
- Analyze with continue_on_error: true
- Verify analysis continues
- Verify error is collected in result.errors
- Verify other files are analyzed successfully

**Test: missing file permissions**
- Create project with unreadable file (if possible)
- Analyze project
- Verify file read error is collected
- Verify other files are analyzed

**Test: invalid mix.exs**
- Create project with malformed mix.exs
- Attempt analysis
- Verify appropriate error is returned

**Test: empty project**
- Create project with no source files
- Analyze project
- Verify returns error or empty result (no crash)

**Test: deeply nested directory structure**
- Create project with deeply nested lib/ structure
- Verify all files are discovered
- Verify relative paths are correct

## Implementation Plan

### Step 1: Create Test File Structure
- [ ] Create `test/elixir_ontologies/analyzer/phase_8_integration_test.exs`
- [ ] Set up test module with async: false (uses temporary files)
- [ ] Add module documentation
- [ ] Import necessary aliases

### Step 2: Create Test Fixtures
- [ ] Create fixture helper functions for generating temp projects
- [ ] Implement `create_sample_project/1` - creates basic project in tmp dir
- [ ] Implement `create_multi_module_project/1` - creates project with multiple modules
- [ ] Implement `create_umbrella_project/1` - creates umbrella structure
- [ ] Implement `create_git_project/1` - creates project with git repo
- [ ] Add cleanup helpers (on_exit callbacks)

### Step 3: Implement Full Project Analysis Tests
- [ ] Test analyze simple project successfully
- [ ] Test analyze project excludes tests by default
- [ ] Test analyze project handles missing files gracefully
- [ ] Test analyze project produces valid RDF graph
- [ ] Test analyze project with OTP patterns
- [ ] Test analyze project metadata is comprehensive

### Step 4: Implement Incremental Update Tests
- [ ] Test incremental update with no changes
- [ ] Test incremental update with modified file
- [ ] Test incremental update with new file
- [ ] Test incremental update with deleted file
- [ ] Test incremental update with mixed changes
- [ ] Test incremental update falls back when state missing
- [ ] Test incremental update performance

### Step 5: Implement Umbrella Project Tests
- [ ] Test detect umbrella project structure
- [ ] Test analyze umbrella project finds all apps
- [ ] Test umbrella project modules have correct IRIs
- [ ] Test incremental update works on umbrella projects
- [ ] Test umbrella project metadata includes all apps

### Step 6: Implement Git Integration Tests
- [ ] Test analysis includes git info when available
- [ ] Test analysis without git info
- [ ] Test git provenance in RDF graph
- [ ] Test git info for specific file revisions
- [ ] Test graceful degradation without git

### Step 7: Implement Cross-Module Tests
- [ ] Test multiple modules in single file
- [ ] Test modules across multiple files
- [ ] Test alias usage detection (stub for future)
- [ ] Test import/require detection (stub for future)

### Step 8: Implement Error Handling Tests
- [ ] Test malformed file in project
- [ ] Test missing file permissions
- [ ] Test invalid mix.exs
- [ ] Test empty project
- [ ] Test deeply nested directory structure

### Step 9: Verification and Documentation
- [ ] Run all tests, verify they pass
- [ ] Run dialyzer, verify no errors
- [ ] Add doctests where appropriate
- [ ] Update phase-08.md integration test checklist
- [ ] Document any limitations or known issues

### Step 10: Final Review
- [ ] Verify test coverage is comprehensive
- [ ] Verify test fixtures are realistic
- [ ] Verify error messages are clear
- [ ] Verify test performance is acceptable
- [ ] Update this document with final results

## Success Criteria

- [ ] All 32+ integration tests pass
- [ ] Tests cover all 5 categories (full analysis, incremental, umbrella, git, cross-module, errors)
- [ ] Test fixtures represent realistic project structures
- [ ] Dialyzer clean (0 errors)
- [ ] All checklist items in phase-08.md are verified
- [ ] Tests run in reasonable time (< 30 seconds for full suite)
- [ ] Tests are deterministic (no flaky tests)
- [ ] Error handling is comprehensive
- [ ] Documentation is complete with examples

## Test Coverage Summary

| Category | Tests | Description |
|----------|-------|-------------|
| Full Project Analysis | 6 | Complete project analysis workflows |
| Incremental Updates | 7 | Change detection and graph updates |
| Umbrella Projects | 5 | Multi-app project analysis |
| Git Integration | 5 | Provenance and source URLs |
| Cross-Module Relations | 4 | Module dependencies (partial) |
| Error Handling | 5 | Graceful degradation scenarios |

**Total: 32 integration tests**

## Helper Functions

### Test Fixture Helpers

```elixir
# Create temporary sample project
defp create_sample_project(tmp_dir) do
  # Create mix.exs
  mix_content = """
  defmodule Sample.MixProject do
    use Mix.Project
    def project do
      [app: :sample, version: "0.1.0"]
    end
  end
  """

  # Create lib/sample.ex
  sample_content = """
  defmodule Sample do
    @moduledoc "Sample module"
    def hello, do: :world
  end
  """

  # Create lib/sample/worker.ex (GenServer)
  worker_content = """
  defmodule Sample.Worker do
    use GenServer
    def init(state), do: {:ok, state}
  end
  """

  # Write files
  File.mkdir_p!(Path.join(tmp_dir, "lib/sample"))
  File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
  File.write!(Path.join(tmp_dir, "lib/sample.ex"), sample_content)
  File.write!(Path.join(tmp_dir, "lib/sample/worker.ex"), worker_content)

  tmp_dir
end

# Modify file content (for incremental tests)
defp modify_file(path, new_content) do
  File.write!(path, new_content)
  # Sleep to ensure mtime changes
  :timer.sleep(10)
end

# Initialize git repository
defp init_git_repo(path) do
  System.cmd("git", ["init"], cd: path)
  System.cmd("git", ["config", "user.email", "test@example.com"], cd: path)
  System.cmd("git", ["config", "user.name", "Test User"], cd: path)
  System.cmd("git", ["add", "."], cd: path)
  System.cmd("git", ["commit", "-m", "Initial commit"], cd: path)
  path
end
```

## Current Status

- **What works:** Planning complete, ready for implementation
- **What's next:** Step 1 - Create test file structure
- **How to run:** `mix test test/elixir_ontologies/analyzer/phase_8_integration_test.exs`

## Notes and Considerations

### Temporary Files
- Use `ExUnit.Callbacks.tmp_dir/1` for temporary project creation
- Clean up in `on_exit` callbacks
- Ensure tests don't interfere with each other (use unique names)

### Git Testing
- Tests that require git should check if git is available
- Skip git tests if git is not installed (use `@tag :git`)
- Clean up git state in `on_exit`

### Performance
- Incremental update tests should verify performance gains
- Full project analysis should complete in < 5s for small projects
- Consider using smaller fixtures for faster test runs

### Cross-Module Relationships
- Phase 8.2.1 deferred cross-module relationship building
- Tests should verify current behavior (modules found, no relationships)
- Prepare tests for future enhancement (mark as pending or skip)

### Umbrella Projects
- Umbrella tests require careful setup
- Verify apps/ directory structure is correct
- Ensure child apps have valid mix.exs files

### Determinism
- File modification tests need careful timestamp handling
- Use `:timer.sleep/1` to ensure mtime changes are detected
- Avoid race conditions in temporary file operations

## Integration with Existing Tests

This integration test suite complements existing unit tests:
- `project_test.exs` - Unit tests for Project.detect/1
- `project_analyzer_test.exs` - Unit tests for ProjectAnalyzer.analyze/2 and update/3
- `file_analyzer_test.exs` - Unit tests for FileAnalyzer.analyze/2
- `change_tracker_test.exs` - Unit tests for ChangeTracker
- `phase_7_integration_test.exs` - Integration tests for Git integration

This suite focuses on end-to-end workflows that exercise multiple components together.

## Current Status

✅ **COMPLETE** - All integration tests implemented and passing

**What works:**
- 32 comprehensive integration tests covering all Phase 8 functionality
- Full project analysis tests (6 tests) - simple projects, OTP patterns, multi-module
- Incremental update tests (7 tests) - modifications, additions, deletions, mixed changes, performance
- Umbrella project tests (5 tests) - detection, discovery, file paths, metadata, incremental updates
- Git integration tests (5 tests) - provenance, graceful degradation, umbrella+git
- Cross-module tests (4 tests) - multiple modules, graph consistency, incremental preservation
- Error handling tests (5 tests) - malformed files, empty projects, permissions, missing projects
- All 2,536 tests passing (911 doctests, 29 properties, 2,536 tests, 0 failures)

**What's implemented:**
- ✅ Integration test file with 32 tests
- ✅ Helper functions for creating test fixtures (simple, multi-module, umbrella projects)
- ✅ Git repository initialization helpers
- ✅ Temporary project creation and cleanup
- ✅ Comprehensive assertions for project analysis, graphs, metadata
- ✅ Performance validation tests
- ✅ Error scenario coverage

**How to run:**
```bash
# Run integration tests only
mix test test/elixir_ontologies/analyzer/phase_8_integration_test.exs

# Run all tests
mix test
```

**Test Coverage by Category:**
1. Full Project Analysis: 6 tests
2. Incremental Updates: 7 tests
3. Umbrella Projects: 5 tests
4. Git Integration: 5 tests (tagged :requires_git)
5. Cross-Module Relationships: 4 tests
6. Error Handling: 5 tests

## Future Enhancements

1. **Performance Benchmarks**: Add benchee tests for large projects
2. **Cross-Module Relationship Building**: Implement relationship extraction
3. **Parallel Analysis**: Test parallel file analysis
4. **Watch Mode**: Test continuous analysis with file watching
5. **Custom Extractors**: Test pluggable extractor architecture
6. **RDF Export**: Test graph serialization to various formats
7. **SHACL Validation**: Test graph validation against ontology shapes
8. **Query Tests**: Test SPARQL queries against generated graphs
