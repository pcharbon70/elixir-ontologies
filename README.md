# Elixir Code Ontology

An OWL ontology for modeling Elixir code structure, OTP runtime patterns, and code evolution. Designed for semantic code analysis and LLM-based code understanding.

## Purpose

Existing code ontologies (CodeOntology, SEON, GraphGen4Code) target object-oriented languages and cannot represent functional programming constructs like:

- Functions as first-class entities with arity-based identity
- Pattern matching and guard conditions
- Protocol-based polymorphism (distinct from interface inheritance)
- Actor/process models with supervision hierarchies
- Macro expansion and compile-time metaprogramming

This ontology fills that gap by modeling Elixir's unique semantics while aligning with established foundational ontologies (BFO, IAO) and provenance standards (PROV-O).

## Features

- **Parse Elixir source code** into RDF knowledge graphs
- **Model functional programming constructs** (first-class functions, pattern matching, guards)
- **Represent OTP runtime patterns** (GenServer, Supervisor, Agent, Task, ETS)
- **Track code evolution** with git provenance and changesets
- **Validate graphs** using SHACL constraints
- **Export to multiple formats** (Turtle, N-Triples, JSON-LD)

## Quick Start

```bash
# Add to your mix.exs
def deps do
  [
    {:elixir_ontologies, "~> 1.0"}
  ]
end

# Analyze your project
mix elixir_ontologies.analyze --output my_project.ttl

# Query the knowledge graph
mix elixir_ontologies.kg load my_project.ttl
mix elixir_ontologies.kg query "SELECT ?m WHERE { ?m a struct:Module }"
```

## Documentation

### User Guides

Comprehensive guides for using the Elixir Ontologies system:

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/users/getting-started.md) | Installation, usage, and configuration |
| [Ontology Overview](guides/users/overview.md) | High-level ontology architecture |
| [Core Ontology](guides/users/ontology/core.md) | AST primitives and foundational classes |
| [Structure Ontology](guides/users/ontology/structure.md) | Modules, functions, protocols, structs |
| [OTP Ontology](guides/users/ontology/otp.md) | GenServer, Supervisor, Agent, Task patterns |
| [Evolution Ontology](guides/users/ontology/evolution.md) | Version tracking and provenance |
| [Shapes Ontology](guides/users/ontology/shapes.md) | SHACL validation constraints |

### Developer Guides

For extending the system with new constructs:

| Guide | Description |
|-------|-------------|
| [Architecture Overview](guides/developer/architecture.md) | System architecture and data flow |
| [Getting Started](guides/developer/getting-started.md) | Adding new extractors, builders, and validation rules |
| [Extractors Component](guides/developer/components/extractors.md) | Extractor patterns and implementation |
| [Builders Component](guides/developer/components/builders.md) | Builder patterns and RDF generation |
| [Validators Component](guides/developer/components/validators.md) | SHACL validation orchestration |
| [SHACL Component](guides/developer/components/shacl.md) | SHACL model and serialization |

## Ontology Components

### elixir-core.ttl

Language-agnostic foundation for representing source code. Provides:

- **AST primitives**: `Expression`, `Statement`, `Declaration`, `ASTNode`
- **Literal types**: atoms, integers, strings, lists, tuples, maps, binaries, sigils
- **Operators**: arithmetic, comparison, logical, pipe, match, capture
- **Control flow**: `if`, `case`, `cond`, `with`, `try`, `receive`
- **Pattern matching**: literal, variable, wildcard, pin, tuple, list, map, struct, binary patterns
- **Scoping**: module, function, and block scopes with variable bindings

Aligned with BFO (Basic Formal Ontology) - code elements are modeled as Generically Dependent Continuants.

### elixir-structure.ttl

Elixir-specific code constructs. Imports `elixir-core`. Provides:

- **Modules**: `Module`, `NestedModule`, aliases, imports, requires, use directives
- **Functions**: identified by `(Module, Name, Arity)` composite key; supports multiple clauses with pattern matching
- **Macros**: `Macro`, `QuotedExpression`, `UnquoteExpression` for metaprogramming
- **Protocols**: type-based polymorphism with `Protocol`, `ProtocolImplementation`, `@derive`
- **Behaviours**: callback contracts with `Behaviour`, `CallbackFunction`, `@behaviour`
- **Structs**: `Struct`, `StructField`, `EnforcedKey`, `Exception`
- **Type system**: `@type`, `@spec`, `@callback` with full type expression modeling
- **Module attributes**: documentation, deprecation, compile hooks

### elixir-otp.ttl

OTP runtime patterns and BEAM VM abstractions. Imports `elixir-structure`. Provides:

