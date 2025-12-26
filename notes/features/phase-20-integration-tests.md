# Phase 20 Integration Tests

## Overview

Implement comprehensive integration tests for the evolution and provenance layer (Phase 20). These tests verify end-to-end functionality across all evolution extractors and builders, ensuring PROV-O compliance and proper cross-module interactions.

## Requirements

From phase-20.md:

- [x] Test complete evolution extraction for repository
- [x] Test commit history RDF generation
- [x] Test activity classification accuracy
- [x] Test PROV-O compliance of generated triples
- [x] Test evolution RDF validates against shapes
- [x] Test Pipeline integration with evolution extractors
- [x] Test Orchestrator coordinates evolution builders
- [x] Test blame integration with code elements
- [x] Test version tracking across multiple commits
- [x] Test agent deduplication across commits
- [x] Test refactoring detection accuracy
- [x] Test release tracking from tags
- [x] Test snapshot statistics accuracy
- [x] Test backward compatibility with existing extractors
- [x] Test error handling for repositories without history

## Implementation Plan

### Step 1: Create Phase 20 Integration Test File
- [x] Create `test/elixir_ontologies/extractors/evolution/phase_20_integration_test.exs`
- [x] Set up module with all required aliases
- [x] Add `@moduletag :integration` for test filtering

### Step 2: Extraction-to-Builder Pipeline Tests
- [x] Test commit extraction → commit builder pipeline
- [x] Test activity extraction → activity builder pipeline
- [x] Test agent extraction → agent builder pipeline
- [x] Test version extraction → version builder pipeline
- [x] Test snapshot extraction → snapshot builder pipeline
- [x] Test release extraction → release builder pipeline

### Step 3: PROV-O Compliance Tests
- [x] Verify prov:Entity typing on entities
- [x] Verify prov:Activity typing on activities
- [x] Verify prov:Agent typing on agents
- [x] Test prov:wasGeneratedBy relationships
- [x] Test prov:wasAttributedTo relationships
- [x] Test prov:wasAssociatedWith relationships
- [x] Test prov:wasDerivedFrom relationships
- [x] Test prov:generatedAtTime timestamps

### Step 4: Cross-Module Integration Tests
- [x] Test blame + commit + developer correlation (expand existing)
- [x] Test activity classification across commit history
- [x] Test agent deduplication across commits
- [x] Test version tracking through multiple commits
- [x] Test refactoring detection with activity classification

### Step 5: Statistics and Accuracy Tests
- [x] Test snapshot statistics accuracy
- [x] Test release tracking from git tags
- [x] Test activity classification accuracy on known commits

### Step 6: Error Handling Tests
- [x] Test error handling for repositories without history
- [x] Test error handling for invalid paths
- [x] Test graceful degradation when git not available

### Step 7: Backward Compatibility Tests
- [x] Test existing extractor APIs still work
- [x] Test builder APIs compatible with new extractors

## Test Categories

### 1. Complete Evolution Extraction Pipeline (3 tests)
Tests that verify the full extraction → builder flow for the entire repository.

### 2. PROV-O Compliance (5 tests)
Tests that verify generated RDF follows PROV-O ontology patterns.

### 3. Cross-Module Correlation (5 tests)
Tests that verify different modules work together correctly (already some in existing integration_test.exs).

### 4. Statistics Accuracy (3 tests)
Tests that verify snapshot and release statistics are accurate.

### 5. Error Handling (3 tests)
Tests that verify graceful error handling.

### 6. Backward Compatibility (2 tests)
Tests that verify existing APIs continue to work.

## Files to Create/Modify

### New Files
- `test/elixir_ontologies/extractors/evolution/phase_20_integration_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark integration tests complete)

## Success Criteria

1. All 15+ integration tests passing
2. Tests cover extraction → builder pipeline for all modules
3. PROV-O compliance verified
4. Error handling tested
5. No regressions in existing tests
