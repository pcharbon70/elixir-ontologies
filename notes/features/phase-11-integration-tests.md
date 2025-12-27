# Phase 11 Integration Tests - Implementation Plan

**Date**: 2025-12-15
**Status**: In Progress
**Branch**: `feature/phase-11-integration-tests`

## Problem Statement

The native Elixir SHACL validation implementation (Phase 11.1-11.6) has completed core infrastructure, W3C test suite integration (66.0% pass rate, 35/53 tests), and domain-specific testing (26 tests, 71.4% shape coverage). However, we lack **end-to-end integration tests** that validate the complete workflow from Elixir code analysis through RDF generation to SHACL validation.

**Current Gaps:**

1. **No End-to-End Workflow Testing**: No tests that analyze real Elixir code → generate RDF → validate with SHACL
2. **No Self-Referential Validation**: Haven't validated this repository's own codebase against SHACL shapes
3. **No Mix Task E2E Testing**: `mix elixir_ontologies.analyze --validate` not tested end-to-end
4. **No Performance Testing**: No tests for parallel validation with large multi-module projects
5. **No Error Scenario Testing**: Limited testing of validation failures with detailed violation reporting
6. **No Real OTP Pattern Testing**: While we have domain fixtures, we need real analyzed OTP code
7. **No Evolution Tracking Testing**: Git tracking + SHACL validation not tested together
8. **No Error Handling Testing**: Invalid shapes files and malformed RDF not systematically tested

**Why This Matters:**

- **Quality Assurance**: Ensures all Phase 11 components work together correctly in production scenarios
- **Regression Prevention**: Catches integration bugs between analyzer, RDF generation, and SHACL validation
- **Production Readiness**: Validates the complete user workflow from code analysis to validation
- **Documentation by Example**: Integration tests serve as executable documentation for users
- **Confidence**: Proves the system works end-to-end with real Elixir codebases

## Solution Overview

Create a comprehensive integration test suite (`test/elixir_ontologies/shacl/integration_test.exs`) with 15+ tests organized into 8 test categories:

### Test Categories

1. **End-to-End Workflow** (3 tests)
   - Analyze Elixir file → Generate RDF → Validate with SHACL → Verify conformance
   - Analyze multi-module file → Validate all modules
   - Analyze project → Validate complete graph

2. **Self-Referential Validation** (2 tests)
   - Validate this repository's own analyzer modules
   - Validate this repository's SHACL validator modules

3. **All Shape Coverage** (1 test)
   - Analyze diverse codebase exercising all 28 shapes in elixir-shapes.ttl

4. **Real OTP Pattern Validation** (3 tests)
   - Analyze real GenServer → Validate GenServer constraints
   - Analyze real Supervisor → Validate Supervisor constraints
   - Analyze Agent/Task/ETS patterns → Validate OTP constraints

5. **Evolution Tracking + Validation** (2 tests)
   - Analyze file with Git info → Validate commit/repository constraints
   - Validate version tracking and changeset constraints

6. **Validation Failure Scenarios** (2 tests)
   - Intentionally create invalid RDF → Verify violations reported correctly
   - Test detailed violation messages and focus node reporting

7. **Error Handling** (2 tests)
   - Test validation with invalid/malformed shapes file
   - Test validation with malformed RDF graph

8. **Performance Testing** (1 test)
   - Validate large multi-module project in parallel mode
   - Measure validation performance and concurrency

**Target**: 15+ integration tests covering complete workflows

## Technical Details

### Available Infrastructure

**Extractors** (22 extractors across 4 layers):
- **Core Extractors**: Module, Function, Clause, Parameter, Guard, Attribute, Literal, Operator, Pattern, Control Flow, Comprehension, Block, Reference, Quote
- **Advanced Extractors**: Type Definition, Type Expression, Function Spec, Macro, Return Expression
- **Protocol/Behavior**: Protocol, Behaviour, Struct
- **OTP Extractors**: GenServer, Supervisor, Agent, Task, ETS

**SHACL Shapes** (28 shapes in elixir-shapes.ttl):
- Module System (6): ModuleShape, NestedModuleShape, FunctionShape, FunctionClauseShape, ParameterShape, DefaultParameterShape
- Macros (1): MacroShape
- Protocols (2): ProtocolShape, ProtocolImplementationShape
- Behaviours (2): BehaviourShape, CallbackSpecShape
- Structs (2): StructShape, StructFieldShape
- Type System (2): TypeSpecShape, FunctionSpecShape
- OTP Patterns (5): GenServerImplementationShape, SupervisorShape, DynamicSupervisorShape, ChildSpecShape, ETSTableShape
- Evolution (8): CommitShape, ChangeSetShape, SemanticVersionShape, CodeVersionShape, RepositoryShape, BranchShape, DeveloperShape, SourceLocationShape

