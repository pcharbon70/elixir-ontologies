# Phase 31: Git History and Evolution Integration

This phase implements optional git history integration that constructs ontology individuals across multiple versions of a project, leveraging the evolution ontology (elixir-evolution.ttl) and PROV-O for provenance tracking. This enables temporal analysis of code evolution, API changes, and contributor attribution.

**Note:** This phase is entirely optional. When `include_history: false`, extraction works on the current codebase state only, as in previous phases.

## 31.1 Configuration for History Extraction

This section extends the Config module to support optional git history extraction with configurable depth.

### 31.1.1 Add include_history to Config Struct
- [ ] 31.1.1.1 Add `include_history: false` field to `Config` struct
- [ ] 31.1.1.2 Add `history_depth: :none` field (options: `:none`, `:tags_only`, `:all_commits`)
- [ ] 31.1.1.3 Add `history_limit: nil` field for limiting number of commits to process
- [ ] 31.1.1.4 Add `max_versions: 100` field for maximum named graphs to generate
- [ ] 31.1.1.5 Update `@type t()` spec with new fields
- [ ] 31.1.1.6 Document trade-offs: storage vs. historical depth, processing time

### 31.1.2 History Configuration Validation
- [ ] 31.1.2.1 Add `:include_history` to `valid_keys` list
- [ ] 31.1.2.2 Add `validate_boolean(:include_history, config.include_history)`
- [ ] 31.1.2.3 Add `validate_history_depth/1` checking valid values
- [ ] 31.1.2.4 Add `validate_positive_or_nil(:history_limit, config.history_limit)`
- [ ] 31.1.2.5 Add `validate_positive(:max_versions, config.max_versions)`
- [ ] 31.1.2.6 Update validation docstring

### 31.1.3 History Mode Detection
- [ ] 31.1.3.1 Add `history_enabled?/1` helper checking `include_history`
- [ ] 31.1.3.2 Add `tags_only_mode?/1` helper checking `history_depth == :tags_only`
- [ ] 31.1.3.3 Add `all_commits_mode?/1` helper checking `history_depth == :all_commits`
- [ ] 31.1.3.4 Document that history applies to project code only, not dependencies
- [ ] 31.1.3.5 Add warning if `include_history: true` but not in a git repository

**Section 31.1 Unit Tests:**
- [ ] Test Config initializes with `include_history: false` and `history_depth: :none`
- [ ] Test Config.merge/2 accepts `include_history` option
- [ ] Test Config.merge/2 accepts `history_depth` with valid values
- [ ] Test Config.merge/2 rejects invalid `history_depth` values
- [ ] Test Config.validate/1 validates `history_limit` as positive integer or nil
- [ ] Test Config.validate/1 validates `max_versions` as positive integer
- [ ] Test `history_enabled?/1` returns true when `include_history: true`
- [ ] Test `tags_only_mode?/1` returns true when `history_depth == :tags_only`
- [ ] Test `all_commits_mode?/1` returns true when `history_depth == :all_commits`

## 31.2 Git Repository Analysis

This section implements git repository traversal and metadata extraction for evolution tracking.

### 31.2.1 Git Repository Detection
- [ ] 31.2.1.1 Implement `in_git_repository?/1` checking for `.git` directory
- [ ] 31.2.1.2 Check parent directories if not found in current directory
- [ ] 31.2.1.3 Return `{:ok, git_root}` or `:error` tuple
- [ ] 31.2.1.4 Handle bare repositories (if applicable)
- [ ] 31.2.1.5 Handle worktrees (if applicable)

### 31.2.2 Commit Traversal
- [ ] 31.2.2.1 Implement `traverse_commits/2` with config and path
- [ ] 31.2.2.2 Use `git log` or git command library to get commit list
- [ ] 31.2.2.3 For `:tags_only` mode: get commits at tags only
- [ ] 31.2.2.4 For `:all_commits` mode: get all commits in current branch
- [ ] 31.2.2.5 Respect `history_limit` config for max commits
- [ ] 31.2.2.6 Respect `max_versions` config for max named graphs
- [ ] 31.2.2.7 Return list of commits with metadata (hash, date, author, message)

