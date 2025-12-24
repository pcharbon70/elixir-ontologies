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
- [ ] **Task 19.2.3 Pending**

Extract DynamicSupervisor-specific configuration.

- [ ] 19.2.3.1 Detect DynamicSupervisor modules
- [ ] 19.2.3.2 Extract `strategy: :one_for_one` (always for DynamicSupervisor)
- [ ] 19.2.3.3 Extract `extra_arguments: [...]` option
- [ ] 19.2.3.4 Extract `max_children: N` option
- [ ] 19.2.3.5 Track that children are added dynamically
- [ ] 19.2.3.6 Add DynamicSupervisor tests

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
- [ ] **Task 19.3.1 Pending**

Extract the order of children in supervision tree (important for rest_for_one).

- [ ] 19.3.1.1 Track child position in children list
- [ ] 19.3.1.2 Create ordered list of child specs
- [ ] 19.3.1.3 Preserve original definition order
- [ ] 19.3.1.4 Handle dynamic children markers
- [ ] 19.3.1.5 Create `%ChildOrder{position: ..., child_spec: ...}` struct
- [ ] 19.3.1.6 Add child ordering tests

### 19.3.2 Nested Supervisor Detection
- [ ] **Task 19.3.2 Pending**

Detect and track nested supervisor relationships in the tree.

- [ ] 19.3.2.1 Identify children that are themselves supervisors
- [ ] 19.3.2.2 Track `type: :supervisor` child specs
- [ ] 19.3.2.3 Link parent supervisor to child supervisor
- [ ] 19.3.2.4 Build hierarchical tree structure
- [ ] 19.3.2.5 Handle supervisor references across modules
- [ ] 19.3.2.6 Add nested supervisor tests

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
- [ ] **Task 19.4.1 Pending**

Generate RDF triples for child specifications.

- [ ] 19.4.1.1 Update `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
- [ ] 19.4.1.2 Implement `build_child_spec/3` generating child spec IRI
- [ ] 19.4.1.3 Generate `rdf:type otp:ChildSpec` triple
- [ ] 19.4.1.4 Generate `otp:hasChildId` with id value
- [ ] 19.4.1.5 Generate `otp:hasStartFunction` linking to start spec
- [ ] 19.4.1.6 Add child spec builder tests

### 19.4.2 Strategy Builder
- [ ] **Task 19.4.2 Pending**

Generate RDF triples for supervision strategies.

- [ ] 19.4.2.1 Implement `build_supervision_strategy/3` generating strategy IRI
- [ ] 19.4.2.2 Generate `rdf:type otp:SupervisionStrategy` triple
- [ ] 19.4.2.3 Generate `otp:strategyType` with strategy enum value
- [ ] 19.4.2.4 Generate `otp:maxRestarts` with restart limit
- [ ] 19.4.2.5 Generate `otp:maxSeconds` with time window
- [ ] 19.4.2.6 Add strategy builder tests

### 19.4.3 Supervision Tree Builder
- [ ] **Task 19.4.3 Pending**

Generate RDF triples for supervision tree relationships.

- [ ] 19.4.3.1 Implement `build_supervision_tree/3` generating tree relationships
- [ ] 19.4.3.2 Generate `otp:supervises` linking supervisor to children
- [ ] 19.4.3.3 Generate `otp:supervisedBy` inverse relationship
- [ ] 19.4.3.4 Generate `otp:childPosition` with ordering
- [ ] 19.4.3.5 Generate `otp:isRootSupervisor` for application supervisors
- [ ] 19.4.3.6 Add supervision tree builder tests

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

- [ ] **Phase 19 Integration Tests** (12+ tests)

- [ ] Test complete supervisor extraction for complex supervision tree
- [ ] Test multi-level supervision tree RDF generation
- [ ] Test DynamicSupervisor extraction
- [ ] Test PartitionSupervisor extraction
- [ ] Test supervisor RDF validates against shapes
- [ ] Test Pipeline integration with supervisor extractors
- [ ] Test Orchestrator coordinates supervisor builders
- [ ] Test child spec completeness
- [ ] Test strategy extraction accuracy
- [ ] Test application supervisor detection
- [ ] Test backward compatibility with existing supervisor extraction
- [ ] Test error handling for malformed child specs
