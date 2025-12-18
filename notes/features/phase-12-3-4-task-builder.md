# Phase 12.3.4: Task Builder Planning Document

## 1. Problem Statement

Phase 12.3.3 completed the Agent Builder. Now we need to implement the Task Builder to handle OTP Task patterns for lightweight concurrent operations.

**The Challenge**: The Task extractor produces structured data about Task usage, but this needs to be converted to RDF triples that conform to the `elixir-otp.ttl` ontology while correctly representing Task's async/await semantics.

**Current State**:
- Task extractor exists and produces `Task.t()` structs
- Task extractor tracks `TaskCall.t()` structs for Task function calls
- GenServer, Supervisor, and Agent builders established patterns
- OTP ontology defines Task as `:Process` subclass (not OTPBehaviour)
- Builder infrastructure exists but no Task-specific builder

**The Gap**: We need to:
1. Generate IRIs for Task implementations (using module IRI pattern)
2. Create `rdf:type` triples for Task class
3. Track Task function calls (async, await, start, etc.)
4. Handle two types: :task and :task_supervisor
5. Link to source locations for Task usage

## 2. Solution Overview

Create a **Task Builder** that transforms Task extractor results into RDF triples representing OTP Task patterns.

### 2.1 Core Functionality

The builder will provide one main function:
- `build_task/3` - Transform Task detection into RDF

Following the established builder pattern:
```elixir
{task_iri, triples} = TaskBuilder.build_task(task_info, module_iri, context)
```

### 2.2 Builder Pattern

**Task Implementation Building**:
```elixir
def build_task(task_info, module_iri, context) do
  # Task IRI is the module IRI
  task_iri = module_iri

  # Build all triples
  triples =
    [
      # Core Task triples
      build_type_triple(task_iri, task_info.type)
    ] ++
      build_location_triple(task_iri, task_info.location, context)

  {task_iri, List.flatten(triples) |> Enum.uniq()}
end
```

## 3. Technical Details

### 3.1 Task Extractor Output Format

**Task Detection Result**:
```elixir
%ElixirOntologies.Extractors.OTP.Task{
  type: :task | :task_supervisor,
  detection_method: :use | :function_call | nil,
  function_calls: [TaskCall.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

### 3.2 OTP Ontology Classes

**Task Class**:
```turtle
:Task a owl:Class ;
    rdfs:label "Task"@en ;
    rdfs:comment """Abstraction for async/await pattern."""@en ;
    rdfs:subClassOf :Process .

:TaskSupervisor a owl:Class ;
    rdfs:label "Task Supervisor"@en ;
    rdfs:subClassOf :Supervisor .
```

### 3.3 IRI Generation Strategy

**Task Implementation IRI**:
- Pattern: Same as module IRI
- Example: `https://w3id.org/elixir-code#MyApp.Workers`

### 3.4 RDF Triple Patterns

**Task Implementation**:
```turtle
<#MyApp.Workers> a otp:Task .
```

**TaskSupervisor Implementation**:
```turtle
<#MyApp.TaskSup> a otp:TaskSupervisor .
```

## 4. Success Criteria

- [ ] `build_task/3` generates correct RDF triples
- [ ] Handles both :task and :task_supervisor types
- [ ] Task IRI uses module IRI pattern
- [ ] No duplicate triples in output
- [ ] **15+ tests passing**

## 5. Implementation Plan

### Phase 1: Research (✅ COMPLETE)
- [✅] Read Task extractor to understand data structures
- [✅] Check OTP ontology for Task properties

### Phase 2: Core Task Builder
- [ ] Create `lib/elixir_ontologies/builders/otp/task_builder.ex`
- [ ] Implement `build_task/3`
- [ ] Implement helper functions

### Phase 3: Testing
- [ ] Create test file with 15+ tests
- [ ] Verify all tests pass

### Phase 4: Documentation
- [ ] Write summary document
- [ ] Ask for permission to commit

## 6. References

- Task Extractor: `lib/elixir_ontologies/extractors/otp/task.ex`
- Agent Builder: `lib/elixir_ontologies/builders/otp/agent_builder.ex`
- OTP Ontology: `priv/ontologies/elixir-otp.ttl`

---

**Status**: Planning Complete, Ready for Implementation