### 31.2.3 Tag and Version Extraction
- [ ] 31.2.3.1 Implement `extract_tags/1` getting all git tags
- [ ] 31.2.3.2 Parse version numbers from tag names (semver)
- [ ] 31.2.3.3 Sort tags by version number (not just git order)
- [ ] 31.2.3.4 Filter tags by pattern if config specifies (e.g., `v*` only)
- [ ] 31.2.3.5 Associate tags with corresponding commits
- [ ] 31.2.3.6 Return ordered list of version tags with commits

**Section 31.2 Unit Tests:**
- [ ] Test `in_git_repository?/1` returns true for git directory
- [ ] Test `in_git_repository?/1` returns false for non-git directory
- [ ] Test `in_git_repository?/1` finds git root in parent directory
- [ ] Test `traverse_commits/2` returns commits in correct order
- [ ] Test `traverse_commits/2` respects `history_limit` config
- [ ] Test `traverse_commits/2` respects `max_versions` config
- [ ] Test `extract_tags/1` parses semver tags correctly
- [ ] Test `extract_tags/1` sorts tags by version number
- [ ] Test tag filtering works with pattern config

## 31.3 Named Graph Generation per Version

This section implements extraction and storage of ontology individuals in separate named graphs for each version.

### 31.3.1 Named Graph IRI Strategy
- [ ] 31.3.1.1 Implement `version_graph_iri/2` generating graph IRIs
- [ ] 31.3.1.2 Use pattern: `<graph:version/{version}>` for tagged versions
- [ ] 31.3.1.3 Use pattern: `<graph:commit/{hash}>` for untagged commits
- [ ] 31.3.1.4 Ensure graph IRIs are stable and queryable
- [ ] 31.3.1.5 Document graph naming convention for SPARQL queries

### 31.3.2 Per-Version Extraction
- [ ] 31.3.2.1 Implement `extract_version/3` with commit hash and config
- [ ] 31.3.2.2 Use `git checkout` to restore repository to commit state
- [ ] 31.3.2.3 Run existing extraction pipeline on checked-out code
- [ ] 31.3.2.4 Store resulting triples in named graph for that version
- [ ] 31.3.2.5 Clean up checkout (restore to original state)
- [ ] 31.3.2.6 Handle extraction failures for specific commits gracefully
- [ ] 31.3.2.7 Store extraction metadata (timestamp, success status)

### 31.3.3 Version Metadata
- [ ] 31.3.3.1 Create `ev:Version` individual for each extracted version
- [ ] 31.3.3.2 Store commit hash in `ev:commitHash` property
- [ ] 31.3.3.3 Store commit date in `prov:generatedAtTime` property
- [ ] 31.3.3.4 Store tag name in `ev:versionName` property (if tagged)
- [ ] 31.3.3.5 Link version to its named graph via `ev:hasGraph` property
- [ ] 31.3.3.6 Store in default graph (not version-specific graph)

**Section 31.3 Unit Tests:**
- [ ] Test `version_graph_iri/2` generates correct IRI for tagged version
- [ ] Test `version_graph_iri/2` generates correct IRI for commit hash
- [ ] Test `extract_version/3` extracts code at specified commit
- [ ] Test `extract_version/3` stores triples in correct named graph
- [ ] Test `extract_version/3` restores repository after extraction
- [ ] Test version metadata creates correct `ev:Version` individual
- [ ] Test named graphs contain only individuals for that version

## 31.4 Changeset Generation from Git Diffs

This section implements changeset extraction by comparing individuals between consecutive versions.

### 31.4.1 Diff Analysis Between Versions
- [ ] 31.4.1.1 Implement `compare_versions/3` comparing two version graphs
- [ ] 31.4.1.2 Extract all individuals from source version graph
- [ ] 31.4.1.3 Extract all individuals from target version graph
- [ ] 31.4.1.4 Compare by IRI to find added individuals (in target, not source)
- [ ] 31.4.1.5 Compare by IRI to find removed individuals (in source, not target)
- [ ] 31.4.1.6 Compare by IRI to find modified individuals (in both, different triples)
- [ ] 31.4.1.7 Return diff result with added, removed, modified sets

