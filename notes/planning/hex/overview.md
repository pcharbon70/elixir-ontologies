# Hex Batch Analyzer

This project implements a comprehensive batch analysis system for processing all Elixir packages from Hex.pm. The system queries the Hex.pm API to enumerate packages, downloads and extracts package tarballs, runs the existing `ProjectAnalyzer` on each package, generates TTL output, and provides robust progress tracking with resume capability.

## Key Metrics

- Approximately 18,000 packages on hex.pm
- Expected runtime: 12-24 hours for full corpus
- Disk space: ~50MB temporary, 10-50GB output
- Rate limiting: 100 requests/min (unauthenticated Hex API)

## Phase Overview

| Phase | Name | Description | Tests |
|-------|------|-------------|-------|
| [Hex.1](phase-01-http-infrastructure.md) | HTTP Infrastructure | Req client wrapper with retry, timeout, rate limiting | ~15 |
| [Hex.2](phase-02-hex-api-client.md) | Hex API Client | Package listing, pagination, Elixir filtering | ~20 |
| [Hex.3](phase-03-package-handler.md) | Package Handler | Download, extract tarball, cleanup | ~30 |
| [Hex.4](phase-04-progress-tracker.md) | Progress Tracker | JSON persistence, resume capability, failure tracking | ~30 |
| [Hex.5](phase-05-batch-processor.md) | Batch Processor | Main orchestration, analyzer integration | ~28 |
| [Hex.6](phase-06-mix-task.md) | Mix Task | CLI interface with options | ~16 |
| [Hex.7](phase-07-unit-tests.md) | Unit Tests | Comprehensive unit test specifications | ~100+ |
| [Hex.8](phase-08-integration-tests.md) | Integration Tests | End-to-end workflow tests | ~15 |

## Dependencies

```elixir
# Add to mix.exs
{:req, "~> 0.5"},
{:bypass, "~> 2.1", only: :test}
```

## File Structure

```
lib/elixir_ontologies/hex/
├── http_client.ex         # Hex.1 - Req wrapper
├── api.ex                 # Hex.2 - Hex.pm API client
├── filter.ex              # Hex.2 - Package filtering
├── downloader.ex          # Hex.3 - Tarball downloads
├── extractor.ex           # Hex.3 - Tarball extraction
├── package_handler.ex     # Hex.3 - Download/extract orchestration
├── progress.ex            # Hex.4 - Progress state model
├── progress_store.ex      # Hex.4 - JSON persistence
├── failure_tracker.ex     # Hex.4 - Failure categorization
├── batch_processor.ex     # Hex.5 - Main orchestrator
├── analyzer_adapter.ex    # Hex.5 - ProjectAnalyzer integration
├── output_manager.ex      # Hex.5 - TTL output management
├── rate_limiter.ex        # Hex.5 - Token bucket rate limiting
└── progress_display.ex    # Hex.6 - Console progress UI

lib/mix/tasks/
└── elixir_ontologies.hex_batch.ex  # Hex.6 - Mix task

test/elixir_ontologies/hex/
├── http_client_test.exs
├── api_test.exs
├── filter_test.exs
├── downloader_test.exs
├── extractor_test.exs
├── package_handler_test.exs
├── progress_test.exs
├── progress_store_test.exs
├── failure_tracker_test.exs
├── batch_processor_test.exs
├── analyzer_adapter_test.exs
├── output_manager_test.exs
├── rate_limiter_test.exs
└── progress_display_test.exs

test/integration/
└── hex_batch_integration_test.exs
```

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| HTTP Client | Req ~> 0.5 | Modern, built-in retry/streaming/JSON |
| Tarball Extraction | `:erl_tar`, `:zlib` | Stdlib, no extra dependencies |
| Progress Persistence | JSON file | Human-readable, easy debugging |
| Rate Limiting | Token bucket | Prevents API throttling |
| Base IRI Pattern | `https://hex.pm/packages/:name#` | Consistent, discoverable |
| Processing | Sequential | Bounded disk usage |
| Output Layout | Flat `{name}-{version}.ttl` | Simple enumeration |

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET https://hex.pm/api/packages?page=N` | Paginated package list |
| `GET https://hex.pm/api/packages/:name` | Single package metadata |
| `GET https://repo.hex.pm/tarballs/:name-:version.tar` | Package tarball |

## Hex Tarball Structure

```
package-version.tar
├── VERSION           # Tarball format version
├── CHECKSUM          # SHA256 checksum
├── metadata.config   # Erlang term package metadata
└── contents.tar.gz   # Actual source code (gzipped tar)
```

## Configuration Options

```elixir
%{
  # Output
  output_dir: "./hex_ontologies",
  progress_file: "./hex_progress.json",

  # Processing
  limit: nil,              # Max packages (nil = all)
  start_page: 1,           # Starting API page
  timeout_minutes: 5,      # Per-package timeout

  # Rate limiting
  delay_ms: 500,           # Inter-package delay
  api_delay_ms: 1000,      # Inter-API-call delay

  # Analysis
  base_iri_template: "https://hex.pm/packages/:name#",
  exclude_tests: true,

  # Behavior
  resume: true,
  dry_run: false,
  verbose: false
}
```

## Usage

```bash
# Analyze all packages
mix elixir_ontologies.hex_batch ./hex_ontologies

# Resume interrupted analysis
mix elixir_ontologies.hex_batch ./hex_ontologies --resume

# Test with single package
mix elixir_ontologies.hex_batch ./hex_ontologies --package phoenix

# Dry run (list packages only)
mix elixir_ontologies.hex_batch ./hex_ontologies --dry-run --limit 100
```

## Critical Existing Files

- `lib/elixir_ontologies/analyzer/project_analyzer.ex` - Core analyzer to reuse
- `lib/elixir_ontologies/graph.ex` - Graph serialization to TTL
- `lib/mix/tasks/elixir_ontologies.analyze.ex` - Mix task pattern reference
