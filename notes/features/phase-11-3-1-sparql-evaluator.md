# Phase 11.3.1: SPARQL Constraint Evaluator - Implementation Plan

## Executive Summary

Phase 11.3.1 implements SPARQL-based constraint validation for complex SHACL validation rules that cannot be expressed with core constraints alone. This adds support for the 3 SPARQL constraints defined in elixir-shapes.ttl: SourceLocationShape, FunctionArityMatchShape, and ProtocolComplianceShape.

**Status**: ✅ Planning Complete → 🚧 Ready for Implementation
**Dependencies**: Phase 11.2.2 (Complete - Validator Engine), SPARQL.ex library (installed)
**Target**: Create `lib/elixir_ontologies/shacl/validators/sparql.ex` with 12+ tests

## Context & Architecture

### What We Have (Built in Previous Phases)

**Phase 11.1 - SHACL Infrastructure:**
- `SHACL.Reader` - Parses shapes including SPARQL constraints
- `SHACL.Writer` - Serializes ValidationReport to RDF
- `SHACL.Model.SPARQLConstraint` - Data structure for SPARQL constraints
- `SHACL.Model.ValidationResult` - Violation representation

**Phase 11.2 - Core Validation:**
- `SHACL.Validator` - Main orchestration engine (22 tests)
- `SHACL.Validators.*` - 5 core constraint validators (110 tests)
- Consistent validator interface: `validate(graph, focus_node, constraint) :: [ValidationResult.t()]`

**SPARQL.ex Library:**
- Already installed as optional dependency (version 0.3.11)
- Main API: `SPARQL.execute_query(rdf_graph, query_string)`
- Returns `SPARQL.Query.Result.t()` with solution bindings

**Existing SPARQL Usage:**
- `ElixirOntologies.Graph.query/3` already uses SPARQL.execute_query/2
- Example pattern available in lib/elixir_ontologies/graph.ex:289-295

### What We're Building (Phase 11.3.1)

The **SPARQL Constraint Validator** evaluates sh:sparql constraints by:

1. **Input**: RDF.Graph, focus_node (IRI or blank node), PropertyShape or NodeShape
2. **$this Substitution**: Replace $this placeholder with actual focus node
3. **Query Execution**: Run SPARQL SELECT against data graph
4. **Result Processing**: Each result row = one violation
5. **Output**: List of ValidationResult structs

## SPARQL Constraints in elixir-shapes.ttl

### 1. SourceLocationShape - Line Number Validation

```sparql
SELECT $this ?startLine ?endLine
WHERE {
    $this core:startLine ?startLine .
    $this core:endLine ?endLine .
    FILTER (?endLine < ?startLine)
}
```

**Violation**: endLine < startLine (invalid source location)

### 2. FunctionArityMatchShape - Arity Consistency

```sparql
SELECT $this ?arity ?paramCount
WHERE {
    $this struct:arity ?arity .
    $this struct:hasClause ?clause .
    ?clause struct:clauseOrder 1 .
    ?clause struct:hasHead ?head .
    {
        SELECT (COUNT(?param) AS ?paramCount)
        WHERE {
            ?head struct:hasParameter ?param .
        }
    }
    FILTER (?arity != ?paramCount)
}
```

**Violation**: Function arity ≠ parameter count in first clause

### 3. ProtocolComplianceShape - Implementation Coverage

```sparql
SELECT $this ?protocol ?missingFunc
WHERE {
    $this struct:implementsProtocol ?protocol .
    ?protocol struct:definesProtocolFunction ?missingFunc .
    FILTER NOT EXISTS {
        $this struct:containsFunction ?implFunc .
        ?implFunc struct:functionName ?name .
        ?missingFunc struct:functionName ?name .
    }
}
```

**Violation**: Protocol implementation missing required function

## Implementation Status

### ✅ Completed Tasks

