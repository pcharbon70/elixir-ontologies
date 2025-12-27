# Phase 17: Integration Tests

## Overview

This task implements integration tests for Phase 17 (Call Graph and Control Flow). The tests verify end-to-end functionality of call extraction, control flow analysis, and RDF generation working together.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:

**Phase 17 Integration Tests (15+ tests):**
- [x] Test complete call graph extraction for complex module
- [x] Test cross-module call graph
- [x] Test control flow extraction accuracy
- [x] Test exception handling coverage
- [x] Test call graph RDF validates against shapes
- [x] Test Pipeline integration with call extractors
- [x] Test Orchestrator coordinates call graph builder
- [x] Test pipe chain representation
- [x] Test recursive function detection
- [x] Test dynamic call handling
- [x] Test receive expression in GenServer
- [x] Test comprehension extraction
- [x] Test nested control flow structures
- [x] Test backward compatibility with existing extractors
- [x] Test error handling for complex AST patterns

## Implementation Plan

### Step 1: Create Test File Structure
- [x] Create `test/elixir_ontologies/phase17_integration_test.exs`
- [x] Set up test module with fixtures path

### Step 2: Implement Core Integration Tests
- [x] Complete call graph extraction test
- [x] Cross-module call graph test
- [x] Control flow extraction test
- [x] Exception handling test

### Step 3: Implement RDF/Builder Integration Tests
- [x] Pipeline integration test
- [x] Orchestrator coordination test
- [x] Call graph RDF shape validation test

### Step 4: Implement Specific Feature Tests
- [x] Pipe chain representation test
- [x] Recursive function detection test
- [x] Dynamic call handling test
- [x] Receive expression test
- [x] Comprehension extraction test
- [x] Nested control flow test

### Step 5: Implement Edge Case Tests
- [x] Backward compatibility test
- [x] Error handling test

### Step 6: Quality Checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

### Step 7: Complete
- [x] Mark phase plan tasks complete
- [x] Write summary

## Success Criteria

- [x] 26 integration tests implemented (exceeds 15+ requirement)
- [x] All tests pass
- [x] Quality checks pass

## Test Implementation Details

The integration test file `test/elixir_ontologies/phase17_integration_test.exs` contains 26 tests organized into the following categories:

### Core Call Graph Tests (4 tests)
- Complete call graph extraction for complex modules
- Cross-module call graph with remote calls
- Control flow extraction accuracy
- Exception handling coverage

### RDF Builder Integration Tests (3 tests)
- Call graph RDF generation with proper triples
- Control flow RDF generation for conditionals/case expressions
- Exception builder RDF generation for try/rescue/catch

### Specific Feature Tests (6 tests)
- Pipe chain representation preserving order
- Recursive function detection
- Dynamic call handling with apply/3
- Receive expression extraction with timeouts
- Comprehension extraction with generators
- Nested control flow structures

### Edge Case Tests (2 tests)
- Backward compatibility with existing extractors
- Error handling for complex AST patterns

### Additional Tests (11 tests)
- Multiple conditional types (if/unless/cond)
- Case expression with multiple clauses
- With expression extraction
- Pipe chain RDF generation
- Call types (local vs remote)
- Conditional branch linking
- Try/rescue/catch/after extraction
- Exception variable binding
- Comprehension filters
- Nested exceptions in control flow
- Cross-module pipeline compatibility
