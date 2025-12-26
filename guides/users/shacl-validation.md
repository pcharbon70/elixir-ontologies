# SHACL Validation Guide

This guide explains how to validate RDF graphs against SHACL (Shapes Constraint Language) shapes.

## What is SHACL?

SHACL is a W3C standard for validating RDF graphs. It allows you to define constraints (shapes) that your data must conform to:

- **Cardinality** - Required properties, min/max counts
- **Types** - Data types and class membership
- **Values** - Allowed values, patterns, ranges
- **Relationships** - Property paths and connections

## Quick Start

### Command Line

```bash
# Validate generated graph against built-in shapes
mix elixir_ontologies.analyze --validate

# Validate with output file
mix elixir_ontologies.analyze --output graph.ttl --validate
```

### Programmatic

```elixir
alias ElixirOntologies.SHACL

# Load data and shapes
{:ok, data} = RDF.Turtle.read_file("my_graph.ttl")
{:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")

# Validate
{:ok, report} = SHACL.validate(data, shapes)

if report.conforms? do
  IO.puts("Valid!")
else
  IO.puts("Found #{length(report.results)} issues")
end
```

## Built-in Shapes

The library includes shapes for Elixir code:

| Shape File | Description |
|------------|-------------|
| `elixir-shapes.ttl` | Core Elixir code constraints |
| `otp-shapes.ttl` | OTP pattern constraints |
| `evolution-shapes.ttl` | Evolution/provenance constraints |

### Using Built-in Shapes

```elixir
alias ElixirOntologies.Validator

# Validate against built-in shapes
{:ok, result} = Validator.validate("my_graph.ttl")

case result do
  :conforms ->
    IO.puts("Graph conforms to all shapes")

  {:violations, report} ->
    IO.puts("Found violations:")
    Enum.each(report.results, &IO.puts("  - #{&1.message}"))
end
```

## Validation Reports

### Report Structure

```elixir
%SHACL.Model.ValidationReport{
  conforms?: false,
  results: [
    %SHACL.Model.ValidationResult{
      focus_node: ~I<https://example.org/MyModule>,
      path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
      severity: :violation,
      message: "Module must have a name",
      source_shape: ~I<http://example.org/ModuleShape>,
      details: %{...}
    }
  ]
}
```

### Checking Results

```elixir
{:ok, report} = SHACL.validate(data, shapes)

# Check overall conformance
if report.conforms? do
  IO.puts("All good!")
else
  # Filter by severity
  violations = Enum.filter(report.results, &(&1.severity == :violation))
  warnings = Enum.filter(report.results, &(&1.severity == :warning))
  info = Enum.filter(report.results, &(&1.severity == :info))

  IO.puts("Violations: #{length(violations)}")
  IO.puts("Warnings: #{length(warnings)}")
  IO.puts("Info: #{length(info)}")
end
```

### Understanding Violations

```elixir
Enum.each(report.results, fn result ->
  IO.puts("""
  Focus Node: #{inspect(result.focus_node)}
  Path: #{inspect(result.path)}
  Severity: #{result.severity}
  Message: #{result.message}
  """)
end)
```

## Writing Custom Shapes

### Basic Node Shape

```turtle
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix elixir: <https://w3id.org/elixir-code/structure#> .

# Every Module must have a name
ex:ModuleShape a sh:NodeShape ;
    sh:targetClass elixir:Module ;
    sh:property [
        sh:path elixir:moduleName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:message "Module must have exactly one name"
    ] .
```

### Property Constraints

```turtle
# Function arity must be non-negative integer
ex:FunctionShape a sh:NodeShape ;
    sh:targetClass elixir:Function ;
    sh:property [
        sh:path elixir:arity ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:integer ;
        sh:minInclusive 0 ;
        sh:maxInclusive 255 ;
        sh:message "Function arity must be 0-255"
    ] .
```

### Pattern Matching

```turtle
# Module names must follow Elixir conventions
ex:ModuleNameShape a sh:NodeShape ;
    sh:targetClass elixir:Module ;
    sh:property [
        sh:path elixir:moduleName ;
        sh:pattern "^[A-Z][a-zA-Z0-9]*(\\.[A-Z][a-zA-Z0-9]*)*$" ;
        sh:message "Module name must be PascalCase with dots"
    ] .
```

### Class Constraints

```turtle
# Functions must belong to a Module
ex:FunctionModuleShape a sh:NodeShape ;
    sh:targetClass elixir:Function ;
    sh:property [
        sh:path [ sh:inversePath elixir:containsFunction ] ;
        sh:minCount 1 ;
        sh:class elixir:Module ;
        sh:message "Function must belong to a module"
    ] .
```

### Qualified Constraints