- **Processes**: `Process`, `PID`, registration (local, global, via Registry)
- **Supervision**: `Supervisor`, `SupervisionTree`, `ChildSpec` with strategies (one_for_one, one_for_all, rest_for_one)
- **Behaviours**: `GenServer`, `Agent`, `Task`, `Application`, `:gen_statem`
- **GenServer callbacks**: `init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`
- **Dynamic supervision**: `DynamicSupervisor`, `TaskSupervisor`, `PartitionSupervisor`
- **Storage**: `ETSTable` with table types and access control
- **Distribution**: `Node`, `Cluster`, remote calls
- **Telemetry**: events, handlers, spans

### elixir-evolution.ttl

Temporal provenance layer for tracking code changes. Imports `elixir-structure` and PROV-O. Provides:

- **Versioned entities**: `CodeVersion`, `ModuleVersion`, `FunctionVersion`, `CodebaseSnapshot`
- **Activities**: `Commit`, `Refactoring`, `BugFix`, `FeatureAddition`, `Deprecation`, `Release`, `Deployment`
- **Agents**: `Developer`, `Team`, `Bot`, `LLMAgent`, `CISystem`
- **Change tracking**: `ChangeSet`, `Addition`, `Modification`, `Removal`, `DependencyChange`
- **Version control**: `Repository`, `Branch`, `Tag`, `PullRequest`
- **Semantic versioning**: major/minor/patch with breaking change classification
- **Bitemporal modeling**: valid time (when true) vs transaction time (when recorded)

Supports RDF-star for fine-grained statement-level provenance annotations.

### elixir-shapes.ttl

SHACL constraints for data validation. Provides closed-world validation complementing OWL's open-world semantics:

- **Naming patterns**: validates Elixir naming conventions (UpperCamelCase modules, snake_case functions)
- **Required properties**: ensures functions have arity, modules have names, etc.
- **Cardinality**: functions must have ≥1 clause, protocols must define ≥1 function
- **Value constraints**: arity 0-255, valid supervision strategies, valid restart policies
- **Cross-entity consistency**: function arity matches parameter count, protocol implementations cover all functions

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Elixir Source                            │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Analysis Layer                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                │
│  │  Parser    │  │ AST Walker │  │ Matchers   │                │
│  └────────────┘  └────────────┘  └────────────┘                │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Extraction Layer                          │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌────────────┐     │
│  │  Module   │ │ Function  │ │ Control   │ │    OTP     │     │
│  │ Extractor │ │ Extractor │ │  Extract  │ │  Extractor │     │
│  └───────────┘ └───────────┘ └───────────┘ └────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Building Layer                           │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌────────────┐     │
│  │  Module   │ │ Function  │ │ Expression│ │    Type    │     │
│  │  Builder  │ │  Builder  │ │  Builder  │ │  System    │     │
│  └───────────┘ └───────────┘ └───────────┘ └────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Validation Layer                          │
│  ┌───────────┐ ┌──────────────────────────────────────────┐   │
│  │   SHACL   │ │          Validation Report               │   │
│  │ Validator │ └──────────────────────────────────────────┘   │
│  └───────────┘                                                │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                          RDF Knowledge Graph                     │
│                 (Turtle / N-Triples / JSON-LD)                  │
└─────────────────────────────────────────────────────────────────┘
```

## Namespaces

| Prefix | IRI | Ontology |
|--------|-----|----------|
| core | `https://w3id.org/elixir-code/core#` | [Core Ontology](priv/ontologies/elixir-core.ttl) |
| struct | `https://w3id.org/elixir-code/structure#` | [Structure Ontology](priv/ontologies/elixir-structure.ttl) |
| otp | `https://w3id.org/elixir-code/otp#` | [OTP Ontology](priv/ontologies/elixir-otp.ttl) |
| evo | `https://w3id.org/elixir-code/evolution#` | [Evolution Ontology](priv/ontologies/elixir-evolution.ttl) |
| shapes | `https://w3id.org/elixir-code/shapes#` | [Shapes Ontology](priv/ontologies/elixir-shapes.ttl) |

## Design Principles

1. **Arity is identity**: `String.split/2` and `String.split/3` are distinct functions, not overloads
2. **Order matters**: function clauses are ordered collections (first match wins)
3. **Protocols ≠ Behaviours**: protocols dispatch on data type; behaviours define module contracts
4. **Separation of concerns**: static structure vs runtime patterns vs temporal evolution
5. **LLM-friendly**: Turtle serialization with human-readable labels and descriptive property names

## Expression Modes

### Light Mode (Default)

Minimal storage (~500 KB per 100 functions). Only structural metadata:
- Module declarations
- Function signatures (name, arity, visibility)
- Struct definitions
- Protocol and behaviour declarations

### Full Mode

Complete AST representation (~5-20 MB per 100 functions):
- Complete function body AST
- Guard condition expressions
- Control flow structures (if, case, cond, etc.)
- All operators and literals
- Pattern matching constructs

```bash
# Light mode (default)
mix elixir_ontologies.analyze

# Full mode
mix elixir_ontologies.analyze --include-expressions
```

## Contributing

See the [Developer Getting Started Guide](guides/developer/getting-started.md) for extending the system with new constructs.

## License

MIT
