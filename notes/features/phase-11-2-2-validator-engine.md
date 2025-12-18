# Phase 11.2.2: Main Validator Engine - Implementation Plan

## Executive Summary

Phase 11.2.2 creates the orchestration engine that coordinates validation across all SHACL shapes, target nodes, and constraint validators. This is the "conductor" that brings together the Phase 11.2.1 constraint validators into a cohesive validation system.

**Status**: ✅ Planning Complete → 🚧 Implementation In Progress
**Dependencies**: Phase 11.2.1 (Complete - 110 tests passing), Phase 11.1 (Complete - Reader, Writer, Models)
**Target**: Create `lib/elixir_ontologies/shacl/validator.ex` with 15+ tests

## Context & Architecture

### What We Have (Built in Previous Phases)

**Phase 11.1 - SHACL Infrastructure:**
- `SHACL.Reader` - Parses elixir-shapes.ttl into NodeShape/PropertyShape structs (32 tests)
- `SHACL.Writer` - Serializes ValidationReport to RDF/Turtle (22 tests)
- `SHACL.Model.*` - Data structures (NodeShape, PropertyShape, ValidationResult, ValidationReport, SPARQLConstraint)
- `SHACL.Vocabulary` - SHACL namespace constants

**Phase 11.2.1 - Core Constraint Validators (110 tests passing):**
- `SHACL.Validators.Cardinality` - minCount, maxCount
- `SHACL.Validators.Type` - datatype, class
- `SHACL.Validators.String` - pattern, minLength
- `SHACL.Validators.Value` - in, hasValue, maxInclusive
- `SHACL.Validators.Qualified` - qualifiedValueShape + qualifiedMinCount
- `SHACL.Validators.Helpers` - Shared utilities

**Validator Function Signature (consistent across all):**
```elixir
@spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
```

### What We're Building (Phase 11.2.2)

The **Main Validator Engine** orchestrates the entire validation process:

1. **Input**: Data graph + Shapes graph + Options
2. **Parse Shapes**: Use Reader to extract NodeShape structs
3. **Target Selection**: Find focus nodes via sh:targetClass
4. **Validation Loop**: For each focus node, validate against property shapes
5. **Constraint Dispatch**: Call appropriate validators based on constraints present
6. **Parallel Processing**: Use Task.async_stream for performance
7. **Report Aggregation**: Collect all ValidationResults into ValidationReport
8. **Output**: ValidationReport with conforms? flag

## Implementation Status

### ✅ Completed Tasks

- [x] Planning document created
- [x] Feature branch created: `feature/phase-11-2-2-validator-engine`
- [x] Step 1: Basic Sequential Validation
- [x] Step 2: Constraint Validator Integration
- [x] Step 3: Parallel Validation
- [x] Step 4: Comprehensive Testing (22 tests - exceeds 15+ target)

## Detailed Design

### Module Structure

**File**: `lib/elixir_ontologies/shacl/validator.ex`

### Public API

```elixir
defmodule ElixirOntologies.SHACL.Validator do
  @moduledoc """
  Main SHACL validation orchestration engine.

  This module coordinates validation across all SHACL shapes, selecting target
  nodes, dispatching to constraint validators, and aggregating results into
  a validation report.
  """

  @spec run(RDF.Graph.t(), RDF.Graph.t(), keyword()) ::
    {:ok, ValidationReport.t()} | {:error, term()}
  def run(data_graph, shapes_graph, opts \\ [])
end
```

### Core Algorithm

```elixir
def run(data_graph, shapes_graph, opts) do
  with {:ok, node_shapes} <- Reader.parse_shapes(shapes_graph),
       {:ok, all_results} <- validate_all_shapes(data_graph, node_shapes, opts) do

    conforms? = Enum.all?(all_results, fn r -> r.severity != :violation end)

    report = %ValidationReport{
      conforms?: conforms?,
      results: all_results
    }

    {:ok, report}
  end
end
```

### Target Node Selection Algorithm

**Problem**: Given a NodeShape with sh:targetClass, find all matching nodes in the data graph.

**Solution**:
```elixir
defp select_target_nodes(data_graph, target_classes) when target_classes == [] do
  []
end

defp select_target_nodes(data_graph, target_classes) do
  target_classes
  |> Enum.flat_map(fn target_class ->
    data_graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, o} ->
      p == RDF.type() && o == target_class
    end)
    |> Enum.map(fn {s, _p, _o} -> s end)
  end)
  |> Enum.uniq()
end
```