- [x] Planning document created
- [x] Feature branch created: `feature/phase-11-3-1-sparql-evaluator`
- [x] SPARQL.ex dependency verified (installed, version 0.3.11)
- [x] SPARQL constraints analyzed from elixir-shapes.ttl
- [x] Step 1: Basic SPARQL Validator Structure
- [x] Step 2: $this Placeholder Substitution (IRIs with BIND, blank nodes with simple replacement)
- [x] Step 3: Query Execution and Result Handling
- [x] Step 4: Real SPARQL Constraint Testing (15/17 tests passing, 2 pending due to SPARQL.ex limitations)
- [x] Integration with Validator engine
- [x] Comprehensive test suite (17 tests)
- [x] Implementation summary written

## Detailed Design

### Module Structure

**File**: `lib/elixir_ontologies/shacl/validators/sparql.ex`

### Validator Signature

Following the established pattern from Phase 11.2.1:

```elixir
defmodule ElixirOntologies.SHACL.Validators.SPARQL do
  @moduledoc """
  SPARQL-based constraint validator for complex validation rules.

  Evaluates sh:sparql constraints by executing SPARQL SELECT queries
  against the data graph with $this placeholder substitution.
  """

  alias ElixirOntologies.SHACL.Model.{SPARQLConstraint, ValidationResult}

  # Main entry point - called by Validator engine
  @spec validate(RDF.Graph.t(), RDF.Term.t(), [SPARQLConstraint.t()]) ::
    [ValidationResult.t()]
  def validate(data_graph, focus_node, sparql_constraints)

  # Process single constraint
  @spec validate_constraint(RDF.Graph.t(), RDF.Term.t(), SPARQLConstraint.t()) ::
    [ValidationResult.t()]
  defp validate_constraint(data_graph, focus_node, constraint)

  # Replace $this with actual focus node
  @spec substitute_this(String.t(), RDF.Term.t()) :: String.t()
  defp substitute_this(query_string, focus_node)

  # Execute SPARQL query
  @spec execute_query(RDF.Graph.t(), String.t()) ::
    {:ok, SPARQL.Query.Result.t()} | {:error, term()}
  defp execute_query(data_graph, query_string)

  # Convert query results to ValidationResults
  @spec results_to_violations(SPARQL.Query.Result.t(), RDF.Term.t(), SPARQLConstraint.t()) ::
    [ValidationResult.t()]
  defp results_to_violations(query_result, focus_node, constraint)
end
```

### Algorithm: $this Placeholder Substitution

The `$this` placeholder must be replaced with the focus node's N-Triples representation:

**For IRIs:**
```elixir
# Input: SELECT $this WHERE { $this a core:Function }
# Focus node: ~I<http://example.org/M#foo/2>
# Output: SELECT <http://example.org/M#foo/2> WHERE { <http://example.org/M#foo/2> a core:Function }
```

**For Blank Nodes:**
```elixir
# Input: SELECT $this WHERE { $this a core:Function }
# Focus node: RDF.bnode("b42")
# Output: SELECT _:b42 WHERE { _:b42 a core:Function }
```

**Implementation:**
```elixir
defp substitute_this(query_string, %RDF.IRI{} = iri) do
  String.replace(query_string, "$this", "<#{iri}>")
end

defp substitute_this(query_string, %RDF.BlankNode{} = bnode) do
  String.replace(query_string, "$this", RDF.BlankNode.to_string(bnode))
end
```

### Algorithm: Query Execution

Using SPARQL.ex library:

```elixir
defp execute_query(data_graph, query_string) do
  try do
    result = SPARQL.execute_query(data_graph, query_string)
    {:ok, result}
  rescue
    e -> {:error, e}
  end
end
```

### Algorithm: Result Processing

SPARQL.Query.Result structure contains solution bindings. Each solution = one violation:

```elixir
defp results_to_violations(%SPARQL.Query.Result{results: solutions}, focus_node, constraint) do
  Enum.map(solutions, fn solution ->
    %ValidationResult{
      severity: :violation,
      focus_node: focus_node,
      source_constraint_component: constraint.source_shape_id,
      message: constraint.message,
      details: solution_to_details(solution)
    }
  end)
end

defp solution_to_details(solution) do
  # Convert SPARQL solution bindings to details map
  # E.g., {?arity => 2, ?paramCount => 3} -> %{arity: 2, param_count: 3}
  solution
  |> Enum.map(fn {var_name, value} ->
    {String.to_atom(var_name), value}
  end)
  |> Map.new()
end
```

