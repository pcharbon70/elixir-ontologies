# Phase 13.1.1: Builder Orchestrator Planning Document

## 1. Problem Statement

Phase 12 completed all individual RDF builders (Module, Function, Clause, Protocol, Behaviour, Struct, Type System, GenServer, Supervisor, Agent, Task). Now we need an orchestrator to coordinate these builders and generate complete RDF graphs from Elixir code analysis results.

**The Challenge**: Individual builders work in isolation. We need a unified system that:
- Coordinates all builders to generate complete RDF graphs
- Enables parallel execution since code is static (read-only)
- Manages builder dependencies (e.g., Module IRI needed by Function builder)
- Aggregates triples from all builders into a single graph

**Current State**:
- 11 individual builders exist with consistent APIs
- Each builder takes extractor results and returns `{iri, triples}`
- No coordination layer exists
- Parallel execution not yet leveraged

## 2. Solution Overview

Create a **Builder Orchestrator** that:

1. **Coordinates Builders**: Invokes appropriate builders based on extraction results
2. **Enables Parallelism**: Uses `Task.async_stream` for parallel builder execution where safe
3. **Aggregates Results**: Combines all triples into unified RDF graph
4. **Manages Dependencies**: Ensures required IRIs are available to dependent builders

### 2.1 Builder Categories and Dependencies

**Level 1 - Independent (can run in parallel)**:
- ModuleBuilder (no dependencies)

**Level 2 - Depend on Module IRI (can run in parallel after Level 1)**:
- FunctionBuilder (needs module_iri)
- ProtocolBuilder (needs module_iri)
- BehaviourBuilder (needs module_iri)
- StructBuilder (needs module_iri)
- TypeSystemBuilder (needs module_iri)
- GenServerBuilder (needs module_iri)
- SupervisorBuilder (needs module_iri)
- AgentBuilder (needs module_iri)
- TaskBuilder (needs module_iri)

**Level 3 - Depend on Function IRI (can run in parallel after Level 2)**:
- ClauseBuilder (needs function_iri)

### 2.2 Parallel Execution Strategy

```
Phase 1: Build Module (single)
    ↓
Phase 2: Build Functions, Protocols, Behaviours, Structs, Types, OTP (parallel)
    ↓
Phase 3: Build Clauses (parallel, depends on function IRIs)
    ↓
Aggregate all triples into RDF.Graph
```

## 3. Technical Details

### 3.1 Orchestrator API

```elixir
defmodule ElixirOntologies.Builders.Orchestrator do
  @spec build_module_graph(module_analysis_result(), Context.t()) ::
        {:ok, RDF.Graph.t()} | {:error, term()}
  def build_module_graph(analysis, context)

  @spec build_module_graph(module_analysis_result(), Context.t(), keyword()) ::
        {:ok, RDF.Graph.t()} | {:error, term()}
  def build_module_graph(analysis, context, opts)
end
```

### 3.2 Options

- `:parallel` - Enable/disable parallel execution (default: true)
- `:timeout` - Timeout for parallel tasks (default: 5000ms)
- `:include` - List of builders to include (default: all)
- `:exclude` - List of builders to exclude (default: [])

### 3.3 Input Structure

The orchestrator expects analysis results with these fields:
- `module` - Module extraction result
- `functions` - List of function extraction results
- `protocols` - List of protocol extraction results (optional)
- `behaviours` - List of behaviour extraction results (optional)
- `structs` - List of struct extraction results (optional)
- `types` - List of type definition results (optional)
- `genservers` - List of GenServer extraction results (optional)
- `supervisors` - List of Supervisor extraction results (optional)
- `agents` - List of Agent extraction results (optional)
- `tasks` - List of Task extraction results (optional)

## 4. Success Criteria

- [✅] Orchestrator coordinates all 11 builders
- [✅] Parallel execution enabled for independent builders
- [✅] Single module analysis generates complete RDF graph
- [✅] Handles missing/optional extraction results gracefully
- [✅] **24 tests passing** (target: 15+, achieved: 160%)

## 5. Implementation Plan

### Phase 1: Research (✅ COMPLETE)
- [✅] List all existing builders
- [✅] Understand builder APIs and dependencies

### Phase 2: Design (✅ COMPLETE)
- [✅] Define orchestrator architecture
- [✅] Plan parallel execution strategy

### Phase 3: Implementation (✅ COMPLETE)
- [✅] Create `lib/elixir_ontologies/builders/orchestrator.ex`
- [✅] Implement `build_module_graph/2` and `build_module_graph/3`
- [✅] Add parallel execution with Task.async_stream
- [✅] Aggregate triples into RDF.Graph

### Phase 4: Testing (✅ COMPLETE)
- [✅] Create comprehensive test suite (24 tests)
- [✅] Test parallel execution
- [✅] Test edge cases

### Phase 5: Documentation (✅ COMPLETE)
- [✅] Write summary document
- [ ] Ask for permission to commit

## 6. References

- Builder files: `lib/elixir_ontologies/builders/*.ex`
- Context: `lib/elixir_ontologies/builders/context.ex`
- Helpers: `lib/elixir_ontologies/builders/helpers.ex`

---

**Status**: ✅ COMPLETE - Ready to Commit
