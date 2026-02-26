# Phase 24.3: Wildcard and Pin Pattern Extraction

**Status:** Planning
**Branch:** `feature/phase-24-3-wildcard-pin-patterns`
**Created:** 2026-01-12
**Target:** Implement wildcard and pin pattern extraction for Phase 24.3

## 1. Problem Statement

Section 24.3 of Phase 24 implements two additional pattern builders: `build_wildcard_pattern/3` and `build_pin_pattern/3`. These handle the underscore wildcard pattern and the pin operator pattern for pattern matching contexts.

**Current State:**
- `detect_pattern_type/1` correctly identifies `:wildcard_pattern` ({:_}) and `:pin_pattern` ({:^, _, [{var, _, _}]})
- `build_pattern/3` dispatches to placeholder functions
- `build_wildcard_pattern/3` returns only type triple: `[Core.WildcardPattern]`
- `build_pin_pattern/3` returns type triple and variable name via `Core.name()`

**What's Missing:**
1. Wildcard pattern should optionally store the original variable name for patterns like `_foo`
2. Pin pattern needs to properly link to the variable being pinned via `pinsVariable` property
3. No test coverage for wildcard pattern edge cases
4. No test coverage for pin pattern variable linking
5. No test coverage for nested patterns with wildcards and pins

## 2. Solution Overview

### 2.1 Wildcard Pattern Extraction

Wildcard patterns match any value and discard it. In Elixir:
- `_` - the anonymous wildcard, matches anything and discards
- `_var` - a named wildcard (still discards but hints at purpose)

| Pattern | AST | Ontology Type | Properties |
|---------|-----|---------------|------------|
| Anonymous wildcard | `{:_}` | `Core.WildcardPattern` | None (minimal) |
| Named wildcard | `{:_name, [], ctx}` | `Core.WildcardPattern` | Optional: `name` property for documentation |

**Design Decision:** The primary wildcard `{:_}` is minimal - only a type triple. Named wildcards like `_foo` may optionally store the name for documentation purposes, but semantically they remain wildcards (not variable bindings).

**Implementation Strategy:**
1. Match the `{:_}` pattern directly for the anonymous wildcard
2. For named wildcards `{:_name, _, _}`, store the name optionally
3. Document that wildcards do not bind values (unlike `VariablePattern`)

### 2.2 Pin Pattern Extraction

Pin patterns match against existing variable values rather than rebinding.

| Pattern | AST | Ontology Type | Properties |
|---------|-----|---------------|------------|
| Pin variable | `{:^, _, [{:x, _, _}]}` | `Core.PinPattern` | `name: "x"`, optionally `pinsVariable` link |

**Current Implementation Analysis:**
The existing `build_pin_pattern/3` (lines 1292-1299) already extracts the variable name and creates:
1. Type triple: `Core.PinPattern`
2. Name triple: `Core.name()` with variable name as string

**What Needs Enhancement:**
The ontology defines a `pinsVariable` object property (line 621-624) that links a `PinPattern` to a `Core.Variable` instance. For full completeness, the pin pattern should create this link. However, since scope analysis is not yet implemented, the current name-based approach is acceptable for now.

## 3. Implementation Plan

### Step 1: Review and Verify `build_wildcard_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1287-1290):**
```elixir
defp build_wildcard_pattern(_ast, expr_iri, _context) do
  [Helpers.type_triple(expr_iri, Core.WildcardPattern)]
end
```

**Status:** The current implementation is essentially complete for the anonymous wildcard `{:_}`. The function:
1. Creates the `Core.WildcardPattern` type triple
2. Does not store additional properties (correct for `_`)
3. Ignores the AST parameter (since `{:_}` has no additional data)

**Enhancement for named wildcards (optional but recommended):**

```elixir
defp build_wildcard_pattern(ast, expr_iri, _context) do
  # Wildcard pattern matches anything and discards the value
  # The AST is either {:_} for anonymous wildcard or {:_name, _, ctx} for named
  type_triple = Helpers.type_triple(expr_iri, Core.WildcardPattern)

  case ast do
    # Anonymous wildcard - no additional properties
    {:_} ->
      [type_triple]

    # Named wildcard - optionally store name for documentation
    # Semantically still a wildcard (does not bind)
    {name, _meta, _ctx} when is_atom(name) ->
      [type_triple, Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)]
  end
end
```

**Note:** Named wildcards like `_foo` have AST representation `{:_foo, [], Elixir}` which would match the variable pattern handler in `detect_pattern_type/1`. The current detector correctly identifies `{:_}` as `:wildcard_pattern` but `_foo` would be detected as `:variable_pattern` since it doesn't match `{:_}`. This is semantically correct as `_foo` is still a variable (just with a leading underscore for compiler warning suppression).

