# Loading and Querying Turtle Files in IEx

This guide covers interactive exploration of RDF data using the TripleStore database engine in IEx.

## Prerequisites

Ensure `triple_store` is installed:

```elixir
iex> ElixirOntologies.KnowledgeGraph.available?()
true
```

If this returns `false`, add `triple_store` to your `mix.exs` dependencies.

## Starting an IEx Session

```bash
cd your_project
iex -S mix
```

## Loading a Turtle File

### Basic Loading

```elixir
alias ElixirOntologies.KnowledgeGraph

# Open or create a knowledge graph database
{:ok, store} = KnowledgeGraph.open("./my_kg")

# Load a single Turtle file
{:ok, stats} = KnowledgeGraph.load_files(store, ["my_ontology.ttl"])
# => {:ok, %{loaded: 1, failed: 0, triples: 1234, errors: []}}

IO.puts("Loaded #{stats.triples} triples")
```

### Loading Multiple Files

```elixir
# Load multiple files at once
{:ok, stats} = KnowledgeGraph.load_files(store, [
  "ontology/elixir-core.ttl",
  "ontology/elixir-structure.ttl",
  "ontology/elixir-otp.ttl"
])

# Load all TTL files matching a glob pattern
{:ok, stats} = KnowledgeGraph.load_glob(store, "ontology/**/*.ttl")
```

### Loading from a String

```elixir
ttl = """
@prefix ex: <http://example.org/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

ex:Alice rdf:type ex:Person ;
         ex:name "Alice" ;
         ex:knows ex:Bob .

ex:Bob rdf:type ex:Person ;
       ex:name "Bob" .
"""

{:ok, count} = KnowledgeGraph.load_string(store, ttl, :turtle)
# => {:ok, 5}
```

### Loading an RDF.Graph

```elixir
# If you have an RDF.Graph from analysis or RDF.ex
{:ok, graph} = RDF.Turtle.read_file("data.ttl")
{:ok, count} = KnowledgeGraph.load_graph(store, graph)
```

## Querying the Data

### SELECT Queries

```elixir
# Find all subjects and their types
{:ok, results} = KnowledgeGraph.query(store, """
  SELECT ?subject ?type
  WHERE {
    ?subject a ?type .
  }
  LIMIT 10
""")

# Results are a list of maps
Enum.each(results, fn row ->
  IO.puts("#{row["subject"]} is a #{row["type"]}")
end)
```

### Using Prefixes

```elixir
{:ok, results} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>

  SELECT ?module ?name
  WHERE {
    ?module a struct:Module ;
            struct:moduleName ?name .
  }
  ORDER BY ?name
""")
```

### ASK Queries

```elixir
# Check if data exists
{:ok, exists?} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  ASK { ?m a struct:Module }
""")

if exists?, do: IO.puts("Modules found!"), else: IO.puts("No modules")
```

### CONSTRUCT Queries

```elixir
# Build a subgraph
{:ok, subgraph} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>

  CONSTRUCT {
    ?func struct:functionName ?name ;
          struct:arity ?arity .
  }
  WHERE {
    ?func a struct:Function ;
          struct:functionName ?name ;
          struct:arity ?arity .
  }
""")

# subgraph is an RDF.Graph
IO.puts(RDF.Turtle.write_string!(subgraph))
```

## Inspecting Results

### Viewing Statistics

```elixir
{:ok, count} = KnowledgeGraph.stats(store)
IO.puts("Database contains #{count} triples")
```

### Exploring Data Structure

```elixir
# See all predicates in use
{:ok, results} = KnowledgeGraph.query(store, """
  SELECT DISTINCT ?predicate
  WHERE { ?s ?predicate ?o }
  ORDER BY ?predicate
""")

# See all types
{:ok, results} = KnowledgeGraph.query(store, """
  SELECT DISTINCT ?type (COUNT(?s) as ?count)
  WHERE { ?s a ?type }
  GROUP BY ?type
  ORDER BY DESC(?count)
""")

Enum.each(results, fn row ->
  IO.puts("#{row["type"]}: #{row["count"]} instances")
end)
```

### Finding All Properties of a Subject

```elixir
subject_iri = "https://w3id.org/elixir-code/structure#Module"

{:ok, results} = KnowledgeGraph.query(store, """
  SELECT ?predicate ?object
  WHERE {
    <#{subject_iri}> ?predicate ?object .
  }
""")
```

## Exporting Data

### Export to RDF.Graph

```elixir
graph = KnowledgeGraph.export(store)
IO.puts("Exported graph with #{RDF.Graph.triple_count(graph)} triples")
```

### Export to File

```elixir
:ok = KnowledgeGraph.export_file(store, "backup.ttl")
# Format is determined by file extension
:ok = KnowledgeGraph.export_file(store, "backup.nt")  # N-Triples
```

