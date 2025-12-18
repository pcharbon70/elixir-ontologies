# Phase 2: AST Parsing Infrastructure

This phase builds the infrastructure for parsing Elixir source files into AST and extracting source location information. We'll create utilities for reading files, parsing code, and walking AST structures.

## 2.1 File Reading and Parsing

This section implements file reading with encoding handling and AST parsing using Elixir's built-in capabilities.

### 2.1.1 File Reader Module
- [x] **Task 2.1.1 Complete**

Create a file reader that handles encoding and provides source text alongside AST.

- [x] 2.1.1.1 Create `lib/elixir_ontologies/analyzer/file_reader.ex`
- [x] 2.1.1.2 Implement `FileReader.read/1` returning `{:ok, result}` or `{:error, reason}`
- [x] 2.1.1.3 Handle UTF-8 encoding with BOM detection
- [x] 2.1.1.4 Implement `FileReader.read!/1` raising on error
- [x] 2.1.1.5 Track file metadata (path, size, mtime)
- [x] 2.1.1.6 Write file reader tests (success: 31 tests - 22 unit + 9 doctests)

### 2.1.2 AST Parser Module
- [x] **Task 2.1.2 Complete**

Create an AST parser wrapping `Code.string_to_quoted` with enhanced error handling.

- [x] 2.1.2.1 Create `lib/elixir_ontologies/analyzer/parser.ex`
- [x] 2.1.2.2 Implement `Parser.parse/1` accepting source string
- [x] 2.1.2.3 Configure parser options: `columns: true`, `token_metadata: true`
- [x] 2.1.2.4 Implement `Parser.parse/2` with custom options
- [x] 2.1.2.5 Return structured error on parse failure with line/column
- [x] 2.1.2.6 Implement `Parser.parse_file/1` combining read + parse
- [x] 2.1.2.7 Write parser tests including error cases (success: 41 tests - 34 unit + 7 doctests)

**Section 2.1 Unit Tests:**
- [x] Test FileReader handles valid Elixir files
- [x] Test FileReader reports missing files
- [x] Test Parser extracts AST from simple module
- [x] Test Parser extracts AST from complex module
- [x] Test Parser returns line/column on syntax error
- [x] Test Parser options propagate correctly

## 2.2 AST Walking Infrastructure

This section implements the AST traversal system that visits all nodes in the tree, collecting information for RDF generation.

### 2.2.1 AST Walker Module
- [x] **Task 2.2.1 Complete**

Create a generic AST walker using Macro.traverse with accumulator pattern.

- [x] 2.2.1.1 Create `lib/elixir_ontologies/analyzer/ast_walker.ex`
- [x] 2.2.1.2 Implement `ASTWalker.walk/3` with AST, initial_acc, and visitor function
- [x] 2.2.1.3 Implement pre-order and post-order callbacks
- [x] 2.2.1.4 Support selective walking (skip subtrees)
- [x] 2.2.1.5 Track depth and parent chain during traversal
- [x] 2.2.1.6 Implement `ASTWalker.find_all/2` for pattern-based collection
- [x] 2.2.1.7 Write walker tests (success: 42 tests - 33 unit + 9 doctests)

### 2.2.2 Node Matchers
- [x] **Task 2.2.2 Complete**

Create pattern matchers for identifying specific AST node types.

- [x] 2.2.2.1 Create `lib/elixir_ontologies/analyzer/matchers.ex`
- [x] 2.2.2.2 Implement `Matchers.module?/1` detecting `defmodule`
- [x] 2.2.2.3 Implement `Matchers.function?/1` detecting `def/defp`
- [x] 2.2.2.4 Implement `Matchers.macro?/1` detecting `defmacro/defmacrop`
- [x] 2.2.2.5 Implement `Matchers.protocol?/1` detecting `defprotocol`
- [x] 2.2.2.6 Implement `Matchers.behaviour?/1` detecting `@behaviour`
- [x] 2.2.2.7 Implement `Matchers.struct?/1` detecting `defstruct`
- [x] 2.2.2.8 Implement `Matchers.type_spec?/1` detecting `@type/@spec/@callback`
- [x] 2.2.2.9 Implement `Matchers.use?/1`, `Matchers.import?/1`, `Matchers.alias?/1`
- [x] 2.2.2.10 Write matcher tests (success: 155 tests - 86 unit + 69 doctests)

**Section 2.2 Unit Tests:**
- [x] Test ASTWalker visits all nodes
- [x] Test ASTWalker accumulator updates correctly
- [x] Test ASTWalker depth tracking
- [x] Test each Matcher function with positive cases
- [x] Test each Matcher function with negative cases
- [x] Test Matchers handle edge cases (empty modules, etc.)

## 2.3 Source Location Tracking

This section implements extraction and tracking of source locations for all code elements, enabling the `hasSourceLocation` property.

### 2.3.1 Location Extractor
- [x] **Task 2.3.1 Complete**

Create utilities for extracting source locations from AST metadata.

- [x] 2.3.1.1 Create `lib/elixir_ontologies/analyzer/location.ex`
- [x] 2.3.1.2 Implement `Location.extract/1` getting line/column from AST node
- [x] 2.3.1.3 Implement `Location.extract_range/1` getting start and end positions
- [x] 2.3.1.4 Handle nodes without location metadata (return nil gracefully)
- [x] 2.3.1.5 Implement `Location.span/2` calculating extent from start/end nodes
- [x] 2.3.1.6 Create `%SourceLocation{}` struct with start_line, end_line, start_column, end_column
- [x] 2.3.1.7 Write location extraction tests (success: 64 tests - 17 doctests + 47 unit tests)

### 2.3.2 End Position Estimation
- [x] **Task 2.3.2 Complete**

Implement heuristics for estimating end positions when not available in metadata.

- [x] 2.3.2.1 Implement end line estimation from last child node
- [x] 2.3.2.2 Implement end line estimation from `end` keyword for blocks (already done in 2.3.1)
- [x] 2.3.2.3 Handle single-line constructs (end_line = start_line)
- [x] 2.3.2.4 Document estimation limitations
- [x] 2.3.2.5 Write estimation tests with various constructs (success: 30 new tests)

**Section 2.3 Unit Tests:**
- [x] Test location extraction from def node
- [x] Test location extraction from defmodule node
- [x] Test location extraction from literals
- [x] Test end position estimation for multi-line functions
- [x] Test single-line function locations
- [x] Test graceful handling of missing metadata

## Phase 2 Integration Tests

- [x] Test full file parsing pipeline: read → parse → walk → extract locations
- [x] Test walker finds all modules in multi-module file
- [x] Test walker finds all functions in complex module
- [x] Test location tracking through nested structures
- [x] Test error handling for malformed files

**Phase 2 Complete**: 28 integration tests covering all requirements.
