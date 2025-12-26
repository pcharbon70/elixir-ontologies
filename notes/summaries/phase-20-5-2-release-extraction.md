# Phase 20.5.2 Release Extraction Summary

## Overview

Implemented release extraction for Phase 20.5.2. Releases track formal version points from git tags and mix.exs versions, with full semantic versioning support.

## Implementation

### New Files

1. **`lib/elixir_ontologies/extractors/evolution/release.ex`** (~570 lines)
   - `Release` struct with fields: release_id, version, tag, commit_sha, short_sha, timestamp, semver, previous_version, project_name, metadata
   - `parse_semver/1` - Parse semantic version strings following semver.org specification
   - `compare_versions/2` - Compare two version strings with proper semver ordering
   - `list_tags/1` - List all git tags in repository
   - `list_version_tags/1` - List only version-like tags (v1.2.3, 1.2.3, etc.)
   - `extract_tag_info/2` - Get commit SHA and timestamp for a tag
   - `extract_version_at_commit/2` - Read version from mix.exs at specific commit
   - `extract_current_version/1` - Get current version from mix.exs
   - `extract_releases/1` - Extract all releases from repository tags
   - `extract_release/2` - Extract single release by tag name
   - `release_progression/1` - Get ordered list of releases (oldest first)
   - `sort_releases/1` - Sort releases by version (newest first)

2. **`test/elixir_ontologies/extractors/evolution/release_test.exs`** (~280 lines)
   - 41 tests covering all public functions
   - Semantic version parsing tests (simple, pre-release, build metadata)
   - Version comparison tests
   - Tag listing and extraction tests
   - Release progression ordering tests
   - Integration tests

### Semantic Version Support

Full support for Semantic Versioning 2.0.0 specification:
- Basic versions: `1.2.3`
- With v prefix: `v1.2.3`
- Pre-release: `1.0.0-alpha.1`, `2.0.0-rc.2`, `1.0.0-beta`
- Build metadata: `1.0.0+build.123`
- Combined: `1.0.0-alpha.1+build.456`

### Key Design Decisions

1. **Semver Regex**: Uses a regex based on the official semver.org specification to properly parse all valid semantic version formats, including pre-release and build metadata.

2. **Version Comparison**: Pre-release versions have lower precedence than normal versions (1.0.0-alpha < 1.0.0). Build metadata is ignored in comparison per the spec.

3. **Tag Filtering**: Supports common tag naming patterns:
   - `v1.2.3` (with v prefix)
   - `1.2.3` (bare version)
   - `release-1.0.0` or `release_1.0.0` (release prefixed)

4. **Previous Version Tracking**: Releases automatically track their previous version for progression analysis.

5. **mix.exs Parsing**: Uses AST parsing to safely extract version from mix.exs without code execution. Handles both literal `version: "x.x.x"` and `@version` module attribute patterns.

## Test Results

```
41 tests, 0 failures
```

All tests pass including:
- Semver parsing for various formats
- Version comparison ordering
- Tag listing and filtering
- Version extraction from mix.exs
- Release extraction and progression
- Error handling for invalid inputs

## Credo Results

```
No issues found
```

## Files Modified

- `notes/planning/extractors/phase-20.md` (marked task 20.5.2 complete)
- `notes/features/phase-20-5-2-release-extraction.md` (implementation plan)

## Next Steps

The next logical task is **20.5.3 Snapshot and Release Builder** which will:
- Implement `build_snapshot/3` generating snapshot IRI
- Generate `rdf:type evolution:CodebaseSnapshot` triple
- Implement `build_release/3` generating release IRI
- Generate `rdf:type evolution:Release` triple
- Generate `evolution:hasSemanticVersion` with version info