### Integration with Validator Engine

The Validator engine needs to call SPARQL validator for NodeShapes with SPARQL constraints:

**Current (lib/elixir_ontologies/shacl/validator.ex):**
```elixir
defp validate_focus_node(data_graph, focus_node, node_shape) do
  node_shape.property_shapes
  |> Enum.flat_map(fn property_shape ->
    validate_property_shape(data_graph, focus_node, property_shape)
  end)
end
```

**After Phase 11.3.1:**
```elixir
defp validate_focus_node(data_graph, focus_node, node_shape) do
  # Property shape constraints
  property_results =
    node_shape.property_shapes
    |> Enum.flat_map(fn property_shape ->
      validate_property_shape(data_graph, focus_node, property_shape)
    end)

  # SPARQL constraints (node-level)
  sparql_results =
    Validators.SPARQL.validate(data_graph, focus_node, node_shape.sparql_constraints)

  property_results ++ sparql_results
end
```

## Implementation Sequence

### Step 1: Basic SPARQL Validator Structure ✅ Planning Complete

**Tasks**:
1. Create `lib/elixir_ontologies/shacl/validators/sparql.ex`
2. Implement basic module structure with @moduledoc
3. Add `validate/3` entry point function
4. Add placeholder for $this substitution
5. Add placeholder for query execution

**Test Coverage** (3 tests):
- Empty constraint list returns empty result
- Non-SPARQL constraint is skipped
- Validator module exists and has correct signature

### Step 2: $this Placeholder Substitution

**Tasks**:
1. Implement `substitute_this/2` for IRIs
2. Implement `substitute_this/2` for blank nodes
3. Handle edge cases (multiple $this occurrences)
4. Test substitution correctness

**Test Coverage** (3 tests):
- $this replaced with IRI in angle brackets
- $this replaced with blank node identifier
- Multiple $this occurrences all replaced

### Step 3: Query Execution and Result Handling

**Tasks**:
1. Implement `execute_query/2` using SPARQL.execute_query
2. Implement `results_to_violations/3` mapping
3. Handle query errors gracefully
4. Test with simple SPARQL queries

**Test Coverage** (3 tests):
- Query execution returns violations on match
- Query execution returns empty on no match
- Query execution handles SPARQL errors

### Step 4: Real SPARQL Constraint Testing

**Tasks**:
1. Test SourceLocationShape constraint (endLine >= startLine)
2. Test FunctionArityMatchShape constraint (arity = param count)
3. Test ProtocolComplianceShape constraint (implementation coverage)
4. Integration with Validator engine

**Test Coverage** (7 tests):
- SourceLocationShape: valid location passes
- SourceLocationShape: invalid location (endLine < startLine) fails
- FunctionArityMatchShape: matching arity passes
- FunctionArityMatchShape: mismatched arity fails
- ProtocolComplianceShape: complete implementation passes
- ProtocolComplianceShape: missing function fails
- Integration: Validator engine calls SPARQL validator

## Testing Strategy

### Test Organization

**File**: `test/elixir_ontologies/shacl/validators/sparql_test.exs`

Target: 16+ tests (exceeds 12+ requirement)

### Test Structure

```elixir
defmodule ElixirOntologies.SHACL.Validators.SPARQLTest do
  use ExUnit.Case, async: true

  import RDF.Sigils
  alias ElixirOntologies.SHACL.Validators.SPARQL
  alias ElixirOntologies.SHACL.Model.SPARQLConstraint

  describe "validate/3 basic functionality" do
    # 3 tests
  end

  describe "$this placeholder substitution" do
    # 3 tests
  end

  describe "query execution" do
    # 3 tests
  end

  describe "real SPARQL constraints" do
    # 7 tests - one for each actual constraint from elixir-shapes.ttl
  end
end
```

### Test Data Fixtures

