# Phase 22.4: Charlist Literal Extraction

**Status:** ✅ Complete
**Branch:** `feature/phase-22-4-charlist-literals`
**Created:** 2025-01-10
**Completed:** 2025-01-10
**Target:** Implement charlist literal extraction

## 1. Problem Statement

Section 22.4 of the expressions plan specifies implementation of charlist literal extraction. Charlists are single-quoted strings in Elixir (e.g., `'hello'`, `'\n'`, `'?`), which are lists of Unicode codepoints.

**Current State:**
- `CharlistLiteral` class exists in ontology
- No `charlistValue` property exists (needs to be added)
- ExpressionBuilder has no handler for charlists (lists of integers)
- Charlists appear as plain lists of integers in Elixir AST

**Elixir AST Behavior:**
- Literal charlists like `'hello'` become lists of integers in AST: `[104, 101, 108, 108, 111]`
- Modern Elixir uses `~c""` sigil syntax which becomes `{:sigil_c, ...}` in AST
- Empty charlist `''` becomes `[]` (empty list)

**Key Challenge:**
Charlists appear as **lists of integers** in the AST, which is the same structure as a regular list literal. The ExpressionBuilder needs to distinguish between:
1. Charlists (e.g., `'abc'` → `[97, 98, 99]`)
2. Regular lists (e.g., `[1, 2, 3]`)

**Solution Approach:**
A list is a charlist if ALL elements are integers AND they represent valid UTF-8 codepoints. We'll add a clause before the general list handler that checks for this pattern.

## 2. Solution Overview

The solution involves:

1. **Add `charlistValue` property** to ontology
2. **Add charlist handler** to ExpressionBuilder
3. **Add comprehensive tests** for charlist extraction

### Implementation Details

#### Ontology Addition

Add `charlistValue` property to `ontology/elixir-core.ttl` (after `stringValue`):

```turtle
:charlistValue a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "charlist value"@en ;
    rdfs:domain :CharlistLiteral ;
    rdfs:range xsd:string .
```

#### ExpressionBuilder Handler

Add a new clause in `build_expression_triples/3` (before any list literal handler, after string literals):

```elixir
# Charlist literals (lists of integers representing UTF-8 codepoints)
# Must come before generic list handler
def build_expression_triples(charlist, expr_iri, _context) when is_list(charlist) do
  if charlist?(charlist) do
    string_value = List.to_string(charlist)
    build_literal(string_value, expr_iri, Core.CharlistLiteral, Core.charlistValue(), RDF.XSD.String)
  else
    # Fall through to list handler
    build_list_literal(charlist, expr_iri, %{})
  end
end
```

With helper:

```elixir
# Check if a list represents a charlist (all elements are valid UTF-8 codepoints)
defp charlist?(list) when is_list(list) do
  Enum.all?(list, fn
    x when is_integer(x) -> x >= 0 and x <= 0x10FFFF
    _ -> false
  end)
end
```

**Note:** If no list literal handler exists yet, this will need to be added or the charlist handler should return generic expression for non-charlist lists.

## 3. Agent Consultations Performed

**Self-Analysis:**
- Verified Elixir AST representation of charlists using `quote do: 'hello'`
- Confirmed charlists appear as lists of integers: `[104, 101, 108, 108, 111]`
- Checked ontology for CharlistLiteral class (exists)
- Checked ontology for charlistValue property (does not exist)
- Verified ExpressionBuilder has no list or charlist handlers

## 4. Technical Details

### Elixir AST Charlist Representations

| Source Code | AST Representation | Notes |
|-------------|-------------------|-------|
| `'hello'` | `[104, 101, 108, 108, 111]` | List of character codes |
| `''` | `[]` | Empty list (empty charlist) |
| `'\n'` | `[10]` | Single newline character |
| `'?'` | `[63]` | Single question mark |
| `~c(hello)` | `{:sigil_c, ...}` | Sigil AST (not plain list) |

### Charlist Detection Logic

A list represents a charlist if:
1. All elements are integers
2. Each integer is a valid Unicode codepoint (0x0 to 0x10FFFF)

### Ontology Classes

Already defined in `ontology/elixir-core.ttl`:

```turtle
:CharlistLiteral a owl:Class ;
    rdfs:label "Charlist Literal"@en ;
    rdfs:comment "A list of Unicode codepoints, denoted with single quotes."@en ;
    rdfs:subClassOf :Literal .
```

## 5. Success Criteria

1. **Ontology updated:**
   - `charlistValue` property added with correct domain/range

2. **ExpressionBuilder handles charlists:**
   - Charlists are detected and converted to CharlistLiteral
   - Value is stored as string (converted from codepoints)
   - Non-charlist lists fall through to list handler or generic expression

3. **Comprehensive test coverage:**
   - Empty charlist
   - Single character charlist
   - Multi-character charlist
   - Charlist with escape sequences
   - Charlist with Unicode characters

4. **All tests pass**

## 6. Implementation Plan

