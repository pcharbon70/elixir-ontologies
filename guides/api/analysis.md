# Analysis API Reference

This guide provides comprehensive documentation for the Elixir Ontologies analysis API.

## Overview

| Function | Use Case |
|----------|----------|
| `analyze_file/2` | Single file analysis |
| `analyze_project/2` | Full project analysis |
| `update_graph/2` | Incremental graph updates |
| `analyze_to_kg/3` | Direct-to-knowledge-graph pipeline |
| `store_graph/3` | Store existing graphs in knowledge graph |

## Common Options

All analysis functions accept these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:base_iri` | `String.t()` | `"https://example.org/code#"` | Base IRI for generated resources |
| `:include_source_text` | `boolean()` | `false` | Include source code text in graph |
| `:include_git_info` | `boolean()` | `true` | Include git provenance metadata |
| `:exclude_tests` | `boolean()` | `true` | Skip files in `test/` directories |

---

## analyze_file/2

Analyzes a single Elixir source file and returns an RDF knowledge graph.

```elixir
@spec analyze_file(Path.t(), keyword()) :: {:ok, Graph.t()} | {:error, term()}
```

### Examples

```elixir
# Basic usage
{:ok, graph} = ElixirOntologies.analyze_file("lib/my_app/users.ex")

# With custom base IRI
{:ok, graph} = ElixirOntologies.analyze_file(
  "lib/my_app/users.ex",
  base_iri: "https://mycompany.org/codebase#"
)

# Include source text for code search
{:ok, graph} = ElixirOntologies.analyze_file(
  "lib/my_app/users.ex",
  include_source_text: true
)
```

### Error Handling

```elixir
case ElixirOntologies.analyze_file(file_path) do
  {:ok, graph} ->
    IO.puts("Analyzed #{ElixirOntologies.Graph.statement_count(graph)} triples")

  {:error, :file_not_found} ->
    IO.puts("File not found: #{file_path}")

  {:error, {:parse_error, message}} ->
    IO.puts("Parse error: #{message}")

  {:error, reason} ->
    IO.puts("Analysis failed: #{inspect(reason)}")
end
```

---

## analyze_project/2

Analyzes an entire Mix project and returns a unified RDF knowledge graph.

```elixir
@spec analyze_project(Path.t(), keyword()) ::
  {:ok, %{graph: Graph.t(), metadata: map(), errors: list()}} | {:error, term()}
```

### Return Structure

```elixir
%{
  graph: %ElixirOntologies.Graph{},    # Unified RDF graph
  metadata: %{
    file_count: 42,                     # Number of files analyzed
    module_count: 35,                   # Number of modules found
    error_count: 2                      # Number of files with errors
  },
  errors: [{"lib/broken.ex", {:parse_error, "..."}}]
}
```

### Examples

```elixir
# Analyze current project
{:ok, result} = ElixirOntologies.analyze_project(".")

IO.puts("Files: #{result.metadata.file_count}")
IO.puts("Modules: #{result.metadata.module_count}")

# Include test files
{:ok, result} = ElixirOntologies.analyze_project(".", exclude_tests: false)

# Full configuration
{:ok, result} = ElixirOntologies.analyze_project(".",
  base_iri: "https://myorg.com/projects/my_app#",
  include_source_text: true,
  include_git_info: true,
  exclude_tests: true
)
```

### Handling Partial Failures

```elixir
{:ok, result} = ElixirOntologies.analyze_project(".")

if result.metadata.error_count > 0 do
  IO.puts("Warning: #{result.metadata.error_count} files had errors:")
  for {file, error} <- result.errors do
    IO.puts("  #{file}: #{inspect(error)}")
  end
end

# Save the successfully analyzed content
:ok = ElixirOntologies.Graph.save(result.graph, "project_graph.ttl")
```

---

## update_graph/2

Updates an existing RDF knowledge graph by re-analyzing the project.

```elixir
@spec update_graph(Path.t(), keyword()) ::
  {:ok, %{graph: Graph.t(), metadata: map()}} | {:error, term()}
```

### Additional Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:project_path` | `Path.t()` | `"."` | Path to project to re-analyze |

### Examples

```elixir
# Initial analysis
{:ok, result} = ElixirOntologies.analyze_project(".")
:ok = ElixirOntologies.Graph.save(result.graph, "project.ttl")

# Later, after code changes
{:ok, updated} = ElixirOntologies.update_graph("project.ttl")
:ok = ElixirOntologies.Graph.save(updated.graph, "project.ttl")

# Update with different project path
{:ok, updated} = ElixirOntologies.update_graph(
  "project.ttl",
  project_path: "/path/to/project"
)
```

