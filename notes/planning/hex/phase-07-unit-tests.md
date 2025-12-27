# Phase Hex.7: Unit Tests

This phase specifies comprehensive unit tests for all Hex batch analyzer components. Tests should be created alongside each module during implementation, but this phase documents the complete test specifications.

## Hex.7.1 HTTP Client Tests

Unit tests for `lib/elixir_ontologies/hex/http_client.ex`.

### Hex.7.1.1 Client Creation Tests

- [ ] Hex.7.1.1.1 Create `test/elixir_ontologies/hex/http_client_test.exs`
- [ ] Hex.7.1.1.2 Test `new/0` creates client with defaults
- [ ] Hex.7.1.1.3 Test `new/1` accepts custom timeout
- [ ] Hex.7.1.1.4 Test `new/1` accepts custom retry count
- [ ] Hex.7.1.1.5 Test User-Agent header format is correct
- [ ] Hex.7.1.1.6 Test client includes Elixir version in User-Agent

### Hex.7.1.2 GET Request Tests

- [ ] Hex.7.1.2.1 Use Bypass to mock HTTP server
- [ ] Hex.7.1.2.2 Test `get/2` returns `{:ok, response}` for 200
- [ ] Hex.7.1.2.3 Test `get/2` returns `{:error, :not_found}` for 404
- [ ] Hex.7.1.2.4 Test `get/2` returns `{:error, :rate_limited}` for 429
- [ ] Hex.7.1.2.5 Test `get/2` retries on 500 status
- [ ] Hex.7.1.2.6 Test `get/2` retries on 503 status
- [ ] Hex.7.1.2.7 Test `get/2` returns error on connection failure

### Hex.7.1.3 Download Tests

- [ ] Hex.7.1.3.1 Test `download/3` streams to file
- [ ] Hex.7.1.3.2 Test `download/3` creates parent directory
- [ ] Hex.7.1.3.3 Test `download/3` handles large files
- [ ] Hex.7.1.3.4 Test `download/3` cleans up on failure
- [ ] Hex.7.1.3.5 Test `download/3` returns error for 404

### Hex.7.1.4 Rate Limit Tests

- [ ] Hex.7.1.4.1 Test `extract_rate_limit/1` parses headers
- [ ] Hex.7.1.4.2 Test `extract_rate_limit/1` handles missing headers
- [ ] Hex.7.1.4.3 Test `rate_limit_delay/1` returns 0 when plenty remaining
- [ ] Hex.7.1.4.4 Test `rate_limit_delay/1` increases when low

- [ ] **Task Hex.7.1 Complete**

## Hex.7.2 API Client Tests

Unit tests for `lib/elixir_ontologies/hex/api.ex`.

### Hex.7.2.1 Package Struct Tests

- [ ] Hex.7.2.1.1 Create `test/elixir_ontologies/hex/api_test.exs`
- [ ] Hex.7.2.1.2 Test `Package.from_json/1` parses all fields
- [ ] Hex.7.2.1.3 Test `Package.from_json/1` handles missing optional fields
- [ ] Hex.7.2.1.4 Test `Package.from_json/1` parses DateTime fields

### Hex.7.2.2 Package Listing Tests

- [ ] Hex.7.2.2.1 Test `list_packages/2` returns page of packages
- [ ] Hex.7.2.2.2 Test `list_packages/2` with page option
- [ ] Hex.7.2.2.3 Test `list_packages/2` with sort option
- [ ] Hex.7.2.2.4 Test `list_packages/2` handles empty response
- [ ] Hex.7.2.2.5 Test `list_packages/2` handles API error

### Hex.7.2.3 Stream Tests

- [ ] Hex.7.2.3.1 Test `stream_all_packages/1` returns stream
- [ ] Hex.7.2.3.2 Test stream fetches multiple pages
- [ ] Hex.7.2.3.3 Test stream stops on empty page
- [ ] Hex.7.2.3.4 Test stream respects delay_ms option
- [ ] Hex.7.2.3.5 Test stream handles rate limiting

