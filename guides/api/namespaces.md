# Namespaces Reference

This guide documents the RDF vocabulary namespaces provided by the `ElixirOntologies.NS` module for building RDF statements with RDF.ex.

## Overview

The namespace module provides pre-defined vocabulary terms for all four ontology layers plus commonly used standard RDF namespaces. Terms are available as Elixir atoms and IRIs for use in graph construction.

**Module**: `ElixirOntologies.NS`

## Elixir Ontology Namespaces

### Core Namespace

**Module**: `ElixirOntologies.NS.Core`
**Base IRI**: `https://w3id.org/elixir-code/core#`
**Prefix**: `core:`

The core namespace provides foundational AST primitives for representing source code:

**Classes**:
- `CodeElement` - Abstract base for all code constructs
- `SourceLocation` - Location within a source file
- `SourceFile` - Physical source file (.ex, .exs)
- `Repository` - Version control repository
- `CommitRef` - Reference to a specific commit

**AST Nodes**:
- `ASTNode`, `Expression`, `Statement`, `Declaration`

**Literals**:
- `Literal`, `AtomLiteral`, `IntegerLiteral`, `FloatLiteral`
- `StringLiteral`, `CharlistLiteral`, `BinaryLiteral`
- `ListLiteral`, `TupleLiteral`, `MapLiteral`
- `KeywordListLiteral`, `SigilLiteral`, `RangeLiteral`

**Operators**:
- `OperatorExpression`, `UnaryOperator`, `BinaryOperator`
- `ArithmeticOperator`, `ComparisonOperator`, `LogicalOperator`
- `PipeOperator`, `MatchOperator`, `CaptureOperator`

**Control Flow**:
- `IfExpression`, `CaseExpression`, `CondExpression`
- `WithExpression`, `TryExpression`, `ReceiveExpression`

**Patterns**:
- `Pattern`, `LiteralPattern`, `VariablePattern`, `WildcardPattern`
- `TuplePattern`, `ListPattern`, `MapPattern`, `StructPattern`

**Scopes**:
- `Scope`, `ModuleScope`, `FunctionScope`, `BlockScope`
- `Binding`, `Closure`

---

### Structure Namespace

**Module**: `ElixirOntologies.NS.Structure`
**Base IRI**: `https://w3id.org/elixir-code/structure#`
**Prefix**: `struct:`

Elixir-specific code structure constructs:

**Modules**:
- `Module`, `NestedModule`
- `ModuleAlias`, `Import`, `Require`, `Use`

**Module Attributes**:
- `ModuleAttribute`, `RegisteredAttribute`, `AccumulatingAttribute`
- `DocAttribute`, `ModuledocAttribute`, `FunctionDocAttribute`
- `DeprecatedAttribute`, `SinceAttribute`, `CompileAttribute`

**Functions** (identity: Module + Name + Arity):
- `Function`, `PublicFunction`, `PrivateFunction`, `GuardFunction`
- `FunctionClause`, `FunctionHead`, `FunctionBody`
- `Parameter`, `DefaultParameter`, `PatternParameter`
- `ReturnExpression`

**Type System**:
- `TypeSpec`, `PublicType`, `PrivateType`, `OpaqueType`
- `FunctionSpec`, `CallbackSpec`, `MacroCallbackSpec`
- `TypeExpression`, `UnionType`, `FunctionType`

**Protocols**:
- `Protocol`, `ProtocolFunction`
- `ProtocolImplementation`, `DerivedImplementation`, `AnyImplementation`

**Behaviours**:
- `Behaviour`, `CallbackFunction`
- `RequiredCallback`, `OptionalCallback`
- `BehaviourImplementation`, `DefaultImplementation`

**Structs**:
- `Struct`, `StructField`, `EnforcedKey`, `Exception`

**Macros**:
- `Macro`, `PublicMacro`, `PrivateMacro`
- `QuotedExpression`, `UnquoteExpression`
- `MacroExpansion`, `MacroInvocation`

---

### OTP Namespace

**Module**: `ElixirOntologies.NS.OTP`
**Base IRI**: `https://w3id.org/elixir-code/otp#`
**Prefix**: `otp:`

OTP runtime patterns and BEAM abstractions:

**Processes**:
- `Process`, `ProcessIdentity`, `PID`
- `RegisteredName`, `LocalRegistration`, `GlobalRegistration`
- `ProcessMailbox`, `ProcessLinks`, `ProcessMonitor`

**OTP Behaviours**:
- `OTPBehaviour`, `GenServer`, `GenServerImplementation`
- `SupervisorBehaviour`, `Application`, `GenStatem`

**Higher-Level Abstractions**:
- `Agent`, `Task`, `TaskSupervisor`
- `Registry`, `DynamicSupervisor`, `PartitionSupervisor`

**Supervision**:
- `Supervisor`, `SupervisionTree`, `ChildSpec`
- `SupervisionStrategy` (`:OneForOne`, `:OneForAll`, `:RestForOne`)
- `RestartStrategy` (`:Permanent`, `:Temporary`, `:Transient`)

