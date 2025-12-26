# Phase 20: Evolution & Provenance (PROV-O)

This phase implements the evolution and provenance layer of the ontology, integrating with W3C PROV-O to track code changes, version history, and attribution. The elixir-evolution.ttl ontology defines classes for commits, development activities, agents, and version tracking that enable understanding how code evolves over time. This is the capstone phase that connects static code analysis to its temporal dimension.

## 20.1 Version Control Integration

This section implements extraction of version control information from Git repositories, linking code elements to their version history.

### 20.1.1 Commit Information Extraction
- [x] **Task 20.1.1 Complete**

Extract commit metadata from Git for code provenance.

- [x] 20.1.1.1 Create `lib/elixir_ontologies/extractors/evolution/commit.ex`
- [x] 20.1.1.2 Define `%Commit{sha: ..., message: ..., author: ..., timestamp: ..., parents: [...]}` struct
- [x] 20.1.1.3 Implement `extract_commit/1` using git log for single commit
- [x] 20.1.1.4 Extract commit SHA (full 40-character)
- [x] 20.1.1.5 Extract commit message (subject and body)
- [x] 20.1.1.6 Add commit extraction tests (46 tests)

### 20.1.2 Author and Committer Extraction
- [x] **Task 20.1.2 Complete**

Extract author and committer information from commits.

- [x] 20.1.2.1 Define `%Developer{name: ..., email: ..., commits: [...]}` struct
- [x] 20.1.2.2 Extract commit author (name and email)
- [x] 20.1.2.3 Extract commit committer (may differ from author)
- [x] 20.1.2.4 Track author timestamps
- [x] 20.1.2.5 Build developer identity across commits
- [x] 20.1.2.6 Add author extraction tests (32 tests)

### 20.1.3 File History Extraction
- [x] **Task 20.1.3 Complete**

Extract the history of changes to individual files.

- [x] 20.1.3.1 Implement `extract_file_history/1` using git log for file
- [x] 20.1.3.2 Track commits that modified each file
- [x] 20.1.3.3 Track file renames and moves
- [x] 20.1.3.4 Build chronological change list
- [x] 20.1.3.5 Create `%FileHistory{path: ..., commits: [...], renames: [...]}` struct
- [x] 20.1.3.6 Add file history tests (30 tests)

### 20.1.4 Blame Information Extraction
- [x] **Task 20.1.4 Complete**

Extract line-level attribution using git blame.

- [x] 20.1.4.1 Implement `extract_blame/1` using git blame
- [x] 20.1.4.2 Define `%BlameInfo{line: ..., commit: ..., author: ..., timestamp: ...}` struct
- [x] 20.1.4.3 Extract commit attribution for each line
- [x] 20.1.4.4 Track line age (time since last change)
- [x] 20.1.4.5 Handle lines not yet committed (working copy)
- [x] 20.1.4.6 Add blame extraction tests (34 tests)

**Section 20.1 Unit Tests:**
- [ ] Test commit SHA extraction
- [ ] Test commit message parsing
- [ ] Test author/committer extraction
- [ ] Test file history extraction
- [ ] Test rename tracking
- [ ] Test blame information extraction
- [ ] Test uncommitted changes handling
- [ ] Test merge commit parent tracking

## 20.2 Development Activity Tracking

This section implements tracking of development activities as PROV-O activities, connecting code changes to their context.

### 20.2.1 Activity Classification
- [x] **Task 20.2.1 Complete**

Classify commits into development activity types based on commit messages and changes.

- [x] 20.2.1.1 Create `lib/elixir_ontologies/extractors/evolution/activity.ex`
- [x] 20.2.1.2 Define `%DevelopmentActivity{type: ..., commit: ..., entities: [...], agents: [...]}` struct
- [x] 20.2.1.3 Implement heuristic classification (bug fix, feature, refactor, etc.)
- [x] 20.2.1.4 Parse conventional commit format (feat:, fix:, refactor:, etc.)
- [x] 20.2.1.5 Track activity scope (files and modules affected)
- [x] 20.2.1.6 Add activity classification tests (45 tests)

