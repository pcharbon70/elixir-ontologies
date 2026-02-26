# Phase 22.8: Map and Keyword List Literal Extraction

**Status:** ✅ Complete
**Branch:** `feature/phase-22-8-map-keyword-literals`
**Created:** 2025-01-10
**Completed:** 2025-01-10
**Target:** Implement map, struct, and keyword list literal extraction

## 1. Problem Statement

Section 22.8 of the expressions plan specifies implementation of map literal, struct literal, and keyword list literal extraction. These are complex literal types with key-value pair structures.

**Current State:**
- `MapLiteral` class exists in ontology (line 157-160)
- `KeywordListLiteral` class exists in ontology (line 162-166)
- `StructLiteral` class does NOT exist - needs to be added
- `MapEntry` class does NOT exist
- `hasEntry` property does NOT exist
- `hasStructType` property does NOT exist
- `refersToModule` property exists (line 664-666)
- `hasChild` property exists for generic AST linking
- ExpressionBuilder has no map, struct, or keyword list handlers

**Elixir AST Behavior:**
- Empty map `%{}` is represented as: `{:%{}, [], []}`
- Map with atom keys `%{a: 1, b: 2}` is: `{:%{}, [], [a: 1, b: 2]}`
- Map with string keys `%{"a" => 1}` is: `{:%{}, [], [{"a", 1}]}`
- Struct literal `%User{name: "John"}` is: `{:%, [], [{:__aliases__, ..., [:User]}, {:%{}, ..., [name: "John"]}]}`
- Keyword list `[a: 1, b: 2]` is just a list: `[a: 1, b: 2]`

**Key Challenges:**

1. **Map entries come in two formats:**
   - Atom keys: `a: 1` (keyword tuple)
   - String/other keys: `{key, value}` (2-tuple)

2. **Struct literals use a special AST form** `{:%, ..., [module, map]}` that needs special handling

3. **Keyword lists are indistinguishable from regular lists** in the AST - both are lists. We need to detect keyword lists using `Keyword.keyword?/1`.

4. **Missing ontology classes:** `StructLiteral` needs to be added to the ontology.

## 2. Solution Overview

The solution involves:

1. **Add StructLiteral to ontology** - subclass of MapLiteral or standalone
2. **Add map handler** for `{:%{}, meta, pairs}` pattern
3. **Add struct handler** for `{:%, meta, [module, map]}` pattern
4. **Add keyword list detection** using `Keyword.keyword?/1` in the list handler
5. **Extract map entries** as child expressions
6. **Add comprehensive tests** for all three types

### Implementation Details

#### Map Handler Strategy

For maps, we need to:

1. **Match `{:%{}, meta, pairs}` pattern**
2. **Extract each key-value pair** - handle both `a: 1` and `{key, value}` formats
3. **Create MapLiteral type triple**
4. **Link entries via `hasChild` property** (since `hasEntry` doesn't exist)

#### Struct Handler Strategy

For structs, we need to:

1. **Match `{:%, meta, [module_ast, map_ast]}` pattern**
2. **Extract module name** from `{:__aliases__, ..., parts}`
3. **Create StructLiteral type triple** (needs to be added to ontology)
4. **Link struct type via `refersToModule` property**
5. **Extract struct fields** using the map handler logic

#### Keyword List Detection Strategy

For keyword lists, we need to:

1. **Detect using `Keyword.keyword?/1`** - checks if list is a keyword list
2. **Check BEFORE regular list handling** - keyword lists should be handled first
3. **Create KeywordListLiteral type triple**
4. **Extract key-value pairs** (always `{atom, value}` tuples)

### Ontology Extension

**Need to add `StructLiteral` class:**

```turtle
:StructLiteral a owl:Class ;
    rdfs:label "Struct Literal"@en ;
    rdfs:comment "A struct literal with a defined type and fields."@en ;
    rdfs:subClassOf :MapLiteral .
```

Or as a standalone class:

```turtle
:StructLiteral a owl:Class ;
    rdfs:label "Struct Literal"@en ;
    rdfs:comment "A struct literal with a defined type and fields."@en ;
    rdfs:subClassOf :Literal .
```

## 3. Agent Consultations Performed

**Self-Analysis:**
- Verified Elixir AST representation of maps, structs, and keyword lists
- Confirmed that maps use `{:%{}, meta, pairs}` pattern
- Confirmed that structs use `{:%, meta, [module, map]}` pattern
- Confirmed that keyword lists are just lists with specific format
- Checked ontology for MapLiteral (exists), KeywordListLiteral (exists)
- Checked ontology for StructLiteral (doesn't exist - needs to be added)
- Checked ontology for hasEntry (doesn't exist - will use hasChild)
- Checked ontology for refersToModule (exists)
- Verified `Keyword.keyword?/1` can detect keyword lists

## 4. Technical Details

### Elixir AST Map/Struct/Keyword List Representations

| Source Code | AST Representation | Notes |
|-------------|-------------------|-------|
| `%{}` | `{:%{}, [], []}` | Empty map |
| `%{a: 1, b: 2}` | `{:%{}, [], [a: 1, b: 2]}` | Atom keys (keyword list format) |
| `%{"a" => 1}` | `{:%{}, [], [{"a", 1}]}` | String keys (2-tuple format) |
| `%{"a" => 1, b: 2}` | `{:%{}, [], [{"a", 1}, {:b, 2}]}` | Mixed keys |
| `%User{name: "John"}` | `{:%, [], [{:__aliases__, ..., [:User]}, {:%{}, ..., [...]}]}` | Struct literal |
| `[a: 1, b: 2]` | `[a: 1, b: 2]` | Keyword list (same as list format) |
| `[1, 2, 3]` | `[1, 2, 3]` | Regular list |

### Map Entry Formats

Map entries in the AST come in two formats:

1. **Keyword tuples (for atom keys):** `{:a, 1}` - the atom `:a` is the key
2. **2-tuples (for other keys):** `{"a", 1}` - the string `"a"` is the key

When using the `key: value` syntax in Elixir, it compiles to `{key, value}` in the AST.

### Keyword List vs Regular List

In Elixir AST, both keyword lists and regular lists are represented as lists:
- `[a: 1, b: 2]` → `[{:a, 1}, {:b, 2}]`
- `[1, 2, 3]` → `[1, 2, 3]`

The distinction is:
- Keyword list: All elements are 2-tuples with atom first elements
- Regular list: Contains non-tuple elements or tuples with non-atom first elements

We can use `Keyword.keyword?/1` to detect keyword lists.

### Ontology Classes

Already defined in `ontology/elixir-core.ttl`:

```turtle
:MapLiteral a owl:Class ;
    rdfs:label "Map Literal"@en ;
    rdfs:comment "A map literal with key-value pairs."@en ;
    rdfs:subClassOf :Literal .

:KeywordListLiteral a owl:Class ;
    rdfs:label "Keyword List Literal"@en ;
    rdfs:comment """A list of {atom, value} tuples, commonly used for options.
    Example: [name: "John", age: 30]."""@en ;
    rdfs:subClassOf :ListLiteral .

:refersToModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "refers to module"@en ;
    rdfs:domain :ModuleReference .
```

**Need to add:**

```turtle
:StructLiteral a owl:Class ;
    rdfs:label "Struct Literal"@en ;
    rdfs:comment "A struct literal with a defined type and fields."@en ;
    rdfs:subClassOf :MapLiteral .
```

## 5. Success Criteria

1. **ExpressionBuilder handles map literals:**
   - Empty map `%{}` creates `MapLiteral`
   - Map with atom keys creates `MapLiteral`
   - Map with string keys creates `MapLiteral`
   - Map with mixed keys creates `MapLiteral`

2. **ExpressionBuilder handles struct literals:**
   - Struct literal creates `StructLiteral`
   - Struct name is extracted and linked via `refersToModule`
   - Struct fields are extracted correctly

3. **ExpressionBuilder handles keyword lists:**
   - Keyword list `[a: 1, b: 2]` creates `KeywordListLiteral`
   - Regular list `[1, 2, 3]` still creates `ListLiteral` or `CharlistLiteral`
   - Keyword list keys are preserved as atoms

4. **Elements are linked correctly:**
   - Map entries are extracted as child expressions
   - Keyword list entries are extracted as child expressions
   - Order is preserved through extraction sequence

5. **Comprehensive test coverage:**
   - Empty map
   - Map with atom keys
   - Map with string keys
   - Map with mixed keys
   - Struct literals
   - Keyword lists
   - Keyword lists with duplicate keys
   - Mixed lists (not keyword lists)

6. **All tests pass**

## 6. Implementation Plan

### Step 1: Update Ontology
- [x] 1.1 Add `StructLiteral` class to `ontology/elixir-core.ttl`
- [x] 1.2 Copy changes to `priv/ontologies/elixir-core.ttl`

### Step 2: Implement Map Literal Extraction
- [x] 2.1 Add handler for `{:%{}, meta, pairs}` pattern
- [x] 2.2 Add `build_map_literal/3` to extract maps as MapLiteral
- [x] 2.3 Handle both keyword tuple and 2-tuple entry formats

### Step 3: Implement Struct Literal Extraction
- [x] 3.1 Add handler for `{:%, meta, [module_ast, map_ast]}` pattern
- [x] 3.2 Add `build_struct_literal/3` to extract structs
- [x] 3.3 Extract module name from `{:__aliases__, ..., parts}`
- [x] 3.4 Link struct type via `refersToModule` property
- [x] 3.5 Extract struct fields using map handler logic

### Step 4: Implement Keyword List Extraction
- [x] 4.1 Modify list handler to check for keyword lists first
- [x] 4.2 Add `build_keyword_list/3` to extract keyword lists
- [x] 4.3 Use `Keyword.keyword?/1` for detection

### Step 5: Add Comprehensive Tests
- [x] 5.1 Test for empty map
- [x] 5.2 Test for map with atom keys
- [x] 5.3 Test for map with string keys
- [x] 5.4 Test for map with mixed keys
- [x] 5.5 Test for struct literal
- [x] 5.6 Test for keyword list
- [x] 5.7 Test for keyword list with duplicates
- [x] 5.8 Test that regular lists still work correctly

### Step 6: Run Tests
- [x] 6.1 Run ExpressionBuilder tests
- [x] 6.2 Run full test suite
- [x] 6.3 Verify no regressions

## 7. Notes/Considerations

### Map Entry Formats

Map entries in the AST can be either:
- Keyword tuples: `{:a, 1}` - when using `a: 1` syntax
- 2-tuples: `{"a", 1}` - when using `"a" => 1` syntax

Both represent the same concept (key-value pair) but have different formats. The extraction logic needs to handle both.

### Struct vs Map

Structs are a special case of maps with:
- A `__struct__` key pointing to the module name
- A defined set of keys (from the struct definition)
- Default values for some keys

For extraction purposes, structs are:
1. Detected by the `{:%, meta, [module, map]}` AST pattern
2. Represented as `StructLiteral` (subclass of `MapLiteral`)
3. Linked to their module via `refersToModule` property

### Keyword List Detection

`Keyword.keyword?/1` returns true if the list is a non-empty list of 2-tuples where the first element of each tuple is an atom. This is exactly what we need to detect keyword lists.

**Note:** `Keyword.keyword?([])` returns `true` for empty lists, so we need to handle empty lists carefully. An empty list `[]` could be:
- An empty keyword list
- An empty regular list
- An empty charlist

For this phase, we'll prioritize empty charlist detection, then keyword list detection.

### Handler Ordering

The handler ordering is critical:
1. **Struct handler** - must come before map handler (structs also start with `:%`)
2. **Map handler** - after struct handler
3. **List handler with keyword check** - before generic list handling
4. **Keyword list handler** - within the list handler

## 8. Progress Tracking

- [x] 8.1 Create feature branch
- [x] 8.2 Create planning document
- [x] 8.3 Update ontology with StructLiteral
- [x] 8.4 Implement map literal extraction
- [x] 8.5 Implement struct literal extraction
- [x] 8.6 Implement keyword list extraction
- [x] 8.7 Add comprehensive tests
- [x] 8.8 Run tests
- [x] 8.9 Write summary document
- [ ] 8.10 Ask for permission to commit and merge

## 9. Status Log

### 2025-01-10 - Initial Planning
- Created feature branch `feature/phase-22-8-map-keyword-literals`
- Analyzed Elixir AST representation of maps, structs, and keyword lists
- Confirmed map patterns: `{:%{}, [], pairs}`
- Confirmed struct pattern: `{:%, [], [module, map]}`
- Confirmed keyword lists are just lists with specific format
- Confirmed MapLiteral and KeywordListLiteral exist in ontology
- Identified that StructLiteral needs to be added to ontology
- Identified that hasEntry doesn't exist (will use hasChild)
- Confirmed refersToModule property exists
- Created planning document

### 2025-01-10 - Implementation Complete ✅
- **Ontology updated:**
  - Added `StructLiteral` class to both `ontology/elixir-core.ttl` and `priv/ontologies/elixir-core.ttl`
  - StructLiteral defined as subclass of MapLiteral

- **ExpressionBuilder Implementation:**
  - Added struct handler for `{:%, meta, [module_ast, map_ast]}` pattern
  - Added map handler for `{:%{}, meta, pairs}` pattern
  - Modified list handler to check for keyword lists first
  - Added `build_struct_literal/4` to extract structs with module reference
  - Added `build_map_literal/3` to extract maps
  - Added `build_map_entries/3` to handle both keyword tuples and 2-tuples
  - Added `build_keyword_list/3` to extract keyword lists

- **Test Implementation:**
  - Added 4 tests for map literals (empty, atom keys, string keys, mixed keys)
  - Added 2 tests for struct literals (type, refersToModule property)
  - Added 3 tests for keyword lists (type, distinction from regular list, duplicates)

- **Test Results:**
  - ExpressionBuilder tests: 133 tests (up from 124), 0 failures
  - Full test suite: 7165 tests (up from 7156), 0 failures, 361 excluded
