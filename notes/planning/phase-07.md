# Phase 7: Evolution & Git Integration (elixir-evolution.ttl)

This phase implements repository detection, commit information extraction, and source URL generation.

## 7.1 Repository Detection

This section detects git repositories and extracts metadata.

### 7.1.1 Git Repository Extractor
- [x] **Task 7.1.1 Complete**

Detect and extract git repository information.

- [x] 7.1.1.1 Create `lib/elixir_ontologies/analyzer/git.ex`
- [x] 7.1.1.2 Implement `Git.detect_repo/1` finding .git directory
- [x] 7.1.1.3 Implement `Git.remote_url/1` extracting origin URL
- [x] 7.1.1.4 Create `Repository` instance with `repositoryUrl`, `repositoryName`
- [x] 7.1.1.5 Handle various remote URL formats (https, ssh, git@)
- [x] 7.1.1.6 Implement `Git.current_branch/1` for `branchName`
- [x] 7.1.1.7 Implement `Git.default_branch/1` for `defaultBranch`
- [x] 7.1.1.8 Write repository detection tests (success: 40 tests)

### 7.1.2 Commit Information Extractor
- [x] **Task 7.1.2 Complete**

Extract current commit information.

- [x] 7.1.2.1 Implement `Git.current_commit/1` returning SHA
- [x] 7.1.2.2 Create `CommitRef` with `commitSha`
- [x] 7.1.2.3 Implement `Git.commit_tags/1` for `commitTag`
- [x] 7.1.2.4 Extract commit message if needed
- [x] 7.1.2.5 Link source files via `atCommit` (via `file_commit/2`)
- [x] 7.1.2.6 Write commit extraction tests (success: 17 new tests, 64 total)

**Section 7.1 Unit Tests:**
- [x] Test repository detection in git repo
- [x] Test repository detection returns error outside repo
- [x] Test remote URL parsing (https format)
- [x] Test remote URL parsing (ssh format)
- [x] Test current commit extraction
- [x] Test branch detection

## 7.2 Source URL Generation

This section generates source URLs for code elements (e.g., GitHub permalinks).

### 7.2.1 Source URL Builder
- [x] **Task 7.2.1 Complete**

Generate source URLs for various hosting platforms.

- [x] 7.2.1.1 Create `lib/elixir_ontologies/analyzer/source_url.ex`
- [x] 7.2.1.2 Implement `SourceUrl.for_file/5` (platform, owner, repo, commit, path)
- [x] 7.2.1.3 Implement `SourceUrl.for_line/6` (platform, owner, repo, commit, path, line)
- [x] 7.2.1.4 Implement `SourceUrl.for_range/7` (platform, owner, repo, commit, path, start, end)
- [x] 7.2.1.5 Support GitHub URL format: `https://github.com/org/repo/blob/sha/path#L10-L20`
- [x] 7.2.1.6 Support GitLab URL format: `https://gitlab.com/org/repo/-/blob/sha/path#L10-15`
- [x] 7.2.1.7 Support Bitbucket URL format: `https://bitbucket.org/org/repo/src/sha/path#lines-10:20`
- [x] 7.2.1.8 Auto-detect platform from remote URL
- [x] 7.2.1.9 Repository struct integration via `for_file/2`, `for_line/3`, `for_range/4`
- [x] 7.2.1.10 Write source URL tests (success: 53 tests - 20 doctests + 33 unit tests)

**Section 7.2 Unit Tests:**
- [x] Test GitHub URL generation
- [x] Test GitLab URL generation
- [x] Test URL with line range
- [x] Test platform auto-detection
- [x] Test URL generation without git info (returns nil)

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
