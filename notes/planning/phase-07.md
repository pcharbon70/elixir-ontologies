# Phase 7: Evolution & Git Integration (elixir-evolution.ttl)

This phase implements repository detection, commit information extraction, and source URL generation.

## 7.1 Repository Detection

This section detects git repositories and extracts metadata.

### 7.1.1 Git Repository Extractor
- [ ] **Task 7.1.1 Complete**

Detect and extract git repository information.

- [ ] 7.1.1.1 Create `lib/elixir_ontologies/analyzer/git.ex`
- [ ] 7.1.1.2 Implement `Git.detect_repo/1` finding .git directory
- [ ] 7.1.1.3 Implement `Git.remote_url/1` extracting origin URL
- [ ] 7.1.1.4 Create `Repository` instance with `repositoryUrl`, `repositoryName`
- [ ] 7.1.1.5 Handle various remote URL formats (https, ssh, git@)
- [ ] 7.1.1.6 Implement `Git.current_branch/1` for `branchName`
- [ ] 7.1.1.7 Implement `Git.default_branch/1` for `defaultBranch`
- [ ] 7.1.1.8 Write repository detection tests (success: 10 tests)

### 7.1.2 Commit Information Extractor
- [ ] **Task 7.1.2 Complete**

Extract current commit information.

- [ ] 7.1.2.1 Implement `Git.current_commit/1` returning SHA
- [ ] 7.1.2.2 Create `CommitRef` with `commitSha`
- [ ] 7.1.2.3 Implement `Git.commit_tags/1` for `commitTag`
- [ ] 7.1.2.4 Extract commit message if needed
- [ ] 7.1.2.5 Link source files via `atCommit`
- [ ] 7.1.2.6 Write commit extraction tests (success: 8 tests)

**Section 7.1 Unit Tests:**
- [ ] Test repository detection in git repo
- [ ] Test repository detection returns nil outside repo
- [ ] Test remote URL parsing (https format)
- [ ] Test remote URL parsing (ssh format)
- [ ] Test current commit extraction
- [ ] Test branch detection

## 7.2 Source URL Generation

This section generates source URLs for code elements (e.g., GitHub permalinks).

### 7.2.1 Source URL Builder
- [ ] **Task 7.2.1 Complete**

Generate source URLs for various hosting platforms.

- [ ] 7.2.1.1 Create `lib/elixir_ontologies/analyzer/source_url.ex`
- [ ] 7.2.1.2 Implement `SourceUrl.for_file/3` (repo, file, commit)
- [ ] 7.2.1.3 Implement `SourceUrl.for_line/4` (repo, file, line, commit)
- [ ] 7.2.1.4 Implement `SourceUrl.for_range/5` (repo, file, start, end, commit)
- [ ] 7.2.1.5 Support GitHub URL format: `https://github.com/org/repo/blob/sha/path#L10-L20`
- [ ] 7.2.1.6 Support GitLab URL format
- [ ] 7.2.1.7 Support Bitbucket URL format
- [ ] 7.2.1.8 Auto-detect platform from remote URL
- [ ] 7.2.1.9 Set `sourceUrl` property on code elements
- [ ] 7.2.1.10 Write source URL tests (success: 12 tests)

**Section 7.2 Unit Tests:**
- [ ] Test GitHub URL generation
- [ ] Test GitLab URL generation
- [ ] Test URL with line range
- [ ] Test platform auto-detection
- [ ] Test URL generation without git info (returns nil)

## 7.3 File Path Handling

This section manages absolute and relative file paths.

### 7.3.1 Path Utilities
- [ ] **Task 7.3.1 Complete**

Implement path utilities for source file management.

- [ ] 7.3.1.1 Create utilities in `Git` or separate module
- [ ] 7.3.1.2 Implement `relative_to_repo/2` converting absolute to relative path
- [ ] 7.3.1.3 Set `filePath` (absolute) and `relativeFilePath` (relative to repo root)
- [ ] 7.3.1.4 Link files via `inRepository`
- [ ] 7.3.1.5 Write path utility tests (success: 6 tests)

**Section 7.3 Unit Tests:**
- [ ] Test relative path calculation
- [ ] Test handling of paths outside repo
- [ ] Test Windows/Unix path normalization

## Phase 7 Integration Tests

- [ ] Test full git info extraction in actual repo
- [ ] Test source URLs generated for functions
- [ ] Test repository linking for all source files
- [ ] Test graceful degradation without git
