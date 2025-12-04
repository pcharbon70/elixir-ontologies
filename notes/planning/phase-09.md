# Phase 9: Mix Tasks & CLI

This phase implements Mix tasks for command-line usage.

## 9.1 Mix Task Implementation

This section creates the `mix elixir_ontologies.analyze` task.

### 9.1.1 Analyze Task
- [ ] **Task 9.1.1 Complete**

Implement main analyze Mix task.

- [ ] 9.1.1.1 Create `lib/mix/tasks/elixir_ontologies.analyze.ex`
- [ ] 9.1.1.2 Implement `Mix.Tasks.ElixirOntologies.Analyze`
- [ ] 9.1.1.3 Parse command-line options: `--output`, `--base-iri`, `--include-source`, `--include-git`
- [ ] 9.1.1.4 Support file path argument for single-file analysis
- [ ] 9.1.1.5 Default to current project analysis
- [ ] 9.1.1.6 Output to stdout or specified file
- [ ] 9.1.1.7 Display progress during analysis
- [ ] 9.1.1.8 Handle errors gracefully with clear messages
- [ ] 9.1.1.9 Write task tests (success: 10 tests)

### 9.1.2 Update Task
- [ ] **Task 9.1.2 Complete**

Implement incremental update task.

- [ ] 9.1.2.1 Create `lib/mix/tasks/elixir_ontologies.update.ex`
- [ ] 9.1.2.2 Accept `--input` for existing graph file
- [ ] 9.1.2.3 Perform incremental analysis
- [ ] 9.1.2.4 Write updated graph to output
- [ ] 9.1.2.5 Report changes (files added, modified, removed)
- [ ] 9.1.2.6 Write update task tests (success: 6 tests)

**Section 9.1 Unit Tests:**
- [ ] Test analyze task with default options
- [ ] Test analyze task with custom output file
- [ ] Test analyze task with base IRI option
- [ ] Test update task loads existing graph
- [ ] Test update task reports changes

## 9.2 API Entry Points

This section creates clean public API functions.

### 9.2.1 Public API Module
- [ ] **Task 9.2.1 Complete**

Create high-level API in main ElixirOntologies module.

- [ ] 9.2.1.1 Update `lib/elixir_ontologies.ex` with public API
- [ ] 9.2.1.2 Implement `ElixirOntologies.analyze_file/2`
- [ ] 9.2.1.3 Implement `ElixirOntologies.analyze_project/2`
- [ ] 9.2.1.4 Implement `ElixirOntologies.update_graph/2`
- [ ] 9.2.1.5 Document all public functions with @doc
- [ ] 9.2.1.6 Add @spec for all public functions
- [ ] 9.2.1.7 Write API tests (success: 8 tests)

**Section 9.2 Unit Tests:**
- [ ] Test analyze_file/2 returns valid graph
- [ ] Test analyze_project/2 returns valid graph
- [ ] Test update_graph/2 performs incremental update
- [ ] Test options propagate correctly

## Phase 9 Integration Tests

- [ ] Test mix task end-to-end with real project
- [ ] Test output file is valid Turtle
- [ ] Test incremental update workflow
- [ ] Test error handling for invalid paths