**SourceLocationShape Test Data:**
```elixir
# Valid: endLine >= startLine
{~I<http://example.org/loc1>, ~I<core:startLine>, RDF.XSD.integer(10)}
{~I<http://example.org/loc1>, ~I<core:endLine>, RDF.XSD.integer(20)}

# Invalid: endLine < startLine
{~I<http://example.org/loc2>, ~I<core:startLine>, RDF.XSD.integer(20)}
{~I<http://example.org/loc2>, ~I<core:endLine>, RDF.XSD.integer(10)}
```

## Success Criteria

- [ ] All 16+ SPARQL validator tests passing
- [ ] `validate/3` correctly executes SPARQL constraints
- [ ] $this placeholder substitution works for IRIs and blank nodes
- [ ] SPARQL query execution handles errors gracefully
- [ ] All 3 real SPARQL constraints from elixir-shapes.ttl work correctly
- [ ] SourceLocationShape detects invalid line ranges
- [ ] FunctionArityMatchShape detects arity mismatches
- [ ] ProtocolComplianceShape detects missing implementations
- [ ] Integration with Validator engine (validate_focus_node calls SPARQL validator)
- [ ] Documentation: Comprehensive @moduledoc with examples

## Implementation Checklist

### Code

- [ ] Create `lib/elixir_ontologies/shacl/validators/sparql.ex`
- [ ] Implement `validate/3` entry point
- [ ] Implement `substitute_this/2` for IRIs
- [ ] Implement `substitute_this/2` for blank nodes
- [ ] Implement `execute_query/2` with error handling
- [ ] Implement `results_to_violations/3` mapper
- [ ] Add comprehensive @moduledoc with examples
- [ ] Add @doc for all public functions
- [ ] Add @spec typespecs for all functions
- [ ] Update Validator engine to call SPARQL validator

### Tests

- [ ] Test basic validator functionality (3 tests)
- [ ] Test $this substitution with IRIs (1 test)
- [ ] Test $this substitution with blank nodes (1 test)
- [ ] Test $this substitution with multiple occurrences (1 test)
- [ ] Test query execution success (1 test)
- [ ] Test query execution no match (1 test)
- [ ] Test query execution error handling (1 test)
- [ ] Test SourceLocationShape valid (1 test)
- [ ] Test SourceLocationShape invalid (1 test)
- [ ] Test FunctionArityMatchShape valid (1 test)
- [ ] Test FunctionArityMatchShape invalid (1 test)
- [ ] Test ProtocolComplianceShape valid (1 test)
- [ ] Test ProtocolComplianceShape invalid (1 test)
- [ ] Test integration with Validator engine (1 test)

## Dependencies & Prerequisites

**External Libraries:**
- ✅ SPARQL.ex (version 0.3.11) - Already installed
- ✅ RDF.ex - Already installed

**Internal Dependencies:**
- ✅ SHACL.Model.SPARQLConstraint - Already implemented
- ✅ SHACL.Model.ValidationResult - Already implemented
- ✅ SHACL.Validator - Needs minor update to call SPARQL validator

## Risk Analysis

**Low Risk:**
- SPARQL.ex library is mature and well-tested
- Simple SPARQL queries (SELECT only, no updates)
- Existing pattern in ElixirOntologies.Graph.query/3 to follow

**Medium Risk:**
- Blank node identifier serialization must match SPARQL expectations
- SPARQL query syntax errors in elixir-shapes.ttl would cause failures
- Performance: SPARQL queries could be slow on large graphs

**Mitigations:**
- Test blank node substitution thoroughly
- Validate all 3 SPARQL constraints from elixir-shapes.ttl
- Add query timeout handling (future enhancement)

## Performance Considerations

- SPARQL queries execute against full data graph (could be large)
- Consider caching query results for repeated validations (future)
- Parallel validation already implemented in Validator engine (Phase 11.2.2)

## Future Enhancements (Not in Scope)

- Query timeout configuration
- Query result caching
- SPARQL ASK query support (in addition to SELECT)
- sh:prefixes handling for custom namespace prefixes
- Performance profiling and optimization

## Notes

- SPARQL constraints are evaluated at NodeShape level, not PropertyShape level
- Each query result row = one validation violation
- $this must be replaced before query execution (SPARQL.ex doesn't handle placeholders)
- Message templates from SPARQLConstraint.message become ValidationResult.message
