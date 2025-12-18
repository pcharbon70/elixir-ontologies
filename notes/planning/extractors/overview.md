# Full Ontological Extraction: Overview

This planning series covers the implementation of extractors and builders to achieve complete coverage of the Elixir ontology classes. The current implementation covers approximately 40% extractable and 17% with builders. These phases will close the gap to achieve near-complete ontological representation.

## Current State Analysis

### Ontology Class Counts
- **elixir-core.ttl**: 77 classes (literals, operators, control flow, patterns, blocks, scopes)
- **elixir-structure.ttl**: 80 classes (modules, functions, protocols, behaviours, structs, macros, types)
- **elixir-otp.ttl**: 60 classes (process, GenServer, Supervisor, Agent, Task, ETS, distributed)
- **elixir-evolution.ttl**: 53 classes (PROV-O integration, versions, commits, agents)
- **Total**: ~270 classes

### Existing Extractors (29)
- Module, Function, Clause, Parameter, Guard, Pattern
- Protocol, Behaviour, Struct, Macro, Attribute
- TypeDefinition, TypeExpression, FunctionSpec
- Literal, Operator, Block, Comprehension, ControlFlow
- Quote, Reference, ReturnExpression
- OTP: GenServer, Supervisor, Agent, Task, ETS

### Existing Builders (14)
- ModuleBuilder, FunctionBuilder, ClauseBuilder
- ProtocolBuilder, BehaviourBuilder, StructBuilder
- TypeSystemBuilder
- OTP: GenServerBuilder, SupervisorBuilder, AgentBuilder, TaskBuilder
- Orchestrator, Context, Helpers

## Phase Roadmap

### Phase 14: Type System Completion
Completes the type system extraction and building, including union types, intersection types, generic types, remote types, type variables, and full typespec support.

### Phase 15: Metaprogramming Support
Implements extraction for macro invocations, module attribute values, quote/unquote semantics, and compile-time code generation tracking.

### Phase 16: Module Directives & Scope Analysis
Extracts alias/import/require/use relationships, tracks lexical scope, and builds the module dependency graph.

### Phase 17: Call Graph & Control Flow
Implements function call extraction, control flow analysis (if/cond/case/with), exception handling, and pipe operator chain tracking.

### Phase 18: Anonymous Functions & Closures
Extracts capture operators (&), closure variable tracking, and lambda definitions with their captured environment.

### Phase 19: Supervisor Child Specifications
Completes supervisor support with child spec extraction, restart strategies, shutdown options, and supervision tree relationships.

### Phase 20: Evolution & Provenance (PROV-O)
Integrates PROV-O provenance tracking including development activities, version control, commit provenance, and change attribution.

## Coverage Goals

| Phase | Target Classes | Extractors Added | Builders Added |
|-------|---------------|------------------|----------------|
| 14    | 20            | 4                | 2              |
| 15    | 15            | 3                | 2              |
| 16    | 12            | 4                | 2              |
| 17    | 25            | 5                | 3              |
| 18    | 8             | 2                | 1              |
| 19    | 12            | 2                | 1              |
| 20    | 30            | 6                | 4              |
| **Total** | **122**   | **26**           | **15**         |

## Success Metrics

- **Extraction Coverage**: 85%+ of ontology classes extractable from static code
- **Builder Coverage**: 70%+ of extractable classes with RDF builders
- **Test Coverage**: 100% of new extractors and builders have unit tests
- **Integration**: Full pipeline from source code to validated RDF graph

## Prerequisites

- Phase 13 (Pipeline Integration) complete
- All existing tests passing
- Familiarity with ontology layer structure

## Document Structure

Each phase document follows the established pattern:
1. Phase introduction paragraph
2. Numbered sections (X.1, X.2) with descriptive paragraphs
3. Tasks (X.1.1, X.1.2) with subtask checkboxes
4. Section unit tests
5. Phase integration tests