### 20.2.2 Refactoring Detection
- [x] **Task 20.2.2 Complete**

Detect and classify refactoring activities from code changes.

- [x] 20.2.2.1 Define `%Refactoring{type: ..., source: ..., target: ..., commit: ...}` struct
- [x] 20.2.2.2 Detect function extraction refactoring
- [x] 20.2.2.3 Detect module extraction refactoring
- [x] 20.2.2.4 Detect rename refactoring (function, module, variable)
- [x] 20.2.2.5 Detect inline refactoring
- [x] 20.2.2.6 Add refactoring detection tests (25 tests)

### 20.2.3 Deprecation Tracking
- [x] **Task 20.2.3 Complete**

Track deprecation activities and their timeline.

- [x] 20.2.3.1 Define `%Deprecation{element: ..., deprecated_in: ..., removed_in: ..., replacement: ...}` struct
- [x] 20.2.3.2 Detect @deprecated attribute additions
- [x] 20.2.3.3 Track deprecation announcement commits
- [x] 20.2.3.4 Track removal commits
- [x] 20.2.3.5 Extract suggested replacement from deprecation message
- [x] 20.2.3.6 Add deprecation tracking tests (29 tests)

### 20.2.4 Feature and Bug Fix Tracking
- [x] **Task 20.2.4 Complete**

Track feature additions and bug fixes as distinct activities.