### 31.4.2 Changeset Creation
- [ ] 31.4.2.1 Implement `create_changeset/4` for version transition
- [ ] 31.4.2.2 Create `ev:Changeset` individual with unique IRI
- [ ] 31.4.2.3 Link source version via `ev:versionFrom` property
- [ ] 31.4.2.4 Link target version via `ev:versionTo` property
- [ ] 31.4.2.5 Add `ev:addedEntity` links for each added individual
- [ ] 31.4.2.6 Add `ev:removedEntity` links for each removed individual
- [ ] 31.4.2.7 Add `ev:modifiedEntity` links for each modified individual
- [ ] 31.4.2.8 Store changeset triples in default graph

### 31.4.3 Function-Specific Changesets
- [ ] 31.4.3.1 Detect function signature changes (arity changes)
- [ ] 31.4.3.2 Create `ev:ArityChange` for function arity modifications
- [ ] 31.4.3.3 Link old and new function individuals
- [ ] 31.4.3.4 Detect parameter pattern changes
- [ ] 31.4.3.5 Detect guard additions/removals
- [ ] 31.4.3.6 Create `ev:BreakingChange` annotation if applicable

**Section 31.4 Unit Tests:**
- [ ] Test `compare_versions/3` correctly identifies added individuals
- [ ] Test `compare_versions/3` correctly identifies removed individuals
- [ ] Test `compare_versions/3` correctly identifies modified individuals
- [ ] Test `create_changeset/4` creates changeset with correct links
- [ ] Test changeset links source and target versions correctly
- [ ] Test function arity changes create `ev:ArityChange`
- [ ] Test breaking changes are annotated correctly

## 31.5 Provenance Metadata Extraction

This section implements extraction of git commit metadata for PROV-O provenance tracking.

### 31.5.1 Activity Creation for Commits
- [ ] 31.5.1.1 Create `prov:Activity` individual for each commit
- [ ] 31.5.1.2 Use commit hash as part of activity IRI
- [ ] 31.5.1.3 Store commit date in `prov:startedAtTime` property
- [ ] 31.5.1.4 Store commit message in `prov:used` / `rdfs:comment` property
- [ ] 31.5.1.5 Link activity to generated version via `prov:generated` property
- [ ] 31.5.1.6 Link activity to parent commit via `prov:used` property

### 31.5.2 Agent Creation for Authors
- [ ] 31.5.2.1 Create `prov:Agent` individual for each unique author
- [ ] 31.5.2.2 Use author email as part of agent IRI (stable identifier)
- [ ] 31.5.2.3 Store author name in `foaf:name` property
- [ ] 31.5.2.4 Store author email in `foaf:mbox` property
- [ ] 31.5.2.5 Link agent to commit activities via `prov:wasAssociatedWith` property
- [ ] 31.5.2.6 Reuse agent individuals across multiple commits

### 31.5.3 Attribution and Derivation
- [ ] 31.5.3.1 Link new version to previous version via `prov:wasDerivedFrom` property
- [ ] 31.5.3.2 Link changeset to commit activity via `prov:wasGeneratedBy` property
- [ ] 31.5.3.3 Store commit author attribution in changeset
- [ ] 31.5.3.4 Distinguish author and committer if different
- [ ] 31.5.3.5 Link to parent commit(s) for merge commits

**Section 31.5 Unit Tests:**
- [ ] Test commit creates `prov:Activity` with correct metadata
- [ ] Test activity stores commit date and message correctly
- [ ] Test activity links to generated version
- [ ] Test author creates `prov:Agent` with name and email
- [ ] Test agent is reused for multiple commits by same author
- [ ] Test version links to parent version via `prov:wasDerivedFrom`
- [ ] Test changeset links to generating commit activity
- [ ] Test merge commits handle multiple parents correctly

## 31.6 History Extraction Pipeline

This section implements the orchestration of git history extraction from start to finish.

### 31.6.1 Pipeline Orchestration
- [ ] 31.6.1.1 Implement `extract_history/2` as main entry point
- [ ] 31.6.1.2 Check if history is enabled in config, return early if not
- [ ] 31.6.1.3 Check if in git repository, return with warning if not
- [ ] 31.6.1.4 Get list of versions (tags or commits) based on `history_depth`
- [ ] 31.6.1.5 For each version: checkout and extract, create named graph
- [ ] 31.6.1.6 After all extractions: generate changesets between consecutive versions
- [ ] 31.6.1.7 Extract provenance metadata for all commits
- [ ] 31.6.1.8 Store all changeset and provenance triples in default graph
- [ ] 31.6.1.9 Restore repository to original state
- [ ] 31.6.1.10 Return summary with version count, changeset count, timing

