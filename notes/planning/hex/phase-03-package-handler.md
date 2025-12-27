# Phase Hex.3: Package Handler

This phase implements package download, tarball extraction (outer tar containing contents.tar.gz), and cleanup operations. The package handler provides the complete lifecycle for processing a single Hex package.

## Hex.3.1 Package Downloader

Create the downloader module for fetching package tarballs from repo.hex.pm.

### Hex.3.1.1 Create Downloader Module

Create `lib/elixir_ontologies/hex/downloader.ex` for tarball downloads.

- [ ] Hex.3.1.1.1 Create `lib/elixir_ontologies/hex/downloader.ex` module
- [ ] Hex.3.1.1.2 Define `@moduledoc` describing package download functionality
- [ ] Hex.3.1.1.3 Define `@repo_url` as `"https://repo.hex.pm"`
- [ ] Hex.3.1.1.4 Define `@tarball_path` as `"/tarballs"`

### Hex.3.1.2 Implement URL Generation

Implement functions to generate download URLs.

- [ ] Hex.3.1.2.1 Implement `tarball_url/2` accepting name and version
- [ ] Hex.3.1.2.2 Return `"#{@repo_url}#{@tarball_path}/#{name}-#{version}.tar"`
- [ ] Hex.3.1.2.3 Handle URL encoding for special characters in names
- [ ] Hex.3.1.2.4 Implement `tarball_filename/2` returning `"#{name}-#{version}.tar"`

### Hex.3.1.3 Implement Download Function

Implement the main download functionality.

- [ ] Hex.3.1.3.1 Implement `download/4` accepting client, name, version, target_path
- [ ] Hex.3.1.3.2 Generate URL using `tarball_url/2`
- [ ] Hex.3.1.3.3 Ensure target directory exists with `File.mkdir_p!/1`
- [ ] Hex.3.1.3.4 Call `HttpClient.download/3` with URL and target path
- [ ] Hex.3.1.3.5 Return `{:ok, target_path}` on success
- [ ] Hex.3.1.3.6 Return `{:error, reason}` on failure
- [ ] Hex.3.1.3.7 Log download progress in verbose mode

### Hex.3.1.4 Implement Temp Download

Implement download to temporary directory.

- [ ] Hex.3.1.4.1 Implement `download_to_temp/3` accepting client, name, version
- [ ] Hex.3.1.4.2 Implement `download_to_temp/4` accepting additional options
- [ ] Hex.3.1.4.3 Accept `temp_dir` option (default: `System.tmp_dir!/0`)
- [ ] Hex.3.1.4.4 Generate unique subdirectory using `make_ref/0`
- [ ] Hex.3.1.4.5 Create temp directory structure
- [ ] Hex.3.1.4.6 Download tarball to temp directory
- [ ] Hex.3.1.4.7 Return `{:ok, tarball_path, temp_dir}`
- [ ] Hex.3.1.4.8 Return `{:error, reason}` on failure

- [ ] **Task Hex.3.1 Complete**

## Hex.3.2 Tarball Extractor

Create the extractor module for unpacking Hex package tarballs.

### Hex.3.2.1 Create Extractor Module

Create `lib/elixir_ontologies/hex/extractor.ex` for tarball extraction.

- [ ] Hex.3.2.1.1 Create `lib/elixir_ontologies/hex/extractor.ex` module
- [ ] Hex.3.2.1.2 Define `@moduledoc` describing tarball extraction
- [ ] Hex.3.2.1.3 Document Hex tarball structure (VERSION, CHECKSUM, metadata.config, contents.tar.gz)

### Hex.3.2.2 Implement Outer Tar Extraction

Extract the outer tar file containing Hex metadata and contents.

- [ ] Hex.3.2.2.1 Implement `extract_outer/2` accepting tarball_path and target_dir
- [ ] Hex.3.2.2.2 Use `:erl_tar.extract/2` with `[:compressed, {:cwd, target_dir}]`
- [ ] Hex.3.2.2.3 Handle `:erl_tar` error tuples
- [ ] Hex.3.2.2.4 Verify expected files exist (VERSION, contents.tar.gz)
- [ ] Hex.3.2.2.5 Return `{:ok, target_dir}` on success
- [ ] Hex.3.2.2.6 Return `{:error, :invalid_tarball}` if structure invalid
- [ ] Hex.3.2.2.7 Return `{:error, reason}` for extraction failures

