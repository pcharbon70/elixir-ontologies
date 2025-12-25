# Phase 19: Supervisor Child Specifications

This phase completes the supervisor support by implementing detailed extraction and building of child specifications. While the Supervisor extractor detects supervisor modules, it does not fully extract child specs, restart strategies, or supervision tree relationships. The elixir-otp.ttl ontology defines ChildSpec, SupervisionStrategy, RestartStrategy, and related classes that this phase will populate.

## 19.1 Child Specification Extraction

This section implements detailed extraction of child specifications from supervisor modules.

### 19.1.1 Child Spec Structure Extraction
- [x] **Task 19.1.1 Complete**

Extract child specification maps/tuples from supervisor init/1 callbacks.

- [x] 19.1.1.1 Update `lib/elixir_ontologies/extractors/otp/supervisor.ex` for child spec extraction
- [x] 19.1.1.2 Define `%ChildSpec{id: ..., start: ..., restart: ..., shutdown: ..., type: ..., modules: [...]}` struct
- [x] 19.1.1.3 Extract child spec from map syntax `%{id: ..., start: ...}`
- [x] 19.1.1.4 Extract child spec from module-based syntax `{Module, arg}`
- [x] 19.1.1.5 Extract child spec from full tuple syntax `{id, start, restart, shutdown, type, modules}`
- [x] 19.1.1.6 Add child spec structure tests

### 19.1.2 Start Function Extraction
- [x] **Task 19.1.2 Complete**

Extract the start function specification from child specs.

- [x] 19.1.2.1 Define `%StartSpec{module: ..., function: ..., args: [...]}` struct
- [x] 19.1.2.2 Extract `start: {Module, :start_link, [args]}` form
- [x] 19.1.2.3 Extract `start: {Module, :start_link, args}` shorthand
- [x] 19.1.2.4 Handle module-only shorthand (implies start_link/1)
- [x] 19.1.2.5 Track start function arity and arguments
- [x] 19.1.2.6 Add start function extraction tests

### 19.1.3 Restart Strategy Extraction
- [x] **Task 19.1.3 Complete**

Extract restart strategy options from child specs.

- [x] 19.1.3.1 Implement `extract_restart_strategy/1` for restart options
- [x] 19.1.3.2 Define `%RestartStrategy{type: :permanent|:temporary|:transient}` struct
- [x] 19.1.3.3 Extract `restart: :permanent` (default)
- [x] 19.1.3.4 Extract `restart: :temporary` (never restart)
- [x] 19.1.3.5 Extract `restart: :transient` (restart only on abnormal exit)
- [x] 19.1.3.6 Add restart strategy tests

### 19.1.4 Shutdown and Type Extraction
- [x] **Task 19.1.4 Complete**

Extract shutdown strategy and child type from child specs.

- [x] 19.1.4.1 Implement `extract_shutdown/1` for shutdown options
- [x] 19.1.4.2 Define `%ShutdownSpec{type: :brutal_kill|:timeout|:infinity, value: ...}` struct
- [x] 19.1.4.3 Extract `shutdown: :brutal_kill`
- [x] 19.1.4.4 Extract `shutdown: timeout_ms` (integer)
- [x] 19.1.4.5 Extract `type: :worker | :supervisor` option
- [x] 19.1.4.6 Add shutdown/type extraction tests

**Section 19.1 Unit Tests:**
- [ ] Test child spec map extraction
- [ ] Test child spec tuple extraction
- [ ] Test module-based child spec shorthand
- [ ] Test start function extraction
- [ ] Test restart strategy extraction
- [ ] Test shutdown option extraction
- [ ] Test child type extraction
- [ ] Test default value handling

## 19.2 Supervision Strategy Extraction

This section extracts supervisor-level strategies that control how the supervisor handles child failures.

### 19.2.1 Strategy Type Extraction
- [x] **Task 19.2.1 Complete**

Extract the supervision strategy type from supervisor init/1.

- [x] 19.2.1.1 Implement `extract_supervision_strategy/1` from init return value
- [x] 19.2.1.2 Define `%SupervisionStrategy{type: ..., max_restarts: ..., max_seconds: ...}` struct
- [x] 19.2.1.3 Extract `:one_for_one` strategy
- [x] 19.2.1.4 Extract `:one_for_all` strategy
- [x] 19.2.1.5 Extract `:rest_for_one` strategy
- [x] 19.2.1.6 Add strategy type tests

