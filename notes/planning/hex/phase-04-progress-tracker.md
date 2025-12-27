# Phase Hex.4: Progress Tracker

This phase implements persistent progress tracking enabling resume capability after interruptions. The progress tracker maintains state in a JSON file and provides failure categorization for debugging.

## Hex.4.1 Progress State Model

Define the data structures for tracking batch processing progress.

### Hex.4.1.1 Create Progress Module

Create `lib/elixir_ontologies/hex/progress.ex` with progress state structures.

- [ ] Hex.4.1.1.1 Create `lib/elixir_ontologies/hex/progress.ex` module
- [ ] Hex.4.1.1.2 Define `@moduledoc` describing progress tracking

### Hex.4.1.2 Define Progress Struct

Define main progress tracking struct.

- [ ] Hex.4.1.2.1 Define `%Progress{}` struct
- [ ] Hex.4.1.2.2 Add field `started_at` (DateTime) - batch start time
- [ ] Hex.4.1.2.3 Add field `updated_at` (DateTime) - last update time
- [ ] Hex.4.1.2.4 Add field `total_packages` (integer | nil) - total count if known
- [ ] Hex.4.1.2.5 Add field `processed` (list) - list of `%PackageResult{}`
- [ ] Hex.4.1.2.6 Add field `current_page` (integer) - current API page
- [ ] Hex.4.1.2.7 Add field `config` (map) - configuration snapshot

### Hex.4.1.3 Define PackageResult Struct

Define struct to track individual package results.

- [ ] Hex.4.1.3.1 Define `%PackageResult{}` struct
- [ ] Hex.4.1.3.2 Add field `name` (string) - package name
- [ ] Hex.4.1.3.3 Add field `version` (string) - package version
- [ ] Hex.4.1.3.4 Add field `status` (atom) - :completed, :failed, :skipped
- [ ] Hex.4.1.3.5 Add field `output_path` (string | nil) - TTL file path
- [ ] Hex.4.1.3.6 Add field `error` (string | nil) - error message if failed
- [ ] Hex.4.1.3.7 Add field `error_type` (atom | nil) - error category
- [ ] Hex.4.1.3.8 Add field `duration_ms` (integer) - processing time
- [ ] Hex.4.1.3.9 Add field `module_count` (integer | nil) - modules analyzed
- [ ] Hex.4.1.3.10 Add field `processed_at` (DateTime) - completion time

### Hex.4.1.4 Implement Progress Functions

Implement functions to manipulate progress state.

- [ ] Hex.4.1.4.1 Implement `new/1` creating initial progress with config
- [ ] Hex.4.1.4.2 Implement `add_result/2` adding `%PackageResult{}` to processed
- [ ] Hex.4.1.4.3 Implement `update_page/2` updating current_page
- [ ] Hex.4.1.4.4 Implement `is_processed?/2` checking if package already processed
- [ ] Hex.4.1.4.5 Implement `processed_count/1` returning count of processed
- [ ] Hex.4.1.4.6 Implement `failed_count/1` returning count of failed
- [ ] Hex.4.1.4.7 Implement `skipped_count/1` returning count of skipped
- [ ] Hex.4.1.4.8 Implement `success_count/1` returning count of completed

### Hex.4.1.5 Implement Summary Functions

Implement functions to generate progress summaries.

- [ ] Hex.4.1.5.1 Implement `summary/1` returning stats map
- [ ] Hex.4.1.5.2 Include `total_processed`, `succeeded`, `failed`, `skipped`
- [ ] Hex.4.1.5.3 Include `duration_seconds` (elapsed time)
- [ ] Hex.4.1.5.4 Include `avg_duration_ms` (average per package)
- [ ] Hex.4.1.5.5 Include `estimated_remaining_seconds` if total known
- [ ] Hex.4.1.5.6 Implement `format_summary/1` returning human-readable string

- [ ] **Task Hex.4.1 Complete**

## Hex.4.2 Progress Persistence

Implement JSON-based persistence for progress state.

### Hex.4.2.1 Create Progress Store Module

Create `lib/elixir_ontologies/hex/progress_store.ex` for file operations.

