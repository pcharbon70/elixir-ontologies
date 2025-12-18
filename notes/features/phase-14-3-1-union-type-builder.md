# Phase 14.3.1: Union Type Builder

## Problem Statement

The TypeSystemBuilder can generate RDF triples for type definitions and function specs, but the `build_type_expression_triples/3` function is currently a stub that returns empty lists. This means union types extracted by the TypeExpression extractor (Phase 14.1.1) are not being converted to RDF representation.

**Impact**: Without union type RDF generation, the knowledge graph cannot represent type unions like `integer() | atom()` or `{:ok, result} | {:error, reason}`, which are fundamental to Elixir's type system.

## Solution Overview

Implement `build_union_type/3` and related functions in TypeSystemBuilder to generate RDF triples following the elixir-structure.ttl ontology:

- `structure:UnionType` class for the union type expression
- `structure:unionOf` property linking to each member type
- Recursive building for nested type expressions

### Key Design Decisions

1. **IRI Generation**: Union types will use blank nodes since they are anonymous structural types (not named definitions)
2. **Recursive Building**: Each union member may itself be a complex type expression requiring recursive processing
3. **TypeExpression Integration**: Use the TypeExpression parser to convert AST to structured form before building

## Technical Details

### Files to Modify

1. **lib/elixir_ontologies/builders/type_system_builder.ex**
   - Add `build_type_expression/3` public function for recursive type building
   - Implement `build_union_type/3` for union types
   - Implement `build_basic_type/3` for basic types
   - Update `build_type_expression_triples/3` to call the new builder

2. **test/elixir_ontologies/builders/type_system_builder_test.exs**
   - Add tests for union type RDF generation
   - Test nested unions
   - Test integration with type definitions

### Ontology Mapping

From `elixir-structure.ttl`:
```turtle
:UnionType a owl:Class ;
    rdfs:label "Union Type"@en ;
    rdfs:comment "A union of types: type1 | type2."@en ;
    rdfs:subClassOf :TypeExpression .

:unionOf a owl:ObjectProperty ;
    rdfs:label "union of"@en ;
    rdfs:domain :UnionType ;
    rdfs:range :TypeExpression .
```

### RDF Output Example

For type expression `integer() | atom()`:
```turtle
_:union1 a structure:UnionType .
_:union1 structure:unionOf _:basic1 .
_:union1 structure:unionOf _:basic2 .
_:basic1 a structure:BasicType .
_:basic1 structure:typeName "integer" .
_:basic2 a structure:BasicType .
_:basic2 structure:typeName "atom" .
```

## Success Criteria

- [x] `build_type_expression/2` handles union type AST patterns
- [x] Generates `rdf:type structure:UnionType` triple
- [x] Generates `structure:unionOf` triples for each member
- [x] Handles nested unions correctly (member types recursively built)
- [x] All tests pass (12 new tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Implementation Plan

### Step 1: Add build_type_expression/3 public API
- [x] Add function that takes AST and context, returns {node, triples}
- [x] Route to specific builders based on TypeExpression.parse() result

### Step 2: Implement build_union_type/3
- [x] Create blank node for union type
- [x] Generate rdf:type triple
- [x] Recursively build member types
- [x] Generate unionOf triples

### Step 3: Implement build_basic_type/3
- [x] Handle basic types as union members
- [x] Generate BasicType class triple
- [x] Generate typeName triple

### Step 4: Update build_type_expression_triples/3
- [x] Call build_type_expression for type definition expressions
- [x] Link type definition to its expression

### Step 5: Add comprehensive tests
- [x] Test simple union `a | b`
- [x] Test multi-member union `a | b | c`
- [x] Test nested union types
- [x] Test union in type definition
- [x] Test type expression IRI patterns

### Step 6: Verify and cleanup
- [x] Run full test suite
- [x] Check credo compliance
- [x] Update phase-14.md

## Notes/Considerations

- Union types are anonymous (use blank nodes) rather than named
- The TypeExpression extractor already flattens nested unions
- Need to handle all type expression kinds for recursive building (basic implemented first)
- Future phases will add support for other type expression kinds (tuples, lists, maps, etc.)
