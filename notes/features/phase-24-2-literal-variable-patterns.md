# Phase 24.2: Literal and Variable Pattern Extraction

**Status:** Planning
**Branch:** `feature/phase-24-2-literal-variable-patterns`
**Created:** 2025-01-12
**Target:** Implement literal and variable pattern extraction for Phase 24.2

## 1. Problem Statement

Section 24.2 of Phase 24 implements the first two concrete pattern builders: `build_literal_pattern/3` and `build_variable_pattern/3`. These functions extract pattern matching constructs (as opposed to literal expressions) and create the appropriate RDF triples.

**Current State:**
- `detect_pattern_type/1` correctly identifies `:literal_pattern` and `:variable_pattern`
- `build_pattern/3` dispatches to placeholder functions
- `build_literal_pattern/3` returns only type triple: `[Core.LiteralPattern]`
- `build_variable_pattern/3` returns type triple and name: `[Core.VariablePattern, Core.name()]`

**What's Missing:**
1. Literal patterns should capture the literal value using appropriate value properties
2. Variable patterns should distinguish pattern context from expression context
3. No property linking to `Core.Variable` instances
4. No test coverage for literal pattern value extraction
5. No test coverage for variable pattern edge cases

## 2. Solution Overview

### 2.1 Literal Pattern Extraction

Literal patterns match against specific literal values. In Elixir, these appear in pattern contexts like function heads and case clauses.

| Pattern | AST | Ontology Type | Value Property |
|---------|-----|---------------|----------------|
| Integer | `42` | `Core.LiteralPattern` | `hasLiteralValue` |
| Float | `3.14` | `Core.LiteralPattern` | `hasLiteralValue` |
| String | `"hello"` | `Core.LiteralPattern` | `hasLiteralValue` |
| Atom | `:ok` | `Core.LiteralPattern` | `hasLiteralValue` |
| Boolean | `true`/`false` | `Core.LiteralPattern` | `hasLiteralValue` |
| Nil | `nil` | `Core.LiteralPattern` | `hasLiteralValue` |

**Design Decision:** Unlike Phase 22 which created specialized literal types (`IntegerLiteral`, `FloatLiteral`, etc.), pattern contexts use a single `LiteralPattern` class. The value is stored via a `hasLiteralValue` property, not the type-specific properties (`integerValue`, `floatValue`, etc.).

**Implementation Strategy:** Reuse the literal value extraction logic from Phase 22 (the `build_literal/4` pattern in `build_expression_triples/3`). Extract the value and datatype, but wrap them in `LiteralPattern` type instead of specific literal types.

### 2.2 Variable Pattern Extraction

Variable patterns bind matched values to variable names.

| Pattern | AST | Property |
|---------|-----|----------|
| Simple variable | `{:x, [], Elixir}` | `variableName: "x"` |
| Leading underscore | `{:_name, [], Elixir}` | `variableName: "_name"` |

**Exclusions (handled elsewhere):**
- Wildcard: `{:_}` - handled by `build_wildcard_pattern/3`
- Pin operator: `{:^, _, [{:x, _, _}]}` - handled by `build_pin_pattern/3`

**Design Decision:** Variable patterns use `Core.VariablePattern` type with a `variableName` property (currently mapped to `Core.name()`). A link to `Core.Variable` instance will be added in a future phase when scope analysis is implemented.

## 3. Implementation Plan

### Step 1: Implement `build_literal_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1242-1245):**
```elixir
defp build_literal_pattern(_ast, expr_iri, _context) do
  [Helpers.type_triple(expr_iri, Core.LiteralPattern)]
end
```

**New implementation:**
```elixir
defp build_literal_pattern(ast, expr_iri, _context) do
  {value_property, xsd_type} = literal_value_info(ast)

  [
    Helpers.type_triple(expr_iri, Core.LiteralPattern),
    Helpers.datatype_property(expr_iri, value_property, ast, xsd_type)
  ]
end

# Helper to determine value property and XSD type for literals
# Reuses logic from Phase 22 literal extraction
defp literal_value_info(int) when is_integer(int), do: {Core.integerValue(), RDF.XSD.Integer}
defp literal_value_info(float) when is_float(float), do: {Core.floatValue(), RDF.XSD.Double}
defp literal_value_info(str) when is_binary(str), do: {Core.stringValue(), RDF.XSD.String}
defp literal_value_info(atom) when is_atom(atom), do: {Core.atomValue(), RDF.XSD.String}
```

**Note:** For atoms including `true`, `false`, and `nil`, use `Core.atomValue()` - pattern context uses `LiteralPattern` not `BooleanLiteral`/`NilLiteral`.

### Step 2: Implement `build_variable_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1247-1254):**
```elixir
defp build_variable_pattern(ast, expr_iri, _context) do
  {name, _, _} = ast
  [
    Helpers.type_triple(expr_iri, Core.VariablePattern),
    Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)
  ]
end
```

**Status:** The current implementation is essentially complete. Only minor updates needed:

1. Update to use `variableName` property if ontology has it (check: currently uses `Core.name()`)
2. Add documentation clarifying pattern vs expression context
3. Consider adding a link to `Core.Variable` for future scope analysis