### Hex.7.2.4 Single Package Tests

- [ ] Hex.7.2.4.1 Test `get_package/2` returns package
- [ ] Hex.7.2.4.2 Test `get_package/2` handles not found
- [ ] Hex.7.2.4.3 Test `latest_stable_version/1` selects stable
- [ ] Hex.7.2.4.4 Test `latest_stable_version/1` handles prereleases
- [ ] Hex.7.2.4.5 Test `is_prerelease?/1` detection

- [ ] **Task Hex.7.2 Complete**

## Hex.7.3 Filter Tests

Unit tests for `lib/elixir_ontologies/hex/filter.ex`.

### Hex.7.3.1 Metadata Filter Tests

- [ ] Hex.7.3.1.1 Create `test/elixir_ontologies/hex/filter_test.exs`
- [ ] Hex.7.3.1.2 Test `likely_elixir_package?/1` with Elixir indicators
- [ ] Hex.7.3.1.3 Test `likely_elixir_package?/1` with Erlang indicators
- [ ] Hex.7.3.1.4 Test `likely_elixir_package?/1` returns :unknown

### Hex.7.3.2 Source Filter Tests

- [ ] Hex.7.3.2.1 Test `has_elixir_source?/1` finds .ex files
- [ ] Hex.7.3.2.2 Test `has_elixir_source?/1` rejects Erlang-only
- [ ] Hex.7.3.2.3 Test `has_mix_project?/1` finds mix.exs
- [ ] Hex.7.3.2.4 Test `has_mix_project?/1` handles missing

### Hex.7.3.3 Stream Filter Tests

- [ ] Hex.7.3.3.1 Test `filter_likely_elixir/1` filters stream
- [ ] Hex.7.3.3.2 Test filter passes unknown packages

- [ ] **Task Hex.7.3 Complete**

## Hex.7.4 Downloader Tests

Unit tests for `lib/elixir_ontologies/hex/downloader.ex`.

### Hex.7.4.1 URL Generation Tests

- [ ] Hex.7.4.1.1 Create `test/elixir_ontologies/hex/downloader_test.exs`
- [ ] Hex.7.4.1.2 Test `tarball_url/2` format
- [ ] Hex.7.4.1.3 Test `tarball_url/2` with special characters
- [ ] Hex.7.4.1.4 Test `tarball_filename/2` format

### Hex.7.4.2 Download Tests

- [ ] Hex.7.4.2.1 Test `download/4` success path
- [ ] Hex.7.4.2.2 Test `download/4` creates directory
- [ ] Hex.7.4.2.3 Test `download/4` handles 404
- [ ] Hex.7.4.2.4 Test `download_to_temp/3` creates temp dir
- [ ] Hex.7.4.2.5 Test `download_to_temp/3` returns paths

- [ ] **Task Hex.7.4 Complete**

## Hex.7.5 Extractor Tests

Unit tests for `lib/elixir_ontologies/hex/extractor.ex`.

### Hex.7.5.1 Outer Tar Tests

- [ ] Hex.7.5.1.1 Create `test/elixir_ontologies/hex/extractor_test.exs`
- [ ] Hex.7.5.1.2 Create test fixture: valid hex tarball
- [ ] Hex.7.5.1.3 Create test fixture: invalid tarball
- [ ] Hex.7.5.1.4 Test `extract_outer/2` extracts files
- [ ] Hex.7.5.1.5 Test `extract_outer/2` validates structure
- [ ] Hex.7.5.1.6 Test `extract_outer/2` handles invalid

### Hex.7.5.2 Contents Tests

- [ ] Hex.7.5.2.1 Test `extract_contents/2` extracts source
- [ ] Hex.7.5.2.2 Test `extract_contents/2` verifies mix.exs
- [ ] Hex.7.5.2.3 Test `extract_contents/2` handles Erlang-only

### Hex.7.5.3 Full Extraction Tests

