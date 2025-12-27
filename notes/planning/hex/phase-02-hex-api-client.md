# Phase Hex.2: Hex API Client

This phase implements the Hex.pm API client for package listing, metadata retrieval, and Elixir package filtering. The API client provides paginated access to all packages on hex.pm with proper rate limiting.

## Hex.2.1 Package Listing API

Create the core Hex.pm API client for retrieving package information.

### Hex.2.1.1 Create API Module

Create `lib/elixir_ontologies/hex/api.ex` with API client functionality.

- [ ] Hex.2.1.1.1 Create `lib/elixir_ontologies/hex/api.ex` module
- [ ] Hex.2.1.1.2 Define `@moduledoc` describing the Hex.pm API client
- [ ] Hex.2.1.1.3 Define `@hex_api_url` as `"https://hex.pm/api"`
- [ ] Hex.2.1.1.4 Define `@hex_repo_url` as `"https://repo.hex.pm"`
- [ ] Hex.2.1.1.5 Define `@default_page_size` as 100 (Hex.pm default)

### Hex.2.1.2 Define Package Struct

Define struct to represent package metadata.

- [ ] Hex.2.1.2.1 Define `%Package{}` struct in `lib/elixir_ontologies/hex/api.ex`
- [ ] Hex.2.1.2.2 Add field `name` (string) - package name
- [ ] Hex.2.1.2.3 Add field `latest_version` (string) - latest stable version
- [ ] Hex.2.1.2.4 Add field `latest_stable_version` (string | nil) - explicit stable version
- [ ] Hex.2.1.2.5 Add field `releases` (list) - list of release maps
- [ ] Hex.2.1.2.6 Add field `meta` (map) - package metadata (description, links, licenses)
- [ ] Hex.2.1.2.7 Add field `downloads` (map) - download statistics
- [ ] Hex.2.1.2.8 Add field `inserted_at` (DateTime) - creation timestamp
- [ ] Hex.2.1.2.9 Add field `updated_at` (DateTime) - last update timestamp
- [ ] Hex.2.1.2.10 Implement `from_json/1` to parse API response into struct

### Hex.2.1.3 Implement Single Page Fetch

Implement function to fetch a single page of packages.

- [ ] Hex.2.1.3.1 Implement `list_packages/2` accepting client and options
- [ ] Hex.2.1.3.2 Accept `page` option (default: 1)
- [ ] Hex.2.1.3.3 Accept `sort` option (default: "name")
- [ ] Hex.2.1.3.4 Build URL: `"#{@hex_api_url}/packages?page=#{page}&sort=#{sort}"`
- [ ] Hex.2.1.3.5 Call `HttpClient.get/2` with URL
- [ ] Hex.2.1.3.6 Parse JSON response body
- [ ] Hex.2.1.3.7 Map each item through `Package.from_json/1`
- [ ] Hex.2.1.3.8 Return `{:ok, [%Package{}], rate_limit_info}`
- [ ] Hex.2.1.3.9 Return `{:error, reason}` on failure

### Hex.2.1.4 Implement Paginated Stream

Implement lazy stream that fetches all packages across pages.

- [ ] Hex.2.1.4.1 Implement `stream_all_packages/1` accepting client
- [ ] Hex.2.1.4.2 Implement `stream_all_packages/2` accepting client and options
- [ ] Hex.2.1.4.3 Accept `delay_ms` option for inter-page delay (default: 1000)
- [ ] Hex.2.1.4.4 Accept `start_page` option (default: 1)
- [ ] Hex.2.1.4.5 Use `Stream.resource/3` for lazy evaluation
- [ ] Hex.2.1.4.6 Initialize with starting page number
- [ ] Hex.2.1.4.7 Fetch page, emit packages, increment page
- [ ] Hex.2.1.4.8 Apply `delay_ms` between page fetches
- [ ] Hex.2.1.4.9 Halt when empty page received (end of packages)
- [ ] Hex.2.1.4.10 Handle rate limiting by waiting and retrying
- [ ] Hex.2.1.4.11 Return `Stream.t()` of `%Package{}`

### Hex.2.1.5 Implement Single Package Fetch

Implement function to fetch metadata for a single package.

