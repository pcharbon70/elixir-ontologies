# Phase Hex.8: Integration Tests

This phase implements integration tests verifying end-to-end workflows for the Hex batch analyzer. Integration tests validate that all components work together correctly.

## Hex.8.1 Full Workflow Integration

Test complete package processing from API to TTL output.

### Hex.8.1.1 Create Integration Test File

Set up integration test infrastructure.

- [ ] Hex.8.1.1.1 Create `test/integration/hex_batch_integration_test.exs`
- [ ] Hex.8.1.1.2 Add `@moduletag :integration` for selective running
- [ ] Hex.8.1.1.3 Set up Bypass for API mocking
- [ ] Hex.8.1.1.4 Create temp directories for output
- [ ] Hex.8.1.1.5 Implement cleanup in `on_exit` callback

### Hex.8.1.2 Single Package End-to-End Test

Test processing a single real package.

- [ ] Hex.8.1.2.1 Test processing `jason` package (small, pure Elixir)
- [ ] Hex.8.1.2.2 Verify TTL file created
- [ ] Hex.8.1.2.3 Verify TTL contains expected module triples
- [ ] Hex.8.1.2.4 Verify TTL contains expected function triples
- [ ] Hex.8.1.2.5 Verify base IRI matches template
- [ ] Hex.8.1.2.6 Verify progress file updated
- [ ] Hex.8.1.2.7 Verify temp files cleaned up

### Hex.8.1.3 Multiple Package Batch Test

Test processing multiple packages in sequence.

- [ ] Hex.8.1.3.1 Mock API to return 3 test packages
- [ ] Hex.8.1.3.2 Process all packages
- [ ] Hex.8.1.3.3 Verify 3 TTL files created
- [ ] Hex.8.1.3.4 Verify progress shows 3 completed
- [ ] Hex.8.1.3.5 Verify inter-package delay respected
- [ ] Hex.8.1.3.6 Verify checkpoint saved periodically

### Hex.8.1.4 Failure Handling Test

Test graceful handling of package failures.

- [ ] Hex.8.1.4.1 Include one valid and one invalid package
- [ ] Hex.8.1.4.2 Verify processing continues after failure
- [ ] Hex.8.1.4.3 Verify failure recorded in progress
- [ ] Hex.8.1.4.4 Verify valid package TTL created
- [ ] Hex.8.1.4.5 Verify error classified correctly

- [ ] **Task Hex.8.1 Complete**

## Hex.8.2 Resume Capability Integration

Test progress persistence and resume functionality.

### Hex.8.2.1 Resume After Interruption

Test resuming from saved progress.

- [ ] Hex.8.2.1.1 Process 2 of 5 packages
- [ ] Hex.8.2.1.2 Save progress and stop
- [ ] Hex.8.2.1.3 Resume with --resume flag
- [ ] Hex.8.2.1.4 Verify skips already-processed packages
- [ ] Hex.8.2.1.5 Verify continues with remaining packages
- [ ] Hex.8.2.1.6 Verify final progress shows all 5

### Hex.8.2.2 Resume After Crash

Simulate crash and verify recovery.

- [ ] Hex.8.2.2.1 Process packages with checkpoint
- [ ] Hex.8.2.2.2 Simulate crash by killing process
- [ ] Hex.8.2.2.3 Resume from progress file
- [ ] Hex.8.2.2.4 Verify progress file integrity
- [ ] Hex.8.2.2.5 Verify no duplicate processing

### Hex.8.2.3 Progress File Corruption

Test handling of corrupted progress files.

- [ ] Hex.8.2.3.1 Create corrupted progress file
- [ ] Hex.8.2.3.2 Attempt to resume
- [ ] Hex.8.2.3.3 Verify graceful error handling
- [ ] Hex.8.2.3.4 Verify option to start fresh

- [ ] **Task Hex.8.2 Complete**

## Hex.8.3 API Interaction Integration

Test Hex.pm API interactions with mocking.

### Hex.8.3.1 Pagination Test

Test handling of paginated API responses.

- [ ] Hex.8.3.1.1 Mock API with 3 pages of packages
- [ ] Hex.8.3.1.2 Stream all packages
- [ ] Hex.8.3.1.3 Verify all pages fetched
- [ ] Hex.8.3.1.4 Verify correct order maintained
- [ ] Hex.8.3.1.5 Verify stops on empty page

### Hex.8.3.2 Rate Limiting Test

Test handling of rate limit responses.

- [ ] Hex.8.3.2.1 Mock API returning 429 on first request
- [ ] Hex.8.3.2.2 Verify retry after delay
- [ ] Hex.8.3.2.3 Verify eventual success
- [ ] Hex.8.3.2.4 Verify rate limit headers parsed

### Hex.8.3.3 Network Error Test

Test handling of network failures.

- [ ] Hex.8.3.3.1 Simulate connection timeout
- [ ] Hex.8.3.3.2 Verify retry behavior
- [ ] Hex.8.3.3.3 Verify error recorded after max retries

