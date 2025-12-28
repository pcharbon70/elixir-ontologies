# Hex Batch Analyzer Security Review

**Date:** 2025-12-28
**Scope:** `/lib/elixir_ontologies/hex/` (Phases Hex.1-8)
**Reviewer:** Security audit of Hex.pm batch package analyzer implementation

---

## Executive Summary

The Hex batch analyzer implementation demonstrates generally sound security practices for a package analysis tool. The codebase uses modern Elixir patterns with proper error handling and resource management. However, several security concerns were identified, ranging from critical path traversal vulnerabilities in tar extraction to medium-severity input validation gaps and low-priority best practice improvements.

**Finding Counts:**
- Critical: 1
- Medium: 5
- Low: 5

---

## 1. HTTP Client Security (http_client.ex)

### 1.1 TLS/SSL Configuration

**Status:** Generally secure, with considerations

The implementation relies on Req with `castore` for certificate validation:

```elixir
# mix.exs
{:req, "~> 0.5"},
{:castore, "~> 1.0"},
```

Req automatically uses the system's CA store via `castore`, which provides proper certificate validation by default.

**Findings:**

- **No explicit TLS version enforcement** - The code does not explicitly require TLS 1.2+
- **No certificate pinning** - For Hex.pm specifically, certificate pinning could be considered

### 1.2 Header Injection Risks

**Status:** Low risk

```elixir
# http_client.ex:56-58
Req.new(
  headers: [{"user-agent", @user_agent}],
  ...
)
```

The User-Agent is constructed at compile time from trusted sources (Mix.Project.config and System.version), eliminating runtime header injection risks.

### 1.3 Timeout Handling

**Status:** Properly implemented

```elixir
# http_client.ex:22-23
@default_timeout 30_000
@default_retries 3
```

Timeouts are properly configured with sensible defaults (30 seconds receive timeout, 3 retries with exponential backoff).

---

## 2. Input Validation

### 2.1 Package Name Validation

#### Path Traversal in URL Construction

**Finding:** Low (URL context)

```elixir
# api.ex:198
url = "#{@hex_api_url}/packages/#{URI.encode(name)}"

# downloader.ex:33-34
encoded_name = URI.encode(name)
"#{@repo_url}#{@tarball_path}/#{encoded_name}-#{version}.tar"
```

Package names are URI-encoded before URL construction, which mitigates URL-based injection. However, `URI.encode/1` does not encode all potentially problematic characters.

#### Path Sanitization in Output

**Finding:** Medium

```elixir
# output_manager.ex:53-58
def sanitize_name(name) when is_binary(name) do
  name
  |> String.replace(~r/[\/\\:*?"<>|]/, "_")
  |> String.replace(~r/\.\./, "_")
  |> String.trim("_")
end
```

The sanitization replaces forward slashes and double-dots, which helps prevent path traversal in output filenames. However:

1. The regex `~r/\.\./` only catches literal `..` but not encoded variants
2. No validation that the final path stays within the intended directory
3. Unicode normalization attacks are not addressed (e.g., using unicode characters that normalize to `/`)

### 2.2 Version String Validation

**Finding:** Medium

```elixir
# downloader.ex:34
"#{@repo_url}#{@tarball_path}/#{encoded_name}-#{version}.tar"
```

The version string is **not** URI-encoded or validated before URL construction. A malicious version string could potentially:
- Include path traversal sequences (`../`)
- Include query string injection (`?foo=bar`)
- Include URL fragment injection (`#fragment`)

**Note:** In practice, versions come from Hex.pm API responses which should be trusted, but defense-in-depth is recommended.

### 2.3 API Response JSON Parsing

**Status:** Safe

The codebase uses Jason for JSON parsing, which is memory-safe and does not execute code. Response parsing in `Api.Package.from_json/1` handles missing fields gracefully with defaults.

---

## 3. File System Operations

### 3.1 Tar Extraction Path Traversal

**Finding:** CRITICAL

```elixir
# extractor.ex:37
case :erl_tar.extract(to_charlist(tarball_path), [{:cwd, to_charlist(target_dir)}]) do

# extractor.ex:87
case :erl_tar.extract({:binary, decompressed}, [{:cwd, to_charlist(target_dir)}]) do
```

The `:erl_tar.extract/2` function is vulnerable to path traversal attacks. A malicious tarball could contain entries like `../../../etc/passwd` that would extract files outside the intended directory.

