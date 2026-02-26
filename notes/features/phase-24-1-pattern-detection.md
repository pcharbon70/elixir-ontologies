# Phase 24.1: Pattern Detection and Dispatch

**Status:** Planning
**Branch:** `feature/phase-24-1-pattern-detection`
**Created:** 2025-01-12
**Target:** Implement pattern type detection and dispatch system for Phase 24.1

## 1. Problem Statement

Section 24.1 of Phase 24 covers the foundational infrastructure for pattern extraction: pattern type detection and a dispatch mechanism that routes different AST patterns to their appropriate builder functions.

**Current State:**
- Pattern detection functions: Not implemented
- Pattern dispatch system: Not implemented
- Individual pattern builders (literal, variable, wildcard, etc.): To be implemented in later sections (24.2-24.6)

**Why This Matters:**
Elixir patterns appear in multiple contexts:
- Function head parameters
- Case expression clauses
- Match expressions
- For comprehension generators
- With clauses

Each context uses the same pattern syntax but with different AST wrapping. The detection/dispatch system provides a unified way to identify and build RDF triples for all pattern types.

## 2. Solution Overview

### 2.1 Pattern Type Detection

The `detect_pattern_type/1` function analyzes an Elixir AST node and returns an atom identifying the pattern type:

| AST Pattern | Return Value | Example AST |
|-------------|--------------|-------------|
| Literal value | `:literal_pattern` | `42`, `"hello"`, `:atom` |
| `{name, _, context}` (non-underscore) | `:variable_pattern` | `{:x, [], Elixir}` |
| `{:_}` | `:wildcard_pattern` | `{:_}` |
| `{:^, _, [{var, _, _}]}` | `:pin_pattern` | `{:^, [], [{:x, [], Elixir}]}` |
| `{:{}, _, elements}` | `:tuple_pattern` | `{{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}` |
| `[...]` | `:list_pattern` | `[{:a, [], Elixir}, {:b, [], Elixir}]` |
| `{:%{}, _, pairs}` | `:map_pattern` | `{:%{}, [], [{:a, [], Elixir}, 1]}` |
| `{:%, _, [module, map]}` | `:struct_pattern` | `{:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}` |
| `{:<<>>, _, segments}` | `:binary_pattern` | `{:<<>>, [], [{:x, [], Elixir}::8]}` |
| `{:=, _, [pattern, var]}` | `:as_pattern` | `{:=, [], [{:a, [], Elixir}, {:var, [], Elixir}]}` |

**Note:** The 2-tuple `{left, right}` is a special form that the Elixir compiler internally converts to `{:{}, _, [left, right]}` for patterns. Pattern detection should handle both.

### 2.2 Pattern Builder Dispatch

The `build_pattern/3` function uses the detected pattern type to dispatch to the appropriate builder function:

```elixir
def build_pattern(ast, expr_iri, context) do
  case detect_pattern_type(ast) do
    :literal_pattern -> build_literal_pattern(ast, expr_iri, context)
    :variable_pattern -> build_variable_pattern(ast, expr_iri, context)
    :wildcard_pattern -> build_wildcard_pattern(ast, expr_iri, context)
    :pin_pattern -> build_pin_pattern(ast, expr_iri, context)
    :tuple_pattern -> build_tuple_pattern(ast, expr_iri, context)
    :list_pattern -> build_list_pattern(ast, expr_iri, context)
    :map_pattern -> build_map_pattern(ast, expr_iri, context)
    :struct_pattern -> build_struct_pattern(ast, expr_iri, context)
    :binary_pattern -> build_binary_pattern(ast, expr_iri, context)
    :as_pattern -> build_as_pattern(ast, expr_iri, context)
    :unknown -> build_generic_expression(expr_iri)
  end
end
```

### 2.3 Distinguishing Patterns from Expressions

An important consideration: In Elixir, the same AST structure can represent both patterns and expressions depending on context. For example:
- `{:{}, [], [1, 2]}` as an expression is a tuple literal
- `{:{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}` as a pattern is a tuple pattern

**Design Decision:** For Phase 24.1, we are implementing detection functions that can identify pattern AST structures. The actual context (pattern vs expression) will be determined by the calling code (e.g., function parameter extractor, case clause extractor). The `build_pattern/3` function assumes the caller knows this is a pattern context.

## 3. Implementation Plan

### Step 1: Implement Pattern Type Detection

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

1.1 Add `detect_pattern_type/1` function after the existing IRI generation functions (around line 1090)

