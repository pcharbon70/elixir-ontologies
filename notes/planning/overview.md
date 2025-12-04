# Elixir Ontologies Knowledge Graph Tooling - Implementation Plan

## Overview

This plan details the implementation of tooling for reading, writing, and populating knowledge graphs based on the Elixir ontologies defined in this repository. The tooling will analyze Elixir source code (single files or entire projects) and create RDF instances conforming to the ontology schemas.

**Key Design Decisions:**
- **IRI Strategy**: Path-based (e.g., `ex:MyApp.Users/get_user/2`)
- **Analysis Approach**: Source AST (via `Code.string_to_quoted/2`)
- **Scope**: All constructs from all ontologies (280+ classes)
- **Output Format**: Turtle (.ttl)

**Dependencies:**
- `{:rdf, "~> 2.0"}` - Marcel Otto's RDF.ex library
- `{:sparql, "~> 0.3"}` - SPARQL query support (optional)

## Phase Overview

| Phase | Focus | Sections | Estimated Tasks |
|-------|-------|----------|-----------------|
| [Phase 1](phase-01.md) | Core Infrastructure & RDF Foundation | 4 | ~45 |
| [Phase 2](phase-02.md) | AST Parsing Infrastructure | 3 | ~35 |
| [Phase 3](phase-03.md) | Core Extractors (elixir-core.ttl) | 6 | ~60 |
| [Phase 4](phase-04.md) | Structure Extractors (elixir-structure.ttl) | 4 | ~55 |
| [Phase 5](phase-05.md) | Advanced Extractors (protocols, behaviours, structs) | 3 | ~35 |
| [Phase 6](phase-06.md) | OTP Extractors (elixir-otp.ttl) | 4 | ~40 |
| [Phase 7](phase-07.md) | Evolution & Git Integration | 3 | ~30 |
| [Phase 8](phase-08.md) | Project Analysis | 3 | ~35 |
| [Phase 9](phase-09.md) | Mix Tasks & CLI | 2 | ~20 |
| [Phase 10](phase-10.md) | Validation & Final Testing | 2 | ~20 |

**Total: ~375 tasks across 10 phases**

## Critical Files to Modify/Create

### Existing Files to Modify
- `mix.exs` - Add RDF dependencies
- `lib/elixir_ontologies.ex` - Add public API

### New Files to Create
```
lib/elixir_ontologies/
├── config.ex
├── graph.ex
├── iri.ex
├── namespaces.ex
├── validator.ex
├── analyzer/
│   ├── ast_walker.ex
│   ├── change_tracker.ex
│   ├── file_analyzer.ex
│   ├── file_reader.ex
│   ├── git.ex
│   ├── location.ex
│   ├── matchers.ex
│   ├── parser.ex
│   ├── project.ex
│   ├── project_analyzer.ex
│   └── source_url.ex
├── extractors/
│   ├── behaviour.ex
│   ├── block.ex
│   ├── comprehension.ex
│   ├── control_flow.ex
│   ├── function.ex
│   ├── literal.ex
│   ├── macro.ex
│   ├── module.ex
│   ├── operator.ex
│   ├── parameter.ex
│   ├── pattern.ex
│   ├── protocol.ex
│   ├── reference.ex
│   ├── struct.ex
│   ├── type_spec.ex
│   └── otp/
│       ├── agent_task.ex
│       ├── ets.ex
│       ├── genserver.ex
│       └── supervisor.ex
└── mix/
    └── tasks/
        ├── elixir_ontologies.analyze.ex
        └── elixir_ontologies.update.ex
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Public API (ElixirOntologies)               │
│  analyze_file/2  │  analyze_project/2  │  update_graph/2        │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                        Analyzers                                 │
│  FileAnalyzer  │  ProjectAnalyzer  │  ChangeTracker             │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                        Extractors                                │
│  Module │ Function │ TypeSpec │ Protocol │ Behaviour │ OTP      │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                     AST Infrastructure                           │
│  Parser  │  ASTWalker  │  Matchers  │  Location                 │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      RDF Infrastructure                          │
│  Graph  │  Namespaces  │  IRI  │  Config                        │
└─────────────────────────────────────────────────────────────────┘
```