### 19.2.2 Restart Intensity Extraction
- [x] **Task 19.2.2 Complete**

Extract restart intensity limits (max_restarts/max_seconds).

- [x] 19.2.2.1 Extract `max_restarts: N` option (default 3)
- [x] 19.2.2.2 Extract `max_seconds: N` option (default 5)
- [x] 19.2.2.3 Calculate restart intensity ratio
- [x] 19.2.2.4 Handle legacy tuple format `{strategy, max_restarts, max_seconds}`
- [x] 19.2.2.5 Track whether using defaults or explicit values
- [x] 19.2.2.6 Add restart intensity tests

### 19.2.3 DynamicSupervisor Strategy
- [x] **Task 19.2.3 Complete**

Extract DynamicSupervisor-specific configuration.

- [x] 19.2.3.1 Detect DynamicSupervisor modules
- [x] 19.2.3.2 Extract `strategy: :one_for_one` (always for DynamicSupervisor)
- [x] 19.2.3.3 Extract `extra_arguments: [...]` option
- [x] 19.2.3.4 Extract `max_children: N` option
- [x] 19.2.3.5 Track that children are added dynamically
- [x] 19.2.3.6 Add DynamicSupervisor tests

**Section 19.2 Unit Tests:**
- [ ] Test one_for_one strategy extraction
- [ ] Test one_for_all strategy extraction
- [ ] Test rest_for_one strategy extraction
- [ ] Test max_restarts extraction
- [ ] Test max_seconds extraction
- [ ] Test DynamicSupervisor detection
- [ ] Test legacy tuple format handling
- [ ] Test default value detection

## 19.3 Supervision Tree Relationships

This section builds the supervision tree structure showing parent-child relationships.

### 19.3.1 Child Ordering Extraction
- [x] **Task 19.3.1 Complete**

Extract the order of children in supervision tree (important for rest_for_one).

- [x] 19.3.1.1 Track child position in children list
- [x] 19.3.1.2 Create ordered list of child specs
- [x] 19.3.1.3 Preserve original definition order
- [x] 19.3.1.4 Handle dynamic children markers
- [x] 19.3.1.5 Create `%ChildOrder{position: ..., child_spec: ...}` struct (enriched with id, is_dynamic, metadata)
- [x] 19.3.1.6 Add child ordering tests (38 tests)

### 19.3.2 Nested Supervisor Detection
- [x] **Task 19.3.2 Complete** (local detection only; cross-module linking deferred)

Detect and track nested supervisor relationships in the tree.

- [x] 19.3.2.1 Identify children that are themselves supervisors
- [x] 19.3.2.2 Track `type: :supervisor` child specs
- [x] 19.3.2.3 Link parent supervisor to child supervisor (local only)
- [x] 19.3.2.4 Build hierarchical tree structure (NestedSupervisor struct)
- [x] 19.3.2.5 Handle supervisor references across modules (LOCAL ONLY - cross-module deferred)
- [x] 19.3.2.6 Add nested supervisor tests (46 tests)

### 19.3.3 Application Supervisor Extraction
- [ ] **Task 19.3.3 Pending**

Extract application root supervisor configuration.

- [ ] 19.3.3.1 Detect Application.start/2 callback
- [ ] 19.3.3.2 Extract root supervisor module
- [ ] 19.3.3.3 Track application → supervisor relationship
- [ ] 19.3.3.4 Handle :mod option in mix.exs application config
- [ ] 19.3.3.5 Create `%ApplicationSupervisor{app: ..., supervisor: ...}` struct
- [ ] 19.3.3.6 Add application supervisor tests

**Section 19.3 Unit Tests:**
- [ ] Test child ordering extraction
- [ ] Test nested supervisor detection
- [ ] Test application root supervisor
- [ ] Test supervision tree hierarchy
- [ ] Test cross-module supervisor references
- [ ] Test dynamic children handling
- [ ] Test type: :supervisor detection
- [ ] Test multi-level supervision trees

## 19.4 Supervisor Builder Enhancement

This section enhances the SupervisorBuilder to generate complete RDF for all supervisor details.