### 31.6.2 Error Handling and Recovery
- [ ] 31.6.2.1 Handle git command failures gracefully
- [ ] 31.6.2.2 Handle checkout failures (skip version, log warning)
- [ ] 31.6.2.3 Handle extraction failures for specific commits (skip, log)
- [ ] 31.6.2.4 Ensure repository is restored even on error
- [ ] 31.6.2.5 Provide progress reporting for long-running extractions
- [ ] 31.6.2.6 Support resumable extraction (skip already processed versions)
- [ ] 31.6.2.7 Validate extraction produced valid triples for each version

### 31.6.3 Performance Optimization
- [ ] 31.6.3.1 Implement parallel extraction where safe (multiple versions)
- [ ] 31.6.3.2 Cache extraction results to avoid re-processing
- [ ] 31.6.3.3 Use incremental updates for new commits only
- [ ] 31.6.3.4 Provide progress callbacks for monitoring
- [ ] 31.6.3.5 Optimize diff comparison for large changesets

**Section 31.6 Unit Tests:**
- [ ] Test `extract_history/2` returns early when `include_history: false`
- [ ] Test `extract_history/2` returns early when not in git repository
- [ ] Test `extract_history/2` processes versions in correct order
- [ ] Test `extract_history/2` generates named graphs for each version
- [ ] Test `extract_history/2` generates changesets between versions
- [ ] Test `extract_history/2` extracts provenance metadata
- [ ] Test `extract_history/2` restores repository state
- [ ] Test error handling skips problematic versions
- [ ] Test progress reporting works correctly

## 31.7 SPARQL Queries for Historical Analysis

This section implements SPARQL queries for analyzing code evolution over time.

### 31.7.1 Version Navigation Queries
- [ ] 31.7.1.1 Implement `list_versions/1` returning all versions with dates
- [ ] 31.7.1.2 Implement `get_version_at_date/2` finding version closest to date
- [ ] 31.7.1.3 Implement `get_next_version/2` finding successor version
- [ ] 31.7.1.4 Implement `get_previous_version/2` finding predecessor version
- [ ] 31.7.1.5 Implement `get_version_range/3` listing versions in range

### 31.7.2 Entity Evolution Queries
- [ ] 31.7.2.1 Implement `entity_history/2` returning all versions of an entity
- [ ] 31.7.2.2 Implement `when_was_added/2` finding when entity first appeared
- [ ] 31.7.2.3 Implement `when_was_removed/2` finding when entity was removed
- [ ] 31.7.2.4 Implement `get_entity_at_version/3` getting entity state at version
- [ ] 31.7.2.5 Implement `modified_between_versions/3` finding changed entities

### 31.7.3 Contributor Analysis Queries
- [ ] 31.7.3.1 Implement `contributor_activity/2` finding commits by author
- [ ] 31.7.3.2 Implement `contributor_stats/1` returning contribution metrics
- [ ] 31.7.3.3 Implement `who_modified_entity/2` finding contributors to entity
- [ ] 31.7.3.4 Implement `contribution_timeline/2` showing activity over time

### 31.7.4 Impact Analysis Queries
- [ ] 31.7.4.1 Implement `breaking_changes/2` finding breaking API changes
- [ ] 31.7.4.2 Implement `most_changed_entities/2` finding frequently modified entities
- [ ] 31.7.4.3 Implement `dependency_evolution/2` tracking dependency changes
- [ ] 31.7.4.4 Implement `code_growth_metrics/1` calculating size changes

