# Phase 8: Project Analysis

This phase implements whole-project analysis: Mix project detection, multi-file analysis, and incremental updates.

## 8.1 Mix Project Detection

This section detects Mix project structure and configuration.

### 8.1.1 Project Detector
- [ ] **Task 8.1.1 Complete**

Detect Mix project and extract metadata.

- [ ] 8.1.1.1 Create `lib/elixir_ontologies/analyzer/project.ex`
- [ ] 8.1.1.2 Implement `Project.detect/1` finding mix.exs
- [ ] 8.1.1.3 Extract project name from mix.exs
- [ ] 8.1.1.4 Extract version from mix.exs
- [ ] 8.1.1.5 Detect umbrella projects
- [ ] 8.1.1.6 Extract dependencies list
- [ ] 8.1.1.7 Identify source directories (lib/, test/)
- [ ] 8.1.1.8 Write project detection tests (success: 10 tests)

**Section 8.1 Unit Tests:**
- [ ] Test Mix project detection
- [ ] Test project name extraction
- [ ] Test umbrella detection
- [ ] Test source directory identification

## 8.2 Multi-File Analysis

This section orchestrates analysis of multiple files into a single graph.

### 8.2.1 Project Analyzer
- [ ] **Task 8.2.1 Complete**

Analyze entire project into knowledge graph.

- [ ] 8.2.1.1 Create `lib/elixir_ontologies/analyzer/project_analyzer.ex`
- [ ] 8.2.1.2 Implement `ProjectAnalyzer.analyze/2` with path and options
- [ ] 8.2.1.3 Discover all .ex and .exs files in source directories
- [ ] 8.2.1.4 Exclude test files by default (configurable)
- [ ] 8.2.1.5 Analyze each file using `FileAnalyzer`
- [ ] 8.2.1.6 Merge results into single graph
- [ ] 8.2.1.7 Build cross-file relationships (imports, aliases, calls)
- [ ] 8.2.1.8 Add project-level metadata to graph
- [ ] 8.2.1.9 Report progress during analysis
- [ ] 8.2.1.10 Write project analyzer tests (success: 12 tests)

### 8.2.2 File Analyzer
- [ ] **Task 8.2.2 Complete**

Single file analyzer composing all extractors.

- [ ] 8.2.2.1 Create `lib/elixir_ontologies/analyzer/file_analyzer.ex`
- [ ] 8.2.2.2 Implement `FileAnalyzer.analyze/2` with path and config
- [ ] 8.2.2.3 Read and parse file
- [ ] 8.2.2.4 Create SourceFile instance
- [ ] 8.2.2.5 Extract all modules in file
- [ ] 8.2.2.6 For each module, run all extractors
- [ ] 8.2.2.7 Collect results into graph
- [ ] 8.2.2.8 Add source locations to all elements
- [ ] 8.2.2.9 Return `{:ok, graph}` or `{:error, reason}`
- [ ] 8.2.2.10 Write file analyzer tests (success: 10 tests)

**Section 8.2 Unit Tests:**
- [ ] Test single file analysis produces valid graph
- [ ] Test multi-module file analysis
- [ ] Test project analysis discovers all files
- [ ] Test project analysis merges graphs correctly
- [ ] Test progress reporting

## 8.3 Incremental Updates

This section implements incremental analysis for changed files.

### 8.3.1 Change Tracker
- [ ] **Task 8.3.1 Complete**

Track file changes for incremental updates.

- [ ] 8.3.1.1 Create `lib/elixir_ontologies/analyzer/change_tracker.ex`
- [ ] 8.3.1.2 Store file modification times in graph metadata
- [ ] 8.3.1.3 Implement `ChangeTracker.changed_files/2` comparing current vs stored
- [ ] 8.3.1.4 Implement `ChangeTracker.new_files/2` finding added files
- [ ] 8.3.1.5 Implement `ChangeTracker.deleted_files/2` finding removed files
- [ ] 8.3.1.6 Write change tracker tests (success: 8 tests)

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
- [ ] Test change detection for modified files
- [ ] Test new file detection
- [ ] Test deleted file detection
- [ ] Test incremental update removes old triples
- [ ] Test incremental update adds new triples

## Phase 8 Integration Tests

- [ ] Test full project analysis on sample project
- [ ] Test incremental update after file modification
- [ ] Test umbrella project analysis
- [ ] Test analysis with git info enabled
- [ ] Test cross-module relationship building
