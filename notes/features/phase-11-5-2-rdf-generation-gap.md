# Phase 11.5.2: RDF Generation Gap - Analysis and Resolution Plan

## Executive Summary

During Phase 11 Integration Tests implementation (Phase 11.5.2), a critical architectural gap was discovered: **RDF generation from extractor results is not implemented**. This blocks Phase 11 Integration Tests as originally specified and requires a new phase (Phase 12) to implement the missing RDF generation layer.

## Original Task

**Phase 11.5.2: Integration Tests** (from notes/planning/phase-11.md, lines 265-292)

Implement comprehensive integration tests validating the complete SHACL validation workflow:
- Analyze Elixir code → Generate RDF → Validate with SHACL
- Self-referential validation of this repository
- Exercise all 28 SHACL shapes
- Test OTP patterns, protocols, behaviours, type specs
- Parallel validation performance testing
- Target: 15+ integration tests

## Critical Discovery: RDF Generation Gap

### What I Found

**File**: `lib/elixir_ontologies/analyzer/file_analyzer.ex:554`

```elixir
defp build_graph(modules, _context, _config) do
  # For now, return an empty graph with module count in metadata
  # Full graph building will be implemented after basic structure is working
  graph = Graph.new()
  _ = length(modules)
  graph
end
```

The `build_graph/3` function is a **stub** that returns an empty RDF graph. This means:

- `ElixirOntologies.analyze_file/2` returns graphs with **0 triples**
- `ElixirOntologies.analyze_project/2` returns graphs with **0 triples**
- Integration tests cannot validate analyzed code (no RDF to validate)
- Only hand-written fixture files can be validated

### What Exists ✅

The codebase has comprehensive infrastructure ready for RDF generation:

1. **Complete Graph API** (`lib/elixir_ontologies/graph.ex`)
   - Graph wrapper around RDF.Graph
   - IRI generation utilities
   - Namespace definitions (core, struct, otp, evo)
   - Graph merging and manipulation

2. **20 Specialized Extractors** (Phases 1-7)
   - ModuleExtractor, FunctionExtractor, ClauseExtractor
   - ProtocolExtractor, BehaviourExtractor, StructExtractor
   - TypeExtractor, MacroExtractor, AttributeExtractor
   - GenServerExtractor, SupervisorExtractor, AgentExtractor, etc.
   - All producing well-structured domain objects

3. **4-Layer Ontology** (`priv/ontologies/`)
   - `elixir-core.ttl` - Base AST primitives
   - `elixir-structure.ttl` - Elixir-specific vocabulary
   - `elixir-otp.ttl` - OTP runtime patterns
   - `elixir-evolution.ttl` - PROV-O integration

4. **28 SHACL Shapes** (`priv/ontologies/elixir-shapes.ttl`)
   - Module, Function, Clause validation
   - Protocol, Behaviour, Struct constraints
   - OTP pattern validation
   - Evolution/provenance constraints

5. **Native SHACL Validator** (Phase 11)
   - Pure Elixir implementation
   - 66.0% W3C compliance (35/53 tests passing)
   - Support for 12 constraint components
   - Detailed violation reporting

### What's Missing ❌

The **critical missing layer** between extractors and validation:

1. **No RDF Builders** - No modules to convert extractor structs → RDF triples
2. **No Graph Generation** - `build_graph/3` stub never implemented
3. **No Triple Construction** - No code translating domain objects to ontology vocabulary
4. **No Nested Structure Handling** - No handling of clauses, parameters, guards in RDF
5. **No Source Location Metadata** - No RDF representation of provenance

## Impact Analysis

### Phase 11 Integration Tests: BLOCKED

The tests as specified require:
```elixir
{:ok, graph} = ElixirOntologies.analyze_file(file_path)
{:ok, report} = Validator.validate(graph)
```

This returns `graph` with 0 triples, so validation has nothing to validate.

**Tests Blocked:**
- ✅ SHACL Validator works (can validate fixtures)
- ❌ Cannot test end-to-end workflow (no RDF generation)
- ❌ Cannot test self-referential validation (no RDF from our code)
- ❌ Cannot validate analyzed code (only hand-written fixtures)

### Current Workaround

Phase 11 domain validation tests use **hand-written RDF fixtures**:
- `test/fixtures/domain/functions/invalid_function_arity_256.ttl`
- `test/fixtures/domain/modules/invalid_module_lowercase_name.ttl`
- etc.

These validate that SHACL shapes work correctly, but don't test the **analysis → RDF → validation** pipeline.

## Solution: Phase 12 - RDF Graph Generation

### Phase 12 Plan Created

**Location**: `~/.claude/plans/parsed-nibbling-thimble.md`

**Structure**: 6 sections, 300+ subtasks

**Sections**:
1. **Core RDF Builders** (Module, Function, Clause)
   - ModuleBuilder, FunctionBuilder, ClauseBuilder
   - Parameter lists (rdf:List), function heads/bodies
   - IRI generation, triple construction

2. **Advanced RDF Builders** (Protocol, Behaviour, Struct, Type)
   - ProtocolBuilder, BehaviourBuilder, StructBuilder
   - TypeBuilder for type system
   - Polymorphism and callback semantics

3. **OTP Pattern RDF Builders**
   - GenServerBuilder, SupervisorBuilder
   - AgentBuilder, TaskBuilder, ETSBuilder
   - Process model and supervision trees