### Step 1: Add Ontology Property
- [x] 1.1 Add `charlistValue` property to `ontology/elixir-core.ttl`
- [x] 1.2 Add `charlistValue` property to `priv/ontologies/elixir-core.ttl`

### Step 2: Implement Charlist Detection
- [x] 2.1 Add `charlist?/1` helper function to ExpressionBuilder
- [x] 2.2 Add charlist handler to `build_expression_triples/3`

### Step 3: Handle List/Charlist Distinction
- [x] 3.1 Check if list literal handler exists (not implemented, falls through to generic)
- [x] 3.2 Ensure proper ordering of clauses (charlist before general list)

### Step 4: Add Comprehensive Tests
- [x] 4.1 Test for empty charlist
- [x] 4.2 Test for single character charlist
- [x] 4.3 Test for multi-character charlist
- [x] 4.4 Test for charlist with escape sequences
- [x] 4.5 Test for charlist with Unicode characters
- [x] 4.6 Test that regular lists are not treated as charlists

### Step 5: Run Tests
- [x] 5.1 Run ExpressionBuilder tests (98 tests, 0 failures)
- [x] 5.2 Run full test suite (7130 tests, 0 failures)
- [x] 5.3 Verify no regressions

## 7. Notes/Considerations

### Empty Charlist Edge Case

An empty charlist `''` is represented as `[]` in the AST. An empty list `[]` is also `[]`. These are indistinguishable in the AST without source context. We'll treat `[]` as an empty charlist, which may not be ideal but is consistent with the list-of-codepoints model.

**Alternative:** If source preservation becomes important, we could add a `sourceCharlist` property or use the `:charlist` type annotation hint from the AST metadata.

### List vs Charlist Ambiguity

Lists like `[65, 66, 67]` could be either:
1. A charlist representing "ABC"
2. A list of integers

Since we can't distinguish without source context, we'll treat lists of valid codepoints as charlists. This is the more specific interpretation and aligns with Elixir's historical use of charlists.

### Future: Sigil Character Lists

The `~c()` sigil creates a different AST structure (`{:sigil_c, ...}`). This phase focuses on literal charlists. Sigil handling could be added in a future phase.

### RDF Literal Value

The charlist value is stored as an `xsd:string` (the string representation, not the list of codepoints). This is because:
1. RDF literals are typically strings
2. The semantic content is the string, not the codepoint list
3. List-to-string conversion is lossless for valid UTF-8

### Modern Elixir Deprecation Warning

Single-quoted strings are deprecated in modern Elixir. The compiler suggests using `~c""` instead. This is just a source syntax issue; the AST still uses lists of integers for literal charlists.

## 8. Progress Tracking

- [x] 8.1 Create feature branch
- [x] 8.2 Create planning document
- [x] 8.3 Add charlistValue property to ontology
- [x] 8.4 Implement charlist detection and handling
- [x] 8.5 Add comprehensive tests
- [x] 8.6 Run tests
- [x] 8.7 Write summary document
- [ ] 8.8 Ask for permission to commit and merge

## 9. Status Log

### 2025-01-10 - Initial Planning
- Created feature branch `feature/phase-22-4-charlist-literals`
- Analyzed Elixir AST representation of charlists
- Confirmed charlists appear as lists of integers in AST
- Confirmed CharlistLiteral class exists in ontology
- Identified that charlistValue property needs to be added
- Identified that ExpressionBuilder has no charlist handler
- Created planning document

### 2025-01-10 - Implementation Complete ✅
- **Ontology Updates:**
  - Added `charlistValue` property to both `ontology/elixir-core.ttl` and `priv/ontologies/elixir-core.ttl`
  - Property has correct domain (:CharlistLiteral) and range (xsd:string)

- **ExpressionBuilder Implementation:**
  - Added `charlist?/1` helper function to detect charlists (lists of valid Unicode codepoints)
  - Added charlist handler clause in `build_expression_triples/3`
  - Handler converts charlist to string using `List.to_string/1`
  - Non-charlist lists fall through to generic expression handler

- **Tests Added (7 new tests):**
  1. Empty charlist (`[]`)
  2. Single character charlist (`[63]` = "?")
  3. Multi-character charlist (`[104, 101, 108, 108, 111]` = "hello")
  4. Charlist with escape sequences (`[10]` = "\n")
  5. Charlist with Unicode characters (`[104, 233, 108, 108, 111]` = "héllo")
  6. Multi-byte Unicode charlist (`[20320, 22909]` = "你好")
  7. Non-charlist lists (mixed content falls through to generic expression)

- **Test Results:**
  - ExpressionBuilder tests: 98 tests (up from 91), 0 failures
  - Full test suite: 7130 tests (up from 7123), 0 failures, 361 excluded

- **Known Limitations:**
  - Empty list `[]` is treated as empty charlist (indistinguishable from empty list literal in AST)
  - Lists of integers that are valid codepoints are treated as charlists (e.g., `[65, 66, 67]` = "ABC")
  - Sigil charlists `~c(...)` have different AST structure and are not handled (deferred to future phase)