**Mitigation options:**
1. Use `:erl_tar` with the `:keep_old_files` or custom extraction with path validation
2. Use the `:safe_relative_path` option (OTP 25+)
3. Manually iterate entries and validate paths before extraction
4. Use a sandbox directory and verify no escapes after extraction

**Risk Context:** While Hex.pm packages are signed and verified by the Hex client, this implementation downloads directly without signature verification. A compromised CDN or MITM attack could serve malicious tarballs.

### 3.2 Symlink Following

**Finding:** Medium

The `:erl_tar.extract/2` function extracts symlinks as-is by default. A malicious tarball could:
1. Create a symlink pointing outside the extraction directory
2. Subsequent file operations could follow the symlink and affect external files

The code does use `Path.wildcard/1` for source file discovery:

```elixir
# filter.ex:137-139
path
|> Path.join("**/*.ex")
|> Path.wildcard()
```

`Path.wildcard/1` does follow symlinks, which could lead to:
- Reading files outside the intended directory
- Denial of service via symlink loops
- Information disclosure

### 3.3 Temp File Cleanup

**Status:** Generally good

```elixir
# package_handler.ex:170-176
try do
  callback.(context)
after
  cleanup(context)
end
```

The `with_package/5` function properly uses try/after to ensure cleanup even on exceptions. However:

```elixir
# downloader.ex:126
File.rm_rf(temp_dir)
```

This cleanup is in an `else` branch that might not execute if later operations fail.

### 3.4 File Permissions

**Finding:** Low

Extracted files inherit permissions from the tarball and umask. The code does not explicitly set restrictive permissions on:
- Temporary directories
- Extracted source files
- Output TTL files

This could be an issue in multi-user environments.

---

## 4. Secrets and Credentials

### 4.1 Hardcoded Secrets

**Status:** None found

No API keys, passwords, or other secrets are hardcoded in the codebase.

### 4.2 API Key Handling

**Status:** Not applicable

The implementation accesses only public Hex.pm API endpoints that don't require authentication.

---

## 5. Resource Exhaustion

### 5.1 Memory Limits on Large Packages

**Finding:** Medium

```elixir
# http_client.ex:156-158
case Req.get(client, [url: url, decode_body: false] ++ opts) do
  {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
    case File.write(file_path, body) do
```

The entire tarball is downloaded into memory before writing to disk. Large packages (some Hex packages exceed 100MB) could cause memory exhaustion.

```elixir
# extractor.ex:84
decompressed = :zlib.gunzip(compressed_data)
```

Similarly, the compressed contents are fully loaded into memory before decompression. A malicious package with high compression ratio (zip bomb pattern) could exhaust memory.

**Recommendations:**
1. Use streaming download with `into: File.stream!/1`
2. Set maximum file size limits
3. Use streaming decompression if possible

### 5.2 Disk Space Protection

**Status:** Partially implemented

```elixir
# output_manager.ex:23-24
@min_disk_space_mb 500
@min_disk_space_bytes @min_disk_space_mb * 1024 * 1024
```

The code checks disk space and warns when below 500MB, but:
1. This only warns, does not stop processing
2. No check before individual package extraction
3. No maximum extraction size limit

### 5.3 Rate Limiting

**Status:** Well implemented

```elixir
# rate_limiter.ex
```

The token bucket rate limiter with adaptive delays based on API headers is well-designed. The implementation:
- Respects `X-RateLimit-*` headers
- Uses exponential backoff
- Has configurable burst and rate parameters

---

## 6. Dependency Security

### 6.1 Req Library Usage

**Status:** Secure usage

The Req library is used appropriately with:
- Proper timeout configuration
- Retry logic for transient errors
- Binary mode for downloads (no auto-decoding issues)

### 6.2 Jason JSON Parsing

**Status:** Secure

Jason is memory-safe and doesn't have known vulnerabilities for parsing untrusted input.

### 6.3 Missing: Checksum Verification

**Finding:** Medium

```elixir
# extractor.ex:7-8 (comment only)
#    - CHECKSUM - Package checksum
```

While the code documents that Hex packages contain a CHECKSUM file, it does not verify the checksum after download. This means:
1. Corrupted downloads would not be detected
2. MITM attacks substituting the tarball would not be detected

---

## 7. Additional Findings

### 7.1 Atom Table Exhaustion

**Finding:** Medium

```elixir
# progress_store.ex:114
defp string_to_atom(str) when is_binary(str), do: String.to_atom(str)
```