## Complete Interactive Session Example

```elixir
alias ElixirOntologies.KnowledgeGraph

# 1. Open the database
{:ok, store} = KnowledgeGraph.open("./code_analysis")

# 2. Load analyzed Elixir code
{:ok, stats} = KnowledgeGraph.load_glob(store, ".ttl-list/**/*.ttl")
IO.puts("Loaded #{stats.triples} triples from #{stats.loaded} files")

# 3. Find all modules
{:ok, modules} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  SELECT ?name WHERE { ?m a struct:Module ; struct:moduleName ?name }
  ORDER BY ?name
""")

IO.puts("Found #{length(modules)} modules:")
modules |> Enum.take(5) |> Enum.each(&IO.puts("  - #{&1["name"]}"))

# 4. Find functions with high arity
{:ok, funcs} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  SELECT ?module ?func ?arity
  WHERE {
    ?f a struct:Function ;
       struct:functionName ?func ;
       struct:arity ?arity ;
       struct:definedIn ?m .
    ?m struct:moduleName ?module .
    FILTER(?arity > 4)
  }
  ORDER BY DESC(?arity)
  LIMIT 10
""")

IO.puts("\nFunctions with arity > 4:")
Enum.each(funcs, fn row ->
  IO.puts("  #{row["module"]}.#{row["func"]}/#{row["arity"]}")
end)

# 5. Clean up
:ok = KnowledgeGraph.close(store)
```

## Working with Query Results

### Extracting Values

```elixir
{:ok, results} = KnowledgeGraph.query(store, "SELECT ?name WHERE { ?m struct:moduleName ?name }")

# Get all names as a list
names = Enum.map(results, & &1["name"])

# Filter results
phoenix_modules = Enum.filter(results, fn row ->
  String.starts_with?(row["name"], "Phoenix.")
end)
```

### Converting to Maps

```elixir
{:ok, results} = KnowledgeGraph.query(store, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>
  SELECT ?name ?arity ?visibility
  WHERE {
    ?f a struct:Function ;
       struct:functionName ?name ;
       struct:arity ?arity .
    OPTIONAL { ?f struct:visibility ?visibility }
  }
""")

# Transform to structured data
functions = Enum.map(results, fn row ->
  %{
    name: row["name"],
    arity: String.to_integer(row["arity"]),
    visibility: row["visibility"] || "public"
  }
end)
```

## Error Handling

### Using query!/3 for Exceptions

```elixir
# Raises on error instead of returning {:error, reason}
results = KnowledgeGraph.query!(store, "SELECT * WHERE { ?s ?p ?o } LIMIT 5")
```

### Handling Load Errors

```elixir
{:ok, stats} = KnowledgeGraph.load_files(store, ["file1.ttl", "missing.ttl"])

if stats.failed > 0 do
  IO.puts("Failed to load #{stats.failed} files:")
  Enum.each(stats.errors, fn {:error, path, reason} ->
    IO.puts("  #{path}: #{inspect(reason)}")
  end)
end
```

## Performance Tips

### Set Query Timeout

```elixir
# Default is 30 seconds, increase for complex queries
{:ok, results} = KnowledgeGraph.query(store, sparql, timeout: 60_000)
```

### Use LIMIT for Exploration

```elixir
# Always limit exploratory queries
{:ok, sample} = KnowledgeGraph.query(store, """
  SELECT * WHERE { ?s ?p ?o } LIMIT 100
""")
```

### Batch Loading

```elixir
# For large files, adjust batch size
{:ok, stats} = KnowledgeGraph.load_files(store, files, batch_size: 5000)
```

## Closing the Database

Always close when done to release resources:

```elixir
:ok = KnowledgeGraph.close(store)
```

Only one process can have the database open at a time.

## Common SPARQL Patterns

### Count Entities

```sparql
SELECT (COUNT(?m) as ?count)
WHERE { ?m a struct:Module }
```

### Find by Name Pattern

```sparql
SELECT ?name
WHERE {
  ?m struct:moduleName ?name .
  FILTER(CONTAINS(?name, "Controller"))
}
```

### Aggregate by Property

```sparql
SELECT ?visibility (COUNT(*) as ?count)
WHERE { ?f struct:visibility ?visibility }
GROUP BY ?visibility
```

### Path Traversal

```sparql
SELECT ?module ?function ?param
WHERE {
  ?m struct:containsFunction ?f ;
     struct:moduleName ?module .
  ?f struct:functionName ?function ;
     struct:hasParameter ?p .
  ?p struct:parameterName ?param .
}
```

## Related Guides

- [Knowledge Graph Guide](../knowledge-graph.md) - Full API reference
- [Querying RDF Graphs](./querying.md) - In-memory graph querying
- [Getting Started](./getting-started.md) - Basic setup