**Proposed enhancement:**
```elixir
defp build_variable_pattern({name, _meta, _ctx}, expr_iri, _context) do
  # Variable pattern captures the variable name
  # For scope analysis, this should eventually link to a Core.Variable instance
  [
    Helpers.type_triple(expr_iri, Core.VariablePattern),
    Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)
  ]
end
```

### Step 3: Add Unit Tests

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

Add tests in a new `describe "literal pattern extraction"` block:

```elixir
describe "literal pattern extraction" do
  test "builds LiteralPattern with integer value" do
    context = full_mode_context()
    ast = 42
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have LiteralPattern type
    assert has_type?(pattern_triples, Core.LiteralPattern)

    # Should have literal value property
    assert has_literal_value?(pattern_triples, expr_iri, Core.integerValue(), 42)
  end

  test "builds LiteralPattern with float value" do
    context = full_mode_context()
    ast = 3.14
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.floatValue(), 3.14)
  end

  test "builds LiteralPattern with string value" do
    context = full_mode_context()
    ast = "hello"
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.stringValue(), "hello")
  end

  test "builds LiteralPattern with atom value" do
    context = full_mode_context()
    ast = :ok
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.atomValue(), ":ok")
  end

  test "builds LiteralPattern with true boolean" do
    context = full_mode_context()
    ast = true
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Pattern context uses LiteralPattern, not BooleanLiteral
    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.atomValue(), "true")
  end

  test "builds LiteralPattern with false boolean" do
    context = full_mode_context()
    ast = false
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.atomValue(), "false")
  end

  test "builds LiteralPattern with nil" do
    context = full_mode_context()
    ast = nil
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.LiteralPattern)
    assert has_literal_value?(pattern_triples, expr_iri, Core.atomValue(), "nil")
  end
end
```

Add tests in a new `describe "variable pattern extraction"` block:

```elixir
describe "variable pattern extraction" do
  test "builds VariablePattern with variable name" do
    context = full_mode_context()
    ast = {:x, [], Elixir}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.VariablePattern)
    assert has_variable_name?(pattern_triples, expr_iri, "x")
  end

  test "builds VariablePattern for variables with leading underscore" do
    context = full_mode_context()
    ast = {:_name, [], Elixir}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.VariablePattern)
    assert has_variable_name?(pattern_triples, expr_iri, "_name")
  end

  test "distinguishes VariablePattern from Variable expression" do
    context = full_mode_context()
    ast = {:result, [], Elixir}
    {:ok, {expr_iri, expression_triples, _}} = ExpressionBuilder.build(ast, context, [])

    # Expression context creates Core.Variable
    assert has_type?(expression_triples, Core.Variable)

    # Pattern context creates Core.VariablePattern
    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)
    assert has_type?(pattern_triples, Core.VariablePattern)
  end
end
```

### Step 4: Add Test Helper Functions

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

Add helper functions after existing helpers:

```elixir
defp has_literal_value?(triples, subject_iri, predicate, expected_value) do
  Enum.any?(triples, fn {s, p, o} ->
    s == subject_iri and p == predicate and RDF.Literal.value(o) == expected_value
  end)
end

defp has_variable_name?(triples, subject_iri, expected_name) do
  Enum.any?(triples, fn {s, p, o} ->
    s == subject_iri and p == Core.name() and RDF.Literal.value(o) == expected_name
  end)
end
```

### Step 5: Run Verification

5.1 Run `mix test test/elixir_ontologies/builders/expression_builder_test.exs`

5.2 Verify new pattern extraction tests pass

5.3 Verify no regressions in existing tests

## 4. Technical Details

### File Locations

**Implementation:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
  - Replace `build_literal_pattern/3` at line 1242-1245
  - Update `build_variable_pattern/3` at line 1247-1254
  - Add `literal_value_info/1` helper function

**Tests:**
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add `describe "literal pattern extraction"` block after existing pattern tests
  - Add `describe "variable pattern extraction"` block
  - Add helper functions `has_literal_value?/4` and `has_variable_name?/3`

### Ontology Classes and Properties

**Existing Classes (in elixir-core.ttl):**
- `Core.LiteralPattern` (line 348-351) - A pattern matching against a specific literal value
- `Core.VariablePattern` (line 353-356) - A pattern that binds a matched value to a variable name
- `Core.Variable` (line 437-441) - A named reference to a value (expression context)

**Existing Properties:**
- `Core.atomValue()` - For atom literal values (line 802-805)
- `Core.integerValue()` - For integer literal values (line 807-810)
- `Core.floatValue()` - For float literal values (line 812-815)
- `Core.stringValue()` - For string literal values (line 817-820)
- `Core.name()` - For identifier names (line 796-799)
- `Core.bindsVariable()` - Links pattern to variable (line 616-619) - for future use

**Note:** The `hasLiteralValue` property mentioned in requirements does not currently exist in the ontology. The implementation will use the specific value properties (`integerValue`, `floatValue`, etc.) which is consistent with Phase 22 patterns.

