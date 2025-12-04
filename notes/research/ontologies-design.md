# Designing an OWL Ontology for Elixir Code Structure and Architecture

Modeling Elixir's unique semantics—arity-based function identity, pattern matching, macros, and OTP supervision trees—requires a fundamentally new approach to code ontologies. Existing work like CodeOntology and SEON targets object-oriented languages and cannot represent first-class functions, process hierarchies, or the BEAM runtime model. This report synthesizes research on ontology engineering, RDF-star temporal modeling, and LLM integration to inform the design of an Elixir-focused code ontology that captures functional programming semantics, tracks code evolution with provenance, and can be consumed by LLMs for code understanding.

## No existing ontology addresses functional programming constructs

The landscape of code ontologies reveals a significant gap for functional programming languages. **CodeOntology**, the most comprehensive effort, models Java source code at AST-level detail but is explicitly designed for object-oriented paradigms—methods are bound to classes, and there's no representation for higher-order functions, closures, or pattern matching. **SEON (Software Engineering Ontology Network)** provides a modular architecture grounded in UFO foundational ontology but operates at high abstraction levels (Code, Program, Software System) without internal structure details. **GraphGen4Code** from IBM handles Python at scale (1.3M files, 2B+ triples) but remains class/method-centric.

The critical missing concepts across all surveyed ontologies include:

- Functions as first-class entities with arity as intrinsic identity
- Pattern matching and guard conditions in function dispatch
- Closures capturing lexical environments
- Protocol-based polymorphism (distinct from interface inheritance)
- Actor/process models with supervision relationships
- Macro expansion and compile-time metaprogramming

For Elixir ontology development, the Erlang Abstract Format and Elixir AST structures provide valuable semantic foundations. Elixir's homoiconic representation uses nested 3-tuples `{function_name, metadata, arguments}` accessible via `Code.string_to_quoted!/1`, while OTP behaviors like GenServer have well-defined callback contracts that can inform the ontology structure.

## Elixir's unique constructs create specific modeling challenges

### Arity must be a first-class property, not metadata

In Elixir, function identity is the triple `(Module, Name, Arity)`—`Enum.map/2` and `Enum.map/3` are fundamentally different functions, not overloaded versions. Default arguments compound this: `def foo(a, b \\ 1)` compiles to *both* `foo/1` and `foo/2`. The ontology must model:

```turtle
code:enumMap2 a code:Function ;
    code:belongsTo code:Enum ;
    code:hasName "map" ;
    code:hasArity 2 ;
    code:hasSignature "(Enumerable.t(), (element -> any)) -> list" .

code:enumMap3 a code:Function ;
    code:belongsTo code:Enum ;
    code:hasName "map" ;
    code:hasArity 3 ;
    code:hasSignature "(Enumerable.t(), acc, (element, acc -> acc)) -> acc" .
```

### Function clauses require ordered sequences with pattern constraints

Multiple function definitions with the same name and arity that differ only by head patterns are matched in source order—first match wins. This necessitates an **ordered collection** rather than an unordered set:

```turtle
code:factorial a code:Function ;
    code:hasArity 1 ;
    code:hasClauses (
        [ a code:FunctionClause ;
          code:clauseOrder 1 ;
          code:hasPattern [ a code:LiteralPattern ; code:value 0 ] ;
          code:hasBody [ code:returnsLiteral 1 ] ]
        [ a code:FunctionClause ;
          code:clauseOrder 2 ;
          code:hasPattern [ a code:VariablePattern ; code:binds "n" ] ;
          code:hasGuard [ code:expression "n > 0" ] ;
          code:hasBody [ code:expression "n * factorial(n - 1)" ] ]
    ) .
```

### Protocols and behaviours represent distinct polymorphism mechanisms

Elixir's **protocols** provide type-based dispatch on the first argument (similar to type classes), while **behaviours** define callback contracts that modules implement. Protocol implementations can be scattered across files and are consolidated at compile time:

```turtle
code:SizeProtocol a code:Protocol ;
    code:definesProtocolFunction code:sizeFunction ;
    code:fallbackToAny false .

code:SizeForBitString a code:ProtocolImplementation ;
    code:implementsProtocol code:SizeProtocol ;
    code:forDataType code:BitString ;
    code:definesFunction [ code:body "byte_size(string)" ] .
```

### Macros operate on quoted expressions at compile time

Elixir macros receive AST (quoted expressions) and return AST, enabling powerful metaprogramming. The ontology must distinguish between macro definition and expansion:

```turtle
code:unlessMacro a code:Macro ;
    code:receivesQuotedArgs true ;
    code:returnsQuotedExpression true ;
    code:expandsTo code:IfExpression .  # Links to expansion pattern
```