- [ ] Hex.4.2.1.1 Create `lib/elixir_ontologies/hex/progress_store.ex` module
- [ ] Hex.4.2.1.2 Define `@moduledoc` describing progress persistence
- [ ] Hex.4.2.1.3 Define `@checkpoint_interval` as 10 (save every N packages)

### Hex.4.2.2 Implement JSON Serialization

Implement serialization to/from JSON.

- [ ] Hex.4.2.2.1 Implement `to_json/1` converting `%Progress{}` to JSON string
- [ ] Hex.4.2.2.2 Handle DateTime serialization to ISO 8601
- [ ] Hex.4.2.2.3 Handle nested `%PackageResult{}` structs
- [ ] Hex.4.2.2.4 Use Jason for JSON encoding with pretty printing
- [ ] Hex.4.2.2.5 Implement `from_json/1` parsing JSON to `%Progress{}`
- [ ] Hex.4.2.2.6 Handle DateTime deserialization from ISO 8601
- [ ] Hex.4.2.2.7 Reconstruct `%PackageResult{}` structs

### Hex.4.2.3 Implement Save Function

Implement atomic save to file.

- [ ] Hex.4.2.3.1 Implement `save/2` accepting progress and file_path
- [ ] Hex.4.2.3.2 Convert progress to JSON with `to_json/1`
- [ ] Hex.4.2.3.3 Write to temporary file first (atomic write pattern)
- [ ] Hex.4.2.3.4 Rename temp file to final path (atomic)
- [ ] Hex.4.2.3.5 Return `:ok` on success
- [ ] Hex.4.2.3.6 Return `{:error, reason}` on failure
- [ ] Hex.4.2.3.7 Ensure parent directory exists

### Hex.4.2.4 Implement Load Function

Implement loading from file.

- [ ] Hex.4.2.4.1 Implement `load/1` accepting file_path
- [ ] Hex.4.2.4.2 Read file contents
- [ ] Hex.4.2.4.3 Parse JSON with `from_json/1`
- [ ] Hex.4.2.4.4 Return `{:ok, %Progress{}}`
- [ ] Hex.4.2.4.5 Return `{:error, :not_found}` if file doesn't exist
- [ ] Hex.4.2.4.6 Return `{:error, :invalid_json}` if parsing fails

### Hex.4.2.5 Implement Load or Create

Implement resumption logic.

- [ ] Hex.4.2.5.1 Implement `load_or_create/2` accepting file_path and config
- [ ] Hex.4.2.5.2 Try `load/1` first
- [ ] Hex.4.2.5.3 If file exists, return loaded progress
- [ ] Hex.4.2.5.4 If file doesn't exist, create new progress with `Progress.new/1`
- [ ] Hex.4.2.5.5 Return `{:ok, %Progress{}, :resumed | :new}`

### Hex.4.2.6 Implement Checkpoint Logic

Implement periodic checkpointing.

- [ ] Hex.4.2.6.1 Implement `should_checkpoint?/1` checking interval
- [ ] Hex.4.2.6.2 Return true every `@checkpoint_interval` packages
- [ ] Hex.4.2.6.3 Implement `checkpoint/2` saving if interval reached
- [ ] Hex.4.2.6.4 Always save on checkpoint call
- [ ] Hex.4.2.6.5 Update `updated_at` timestamp before save

- [ ] **Task Hex.4.2 Complete**

## Hex.4.3 Failure Tracking

Implement detailed failure tracking for debugging and retry capability.

### Hex.4.3.1 Create Failure Tracker Module

Create `lib/elixir_ontologies/hex/failure_tracker.ex` for failure categorization.

- [ ] Hex.4.3.1.1 Create `lib/elixir_ontologies/hex/failure_tracker.ex` module
- [ ] Hex.4.3.1.2 Define `@moduledoc` describing failure tracking

### Hex.4.3.2 Define Error Types

Define error type categories.

