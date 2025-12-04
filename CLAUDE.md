# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is developing an OWL ontology for modeling Elixir code structure and architecture. The ontology captures functional programming semantics, tracks code evolution with provenance, and is designed for LLM consumption.

## Ontology Architecture

Four-layer modular architecture with explicit import dependencies:

```
elixir-core.ttl          → Base AST primitives, BFO/IAO alignment
    ↓
elixir-structure.ttl     → Elixir-specific: Module, Function, Protocol, Behaviour, Macro
    ↓
elixir-otp.ttl           → OTP runtime: GenServer, Supervisor, Agent, Task, ETS
    ↓
elixir-evolution.ttl     → PROV-O integration, version tracking, changesets

elixir-shapes.ttl        → SHACL validation constraints (cross-cutting)
```

Each layer imports the previous via `owl:imports`. Changes to core classes cascade upward.

## Key Design Decisions

- **Function identity**: Composite key `(Module, Name, Arity)` via `owl:hasKey` - arity is intrinsic, not metadata
- **Function clauses**: Ordered via `rdf:List` preserving pattern-match order (first match wins)
- **Protocols vs Behaviours**: Protocols use type-based dispatch on first argument; Behaviours define callback contracts
- **Temporal tracking**: RDF-star for statement-level provenance, named graphs for version snapshots
- **Validation**: OWL axioms for open-world reasoning, SHACL shapes for closed-world constraints

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Classes | UpperCamelCase | `FunctionClause`, `ProtocolImplementation` |
| Object Properties | lowerCamelCase verb phrases | `hasParameter`, `implementsProtocol` |
| Data Properties | lowerCamelCase | `arityValue`, `sourceText` |
| IRIs | w3id.org namespace | `https://w3id.org/elixir-code/{module}#` |

## Validation

SHACL shapes in `elixir-shapes.ttl` validate:
- Module/function naming patterns (regex constraints)
- Required properties (arity, module membership, etc.)
- Cardinality constraints (e.g., function must have ≥1 clause)
- Cross-module consistency (e.g., arity matches parameter count)

## External Dependencies

- **BFO** (`http://purl.obolibrary.org/obo/`) - Basic Formal Ontology for foundational classes
- **IAO** (`http://purl.obolibrary.org/obo/IAO_`) - Information Artifact Ontology
- **PROV-O** (`http://www.w3.org/ns/prov#`) - W3C Provenance ontology
- **SHACL** (`http://www.w3.org/ns/shacl#`) - Shapes Constraint Language

## Commit Guidelines

- NEVER mention Claude or any AI assistance in commit messages