### Module attributes have dual compile-time/runtime semantics

Attributes like `@moduledoc` are evaluated at compile time, with some persisting to runtime via `Module.register_attribute/3`. The ontology must capture accumulating vs. replacing semantics and the distinction between built-in semantic attributes (`@spec`, `@behaviour`) and user-defined constants.

## OTP runtime patterns warrant a separate but linked ontology layer

The static code structure and OTP runtime semantics serve different purposes and should be modeled in separate but interconnected ontology modules.

### Supervision trees form typed hierarchies with restart semantics

```turtle
code:AppSupervisor a code:Supervisor ;
    code:hasStrategy code:OneForOne ;
    code:maxRestarts 3 ;
    code:maxSeconds 5 ;
    code:hasChildren (
        [ a code:ChildSpec ;
          code:childId "worker1" ;
          code:childModule code:MyWorker ;
          code:restart code:Permanent ;
          code:type code:Worker ]
        [ a code:ChildSpec ;
          code:childId "subsupervisor" ;
          code:childModule code:SubSupervisor ;
          code:restart code:Permanent ;
          code:type code:Supervisor ]
    ) .
```

### GenServer, Agent, Task represent standard OTP abstractions

These behaviours define specific callback contracts. GenServer manages explicit state through `handle_call/3`, `handle_cast/2`, and `handle_info/2`, while Agent wraps state with functional accessors. The ontology should model both the behaviour contracts and their implementations:

```turtle
code:GenServerBehaviour a code:Behaviour ;
    code:definesCallback [
        code:callbackName "handle_call" ;
        code:arity 3 ;
        code:signature "(request, from, state) -> {:reply, reply, new_state} | ..." ] ;
    code:definesCallback [
        code:callbackName "init" ;
        code:arity 1 ;
        code:signature "(args) -> {:ok, state} | {:stop, reason}" ] .
```

### Process identity decouples from PIDs through Registry

Processes can be named via atoms, `{:via, Registry, key}` tuples, or `{:global, name}`. The ontology should represent this naming indirection:

```turtle
code:myWorkerProcess a code:Process ;
    code:registeredName "my_worker" ;
    code:registeredVia code:MyRegistry ;
    code:implementsBehaviour code:GenServerBehaviour .
```

## RDF-star with PROV-O enables fine-grained provenance tracking

### RDF-star provides statement-level annotations without reification overhead

Traditional RDF reification requires 4+ additional triples per annotated statement. **RDF-star** (included in RDF 1.2) enables direct statement annotation with quoted triples:

```turtle
# RDF-star annotation
<<code:function1 code:hasReturnType code:String>> 
    prov:wasGeneratedBy code:commit_abc123 ;
    code:addedInVersion "2.0" ;
    prov:generatedAtTime "2024-03-15"^^xsd:dateTime .
```

Current tool support is strong: **GraphDB** (v9.2+), **Stardog**, **Apache Jena**, and **RDF4J** all support RDF-star and SPARQL-star queries. The query capabilities enable temporal provenance queries:

```sparql
SELECT ?function ?property ?modifiedBy WHERE {
  <<?function ?property ?value>> prov:wasGeneratedBy ?commit .
  ?commit prov:wasAssociatedWith ?modifiedBy ;
          prov:endedAtTime ?time .
  FILTER(?time > "2024-01-01"^^xsd:date)
}
```

### Named graphs complement RDF-star for version snapshots

Use **named graphs** for grouping (version snapshots, file boundaries) and **RDF-star** for individual statement metadata:

```trig
GRAPH code:codebase_v2.1.0 {
    code:UserService code:hasMethod code:getUserById .
    
    <<code:getUserById code:hasParameter code:userId>>
        prov:wasGeneratedBy code:commit_abc123 ;
        code:validFrom "2024-03-01"^^xsd:date .
}

code:codebase_v2.1.0 a code:CodeVersion ;
    prov:generatedAtTime "2024-03-15T14:00:00"^^xsd:dateTime ;
    code:previousVersion code:codebase_v2.0.0 .
```

### PROV-O captures complete activity chains

The W3C PROV-O ontology models **Entities** (code artifacts), **Activities** (commits, refactoring), and **Agents** (developers, CI systems):

```turtle
code:MyClass_v2 a prov:Entity, code:Module ;
    prov:wasRevisionOf code:MyClass_v1 ;
    prov:wasGeneratedBy code:commit_def456 ;
    prov:wasAttributedTo code:alice .

code:commit_def456 a prov:Activity, code:Commit ;
    prov:wasAssociatedWith code:alice ;
    prov:used code:MyClass_v1 ;
    prov:qualifiedAssociation [
        prov:agent code:alice ;
        prov:hadRole code:Author
    ] ;
    code:commitHash "def456789abc" ;
    code:commitMessage "Refactored for performance" .
```