**Section 31.7 Unit Tests:**
- [ ] Test `list_versions/1` returns versions in chronological order
- [ ] Test `get_version_at_date/2` finds correct version for date
- [ ] Test `get_next_version/2` returns successor version
- [ ] Test `get_previous_version/2` returns predecessor version
- [ ] Test `entity_history/2` returns all versions of entity
- [ ] Test `when_was_added/2` returns correct first appearance
- [ ] Test `when_was_removed/2` returns correct removal date
- [ ] Test `contributor_activity/2` returns commits for author
- [ ] Test `who_modified_entity/2` returns contributors for entity
- [ ] Test `breaking_changes/2` identifies breaking changes correctly
- [ ] Test `most_changed_entities/2` ranks entities by modification count

## 31.8 History Integration with Existing Extraction

This section ensures history extraction integrates seamlessly with existing extraction pipeline.

### 31.8.1 Update Main Extraction Entry Point
- [ ] 31.8.1.1 Update `extract/2` to call `extract_history/2` after main extraction
- [ ] 31.8.1.2 Pass config and project path to history extraction
- [ ] 31.8.1.3 Combine history results with main extraction results
- [ ] 31.8.1.4 Include history metadata in extraction summary
- [ ] 31.8.1.5 Ensure history extraction doesn't break when disabled

### 31.8.2 CLI Integration
- [ ] 31.8.2.1 Add `--include-history` flag to CLI
- [ ] 31.8.2.2 Add `--history-depth` flag with options: `none`, `tags`, `all`
- [ ] 31.8.2.3 Add `--max-versions` flag limiting versions to process
- [ ] 31.8.2.4 Add `--history-limit` flag limiting commits to process
- [ ] 31.8.2.5 Document CLI flags in help text
- [ ] 31.8.2.6 Provide examples of common usage patterns

### 31.8.3 History Query Helpers
- [ ] 31.8.3.1 Create `HistoryQueries` module with common queries
- [ ] 31.8.3.2 Document query API with examples
- [ ] 31.8.3.3 Provide query helpers for IEx/console usage
- [ ] 31.8.3.4 Handle missing history gracefully (return empty, not error)
- [ ] 31.8.3.5 Support both single-version and cross-version queries

**Section 31.8 Unit Tests:**
- [ ] Test main extraction calls history extraction when enabled
- [ ] Test main extraction skips history when disabled
- [ ] Test CLI flags correctly set config options
- [ ] Test CLI rejects invalid history depth values
- [ ] Test history query helpers return empty when no history
- [ ] Test history query helpers work correctly with history

## Phase 31 Integration Tests

- [ ] Test complete history extraction flow: git analysis → per-version extraction → changesets → provenance
- [ ] Test history extraction in tags-only mode
- [ ] Test history extraction in all-commits mode (small repo)
- [ ] Test history extraction respects `max_versions` limit
- [ ] Test history extraction respects `history_limit` config
- [ ] Test named graphs contain correct individuals for each version
- [ ] Test changesets correctly track additions, modifications, deletions
- [ ] Test provenance metadata captures authors and dates correctly
- [ ] Test SPARQL queries find entities across versions
- [ ] Test SPARQL queries track entity evolution over time
- [ ] Test SPARQL queries find contributor activity
- [ ] Test history extraction with expression extraction enabled
- [ ] Test history extraction with expression extraction disabled
- [ ] Test history extraction gracefully handles non-git repositories
- [ ] Test history extraction restores repository state after completion
- [ ] Test incremental extraction (re-running doesn't duplicate work)

**Integration Test Summary:**
- 16 integration tests covering complete history extraction pipeline
- Tests verify both tags-only and all-commits modes
- Tests confirm integration with expression extraction
- Tests verify SPARQL queryability of historical data
- Test file: `test/elixir_ontologies/history/git_history_test.exs`

## Configuration Summary After Phase 31

After completing Phase 31, the full configuration matrix is:

```elixir
config :elixir_ontologies,
  # Expression extraction (Phase 21-30)
  include_expressions: false,  # true = full AST for project code

  # History extraction (Phase 31)
  include_history: false,      # true = extract git history
  history_depth: :none,        # :tags_only | :all_commits
  history_limit: nil,          # max commits (nil = unlimited)
  max_versions: 100            # max named graphs
```

**Storage Impact for 50-release project:**
- Light mode (default): ~500 KB (current only)
- Full expressions: ~5 MB (current only)
- Historical (tags): ~25 MB (50 versions, light mode)
- Complete (tags + expressions): ~250 MB (50 versions, full mode)
