# Querying RDF Graphs

This guide explains how to query and explore RDF knowledge graphs generated from Elixir code.

## Understanding the Graph

The generated RDF graph represents your codebase as interconnected nodes:

```
Module ──containsFunction──▶ Function ──hasClause──▶ Clause
   │                            │                       │
   └──hasModuleAttribute──▶    hasSpec──▶           hasParameter──▶
         Attribute              TypeSpec               Parameter
```

## Basic Graph Operations

### Loading Graphs

```elixir
alias ElixirOntologies.Graph

# From Turtle file
{:ok, graph} = RDF.Turtle.read_file("my_code.ttl")

# From analysis
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")
graph = result.graph
```

### Graph Statistics

```elixir
# Count statements (triples)
count = Graph.statement_count(graph)
IO.puts("Graph has #{count} statements")

# Get all statements
statements = Graph.statements(graph)
```

### Serialization

```elixir
# To Turtle string
turtle = Graph.to_turtle(graph)

# Write to file
File.write!("output.ttl", turtle)
```

## Querying with Pattern Matching

### Find All Modules

```elixir
alias ElixirOntologies.NS.Structure

# Using RDF.ex pattern matching
modules = RDF.Graph.query(graph, %{
  subject: nil,
  predicate: RDF.type(),
  object: Structure.Module
})

Enum.each(modules, fn %{subject: module_iri} ->
  IO.puts("Found module: #{module_iri}")
end)
```

### Find Functions in a Module

```elixir
module_iri = RDF.iri("https://example.org/code#MyApp.Users")

functions = RDF.Graph.query(graph, %{
  subject: module_iri,
  predicate: Structure.containsFunction(),
  object: nil
})

Enum.each(functions, fn %{object: func_iri} ->
  IO.puts("Function: #{func_iri}")
end)
```

### Get Property Values

```elixir
# Get module name
[%{object: name}] = RDF.Graph.query(graph, %{
  subject: module_iri,
  predicate: Structure.moduleName(),
  object: nil
})

IO.puts("Module name: #{RDF.Literal.value(name)}")
```

## SPARQL Queries

For complex queries, use SPARQL:

### Find Functions by Arity

```elixir
alias SPARQL

query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>

SELECT ?function ?name ?arity
WHERE {
  ?function a elixir:Function ;
            elixir:functionName ?name ;
            elixir:arity ?arity .
  FILTER (?arity > 3)
}
ORDER BY DESC(?arity)
"""

{:ok, results} = SPARQL.execute_query(graph, query)

Enum.each(results, fn row ->
  IO.puts("#{row["name"]}/#{row["arity"]}")
end)
```

### Find Modules with GenServer

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>
PREFIX otp: <https://w3id.org/elixir-code/otp#>

SELECT ?module ?name
WHERE {
  ?module a elixir:Module ;
          elixir:moduleName ?name ;
          elixir:usesBehaviour otp:GenServer .
}
"""

{:ok, results} = SPARQL.execute_query(graph, query)
```

### Find Public Functions

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?function ?name ?arity
WHERE {
  ?module elixir:containsFunction ?function .
  ?function elixir:functionName ?name ;
            elixir:arity ?arity ;
            elixir:visibility "public" .
}
ORDER BY ?module ?name
"""
```

### Find Functions Without Typespecs

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>

SELECT ?function ?name ?arity
WHERE {
  ?function a elixir:Function ;
            elixir:functionName ?name ;
            elixir:arity ?arity .
  FILTER NOT EXISTS { ?function elixir:hasSpec ?spec }
}
"""
```

## Provenance Queries

### Find Commits by Author

```elixir
query = """
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX evo: <https://w3id.org/elixir-code/evolution#>

SELECT ?commit ?message ?date
WHERE {
  ?commit a evo:Commit ;
          evo:commitMessage ?message ;
          prov:endedAtTime ?date .
  ?commit prov:wasAssociatedWith ?agent .
  ?agent evo:agentEmail "developer@example.com" .
}
ORDER BY DESC(?date)
LIMIT 10
"""
```

### Find Activity Types

```elixir
query = """
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX evo: <https://w3id.org/elixir-code/evolution#>

SELECT ?type (COUNT(?activity) AS ?count)
WHERE {
  ?activity a prov:Activity .
  ?activity a ?type .
  FILTER (?type != prov:Activity)
}
GROUP BY ?type
ORDER BY DESC(?count)
"""
```

### Find Code Changes

```elixir
query = """
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX evo: <https://w3id.org/elixir-code/evolution#>

SELECT ?entity ?activity ?date
WHERE {
  ?entity prov:wasGeneratedBy ?activity .
  ?activity prov:endedAtTime ?date .
}
ORDER BY DESC(?date)
LIMIT 20
"""
```

## Common Query Patterns

### Count by Type

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>

