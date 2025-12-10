# Phase 8: Project Analysis

This phase implements whole-project analysis: Mix project detection, multi-file analysis, and incremental updates.

## 8.1 Mix Project Detection

This section detects Mix project structure and configuration.

### 8.1.1 Project Detector
- [x] **Task 8.1.1 Complete**

Detect Mix project and extract metadata.

- [x] 8.1.1.1 Create `lib/elixir_ontologies/analyzer/project.ex`
- [x] 8.1.1.2 Implement `Project.detect/1` finding mix.exs
- [x] 8.1.1.3 Extract project name from mix.exs
- [x] 8.1.1.4 Extract version from mix.exs
- [x] 8.1.1.5 Detect umbrella projects
- [x] 8.1.1.6 Extract dependencies list
- [x] 8.1.1.7 Identify source directories (lib/, test/)
- [x] 8.1.1.8 Write project detection tests (success: 27 tests + 7 doctests)

**Section 8.1 Unit Tests:**
- [x] Test Mix project detection
- [x] Test project name extraction
- [x] Test umbrella detection
- [x] Test source directory identification

## 8.2 Multi-File Analysis

This section orchestrates analysis of multiple files into a single graph.

### 8.2.1 Project Analyzer
- [x] **Task 8.2.1 Complete**

Analyze entire project into knowledge graph.

- [x] 8.2.1.1 Create `lib/elixir_ontologies/analyzer/project_analyzer.ex`
- [x] 8.2.1.2 Implement `ProjectAnalyzer.analyze/2` with path and options
- [x] 8.2.1.3 Discover all .ex and .exs files in source directories
- [x] 8.2.1.4 Exclude test files by default (configurable)
- [x] 8.2.1.5 Analyze each file using `FileAnalyzer`
- [x] 8.2.1.6 Merge results into single graph
- [ ] 8.2.1.7 Build cross-file relationships (imports, aliases, calls) - DEFERRED
- [x] 8.2.1.8 Add project-level metadata to graph (basic statistics)
- [ ] 8.2.1.9 Report progress during analysis - DEFERRED
- [x] 8.2.1.10 Write project analyzer tests (success: 18 tests)

### 8.2.2 File Analyzer
- [x] **Task 8.2.2 Complete**

Single file analyzer composing all extractors.

- [x] 8.2.2.1 Create `lib/elixir_ontologies/analyzer/file_analyzer.ex`
- [x] 8.2.2.2 Implement `FileAnalyzer.analyze/2` with path and config
- [x] 8.2.2.3 Read and parse file
- [x] 8.2.2.4 Create SourceFile instance (Git context detection)
- [x] 8.2.2.5 Extract all modules in file
- [x] 8.2.2.6 For each module, run all extractors (functions, types, specs, attributes)
- [x] 8.2.2.7 Collect results into graph (basic structure)
- [x] 8.2.2.8 Add source locations to all elements (deferred to future enhancement)
- [x] 8.2.2.9 Return `{:ok, result}` with Result struct
- [x] 8.2.2.10 Write file analyzer tests (success: 22 tests)

**Section 8.2 Unit Tests:**
- [x] Test single file analysis produces valid graph
- [x] Test multi-module file analysis
- [x] Test project analysis discovers all files
- [x] Test project analysis merges graphs correctly
- [ ] Test progress reporting - DEFERRED

## 8.3 Incremental Updates

This section implements incremental analysis for changed files.

### 8.3.1 Change Tracker
- [x] **Task 8.3.1 Complete**

Track file changes for incremental updates.

- [x] 8.3.1.1 Create `lib/elixir_ontologies/analyzer/change_tracker.ex`
- [x] 8.3.1.2 Implement State and FileInfo structs for storing file metadata
- [x] 8.3.1.3 Implement `ChangeTracker.changed_files/2` comparing current vs stored
- [x] 8.3.1.4 Implement `ChangeTracker.new_files/2` finding added files
- [x] 8.3.1.5 Implement `ChangeTracker.deleted_files/2` finding removed files
- [x] 8.3.1.6 Write change tracker tests (success: 10 tests + 5 doctests)

### 8.3.2 Incremental Analyzer
- [ ] **Task 8.3.2 Complete**

Update graph incrementally based on changes.

- [ ] 8.3.2.1 Implement `ProjectAnalyzer.update/2` with existing graph
- [ ] 8.3.2.2 Remove triples for deleted/changed files
- [ ] 8.3.2.3 Re-analyze changed files
- [ ] 8.3.2.4 Analyze new files
- [ ] 8.3.2.5 Merge updates into graph
- [ ] 8.3.2.6 Update modification timestamps
- [ ] 8.3.2.7 Write incremental update tests (success: 10 tests)

**Section 8.3 Unit Tests:**
- [x] Test change detection for modified files
- [x] Test new file detection
- [x] Test deleted file detection
- [ ] Test incremental update removes old triples
- [ ] Test incremental update adds new triples

## Phase 8 Integration Tests

- [ ] Test full project analysis on sample project
- [ ] Test incremental update after file modification
- [ ] Test umbrella project analysis
- [ ] Test analysis with git info enabled
- [ ] Test cross-module relationship building