**GenServer Callbacks**:
- `GenServerCallback`, `InitCallback`
- `HandleCallCallback`, `HandleCastCallback`, `HandleInfoCallback`
- `TerminateCallback`, `CodeChangeCallback`

**Messages**:
- `GenServerMessage`, `Call`, `Cast`, `Info`
- `GenServerReply`, `ReplyTuple`, `NoReplyTuple`, `StopTuple`

**Distributed Erlang**:
- `Node`, `Cluster`, `NodeConnection`
- `DistributedProcess`, `RemoteCall`, `GlobalProcess`

**Storage**:
- `ETSTable`, `DETSTable`
- `ETSTableType` (`:SetTable`, `:OrderedSetTable`, `:BagTable`)
- `ETSAccessType` (`:PublicTable`, `:ProtectedTable`, `:PrivateTable`)

**Telemetry**:
- `TelemetryEvent`, `TelemetryHandler`, `TelemetrySpan`

---

### Evolution Namespace

**Module**: `ElixirOntologies.NS.Evolution`
**Base IRI**: `https://w3id.org/elixir-code/evolution#`
**Prefix**: `evo:`

Temporal provenance and code evolution (PROV-O aligned):

**Code Versions (prov:Entity)**:
- `CodeVersion`, `ModuleVersion`, `FunctionVersion`
- `CodebaseSnapshot`, `ReleaseArtifact`, `BeamFile`

**Development Activities (prov:Activity)**:
- `DevelopmentActivity`, `Commit`, `MergeCommit`
- `Refactoring`, `FunctionExtraction`, `Rename`
- `BugFix`, `FeatureAddition`, `Deprecation`
- `Compilation`, `Release`, `Deployment`, `HotCodeUpgrade`

**Agents (prov:Agent)**:
- `DevelopmentAgent`, `Developer`, `Team`
- `Bot`, `LLMAgent`, `CISystem`

**Change Tracking**:
- `ChangeSet`, `Addition`, `Modification`, `Removal`
- `SignatureChange`, `BodyChange`, `DocumentationChange`
- `DependencyChange`, `DependencyAddition`, `DependencyUpdate`

**Version Control**:
- `Repository`, `Branch`, `Tag`, `PullRequest`

**Roles (prov:Role)**:
- `DevelopmentRole`
- `:Author`, `:Committer`, `:Reviewer`, `:Approver`, `:Maintainer`

**Semantic Versioning**:
- `SemanticVersion`, `BreakingChange`, `MinorChange`, `PatchChange`

**Temporal Modeling**:
- `TemporalExtent`, `ValidTime`, `TransactionTime`

---

## Standard Namespaces

The following standard RDF namespaces are re-exported for convenience:

| Namespace | Module | Base IRI |
|-----------|--------|----------|
| RDF | `RDF.NS.RDF` | `http://www.w3.org/1999/02/22-rdf-syntax-ns#` |
| RDFS | `RDF.NS.RDFS` | `http://www.w3.org/2000/01/rdf-schema#` |
| OWL | `RDF.NS.OWL` | `http://www.w3.org/2002/07/owl#` |
| XSD | `RDF.NS.XSD` | `http://www.w3.org/2001/XMLSchema#` |
| SKOS | `RDF.NS.SKOS` | `http://www.w3.org/2004/02/skos/core#` |
| PROV | `ElixirOntologies.NS.PROV` | `http://www.w3.org/ns/prov#` |
| BFO | `ElixirOntologies.NS.BFO` | `http://purl.obolibrary.org/obo/` |
| IAO | `ElixirOntologies.NS.IAO` | `http://purl.obolibrary.org/obo/IAO_` |
| DC | `ElixirOntologies.NS.DC` | `http://purl.org/dc/elements/1.1/` |
| DCTerms | `ElixirOntologies.NS.DCTerms` | `http://purl.org/dc/terms/` |

---

## Key Functions

### `NS.prefix_map/0`

Returns a complete prefix map for RDF serialization:

```elixir
ElixirOntologies.NS.prefix_map()
# Returns:
[
  core: "https://w3id.org/elixir-code/core#",
  struct: "https://w3id.org/elixir-code/structure#",
  otp: "https://w3id.org/elixir-code/otp#",
  evo: "https://w3id.org/elixir-code/evolution#",
  rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
  rdfs: "http://www.w3.org/2000/01/rdf-schema#",
  owl: "http://www.w3.org/2002/07/owl#",
  xsd: "http://www.w3.org/2001/XMLSchema#",
  skos: "http://www.w3.org/2004/02/skos/core#",
  prov: "http://www.w3.org/ns/prov#",
  bfo: "http://purl.obolibrary.org/obo/",
  iao: "http://purl.obolibrary.org/obo/IAO_",
  dc: "http://purl.org/dc/elements/1.1/",
  dcterms: "http://purl.org/dc/terms/"
]
```

Use with serializers:

```elixir
graph
|> RDF.Turtle.write_string!(prefixes: ElixirOntologies.NS.prefix_map())
```

### `NS.base_iri/1`

Returns the base IRI for a given prefix atom:

```elixir
ElixirOntologies.NS.base_iri(:core)
# => "https://w3id.org/elixir-code/core#"

ElixirOntologies.NS.base_iri(:struct)
# => "https://w3id.org/elixir-code/structure#"

ElixirOntologies.NS.base_iri(:prov)
# => "http://www.w3.org/ns/prov#"
```

---

## Usage Patterns

### Basic Triple Construction

```elixir
alias ElixirOntologies.NS.{Core, Structure}

# Create IRIs for code elements
module_iri = RDF.iri("https://example.org/code#MyApp.Users")
function_iri = RDF.iri("https://example.org/code#MyApp.Users/get_user/1")

# Build an RDF graph
graph = RDF.Graph.new()
|> RDF.Graph.add({module_iri, RDF.type(), Structure.Module})
|> RDF.Graph.add({module_iri, Structure.moduleName(), "MyApp.Users"})
|> RDF.Graph.add({module_iri, Structure.containsFunction(), function_iri})
|> RDF.Graph.add({function_iri, RDF.type(), Structure.PublicFunction})
|> RDF.Graph.add({function_iri, Structure.functionName(), "get_user"})
|> RDF.Graph.add({function_iri, Structure.arity(), 1})
```

### Source Location Tracking

```elixir
alias ElixirOntologies.NS.Core

loc_iri = RDF.iri("https://example.org/code#loc_123")
file_iri = RDF.iri("https://example.org/code#lib_users_ex")

graph
|> RDF.Graph.add({function_iri, Core.hasSourceLocation(), loc_iri})
|> RDF.Graph.add({loc_iri, RDF.type(), Core.SourceLocation})
|> RDF.Graph.add({loc_iri, Core.startLine(), 15})
|> RDF.Graph.add({loc_iri, Core.endLine(), 25})
|> RDF.Graph.add({loc_iri, Core.inSourceFile(), file_iri})
```

### OTP Process Modeling

```elixir
alias ElixirOntologies.NS.OTP

server_iri = RDF.iri("https://example.org/runtime#user_cache")

graph
|> RDF.Graph.add({server_iri, RDF.type(), OTP.GenServer})
|> RDF.Graph.add({server_iri, OTP.registeredAtom(), "UserCache"})
|> RDF.Graph.add({server_iri, OTP.hasStrategy(), OTP.OneForOne})
```

### Evolution Provenance

```elixir
alias ElixirOntologies.NS.Evolution

commit_iri = RDF.iri("https://example.org/commits#abc123")
version_iri = RDF.iri("https://example.org/versions#v1.2.0")

graph
|> RDF.Graph.add({commit_iri, RDF.type(), Evolution.Commit})
|> RDF.Graph.add({commit_iri, Evolution.commitHash(), "abc123def..."})
|> RDF.Graph.add({commit_iri, Evolution.authoredAt(), ~U[2025-01-15 10:30:00Z]})
|> RDF.Graph.add({version_iri, Evolution.wasGeneratedBy(), commit_iri})
```

### Using PROV-O Terms

```elixir
alias ElixirOntologies.NS.{Evolution, PROV}

graph
|> RDF.Graph.add({entity_iri, PROV.wasAttributedTo(), developer_iri})
|> RDF.Graph.add({activity_iri, PROV.wasAssociatedWith(), developer_iri})
|> RDF.Graph.add({entity_iri, PROV.wasGeneratedBy(), activity_iri})
```

---

## Serialization Example

Complete workflow from graph construction to Turtle output:

```elixir
alias ElixirOntologies.NS
alias ElixirOntologies.NS.{Core, Structure}

# Build graph
graph = RDF.Graph.new(prefixes: NS.prefix_map())
|> RDF.Graph.add({
  RDF.iri("https://example.org/code#MyApp.Users"),
  RDF.type(),
  Structure.Module
})
|> RDF.Graph.add({
  RDF.iri("https://example.org/code#MyApp.Users"),
  Structure.moduleName(),
  "MyApp.Users"
})

# Serialize to Turtle
turtle = RDF.Turtle.write_string!(graph)

# Output:
# @prefix struct: <https://w3id.org/elixir-code/structure#> .
#
# <https://example.org/code#MyApp.Users>
#     a struct:Module ;
#     struct:moduleName "MyApp.Users" .
```

---

## Vocabulary Term Access

Namespace terms can be accessed in several ways:

```elixir
alias ElixirOntologies.NS.Structure

# As an atom function call (returns RDF.IRI)
Structure.Module
# => ~I<https://w3id.org/elixir-code/structure#Module>

# Get the base IRI
Structure.__base_iri__()
# => "https://w3id.org/elixir-code/structure#"

# List all terms (if vocabulary loaded from file)
Structure.__terms__()
# => [:Module, :Function, :Protocol, ...]
```

---

## See Also

- [Core Ontology Guide](../core.md) - AST primitives and foundational classes
- [Structure Ontology Guide](../structure.md) - Modules, functions, protocols
- [OTP Ontology Guide](../otp.md) - Processes, supervision, GenServer
- [Evolution Ontology Guide](../evolution.md) - Provenance and version tracking
