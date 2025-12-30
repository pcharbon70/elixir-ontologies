# Knowledge Graph Guide

**Module**: `ElixirOntologies.KnowledgeGraph`
**Mix Task**: `mix elixir_ontologies.kg`
**Dependency**: `triple_store` (optional)

## Overview

The Knowledge Graph module provides persistent storage and SPARQL querying capabilities for Elixir code ontologies. It wraps the embedded `triple_store` database, allowing you to:

- Load analyzed Elixir projects into a persistent RDF store
- Query code structure using SPARQL
- Combine ontologies from multiple packages for cross-project analysis
- Export knowledge graphs to standard RDF formats

This is an **optional feature** that requires the `triple_store` dependency.

## Installation

Add `triple_store` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:elixir_ontologies, "~> 0.1.0"},
    {:triple_store, path: "../triple_store"}  # or from hex when published
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

Verify installation:

```elixir
iex> ElixirOntologies.KnowledgeGraph.available?()
true
```

## Quick Start

### Loading Data via Mix Task

```bash
# Load a single Turtle file
mix elixir_ontologies.kg load --db ./my_kg ontology.ttl

# Load multiple files
mix elixir_ontologies.kg load --db ./my_kg file1.ttl file2.ttl file3.ttl

# Load with glob patterns
mix elixir_ontologies.kg load --db ./my_kg "ontologies/**/*.ttl"

# Load analyzed package data
mix elixir_ontologies.kg load --db ./my_kg ".ttl-list/**/*.ttl"
```

### Querying via Mix Task

```bash
# Simple SELECT query
mix elixir_ontologies.kg query --db ./my_kg \
  "PREFIX struct: <https://w3id.org/elixir-code/structure#>
   SELECT ?module WHERE { ?module a struct:Module }"

# Query from file
mix elixir_ontologies.kg query --db ./my_kg --file queries/find_genservers.sparql

# Output as JSON
mix elixir_ontologies.kg query --db ./my_kg --format json "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10"

# Output as CSV
mix elixir_ontologies.kg query --db ./my_kg --format csv "SELECT ?m WHERE { ?m a :Module }"
```

### Statistics and Export

```bash
# Show database statistics
mix elixir_ontologies.kg stats --db ./my_kg

# Export entire graph to Turtle
mix elixir_ontologies.kg export --db ./my_kg backup.ttl
```

## Programmatic API

### Opening and Closing

```elixir
alias ElixirOntologies.KnowledgeGraph

# Open (creates if missing by default)
{:ok, store} = KnowledgeGraph.open("./my_knowledge_graph")

# Open existing only (fails if missing)
{:ok, store} = KnowledgeGraph.open("./my_kg", create_if_missing: false)

# Always close when done
:ok = KnowledgeGraph.close(store)
```

### Loading RDF Data

```elixir
# Load from files
{:ok, stats} = KnowledgeGraph.load_files(store, ["ontology.ttl", "data.ttl"])
# => {:ok, %{loaded: 2, failed: 0, triples: 5432, errors: []}}

# Load with glob pattern
{:ok, stats} = KnowledgeGraph.load_glob(store, "ontologies/**/*.ttl")

# Load from string
ttl = """
@prefix ex: <http://example.org/> .
ex:alice ex:knows ex:bob .
"""
{:ok, count} = KnowledgeGraph.load_string(store, ttl, :turtle)

# Load an RDF.Graph directly
{:ok, count} = KnowledgeGraph.load_graph(store, my_graph)
```

### Querying with SPARQL

```elixir
# SELECT query - returns list of maps
{:ok, results} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  SELECT ?module ?name
  WHERE {
    ?module a struct:Module ;
            struct:moduleName ?name .
  }
  ORDER BY ?name
  LIMIT 100
""")

Enum.each(results, fn row ->
  IO.puts("Module: #{row["name"]}")
end)

# ASK query - returns boolean
{:ok, exists?} = KnowledgeGraph.query(store, """
  PREFIX otp: <https://w3id.org/elixir-code/otp#>
  ASK { ?s a otp:GenServer }
""")

# CONSTRUCT query - returns RDF.Graph
{:ok, subgraph} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  CONSTRUCT { ?m ?p ?o }
  WHERE {
    ?m a struct:Module ;
       struct:moduleName "MyApp.Core" ;
       ?p ?o .
  }
""")
```

### Pipeline Integration

Analyze a project and store directly to knowledge graph:

```elixir
# Analyze and store in one step
{:ok, result} = ElixirOntologies.analyze_to_kg("/path/to/project", "./my_kg")
# => {:ok, %{analysis: %{...}, kg_triples: 12345}}

# Or store an existing graph
{:ok, result} = ElixirOntologies.analyze("/path/to/project")
{:ok, count} = ElixirOntologies.store_graph(result.graph, "./my_kg")
```

## Example Queries

### Find All Modules

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?name
WHERE {
  ?module a struct:Module ;
          struct:moduleName ?name .
}
ORDER BY ?name
```

### Find GenServers with Their Callbacks

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>
PREFIX otp: <https://w3id.org/elixir-code/otp#>

SELECT ?module ?callback ?arity
WHERE {
  ?module a otp:GenServer ;
          struct:hasFunction ?func .
  ?func struct:functionName ?callback ;
        struct:arity ?arity .
  FILTER(?callback IN ("init", "handle_call", "handle_cast", "handle_info"))
}
ORDER BY ?module ?callback
```

