# Phase Hex.5: Batch Processor

This phase implements the main batch processing orchestration with analyzer integration, output management, and rate limiting. The batch processor coordinates all components to process packages sequentially with proper error handling.

## Hex.5.1 Batch Processor Core

Create the main orchestration module for batch processing.

### Hex.5.1.1 Create Batch Processor Module

Create `lib/elixir_ontologies/hex/batch_processor.ex` for orchestration.

- [ ] Hex.5.1.1.1 Create `lib/elixir_ontologies/hex/batch_processor.ex` module
- [ ] Hex.5.1.1.2 Define `@moduledoc` describing batch processing

### Hex.5.1.2 Define Batch Config Struct

Define configuration struct for batch processing.

- [ ] Hex.5.1.2.1 Define `%Config{}` struct
- [ ] Hex.5.1.2.2 Add field `output_dir` (string) - output directory path
- [ ] Hex.5.1.2.3 Add field `progress_file` (string) - progress JSON path
- [ ] Hex.5.1.2.4 Add field `temp_dir` (string) - temporary directory
- [ ] Hex.5.1.2.5 Add field `limit` (integer | nil) - max packages to process
- [ ] Hex.5.1.2.6 Add field `start_page` (integer) - starting API page
- [ ] Hex.5.1.2.7 Add field `delay_ms` (integer) - inter-package delay
- [ ] Hex.5.1.2.8 Add field `api_delay_ms` (integer) - inter-API-call delay
- [ ] Hex.5.1.2.9 Add field `timeout_minutes` (integer) - per-package timeout
- [ ] Hex.5.1.2.10 Add field `base_iri_template` (string) - IRI pattern
- [ ] Hex.5.1.2.11 Add field `resume` (boolean) - resume from progress
- [ ] Hex.5.1.2.12 Add field `dry_run` (boolean) - list only mode
- [ ] Hex.5.1.2.13 Add field `verbose` (boolean) - verbose output
- [ ] Hex.5.1.2.14 Implement `new/1` with defaults
- [ ] Hex.5.1.2.15 Implement `validate/1` checking required fields

### Hex.5.1.3 Implement Initialization

Implement batch processor initialization.

- [ ] Hex.5.1.3.1 Implement `init/1` accepting `%Config{}`
- [ ] Hex.5.1.3.2 Validate config with `Config.validate/1`
- [ ] Hex.5.1.3.3 Create output directory if needed
- [ ] Hex.5.1.3.4 Create temp directory if needed
- [ ] Hex.5.1.3.5 Initialize HTTP client with `HttpClient.new/1`
- [ ] Hex.5.1.3.6 Load or create progress with `ProgressStore.load_or_create/2`
- [ ] Hex.5.1.3.7 Initialize rate limiter with `RateLimiter.new/1`
- [ ] Hex.5.1.3.8 Return `{:ok, state}` with initialized state
- [ ] Hex.5.1.3.9 Return `{:error, reason}` on failure

### Hex.5.1.4 Implement Main Run Loop

Implement the main processing loop.

- [ ] Hex.5.1.4.1 Implement `run/1` accepting `%Config{}`
- [ ] Hex.5.1.4.2 Call `init/1` to initialize state
- [ ] Hex.5.1.4.3 Get package stream from `Api.stream_all_packages/2`
- [ ] Hex.5.1.4.4 Filter to Elixir packages with `Filter.filter_likely_elixir/1`
- [ ] Hex.5.1.4.5 Skip already-processed packages using progress
- [ ] Hex.5.1.4.6 Apply limit if configured
- [ ] Hex.5.1.4.7 Process each package with `process_package/2`
- [ ] Hex.5.1.4.8 Apply delay between packages
- [ ] Hex.5.1.4.9 Checkpoint progress periodically
- [ ] Hex.5.1.4.10 Handle interruption signals
- [ ] Hex.5.1.4.11 Return final progress summary

### Hex.5.1.5 Implement Package Processing

Implement single package processing logic.

