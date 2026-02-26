# Getting Started with Elixir Ontologies

This guide covers installation, usage, and configuration options for analyzing Elixir code and generating RDF knowledge graphs using the Elixir Ontologies suite.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Mix Tasks](#mix-tasks)
  - [analyze](#mix-elixir_ontologiesanalyze)
  - [update](#mix-elixir_ontologiesupdate)
  - [kg](#mix-elixir_ontologieskg)
  - [hex_batch](#mix-elixir_ontologieshex_batch)
- [Configuration Options](#configuration-options)
- [Expression Modes](#expression-modes)
- [Output Formats](#output-formats)
- [Validation](#validation)
- [Examples](#examples)

## Installation

### As a Dependency

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:elixir_ontologies, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
mix compile
```

### Development Setup

For development on the elixir-ontologies project:

```bash
# Clone the repository
git clone https://github.com/your-org/elixir-ontologies.git
cd elixir-ontologies

# Install dependencies
mix deps.get

# Run tests
mix test

# Compile
mix compile
```

## Quick Start

### Analyze Your Project

```bash
# Basic analysis - outputs to stdout
mix elixir_ontologies.analyze

# Save to file
mix elixir_ontologies.analyze --output my_project.ttl

# Analyze with full expressions
mix elixir_ontologies.analyze --include-expressions

# Analyze single file
mix elixir_ontologies.analyze lib/my_app/user.ex
```

### Query the Knowledge Graph

```bash
# Load into triple store
mix elixir_ontologies.kg load my_project.ttl

# Run SPARQL query
mix elixir_ontologies.kg query "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10"

# Get statistics
mix elixir_ontologies.kg stats
```

## Mix Tasks

### mix elixir_ontologies.analyze

Analyzes Elixir source code and generates an RDF knowledge graph.

#### Usage

```bash
mix elixir_ontologies.analyze [options] [path]
```

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | stdout |
| `--base-iri` | `-b` | Base IRI for resources | `https://example.org/code#` |
| `--include-source` | | Include source code text | `false` |
| `--include-git` | | Include git provenance | `true` |
| `--include-expressions` | | Enable full expression extraction | `false` |
| `--exclude-tests` | | Exclude test files | `true` |
| `--validate` | `-v` | Validate against SHACL shapes | `false` |
| `--quiet` | `-q` | Suppress progress output | `false` |

#### Examples

```bash
# Analyze current project
mix elixir_ontologies.analyze

# Analyze with custom IRI
mix elixir_ontologies.analyze --base-iri https://myapp.org/code#

# Analyze with full expressions
mix elixir_ontologies.analyze --include-expressions

# Analyze and save to file
mix elixir_ontologies.analyze --output output/my_project.ttl

# Analyze without git info (faster)
mix elixir_ontologies.analyze --no-include-git

# Analyze with validation
mix elixir_ontologies.analyze --validate

# Pipe to file
mix elixir_ontologies.analyze > output.ttl

# Analyze external project
mix elixir_ontologies.analyze /path/to/other/project
```

#### Output Modes

**Light Mode** (default):
```bash
mix elixir_ontologies.analyze
```
Minimal storage (~500 KB per 100 functions). Only structural metadata.

**Full Mode**:
```bash
mix elixir_ontologies.analyze --include-expressions
```
Complete AST representation (~5-20 MB per 100 functions). Project code only (dependencies always light mode).

### mix elixir_ontologies.update

Updates an existing RDF knowledge graph with incremental analysis.

#### Usage

```bash
mix elixir_ontologies.update [options] [path]
```

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | stdout |
| `--base-iri` | `-b` | Base IRI for resources | `https://example.org/code#` |
| `--include-source` | | Include source code text | `false` |
| `--include-git` | | Include git provenance | `true` |
| `--include-expressions` | | Enable full expression extraction | `false` |
| `--exclude-tests` | | Exclude test files | `true` |
| `--validate` | `-v` | Validate against SHACL shapes | `false` |
| `--quiet` | `-q` | Suppress progress output | `false` |

#### Examples

```bash
# Update existing graph
mix elixir_ontologies.update

# Update with changeset detection
mix elixir_ontologies.update --output changes.ttl
```

### mix elixir_ontologies.kg

Manages the Elixir ontologies knowledge graph - loading, querying, and exporting RDF data.

#### Usage

```bash
mix elixir_ontologies.kg <command> [options]
```

#### Commands

| Command | Description |
|---------|-------------|
| `load <file>` | Load RDF data into triple store |
| `query <sparql>` | Execute SPARQL query |
| `stats` | Show graph statistics |
| `export <format>` | Export graph in specified format |
| `clear` | Clear the triple store |

#### Examples

```bash
# Load data
mix elixir_ontologies.kg load my_project.ttl

# Query all modules
mix elixir_ontologies.kg query "SELECT ?m WHERE { ?m a <https://w3id.org/elixir-code/structure#Module> }"

# Get statistics
mix elixir_ontologies.kg stats

# Export as N-Triples
mix elixir_ontologies.kg export ntriples > output.nt

# Clear store
mix elixir_ontologies.kg clear
```

#### Query Examples

```bash
# Find all functions in a module
mix elixir_ontologies.kg query "
PREFIX s: <https://w3id.org/elixir-code/structure#>
SELECT ?func_name ?arity WHERE {
  ?module s:moduleName 'MyApp.User' ;
           s:definesFunction ?func .
  ?func s:functionName ?func_name ;
        s:arity ?arity .
}"

# Find all GenServers
mix elixir_ontologies.kg query "
PREFIX otp: <https://w3id.org/elixir-code/otp#>
SELECT ?module WHERE {
  ?module a otp:GenServer .
}"

# Find protocol implementations
mix elixir_ontologies.kg query "
PREFIX s: <https://w3id.org/elixir-code/structure#>
SELECT ?protocol ?impl_module WHERE {
  ?impl s:implementsProtocol ?impl .
  ?impl s:forType ?type .
  ?protocol s:protocolName ?proto_name .
}"
```

### mix elixir_ontologies.hex_batch

Analyzes all Elixir packages from hex.pm and generates RDF knowledge graphs.

#### Usage

```bash
mix elixir_ontologies.hex_batch [options]
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--output-dir` | Directory for output files | `output/hex` |
| `--max-packages` | Maximum number of packages to analyze | All |
| `--concurrency` | Number of concurrent downloads | 10 |
| `--resume-from` | Package name to resume from | None |
| `--include-deps` | Include dependencies | `false` |
| `--download-only` | Download without analysis | `false` |

#### Examples

```bash
# Analyze all hex.pm packages
mix elixir_ontologies.hex_batch

# Limit to 100 packages
mix elixir_ontologies.hex_batch --max-packages 100

# Resume from specific package
mix elixir_ontologies.hex_batch --resume-from poison

# Include dependencies
mix elixir_ontologies.hex_batch --include-deps
```

## Configuration Options

### Config Module

Create a configuration in your code:

```elixir
config = ElixirOntologies.Config.new(
  base_iri: "https://myapp.org/code#",
  include_source_text: false,
  include_git_info: true,
  include_expressions: false,
  output_format: :turtle
)
```

### Config Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `base_iri` | string | `"https://example.org/code#"` | Base IRI for generated resources |
| `include_source_text` | boolean | `false` | Include source code text in triples |
| `include_git_info` | boolean | `true` | Include git provenance information |
| `include_expressions` | boolean | `false` | Enable full expression extraction |
| `output_format` | atom | `:turtle` | Output format (`:turtle`, `:ntriples`, `:jsonld`) |

### Config Validation

```elixir
# Validate config
{:ok, config} = ElixirOntologies.Config.validate(config)

# Or raise on error
config = ElixirOntologies.Config.new!(base_iri: "https://myapp.org/")
```

## Expression Modes

The `include_expressions` flag controls the depth of code analysis.

### Light Mode (Default)

```bash
mix elixir_ontologies.analyze
```

**Storage**: ~500 KB per 100 functions

**What's extracted**:
- Module declarations
- Function signatures (name, arity, visibility)
- Struct definitions
- Protocol and behaviour declarations
- Module attributes

**What's NOT extracted**:
- Function body expressions
- Guard expressions
- Control flow bodies
- Operator expressions

### Full Mode

```bash
mix elixir_ontologies.analyze --include-expressions
```

**Storage**: ~5-20 MB per 100 functions (project code only)

**Additional extractions**:
- Complete function body AST
- Guard condition expressions
- Control flow structures (if, case, cond, etc.)
- All operators and literals
- Pattern matching constructs
- Call expressions with arguments

**Important**: Dependencies are **always** in light mode regardless of the `include_expressions` setting. Files in `/deps/` are detected and extracted in light mode to keep storage manageable.

### Example Comparison

**Light mode output**:
```turtle
<#func/MyApp.User.new/1> a struct:Function ;
    struct:functionName "new" ;
    struct:arity 1 ;
    struct:visibility "public" .
```

**Full mode output**:
```turtle
<#func/MyApp.User.new/1> a struct:Function ;
    struct:functionName "new" ;
    struct:arity 1 ;
    struct:visibility "public" ;
    struct:hasClause <#clause/0> .

<#clause/0> a struct:FunctionClause ;
    struct:hasParameter <#param/0> ;
    struct:hasBody <#expr/body> .

<#param/0> a struct:Parameter ;
    struct:parameterName "attrs" .

<#expr/body> a core:BlockExpression ;
    core:hasExpression <#expr/struct> .

<#expr/struct> a core:StructLiteral ;
    core:hasField <#field/__struct__> .
    # ... complete AST representation
```

## Output Formats

### Turtle (Default)

Human-readable, recommended for development:

```bash
mix elixir_ontologies.analyze --output output.ttl
```

```turtle
@prefix s: <https://w3id.org/elixir-code/structure#> .

<#module/MyApp.User> a s:Module ;
    s:moduleName "MyApp.User" .
```

### N-Triples

Machine-readable, line-based:

```bash
mix elixir_ontologies.analyze --output-format ntriples --output output.nt
```

```
<https://example.org/code#module/MyApp.User> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://w3id.org/elixir-code/structure#Module> .
<https://example.org/code#module/MyApp.User> <https://w3id.org/elixir-code/structure#moduleName> "MyApp.User" .
```

### JSON-LD

Web-friendly, JSON with context:

```bash
mix elixir_ontologies.analyze --output-format jsonld --output output.jsonld
```

```json
[
  {
    "@id": "https://example.org/code#module/MyApp.User",
    "@type": "https://w3id.org/elixir-code/structure#Module",
    "https://w3id.org/elixir-code/structure#moduleName": "MyApp.User"
  }
]
```

## Validation

### SHACL Validation

Validate output against ontology shapes:

```bash
mix elixir_ontologies.analyze --validate
```

This requires pySHACL for SHACL validation:
```bash
pip install pySHACL
```

### Validation Report

Validation reports include:
- Conformant/non-conformant status
- Constraint violations
- Focus nodes with issues
- Severity levels (Violation, Warning, Info)

Example output:
```
Validation Report: Non-Conformant
Violations: 3

1. [Violation] Module name must start with capital letter
   Focus Node: <#module/invalid_name>

2. [Violation] Function missing required property: arity
   Focus Node: <#func/foo>

3. [Warning] Function has no @spec
   Focus Node: <#func/bar>
```

## Examples

### Analyze a Single Module

```bash
mix elixir_ontologies.analyze lib/my_app/user.ex > user.ttl
```

### Analyze with Custom IRI

```bash
mix elixir_ontologies.analyze \
  --base-iri https://production.myapp.com/code# \
  --output prod.ttl
```

### Batch Analysis

```bash
# Analyze multiple projects
for project in project_a project_b project_c; do
  mix elixir_ontologies.analyze /path/to/$project --output output/$project.ttl
done
```

### Query in IEx

```elixir
# Start IEx
iex -S mix

# Analyze and query
graph = ElixirOntologies.analyze("lib/my_app")

# Count modules
import RDF.SPARQL.Query
query = """
PREFIX s: <https://w3id.org/elixir-code/structure#>
SELECT (COUNT(?module) AS ?count)
WHERE { ?module a s:Module }
"""
ElixirOntologies.KG.query(query)
```

### Filter by Test Status

```bash
# Exclude test files (default)
mix elixir_ontologies.analyze --exclude-tests

# Include test files
mix elixir_ontologies.analyze --no-exclude-tests
```

### Generate Documentation

```bash
# Include source text for documentation generation
mix elixir_ontologies.analyze --include-source --output with_docs.ttl
```

## Programmatic Usage

### In Your Application

```elixir
defmodule MyAnalyzer do
  alias ElixirOntologies.{Config, Analyzer}

  def analyze_project(project_path) do
    config = Config.new(
      base_iri: "https://myapp.org/code#",
      include_expressions: true,
      include_git_info: true
    )

    {:ok, graph} = Analyzer.ProjectAnalyzer.analyze(project_path, config)
    graph
  end

  def save_to_file(graph, file_path) do
    {:ok, turtle} = RDF.Turtle.write_string(graph, prefixes: nil)
    File.write(file_path, turtle)
  end
end
```

### With Knowledge Graph

```elixir
# Load and query
ElixirOntologies.KG.load("my_project.ttl")

results = ElixirOntologies.KG.query("""
  PREFIX s: <https://w3id.org/elixir-code/structure#>
  SELECT ?module ?func WHERE {
    ?module a s:Module .
    ?module s:definesFunction ?func .
  }
""")

Enum.each(results, fn row ->
  IO.puts("#{row.module} defines #{row.func}")
end)
```

## Troubleshooting

### Common Issues

**Issue**: "No such file or directory" error
**Solution**: Ensure you're in an Elixir project with `mix.exs`

**Issue**: "Compilation failed"
**Solution**: Run `mix compile` first

**Issue**: SHACL validation fails
**Solution**: Install pySHACL: `pip install pySHACL`

**Issue**: Large output files
**Solution**: Use light mode (default) without `--include-expressions`

**Issue**: Missing git information
**Solution**: Ensure git repo is initialized: `git init`

## Next Steps

- **[Ontology Overview](overview.md)** - Understand the ontology architecture
- **[Core Ontology Guide](ontology/core.md)** - Learn about AST primitives
- **[Structure Ontology Guide](ontology/structure.md)** - Learn about Elixir constructs
- **[OTP Ontology Guide](ontology/otp.md)** - Learn about OTP patterns
- **[Evolution Ontology Guide](ontology/evolution.md)** - Learn about version tracking
- **[Shapes Ontology Guide](ontology/shapes.md)** - Learn about validation

## References

- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [RDF 1.1 Primer](https://www.w3.org/TR/rdf11-primer/)
- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [SHACL Specification](https://www.w3.org/TR/shacl/)