### Bitemporal modeling captures both valid time and transaction time

For complete code evolution tracking, record **when facts were true in the codebase** (valid time) and **when they were recorded** (transaction time):

```turtle
<<code:function1 code:signature "void process(String)">>
    code:validFrom "2024-01-15"^^xsd:date ;
    code:validTo "2024-06-01"^^xsd:date ;
    prov:generatedAtTime "2024-01-15T09:30:00"^^xsd:dateTime ;
    code:supersededAt "2024-06-01T14:00:00"^^xsd:dateTime .
```

### Delta-based versioning enables efficient storage

Rather than full snapshots, store changesets between versions:

```turtle
code:changeset_v1_to_v2 a code:ChangeSet ;
    code:addition <<code:MyModule code:hasFunction code:newFunction>> ;
    code:deletion <<code:MyModule code:hasFunction code:deprecatedFunction>> ;
    prov:wasGeneratedBy code:commit_abc123 .
```

## LLMs reason best over Turtle-serialized knowledge graphs

### Turtle format outperforms alternatives for LLM comprehension

Research from LLM-KG-Bench demonstrates that **Turtle syntax has the strongest resemblance to natural language**, aligning well with LLM interaction patterns. GPT-4 and Claude show proficiency with Turtle for parsing, comprehension, and generation. Token efficiency matters for context windows—emerging formats like TOON claim **~60% token reduction** for structured data.

### GraphRAG patterns enhance code understanding

Microsoft's **GraphRAG** approach creates community summaries from knowledge graphs using Leiden detection, enabling both **global search** (holistic questions using summaries) and **local search** (specific entity queries via neighbor traversal). For code understanding, this supports queries like "What are the main patterns in this codebase?" alongside "What functions call this method?"

### Subgraph selection requires balancing structure and content

Research indicates optimal retrieval uses **α ∈ [0.3-0.7]** to balance question-based retrieval (maintains connectivity) with subquestion-based retrieval (higher precision). At α ≈ 0.5, systems achieve **85-90% connected graphs** with high precision.

### Ontology design should optimize for LLM consumption

Key recommendations for LLM-friendly ontologies:

- Use **human-readable rdfs:labels** without language tags
- Employ **descriptive property names** following natural language patterns (e.g., `hasMethod`, `dependsOn`)
- Provide **explicit prefix definitions** at the start
- Design for **modularity** to fit context window limits
- Include **entity descriptions** in the graph for context

```turtle
PREFIX code: <https://example.org/code/>

code:UserAuthService a code:Module ;
    rdfs:label "User Authentication Service" ;
    rdfs:comment "Handles user login, logout, and session management" ;
    code:hasFunction code:validateCredentials, code:generateToken ;
    code:dependsOn code:DatabaseConnection, code:CryptoUtils .
```

## Align with BFO and IAO for foundational rigor

### BFO provides the strongest foundation for software artifacts

**Basic Formal Ontology (BFO)** is an ISO standard (ISO/IEC 21838-2) with 350+ ontologies in OBO Foundry. Combined with the **Information Artifact Ontology (IAO)**, it provides a well-grounded framework for modeling code as Information Content Entities:

```
BFO:Generically Dependent Continuant → Source code content
IAO:Information Content Entity → Programs, functions (abstract)
BFO:Object → Physical files (concrete realizations)
BFO:Process → Compilation, execution
```

DOLCE patterns can supplement BFO for complex conceptual modeling, particularly agent/artifact relations relevant to developer attribution.

### Target OWL 2 DL with EL-compatible modules

Code structures require OWL 2 DL expressivity for:

- **Property chains**: `containsStatement ∘ hasExpression → containsExpression`
- **Cardinality restrictions**: `IfStatement hasExactly 1 condition`
- **Inverse properties**: `containedIn` as inverse of `contains`
- **Transitive properties**: `isAncestorOf` for AST traversal

Design EL-compatible modules where possible for efficient classification. Use **SHACL** for closed-world validation constraints rather than trying to express everything in OWL.

### Adopt modular three-layer architecture

```
Layer 1: PRIMITIVE (code-core)
├── Basic AST constructs: Statement, Expression, Declaration
├── Language-agnostic foundations
└── Imports: BFO, IAO

Layer 2: COMPLEX (code-elixir-structure)
├── Elixir-specific: Module, Function, Protocol, Behaviour
├── Pattern matching, guards, macros
└── Imports: Layer 1

Layer 3: RUNTIME (code-otp)
├── GenServer, Supervisor, Agent, Task
├── Supervision trees, process relationships
└── Imports: Layers 1 & 2

Layer 4: TEMPORAL (code-evolution)
├── PROV-O integration
├── Version tracking, changesets
└── Imports: Layers 1-3
```

