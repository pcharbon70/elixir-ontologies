# Pipeline Architecture

This guide provides an overview of the ElixirOntologies analysis pipeline,
explaining how Elixir source code is transformed into RDF knowledge graphs.

## Overview

The pipeline transforms Elixir source code through five distinct stages:

```
Source Code → AST → ModuleAnalysis → Orchestrator Format → RDF Triples → Unified Graph
```

## Pipeline Stages

### Stage 1: Parse Source to AST

The first stage reads Elixir source code and produces an Abstract Syntax Tree (AST):

```elixir
# File parsing
{:ok, ast} = ElixirOntologies.Analyzer.Parser.parse_file("lib/my_module.ex")

# String parsing
{:ok, ast} = ElixirOntologies.Analyzer.Parser.parse(source_code)
```

### Stage 2: Extract Modules from AST

The `FileAnalyzer` walks the AST to find all module definitions:

```elixir
alias ElixirOntologies.Analyzer.FileAnalyzer

{:ok, result} = FileAnalyzer.analyze("lib/my_module.ex")
Enum.each(result.modules, fn m -> IO.puts("Found: #{m.name}") end)
```

Each `ModuleAnalysis` struct contains:

| Field | Description |
|-------|-------------|
| `name` | Module name as atom |
| `functions` | List of function definitions |
| `types` | Type definitions (@type, @typep, @opaque) |
| `protocols` | Protocol definitions and implementations |
| `behaviors` | Behaviour definitions and implementations |
| `otp_patterns` | GenServer, Supervisor, Agent, Task patterns |
| `calls` | Function call graph |
| `control_flow` | Control flow structures |
| `exceptions` | Exception handling patterns |

### Stage 3: Convert to Orchestrator Format

The pipeline converts `ModuleAnalysis` structs into the format expected by the Orchestrator.

### Stage 4: Run Builders

The Orchestrator coordinates multiple builders in phases:

**Phase 1: Module Builder (Sequential)**
- Establishes module IRI and creates base triples

**Phase 2: Component Builders (Parallel)**

| Builder | Responsibility |
|---------|----------------|
| `FunctionBuilder` | Functions and their clauses |
| `ProtocolBuilder` | Protocols and implementations |
| `BehaviourBuilder` | Behaviour definitions |
| `StructBuilder` | Struct definitions |
| `TypeSystemBuilder` | Type definitions and specs |
| `GenServerBuilder` | GenServer patterns |
| `SupervisorBuilder` | Supervisor configurations |
| `AgentBuilder` | Agent patterns |
| `TaskBuilder` | Task patterns |
| `CallGraphBuilder` | Function call relationships |
| `ControlFlowBuilder` | Control flow structures |
| `ExceptionBuilder` | Exception handling patterns |

### Stage 5: Merge Graphs

All generated triples are merged into a unified `ElixirOntologies.Graph`.

## Entry Points

### High-Level: analyze_and_build

For complete file analysis with all stages:

```elixir
alias ElixirOntologies.Pipeline
alias ElixirOntologies.Config

# Basic usage
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")

# With custom configuration
config = Config.new(
  base_iri: "https://myapp.org/code#",
  include_source_text: true,
  include_git_info: true
)
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex", config)
```

### Source String Analysis

For analyzing code from strings:

```elixir
source_code = """
defmodule MyApp.Calculator do
  def add(a, b), do: a + b
end
"""

{:ok, result} = Pipeline.analyze_string_and_build(source_code)
```

### Low-Level: build_graph_for_modules

For working with pre-extracted modules:

```elixir
alias ElixirOntologies.Builders.Context

context = Context.new(
  base_iri: "https://myapp.org/code#",
  file_path: "lib/my_module.ex"
)
graph = Pipeline.build_graph_for_modules(modules, context)
```

## Pipeline Options

### Parallel Processing

Parallel execution is enabled by default:

```elixir
# Disable parallel processing
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  parallel: false
)
```

### Timeout Configuration

Set custom timeouts for parallel tasks:

```elixir
# Default is 5000ms
{:ok, result} = Pipeline.analyze_and_build(
  "lib/complex_module.ex",
  config,
  timeout: 15_000
)
```