```turtle
# Module must have at least one public function
ex:ModulePublicFunctionShape a sh:NodeShape ;
    sh:targetClass elixir:Module ;
    sh:property [
        sh:path elixir:containsFunction ;
        sh:qualifiedValueShape [
            sh:property [
                sh:path elixir:visibility ;
                sh:hasValue "public"
            ]
        ] ;
        sh:qualifiedMinCount 1 ;
        sh:message "Module should have at least one public function"
    ] .
```

## SPARQL Constraints

For complex validation rules, use SPARQL:

```turtle
# Arity must match parameter count
ex:ArityMatchShape a sh:NodeShape ;
    sh:targetClass elixir:Function ;
    sh:sparql [
        sh:select """
            SELECT $this ?arity ?paramCount
            WHERE {
                $this elixir:arity ?arity .
                $this elixir:hasClause ?clause .
                {
                    SELECT ?clause (COUNT(?param) AS ?paramCount)
                    WHERE { ?clause elixir:hasParameter ?param }
                    GROUP BY ?clause
                }
                FILTER (?arity != ?paramCount)
            }
        """ ;
        sh:message "Function arity must match parameter count"
    ] .
```

## Validation Options

### Parallel Validation

```elixir
# Enable parallel validation (default)
{:ok, report} = SHACL.validate(data, shapes, parallel: true)

# Control concurrency
{:ok, report} = SHACL.validate(data, shapes,
  parallel: true,
  max_concurrency: 4
)

# Disable for debugging
{:ok, report} = SHACL.validate(data, shapes, parallel: false)
```

### Timeouts

```elixir
# Increase timeout for complex shapes
{:ok, report} = SHACL.validate(data, shapes, timeout: 30_000)
```

## File-based Validation

### Validate Files Directly

```elixir
# Validate Turtle files
{:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

# Handle file errors
case SHACL.validate_file("data.ttl", "shapes.ttl") do
  {:ok, report} ->
    IO.puts("Conforms: #{report.conforms?}")

  {:error, {:file_read_error, :data, path, reason}} ->
    IO.puts("Cannot read data file: #{path}")

  {:error, {:file_read_error, :shapes, path, reason}} ->
    IO.puts("Cannot read shapes file: #{path}")
end
```

## Integration with Analysis

### Validate During Analysis

```elixir
alias ElixirOntologies.{Pipeline, Validator}

# Analyze code
{:ok, result} = Pipeline.analyze_and_build("lib/my_module.ex")

# Validate the generated graph
{:ok, report} = Validator.validate_graph(result.graph)

if report.conforms? do
  IO.puts("Generated graph is valid")
else
  IO.puts("Graph has issues - check shapes")
end
```

### Custom Validation Pipeline

```elixir
alias ElixirOntologies.{Pipeline, SHACL}

# Analyze
{:ok, result} = Pipeline.analyze_and_build("lib/")

# Load custom shapes
{:ok, shapes} = RDF.Turtle.read_file("my_shapes.ttl")

# Validate
{:ok, report} = SHACL.validate(result.graph, shapes)

# Report issues
unless report.conforms? do
  Enum.each(report.results, fn r ->
    IO.puts("[#{r.severity}] #{r.message}")
    IO.puts("  Node: #{inspect(r.focus_node)}")
  end)
end
```

## Common Validation Patterns

### Check Module Structure

```elixir
# Verify all modules have required properties
violations = Enum.filter(report.results, fn r ->
  String.contains?(to_string(r.focus_node), "Module") and
  r.severity == :violation
end)

if violations != [] do
  IO.puts("Module structure issues found!")
end
```

### Check Function Completeness

```elixir
# Find functions missing specs
{:ok, shapes} = RDF.Turtle.read_string("""
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix elixir: <https://w3id.org/elixir-code/structure#> .

ex:FunctionSpecShape a sh:NodeShape ;
    sh:targetClass elixir:Function ;
    sh:property [
        sh:path elixir:hasSpec ;
        sh:minCount 1 ;
        sh:severity sh:Warning ;
        sh:message "Function should have a typespec"
    ] .
""")

{:ok, report} = SHACL.validate(graph, shapes)
```

## Error Handling

```elixir
case SHACL.validate(data, shapes) do
  {:ok, report} ->
    handle_report(report)

  {:error, {:parse_error, details}} ->
    IO.puts("Failed to parse shapes: #{inspect(details)}")

  {:error, {:validation_error, reason}} ->
    IO.puts("Validation failed: #{inspect(reason)}")

  {:error, reason} ->
    IO.puts("Unknown error: #{inspect(reason)}")
end
```

## Next Steps

- [Querying the Graph](./querying.md) - Query validated data
- [Evolution Tracking](./evolution-tracking.md) - Validate provenance graphs