### Follow consistent naming conventions

| Element | Convention | Example |
|---------|------------|---------|
| Classes | UpperCamelCase | `FunctionClause`, `ProtocolImplementation` |
| Object Properties | lowerCamelCase verb phrases | `hasParameter`, `implementsProtocol` |
| Data Properties | lowerCamelCase | `arityValue`, `sourceText` |
| IRIs | w3id.org with semantic versioning | `https://w3id.org/elixir-code/core/1.0.0` |

## Proposed ontology architecture

Based on this research, the Elixir code ontology should follow this structure:

### Core module (elixir-code-core)

```turtle
@prefix code: <https://w3id.org/elixir-code/core/> .
@prefix bfo: <http://purl.obolibrary.org/obo/> .

code:CodeElement a owl:Class ;
    rdfs:subClassOf bfo:BFO_0000031 .  # Generically Dependent Continuant

code:Module a owl:Class ;
    rdfs:subClassOf code:CodeElement .

code:Function a owl:Class ;
    rdfs:subClassOf code:CodeElement ;
    owl:hasKey (code:belongsTo code:hasName code:hasArity) .  # Composite key

code:hasArity a owl:DatatypeProperty ;
    rdfs:domain code:Function ;
    rdfs:range xsd:nonNegativeInteger .

code:FunctionClause a owl:Class ;
    rdfs:subClassOf code:CodeElement .

code:hasClauses a owl:ObjectProperty ;
    rdfs:domain code:Function ;
    rdfs:range rdf:List .  # Ordered list of FunctionClause
```

### Protocol and behaviour module

```turtle
code:Protocol a owl:Class ;
    rdfs:subClassOf code:CodeElement .

code:ProtocolImplementation a owl:Class ;
    owl:equivalentClass [
        owl:intersectionOf (
            code:CodeElement
            [ owl:onProperty code:implementsProtocol ; owl:cardinality 1 ]
            [ owl:onProperty code:forDataType ; owl:cardinality 1 ]
        )
    ] .

code:Behaviour a owl:Class ;
    rdfs:subClassOf code:CodeElement .

code:CallbackSpec a owl:Class ;
    rdfs:subClassOf code:CodeElement .
```

### OTP runtime module (elixir-otp)

```turtle
@prefix otp: <https://w3id.org/elixir-code/otp/> .

otp:Process a owl:Class .

otp:Supervisor a owl:Class ;
    rdfs:subClassOf otp:Process .

otp:SupervisionStrategy a owl:Class .
otp:OneForOne a otp:SupervisionStrategy .
otp:OneForAll a otp:SupervisionStrategy .
otp:RestForOne a otp:SupervisionStrategy .

otp:ChildSpec a owl:Class ;
    rdfs:subClassOf [
        owl:onProperty otp:restart ;
        owl:someValuesFrom otp:RestartStrategy
    ] .
```

### Temporal/provenance module (elixir-evolution)

```turtle
@prefix evo: <https://w3id.org/elixir-code/evolution/> .
@prefix prov: <http://www.w3.org/ns/prov#> .

evo:CodeVersion a owl:Class ;
    rdfs:subClassOf prov:Entity .

evo:Commit a owl:Class ;
    rdfs:subClassOf prov:Activity .

evo:ChangeSet a owl:Class ;
    rdfs:subClassOf prov:Entity .
```

## Conclusion: A novel approach to functional code representation

Designing an OWL ontology for Elixir requires breaking from object-oriented assumptions that pervade existing code ontologies. The key insights from this research are:

**Arity-based function identity** demands treating arity as an intrinsic property forming a composite key with module and name, not as optional metadata. **Ordered clause sequences** with pattern constraints need RDF collections preserving order. **Protocol/behaviour separation** requires distinct modeling for type-based dispatch versus callback contracts. **Macro expansion** necessitates representing both the macro definition and its compile-time transformation.

For temporal modeling, **RDF-star combined with named graphs** provides the optimal balance: named graphs for version snapshots and logical grouping, RDF-star for fine-grained statement provenance. **PROV-O** supplies the vocabulary for complete activity chains linking code changes to agents and commits.

For LLM consumption, **Turtle serialization** with human-readable labels and descriptive property names enables effective reasoning. **GraphRAG patterns** with community summaries support both holistic and specific queries. **Modular ontology design** respects context window limits while maintaining semantic richness.

The recommended architecture aligns with **BFO/IAO** foundations, uses **OWL 2 DL** expressivity with SHACL validation, and separates concerns into core structure, OTP runtime, and temporal evolution modules. This design positions the ontology to serve both as a rigorous semantic model of Elixir code and as an effective knowledge source for LLM-powered code understanding and generation systems.