### Find Functions by Arity

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?function ?arity
WHERE {
  ?func a struct:Function ;
        struct:functionName ?function ;
        struct:arity ?arity ;
        struct:definedIn ?mod .
  ?mod struct:moduleName ?module .
  FILTER(?arity > 5)
}
ORDER BY DESC(?arity)
```

### Find Protocol Implementations

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?protocol ?impl ?for_type
WHERE {
  ?impl a struct:ProtocolImplementation ;
        struct:implementsProtocol ?proto ;
        struct:forType ?for_type .
  ?proto struct:moduleName ?protocol .
}
ORDER BY ?protocol ?for_type
```

### Find Module Dependencies

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?caller ?callee (COUNT(*) as ?calls)
WHERE {
  ?func struct:definedIn ?caller_mod ;
        struct:calls ?target .
  ?target struct:definedIn ?callee_mod .
  ?caller_mod struct:moduleName ?caller .
  ?callee_mod struct:moduleName ?callee .
  FILTER(?caller != ?callee)
}
GROUP BY ?caller ?callee
ORDER BY DESC(?calls)
```

### Find Unused Functions (No Incoming Calls)

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?function ?arity
WHERE {
  ?func a struct:Function ;
        struct:functionName ?function ;
        struct:arity ?arity ;
        struct:definedIn ?mod .
  ?mod struct:moduleName ?module .

  # Exclude if any function calls this one
  FILTER NOT EXISTS {
    ?caller struct:calls ?func .
  }

  # Exclude common entry points
  FILTER(?function NOT IN ("start", "start_link", "init", "main", "run"))
}
ORDER BY ?module ?function
```

## Building a Package Knowledge Graph

Analyze multiple Hex packages and combine into a single knowledge graph:

```bash
# Analyze packages (generates .ttl files)
mix elixir_ontologies.hex_batch phoenix ecto plug jason

# Load all into knowledge graph
mix elixir_ontologies.kg load --db ./hex_packages ".ttl-list/**/*.ttl"

# Query across all packages
mix elixir_ontologies.kg query --db ./hex_packages \
  "SELECT (COUNT(*) as ?count) WHERE { ?s a <https://w3id.org/elixir-code/structure#Module> }"
```

## Format Support

### Loading

| Format | Extensions | MIME Type |
|--------|-----------|-----------|
| Turtle | `.ttl` | `text/turtle` |
| N-Triples | `.nt` | `application/n-triples` |
| N-Quads | `.nq` | `application/n-quads` |
| RDF/XML | `.rdf`, `.xml` | `application/rdf+xml` |
| TriG | `.trig` | `application/trig` |
| JSON-LD | `.jsonld` | `application/ld+json` |

Format is auto-detected from file extension. Override with `:format` option:

```elixir
KnowledgeGraph.load_files(store, ["data.txt"], format: :turtle)
```

### Export

Export format is determined by file extension:

```bash
mix elixir_ontologies.kg export --db ./my_kg output.ttl   # Turtle
mix elixir_ontologies.kg export --db ./my_kg output.nt    # N-Triples
```

## Performance Tips

### Batch Loading

For large datasets, use batch loading:

```elixir
# Default batch size is 1000 triples
{:ok, stats} = KnowledgeGraph.load_files(store, files, batch_size: 5000)
```

Via Mix task:

```bash
mix elixir_ontologies.kg load --db ./my_kg --batch-size 5000 "**/*.ttl"
```

### Query Timeout

For complex queries, increase timeout:

```elixir
{:ok, results} = KnowledgeGraph.query(store, sparql, timeout: 60_000)
```

Via Mix task:

```bash
mix elixir_ontologies.kg query --db ./my_kg --timeout 60000 "..."
```

## Troubleshooting

### "triple_store dependency not available"

Ensure `triple_store` is in your dependencies and compiled:

```bash
mix deps.get
mix deps.compile triple_store
```

### Query Returns Empty Results

1. Verify data was loaded: `mix elixir_ontologies.kg stats --db ./my_kg`
2. Check namespace prefixes match your data
3. Test with a simple query: `SELECT * WHERE { ?s ?p ?o } LIMIT 10`

### Database Locked

Only one process can have the database open at a time. Ensure you close the store:

```elixir
:ok = KnowledgeGraph.close(store)
```

## API Reference

| Function | Description |
|----------|-------------|
| `available?/0` | Check if triple_store is installed |
| `open/2` | Open or create a knowledge graph |
| `close/1` | Close and release resources |
| `load_files/3` | Load RDF files |
| `load_glob/3` | Load files matching glob pattern |
| `load_graph/2` | Load an RDF.Graph |
| `load_string/4` | Load RDF from string |
| `query/3` | Execute SPARQL query |
| `query!/3` | Execute SPARQL query, raise on error |
| `stats/1` | Get database statistics |
| `export/1` | Export as RDF.Graph |
| `export_file/3` | Export to file |
| `materialize/2` | Run OWL reasoning (if available) |

## Related Guides

- [TripleStore in IEx](./users/triple-store-iex.md) - Interactive session guide
- [Querying RDF Graphs](./users/querying.md) - In-memory graph querying
- [Hex Batch Analyzer](./users/hex-batch-analyzer.md) - Analyze multiple packages