1.2 Implement detection for each pattern type in order of specificity:
   - Wildcard pattern: `{:_}` - check first as it's a special 2-tuple
   - Pin pattern: `{:^, _, [_]}`
   - As pattern: `{:=, _, [_, _]}`
   - Tuple pattern: `{:{}, _, _}` or 2-tuple `{left, right}`
   - Struct pattern: `{:%, _, [_, _]}`
   - Map pattern: `{:%{}, _, _}`
   - Binary pattern: `{:<<>>, _, _}`
   - List pattern: flat list, not containing `|` operator
   - Variable pattern: `{name, _, ctx}` where name is not `:_`
   - Literal pattern: integer, float, string, atom, or `nil`

1.3 Return `:unknown` for unrecognized patterns

### Step 2: Implement Pattern Builder Dispatch

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

2.1 Add `build_pattern/3` function after `detect_pattern_type/1`

2.2 Implement case statement dispatching to each builder function

2.3 For Phase 24.1, each individual builder function should return a minimal placeholder implementation:
   ```elixir
   defp build_literal_pattern(_ast, expr_iri, _context) do
     [Helpers.type_triple(expr_iri, Core.LiteralPattern)]
   end
   ```

**Note:** Full implementation of individual pattern builders is reserved for later sections:
- Section 24.2: Literal and Variable Patterns
- Section 24.3: Wildcard and Pin Patterns
- Section 24.4: Tuple and List Patterns
- Section 24.5: Map and Struct Patterns
- Section 24.6: Binary and As Patterns

### Step 3: Add Unit Tests

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

3.1 Add `describe "pattern type detection"` block

3.2 Test each pattern type detection:
   - Test literal patterns (integer, float, string, atom, boolean, nil)
   - Test variable patterns (simple variable, variables with underscores like `_name`)
   - Test wildcard pattern (`_`)
   - Test pin pattern (`^x`)
   - Test tuple patterns (empty, 2-tuple, n-tuple, nested)
   - Test list patterns (empty, flat, nested)
   - Test map patterns (empty, with entries)
   - Test struct patterns (simple struct, with fields)
   - Test binary patterns (empty, with segments)
   - Test as-pattern (pattern = var)

3.3 Test nested pattern detection:
   - Tuple within list: `[{1, 2}]`
   - List within tuple: `{[1, 2]}`
   - Map within list: `[%{a: 1}]`

3.4 Test edge cases:
   - Return `:unknown` for unhandled AST
   - Empty list `[]` as list pattern
   - Empty map `%{}`
   - Empty binary `<<>>`

3.5 Test pattern dispatch:
   - Dispatch to correct builder for each pattern type
   - Returns type triple for pattern class

### Step 4: Run Verification

4.1 Run `mix test test/elixir_ontologies/builders/expression_builder_test.exs`

4.2 Verify pattern detection tests pass

4.3 Verify no regressions in existing tests

## 4. Technical Details

### File Locations

**Implementation:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
  - Add `detect_pattern_type/1` around line 1090 (after capture operator helpers)
  - Add `build_pattern/3` after `detect_pattern_type/1`
  - Add placeholder builder functions at end of file

**Tests:**
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add new `describe "pattern type detection"` block after "capture operator" tests
  - Add test helper functions if needed

### Ontology Classes

All pattern classes are already defined in `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`:

```turtle
:Pattern a owl:Class ;
    rdfs:subClassOf :ASTNode .

:LiteralPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:VariablePattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:WildcardPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:PinPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:TuplePattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:ListPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:MapPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:StructPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:BinaryPattern a owl:Class ;
    rdfs:subClassOf :Pattern .

:AsPattern a owl:Class ;
    rdfs:subClassOf :Pattern .
```

### Helper Functions

Existing helper functions from `ExpressionBuilder`:
- `fresh_iri/2` - For generating child expression IRIs
- `build_expression_triples/3` - For recursive pattern building

Existing helpers from `Helpers` module:
- `type_triple/2` - For creating rdf:type triples
- `datatype_property/4` - For creating literal property triples
- `object_property/3` - For creating object property triples

### Elixir AST Pattern Reference

| Pattern Type | AST Form | Example |
|--------------|----------|---------|
| Literal | `42`, `"hello"`, `:atom` | `42` |
| Variable | `{name, meta, ctx}` | `{:x, [], Elixir}` |
| Wildcard | `{:_}` or `{:_, [], ctx}` | `{:_}` |
| Pin | `{:^, meta, [{var, meta, ctx}]}` | `{:^, [], [{:x, [], Elixir}]}` |
| Tuple | `{:{}, meta, elements}` or `{left, right}` | `{{}, [], [1, 2]}` or `{1, 2}` |
| List | `[elements]` | `[1, 2, 3]` |
| Map | `{:%{}, meta, pairs}` | `{:%{}, [], [{:a, [], nil}, 1]}` |
| Struct | `{:%, meta, [module_ast, map_ast]}` | `{:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}` |
| Binary | `{:<<>>, meta, segments}` | `{:<<>>, [], [{:x, [], Elixir}::8]}` |
| As | `{:=, meta, [pattern_ast, var_ast]}` | `{:=, [], [{:a, [], Elixir}, {:var, [], Elixir}]}` |