4. **Metadata RDF Builders**
   - LocationBuilder (source locations)
   - DocBuilder (documentation, docstrings)
   - AttributeBuilder (module attributes)
   - ProvenanceBuilder (Git metadata, PROV-O)

5. **FileAnalyzer Integration**
   - Replace `build_graph/3` stub with orchestrator
   - Wire all builders into analysis pipeline
   - Error handling and performance optimization

6. **SHACL Validation & Integration Tests**
   - Validate generated RDF against SHACL shapes
   - End-to-end integration tests
   - Unblock Phase 11 Integration Tests

### Builder Architecture

**Pattern**:
```
Extractor Result → Builder Module → RDF Triples
                                  ↓
                          Graph.add_all(graph, triples)
```

**Example**:
```elixir
# ModuleBuilder.build/2
def build(module_info, context) do
  module_iri = IRI.for_module(context.base_iri, module_info.name)

  triples = [
    {module_iri, RDF.type(), NS.STRUCT.Module},
    {module_iri, NS.STRUCT.moduleName, module_info.name}
  ]

  {module_iri, triples}
end

# FileAnalyzer.build_graph/3 (after Phase 12)
defp build_graph(modules, context, config) do
  builder_context = BuilderContext.new(config)
  graph = Graph.new()

  Enum.reduce(modules, graph, fn module, acc ->
    {module_iri, triples} = ModuleBuilder.build(module, builder_context)
    Graph.add_all(acc, triples)
  end)
end
```

## Additional Phases Created

Based on the RDF generation foundation, two additional phases were planned:

### Phase 13: Enhanced Query & Analysis API

**Location**: `~/.claude/plans/phase-13-query-analysis-api.md`
**Structure**: 6 sections, 350+ subtasks

Provides query and analysis capabilities over generated RDF graphs:
- SPARQL query helpers for common patterns
- Graph traversal utilities (find callers, find implementations)
- Dependency analysis (call graphs, module dependencies)
- Code quality metrics derived from RDF
- Visualization support (GraphViz, D3.js)

### Phase 14: Temporal Analysis

**Location**: `~/.claude/plans/phase-14-temporal-analysis.md`
**Structure**: 7 sections, 400+ subtasks

Tracks code evolution over time:
- Historical graph storage (time-indexed RDF snapshots)
- Temporal query API (query code at any point in time)
- Trend analysis (metrics over time, predictions)
- Hotspot detection (frequently changed code)
- Developer analytics (contributions, ownership)
- Temporal visualization (timelines, animations)

## Revised Integration Test Approach

### Short-Term: Fixture-Based Testing

Created `test/elixir_ontologies/shacl/integration_test.exs` with tests that:

1. **Use existing domain fixtures** (where available)
   - Test SHACL validator with hand-written RDF
   - Verify violation reporting
   - Test error handling

2. **Test SHACL validation infrastructure**
   - Verify validator works correctly
   - Test parallel validation
   - Test performance

3. **Prepare for RDF generation**
   - Structure tests to easily add RDF generation when available
   - Use `analyze_and_validate/2` helper (will work after Phase 12)

### Long-Term: Full Integration Testing (Post-Phase 12)

After Phase 12 implementation, update integration tests to:

1. **Test complete workflow**
   ```elixir
   {:ok, graph} = ElixirOntologies.analyze_file(file_path)
   assert ElixirOntologies.Graph.statement_count(graph) > 0
   {:ok, report} = Validator.validate(graph)
   assert report.conforms?
   ```

2. **Self-referential validation**
   - Analyze FileAnalyzer → validate
   - Analyze SHACL Validator → validate
   - Analyze entire project → validate

3. **Exercise all SHACL shapes**
   - Generate RDF covering all 28 shapes
   - Verify no violations on valid code
   - Verify violations detected on invalid patterns

## Recommendations

### Immediate Next Steps

1. **Review Phase 12 Plan** - Validate approach and scope
2. **Implement Phase 12** - Build RDF generation layer (300+ subtasks)
3. **Update Integration Tests** - Add RDF generation testing
4. **Unblock Phase 11** - Complete Phase 11.5.2 after Phase 12

### Phase Ordering

Recommended sequence:
1. **Phase 12: RDF Graph Generation** (unblocks everything)
2. **Phase 11.5.2: Integration Tests** (now possible)
3. **Phase 13: Query & Analysis API** (builds on RDF)
4. **Phase 14: Temporal Analysis** (builds on history)

### Success Criteria

Phase 12 will be complete when:
- ✅ `analyze_file/2` returns graphs with >0 triples
- ✅ Generated RDF passes all 28 SHACL shape validations
- ✅ Self-referential validation works (analyze this repo → validate)
- ✅ All 20 extractors have corresponding RDF builders
- ✅ FileAnalyzer integration complete (`build_graph/3` implemented)
- ✅ Phase 11 Integration Tests unblocked and passing

## Conclusion

The RDF generation gap is not a bug but an **architectural incompleteness**. The infrastructure exists, but the critical middle layer (extractor results → RDF triples) was never implemented. Phase 12 provides a comprehensive plan to fill this gap and unlock the full potential of the elixir-ontologies system.

**Current State**: Analysis → Empty Graph → Validation (blocked)
**After Phase 12**: Analysis → RDF Graph → Validation (working)

This discovery has clarified the true state of the codebase and provided a clear path forward.