- [ ] Hex.7.5.3.1 Test `extract/2` full pipeline
- [ ] Hex.7.5.3.2 Test `extract/2` cleans up on failure
- [ ] Hex.7.5.3.3 Test `extract_metadata/1` parses config

### Hex.7.5.4 Cleanup Tests

- [ ] Hex.7.5.4.1 Test `cleanup/1` removes directory
- [ ] Hex.7.5.4.2 Test `cleanup/1` handles missing
- [ ] Hex.7.5.4.3 Test `cleanup_tarball/1` removes file

- [ ] **Task Hex.7.5 Complete**

## Hex.7.6 Package Handler Tests

Unit tests for `lib/elixir_ontologies/hex/package_handler.ex`.

### Hex.7.6.1 Context Tests

- [ ] Hex.7.6.1.1 Create `test/elixir_ontologies/hex/package_handler_test.exs`
- [ ] Hex.7.6.1.2 Test `%Context{}` struct creation
- [ ] Hex.7.6.1.3 Test context status transitions

### Hex.7.6.2 Prepare Tests

- [ ] Hex.7.6.2.1 Test `prepare/4` downloads and extracts
- [ ] Hex.7.6.2.2 Test `prepare/4` handles download failure
- [ ] Hex.7.6.2.3 Test `prepare/4` handles extraction failure

### Hex.7.6.3 Cleanup Tests

- [ ] Hex.7.6.3.1 Test `cleanup/1` removes all temp files
- [ ] Hex.7.6.3.2 Test `cleanup/1` handles partial state

### Hex.7.6.4 With-Package Tests

- [ ] Hex.7.6.4.1 Test `with_package/5` callback pattern
- [ ] Hex.7.6.4.2 Test `with_package/5` cleanup on success
- [ ] Hex.7.6.4.3 Test `with_package/5` cleanup on callback error
- [ ] Hex.7.6.4.4 Test `with_package/5` cleanup on prepare failure

- [ ] **Task Hex.7.6 Complete**

## Hex.7.7 Progress Tests

Unit tests for `lib/elixir_ontologies/hex/progress.ex` and `progress_store.ex`.

### Hex.7.7.1 Progress Model Tests

- [ ] Hex.7.7.1.1 Create `test/elixir_ontologies/hex/progress_test.exs`
- [ ] Hex.7.7.1.2 Test `Progress.new/1` creation
- [ ] Hex.7.7.1.3 Test `add_result/2` updates list
- [ ] Hex.7.7.1.4 Test `is_processed?/2` detection
- [ ] Hex.7.7.1.5 Test count functions accuracy
- [ ] Hex.7.7.1.6 Test `summary/1` calculation

### Hex.7.7.2 Serialization Tests

- [ ] Hex.7.7.2.1 Create `test/elixir_ontologies/hex/progress_store_test.exs`
- [ ] Hex.7.7.2.2 Test `to_json/1` serialization
- [ ] Hex.7.7.2.3 Test `from_json/1` deserialization
- [ ] Hex.7.7.2.4 Test DateTime roundtrip
- [ ] Hex.7.7.2.5 Test nested struct handling

### Hex.7.7.3 Persistence Tests

- [ ] Hex.7.7.3.1 Test `save/2` creates file
- [ ] Hex.7.7.3.2 Test `save/2` atomic write
- [ ] Hex.7.7.3.3 Test `load/1` reads file
- [ ] Hex.7.7.3.4 Test `load/1` handles missing
- [ ] Hex.7.7.3.5 Test `load/1` handles invalid JSON
- [ ] Hex.7.7.3.6 Test `load_or_create/2` resume
- [ ] Hex.7.7.3.7 Test `load_or_create/2` new
- [ ] Hex.7.7.3.8 Test checkpoint interval

- [ ] **Task Hex.7.7 Complete**

## Hex.7.8 Failure Tracker Tests

Unit tests for `lib/elixir_ontologies/hex/failure_tracker.ex`.

### Hex.7.8.1 Classification Tests