- [ ] **Task Hex.8.3 Complete**

## Hex.8.4 Package Type Integration

Test handling of different package types.

### Hex.8.4.1 Elixir Package Test

Test with standard Elixir package.

- [ ] Hex.8.4.1.1 Process pure Elixir package
- [ ] Hex.8.4.1.2 Verify modules extracted
- [ ] Hex.8.4.1.3 Verify functions extracted
- [ ] Hex.8.4.1.4 Verify TTL validates against SHACL

### Hex.8.4.2 Erlang Package Test

Test filtering of Erlang-only packages.

- [ ] Hex.8.4.2.1 Attempt to process Erlang package
- [ ] Hex.8.4.2.2 Verify detected as non-Elixir
- [ ] Hex.8.4.2.3 Verify marked as skipped
- [ ] Hex.8.4.2.4 Verify no TTL created

### Hex.8.4.3 Mixed Package Test

Test package with both Elixir and Erlang.

- [ ] Hex.8.4.3.1 Process mixed package
- [ ] Hex.8.4.3.2 Verify Elixir modules extracted
- [ ] Hex.8.4.3.3 Verify Erlang files ignored

- [ ] **Task Hex.8.4 Complete**

## Hex.8.5 CLI Integration

Test Mix task CLI interface.

### Hex.8.5.1 Basic CLI Test

Test basic command execution.

- [ ] Hex.8.5.1.1 Run `mix elixir_ontologies.hex_batch` with output dir
- [ ] Hex.8.5.1.2 Verify creates output directory
- [ ] Hex.8.5.1.3 Verify creates progress file
- [ ] Hex.8.5.1.4 Verify exit code on success

### Hex.8.5.2 Options Test

Test CLI option handling.

- [ ] Hex.8.5.2.1 Test --limit option
- [ ] Hex.8.5.2.2 Test --package option
- [ ] Hex.8.5.2.3 Test --dry-run option
- [ ] Hex.8.5.2.4 Test --resume option
- [ ] Hex.8.5.2.5 Test --verbose option

### Hex.8.5.3 Error Handling Test

Test CLI error conditions.

- [ ] Hex.8.5.3.1 Test missing output directory argument
- [ ] Hex.8.5.3.2 Test invalid option values
- [ ] Hex.8.5.3.3 Verify error messages

- [ ] **Task Hex.8.5 Complete**

## Hex.8.6 Performance Integration

Test performance characteristics.

### Hex.8.6.1 Memory Usage Test

Test memory remains bounded during processing.

- [ ] Hex.8.6.1.1 Process 10 packages
- [ ] Hex.8.6.1.2 Monitor memory usage
- [ ] Hex.8.6.1.3 Verify no memory leak pattern
- [ ] Hex.8.6.1.4 Verify cleanup effective

### Hex.8.6.2 Disk Cleanup Test

Test temporary files are cleaned up.

- [ ] Hex.8.6.2.1 Process packages
- [ ] Hex.8.6.2.2 Monitor temp directory size
- [ ] Hex.8.6.2.3 Verify size stays bounded
- [ ] Hex.8.6.2.4 Verify no orphaned files

### Hex.8.6.3 Throughput Test

Test processing throughput.

- [ ] Hex.8.6.3.1 Time processing of 5 packages
- [ ] Hex.8.6.3.2 Calculate average per-package time
- [ ] Hex.8.6.3.3 Verify within expected range
- [ ] Hex.8.6.3.4 Verify delay enforcement

- [ ] **Task Hex.8.6 Complete**

**Section Hex.8 Integration Test Summary:**

| Test Category | Test Count |
|---------------|------------|
| Full Workflow | 4 |
| Resume Capability | 3 |
| API Interaction | 3 |
| Package Types | 3 |
| CLI Integration | 3 |
| Performance | 3 |
| **Total** | **19** |

## Integration Test Configuration

```elixir
# test/test_helper.exs additions
ExUnit.configure(exclude: [:integration])

# Run unit tests only (default)
# mix test

# Run integration tests only
# mix test --only integration

# Run all tests
# mix test --include integration
```

## Test Fixtures

Create test fixtures for integration tests:

```
test/fixtures/hex/
├── jason-1.4.1.tar          # Real small package
├── valid_package.tar         # Minimal valid package
├── erlang_only.tar           # Erlang-only package
├── invalid.tar               # Corrupted tarball
└── mock_api_responses/
    ├── packages_page_1.json
    ├── packages_page_2.json
    └── packages_empty.json
```

## Integration Test Environment

```elixir
# config/test.exs additions for integration tests
config :elixir_ontologies, :hex_api_url,
  System.get_env("HEX_API_URL", "http://localhost:4001")

config :elixir_ontologies, :hex_repo_url,
  System.get_env("HEX_REPO_URL", "http://localhost:4002")
```