- [ ] Hex.4.3.2.1 Define `@error_types` list of atoms
- [ ] Hex.4.3.2.2 Include `:download_error` - network/HTTP failures
- [ ] Hex.4.3.2.3 Include `:extraction_error` - tarball unpacking failures
- [ ] Hex.4.3.2.4 Include `:analysis_error` - ProjectAnalyzer failures
- [ ] Hex.4.3.2.5 Include `:output_error` - TTL writing failures
- [ ] Hex.4.3.2.6 Include `:timeout` - processing timeout
- [ ] Hex.4.3.2.7 Include `:not_elixir` - Erlang-only package
- [ ] Hex.4.3.2.8 Include `:unknown` - unclassified errors

### Hex.4.3.3 Implement Error Classification

Implement functions to classify errors.

- [ ] Hex.4.3.3.1 Implement `classify_error/1` accepting error term
- [ ] Hex.4.3.3.2 Match HTTP errors to `:download_error`
- [ ] Hex.4.3.3.3 Match tarball errors to `:extraction_error`
- [ ] Hex.4.3.3.4 Match analysis exceptions to `:analysis_error`
- [ ] Hex.4.3.3.5 Match file write errors to `:output_error`
- [ ] Hex.4.3.3.6 Match timeout to `:timeout`
- [ ] Hex.4.3.3.7 Return `:unknown` for unrecognized errors

### Hex.4.3.4 Implement Failure Recording

Implement functions to record failures.

- [ ] Hex.4.3.4.1 Implement `record_failure/4` accepting name, version, error, stacktrace
- [ ] Hex.4.3.4.2 Classify error with `classify_error/1`
- [ ] Hex.4.3.4.3 Format error message as string
- [ ] Hex.4.3.4.4 Format stacktrace as string (first 5 frames)
- [ ] Hex.4.3.4.5 Create `%PackageResult{}` with failure info
- [ ] Hex.4.3.4.6 Return `%PackageResult{status: :failed, ...}`

### Hex.4.3.5 Implement Failure Analysis

Implement functions to analyze failures.

- [ ] Hex.4.3.5.1 Implement `failures_by_type/1` accepting list of results
- [ ] Hex.4.3.5.2 Group failed results by `error_type`
- [ ] Hex.4.3.5.3 Return map of `%{error_type => [%PackageResult{}]}`
- [ ] Hex.4.3.5.4 Implement `retry_candidates/1` returning retryable failures
- [ ] Hex.4.3.5.5 Consider `:download_error` and `:timeout` as retryable
- [ ] Hex.4.3.5.6 Exclude `:not_elixir` from retry candidates

### Hex.4.3.6 Implement Failure Export

Implement functions to export failures for analysis.

- [ ] Hex.4.3.6.1 Implement `export_failures/2` accepting progress and file_path
- [ ] Hex.4.3.6.2 Extract all failed results from progress
- [ ] Hex.4.3.6.3 Group by error type
- [ ] Hex.4.3.6.4 Write to JSON file with details
- [ ] Hex.4.3.6.5 Include summary statistics
- [ ] Hex.4.3.6.6 Return `:ok` on success

- [ ] **Task Hex.4.3 Complete**

**Section Hex.4 Unit Tests:**

- [ ] Test Progress struct creation
- [ ] Test add_result updates processed list
- [ ] Test is_processed? detects processed packages
- [ ] Test processed_count accuracy
- [ ] Test failed_count accuracy
- [ ] Test summary calculation
- [ ] Test to_json serialization
- [ ] Test from_json deserialization
- [ ] Test DateTime serialization roundtrip
- [ ] Test nested struct serialization
- [ ] Test save creates file
- [ ] Test save uses atomic write
- [ ] Test load reads file
- [ ] Test load handles missing file
- [ ] Test load handles invalid JSON
- [ ] Test load_or_create creates new
- [ ] Test load_or_create resumes existing
- [ ] Test should_checkpoint interval
- [ ] Test checkpoint saves file
- [ ] Test classify_error categories
- [ ] Test record_failure creates result
- [ ] Test failures_by_type grouping
- [ ] Test retry_candidates filtering
- [ ] Test export_failures writes file
- [ ] Test format_summary output
- [ ] Test update_page updates state
- [ ] Test concurrent access handling
- [ ] Test large progress file handling
- [ ] Test corrupted file recovery
- [ ] Test estimated_remaining calculation

**Target: 30 unit tests**