### Public API Available

**Analysis API** (`ElixirOntologies`):
- `analyze_file/2` - Analyze single Elixir file → RDF graph
- `analyze_project/2` - Analyze Mix project → Unified RDF graph

**Validation API** (`ElixirOntologies.Validator`):
- `validate/2` - Validate graph against elixir-shapes.ttl (domain-specific)

**SHACL API** (`ElixirOntologies.SHACL`):
- `validate/3` - General-purpose SHACL validation

## Implementation Progress

### ✅ Completed Tasks

None yet - starting implementation

### 🔄 In Progress

Creating integration test suite structure

### ⏳ Pending Tasks

All implementation steps pending

## Test Implementation Plan

### Step 1: End-to-End Workflow Tests (3 tests)

**Test 1.1: Simple File Analysis → Validation**
- Create minimal valid Elixir module
- Analyze → RDF → Validate
- Assert conformance

**Test 1.2: Multi-Module File → Validation**
- Use existing multi-module fixture
- Analyze → Validate
- Assert all modules conform

**Test 1.3: Project Analysis → Validation**
- Create temp Mix project
- Analyze project → Validate
- Assert conformance

### Step 2: Self-Referential Validation (2 tests)

**Test 2.1: Validate Analyzer Modules**
- Analyze lib/elixir_ontologies/analyzer/file_analyzer.ex
- Validate graph
- Assert our code validates!

**Test 2.2: Validate SHACL Validator Modules**
- Analyze lib/elixir_ontologies/shacl/validator.ex
- Validate graph
- Assert conformance

### Step 3: All Shape Coverage (1 test)

**Test 3.1: Exercise All 28 Shapes**
- Create comprehensive test module
- Include: nested modules, functions, macros, protocols, behaviours, structs, type specs, GenServer, Supervisor
- Analyze → Validate
- Verify all 28 shapes exercised

### Step 4: Real OTP Pattern Validation (3 tests)

**Test 4.1: GenServer Analysis**
- Analyze real GenServer
- Validate OTP constraints
- Verify init/1 callback

**Test 4.2: Supervisor Analysis**
- Analyze Supervisor
- Validate strategy constraints
- Verify enumeration constraint

**Test 4.3: Agent/Task/ETS**
- Analyze OTP patterns
- Validate constraints

### Step 5: Evolution Tracking + Validation (2 tests)

**Test 5.1: Git Info + Commit Validation**
- Analyze with Git info
- Validate commit constraints
- Verify hash pattern (40-char hex)

**Test 5.2: Version Tracking**
- Validate semantic version constraints
- Assert version pattern matching

### Step 6: Validation Failure Scenarios (2 tests)

**Test 6.1: Intentional Violations**
- Create invalid RDF
- Verify violations reported
- Check violation details

**Test 6.2: Detailed Violation Reporting**
- Use domain fixtures
- Verify constraint components
- Check error messages

### Step 7: Error Handling (2 tests)

**Test 7.1: Invalid Shapes File**
- Create malformed shapes
- Assert error handling

**Test 7.2: Malformed RDF Graph**
- Create invalid RDF
- Assert graceful error

### Step 8: Performance Testing (1 test)

**Test 8.1: Parallel Validation**
- Analyze 10+ modules
- Validate in parallel
- Measure performance

## Success Criteria

1. ✅ **Test Count**: 15+ integration tests passing
2. ✅ **Workflow Coverage**: All major workflows tested
3. ✅ **Shape Coverage**: All 28 shapes exercised
4. ✅ **Self-Validation**: Repository validates itself
5. ✅ **Error Coverage**: Success and failure scenarios
6. ✅ **Performance**: Parallel validation tested
7. ✅ **Documentation**: Tests as executable examples
8. ✅ **CI Integration**: All tests pass in CI
9. ✅ **No Regressions**: Existing tests continue passing
10. ✅ **Real Code**: Tests use real analysis, not just fixtures

## Next Steps

1. Create integration test file structure
2. Implement test helpers
3. Implement tests incrementally
4. Run and verify all tests pass
5. Update phase plan
6. Write summary

## Notes

- Tests tagged with `:integration` and `:shacl_integration`
- Some tests use `:tmp_dir` for file operations
- Most tests can run async except file I/O tests
- Target completion time: <30 seconds for all tests