- [ ] Hex.5.1.5.1 Implement `process_package/2` accepting package and state
- [ ] Hex.5.1.5.2 Log package start if verbose
- [ ] Hex.5.1.5.3 Record start time for duration tracking
- [ ] Hex.5.1.5.4 Call `PackageHandler.with_package/5` for lifecycle
- [ ] Hex.5.1.5.5 In callback: verify Elixir source with `Filter.has_elixir_source?/1`
- [ ] Hex.5.1.5.6 In callback: run analysis with `AnalyzerAdapter.analyze_package/3`
- [ ] Hex.5.1.5.7 In callback: save output with `OutputManager.save_graph/3`
- [ ] Hex.5.1.5.8 Create `%PackageResult{}` with success info
- [ ] Hex.5.1.5.9 Update progress with result
- [ ] Hex.5.1.5.10 Return updated state

### Hex.5.1.6 Implement Error Handling

Implement error handling for package processing.

- [ ] Hex.5.1.6.1 Wrap `process_package/2` in try/rescue
- [ ] Hex.5.1.6.2 Catch all exceptions
- [ ] Hex.5.1.6.3 Call `FailureTracker.record_failure/4` on error
- [ ] Hex.5.1.6.4 Log error if verbose
- [ ] Hex.5.1.6.5 Update progress with failure result
- [ ] Hex.5.1.6.6 Continue processing (don't halt on single failure)
- [ ] Hex.5.1.6.7 Return updated state

### Hex.5.1.7 Implement Interruption Handling

Handle graceful shutdown on interruption.

- [ ] Hex.5.1.7.1 Implement `setup_signal_handlers/1` trapping exits
- [ ] Hex.5.1.7.2 Handle `:SIGINT` (Ctrl+C)
- [ ] Hex.5.1.7.3 Handle `:SIGTERM`
- [ ] Hex.5.1.7.4 Save progress immediately on signal
- [ ] Hex.5.1.7.5 Clean up current package if in progress
- [ ] Hex.5.1.7.6 Log interruption message
- [ ] Hex.5.1.7.7 Exit gracefully

- [ ] **Task Hex.5.1 Complete**

## Hex.5.2 Analyzer Integration

Integrate with existing ProjectAnalyzer for package analysis.

### Hex.5.2.1 Create Analyzer Adapter Module

Create `lib/elixir_ontologies/hex/analyzer_adapter.ex` for analysis.

- [ ] Hex.5.2.1.1 Create `lib/elixir_ontologies/hex/analyzer_adapter.ex` module
- [ ] Hex.5.2.1.2 Define `@moduledoc` describing analyzer integration
- [ ] Hex.5.2.1.3 Import `ElixirOntologies.Analyzer.ProjectAnalyzer`

### Hex.5.2.2 Implement Analysis Function

Wrap ProjectAnalyzer for batch use.

- [ ] Hex.5.2.2.1 Implement `analyze_package/3` accepting path, name, config
- [ ] Hex.5.2.2.2 Generate base_iri from template and package name
- [ ] Hex.5.2.2.3 Build analysis options map
- [ ] Hex.5.2.2.4 Set `exclude_tests: true`
- [ ] Hex.5.2.2.5 Set `continue_on_error: true`
- [ ] Hex.5.2.2.6 Set `include_git_info: false` (no git in tarballs)
- [ ] Hex.5.2.2.7 Call `ProjectAnalyzer.analyze/2`
- [ ] Hex.5.2.2.8 Return `{:ok, graph, metadata}`
- [ ] Hex.5.2.2.9 Return `{:error, reason}` on failure

### Hex.5.2.3 Implement Timeout Wrapper

Add timeout protection for long-running analyses.

- [ ] Hex.5.2.3.1 Implement `with_timeout/2` accepting function and timeout
- [ ] Hex.5.2.3.2 Use `Task.async/1` to run analysis
- [ ] Hex.5.2.3.3 Use `Task.yield/2` with configured timeout
- [ ] Hex.5.2.3.4 Call `Task.shutdown/2` if timeout exceeded
- [ ] Hex.5.2.3.5 Return `{:error, :timeout}` on timeout
- [ ] Hex.5.2.3.6 Return analysis result on success

### Hex.5.2.4 Implement Metadata Extraction

Extract analysis metadata for progress tracking.

- [ ] Hex.5.2.4.1 Implement `extract_metadata/1` accepting analysis result
- [ ] Hex.5.2.4.2 Count modules in result
- [ ] Hex.5.2.4.3 Count functions in result
- [ ] Hex.5.2.4.4 Count triples in graph
- [ ] Hex.5.2.4.5 Return metadata map

- [ ] **Task Hex.5.2 Complete**

## Hex.5.3 Output Management

Manage TTL output file organization and naming.

### Hex.5.3.1 Create Output Manager Module

Create `lib/elixir_ontologies/hex/output_manager.ex` for output handling.

- [ ] Hex.5.3.1.1 Create `lib/elixir_ontologies/hex/output_manager.ex` module
- [ ] Hex.5.3.1.2 Define `@moduledoc` describing output management

### Hex.5.3.2 Implement Path Generation

Generate output file paths.

- [ ] Hex.5.3.2.1 Implement `output_path/3` accepting output_dir, name, version
- [ ] Hex.5.3.2.2 Sanitize package name for filesystem safety
- [ ] Hex.5.3.2.3 Generate filename: `"#{name}-#{version}.ttl"`
- [ ] Hex.5.3.2.4 Return full path: `Path.join(output_dir, filename)`
- [ ] Hex.5.3.2.5 Implement `sanitize_name/1` for special characters

### Hex.5.3.3 Implement Directory Management

Manage output directory structure.

- [ ] Hex.5.3.3.1 Implement `ensure_output_dir/1` accepting output_dir
- [ ] Hex.5.3.3.2 Create directory if doesn't exist with `File.mkdir_p!/1`
- [ ] Hex.5.3.3.3 Verify write permissions
- [ ] Hex.5.3.3.4 Return `:ok` or `{:error, reason}`

### Hex.5.3.4 Implement Graph Saving

Save RDF graph to TTL file.

- [ ] Hex.5.3.4.1 Implement `save_graph/4` accepting graph, output_dir, name, version
- [ ] Hex.5.3.4.2 Generate path with `output_path/3`
- [ ] Hex.5.3.4.3 Call `Graph.save/2` to write TTL
- [ ] Hex.5.3.4.4 Return `{:ok, path}` on success
- [ ] Hex.5.3.4.5 Return `{:error, reason}` on failure
- [ ] Hex.5.3.4.6 Log output path if verbose

### Hex.5.3.5 Implement Output Listing

List existing output files.

- [ ] Hex.5.3.5.1 Implement `list_outputs/1` accepting output_dir
- [ ] Hex.5.3.5.2 Use `Path.wildcard/1` to find `*.ttl` files
- [ ] Hex.5.3.5.3 Parse name and version from filenames
- [ ] Hex.5.3.5.4 Return list of `{name, version, path}` tuples
- [ ] Hex.5.3.5.5 Implement `output_exists?/3` checking specific package

### Hex.5.3.6 Implement Disk Space Monitoring

Monitor available disk space.

- [ ] Hex.5.3.6.1 Implement `check_disk_space/1` accepting output_dir
- [ ] Hex.5.3.6.2 Use `:disksup.get_disk_data/0` or shell command
- [ ] Hex.5.3.6.3 Return available bytes
- [ ] Hex.5.3.6.4 Implement `warn_if_low/2` accepting threshold
- [ ] Hex.5.3.6.5 Log warning if below threshold
- [ ] Hex.5.3.6.6 Return `:ok` or `:low_disk_space`

- [ ] **Task Hex.5.3 Complete**

## Hex.5.4 Rate Limiting

Implement configurable rate limiting for API calls.

### Hex.5.4.1 Create Rate Limiter Module

Create `lib/elixir_ontologies/hex/rate_limiter.ex` for rate limiting.

- [ ] Hex.5.4.1.1 Create `lib/elixir_ontologies/hex/rate_limiter.ex` module
- [ ] Hex.5.4.1.2 Define `@moduledoc` describing rate limiting
- [ ] Hex.5.4.1.3 Define `@default_rate` as 100 (requests per minute)
- [ ] Hex.5.4.1.4 Define `@default_burst` as 10 (burst allowance)

### Hex.5.4.2 Define Rate Limiter State

Define state for token bucket algorithm.

- [ ] Hex.5.4.2.1 Define `%State{}` struct
- [ ] Hex.5.4.2.2 Add field `tokens` (float) - available tokens
- [ ] Hex.5.4.2.3 Add field `max_tokens` (integer) - bucket capacity
- [ ] Hex.5.4.2.4 Add field `refill_rate` (float) - tokens per millisecond
- [ ] Hex.5.4.2.5 Add field `last_refill` (integer) - last refill timestamp
- [ ] Hex.5.4.2.6 Add field `api_remaining` (integer | nil) - from headers
- [ ] Hex.5.4.2.7 Add field `api_reset` (integer | nil) - from headers

### Hex.5.4.3 Implement Token Bucket

Implement token bucket rate limiting.

- [ ] Hex.5.4.3.1 Implement `new/1` accepting options
- [ ] Hex.5.4.3.2 Calculate `refill_rate` from requests per minute
- [ ] Hex.5.4.3.3 Initialize with full bucket
- [ ] Hex.5.4.3.4 Implement `refill/1` adding tokens based on elapsed time
- [ ] Hex.5.4.3.5 Cap tokens at `max_tokens`
- [ ] Hex.5.4.3.6 Implement `consume/1` removing one token
- [ ] Hex.5.4.3.7 Return `{:ok, state}` if token available
- [ ] Hex.5.4.3.8 Return `{:wait, milliseconds}` if bucket empty

### Hex.5.4.4 Implement Acquire Function

Implement blocking acquire for rate limiting.

- [ ] Hex.5.4.4.1 Implement `acquire/1` accepting state
- [ ] Hex.5.4.4.2 Call `refill/1` to update tokens
- [ ] Hex.5.4.4.3 Call `consume/1` to try taking token
- [ ] Hex.5.4.4.4 If `{:wait, ms}`, sleep for duration
- [ ] Hex.5.4.4.5 Retry after sleep
- [ ] Hex.5.4.4.6 Return updated state

### Hex.5.4.5 Implement Adaptive Delay

Adjust delay based on API rate limit headers.

- [ ] Hex.5.4.5.1 Implement `update_from_headers/2` accepting state and headers
- [ ] Hex.5.4.5.2 Parse `X-RateLimit-Remaining` header
- [ ] Hex.5.4.5.3 Parse `X-RateLimit-Reset` header
- [ ] Hex.5.4.5.4 Update state with API limits
- [ ] Hex.5.4.5.5 Implement `adaptive_delay/1` calculating extra delay
- [ ] Hex.5.4.5.6 Return higher delay when API remaining is low
- [ ] Hex.5.4.5.7 Return 0 when plenty of API calls remaining

- [ ] **Task Hex.5.4 Complete**

**Section Hex.5 Unit Tests:**

- [ ] Test Config struct validation
- [ ] Test Config defaults
- [ ] Test init creates directories
- [ ] Test init loads progress
- [ ] Test run processes packages
- [ ] Test run respects limit
- [ ] Test run skips processed packages
- [ ] Test process_package success flow
- [ ] Test process_package error handling
- [ ] Test progress checkpoint saving
- [ ] Test interruption handling
- [ ] Test analyze_package calls ProjectAnalyzer
- [ ] Test analyze_package timeout
- [ ] Test metadata extraction
- [ ] Test output_path generation
- [ ] Test output_path sanitization
- [ ] Test save_graph writes file
- [ ] Test list_outputs finds files
- [ ] Test output_exists? detection
- [ ] Test disk space monitoring
- [ ] Test token bucket initialization
- [ ] Test token refill calculation
- [ ] Test token consumption
- [ ] Test acquire blocking
- [ ] Test adaptive delay calculation
- [ ] Test header parsing for rate limits
- [ ] Test dry_run mode
- [ ] Test verbose logging

**Target: 28 unit tests**
