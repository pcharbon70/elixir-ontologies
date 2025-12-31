# Validation API

This guide documents the SHACL validation API for validating RDF graphs against shape constraints.

## Overview

The validation system consists of two main modules:

- `ElixirOntologies.SHACL` - General-purpose SHACL validation for any RDF graphs
- `ElixirOntologies.Validator` - Domain-specific facade with automatic Elixir shapes loading

## SHACL Module

The `ElixirOntologies.SHACL` module provides general-purpose SHACL validation.

### validate/3

Validates an RDF data graph against SHACL shapes.

```elixir
@spec validate(RDF.Graph.t(), RDF.Graph.t(), keyword()) ::
  {:ok, ValidationReport.t()} | {:error, term()}
```

**Parameters:**

- `data_graph` - The RDF graph containing data to validate
- `shapes_graph` - The RDF graph containing SHACL shape definitions
- `opts` - Optional validation settings

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `:parallel` | `true` | Enable parallel validation across shapes |
| `:max_concurrency` | `System.schedulers_online()` | Maximum concurrent validation tasks |
| `:timeout` | `5000` | Validation timeout per shape in milliseconds |

**Example:**

```elixir
alias ElixirOntologies.SHACL

{:ok, data} = RDF.Turtle.read_file("data.ttl")
{:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
{:ok, report} = SHACL.validate(data, shapes)

if report.conforms? do
  IO.puts("Data conforms to all shapes")
else
  Enum.each(report.results, fn result ->
    IO.puts("[#{result.severity}] #{result.message}")
  end)
end
```

### validate_file/3

Validates Turtle files directly without manual loading.

```elixir
@spec validate_file(Path.t(), Path.t(), keyword()) ::
  {:ok, ValidationReport.t()} | {:error, term()}
```

**Example:**

```elixir
case SHACL.validate_file("data.ttl", "shapes.ttl") do
  {:ok, report} ->
    IO.puts("Conforms: #{report.conforms?}")

  {:error, {:file_read_error, :data, path, :enoent}} ->
    IO.puts("Data file not found: #{path}")

  {:error, {:file_read_error, :shapes, path, reason}} ->
    IO.puts("Failed to read shapes: #{inspect(reason)}")
end
```

## Validator Module

The `ElixirOntologies.Validator` module provides domain-specific validation with automatic shapes loading.

### validate/2

Validates an Elixir code graph against built-in shapes.

```elixir
@spec validate(Graph.t(), keyword()) ::
  {:ok, ValidationReport.t()} | {:error, term()}
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `:shapes_graph` | Loads `elixir-shapes.ttl` | Custom shapes graph to use |
| `:parallel` | `true` | Enable parallel validation |
| `:max_concurrency` | `System.schedulers_online()` | Max concurrent tasks |
| `:timeout` | `5000` | Timeout per shape in ms |

**Example:**

```elixir
{:ok, graph} = ElixirOntologies.analyze_file("lib/my_module.ex")
{:ok, report} = ElixirOntologies.Validator.validate(graph)

if report.conforms? do
  IO.puts("Code graph is valid")
end
```

## ValidationReport Structure

```elixir
%SHACL.Model.ValidationReport{
  conforms?: boolean(),
  results: [ValidationResult.t()]
}
```

| Field | Description |
|-------|-------------|
| `conforms?` | `true` if data conforms to all shapes |
| `results` | List of validation results (violations, warnings, info) |

## ValidationResult Structure

```elixir
%SHACL.Model.ValidationResult{
  focus_node: RDF.IRI.t(),
  path: RDF.IRI.t() | nil,
  severity: :violation | :warning | :info,
  source_constraint_component: String.t(),
  message: String.t(),
  details: map()
}
```

| Field | Description |
|-------|-------------|
| `focus_node` | The RDF node that violated the constraint |
| `path` | The property path constrained (nil for node-level) |
| `severity` | Severity level: `:violation`, `:warning`, or `:info` |
| `source_constraint_component` | The SHACL constraint type violated |
| `message` | Human-readable error message |
| `details` | Additional constraint-specific information |

## Built-in Shapes

The library includes shapes in `priv/ontologies/elixir-shapes.ttl`:

| Category | Shapes | Description |
|----------|--------|-------------|
| Module | `ModuleShape`, `NestedModuleShape` | Module naming and structure |
| Function | `FunctionShape`, `FunctionClauseShape` | Function identity and clauses |
| Protocol | `ProtocolShape`, `ProtocolImplementationShape` | Protocol definitions |
| Behaviour | `BehaviourShape`, `CallbackSpecShape` | Behaviour contracts |
| OTP | `SupervisorShape`, `GenServerShape`, `ETSTableShape` | OTP patterns |
| Evolution | `CommitShape`, `ChangeSetShape` | Provenance tracking |

## Custom Shapes

Create custom SHACL shapes for project-specific constraints:

```turtle
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix struct: <https://w3id.org/elixir-code/structure#> .

ex:CustomModuleShape a sh:NodeShape ;
    sh:targetClass struct:Module ;
    sh:property [
        sh:path struct:moduleName ;
        sh:pattern "^MyApp\\." ;
        sh:message "Module must be in MyApp namespace"
    ] .
```

**Using custom shapes:**

```elixir
{:ok, custom_shapes} = RDF.Turtle.read_file("custom-shapes.ttl")
{:ok, report} = Validator.validate(graph, shapes_graph: custom_shapes)
```

## Handling Results

### Filtering by Severity

```elixir
{:ok, report} = SHACL.validate(data, shapes)

violations = Enum.filter(report.results, &(&1.severity == :violation))
warnings = Enum.filter(report.results, &(&1.severity == :warning))

IO.puts("Violations: #{length(violations)}, Warnings: #{length(warnings)}")
```

### Grouping by Focus Node

```elixir
by_node = Enum.group_by(report.results, & &1.focus_node)

Enum.each(by_node, fn {node, results} ->
  IO.puts("Node: #{inspect(node)}")
  Enum.each(results, &IO.puts("  - #{&1.message}"))
end)
```

## Performance Tuning

```elixir
# High concurrency for large graphs
{:ok, report} = SHACL.validate(data, shapes, max_concurrency: 16)

# Sequential for debugging
{:ok, report} = SHACL.validate(data, shapes, parallel: false)

# Longer timeout for complex SPARQL constraints
{:ok, report} = SHACL.validate(data, shapes, timeout: 30_000)
```

## Error Handling

```elixir
case SHACL.validate(data, shapes) do
  {:ok, report} ->
    process_report(report)

  {:error, {:shapes_read_error, reason}} ->
    Logger.error("Failed to parse shapes: #{inspect(reason)}")

  {:error, :shapes_file_not_found} ->
    Logger.error("Default shapes file missing")

  {:error, reason} ->
    Logger.error("Validation error: #{inspect(reason)}")
end
```

## Mix Task Integration

```bash
# Validate during analysis
mix elixir_ontologies.analyze --validate

# Validate with output file
mix elixir_ontologies.analyze --output graph.ttl --validate
```

## See Also

- [SHACL Validation Guide](../users/shacl-validation.md) - User-focused tutorial
- [Shapes Reference](../shapes.md) - Built-in shapes documentation