- [ ] Hex.2.1.5.1 Implement `get_package/2` accepting client and package name
- [ ] Hex.2.1.5.2 Build URL: `"#{@hex_api_url}/packages/#{name}"`
- [ ] Hex.2.1.5.3 Call `HttpClient.get/2` with URL
- [ ] Hex.2.1.5.4 Parse JSON response into `%Package{}`
- [ ] Hex.2.1.5.5 Return `{:ok, %Package{}}`
- [ ] Hex.2.1.5.6 Return `{:error, :not_found}` for missing package
- [ ] Hex.2.1.5.7 Return `{:error, reason}` for other failures

### Hex.2.1.6 Implement Version Selection

Implement logic to select the best version to analyze.

- [ ] Hex.2.1.6.1 Implement `latest_stable_version/1` accepting `%Package{}`
- [ ] Hex.2.1.6.2 Return `latest_stable_version` field if present
- [ ] Hex.2.1.6.3 Fall back to first non-prerelease in `releases`
- [ ] Hex.2.1.6.4 Fall back to latest version if all are prereleases
- [ ] Hex.2.1.6.5 Implement `is_prerelease?/1` checking for `-alpha`, `-beta`, `-rc`
- [ ] Hex.2.1.6.6 Return version string

- [ ] **Task Hex.2.1 Complete**

## Hex.2.2 Package Filtering

Implement filtering logic to identify Elixir packages and skip Erlang-only packages.

### Hex.2.2.1 Create Filter Module

Create `lib/elixir_ontologies/hex/filter.ex` for package filtering.

- [ ] Hex.2.2.1.1 Create `lib/elixir_ontologies/hex/filter.ex` module
- [ ] Hex.2.2.1.2 Define `@moduledoc` describing package filtering
- [ ] Hex.2.2.1.3 Define `@elixir_indicators` list of metadata patterns

### Hex.2.2.2 Implement Metadata-Based Filtering

Implement heuristics to detect Elixir packages from metadata.

- [ ] Hex.2.2.2.1 Implement `likely_elixir_package?/1` accepting `%Package{}`
- [ ] Hex.2.2.2.2 Check if `meta.links` contains "GitHub" with `/elixir` path
- [ ] Hex.2.2.2.3 Check if `meta.licenses` includes common Elixir licenses
- [ ] Hex.2.2.2.4 Check if package name follows Elixir conventions (snake_case)
- [ ] Hex.2.2.2.5 Return `true` if any indicator matches
- [ ] Hex.2.2.2.6 Return `:unknown` if no strong indicators

### Hex.2.2.3 Implement Source-Based Filtering

Implement filtering by checking extracted source files.

- [ ] Hex.2.2.3.1 Implement `has_elixir_source?/1` accepting extracted path
- [ ] Hex.2.2.3.2 Search for `**/*.ex` files using `Path.wildcard/1`
- [ ] Hex.2.2.3.3 Return `true` if any `.ex` files found
- [ ] Hex.2.2.3.4 Return `false` if only `.erl` files present
- [ ] Hex.2.2.3.5 Implement `has_mix_project?/1` checking for `mix.exs`
- [ ] Hex.2.2.3.6 Return `true` if `mix.exs` exists in root

### Hex.2.2.4 Implement Stream Filtering

Implement filtering for package streams.

- [ ] Hex.2.2.4.1 Implement `filter_likely_elixir/1` accepting package stream
- [ ] Hex.2.2.4.2 Use `Stream.filter/2` with `likely_elixir_package?/1`
- [ ] Hex.2.2.4.3 Pass through packages with `:unknown` for later verification
- [ ] Hex.2.2.4.4 Reject packages with clear Erlang indicators

- [ ] **Task Hex.2.2 Complete**

**Section Hex.2 Unit Tests:**

- [ ] Test Package struct creation from JSON
- [ ] Test list_packages returns page of packages
- [ ] Test list_packages with different page numbers
- [ ] Test stream_all_packages starts from page 1
- [ ] Test stream_all_packages stops on empty page
- [ ] Test stream_all_packages respects delay_ms
- [ ] Test get_package returns package metadata
- [ ] Test get_package returns error for missing package
- [ ] Test latest_stable_version selection
- [ ] Test prerelease detection
- [ ] Test likely_elixir_package? with Elixir indicators
- [ ] Test likely_elixir_package? with Erlang indicators
- [ ] Test has_elixir_source? finds .ex files
- [ ] Test has_elixir_source? rejects Erlang-only
- [ ] Test has_mix_project? detects mix.exs
- [ ] Test filter_likely_elixir filters stream
- [ ] Test API error handling (404, 429, 500)
- [ ] Test rate limit header extraction
- [ ] Test JSON parsing errors
- [ ] Test network timeout handling

**Target: 20 unit tests**