### Error Handling

```elixir
case ElixirOntologies.update_graph("project.ttl") do
  {:ok, result} ->
    :ok = ElixirOntologies.Graph.save(result.graph, "project.ttl")
  {:error, :graph_not_found} ->
    IO.puts("Graph file does not exist")
  {:error, {:invalid_graph, reason}} ->
    IO.puts("Invalid graph: #{inspect(reason)}")
end
```

---

## analyze_to_kg/3

Analyzes a project and stores the result directly in a knowledge graph database.

**Requires:** The optional `triple_store` dependency.

```elixir
@spec analyze_to_kg(Path.t(), Path.t(), keyword()) ::
  {:ok, result_map()} | {:error, term()}
```

### Additional Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:create_if_missing` | `boolean()` | `true` | Create database if missing |

### Examples

```elixir
# Basic usage
{:ok, result} = ElixirOntologies.analyze_to_kg(".", "./knowledge_graph")
IO.puts("Stored #{result.triple_count} triples")

# With configuration
{:ok, result} = ElixirOntologies.analyze_to_kg(
  "/path/to/project",
  "./kg",
  base_iri: "https://myorg.com/code#"
)

# Check availability first
if ElixirOntologies.kg_available?() do
  {:ok, result} = ElixirOntologies.analyze_to_kg(".", "./kg")
else
  IO.puts("Install triple_store for knowledge graph features")
end
```

---

## store_graph/3

Stores an existing RDF graph in a knowledge graph database.

**Requires:** The optional `triple_store` dependency.

```elixir
@spec store_graph(Graph.t() | RDF.Graph.t(), Path.t(), keyword()) ::
  {:ok, non_neg_integer()} | {:error, term()}
```

### Examples

```elixir
# Store analysis result
{:ok, graph} = ElixirOntologies.analyze_file("lib/my_module.ex")
{:ok, count} = ElixirOntologies.store_graph(graph, "./knowledge_graph")
IO.puts("Stored #{count} triples")

# Store loaded Turtle file
{:ok, rdf_graph} = RDF.Turtle.read_file("ontology.ttl")
{:ok, count} = ElixirOntologies.store_graph(rdf_graph, "./kg")
```

---

## kg_available?/0

Checks if knowledge graph features are available.

```elixir
@spec kg_available?() :: boolean()
```

Returns `true` if the `triple_store` dependency is installed.

```elixir
if ElixirOntologies.kg_available?() do
  {:ok, _} = ElixirOntologies.analyze_to_kg(".", "./kg")
else
  {:ok, result} = ElixirOntologies.analyze_project(".")
  :ok = ElixirOntologies.Graph.save(result.graph, "output.ttl")
end
```

---

## Working with Results

### Inspecting the Graph

```elixir
{:ok, result} = ElixirOntologies.analyze_project(".")
graph = result.graph

# Count statements
count = ElixirOntologies.Graph.statement_count(graph)

# Get all subjects
subjects = ElixirOntologies.Graph.subjects(graph)

# Check if empty
ElixirOntologies.Graph.empty?(graph)
```

### Serializing Results

```elixir
# To Turtle string
{:ok, turtle} = ElixirOntologies.Graph.to_turtle(result.graph)

# Save to file
:ok = ElixirOntologies.Graph.save(result.graph, "output.ttl")
```

### SPARQL Queries

```elixir
query = """
SELECT ?module ?name WHERE {
  ?module a struct:Module .
  ?module struct:moduleName ?name .
}
"""

case ElixirOntologies.Graph.query(result.graph, query) do
  {:ok, results} -> Enum.each(results, &IO.inspect/1)
  {:error, :sparql_not_available} -> IO.puts("Install sparql library")
end
```

---

## Performance Tips

For large projects, optimize with:

```elixir
{:ok, result} = ElixirOntologies.analyze_project(".",
  include_source_text: false,  # Reduces graph size
  include_git_info: false,     # Faster, no git calls
  exclude_tests: true          # Skip test files
)
```

---

## See Also

- [Analyzing Code Guide](../users/analyzing-code.md) - Command-line usage
- [Querying Guide](../users/querying.md) - SPARQL queries
- [Knowledge Graph Guide](../knowledge-graph.md) - Persistent storage
