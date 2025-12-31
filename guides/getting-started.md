# Getting Started with Elixir Ontologies

This guide introduces Elixir Ontologies and walks you through analyzing your first Elixir codebase to generate semantic knowledge graphs.

## What is Elixir Ontologies?

Elixir Ontologies is a library that transforms Elixir source code into RDF (Resource Description Framework) knowledge graphs. It provides:

1. **Semantic Code Analysis** - Parses Elixir modules, functions, types, protocols, behaviours, and OTP patterns into a structured semantic representation.

2. **OWL Ontologies** - A four-layer ontology architecture modeling Elixir's unique constructs:
   - **Core** - Language-agnostic AST primitives
   - **Structure** - Elixir-specific: modules, functions, protocols, behaviours, macros
   - **OTP** - Runtime patterns: GenServer, Supervisor, Agent, Task
   - **Evolution** - Version tracking and provenance via PROV-O

3. **Knowledge Graph Generation** - Creates queryable RDF graphs that can be stored, queried with SPARQL, and used for advanced code analysis.

### Why Use It?

- **Code Understanding for LLMs** - Provide structured, semantic context about codebases to language models
- **Architecture Analysis** - Query module dependencies, function relationships, and OTP supervision trees
- **Code Evolution Tracking** - Track how code changes over time with git-integrated provenance
- **Cross-Project Analysis** - Combine multiple codebases into unified knowledge graphs

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

### Optional: Persistent Storage

For persistent storage and advanced SPARQL queries, add the `triple_store` dependency:

```elixir
def deps do
  [
    {:elixir_ontologies, "~> 0.1.0"},
    {:triple_store, "~> 0.1.0"}  # Optional - enables knowledge graph persistence
  ]
end
```

## Quick Start - Analyzing Your First File

Let's analyze a simple Elixir module. Create a file `lib/greeter.ex`:

```elixir
defmodule Greeter do
  @moduledoc "A simple greeting module"

  @doc "Greets a person by name"
  @spec greet(String.t()) :: String.t()
  def greet(name) do
    "Hello, #{name}!"
  end

  @doc "Greets with a custom message"
  @spec greet(String.t(), String.t()) :: String.t()
  def greet(name, greeting) do
    "#{greeting}, #{name}!"
  end
end
```

### Using the Programmatic API

Start an IEx session and analyze the file:

```elixir
# Analyze a single file
{:ok, graph} = ElixirOntologies.analyze_file("lib/greeter.ex")

# Check how many RDF statements were generated
ElixirOntologies.Graph.statement_count(graph)
# => 42  (varies based on content)

# Serialize to Turtle format for inspection
{:ok, turtle} = ElixirOntologies.Graph.to_turtle(graph)
IO.puts(turtle)
```

### Using the Mix Task

You can also use the command line:

```bash
# Analyze a file and print to stdout
mix elixir_ontologies.analyze lib/greeter.ex

# Save to a file
mix elixir_ontologies.analyze lib/greeter.ex --output greeter.ttl
```

### Analyzing an Entire Project

To analyze all Elixir files in a project:

```elixir
# Analyze current project
{:ok, result} = ElixirOntologies.analyze_project(".")

# Access the unified graph
graph = result.graph

# Check analysis metadata
IO.puts("Analyzed #{result.metadata.file_count} files")
IO.puts("Found #{result.metadata.module_count} modules")

# Check for any errors
if result.metadata.error_count > 0 do
  IO.puts("Errors occurred in #{result.metadata.error_count} files:")
  for {file, error} <- result.errors do
    IO.puts("  #{file}: #{inspect(error)}")
  end
end
```

Or via the command line:

```bash
# Analyze entire project
mix elixir_ontologies.analyze --output project.ttl

# Include test files
mix elixir_ontologies.analyze --no-exclude-tests --output project.ttl
```

## Understanding the Output

The generated RDF graph uses the Turtle format. Here's what our `Greeter` module looks like:

```turtle
@prefix struct: <https://w3id.org/elixir-code/structure#> .
@prefix core: <https://w3id.org/elixir-code/core#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<https://example.org/code#Greeter>
    a struct:Module ;
    struct:moduleName "Greeter" ;
    struct:hasModuledoc "A simple greeting module" ;
    struct:containsFunction <https://example.org/code#Greeter/greet/1> ,
                            <https://example.org/code#Greeter/greet/2> .

<https://example.org/code#Greeter/greet/1>
    a struct:PublicFunction ;
    struct:functionName "greet" ;
    struct:arity 1 ;
    struct:belongsTo <https://example.org/code#Greeter> ;
    struct:hasDoc "Greets a person by name" .

<https://example.org/code#Greeter/greet/2>
    a struct:PublicFunction ;
    struct:functionName "greet" ;
    struct:arity 2 ;
    struct:belongsTo <https://example.org/code#Greeter> ;
    struct:hasDoc "Greets with a custom message" .
```

### Key Concepts

**IRIs (Identifiers)**: Every code element gets a unique IRI:

| Element | Pattern | Example |
|---------|---------|---------|
| Module | `{base}ModuleName` | `https://example.org/code#Greeter` |
| Function | `{base}Module/name/arity` | `https://example.org/code#Greeter/greet/2` |
| Clause | `{function}/clause/N` | `.../greet/2/clause/0` |

**Function Identity**: In Elixir, `greet/1` and `greet/2` are completely different functions. The ontology captures this with the composite key `(Module, Name, Arity)`.

**Namespaces**: The ontology uses these namespace prefixes:

| Prefix | IRI | Purpose |
|--------|-----|---------|
| `core:` | `https://w3id.org/elixir-code/core#` | AST primitives |
| `struct:` | `https://w3id.org/elixir-code/structure#` | Elixir constructs |
| `otp:` | `https://w3id.org/elixir-code/otp#` | OTP patterns |
| `evo:` | `https://w3id.org/elixir-code/evolution#` | Provenance |

## Configuration Options

### Custom Base IRI

Use a custom base IRI for your organization:

```elixir
{:ok, graph} = ElixirOntologies.analyze_file(
  "lib/greeter.ex",
  base_iri: "https://mycompany.org/code#"
)
```

Or via command line:

```bash
mix elixir_ontologies.analyze --base-iri https://mycompany.org/code# -o output.ttl
```

### Include Source Code

Embed the actual source text in the graph (useful for LLM context):

```elixir
{:ok, graph} = ElixirOntologies.analyze_file(
  "lib/greeter.ex",
  include_source_text: true
)
```

### Git Integration

By default, git provenance is included (commit hash, author, timestamp). Disable for faster analysis:

```elixir
{:ok, graph} = ElixirOntologies.analyze_file(
  "lib/greeter.ex",
  include_git_info: false
)
```

## Saving and Loading Graphs

### Save to File

```elixir
{:ok, graph} = ElixirOntologies.analyze_file("lib/greeter.ex")

# Save as Turtle
:ok = ElixirOntologies.Graph.save(graph, "greeter.ttl")

# Or get the string directly
{:ok, turtle} = ElixirOntologies.Graph.to_turtle(graph)
File.write!("greeter.ttl", turtle)
```

### Load from File

```elixir
{:ok, graph} = ElixirOntologies.Graph.load("greeter.ttl")
count = ElixirOntologies.Graph.statement_count(graph)
```

### Merge Multiple Graphs

```elixir
{:ok, graph1} = ElixirOntologies.analyze_file("lib/module_a.ex")
{:ok, graph2} = ElixirOntologies.analyze_file("lib/module_b.ex")

# Merge into a single graph
merged = ElixirOntologies.Graph.merge(graph1, graph2)
```

## Querying Results

### Basic Graph Queries

```elixir
alias ElixirOntologies.Graph

{:ok, graph} = ElixirOntologies.analyze_project(".")

# Get all subjects (IRIs of entities in the graph)
subjects = Graph.subjects(graph)

# Get description of a specific entity
module_iri = RDF.iri("https://example.org/code#MyApp.Users")
description = Graph.describe(graph, module_iri)
```

### SPARQL Queries

If you have the `sparql` library installed:

```elixir
{:ok, graph} = ElixirOntologies.analyze_project(".")

# Find all modules
{:ok, results} = ElixirOntologies.Graph.query(graph, """
  SELECT ?module ?name
  WHERE {
    ?module a struct:Module ;
            struct:moduleName ?name .
  }
  ORDER BY ?name
""")

# Find functions with high arity
{:ok, results} = ElixirOntologies.Graph.query(graph, """
  SELECT ?module ?func ?arity
  WHERE {
    ?f a struct:Function ;
       struct:functionName ?func ;
       struct:arity ?arity ;
       struct:belongsTo ?m .
    ?m struct:moduleName ?module .
    FILTER(?arity > 5)
  }
""")
```

## Persistent Storage with Triple Store

For larger codebases or repeated queries, use persistent storage:

```elixir
# Check if triple_store is available
ElixirOntologies.kg_available?()
# => true

# Analyze and store in one step
{:ok, result} = ElixirOntologies.analyze_to_kg(".", "./my_knowledge_graph")
IO.puts("Stored #{result.triple_count} triples")

# Or store an existing graph
{:ok, graph} = ElixirOntologies.analyze_project(".")
{:ok, count} = ElixirOntologies.store_graph(graph, "./my_knowledge_graph")
```

Query the persistent store:

```bash
# Via mix task
mix elixir_ontologies.kg query --db ./my_knowledge_graph \
  "SELECT ?m ?n WHERE { ?m a struct:Module ; struct:moduleName ?n }"
```

## Accessing the Ontology Files

The ontology definitions themselves are included in the package:

```elixir
# List available ontologies
ElixirOntologies.list_ontologies()
# => ["elixir-core.ttl", "elixir-evolution.ttl", "elixir-otp.ttl",
#     "elixir-shapes.ttl", "elixir-structure.ttl"]

# Get path to a specific ontology
ElixirOntologies.ontology_path("elixir-structure.ttl")
# => "/path/to/priv/ontologies/elixir-structure.ttl"

# Read ontology content
{:ok, content} = ElixirOntologies.read_ontology("elixir-core.ttl")

# Get namespace IRIs
ElixirOntologies.namespaces()
# => %{
#   core: "https://w3id.org/elixir-code/core#",
#   struct: "https://w3id.org/elixir-code/structure#",
#   otp: "https://w3id.org/elixir-code/otp#",
#   evo: "https://w3id.org/elixir-code/evolution#",
#   shapes: "https://w3id.org/elixir-code/shapes#"
# }
```

## Next Steps

Now that you have the basics, explore these topics:

- **[Analyzing Code](users/analyzing-code.md)** - Detailed analysis options and what gets extracted
- **[Core Ontology](core.md)** - Understanding the base AST primitives
- **[Structure Ontology](structure.md)** - Elixir modules, functions, protocols, and behaviours
- **[OTP Ontology](otp.md)** - GenServer, Supervisor, and OTP patterns
- **[Evolution Tracking](users/evolution-tracking.md)** - Track code changes with Git provenance
- **[SHACL Validation](users/shacl-validation.md)** - Validate your graphs against constraints
- **[Knowledge Graph Guide](knowledge-graph.md)** - Persistent storage and advanced querying
- **[Querying](users/querying.md)** - In-depth guide to querying RDF graphs

## Troubleshooting

### "No source files found"

Ensure you're in an Elixir project directory with a `lib/` folder containing `.ex` files.

### Parse errors

Files with syntax errors are skipped with warnings. Fix the syntax errors and re-run the analysis.

### Memory issues with large projects

For very large codebases:

```elixir
# Analyze specific directories
{:ok, graph} = ElixirOntologies.analyze_file("lib/my_app/users/")

# Disable source text inclusion
{:ok, graph} = ElixirOntologies.analyze_project(".",
  include_source_text: false,
  include_git_info: false
)
```

### SPARQL not available

If `Graph.query/2` returns `{:error, :sparql_not_available}`, add the sparql library:

```elixir
{:sparql, "~> 0.3"}
```

### Triple store not available

If `analyze_to_kg/3` returns `{:error, :triple_store_not_available}`, add the triple_store dependency as shown in the installation section.
