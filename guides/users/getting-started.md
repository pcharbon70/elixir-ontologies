# Getting Started with Elixir Ontologies

This guide will help you get started with analyzing Elixir code and generating RDF knowledge graphs using the Elixir Ontologies library.

## What is Elixir Ontologies?

Elixir Ontologies is a tool that:

1. **Analyzes Elixir source code** - Parses modules, functions, types, and other code elements
2. **Generates RDF knowledge graphs** - Creates semantic representations of your codebase
3. **Tracks code evolution** - Integrates with Git to track how code changes over time
4. **Validates with SHACL** - Ensures generated graphs conform to defined constraints

## Installation

Add `elixir_ontologies` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elixir_ontologies, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Quick Start

### Analyze Your Project

The simplest way to analyze your Elixir project:

```bash
# Analyze current project and output to stdout
mix elixir_ontologies.analyze

# Save to a file
mix elixir_ontologies.analyze --output my_project.ttl
```

### Analyze a Single File

```bash
mix elixir_ontologies.analyze lib/my_module.ex
```

### Programmatic Usage

```elixir
alias ElixirOntologies.Pipeline

# Analyze a file
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")

# Access the generated graph
graph = result.graph

# Get statement count
count = ElixirOntologies.Graph.statement_count(graph)
IO.puts("Generated #{count} RDF statements")
```

## Understanding the Output

The generated RDF graph uses the Turtle format by default. Here's what a simple module looks like:

```turtle
@prefix elixir: <https://w3id.org/elixir-code/structure#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<https://example.org/code#MyApp.Users>
    a elixir:Module ;
    elixir:moduleName "MyApp.Users" ;
    elixir:containsFunction <https://example.org/code#MyApp.Users/get_user/1> .

<https://example.org/code#MyApp.Users/get_user/1>
    a elixir:Function ;
    elixir:functionName "get_user" ;
    elixir:arity 1 .
```

## Key Concepts

### IRIs (Identifiers)

Every code element gets a unique IRI (Internationalized Resource Identifier):

| Element | IRI Pattern | Example |
|---------|-------------|---------|
| Module | `{base}ModuleName` | `https://example.org/code#MyApp.Users` |
| Function | `{base}Module/name/arity` | `https://example.org/code#MyApp.Users/get_user/1` |
| Clause | `{function}/clause/N` | `.../get_user/1/clause/0` |

### Ontology Layers

The ontology is organized in layers:

1. **ontology/elixir-core.ttl** - Base AST primitives
2. **ontology/elixir-structure.ttl** - Elixir-specific: Module, Function, Protocol
3. **ontology/elixir-otp.ttl** - OTP runtime: GenServer, Supervisor
4. **ontology/elixir-evolution.ttl** - Version tracking with PROV-O

## Common Options

### Base IRI

Customize the base IRI for your organization:

```bash
mix elixir_ontologies.analyze --base-iri https://mycompany.org/code#
```

### Include Source Code

Include the actual source text in the graph:

```bash
mix elixir_ontologies.analyze --include-source
```

### Git Integration

By default, Git information is included. Disable it for faster analysis:

```bash
mix elixir_ontologies.analyze --no-include-git
```

### Validation

Validate output against SHACL shapes (requires pySHACL):

```bash
mix elixir_ontologies.analyze --validate
```

## Next Steps

- [Code Analysis Guide](./analyzing-code.md) - Detailed analysis options
- [Evolution Tracking Guide](./evolution-tracking.md) - Track code changes with Git
- [SHACL Validation Guide](./shacl-validation.md) - Validate your graphs
- [Querying the Graph](./querying.md) - Query your RDF data
- [TripleStore in IEx](./triple-store-iex.md) - Interactive querying with persistent storage

## Getting Help

If you encounter issues:

1. Check the [troubleshooting section](#troubleshooting) below
2. Run with `--verbose` for detailed output
3. Report issues at the project repository

## Troubleshooting

### "No source files found"

Make sure you're in an Elixir project directory with a `lib/` folder.

### Parse errors

If a file has syntax errors, it will be skipped with a warning. Fix the syntax errors and re-run.

### Memory issues with large projects

For very large codebases, analyze in batches:

```bash
# Analyze specific directories
mix elixir_ontologies.analyze lib/my_app/users/
```

### pySHACL not found

For validation, install pySHACL:

```bash
pip install pyshacl
```
