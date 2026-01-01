# Configuration Guide

This guide covers all configuration options available in Elixir Ontologies for controlling code analysis and graph generation.

## The Config Struct

```elixir
%ElixirOntologies.Config{
  base_iri: String.t(),           # Base IRI namespace for generated entities
  include_source_text: boolean(), # Whether to embed source code in the graph
  include_git_info: boolean(),    # Whether to include Git provenance data
  output_format: atom()           # Serialization format (:turtle, :ntriples, :jsonld)
}
```

## Creating Configurations

### Default Configuration

```elixir
config = ElixirOntologies.Config.default()
# => %Config{base_iri: "https://example.org/code#", include_source_text: false,
#            include_git_info: true, output_format: :turtle}
```

### Custom Configuration with new/1

```elixir
config = ElixirOntologies.Config.new(
  base_iri: "https://mycompany.org/codebase#",
  include_source_text: true,
  output_format: :jsonld
)
```

Raises `ArgumentError` if any values are invalid.

### Modifying with merge/2

```elixir
base_config = ElixirOntologies.Config.default()
custom_config = ElixirOntologies.Config.merge(base_config,
  base_iri: "https://myproject.org/",
  include_source_text: true
)
```

## Configuration Options

### base_iri

**Default:** `"https://example.org/code#"`

The base IRI forms the namespace for all generated entity identifiers:

```
Module:   https://myapp.org/code#MyApp.Users
Function: https://myapp.org/code#MyApp.Users/get_user/1
Clause:   https://myapp.org/code#MyApp.Users/get_user/1/clause/0
```

| Scenario | Recommended Base IRI |
|----------|---------------------|
| Personal project | `https://example.org/code#` (default) |
| Company codebase | `https://yourcompany.org/projects/myapp#` |
| Open source library | `https://w3id.org/elixir-packages/yourlib#` |

End with `#` or `/` to ensure proper IRI concatenation.

### include_source_text

**Default:** `false`

When enabled, embeds source code as RDF literals:

```turtle
<https://example.org/code#MyApp.Users/get_user/1>
    elixir:sourceText "def get_user(id), do: Repo.get(User, id)" .
```

**Enable when:**
- Building code search or documentation systems
- Training ML models on code
- Debugging analysis results

**Disable when:**
- Handling proprietary code
- Graph size is a concern (can increase size 10-50x)

### include_git_info

**Default:** `true`

Includes Git provenance using PROV-O vocabulary:

```turtle
<https://example.org/code#MyApp.Users>
    prov:wasGeneratedBy [
        a prov:Activity ;
        prov:atTime "2024-01-15T10:30:00Z"^^xsd:dateTime
    ] ;
    elixir:gitCommit "abc123def456" .
```

**Enable when:**
- Tracking code evolution
- Auditing and compliance needs
- Analyzing contribution patterns

**Disable when:**
- Code not under Git version control
- Privacy-sensitive analysis (avoids author emails)
- Performance-critical batch processing

### output_format

**Default:** `:turtle`

| Format | Extension | Best For |
|--------|-----------|----------|
| `:turtle` | `.ttl` | Human reading, debugging, version control |
| `:ntriples` | `.nt` | Streaming, large datasets, parallel processing |
| `:jsonld` | `.jsonld` | Web APIs, JavaScript integration |

## Validation

### Safe Validation

```elixir
case ElixirOntologies.Config.validate(config) do
  {:ok, valid_config} -> Pipeline.analyze_and_build(file, valid_config)
  {:error, reasons} -> Enum.each(reasons, &IO.puts/1)
end
```

### Fail-Fast Validation

```elixir
config = ElixirOntologies.Config.validate!(config)  # Raises on error
```

### Validation Rules

| Field | Rule |
|-------|------|
| `base_iri` | Must be a non-empty string |
| `include_source_text` | Must be a boolean |
| `include_git_info` | Must be a boolean |
| `output_format` | Must be `:turtle`, `:ntriples`, or `:jsonld` |

## Common Usage Patterns

### Per-File Analysis with Custom Base IRI

```elixir
def analyze_file(file_path) do
  base = "https://myorg.org/code/#{Path.basename(file_path, ".ex")}#"
  config = ElixirOntologies.Config.new(base_iri: base)
  Pipeline.analyze_and_build(file_path, config)
end
```

### Project-Wide Analysis with Source Text

```elixir
config = ElixirOntologies.Config.new(
  base_iri: "https://docs.myproject.org/code#",
  include_source_text: true,
  include_git_info: true
)
{:ok, result} = ProjectAnalyzer.analyze("/path/to/project", config: config)
```

### Production Analysis (Privacy-Conscious)

```elixir
config = ElixirOntologies.Config.new(
  base_iri: "https://internal.company.org/analysis#",
  include_source_text: false,
  include_git_info: false,
  output_format: :ntriples
)
```

### CI/CD Integration

```elixir
config = ElixirOntologies.Config.new(
  base_iri: System.get_env("CODE_BASE_IRI", "https://ci.example.org/"),
  include_source_text: false,
  include_git_info: true,
  output_format: :ntriples
)
```

## Command-Line Usage

Configuration options map to Mix task flags:

```bash
# Base IRI
mix elixir_ontologies.analyze --base-iri https://myapp.org/code#
mix elixir_ontologies.analyze -b https://myapp.org/code#

# Include source text
mix elixir_ontologies.analyze --include-source

# Disable Git info
mix elixir_ontologies.analyze --no-include-git

# Combined example
mix elixir_ontologies.analyze \
  --base-iri https://myapp.org/code# \
  --include-source \
  --no-include-git \
  -o output.ttl
```

## Next Steps

- [Code Analysis Guide](../users/analyzing-code.md) - Detailed analysis options
- [Evolution Tracking](../users/evolution-tracking.md) - Using Git provenance data
- [Querying the Graph](../users/querying.md) - Query your generated RDF data
