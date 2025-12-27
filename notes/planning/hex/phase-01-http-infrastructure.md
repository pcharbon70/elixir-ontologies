# Phase Hex.1: HTTP Infrastructure

This phase establishes the HTTP client foundation using Req with built-in retry, timeout, and rate limiting support. The HTTP client provides the networking layer for all Hex.pm API and tarball download operations.

## Hex.1.1 HTTP Dependencies

Add HTTP client dependencies to enable network operations for the Hex batch analyzer.

### Hex.1.1.1 Add Req Dependency

Add the Req HTTP client library to the project dependencies.

- [ ] Hex.1.1.1.1 Add `{:req, "~> 0.5"}` to deps in `mix.exs`
- [ ] Hex.1.1.1.2 Add `{:castore, "~> 1.0"}` for SSL certificate verification
- [ ] Hex.1.1.1.3 Run `mix deps.get` to fetch dependencies
- [ ] Hex.1.1.1.4 Run `mix compile` to verify compilation succeeds
- [ ] Hex.1.1.1.5 Verify Req module is available in IEx

### Hex.1.1.2 Add Test Dependencies

Add HTTP mocking library for testing.

- [ ] Hex.1.1.2.1 Add `{:bypass, "~> 2.1", only: :test}` to deps in `mix.exs`
- [ ] Hex.1.1.2.2 Run `mix deps.get` to fetch test dependencies
- [ ] Hex.1.1.2.3 Verify Bypass is available in test environment

- [ ] **Task Hex.1.1 Complete**

## Hex.1.2 HTTP Client Wrapper

Create a thin wrapper around Req providing project-specific defaults and consistent error handling.

### Hex.1.2.1 Create HTTP Client Module

Create `lib/elixir_ontologies/hex/http_client.ex` with core HTTP functionality.

- [ ] Hex.1.2.1.1 Create `lib/elixir_ontologies/hex/` directory
- [ ] Hex.1.2.1.2 Create `lib/elixir_ontologies/hex/http_client.ex` module
- [ ] Hex.1.2.1.3 Define `@moduledoc` describing the HTTP client purpose
- [ ] Hex.1.2.1.4 Define `@user_agent` with format `ElixirOntologies/{version} (Elixir/{elixir_version})`
- [ ] Hex.1.2.1.5 Define `@default_timeout` as 30_000 milliseconds
- [ ] Hex.1.2.1.6 Define `@default_retries` as 3

### Hex.1.2.2 Implement Client Creation

Implement `new/1` function to create configured Req client.

- [ ] Hex.1.2.2.1 Implement `new/0` creating client with default options
- [ ] Hex.1.2.2.2 Implement `new/1` accepting keyword options
- [ ] Hex.1.2.2.3 Set User-Agent header from `@user_agent`
- [ ] Hex.1.2.2.4 Configure `receive_timeout` from options or `@default_timeout`
- [ ] Hex.1.2.2.5 Configure `retry` with `:safe_transient` mode
- [ ] Hex.1.2.2.6 Configure `max_retries` from options or `@default_retries`
- [ ] Hex.1.2.2.7 Configure `retry_delay` with exponential backoff function
- [ ] Hex.1.2.2.8 Return `%Req.Request{}` struct

### Hex.1.2.3 Implement GET Requests

Implement `get/2` and `get/3` for JSON API requests.

- [ ] Hex.1.2.3.1 Implement `get/2` accepting client and URL
- [ ] Hex.1.2.3.2 Implement `get/3` accepting client, URL, and options
- [ ] Hex.1.2.3.3 Use `Req.get/2` with merged options
- [ ] Hex.1.2.3.4 Return `{:ok, response}` on success (2xx status)
- [ ] Hex.1.2.3.5 Return `{:error, :not_found}` for 404 responses
- [ ] Hex.1.2.3.6 Return `{:error, :rate_limited}` for 429 responses
- [ ] Hex.1.2.3.7 Return `{:error, {:http_error, status}}` for other errors
- [ ] Hex.1.2.3.8 Return `{:error, reason}` for connection failures

### Hex.1.2.4 Implement Download Streaming

Implement `download/3` for streaming large files to disk.

- [ ] Hex.1.2.4.1 Implement `download/3` accepting client, URL, and file_path
- [ ] Hex.1.2.4.2 Implement `download/4` accepting additional options
- [ ] Hex.1.2.4.3 Open file with `:write` and `:binary` modes
- [ ] Hex.1.2.4.4 Use `Req.get/2` with `into: :self` for streaming
- [ ] Hex.1.2.4.5 Write chunks to file as they arrive
- [ ] Hex.1.2.4.6 Close file handle on completion
- [ ] Hex.1.2.4.7 Return `{:ok, file_path}` on success
- [ ] Hex.1.2.4.8 Return `{:error, reason}` on failure
- [ ] Hex.1.2.4.9 Clean up partial file on failure

### Hex.1.2.5 Implement Rate Limit Tracking

Track rate limit headers for adaptive delay.

- [ ] Hex.1.2.5.1 Define `@rate_limit_headers` list: `["x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset"]`
- [ ] Hex.1.2.5.2 Implement `extract_rate_limit/1` parsing headers from response
- [ ] Hex.1.2.5.3 Return `%{limit: integer, remaining: integer, reset: unix_timestamp}`
- [ ] Hex.1.2.5.4 Return `nil` if headers not present
- [ ] Hex.1.2.5.5 Implement `rate_limit_delay/1` calculating delay when low on remaining
- [ ] Hex.1.2.5.6 Return 0 when remaining > 10% of limit
- [ ] Hex.1.2.5.7 Return increasing delay as remaining approaches 0

- [ ] **Task Hex.1.2 Complete**

**Section Hex.1 Unit Tests:**

- [ ] Test client creation with default options
- [ ] Test client creation with custom timeout
- [ ] Test client creation with custom retry count
- [ ] Test User-Agent header is properly formatted
- [ ] Test GET request returns `{:ok, response}` for 200
- [ ] Test GET request returns `{:error, :not_found}` for 404
- [ ] Test GET request returns `{:error, :rate_limited}` for 429
- [ ] Test GET request retries on 500/503
- [ ] Test download streams to file correctly
- [ ] Test download cleans up partial file on failure
- [ ] Test rate limit header parsing
- [ ] Test rate limit delay calculation
- [ ] Test timeout handling returns error
- [ ] Test connection failure returns error
- [ ] Test exponential backoff between retries

**Target: 15 unit tests**