### Hex.3.2.3 Implement Contents Extraction

Extract the inner contents.tar.gz containing source code.

- [ ] Hex.3.2.3.1 Implement `extract_contents/2` accepting outer_dir and target_dir
- [ ] Hex.3.2.3.2 Locate `contents.tar.gz` in outer_dir
- [ ] Hex.3.2.3.3 Read and decompress with `:zlib.gunzip/1`
- [ ] Hex.3.2.3.4 Extract decompressed tar with `:erl_tar.extract/2`
- [ ] Hex.3.2.3.5 Handle memory efficiently for large archives
- [ ] Hex.3.2.3.6 Verify `mix.exs` exists (valid Elixir project)
- [ ] Hex.3.2.3.7 Return `{:ok, target_dir}` on success
- [ ] Hex.3.2.3.8 Return `{:error, :no_mix_exs}` if not Elixir project
- [ ] Hex.3.2.3.9 Return `{:error, reason}` for failures

### Hex.3.2.4 Implement Full Extraction

Combine outer and inner extraction into single operation.

- [ ] Hex.3.2.4.1 Implement `extract/2` accepting tarball_path and target_dir
- [ ] Hex.3.2.4.2 Create temporary directory for outer extraction
- [ ] Hex.3.2.4.3 Call `extract_outer/2` to outer temp dir
- [ ] Hex.3.2.4.4 Call `extract_contents/2` to final target dir
- [ ] Hex.3.2.4.5 Clean up outer temp directory
- [ ] Hex.3.2.4.6 Return `{:ok, target_dir}` with source path
- [ ] Hex.3.2.4.7 Return `{:error, reason}` on failure
- [ ] Hex.3.2.4.8 Clean up partial extraction on failure

### Hex.3.2.5 Implement Metadata Extraction

Parse Hex package metadata from tarball.

- [ ] Hex.3.2.5.1 Implement `extract_metadata/1` accepting outer_dir
- [ ] Hex.3.2.5.2 Read `metadata.config` file
- [ ] Hex.3.2.5.3 Parse Erlang term format with `:file.consult/1`
- [ ] Hex.3.2.5.4 Convert to map with string keys
- [ ] Hex.3.2.5.5 Return `{:ok, metadata_map}`
- [ ] Hex.3.2.5.6 Return `{:error, reason}` if parsing fails

- [ ] **Task Hex.3.2 Complete**

## Hex.3.3 Cleanup Operations

Implement cleanup functions to remove temporary files and directories.

### Hex.3.3.1 Implement Directory Cleanup

Implement functions to clean up extracted directories.

- [ ] Hex.3.3.1.1 Implement `cleanup/1` accepting directory path
- [ ] Hex.3.3.1.2 Use `File.rm_rf!/1` to remove directory tree
- [ ] Hex.3.3.1.3 Return `:ok` on success
- [ ] Hex.3.3.1.4 Log cleanup in verbose mode
- [ ] Hex.3.3.1.5 Handle already-deleted directories gracefully

### Hex.3.3.2 Implement Tarball Cleanup

Implement functions to clean up downloaded tarballs.

- [ ] Hex.3.3.2.1 Implement `cleanup_tarball/1` accepting tarball path
- [ ] Hex.3.3.2.2 Use `File.rm/1` to remove file
- [ ] Hex.3.3.2.3 Return `:ok` on success
- [ ] Hex.3.3.2.4 Return `{:error, reason}` on failure
- [ ] Hex.3.3.2.5 Handle missing files gracefully

- [ ] **Task Hex.3.3 Complete**

## Hex.3.4 Package Handler Orchestration

Create the orchestration module that combines download, extract, and cleanup.

### Hex.3.4.1 Create Package Handler Module

Create `lib/elixir_ontologies/hex/package_handler.ex` for lifecycle management.

