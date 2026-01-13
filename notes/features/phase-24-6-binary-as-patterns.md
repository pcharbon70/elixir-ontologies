# Phase 24.6: Binary and As Pattern Extraction

**Status:** Implementation
**Branch:** `feature/phase-24-6-binary-as-patterns`
**Created:** 2026-01-13
**Target:** Implement binary pattern and as-pattern extraction for Phase 24.6

## 1. Problem Statement

Section 24.6 of Phase 24 implements the final two pattern builders: `build_binary_pattern/3` for binary/bitstring patterns and `build_as_pattern/3` for pattern aliasing. These functions complete the pattern extraction system.

### Current State

- `detect_pattern_type/1` correctly identifies `:binary_pattern` and `:as_pattern`
- `build_pattern/3` dispatches to placeholder functions
- `build_binary_pattern/3` returns only type triple: `[Core.BinaryPattern]`
- `build_as_pattern/3` returns only type triple: `[Core.AsPattern]`

### What's Missing

**Binary Patterns:**
1. No extraction of binary segment structure
2. No handling of size/type specifiers (`::8`, `::binary`, `::unit(8)`)
3. No recursive pattern building for segment variables
4. No representation of segment modifiers

**As Patterns:**
1. No extraction of the inner pattern
2. No extraction of the binding variable
3. No linking via `hasPattern` and `bindsVariable` properties

## 2. Elixir AST Research

### 2.1 Binary Pattern AST Structure

| Pattern | AST Structure |
|---------|---------------|
| `<<>>` | `{:<<>>, [], []}` |
| `<<x>>` | `{:<<>>, [], [{:x, [], Elixir}]}` |
| `<<x::8>>` | `{:<<>>, [], [{:"::", [], [{:x, [], Elixir}, 8]}]` |
| `<<x::binary>>` | `{:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:binary, [], Elixir}]}]` |
| `<<x::size(8)>>` | `{:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:size, [], [8]}]}]` |
| `<<x::unit(8)>>` | `{:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:unit, [], [8]}]}]` |
| `<<x::_*8>>` | `{:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:*, [], [_, 8]}]}]` |
| `<<head::8, rest::binary>>` | `{:<<>>, [], [seg1, seg2]}` where each seg has `::` form |

### 2.2 As Pattern AST Structure

| Pattern | AST Structure |
|---------|---------------|
| `pattern = var` | `{:=, meta, [pattern, var]}` |
| `{:ok, x} = result` | `{:=, [], [{{:ok, [], Elixir}, {:x, [], Elixir}}, {:result, [], Elixir}]}` |

## 3. Solution Overview

### 3.1 Binary Pattern Extraction

Binary patterns match binary data with optional size, type, and unit specifiers.

1. Create `Core.BinaryPattern` type triple
2. Extract each segment as a child pattern
3. For segments with specifiers (`::`), extract:
   - The pattern (variable or literal)
   - Size specifier (integer or expression)
   - Type specifier (`:integer`, `:float`, `:binary`, `:bits`, etc.)
   - Unit specifier (for variable-sized segments)

### 3.2 As Pattern Extraction

As patterns bind the entire matched value while also destructuring it:

1. Create `Core.AsPattern` type triple
2. Recursively extract the left (pattern) side
3. Extract the right (variable) side
4. Link via `hasPattern` to the inner pattern
5. Link via `bindsVariable` to the variable

## 4. Implementation Plan

### Step 1: Implement Binary Pattern Extraction

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

Replace `build_binary_pattern/3` placeholder with full implementation.

**Key Functions:**
- `build_binary_pattern/3` - Main entry point
- `build_binary_segments/4` - Process all segments
- `build_binary_segment/3` - Build individual segment
- `extract_binary_specifier/2` - Extract size/type/unit from specifier

### Step 2: Implement As Pattern Extraction

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

Replace `build_as_pattern/3` placeholder with full implementation.

**Key Functions:**
- `build_as_pattern/3` - Main entry point
- Extract left pattern via `build/3` + `build_pattern/3`
- Extract right variable via `build/3` + `build_pattern/3`
- Create `hasPattern` and `bindsVariable` property triples