SELECT ?type (COUNT(?entity) AS ?count)
WHERE {
  ?entity a ?type .
  FILTER (STRSTARTS(STR(?type), "https://w3id.org/elixir-code/"))
}
GROUP BY ?type
ORDER BY DESC(?count)
"""

{:ok, results} = SPARQL.execute_query(graph, query)

Enum.each(results, fn row ->
  IO.puts("#{row["type"]}: #{row["count"]}")
end)
```

### Find Dependencies

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?imports
WHERE {
  ?module a elixir:Module ;
          elixir:moduleName ?name ;
          elixir:importsModule ?imports .
}
"""
```

### Find Callback Implementations

```elixir
query = """
PREFIX elixir: <https://w3id.org/elixir-code/structure#>
PREFIX otp: <https://w3id.org/elixir-code/otp#>

SELECT ?module ?callback
WHERE {
  ?module a elixir:Module ;
          elixir:implementsCallback ?callback .
  ?callback elixir:functionName ?name .
}
"""
```

## Building Query Results

### Extract Module Information

```elixir
defmodule CodeQuery do
  def get_module_info(graph, module_name) do
    query = """
    PREFIX elixir: <https://w3id.org/elixir-code/structure#>

    SELECT ?function ?name ?arity ?visibility
    WHERE {
      ?module elixir:moduleName "#{module_name}" ;
              elixir:containsFunction ?function .
      ?function elixir:functionName ?name ;
                elixir:arity ?arity .
      OPTIONAL { ?function elixir:visibility ?visibility }
    }
    ORDER BY ?name ?arity
    """

    case SPARQL.execute_query(graph, query) do
      {:ok, results} ->
        functions = Enum.map(results, fn row ->
          %{
            name: row["name"],
            arity: String.to_integer(row["arity"]),
            visibility: row["visibility"] || "public"
          }
        end)
        {:ok, functions}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Aggregate Statistics

```elixir
defmodule CodeStats do
  def calculate_stats(graph) do
    queries = %{
      modules: "SELECT (COUNT(?m) AS ?c) WHERE { ?m a elixir:Module }",
      functions: "SELECT (COUNT(?f) AS ?c) WHERE { ?f a elixir:Function }",
      public_functions: """
        SELECT (COUNT(?f) AS ?c)
        WHERE { ?f a elixir:Function ; elixir:visibility "public" }
      """,
      typespecs: "SELECT (COUNT(?s) AS ?c) WHERE { ?f elixir:hasSpec ?s }"
    }

    prefix = "PREFIX elixir: <https://w3id.org/elixir-code/structure#>\n"

    Enum.map(queries, fn {key, query} ->
      {:ok, [row]} = SPARQL.execute_query(graph, prefix <> query)
      {key, String.to_integer(row["c"])}
    end)
    |> Map.new()
  end
end
```

## Exporting Query Results

### To JSON

```elixir
{:ok, results} = SPARQL.execute_query(graph, query)

json = Jason.encode!(results, pretty: true)
File.write!("results.json", json)
```

### To CSV

```elixir
{:ok, results} = SPARQL.execute_query(graph, query)

csv = [Map.keys(hd(results)) | Enum.map(results, &Map.values/1)]
      |> Enum.map(&Enum.join(&1, ","))
      |> Enum.join("\n")

File.write!("results.csv", csv)
```

## Performance Tips

### Limit Results

Always use `LIMIT` for exploratory queries:

```sparql
SELECT ?s ?p ?o
WHERE { ?s ?p ?o }
LIMIT 100
```

### Use Specific Patterns

More specific patterns are faster:

```sparql
# Slower - scans all triples
SELECT ?f WHERE { ?f a elixir:Function }

# Faster - starts from known module
SELECT ?f WHERE {
  <https://example.org/MyModule> elixir:containsFunction ?f
}
```

### Avoid `SELECT *`

Only select needed variables:

```sparql
# Instead of SELECT *
SELECT ?name ?arity
WHERE { ?f elixir:functionName ?name ; elixir:arity ?arity }
```

## Integration with Tools

### Load into Triple Store

Export to file and load into Fuseki, Stardog, or other stores:

```bash
# Generate graph
mix elixir_ontologies.analyze -o mycode.ttl

# Load into Fuseki
curl -X POST --data-binary @mycode.ttl \
  -H "Content-Type: text/turtle" \
  http://localhost:3030/dataset/data
```

### Use with GraphDB

```elixir
# Generate N-Triples for bulk loading
ntriples = RDF.NTriples.write_string!(graph)
File.write!("mycode.nt", ntriples)

# Load via GraphDB importrdf tool
```

## Next Steps

- [Getting Started](./getting-started.md) - Basic setup
- [Code Analysis](./analyzing-code.md) - Generate graphs
- [Evolution Tracking](./evolution-tracking.md) - Query provenance