- [ ] Hex.7.8.1.1 Create `test/elixir_ontologies/hex/failure_tracker_test.exs`
- [ ] Hex.7.8.1.2 Test `classify_error/1` for each type
- [ ] Hex.7.8.1.3 Test `classify_error/1` unknown handling

### Hex.7.8.2 Recording Tests

- [ ] Hex.7.8.2.1 Test `record_failure/4` creates result
- [ ] Hex.7.8.2.2 Test stacktrace formatting

### Hex.7.8.3 Analysis Tests

- [ ] Hex.7.8.3.1 Test `failures_by_type/1` grouping
- [ ] Hex.7.8.3.2 Test `retry_candidates/1` filtering
- [ ] Hex.7.8.3.3 Test `export_failures/2` output

- [ ] **Task Hex.7.8 Complete**

## Hex.7.9 Batch Processor Tests

Unit tests for batch processor components.

### Hex.7.9.1 Config Tests

- [ ] Hex.7.9.1.1 Create `test/elixir_ontologies/hex/batch_processor_test.exs`
- [ ] Hex.7.9.1.2 Test `Config.new/1` defaults
- [ ] Hex.7.9.1.3 Test `Config.validate/1` required fields

### Hex.7.9.2 Analyzer Adapter Tests

- [ ] Hex.7.9.2.1 Create `test/elixir_ontologies/hex/analyzer_adapter_test.exs`
- [ ] Hex.7.9.2.2 Test `analyze_package/3` calls ProjectAnalyzer
- [ ] Hex.7.9.2.3 Test timeout handling
- [ ] Hex.7.9.2.4 Test metadata extraction

### Hex.7.9.3 Output Manager Tests

- [ ] Hex.7.9.3.1 Create `test/elixir_ontologies/hex/output_manager_test.exs`
- [ ] Hex.7.9.3.2 Test `output_path/3` generation
- [ ] Hex.7.9.3.3 Test `sanitize_name/1`
- [ ] Hex.7.9.3.4 Test `save_graph/4` writes file
- [ ] Hex.7.9.3.5 Test `list_outputs/1` enumeration
- [ ] Hex.7.9.3.6 Test `output_exists?/3` detection

### Hex.7.9.4 Rate Limiter Tests

- [ ] Hex.7.9.4.1 Create `test/elixir_ontologies/hex/rate_limiter_test.exs`
- [ ] Hex.7.9.4.2 Test token bucket initialization
- [ ] Hex.7.9.4.3 Test token refill
- [ ] Hex.7.9.4.4 Test token consumption
- [ ] Hex.7.9.4.5 Test `acquire/1` blocking
- [ ] Hex.7.9.4.6 Test adaptive delay

- [ ] **Task Hex.7.9 Complete**

## Hex.7.10 Mix Task Tests

Unit tests for the Mix task.

### Hex.7.10.1 Option Parsing Tests

- [ ] Hex.7.10.1.1 Create `test/mix/tasks/elixir_ontologies.hex_batch_test.exs`
- [ ] Hex.7.10.1.2 Test option parsing
- [ ] Hex.7.10.1.3 Test required output_dir
- [ ] Hex.7.10.1.4 Test Config building

### Hex.7.10.2 Progress Display Tests

- [ ] Hex.7.10.2.1 Create `test/elixir_ontologies/hex/progress_display_test.exs`
- [ ] Hex.7.10.2.2 Test `status_line/1` format
- [ ] Hex.7.10.2.3 Test ETA calculation
- [ ] Hex.7.10.2.4 Test `stats_line/1` format

- [ ] **Task Hex.7.10 Complete**

**Section Hex.7 Summary:**

Total unit tests specified: ~100+ across all modules

| Module | Test Count |
|--------|------------|
| http_client | 15 |
| api | 15 |
| filter | 8 |
| downloader | 8 |
| extractor | 12 |
| package_handler | 10 |
| progress | 8 |
| progress_store | 10 |
| failure_tracker | 8 |
| batch_processor | 4 |
| analyzer_adapter | 4 |
| output_manager | 6 |
| rate_limiter | 6 |
| mix task | 4 |
| progress_display | 4 |