**Decision:** Keep the current simple implementation. Named wildcards are handled as `VariablePattern` which is correct Elixir semantics.

### Step 2: Review and Document `build_pin_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1292-1299):**
```elixir
defp build_pin_pattern(ast, expr_iri, _context) do
  {:^, _, [{var, _, _}]} = ast
  [
    Helpers.type_triple(expr_iri, Core.PinPattern),
    Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(var), RDF.XSD.String)
  ]
end
```

**Status:** The current implementation is functionally complete. It:
1. Correctly extracts the pinned variable name from the AST
2. Creates the `Core.PinPattern` type triple
3. Stores the variable name via `Core.name()` property

**Documentation Enhancement:**

Add module documentation explaining:
- Pin operator semantics (matches against existing variable value)
- The `name` property stores which variable is pinned
- Future enhancement: link to `Core.Variable` via `pinsVariable` property when scope analysis is implemented

```elixir
@doc """
Builds RDF triples for a pin pattern.

Pin patterns (^var) match against a variable's existing value rather than
rebinding it. The pin operator forces pattern matching to use the current
value of a variable rather than treating it as a new pattern binding.

## Parameters

- `ast` - The pin pattern AST: {:^, _, [{var_name, _, ctx}]}
- `expr_iri` - The IRI for this pattern expression
- `context` - The builder context

## Returns

A list of RDF triples with:
- Core.PinPattern type triple
- Core.name property with the pinned variable name

## Examples

  iex> ast = {:^, [], [{:x, [], Elixir}]}
  iex> build_pin_pattern(ast, expr_iri, context)
  [
    {expr_iri, RDF.type(), Core.PinPattern},
    {expr_iri, Core.name(), "x"}
  ]

## Notes

The current implementation stores only the variable name. A future version
with scope analysis could create a Core.Variable instance and link it via
the pinsVariable object property defined in the ontology.
"""
defp build_pin_pattern(ast, expr_iri, _context) do
  {:^, _, [{var, _, _}]} = ast
  [
    Helpers.type_triple(expr_iri, Core.PinPattern),
    Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(var), RDF.XSD.String)
  ]
end
```

### Step 3: Add Unit Tests

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

Add tests in a new `describe "wildcard pattern extraction"` block:

```elixir
describe "wildcard pattern extraction" do
  test "builds WildcardPattern for anonymous wildcard" do
    context = full_mode_context()
    ast = {:_}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have WildcardPattern type
    assert has_type?(pattern_triples, Core.WildcardPattern)

    # Should have only the type triple (minimal representation)
    assert length(pattern_triples) == 1
  end

  test "distinguishes wildcard from variable pattern" do
    context = full_mode_context()

    # Wildcard creates WildcardPattern
    wildcard_ast = {:_}
    {:ok, {wildcard_iri, _, _}} = ExpressionBuilder.build(wildcard_ast, context, [])
    wildcard_triples = ExpressionBuilder.build_pattern(wildcard_ast, wildcard_iri, context)

    assert has_type?(wildcard_triples, Core.WildcardPattern)
    refute has_type?(wildcard_triples, Core.VariablePattern)

    # Variable creates VariablePattern
    var_ast = {:x, [], Elixir}
    {:ok, {var_iri, _, _}} = ExpressionBuilder.build(var_ast, context, [])
    var_triples = ExpressionBuilder.build_pattern(var_ast, var_iri, context)

    assert has_type?(var_triples, Core.VariablePattern)
    refute has_type?(var_triples, Core.WildcardPattern)
  end
end
```

Add tests in a new `describe "pin pattern extraction"` block:

```elixir
describe "pin pattern extraction" do
  test "builds PinPattern with variable name" do
    context = full_mode_context()
    ast = {:^, [], [{:x, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have PinPattern type
    assert has_type?(pattern_triples, Core.PinPattern)

    # Should have variable name property
    assert has_variable_name?(pattern_triples, expr_iri, "x")
  end

  test "captures pinned variable name correctly" do
    context = full_mode_context()
    ast = {:^, [], [{:result, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    assert has_type?(pattern_triples, Core.PinPattern)
    assert has_variable_name?(pattern_triples, expr_iri, "result")
  end

  test "distinguishes pin pattern from variable pattern" do
    context = full_mode_context()

    # Pin pattern creates PinPattern
    pin_ast = {:^, [], [{:x, [], Elixir}]}
    {:ok, {pin_iri, _, _}} = ExpressionBuilder.build(pin_ast, context, [])
    pin_triples = ExpressionBuilder.build_pattern(pin_ast, pin_iri, context)

    assert has_type?(pin_triples, Core.PinPattern)
    refute has_type?(pin_triples, Core.VariablePattern)

    # Variable creates VariablePattern
    var_ast = {:x, [], Elixir}
    {:ok, {var_iri, _, _}} = ExpressionBuilder.build(var_ast, context, [])
    var_triples = ExpressionBuilder.build_pattern(var_ast, var_iri, context)

    assert has_type?(var_triples, Core.VariablePattern)
    refute has_type?(var_triples, Core.PinPattern)
  end
end
```

