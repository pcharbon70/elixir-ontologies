# Phase 12.3.3: Agent Builder Planning Document

## 1. Problem Statement

Phase 12.3.2 completed the Supervisor Builder, handling OTP supervision patterns. Now we need to implement the Agent Builder to complete the trio of fundamental OTP pattern builders (GenServer, Supervisor, Agent).

**The Challenge**: The Agent extractor (`ElixirOntologies.Extractors.OTP.Agent`) produces rich structured data about Agent usage patterns, but this data needs to be converted to RDF triples that conform to the `elixir-otp.ttl` ontology while correctly representing Agent's simple state-wrapper semantics.

**Current State**:
- Agent extractor exists and produces `Agent.t()` structs for Agent detection
- Agent extractor tracks `AgentCall.t()` structs for Agent function calls
- GenServer and Supervisor builders established OTP builder patterns
- OTP ontology (`elixir-otp.ttl`) defines Agent as `:OTPBehaviour` subclass
- Builder infrastructure exists but no Agent-specific builder

**Why Agents Are Important**:
Agents provide simple state abstraction in Elixir/OTP applications, enabling:
- Lightweight state management without full GenServer complexity
- Synchronous state access via Agent.get/2
- State updates via Agent.update/2 and Agent.get_and_update/2
- Simplified concurrency for shared state
- Built atop GenServer but with simpler API

Understanding Agent patterns is critical for:
- Analyzing simple state management in applications
- Distinguishing between Agent and GenServer usage patterns
- Tracking state access patterns (get vs update operations)
- Understanding lightweight OTP process usage
- Validating appropriate Agent usage vs over-engineering

**The Gap**: We need to:
1. Generate IRIs for Agent implementations (using module IRI pattern)
2. Create `rdf:type` triples for Agent and OTPBehaviour classes
3. Build Agent-specific properties (detection method, use options)
4. Track Agent function calls (start, start_link, get, update, etc.)
5. Link Agent implementations to OTP behaviour infrastructure
6. Handle three detection methods (use, @behaviour, function calls only)
7. Support use options from `use Agent, opts`
8. Track Agent API usage patterns
9. Link to source locations for Agent usage
10. Differentiate Agent from GenServer in RDF

## 2. Solution Overview

Create an **Agent Builder** that transforms Agent extractor results into RDF triples representing OTP Agent patterns.

### 2.1 Core Functionality

The builder will provide one main function:
- `build_agent/3` - Transform Agent detection into RDF

Following the established builder pattern:
```elixir
{agent_iri, triples} = AgentBuilder.build_agent(agent_info, module_iri, context)
```

### 2.2 Builder Pattern

**Agent Implementation Building**:
```elixir
def build_agent(agent_info, module_iri, context) do
  # Agent IRI is the module IRI (Agent implementation IS a module)
  agent_iri = module_iri

  # Build all triples
  triples =
    [
      # Core Agent triples
      build_type_triple(agent_iri),
      build_implements_otp_behaviour_triple(agent_iri)
    ] ++
      build_location_triple(agent_iri, agent_info.location, context)

  {agent_iri, List.flatten(triples) |> Enum.uniq()}
end
```

## 3. Technical Details

### 3.1 Agent Extractor Output Format

**Agent Detection Result**:
```elixir
%ElixirOntologies.Extractors.OTP.Agent{
  # How Agent was detected
  detection_method: :use | :behaviour | :function_call,

  # Options from `use Agent, opts` (nil if via @behaviour or function_call)
  use_options: keyword() | nil,

  # List of Agent function calls found in module
  function_calls: [AgentCall.t()],

  # Source location of Agent declaration
  location: SourceLocation.t() | nil,

  # Additional metadata
  metadata: map()
}
```

### 3.2 OTP Ontology Classes and Properties

**Agent Class**:
```turtle
:Agent a owl:Class ;
    rdfs:label "Agent"@en ;
    rdfs:comment """Simple state wrapper around a process."""@en ;
    rdfs:subClassOf :OTPBehaviour .
```

**Key Properties**:
- `:implementsOTPBehaviour` - Links module to Agent behaviour
- `core:hasSourceLocation` - Links to source location

### 3.3 IRI Generation Strategy

**Agent Implementation IRI**:
- Pattern: Same as module IRI (Agent implementation IS a module)
- Example: `https://w3id.org/elixir-code#MyApp.Counter`
- Rationale: One module can only implement one Agent pattern

### 3.4 RDF Triple Patterns

**Agent Implementation Triples**:
```turtle
# Type triple
<#MyApp.Counter> a otp:Agent .

# Implements OTP Behaviour
<#MyApp.Counter> otp:implementsOTPBehaviour otp:Agent .

# Source location (if available)
<#MyApp.Counter> core:hasSourceLocation <#file/lib/counter.ex/L5-10> .
```

## 4. Success Criteria

### 4.1 Functional Requirements
- [ ] `build_agent/3` generates correct RDF triples for Agent implementations
- [ ] Handles all three detection methods (use, @behaviour, function_call)
- [ ] Generates `rdf:type otp:Agent` triples
- [ ] Generates `otp:implementsOTPBehaviour` triples
- [ ] Handles source location linking when available
- [ ] Handles nil locations gracefully
- [ ] Agent IRI uses module IRI pattern (same as module)
- [ ] No duplicate triples in output

### 4.2 Edge Cases
- [ ] Handles Agent with use options
- [ ] Handles Agent without use options
- [ ] Handles @behaviour Agent (no use options)
- [ ] Handles function_call detection (no use or @behaviour)
- [ ] Handles Agent in nested modules
- [ ] Handles missing location information

### 4.3 Testing (15+ Tests Required)
- [ ] Test basic Agent with use detection
- [ ] Test Agent with @behaviour detection
- [ ] Test Agent with function_call detection
- [ ] Test Agent with use options
- [ ] Test Agent without use options
- [ ] Test IRI pattern (Agent IRI = module IRI)
- [ ] Test nested module names
- [ ] Test no duplicate triples
- [ ] Test with source location
- [ ] Test without source location
- [ ] Test all expected triples present
- [ ] Test integration scenarios

**Target: 15+ tests**

## 5. Implementation Plan

### Phase 1: Research (✅ COMPLETE)
- [✅] Read Agent extractor to understand data structures
- [✅] Check OTP ontology for Agent properties
- [✅] Review GenServer and Supervisor builders for patterns

### Phase 2: Core Agent Builder
- [ ] Create `lib/elixir_ontologies/builders/otp/agent_builder.ex`
- [ ] Implement `build_agent/3`
- [ ] Implement helper functions

### Phase 3: Testing
- [ ] Create `test/elixir_ontologies/builders/otp/agent_builder_test.exs`
- [ ] Implement core tests (15+ tests)
- [ ] Verify all tests pass

### Phase 4: Documentation
- [ ] Write summary document
- [ ] Ask for permission to commit

## 6. References

### Code References
- Agent Extractor: `lib/elixir_ontologies/extractors/otp/agent.ex`
- GenServer Builder: `lib/elixir_ontologies/builders/otp/genserver_builder.ex`
- Supervisor Builder: `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
- OTP Ontology: `priv/ontologies/elixir-otp.ttl`

---

**Status**: Planning Complete, Ready for Implementation