### 19.4.1 Child Spec Builder
- [x] **Task 19.4.1 Complete**

Generate RDF triples for child specifications.

- [x] 19.4.1.1 Update `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
- [x] 19.4.1.2 Implement `build_child_spec/4` generating child spec IRI (with index parameter)
- [x] 19.4.1.3 Generate `rdf:type otp:ChildSpec` triple
- [x] 19.4.1.4 Generate `otp:childId` with id value
- [x] 19.4.1.5 Generate `otp:startModule`, `otp:startFunction` for start spec
- [x] 19.4.1.6 Generate `otp:hasRestartStrategy` and `otp:hasChildType` triples
- [x] 19.4.1.7 Implement `build_child_specs/3` for multiple children
- [x] 19.4.1.8 Add `for_child_spec/3` to IRI module
- [x] 19.4.1.9 Add child spec builder tests (16 tests)

### 19.4.2 Strategy Builder
- [x] **Task 19.4.2 Complete**

Generate RDF triples for supervision strategies.

- [x] 19.4.2.1 Implement `build_supervision_strategy/3` generating strategy IRI
- [x] 19.4.2.2 Generate `otp:hasStrategy` linking to predefined individual (OneForOne, OneForAll, RestForOne)
- [x] 19.4.2.3 Generate `otp:maxRestarts` with restart limit (on supervisor per ontology)
- [x] 19.4.2.4 Generate `otp:maxSeconds` with time window (on supervisor per ontology)
- [x] 19.4.2.5 Handle OTP default values (max_restarts=3, max_seconds=5)
- [x] 19.4.2.6 Add strategy builder tests (12 tests)

### 19.4.3 Supervision Tree Builder
- [x] **Task 19.4.3 Complete**

Generate RDF triples for supervision tree relationships.

- [x] 19.4.3.1 Implement `build_supervision_tree/4` generating tree relationships
- [x] 19.4.3.2 Generate `otp:supervises` linking supervisor to child modules
- [x] 19.4.3.3 Generate `otp:supervisedBy` inverse relationship
- [x] 19.4.3.4 Generate `otp:hasChildren` with rdf:List for ordering
- [x] 19.4.3.5 Generate `otp:rootSupervisor` and `otp:partOfTree` for application supervisors
- [x] 19.4.3.6 Add `for_supervision_tree/2` to IRI module
- [x] 19.4.3.7 Add `build_supervision_relationships/3` for supervises/supervisedBy
- [x] 19.4.3.8 Add `build_ordered_children/3` for rdf:List ordering
- [x] 19.4.3.9 Add `build_root_supervisor/3` for root supervisor triples
- [x] 19.4.3.10 Add supervision tree builder tests (17 tests)

**Section 19.4 Unit Tests:**
- [ ] Test child spec RDF generation
- [ ] Test restart strategy RDF
- [ ] Test shutdown option RDF
- [ ] Test supervision strategy RDF
- [ ] Test supervision tree relationship RDF
- [ ] Test child ordering RDF
- [ ] Test nested supervisor linking
- [ ] Test SHACL validation of supervisor RDF

## Phase 19 Integration Tests

- [x] **Phase 19 Integration Tests** (32 tests)

- [x] Test complete supervisor extraction for complex supervision tree
- [x] Test multi-level supervision tree RDF generation
- [x] Test DynamicSupervisor extraction
- [N/A] Test PartitionSupervisor extraction (not yet implemented in extractor)
- [x] Test supervisor RDF validates against shapes (via builder tests)
- [x] Test Pipeline integration with supervisor extractors
- [x] Test Orchestrator coordinates supervisor builders
- [x] Test child spec completeness
- [x] Test strategy extraction accuracy
- [N/A] Test application supervisor detection (deferred to Phase 20)
- [x] Test backward compatibility with existing supervisor extraction
- [x] Test error handling for malformed child specs
- [x] Test shutdown strategy extraction (brutal_kill, infinity, timeout)

## Phase 19 Review Improvements

- [x] Add @moduletag :integration for test filtering
- [x] Fix IRI sanitization for child IDs (added escape_name)
- [x] Replace assert != nil with pattern match assertions
- [x] Use Enum.any?/2 for existence checks
- [x] Extract helper functions (parse_module_body, build_test_context, build_test_iri)
- [x] Add shutdown strategy test