- [x] 20.2.4.1 Define `%FeatureAddition{name: ..., commit: ..., modules: [...]}` struct
- [x] 20.2.4.2 Define `%BugFix{description: ..., commit: ..., affected_functions: [...]}` struct
- [x] 20.2.4.3 Parse issue references from commit messages (#123, GH-456)
- [x] 20.2.4.4 Link activities to external issue trackers
- [x] 20.2.4.5 Track scope of changes per activity
- [x] 20.2.4.6 Add feature/bug fix tracking tests (40 tests)

**Section 20.2 Unit Tests:**
- [ ] Test activity type classification
- [ ] Test conventional commit parsing
- [ ] Test refactoring detection
- [ ] Test deprecation tracking
- [ ] Test feature addition detection
- [ ] Test bug fix detection
- [ ] Test issue reference parsing
- [ ] Test activity scope calculation

## 20.3 PROV-O Integration

This section implements full PROV-O integration, modeling code evolution using standard provenance ontology patterns.

### 20.3.1 Entity Versioning
- [x] **Task 20.3.1 Complete**

Model code elements as PROV-O entities with version relationships.

- [x] 20.3.1.1 Create `lib/elixir_ontologies/extractors/evolution/entity_version.ex`
- [x] 20.3.1.2 Define `%EntityVersion{entity: ..., version: ..., commit: ..., previous: ...}` struct
- [x] 20.3.1.3 Track module versions across commits
- [x] 20.3.1.4 Track function versions across commits
- [x] 20.3.1.5 Implement `prov:wasDerivedFrom` relationships
- [x] 20.3.1.6 Add entity versioning tests (40 tests)

### 20.3.2 Activity Modeling
- [x] **Task 20.3.2 Complete**

Model development activities using PROV-O Activity class.

- [x] 20.3.2.1 Implement `prov:Activity` for commits and development activities
- [x] 20.3.2.2 Track `prov:startedAtTime` and `prov:endedAtTime`
- [x] 20.3.2.3 Implement `prov:used` for entities read by activity
- [x] 20.3.2.4 Implement `prov:generated` for entities created by activity
- [x] 20.3.2.5 Implement `prov:wasInformedBy` for activity chains
- [x] 20.3.2.6 Add activity modeling tests (43 tests)

### 20.3.3 Agent Attribution
- [x] **Task 20.3.3 Complete**

Model developers, bots, and CI systems as PROV-O agents.

- [x] 20.3.3.1 Create `lib/elixir_ontologies/extractors/evolution/agent.ex`
- [x] 20.3.3.2 Define `%Agent{type: :developer|:bot|:ci|:llm, identity: ...}` struct
- [x] 20.3.3.3 Implement `prov:wasAssociatedWith` for activity-agent links
- [x] 20.3.3.4 Implement `prov:wasAttributedTo` for entity-agent links
- [x] 20.3.3.5 Detect bot commits (dependabot, renovate, etc.)
- [x] 20.3.3.6 Add agent attribution tests (70 tests)

### 20.3.4 Delegation and Responsibility
- [x] **Task 20.3.4 Complete**

Model delegation relationships between agents (team leads, code owners).

- [x] 20.3.4.1 Define `%Delegation{delegator: ..., delegate: ..., activity: ...}` struct
- [x] 20.3.4.2 Implement `prov:actedOnBehalfOf` relationships
- [x] 20.3.4.3 Track code ownership from CODEOWNERS file
- [x] 20.3.4.4 Model team membership if available
- [x] 20.3.4.5 Track review approval chains
- [x] 20.3.4.6 Add delegation tests (60 tests)

**Section 20.3 Unit Tests:**
- [ ] Test entity version tracking
- [ ] Test prov:wasDerivedFrom generation
- [ ] Test activity time tracking
- [ ] Test prov:used and prov:generated relationships
- [ ] Test agent type detection
- [ ] Test bot commit detection
- [ ] Test delegation relationship modeling
- [ ] Test CODEOWNERS parsing

## 20.4 Evolution Builder

This section implements RDF builders for all evolution and provenance constructs.

### 20.4.1 Commit Builder
- [x] **Task 20.4.1 Complete**

Generate RDF triples for commits and their metadata.

- [x] 20.4.1.1 Create `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- [x] 20.4.1.2 Implement `build_commit/3` generating commit IRI
- [x] 20.4.1.3 Generate `rdf:type evolution:Commit` triple
- [x] 20.4.1.4 Generate `evolution:commitHash` with SHA
- [x] 20.4.1.5 Generate `evolution:commitMessage` with message
- [x] 20.4.1.6 Add commit builder tests (31 tests)

### 20.4.2 Activity Builder
- [x] **Task 20.4.2 Complete**

Generate RDF triples for development activities.

- [x] 20.4.2.1 Create `lib/elixir_ontologies/builders/evolution/activity_builder.ex`
- [x] 20.4.2.2 Implement `build_activity/3` generating activity IRI
- [x] 20.4.2.3 Generate `rdf:type prov:Activity` and subclass triple
- [x] 20.4.2.4 Generate `prov:startedAtTime` and `prov:endedAtTime`
- [x] 20.4.2.5 Generate `prov:used` and `prov:generated` relationships
- [x] 20.4.2.6 Add activity builder tests (44 tests)

### 20.4.3 Agent Builder
- [x] **Task 20.4.3 Complete**

Generate RDF triples for development agents.

- [x] 20.4.3.1 Create `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- [x] 20.4.3.2 Implement `build_agent/3` generating agent IRI
- [x] 20.4.3.3 Generate `rdf:type prov:Agent` and subclass triple
- [x] 20.4.3.4 Generate `evolution:developerName/botName` and `evolution:developerEmail`
- [x] 20.4.3.5 Generate agent type mapping (Developer, Bot, CISystem, LLMAgent)
- [x] 20.4.3.6 Add agent builder tests (32 tests)

### 20.4.4 Version Builder
- [x] **Task 20.4.4 Complete**

Generate RDF triples for code version relationships.

- [x] 20.4.4.1 Create `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- [x] 20.4.4.2 Implement `build_version/3` generating version IRI
- [x] 20.4.4.3 Generate `rdf:type prov:Entity` and subclass triple (ModuleVersion, FunctionVersion)
- [x] 20.4.4.4 Generate `evolution:hasPreviousVersion` linking versions
- [x] 20.4.4.5 Generate `evolution:versionString` with version identifier
- [x] 20.4.4.6 Add version builder tests (30 tests)

**Section 20.4 Unit Tests:**
- [ ] Test commit RDF generation
- [ ] Test activity RDF generation
- [ ] Test agent RDF generation
- [ ] Test version RDF generation
- [ ] Test PROV-O relationship triples
- [ ] Test evolution IRI stability
- [ ] Test cross-commit linking
- [ ] Test SHACL validation of evolution RDF

## 20.5 Codebase Snapshot and Release Tracking

This section implements tracking of codebase snapshots and release artifacts.

### 20.5.1 Snapshot Extraction
- [ ] **Task 20.5.1 Pending**

Extract codebase snapshot information at specific points in time.

- [ ] 20.5.1.1 Create `lib/elixir_ontologies/extractors/evolution/snapshot.ex`
- [ ] 20.5.1.2 Define `%CodebaseSnapshot{commit: ..., timestamp: ..., modules: [...], stats: ...}` struct
- [ ] 20.5.1.3 Implement `extract_snapshot/1` for current HEAD
- [ ] 20.5.1.4 Calculate codebase statistics (module count, function count, LOC)
- [ ] 20.5.1.5 Track snapshot as point-in-time state
- [ ] 20.5.1.6 Add snapshot extraction tests

### 20.5.2 Release Extraction
- [ ] **Task 20.5.2 Pending**

Extract release information from tags and mix.exs versions.

- [ ] 20.5.2.1 Define `%Release{version: ..., tag: ..., commit: ..., timestamp: ...}` struct
- [ ] 20.5.2.2 Extract version from mix.exs
- [ ] 20.5.2.3 Extract git tags as release markers
- [ ] 20.5.2.4 Parse semantic versioning
- [ ] 20.5.2.5 Track release progression
- [ ] 20.5.2.6 Add release extraction tests

### 20.5.3 Snapshot and Release Builder
- [ ] **Task 20.5.3 Pending**

Generate RDF triples for snapshots and releases.

- [ ] 20.5.3.1 Implement `build_snapshot/3` generating snapshot IRI
- [ ] 20.5.3.2 Generate `rdf:type evolution:CodebaseSnapshot` triple
- [ ] 20.5.3.3 Implement `build_release/3` generating release IRI
- [ ] 20.5.3.4 Generate `rdf:type evolution:Release` triple
- [ ] 20.5.3.5 Generate `evolution:hasSemanticVersion` with version info
- [ ] 20.5.3.6 Add snapshot/release builder tests

**Section 20.5 Unit Tests:**
- [ ] Test snapshot extraction
- [ ] Test codebase statistics calculation
- [ ] Test release extraction from tags
- [ ] Test mix.exs version parsing
- [ ] Test semantic version parsing
- [ ] Test snapshot RDF generation
- [ ] Test release RDF generation
- [ ] Test version progression tracking

## Phase 20 Integration Tests

- [ ] **Phase 20 Integration Tests** (15+ tests)

- [ ] Test complete evolution extraction for repository
- [ ] Test commit history RDF generation
- [ ] Test activity classification accuracy
- [ ] Test PROV-O compliance of generated triples
- [ ] Test evolution RDF validates against shapes
- [ ] Test Pipeline integration with evolution extractors
- [ ] Test Orchestrator coordinates evolution builders
- [ ] Test blame integration with code elements
- [ ] Test version tracking across multiple commits
- [ ] Test agent deduplication across commits
- [ ] Test refactoring detection accuracy
- [ ] Test release tracking from tags
- [ ] Test snapshot statistics accuracy
- [ ] Test backward compatibility with existing extractors
- [ ] Test error handling for repositories without history