### Pattern vs Expression Distinction

| Context | Integer AST | Type Created |
|---------|-------------|--------------|
| Expression (Phase 22) | `42` | `Core.IntegerLiteral` |
| Pattern (Phase 24.2) | `42` | `Core.LiteralPattern` |
| Expression | `{:x, [], Elixir}` | `Core.Variable` |
| Pattern | `{:x, [], Elixir}` | `Core.VariablePattern` |

The `build_pattern/3` function assumes the caller knows this is a pattern context. The `build/3` function (expression context) will continue to create expression types.

### Helper Functions

**Existing from `Helpers` module:**
- `type_triple/2` - For creating rdf:type triples
- `datatype_property/4` - For creating literal property triples

**Existing from `ExpressionBuilder`:**
- `atom_to_string/1` - For converting atoms to string representation (line 670-675)

## 5. Success Criteria

1. **Literal pattern extraction:**
   - Integer literals captured with `LiteralPattern` type and `integerValue` property
   - Float literals captured with `LiteralPattern` type and `floatValue` property
   - String literals captured with `LiteralPattern` type and `stringValue` property
   - Atom literals (including `true`, `false`, `nil`) captured with `LiteralPattern` type and `atomValue` property

2. **Variable pattern extraction:**
   - Variable name captured via `name` property
   - Variables with leading underscore (`_name`) handled correctly
   - Wildcard (`_`) and pin patterns (`^x`) excluded (handled by other builders)

3. **Pattern vs expression distinction:**
   - Same AST creates different types in pattern vs expression context
   - Tests verify the distinction is maintained

4. **Tests pass:**
   - All new literal pattern tests pass
   - All new variable pattern tests pass
   - No regressions in existing tests

5. **Code quality:**
   - Functions follow existing code style
   - Proper documentation added
   - DRY principle followed (reuse `atom_to_string/1` helper)

## 6. Notes and Considerations

### 6.1 Reusing Phase 22 Logic

The `literal_value_info/1` helper mirrors the type detection logic from Phase 22's `build_expression_triples/3` but returns `{property, xsd_type}` tuples instead of building triples directly. This promotes code reuse and ensures consistency.

### 6.2 Variable Scope Tracking

The current implementation does not create links between `VariablePattern` and `Core.Variable` instances. This is deferred to future scope analysis work. The `bindsVariable` property exists in the ontology for this purpose.

### 6.3 Atom String Representation

The `atom_to_string/1` helper (from Phase 22) handles special atoms:
- `true` → `"true"`
- `false` → `"false"`
- `nil` → `"nil"`
- `:foo` → `":foo"` (with colon prefix)

This ensures literal patterns capture the exact source representation.

### 6.4 Future Integration Points

These pattern builders will be used by:
- Function clause parameter extractors
- Case expression clause extractors
- Match expression handlers
- For comprehension generators

## 7. Progress Tracking

- [x] 7.1 Create feature branch `feature/phase-24-2-literal-variable-patterns`
- [x] 7.2 Create planning document
- [x] 7.3 Implement `build_literal_pattern/3` with value extraction
- [x] 7.4 Add `literal_value_info/1` helper function
- [x] 7.5 Review and enhance `build_variable_pattern/3`
- [x] 7.6 Add literal pattern extraction tests (7 tests)
- [x] 7.7 Add variable pattern extraction tests (3 tests)
- [x] 7.8 Add test helper functions
- [x] 7.9 Run verification
- [x] 7.10 Write summary document
- [ ] 7.11 Ask for permission to commit and merge

## 8. Status Log

### 2025-01-12 - Initial Planning
- Analyzed Phase 24.2 requirements
- Studied existing `build_literal_pattern/3` and `build_variable_pattern/3` placeholders
- Reviewed Phase 22 literal extraction patterns
- Examined ontology pattern class definitions
- Reviewed testing patterns from Phase 24.1
- Created planning document

### 2026-01-12 - Implementation Complete
- Implemented `build_literal_pattern/3` with full value extraction
- Added `literal_value_info/1` helper function returning {property, type, value}
- Enhanced `build_variable_pattern/3` documentation
- Added 10 new tests (7 literal, 3 variable)
- Total: 256 tests, 0 failures
- Summary document created at `notes/summaries/phase-24-2-literal-variable-patterns.md`

---

### Critical Files for Implementation

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` - Main implementation file; replace `build_literal_pattern/3` (lines 1242-1245), review `build_variable_pattern/3` (lines 1247-1254), add `literal_value_info/1` helper

- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs` - Test file; add `describe "literal pattern extraction"` and `describe "variable pattern extraction"` blocks after existing pattern dispatch tests (around line 2900)

- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` - Reference for pattern classes and value properties; `LiteralPattern` at lines 348-351, `VariablePattern` at lines 353-356, value properties at lines 796-820

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Helper functions for RDF triple creation; `type_triple/2` at lines 47-50, `datatype_property/4` at lines 90-106

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespace definitions; reference for accessing `Core.LiteralPattern`, `Core.VariablePattern`, and value properties via `Core` namespace