### Step 3: Add Unit Tests

**File:** `test/elixir_ontologies/builders/expression_builder_test.exs`

Add tests in two new blocks:
- `describe "binary pattern extraction"` - ~6 tests
- `describe "as pattern extraction"` - ~4 tests

## 5. Technical Details

### File Locations

**Implementation:**
- `lib/elixir_ontologies/builders/expression_builder.ex`
  - Replace `build_binary_pattern/3` (around line 1665)
  - Replace `build_as_pattern/3` (around line 1670)
  - Add helper functions

**Tests:**
- `test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add after struct pattern tests

### Ontology Classes and Properties

**Existing Classes:**
- `Core.BinaryPattern` (line 390-394) - Pattern for matching binary/bitstring data
- `Core.AsPattern` (line 396-400) - Pattern that binds entire matched value

**Existing Properties:**
- `Core.hasPattern()` (line 608-610) - Links to pattern structure
- `Core.bindsVariable()` (line 616-619) - Links pattern to variable

**Properties to Add (if not present):**
- `Core.segmentSize()` - For size specifier (e.g., `8` in `<<x::8>>`)
- `Core.segmentType()` - For type specifier (e.g., `:binary`, `:integer`)
- `Core.segmentUnit()` - For unit specifier (e.g., `8` in `<<x::_*8>>`)

### Binary Segment Types

| Type | Description | Example |
|------|-------------|---------|
| `:integer` | Integer segment | `<<n::integer>>` |
| `:float` | Float segment | `<<f::float>>` |
| `:binary` | Binary segment | `<<b::binary>>` |
| `:bits` | Bitstring segment | `<<b::bits>>` |
| `:utf8` | UTF-8 codepoint | `<<c::utf8>>` |
| `:utf16` | UTF-16 codepoint | `<<c::utf16>>` |
| `:utf32` | UTF-32 codepoint | `<<c::utf32>>` |

## 6. Success Criteria

1. **Binary pattern extraction:**
   - Empty binary `<<>>` creates `BinaryPattern`
   - Simple segments extract variable patterns
   - Sized segments capture size information
   - Typed segments capture type information
   - Multi-segment binaries create nested patterns

2. **As pattern extraction:**
   - Creates `AsPattern` type
   - Extracts left (destructure) pattern recursively
   - Extracts right (binding) variable
   - Links via `hasPattern` property
   - Links via `bindsVariable` property

3. **Tests pass:**
   - All new binary pattern tests pass
   - All new as pattern tests pass
   - No regressions in existing tests

## 7. Notes and Considerations

### 7.1 Ontology Extensions

The ontology may need additional properties for binary segment specifiers. These will be added as needed during implementation.

### 7.2 Complex Specifier Handling

Complex specifiers like `<<x::binary-size(4)-native>>` have nested AST structures. The initial implementation will capture these as string representations for simplicity.

### 7.3 Variable Scope Tracking

Similar to other pattern builders, `build_as_pattern/3` does not create actual `Core.Variable` instances. This is deferred to future scope analysis work.

## 8. Implementation Tasks

- [x] Implement `build_binary_pattern/3` function
- [x] Add `extract_binary_segment_patterns/1` helper
- [x] Implement `build_as_pattern/3` function
- [x] Add binary pattern extraction tests (6 tests)
- [x] Add as pattern extraction tests (4 tests)
- [x] Run verification tests
- [x] Write summary document

## Implementation Notes

### Simplified Approach

The implementation took a simplified approach compared to the original plan:

1. **Binary Patterns**: Instead of parsing specifier details (size, type, unit), the implementation focuses on extracting the patterns within segments. The `extract_binary_segment_patterns/1` helper returns the pattern portion of each segment, which are then built as child patterns.

2. **As Patterns**: The implementation builds both the left (destructure) and right (binding) patterns, and creates the `hasPattern` link. The `bindsVariable` property was not implemented as it would require creating actual `Core.Variable` instances.

### Future Enhancements

- Add binary specifier properties (`segmentSize`, `segmentType`, `segmentUnit`) to ontology
- Parse specifier AST to extract size, type, and unit information
- Implement `bindsVariable` property for as patterns when scope analysis is available
