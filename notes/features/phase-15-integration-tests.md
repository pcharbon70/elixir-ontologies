# Phase 15 Integration Tests

## Overview

Implement comprehensive integration tests for Phase 15 metaprogramming support. These tests verify end-to-end functionality across macro invocation extraction, attribute value extraction, quote/unquote handling, and RDF generation.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- Test complete metaprogramming extraction for macro-heavy module
- Test macro invocation tracking across multiple modules
- Test attribute value extraction for all attribute types
- Test quote/unquote extraction in macro definitions
- Test metaprogramming RDF validates against shapes
- Test Pipeline integration with metaprogramming extractors
- Test Orchestrator coordinates metaprogramming builders
- Test cross-module macro invocation linking
- Test accumulated attribute representation
- Test documentation content preservation
- Test compile attribute extraction
- Test nested quote handling
- Test hygiene analysis accuracy
- Test backward compatibility with existing macro extraction
- Test error handling for complex AST patterns

## Key Components to Test

### Extractors
- `MacroInvocation` - Macro invocation extraction
- `Attribute` - Module attribute extraction with values
- `Quote` - Quote/unquote/hygiene extraction

### Builders
- `MacroBuilder` - Macro invocation RDF generation
- `AttributeBuilder` - Attribute value RDF generation
- `QuoteBuilder` - Quote block RDF generation

## Test Structure

Following the pattern from `Phase14IntegrationTest`:

1. **Test Helpers**
   - Context builders
   - IRI generators
   - Triple assertion helpers
   - Code extraction helpers

2. **Macro-Heavy Module Tests**
   - Module with multiple macro types
   - End-to-end extraction and building

3. **Attribute Tests**
   - All attribute types
   - Accumulated attributes
   - Documentation content

4. **Quote/Unquote Tests**
   - Quote options
   - Nested quotes
   - Hygiene violations

5. **Error Handling Tests**
   - Complex AST patterns
   - Edge cases

## Implementation Plan

### Step 1: Create Test File Structure
- [ ] Create `test/elixir_ontologies/metaprogramming/phase_15_integration_test.exs`
- [ ] Add test helpers and setup

### Step 2: Macro-Heavy Module Tests
- [ ] Test complete extraction for macro-heavy module
- [ ] Test macro invocation tracking
- [ ] Test cross-module macro references

### Step 3: Attribute Tests
- [ ] Test all attribute types extraction
- [ ] Test accumulated attributes
- [ ] Test documentation content preservation
- [ ] Test compile attribute extraction

### Step 4: Quote/Unquote Tests
- [ ] Test quote block extraction in macro definitions
- [ ] Test nested quote handling
- [ ] Test hygiene analysis accuracy
- [ ] Test unquote linking

### Step 5: RDF Validation Tests
- [ ] Test RDF generation for all metaprogramming constructs
- [ ] Test triple correctness

### Step 6: Error Handling Tests
- [ ] Test backward compatibility
- [ ] Test error handling for complex patterns

## Success Criteria

- [ ] 15+ integration tests passing
- [ ] All metaprogramming extractors tested
- [ ] All metaprogramming builders tested
- [ ] Edge cases covered
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix credo --strict` passes