Add tests for nested patterns:

```elixir
describe "nested pattern extraction with wildcards and pins" do
  test "handles wildcard in tuple pattern" do
    context = full_mode_context()
    # Tuple pattern with wildcard: {:ok, _}
    ast = {:{}, [], [{:ok, [], nil}, {:_}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)
  end

  test "handles pin pattern in list pattern" do
    context = full_mode_context()
    # List pattern with pin: [^x, y]
    ast = [{:^, [], [{:x, [], Elixir}]}, {:y, [], Elixir}]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)
  end

  test "handles wildcard and pin in same pattern" do
    context = full_mode_context()
    # Map pattern with both wildcard and pin: %{^key => _}
    # Note: This is a simplified representation
    pin_ast = {:^, [], [{:key, [], Elixir}]}
    wildcard_ast = {:_}

    {:ok, {pin_iri, _, _}} = ExpressionBuilder.build(pin_ast, context, [])
    {:ok, {wildcard_iri, _, _}} = ExpressionBuilder.build(wildcard_ast, context, [])

    pin_triples = ExpressionBuilder.build_pattern(pin_ast, pin_iri, context)
    wildcard_triples = ExpressionBuilder.build_pattern(wildcard_ast, wildcard_iri, context)

    assert has_type?(pin_triples, Core.PinPattern)
    assert has_type?(wildcard_triples, Core.WildcardPattern)
  end
end
```

### Step 4: Update Test Helper Functions

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

The `has_variable_name?/3` helper should already exist from Phase 24.2. Verify it's present:

```elixir
defp has_variable_name?(triples, subject_iri, expected_name) do
  Enum.any?(triples, fn {s, p, o} ->
    s == subject_iri and p == Core.name() and RDF.Literal.value(o) == expected_name
  end)
end
```

### Step 5: Run Verification

5.1 Run `mix test test/elixir_ontologies/builders/expression_builder_test.exs --only wildcard_pattern`
5.2 Run `mix test test/elixir_ontologies/builders/expression_builder_test.exs --only pin_pattern`
5.3 Verify new pattern extraction tests pass
5.4 Verify no regressions in existing tests

## 4. Technical Details

### File Locations

**Implementation:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
  - `build_wildcard_pattern/3` at lines 1287-1290 - currently complete, add documentation
  - `build_pin_pattern/3` at lines 1292-1299 - currently complete, add documentation

**Tests:**
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add `describe "wildcard pattern extraction"` block after pattern dispatch tests (around line 2910)
  - Add `describe "pin pattern extraction"` block
  - Add `describe "nested pattern extraction with wildcards and pins"` block

