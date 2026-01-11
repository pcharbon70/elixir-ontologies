# Phase 22.8: Map and Keyword List Literal Extraction - Summary

**Status:** ✅ Complete
**Branch:** `feature/phase-22-8-map-keyword-literals`
**Date:** 2025-01-10

## Overview

Section 22.8 of the expressions plan covers map literal, struct literal, and keyword list literal extraction. This phase implemented extraction for all three complex literal types with proper handling of their key-value pair structures.

## Key Findings

### Elixir AST Behavior for Maps, Structs, and Keyword Lists

| Source Code | AST Representation | Current Handling |
|-------------|-------------------|------------------|
| `%{}` | `{:%{}, [], []}` | ✅ MapLiteral |
| `%{a: 1, b: 2}` | `{:%{}, [], [a: 1, b: 2]}` | ✅ MapLiteral |
| `%{"a" => 1}` | `{:%{}, [], [{"a", 1}]}` | ✅ MapLiteral |
| `%{"a" => 1, b: 2}` | `{:%{}, [], [{"a", 1}, {:b, 2}]}` | ✅ MapLiteral |
| `%User{name: "John"}` | `{:%, [], [{:__aliases__, ..., [:User]}, {:%{}, ..., [...]}]}` | ✅ StructLiteral |
| `[a: 1, b: 2]` | `[a: 1, b: 2]` | ✅ KeywordListLiteral |
| `[1, 2, 3]` | `[1, 2, 3]` | ✅ ListLiteral (not keyword) |

### Key Design Decisions

**Map Entry Formats:**
Map entries in the AST come in two formats:
- Keyword tuples: `{:a, 1}` - when using `a: 1` syntax
- 2-tuples: `{"a", 1}` - when using `"a" => 1` syntax

Both represent the same concept (key-value pair) but have different AST representations.

**Struct vs Map:**
Structs are a special case of maps with:
- A special AST pattern: `{:%, meta, [module_ast, map_ast]}`
- A module reference extracted from `{:__aliases__, ..., parts}`
- Linked to their module via `refersToModule` property

**Keyword List Detection:**
Keyword lists are detected using `Keyword.keyword?/1` which checks if:
- The list is non-empty
- All elements are 2-tuples
- The first element of each tuple is an atom

**Handler Ordering:**
Critical to prevent pattern matching conflicts:
1. Struct handler - must come before map handler (both start with `:%`)
2. Map handler - after struct handler
3. Keyword list check - must come before cons pattern and regular list handling

## Changes Made

### Ontology Extension

**Files:** `ontology/elixir-core.ttl` and `priv/ontologies/elixir-core.ttl`

Added `StructLiteral` class:
```turtle
:StructLiteral a owl:Class ;
    rdfs:label "Struct Literal"@en ;
    rdfs:comment "A struct literal with a defined type and fields."@en ;
    rdfs:subClassOf :MapLiteral .
```

### ExpressionBuilder Implementation

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

1. **Added struct handler** (lines 378-382):
   - Matches `{:%, meta, [module_ast, map_ast]}` pattern
   - Must come before map handler to avoid conflicts

2. **Added map handler** (lines 384-388):
   - Matches `{:%{}, meta, pairs}` pattern
   - Handles all map types (empty, atom keys, string keys, mixed)

3. **Modified list handler** (lines 327-330):
   - Added keyword list check first: `Keyword.keyword?(list) and list != []`
   - Keyword lists checked before cons patterns and regular lists

4. **Added `build_struct_literal/4`** (lines 679-709):
   - Extracts module name from `{:__aliases__, ..., parts}`
   - Creates StructLiteral type triple
   - Creates refersToModule property linking to module IRI
   - Extracts struct fields using map entries logic

5. **Added `build_map_literal/3`** (lines 719-724):
   - Creates MapLiteral type triple
   - Builds map entries for key-value pairs

6. **Added `build_map_entries/3`** (lines 745-769):
   - Handles both keyword tuples and 2-tuples
   - Extracts values as child expressions

7. **Added `build_keyword_list/3`** (lines 665-681):
   - Creates KeywordListLiteral type triple
   - Extracts values as child expressions

### Test Changes

**File:** `test/elixir_ontologies/builders/expression_builder_test.exs`

1. **Added 4 map literal tests:**
   - Empty map
   - Map with atom keys
   - Map with string keys
   - Map with mixed keys

2. **Added 2 struct literal tests:**
   - Struct literal type
   - refersToModule property

3. **Added 3 keyword list tests:**
   - Keyword list type
   - Keyword list vs regular list distinction
   - Keyword list with duplicate keys

## Test Results

- **ExpressionBuilder tests:** 133 tests (up from 124), 0 failures
- **Full test suite:** 7165 tests (up from 7156), 0 failures, 361 excluded

## Notes

### Empty Keyword List Handling

`Keyword.keyword?([])` returns `true` in Elixir, but we exclude empty lists from keyword list handling with `and list != []` because:
- Empty list `[]` is already handled as a charlist (indistinguishable from empty charlist)
- Empty keyword list is rare in practice
- This preserves existing charlist behavior

### Map Entry Extraction

Map values are extracted as child expressions, but keys are not. Keys are always literal values (atoms or strings) in map literals, so they don't need expression extraction. Only the values need to be recursively processed.

### Struct Module IRI

The `refersToModule` property creates a module IRI in the format `{base_iri}module/{module_name}`. This IRI may or may not correspond to an actual module in the codebase - it's a reference that could be validated in a later phase.

## Files Modified

1. `ontology/elixir-core.ttl` - Added StructLiteral class
2. `priv/ontologies/elixir-core.ttl` - Added StructLiteral class (compiled)
3. `lib/elixir_ontologies/builders/expression_builder.ex` - Added handlers and helper functions
4. `test/elixir_ontologies/builders/expression_builder_test.exs` - Added 9 new tests
5. `notes/features/phase-22-8-map-keyword-literals.md` - Planning document
6. `notes/summaries/phase-22-8-map-keyword-literals.md` - This summary document

## Next Steps

Phase 22.8 is complete and ready to merge into the `expressions` branch. The map, struct, and keyword list literal extraction is functional with comprehensive test coverage.