## Implementation Sequence

### Step 1: Basic Sequential Validation ✅ Planning Complete

**Tasks**:
1. Create `lib/elixir_ontologies/shacl/validator.ex`
2. Implement `run/3` with basic error handling
3. Implement `select_target_nodes/2` for sh:targetClass
4. Implement `validate_node_shape/2` loop
5. Implement `validate_focus_node/3` loop
6. Implement `validate_property_shape/3` dispatcher

**Test Coverage** (5 tests):
- Parse shapes and validate simple graph
- Target node selection for single class
- Target node selection for multiple classes
- Validation with no target nodes (empty result)
- End-to-end: conformant data → conforms? = true

### Step 2: Constraint Validator Integration

**Tasks**:
1. Wire up all 5 constraint validators in dispatcher
2. Test each validator is called correctly
3. Test results are aggregated properly
4. Test ValidationReport conformance logic

**Test Coverage** (5 tests):
- Cardinality violations are detected
- Type violations are detected
- String pattern violations are detected
- Value enumeration violations are detected
- Multiple constraint violations on same node

### Step 3: Parallel Validation

**Tasks**:
1. Implement `validate_shapes_parallel/3`
2. Add `parallel` and `max_concurrency` options
3. Handle Task.async_stream results
4. Add timeout handling

**Test Coverage** (3 tests):
- Parallel validation produces same results as sequential
- Parallel validation with timeout option
- Parallel validation handles task failures gracefully

### Step 4: Real-World Testing

**Tasks**:
1. Load real elixir-shapes.ttl
2. Create realistic test data graphs
3. Test against production shapes
4. Test edge cases and error conditions

**Test Coverage** (7 tests):
- Validate Module with all ModuleShape constraints
- Validate Function with all FunctionShape constraints
- Validate OTP Supervisor with strategy constraints
- Validate mixed valid/invalid data
- Empty data graph validation
- Invalid shapes graph error handling
- Large graph performance test (100+ nodes)

## Testing Strategy

### Test Organization

**File**: `test/elixir_ontologies/shacl/validator_test.exs`

Target: 20+ tests (exceeds 15+ requirement)

## Success Criteria

- [ ] All 20+ validator orchestration tests passing
- [ ] `run/3` validates conformant graphs correctly (conforms? = true)
- [ ] `run/3` detects violations in non-conformant graphs (conforms? = false)
- [ ] Target node selection works for single and multiple sh:targetClass
- [ ] All 5 constraint validators are called and results aggregated
- [ ] Parallel validation produces identical results to sequential
- [ ] Real-world validation against elixir-shapes.ttl succeeds
- [ ] Performance: <1s for 1000-node graphs
- [ ] Error handling: Invalid shapes, timeouts, exceptions handled gracefully
- [ ] Documentation: Comprehensive @moduledoc with examples

## Implementation Checklist

### Code

- [ ] Create `lib/elixir_ontologies/shacl/validator.ex`
- [ ] Implement `run/3` entry point
- [ ] Implement `select_target_nodes/2` for sh:targetClass
- [ ] Implement `validate_node_shape/2` loop
- [ ] Implement `validate_focus_node/3` loop
- [ ] Implement `validate_property_shape/3` dispatcher
- [ ] Implement `validate_shapes_sequential/2`
- [ ] Implement `validate_shapes_parallel/3` with Task.async_stream
- [ ] Add comprehensive @moduledoc with examples
- [ ] Add @doc for all public functions
- [ ] Add @spec typespecs for all functions

### Tests

- [ ] Test conformant graph validation (conforms? = true)
- [ ] Test non-conformant graph validation (conforms? = false)
- [ ] Test target node selection (single class)
- [ ] Test target node selection (multiple classes)
- [ ] Test target node selection (no matching nodes)
- [ ] Test cardinality constraint integration
- [ ] Test type constraint integration
- [ ] Test string constraint integration
- [ ] Test value constraint integration
- [ ] Test qualified constraint integration
- [ ] Test multiple constraints on same property
- [ ] Test parallel validation equivalence
- [ ] Test parallel validation with timeout
- [ ] Test validation against real elixir-shapes.ttl
- [ ] Test empty data graph
- [ ] Test invalid shapes graph error handling
- [ ] Test large graph performance (100+ nodes)
