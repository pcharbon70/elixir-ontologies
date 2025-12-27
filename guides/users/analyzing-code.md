# Analyzing Elixir Code

This guide covers the various ways to analyze Elixir source code and generate RDF knowledge graphs.

## Analysis Modes

### Project Analysis

Analyze an entire Elixir project:

```bash
# Current directory
mix elixir_ontologies.analyze

# Specific project path
mix elixir_ontologies.analyze /path/to/project
```

Project analysis:
- Finds all `.ex` files in `lib/`
- Excludes test files by default
- Includes Git provenance information
- Generates a unified graph for the entire project

### File Analysis

Analyze a single source file:

```bash
mix elixir_ontologies.analyze lib/my_app/users.ex
```

### Directory Analysis

Analyze a specific directory:

```bash
mix elixir_ontologies.analyze lib/my_app/controllers/
```

## Command-Line Options

### Output Options

```bash
# Write to file
mix elixir_ontologies.analyze --output graph.ttl
mix elixir_ontologies.analyze -o graph.ttl

# Pipe to file
mix elixir_ontologies.analyze > graph.ttl

# Quiet mode (no progress output)
mix elixir_ontologies.analyze --quiet -o graph.ttl
```

### IRI Configuration

```bash
# Custom base IRI
mix elixir_ontologies.analyze --base-iri https://myapp.org/code#
mix elixir_ontologies.analyze -b https://myapp.org/code#
```

### Content Options

```bash
# Include source code text
mix elixir_ontologies.analyze --include-source

# Exclude Git information (faster)
mix elixir_ontologies.analyze --no-include-git

# Include test files
mix elixir_ontologies.analyze --no-exclude-tests
```

### Validation

```bash
# Validate against SHACL shapes
mix elixir_ontologies.analyze --validate
mix elixir_ontologies.analyze -v
```

## Programmatic API

### Basic Analysis

```elixir
alias ElixirOntologies.Pipeline
alias ElixirOntologies.Config

# Analyze with default config
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")

# Access the graph
graph = result.graph
modules = result.modules
```

### Custom Configuration

```elixir
# Create custom config
config = Config.new(
  base_iri: "https://myapp.org/code#",
  include_source: true,
  include_git: true
)

{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex", config)
```

### Pipeline Options

```elixir
# Disable parallel processing
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  parallel: false
)

# Custom timeout
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  timeout: 10_000
)

# Include/exclude specific builders
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  include: [:module, :function],
  exclude: [:typespecs]
)
```

### Analyzing Source Strings

```elixir
source_code = """
defmodule MyApp.Users do
  def get_user(id), do: {:ok, id}
end
"""

{:ok, result} = Pipeline.analyze_string_and_build(source_code)
```

### Project Analysis

```elixir
alias ElixirOntologies.Analyzer.ProjectAnalyzer

# Analyze entire project
{:ok, result} = ProjectAnalyzer.analyze("/path/to/project")

# With options
{:ok, result} = ProjectAnalyzer.analyze("/path/to/project",
  exclude_tests: true,
  include_git: true
)
```

## What Gets Extracted

### Modules

- Module name and documentation
- Module attributes (@moduledoc, @doc, custom)
- Use/import/alias/require directives

### Functions

- Function name, arity, and visibility (public/private)
- Function clauses with guards
- Parameters and their patterns
- Return expressions
- Documentation

### Types

- Type definitions (@type, @typep, @opaque)
- Type specifications (@spec, @callback)
- Type expressions and parameters

### OTP Patterns

- GenServer callbacks
- Supervisor child specs
- Agent/Task usage

### Macros

- Macro definitions
- Quote/unquote expressions
- Hygiene information

## Output Formats

### Turtle (Default)

```bash
mix elixir_ontologies.analyze -o graph.ttl
```

Human-readable, compact format:

```turtle
@prefix elixir: <https://w3id.org/elixir-code/structure#> .

<https://example.org/code#MyApp.Users>
    a elixir:Module ;
    elixir:moduleName "MyApp.Users" .
```

### Working with the Graph

```elixir
alias ElixirOntologies.Graph

# Get all statements
statements = Graph.statements(graph)

# Count statements
count = Graph.statement_count(graph)

# Serialize to Turtle
turtle = Graph.to_turtle(graph)

# Add statements
graph = Graph.add(graph, {subject, predicate, object})
```

## Performance Tips

### Large Projects

For large codebases:

1. **Analyze incrementally**: Focus on changed files
2. **Disable source inclusion**: `--no-include-source`
3. **Skip Git for speed**: `--no-include-git`
4. **Increase timeout**: Use `timeout: 30_000` option

### Parallel Processing

Parallel processing is enabled by default. Disable if you encounter issues:

```elixir
Pipeline.analyze_and_build(file, config, parallel: false)
```

## Error Handling

### Parse Errors

Files with syntax errors are skipped:

```elixir
case Pipeline.analyze_and_build("lib/broken.ex") do
  {:ok, result} ->
    # Success
  {:error, {:parse_error, message}} ->
    IO.puts("Parse error: #{message}")
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

### Partial Results

Project analysis continues even if some files fail:

```elixir
{:ok, result} = ProjectAnalyzer.analyze("/path/to/project")

# Check for errors
if result.errors != [] do
  IO.puts("Some files had errors:")
  Enum.each(result.errors, &IO.inspect/1)
end
```

## Next Steps

- [Evolution Tracking](./evolution-tracking.md) - Track code changes over time
- [SHACL Validation](./shacl-validation.md) - Validate your graphs
- [Querying the Graph](./querying.md) - Query your RDF data