### Builder Selection

Include or exclude specific builders:

```elixir
# Only run specific builders
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  include: [:functions, :types, :protocols]
)

# Exclude specific builders
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  exclude: [:genservers, :supervisors, :agents, :tasks]
)
```

Available builder keys:
- `:functions`, `:protocols`, `:behaviours`, `:structs`, `:types`
- `:genservers`, `:supervisors`, `:agents`, `:tasks`
- `:calls`, `:control_flow`, `:exceptions`

## Configuration

### Config Struct

```elixir
alias ElixirOntologies.Config

config = Config.new(
  base_iri: "https://myapp.org/code#",
  include_source_text: true,
  include_git_info: true,
  output_format: :turtle
)
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `base_iri` | String | `"https://example.org/code#"` | Base IRI for resources |
| `include_source_text` | Boolean | `false` | Include source code |
| `include_git_info` | Boolean | `true` | Include Git provenance |
| `output_format` | Atom | `:turtle` | Output format |

### Builder Context

The `Context` struct carries state through the build process:

```elixir
alias ElixirOntologies.Builders.Context

context = Context.new(
  base_iri: "https://myapp.org/code#",
  file_path: "lib/users.ex",
  config: %{include_source_text: true}
)

# Update for nested operations
child = Context.with_parent_module(context, parent_iri)
```

## Advanced Usage

### Cross-Module Linking

Distinguish internal vs external modules:

```elixir
known = MapSet.new(["MyApp.Users", "MyApp.Accounts"])
context = Context.new(base_iri: "https://myapp.org/code#")
context = Context.with_known_modules(context, known)
```

### Custom Pipeline

Build a custom pipeline:

```elixir
alias ElixirOntologies.Analyzer.FileAnalyzer
alias ElixirOntologies.Builders.Context

# Parse and extract
{:ok, result} = FileAnalyzer.analyze("lib/my_module.ex")

# Filter modules
filtered = Enum.filter(result.modules, fn m ->
  not String.starts_with?(to_string(m.name), "MyApp.Internal")
end)

# Build with custom options
context = Context.new(base_iri: "https://myapp.org/code#")
graph = Pipeline.build_graph_for_modules(
  filtered,
  context,
  include: [:functions, :types]
)
```

### Batch Processing

Process multiple files:

```elixir
config = Config.new(base_iri: "https://myapp.org/code#")

graphs = Path.wildcard("lib/**/*.ex")
|> Task.async_stream(fn file ->
  case Pipeline.analyze_and_build(file, config) do
    {:ok, result} -> result.graph
    {:error, _} -> nil
  end
end, timeout: 30_000)
|> Enum.flat_map(fn
  {:ok, graph} when not is_nil(graph) -> [graph]
  _ -> []
end)

# Merge all graphs
unified = Enum.reduce(graphs, Graph.new(), &Graph.merge(&2, &1))
```

## Error Handling

```elixir
case Pipeline.analyze_and_build("lib/broken.ex") do
  {:ok, result} ->
    result.graph

  {:error, {:parse_error, message}} ->
    Logger.error("Parse error: #{message}")
    nil

  {:error, :file_not_found} ->
    Logger.error("File not found")
    nil

  {:error, reason} ->
    Logger.error("Error: #{inspect(reason)}")
    nil
end
```

## Performance Tips

### Large Files

```elixir
# Increase timeout
{:ok, result} = Pipeline.analyze_and_build(file, config, timeout: 30_000)

# Exclude heavy builders if not needed
{:ok, result} = Pipeline.analyze_and_build(file, config,
  exclude: [:calls, :control_flow, :exceptions]
)
```

### Selective Analysis

```elixir
# For call graph analysis only
{:ok, result} = Pipeline.analyze_and_build(
  "lib/my_module.ex",
  config,
  include: [:functions, :calls]
)
```

## Next Steps

- [Analyzing Code](./users/analyzing-code.md) - Command-line and programmatic analysis
- [SHACL Validation](./users/shacl-validation.md) - Validate your graphs
- [Querying the Graph](./users/querying.md) - Query RDF data with SPARQL
- [Evolution Tracking](./users/evolution-tracking.md) - Track code changes over time
