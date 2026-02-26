# Phase 22.1: Atom Literal Extraction

**Status:** ✅ Complete
**Branch:** `feature/phase-22-1-atom-literals`
**Created:** 2025-01-10
**Completed:** 2025-01-10
**Target:** Implement specialized atom literal extraction (BooleanLiteral, NilLiteral)

## 1. Problem Statement

Phase 21 implemented basic atom literal extraction using the generic `AtomLiteral` class. However, the Phase 22 plan specifies that boolean atoms (`true`, `false`) and `nil` should have their own specialized classes:

- `BooleanLiteral` - subclass of `AtomLiteral` for `true` and `false`
- `NilLiteral` - subclass of `AtomLiteral` for `nil`

The ontology currently only has `AtomLiteral`, so these specialized classes need to be added first.

**Current State:**
- ExpressionBuilder already has `build_atom_literal/2` function
- Currently all atoms (including `true`, `false`, `nil`) use `Core.AtomLiteral`
- `nil` returns `:skip` instead of creating a literal
- Tests expect generic `AtomLiteral` for all atoms

**Desired State:**
- `true` and `false` → `Core.BooleanLiteral` type triple
- `nil` → `Core.NilLiteral` type triple (not `:skip`)
- Other atoms (`:ok`, `:error`, etc.) → `Core.AtomLiteral` type triple

## 2. Solution Overview

The implementation requires:

1. **Ontology Extension:** Add `BooleanLiteral` and `NilLiteral` classes to `elixir-core.ttl`
2. **Builder Update:** Modify `build_atom_literal/2` to return specific types
3. **Test Updates:** Update tests to verify the new specific types

### Key Design Decisions

**Question:** Should `nil` be extracted or return `:skip`?

Looking at the current implementation, `nil` returns `:skip`. However, the Phase 22 plan specifically mentions `NilLiteral` as a subclass of `AtomLiteral`. The plan is authoritative, so we should extract `nil` as `NilLiteral`.

## 3. Agent Consultations Performed

**Self-Analysis:**
- Reviewed existing ExpressionBuilder implementation in `lib/elixir_ontologies/builders/expression_builder.ex`
- Reviewed ontology structure in `ontology/elixir-core.ttl`
- Reviewed NS module for vocabulary loading mechanism
- Reviewed test file `test/elixir_ontologies/builders/expression_builder_test.exs`

## 4. Technical Details

### Files to Modify

#### 4.1 Ontology Files

**File:** `ontology/elixir-core.ttl` (source)
**File:** `priv/ontologies/elixir-core.ttl` (compiled - needs manual sync)

Add after `AtomLiteral` definition (around line 110):

```turtle
:BooleanLiteral a owl:Class ;
    rdfs:label "Boolean Literal"@en ;
    rdfs:comment "A boolean atom literal: true or false."@en ;
    rdfs:subClassOf :AtomLiteral .

:NilLiteral a owl:Class ;
    rdfs:label "Nil Literal"@en ;
    rdfs:comment "The nil atom literal representing absence of value."@en ;
    rdfs:subClassOf :AtomLiteral .
```

#### 4.2 ExpressionBuilder

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

Current implementation (line 510-515):
```elixir
defp build_atom_literal(atom_value, expr_iri) do
  [
    Helpers.type_triple(expr_iri, Core.AtomLiteral),
    Helpers.datatype_property(expr_iri, Core.atomValue(), atom_to_string(atom_value), RDF.XSD.String)
  ]
end
```

New implementation needed:
```elixir
defp build_atom_literal(atom_value, expr_iri) do
  type_class =
    case atom_value do
      true -> Core.BooleanLiteral
      false -> Core.BooleanLiteral
      nil -> Core.NilLiteral
      _ -> Core.AtomLiteral
    end

  [
    Helpers.type_triple(expr_iri, type_class),
    Helpers.datatype_property(expr_iri, Core.atomValue(), atom_to_string(atom_value), RDF.XSD.String)
  ]
end
```

Also need to update `build_expression_triples/3` for `nil` case (line 325-328):
```elixir
# Atom literals (including true, false, nil)
def build_expression_triples(atom, expr_iri, _context) when is_atom(atom) do
  build_atom_literal(atom, expr_iri)
end
```

The current `nil` handling (around line 44-46) that returns `:skip` needs to be removed:
```elixir
test "returns :skip for nil AST regardless of mode" do
  # This test should be updated - nil should now create NilLiteral
```

#### 4.3 Test Updates

**File:** `test/elixir_ontologies/builders/expression_builder_test.exs`

Current tests (line 411-430):
- `builds AtomLiteral triples for true` - should expect `BooleanLiteral`
- `builds AtomLiteral triples for false` - should expect `BooleanLiteral`
- `returns :skip for nil literals` - should expect `NilLiteral` instead