**Ontology Reference:**
- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`
  - `Core.WildcardPattern` at lines 358-361
  - `Core.PinPattern` at lines 363-367
  - `pinsVariable` property at lines 621-624 (for future use with scope analysis)

### Ontology Classes and Properties

**Existing Classes:**
- `Core.WildcardPattern` (line 358-361) - The underscore _ pattern that matches anything and discards the value
- `Core.PinPattern` (line 363-367) - The ^variable pattern that matches against a variable's existing value
- `Core.VariablePattern` (line 353-356) - A pattern that binds a matched value to a variable name

**Existing Properties:**
- `Core.name()` - For identifier names (line 796-799)
- `Core.pinsVariable()` - Links pin pattern to variable instance (line 621-624) - for future use

### Pattern Detection Summary

| Pattern | AST | Detected As | Builder Function |
|---------|-----|-------------|------------------|
| `_` | `{:_}` | `:wildcard_pattern` | `build_wildcard_pattern/3` |
| `^x` | `{:^, _, [{:x, _, _}]}` | `:pin_pattern` | `build_pin_pattern/3` |
| `_name` | `{:_name, _, ctx}` | `:variable_pattern` | `build_variable_pattern/3` |
| `x` | `{:x, _, ctx}` | `:variable_pattern` | `build_variable_pattern/3` |

### Current Test Coverage

**From Phase 24.1:**
- Pattern type detection tests (lines 2763-2771)
- Pattern dispatch tests via `build_pattern/3` (lines 2885-2911)

**What's Missing for Phase 24.3:**
- Dedicated wildcard pattern extraction tests
- Dedicated pin pattern extraction tests
- Nested pattern tests with wildcards and pins
- Distinction tests between wildcards, variables, and pins

## 5. Success Criteria

1. **Wildcard pattern extraction:**
   - Anonymous wildcard `{:_}` creates `Core.WildcardPattern` type triple
   - Wildcard representation is minimal (no additional properties)
   - Distinguished from `VariablePattern` in tests

2. **Pin pattern extraction:**
   - Pin pattern `^x` creates `Core.PinPattern` type triple
   - Variable name captured via `name` property
   - Distinguished from `VariablePattern` in tests

3. **Nested patterns:**
   - Wildcards in tuple patterns handled correctly
   - Pins in list patterns handled correctly
   - Combined wildcard and pin patterns work correctly

4. **Tests pass:**
   - All new wildcard pattern tests pass (2-3 tests)
   - All new pin pattern tests pass (3-4 tests)
   - All nested pattern tests pass (2-3 tests)
   - No regressions in existing tests (256+ tests)

5. **Code quality:**
   - Functions follow existing code style
   - Proper documentation added
   - Test helpers reused from Phase 24.2

## 6. Notes and Considerations

### 6.1 Named Wildcards

Variables with leading underscores (`_name`) are NOT wildcards in Elixir - they are regular variables that happen to start with underscore. The compiler treats them as variables but doesn't emit "unused variable" warnings. The current `detect_pattern_type/1` correctly identifies them as `:variable_pattern`, not `:wildcard_pattern`.

Only the single underscore `{:_}` is a true wildcard pattern.

### 6.2 Pin Operator Semantics

The pin operator `^x` matches against the existing value of variable `x`. If `x` is unbound, a compile error occurs. This is different from the variable pattern `x` which would bind the matched value to `x`.

Current implementation captures the variable name but does not link to a `Core.Variable` instance. This is acceptable without scope analysis. Future work could add `pinsVariable` object property linking.

### 6.3 Expression vs Pattern Context

Both wildcards and pins can appear in expression contexts:
- In expression context, `{:_}` is handled by `build_wildcard/1` (line 637-639) - creates `Core.WildcardPattern`
- In expression context, `^x` is an error (pin only valid in pattern context)

The `build_pattern/3` function assumes pattern context, so wildcard and pin patterns are always created with pattern types.

### 6.4 Future Integration Points

These pattern builders will be used by:
- Function clause parameter extractors
- Case expression clause extractors
- Match expression handlers
- For comprehension generators (can use pins)
- Receive pattern matching

## 7. Progress Tracking

- [x] 7.1 Review current `build_wildcard_pattern/3` implementation
- [x] 7.2 Review current `build_pin_pattern/3` implementation
- [x] 7.3 Add documentation to both builder functions
- [x] 7.4 Create `describe "wildcard pattern extraction"` test block (2-3 tests)
- [x] 7.5 Create `describe "pin pattern extraction"` test block (3-4 tests)
- [x] 7.6 Create `describe "nested pattern extraction"` test block (2-3 tests)
- [x] 7.7 Run verification
- [x] 7.8 Write summary document
- [ ] 7.9 Ask for permission to commit and merge

## 8. Status Log

### 2026-01-12 - Initial Planning
- Analyzed Phase 24.3 requirements
- Reviewed existing `build_wildcard_pattern/3` and `build_pin_pattern/3` implementations
- Confirmed implementations are functionally complete
- Identified documentation and test coverage gaps
- Created planning document

### 2026-01-12 - Implementation Complete
- Added comprehensive documentation to `build_wildcard_pattern/3` with doctest
- Added comprehensive documentation to `build_pin_pattern/3` with doctest
- Added 8 new tests (2 wildcard, 3 pin, 3 nested pattern tests)
- Total: 264 tests, 0 failures
- Summary document created at `notes/summaries/phase-24-3-wildcard-pin-patterns.md`

---

### Critical Files for Implementation

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` - Main implementation file; `build_wildcard_pattern/3` at lines 1287-1290, `build_pin_pattern/3` at lines 1292-1299

- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs` - Test file; add new test blocks after existing pattern dispatch tests (around line 2910)

- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` - Reference for pattern classes; `WildcardPattern` at lines 358-361, `PinPattern` at lines 363-367, `pinsVariable` property at lines 621-624

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Helper functions for RDF triple creation; `type_triple/2`, `datatype_property/4`

- `/home/ducky/code/elixir-ontologies/notes/features/phase-24-2-literal-variable-patterns.md` - Reference for Phase 24.2 test patterns and helper functions