This converts arbitrary strings from JSON to atoms. While the input is from the progress file (trusted), if the progress file is corrupted or manipulated, this could lead to atom table exhaustion since atoms are never garbage collected.

**Recommendation:** Use `String.to_existing_atom/1` with a fallback, or use string keys instead.

### 7.2 Erlang Term File Parsing

**Finding:** Low

```elixir
# extractor.ex:144
case :file.consult(to_charlist(metadata_path)) do
```

`:file.consult/1` parses Erlang terms from a file. While this is less dangerous than `:erlang.binary_to_term/1`, malformed terms could cause parsing errors or unexpected behavior. The metadata comes from within the (potentially malicious) tarball.

### 7.3 System Command Injection

**Finding:** Low

```elixir
# output_manager.ex:157
case System.cmd("df", ["-B1", "--output=avail", output_dir], stderr_to_stdout: true) do
```

The `output_dir` is passed as a command argument. While `System.cmd/3` properly escapes arguments (unlike shell execution), the code doesn't validate that `output_dir` is a reasonable path. An extremely long path could cause issues.

---

## Findings Summary

### Critical

| ID | Finding | File | Line | Recommendation |
|----|---------|------|------|----------------|
| C1 | Path traversal in tar extraction | extractor.ex | 37, 87 | Validate extracted paths stay within target directory |

### Medium

| ID | Finding | File | Line | Recommendation |
|----|---------|------|------|----------------|
| M1 | Version string not validated | downloader.ex | 34 | URI-encode or validate version strings |
| M2 | Symlinks not handled in extraction | extractor.ex | 37 | Use `:keep_old_files` or validate symlink targets |
| M3 | Full file loaded to memory | http_client.ex | 156 | Use streaming download for large files |
| M4 | No package checksum verification | extractor.ex | - | Verify CHECKSUM after download |
| M5 | Unbounded atom creation | progress_store.ex | 114 | Use String.to_existing_atom or string keys |

### Low

| ID | Finding | File | Line | Recommendation |
|----|---------|------|------|----------------|
| L1 | Output path sanitization incomplete | output_manager.ex | 53 | Add path canonicalization check |
| L2 | No explicit TLS version requirement | http_client.ex | - | Configure minimum TLS 1.2 |
| L3 | Extracted file permissions not set | extractor.ex | - | Set explicit permissions on temp dirs |
| L4 | Disk space check is advisory only | output_manager.ex | 184 | Stop processing when disk is critically low |
| L5 | Erlang term parsing from untrusted source | extractor.ex | 144 | Wrap in try/rescue with specific error handling |

---

## Recommended Actions

### Immediate (Critical)

1. **Add tar extraction path validation:**

```elixir
def safe_extract(tarball_path, target_dir) do
  target_dir = Path.expand(target_dir)

  # First, list contents to validate
  {:ok, files} = :erl_tar.table(to_charlist(tarball_path), [:verbose])

  Enum.each(files, fn {name, _type, _size, _mtime, _mode, _uid, _gid} ->
    full_path = Path.expand(Path.join(target_dir, to_string(name)))
    unless String.starts_with?(full_path, target_dir <> "/") do
      raise "Path traversal attempt: #{name}"
    end
  end)

  # Safe to extract
  :erl_tar.extract(to_charlist(tarball_path), [{:cwd, to_charlist(target_dir)}])
end
```

### Short-term (Medium)

2. Add streaming downloads for large tarballs
3. Implement checksum verification
4. Replace `String.to_atom/1` with safe alternatives
5. Add symlink validation post-extraction
6. Validate version strings before URL construction

### Long-term (Low)

7. Consider implementing Hex package signature verification
8. Add file size limits for extraction
9. Implement sandbox extraction (extract to temp, verify, move)
10. Add comprehensive path canonicalization

---

## Security Testing Recommendations

1. **Fuzzing:** Test with malformed tarballs, JSON responses, and package names
2. **Path traversal testing:** Create test tarballs with `../` entries
3. **Resource exhaustion:** Test with very large packages and zip bombs
4. **Symlink attacks:** Create test tarballs with symlinks outside directory
5. **Rate limit bypass:** Verify rate limiting cannot be circumvented

---

## Conclusion

The Hex batch analyzer has a solid foundation but requires attention to the critical path traversal vulnerability in tar extraction. The implementation follows good Elixir practices for error handling and resource cleanup. After addressing the critical and medium findings, the codebase would be suitable for processing untrusted package sources with appropriate caution.