## 5. Success Criteria

1. **Pattern detection works:**
   - `detect_pattern_type/1` correctly identifies all 10 pattern types
   - Returns `:unknown` for unrecognized patterns

2. **Pattern dispatch works:**
   - `build_pattern/3` routes to correct builder based on pattern type
   - Returns appropriate RDF type triple for each pattern

3. **Tests pass:**
   - All pattern detection tests pass
   - All pattern dispatch tests pass
   - No regressions in existing ExpressionBuilder tests

4. **Code quality:**
   - Functions follow existing code style
   - Proper documentation added
   - Code is maintainable for future pattern builder implementations

## 6. Notes and Considerations

### 6.1 Expression vs Pattern Context

The same AST can represent either an expression or a pattern depending on context:
- `{:{}, [], [1, 2]}` - Tuple literal expression vs tuple pattern
- `{:{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}` - Always a tuple pattern (contains variables)
- `[1, 2, 3]` - List literal expression vs list pattern
- `[{:x, [], Elixir}, {:y, [], Elixir}]` - Always a list pattern (contains variables)

**Design Decision:** The detection functions identify patterns by their AST structure. Context determination is left to the caller (e.g., function parameter extractor knows it's building patterns).

### 6.2 2-Tuple Special Case

The 2-tuple `{left, right}` is represented directly in the AST (not as a 3-tuple). In Elixir:
- `quote do {1, 2} end` returns `{1, 2}` (2 elements)
- `quote do {1, 2, 3} end` returns `{{}, [], [1, 2, 3]}` (3-tuple)

For pattern detection, we should recognize both:
- 2-tuple: `{left, right}` where left and right may be patterns
- n-tuple: `{:{}, _, elements}` for n >= 0

### 6.3 Variable Name Validation

Variable patterns must exclude:
- Wildcard: `_` or `{:_}`
- Pinned variables: `{:^, _, [{var, _, _}]}`
- Leading underscore variables: `_name` - In Elixir, `_name` is still a variable pattern (not a wildcard), but it generates a compiler warning. For pattern detection purposes, treat `_name` as a variable pattern.

### 6.4 Future Integration Points

The pattern detection/dispatch system will be used by:
- Function clause parameter extraction (Phase 24.7+)
- Case expression clause extraction
- Match expression handling
- For comprehension generator extraction

## 7. Progress Tracking

- [x] 7.1 Create feature branch `feature/phase-24-1-pattern-detection`
- [x] 7.2 Create planning document
- [x] 7.3 Implement `detect_pattern_type/1` function
- [x] 7.4 Implement `build_pattern/3` function
- [x] 7.5 Add placeholder builder functions
- [x] 7.6 Add comprehensive unit tests
- [x] 7.7 Run verification
- [x] 7.8 Write summary document
- [ ] 7.9 Ask for permission to commit and merge

## 8. Status Log

### 2025-01-12 - Initial Planning
- Analyzed Phase 24.1 requirements
- Studied existing ExpressionBuilder patterns (operator detection/dispatch)
- Examined ontology pattern class definitions
- Reviewed testing patterns from existing test suite
- Created planning document

### 2026-01-12 - Implementation Complete
- Implemented `detect_pattern_type/1` with support for all 10 pattern types
- Implemented `build_pattern/3` dispatch function
- Added 11 placeholder builder functions
- Added 36+ comprehensive unit tests (all passing)
- Total: 246 tests, 0 failures
- Summary document created at `notes/summaries/phase-24-1-pattern-detection.md`

---

### Critical Files for Implementation

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` - Main implementation file; add `detect_pattern_type/1` and `build_pattern/3` functions after line 1090 (after capture operator helpers)

- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs` - Test file; add pattern detection describe block after capture operator tests (around line 1050)

- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` - Reference for pattern class definitions (lines 342-400); all pattern classes are already defined

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Helper functions for creating RDF triples; use `type_triple/2`, `datatype_property/4`, `object_property/3`

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespace definitions; reference for `Core.LiteralPattern`, `Core.VariablePattern`, etc.