- [ ] Hex.3.4.1.1 Create `lib/elixir_ontologies/hex/package_handler.ex` module
- [ ] Hex.3.4.1.2 Define `@moduledoc` describing package lifecycle

### Hex.3.4.2 Define Context Struct

Define struct to track package processing state.

- [ ] Hex.3.4.2.1 Define `%Context{}` struct
- [ ] Hex.3.4.2.2 Add field `name` (string) - package name
- [ ] Hex.3.4.2.3 Add field `version` (string) - package version
- [ ] Hex.3.4.2.4 Add field `tarball_path` (string | nil) - downloaded tarball
- [ ] Hex.3.4.2.5 Add field `extract_dir` (string | nil) - extracted source
- [ ] Hex.3.4.2.6 Add field `temp_dir` (string | nil) - temp working directory
- [ ] Hex.3.4.2.7 Add field `status` (atom) - :pending, :downloaded, :extracted, :cleaned

### Hex.3.4.3 Implement Prepare Function

Implement function to download and extract package.

- [ ] Hex.3.4.3.1 Implement `prepare/4` accepting client, name, version, opts
- [ ] Hex.3.4.3.2 Create `%Context{}` with name and version
- [ ] Hex.3.4.3.3 Call `Downloader.download_to_temp/3`
- [ ] Hex.3.4.3.4 Update context with tarball_path and temp_dir
- [ ] Hex.3.4.3.5 Call `Extractor.extract/2`
- [ ] Hex.3.4.3.6 Update context with extract_dir and status
- [ ] Hex.3.4.3.7 Return `{:ok, %Context{}}`
- [ ] Hex.3.4.3.8 Return `{:error, reason, %Context{}}` on failure

### Hex.3.4.4 Implement Cleanup Function

Implement function to clean up all temporary files.

- [ ] Hex.3.4.4.1 Implement `cleanup/1` accepting `%Context{}`
- [ ] Hex.3.4.4.2 Remove tarball using `Extractor.cleanup_tarball/1`
- [ ] Hex.3.4.4.3 Remove extract directory using `Extractor.cleanup/1`
- [ ] Hex.3.4.4.4 Remove temp directory using `Extractor.cleanup/1`
- [ ] Hex.3.4.4.5 Update context status to `:cleaned`
- [ ] Hex.3.4.4.6 Return `{:ok, %Context{}}`

### Hex.3.4.5 Implement With-Package Callback

Implement callback pattern for safe resource management.

- [ ] Hex.3.4.5.1 Implement `with_package/5` accepting client, name, version, opts, callback
- [ ] Hex.3.4.5.2 Call `prepare/4` to download and extract
- [ ] Hex.3.4.5.3 If prepare succeeds, call callback with context
- [ ] Hex.3.4.5.4 Always call `cleanup/1` after callback (even on exception)
- [ ] Hex.3.4.5.5 Use `try/after` for guaranteed cleanup
- [ ] Hex.3.4.5.6 Return callback result on success
- [ ] Hex.3.4.5.7 Return `{:error, reason}` on prepare failure

- [ ] **Task Hex.3.4 Complete**

**Section Hex.3 Unit Tests:**

- [ ] Test tarball_url generation
- [ ] Test tarball_filename generation
- [ ] Test download to specific path
- [ ] Test download to temp directory
- [ ] Test download error handling (404, network)
- [ ] Test outer tar extraction
- [ ] Test outer tar with invalid structure
- [ ] Test contents.tar.gz extraction
- [ ] Test full extraction pipeline
- [ ] Test extraction of Erlang-only package (no mix.exs)
- [ ] Test metadata extraction from metadata.config
- [ ] Test cleanup removes directory
- [ ] Test cleanup handles missing directory
- [ ] Test tarball cleanup removes file
- [ ] Test Context struct creation
- [ ] Test prepare downloads and extracts
- [ ] Test prepare failure cleanup
- [ ] Test cleanup clears all temp files
- [ ] Test with_package callback pattern
- [ ] Test with_package cleanup on callback exception
- [ ] Test with_package cleanup on prepare failure
- [ ] Test large package handling
- [ ] Test special characters in package names
- [ ] Test concurrent package handling
- [ ] Test disk space handling

**Target: 30 unit tests**
