# Hex Batch Analyzer Guide

Analyze Elixir packages from hex.pm and generate RDF knowledge graphs in Turtle format.

## Overview

The hex batch analyzer downloads packages from hex.pm, extracts their source code, runs the project analyzer, and outputs TTL (Turtle) files containing RDF triples that describe the code structure.

## Quick Start

```bash
# Analyze a single package
mix elixir_ontologies.hex_batch --package phoenix

# Preview top 10 packages without processing
mix elixir_ontologies.hex_batch --dry-run --limit 10

# Analyze top 100 most popular packages
mix elixir_ontologies.hex_batch --limit 100

# Full batch (all ~18,000 packages)
mix elixir_ontologies.hex_batch
```

## Output

TTL files are written to the `.ttl/` directory by default:

```
.ttl/
  phoenix-1.7.14.ttl
  ecto-3.11.2.ttl
  jason-1.4.4.ttl
  progress.json
```

Each TTL file contains RDF triples describing:
- Modules and their relationships
- Functions with arity, parameters, and return types
- Type specifications and documentation
- Macros, protocols, and behaviours

## Options Reference

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output-dir` | `-o` | Output directory for TTL files | `.ttl` |
| `--limit` | `-l` | Maximum packages to process | unlimited |
| `--package` | `-p` | Analyze single package by name | - |
| `--sort-by` | `-s` | Sort order: `popularity` or `alphabetical` | `popularity` |
| `--resume` | `-r` | Resume from progress file | `true` |
| `--dry-run` | | List packages without processing | `false` |
| `--verbose` | `-v` | Show detailed progress with timestamps | `false` |
| `--quiet` | `-q` | Minimal output | `false` |
| `--delay` | | Delay between packages (ms) | `100` |
| `--timeout` | | Per-package timeout (minutes) | `5` |
| `--start-page` | | Starting API page number | `1` |
| `--progress-file` | | Custom progress file path | `OUTPUT_DIR/progress.json` |

## Sort Order

By default, packages are processed by popularity (download count), so the most important packages are analyzed first:

```bash
# Top packages first (default)
mix elixir_ontologies.hex_batch --limit 100

# Alphabetical order
mix elixir_ontologies.hex_batch --limit 100 --sort-by alphabetical
```

## Resume Capability

The analyzer automatically saves progress to `progress.json`. If interrupted, simply run again to continue:

```bash
# First run - processes 50 packages then interrupted
mix elixir_ontologies.hex_batch --limit 100
# Ctrl+C at package 50

# Resume - skips completed packages, processes remaining 50
mix elixir_ontologies.hex_batch --limit 100
```

To start fresh, disable resume or delete the progress file:

```bash
# Disable resume
mix elixir_ontologies.hex_batch --resume false

# Or delete progress file
rm .ttl/progress.json
```

## Examples

### Test with a Single Package

```bash
mix elixir_ontologies.hex_batch --package ecto --verbose
```

Output:
```
Analyzing single package: ecto

[10:30:15] Starting: ecto v3.11.2
[10:30:18] Complete: ecto v3.11.2 (2847ms)
Success: ecto v3.11.2
  Output: .ttl/ecto-3.11.2.ttl
  Modules: 45
  Duration: 2.8s
```

### Preview Before Processing

```bash
mix elixir_ontologies.hex_batch --dry-run --limit 20
```

Output:
```
Dry run - listing Elixir packages from hex.pm
Sort order: popularity

  1. jason v1.4.4
  2. telemetry v1.3.0
  3. mime v2.0.7
  4. plug v1.16.1
  5. phoenix v1.7.14
  ...

Total Elixir packages found: 20

Run without --dry-run to process these packages.
```

### Custom Output Directory

```bash
mix elixir_ontologies.hex_batch --output-dir ./my_graphs --limit 50
```

### Verbose Batch Processing

```bash
mix elixir_ontologies.hex_batch --limit 10 --verbose
```

## Base IRI Pattern

Each package gets unique IRIs based on package name and version:

```
https://elixir-code.org/{package}/{version}/
```

For example, `phoenix` version `1.7.14` uses:
```
https://elixir-code.org/phoenix/1.7.14/
```

## Performance

- **Rate limiting**: Respects hex.pm API rate limits with automatic backoff
- **Disk usage**: ~50MB temp space, output varies by package count
- **Timing**: ~1-5 seconds per package depending on size
- **Full batch**: ~18,000 packages, estimated 12-24 hours

## Troubleshooting

### Package Analysis Fails

Some packages may fail due to:
- Erlang-only code (no `.ex` files)
- Macro-heavy code with unusual AST patterns
- Missing dependencies

Failed packages are logged and skipped. Check `progress.json` for failure details.

### Rate Limited

If you see rate limit warnings, the analyzer automatically backs off. You can increase delay:

```bash
mix elixir_ontologies.hex_batch --delay 500
```

### Timeout

For large packages, increase the timeout:

```bash
mix elixir_ontologies.hex_batch --timeout 10
```

### Out of Disk Space

TTL files can be large. Monitor disk usage or process in batches:

```bash
# Process in chunks
mix elixir_ontologies.hex_batch --limit 1000
# ... process/move files ...
mix elixir_ontologies.hex_batch --limit 1000
```

## Progress File Format

The `progress.json` file tracks:

```json
{
  "started_at": "2024-01-15T10:00:00Z",
  "updated_at": "2024-01-15T12:30:00Z",
  "processed": [
    {
      "name": "phoenix",
      "version": "1.7.14",
      "status": "completed",
      "output_path": ".ttl/phoenix-1.7.14.ttl",
      "duration_ms": 2847
    }
  ],
  "current_page": 5,
  "config": {
    "output_dir": ".ttl",
    "sort_by": "popularity"
  }
}
```

## See Also

- [Analyzing Code](analyzing-code.md) - Using the project analyzer directly
- [Querying](querying.md) - SPARQL queries on generated graphs
- [Structure Guide](../structure.md) - Understanding the ontology structure