## 5. Success Criteria

1. **Ontology updated:**
   - `BooleanLiteral` class added as subclass of `AtomLiteral`
   - `NilLiteral` class added as subclass of `AtomLiteral`
   - Both `ontology/elixir-core.ttl` and `priv/ontologies/elixir-core.ttl` updated

2. **ExpressionBuilder updated:**
   - `true` creates `BooleanLiteral` triples
   - `false` creates `BooleanLiteral` triples
   - `nil` creates `NilLiteral` triples (not `:skip`)
   - Other atoms create `AtomLiteral` triples

3. **Tests pass:**
   - All existing tests updated to expect new types
   - New tests added for BooleanLiteral and NilLiteral
   - All ExpressionBuilder tests pass

4. **Backward compatibility:**
   - Light mode still returns `:skip` for all literals when `include_expressions: false`

## 6. Implementation Plan

### Step 1: Update Ontology
- [x] 1.1 Add `BooleanLiteral` class to `ontology/elixir-core.ttl`
- [x] 1.2 Add `NilLiteral` class to `ontology/elixir-core.ttl`
- [x] 1.3 Copy changes to `priv/ontologies/elixir-core.ttl`

### Step 2: Update ExpressionBuilder
- [x] 2.1 Modify `build_atom_literal/2` to return specific types
- [x] 2.2 Remove `nil` `:skip` handling from `build/3`
- [x] 2.3 Verify `build_expression_triples/3` correctly handles `nil`

### Step 3: Update Tests
- [x] 3.1 Update test for `true` to expect `BooleanLiteral`
- [x] 3.2 Update test for `false` to expect `BooleanLiteral`
- [x] 3.3 Update test for `nil` to expect `NilLiteral` (not `:skip`)
- [x] 3.4 Add test verifying other atoms still use `AtomLiteral`

### Step 4: Verify
- [x] 4.1 Run ExpressionBuilder tests
- [x] 4.2 Verify no regressions in other builders
- [x] 4.3 Run full test suite

## 7. Notes/Considerations

### Ontology File Synchronization

The project has ontology files in two locations:
- `ontology/elixir-core.ttl` - source (32884 bytes)
- `priv/ontologies/elixir-core.ttl` - compiled (36208 bytes)

The NS module reads from `priv/ontologies/`, so both files must be updated. The source file in `ontology/` is smaller, suggesting there may be a build process that generates the compiled version. For this change, we'll update both manually.

### Property Inheritance

Since `BooleanLiteral` and `NilLiteral` are subclasses of `AtomLiteral`, they inherit the `atomValue` property. No new properties are needed.

### Test Assertions

The tests use helper functions like `has_type?/2`. These will automatically work with the new types once the NS module is reloaded.

### Light Mode Behavior

The `:skip` behavior for light mode (when `include_expressions: false`) should still apply. Only the `nil` handling in full mode changes.

## 8. Progress Tracking

- [x] 8.1 Create feature branch
- [x] 8.2 Create planning document
- [x] 8.3 Implement Step 1: Update Ontology
- [x] 8.4 Implement Step 2: Update ExpressionBuilder
- [x] 8.5 Implement Step 3: Update Tests
- [x] 8.6 Implement Step 4: Verify
- [x] 8.7 Write summary document
- [ ] 8.8 Ask for permission to commit and merge

## 9. Status Log

### 2025-01-10 - Initial Planning
- Created feature branch `feature/phase-22-1-atom-literals`
- Analyzed existing ExpressionBuilder implementation
- Identified ontology extension requirements
- Created planning document

### 2025-01-10 - Implementation Complete ✅
- **Ontology updated:**
  - Added `BooleanLiteral` class to both `ontology/elixir-core.ttl` and `priv/ontologies/elixir-core.ttl`
  - Added `NilLiteral` class to both ontology files
  - Both classes defined as subclasses of `AtomLiteral`

- **ExpressionBuilder updated:**
  - Modified `build_atom_literal/2` to return specific types based on atom value
  - Removed special `nil` handling that returned `:skip`
  - `true` and `false` now create `BooleanLiteral` triples
  - `nil` now creates `NilLiteral` triples
  - Other atoms continue to create `AtomLiteral` triples

- **Tests updated:**
  - Updated "builds AtomLiteral triples for true" → "builds BooleanLiteral triples for true"
  - Updated "builds AtomLiteral triples for false" → "builds BooleanLiteral triples for false"
  - Updated "returns :skip for nil literals" → "builds NilLiteral triples for nil"
  - Updated "returns :skip for nil AST regardless of mode" → "returns {:ok, ...} for nil AST in full mode"

- **Test Results:**
  - 76 ExpressionBuilder tests: 0 failures
  - Full test suite: 7108 tests, 0 failures, 361 excluded (pending/integration)
