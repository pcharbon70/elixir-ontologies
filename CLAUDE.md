# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is developing an OWL ontology for modeling Elixir code structure and architecture. The ontology aims to capture functional programming semantics, track code evolution with provenance, and be consumable by LLMs for code understanding.

## Architecture

The ontology follows a modular four-layer architecture:

1. **code-core** - Language-agnostic AST primitives (Statement, Expression, Declaration), imports BFO/IAO
2. **code-elixir-structure** - Elixir-specific constructs (Module, Function, Protocol, Behaviour, pattern matching, guards, macros)
3. **code-otp** - OTP runtime patterns (GenServer, Supervisor, Agent, Task, supervision trees)
4. **code-evolution** - Temporal modeling with PROV-O integration, version tracking, changesets

## Key Design Decisions

- **Function identity**: Represented as composite key of `(Module, Name, Arity)` - arity is intrinsic, not metadata
- **Function clauses**: Modeled as ordered RDF collections preserving pattern-match order
- **Protocols vs Behaviours**: Distinct modeling - protocols for type-based dispatch, behaviours for callback contracts
- **Temporal tracking**: RDF-star for statement-level provenance, named graphs for version snapshots
- **Serialization**: Turtle format for LLM consumption with human-readable labels

## Standards and Foundations

- **OWL 2 DL** expressivity with EL-compatible modules where possible
- **BFO** (Basic Formal Ontology) and **IAO** (Information Artifact Ontology) alignment
- **PROV-O** for provenance modeling
- **SHACL** for closed-world validation constraints
- **IRI convention**: `https://w3id.org/elixir-code/{module}/{version}`

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Classes | UpperCamelCase | `FunctionClause`, `ProtocolImplementation` |
| Object Properties | lowerCamelCase verb phrases | `hasParameter`, `implementsProtocol` |
| Data Properties | lowerCamelCase | `arityValue`, `sourceText` |
- NEVER mention Claude or any AI assistance in ANY commit message