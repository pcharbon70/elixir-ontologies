# Phase 17.4.3: Exception Builder - Summary

## Completed

Implemented the `ExceptionBuilder` module for generating RDF triples from exception handling expressions.

## Files Created

- `lib/elixir_ontologies/builders/exception_builder.ex` - Main builder module
- `test/elixir_ontologies/builders/exception_builder_test.exs` - Test suite (30 tests)

## Implementation Details

### Builder Functions

1. **`build_try/3`** - Builds try expressions
   - Generates `rdf:type core:TryExpression`
   - Generates `hasRescueClause` boolean when rescue clauses present
   - Generates `hasCatchClause` boolean when catch clauses present
   - Generates `hasAfterClause` boolean when after block present
   - Generates `hasElseClause` boolean when else clauses present

2. **`build_raise/3`** - Builds raise/reraise expressions
   - Generates `rdf:type core:RaiseExpression`
   - Covers both raise and reraise (same ontology class)

3. **`build_throw/3`** - Builds throw expressions
   - Generates `rdf:type core:ThrowExpression`

### IRI Patterns

- Try: `{base}try/{containing_function}/{index}`
- Raise: `{base}raise/{containing_function}/{index}`
- Throw: `{base}throw/{containing_function}/{index}`

### Location Handling

All builders generate `core:startLine` triples when location information is available.

## Design Decisions

1. **Boolean properties for clause presence** - Following the pattern from ControlFlowBuilder, we use boolean indicators (`hasRescueClause: true`) rather than linking to individual clauses.

2. **No isReraise property** - The ontology doesn't define an `isReraise` property, so both raise and reraise use `core:RaiseExpression` type. The distinction is preserved in the extraction struct but not in RDF.

3. **Builder pattern** - Follows established pattern:
   - Takes extraction struct + Context
   - Returns `{iri, triples}` tuple
   - Uses `Helpers` module for triple generation

## Test Coverage

30 tests covering:
- IRI generation for try/raise/throw expressions
- Type triple generation for all expression types
- Rescue clause detection
- Catch clause detection
- After block detection
- Else clause detection
- Complete try with all clause types
- Raise expression building
- Throw expression building
- Location handling
- Edge cases (defaults, single clause types)

## Quality Checks

- `mix compile --warnings-as-errors` - Pass
- `mix credo --strict` on new file - No issues
- All 30 tests pass
