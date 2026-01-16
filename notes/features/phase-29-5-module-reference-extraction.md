# Phase 29.5: Module Reference Extraction

**Feature Branch:** `feature/phase-29-5-module-reference-extraction`
**Created:** 2026-01-16
**Based On:** Phase 29 Expressions Plan (`notes/planning/expressions/phase-29.md`)

---

## Problem Statement

Phase 29.5 implements extraction for module references and aliases used as expressions. Module references can appear in various contexts:
- As standalone atoms: `MyApp`, `String`, etc.
- In attribute definitions: `@moduledoc MyApp`
- In type specs: `@spec foo(MyApp.Type) :: :ok`
- As values in data structures

The AST for module aliases is `{:__aliases__, _, parts}` where `parts` is a list of atoms like `[:MyApp, :Users]`.

Currently, the ExpressionBuilder does not handle module aliases as standalone expressions - they fall through to the generic atom handler.

---

## Solution Overview

This enhancement adds:
1. **Module reference handler** - Detect `{:__aliases__, _, parts}` pattern
2. **Builder function** - Create `ModuleReference` type with `moduleName` property
3. **Property domain update** - Extend `moduleName` property to include `ModuleReference`
4. **Module IRI linking** - Add `refersToModule` object property

---

## Technical Details

### Files Modified

| File | Changes |
|------|---------|
| `priv/ontologies/elixir-core.ttl` | Update moduleName property domain to include ModuleReference |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add module reference handler and builder |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add tests for module references |

### AST Patterns

**Module Alias (Simple):**
```elixir
# Elixir code: MyApp
# AST:
{:__aliases__, [], [:MyApp]}

# Pattern to match: {:__aliases__, _, parts}
```

**Module Alias (Nested):**
```elixir
# Elixir code: MyApp.Users
# AST:
{:__aliases__, [], [:MyApp, :Users]}
```

**Module Alias (Elixir prefix):**
```elixir
# Elixir code: Elixir.MyApp
# AST:
{:__aliases__, [], [:Elixir, :MyApp]}
```

### Ontology Changes

**Update Property Domain:**
```turtle
:moduleName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "module name"@en ;
    rdfs:comment "The module name for a remote function call or module reference (e.g., 'String', 'MyApp.Users')."@en ;
    rdfs:domain :RemoteCall, :ModuleReference ;  # Add :ModuleReference
    rdfs:range xsd:string .
```

---

## Implementation Plan

### 1.0 Setup
- [x] 1.1 Create feature branch `feature/phase-29-5-module-reference-extraction`
- [x] 1.2 Create planning document

### 2.0 Ontology Updates
- [x] 2.1 Update `moduleName` property domain to include `:ModuleReference`

### 3.0 Detection Logic
- [x] 3.1 Add module alias pattern matching
- [x] 3.2 Must come BEFORE atom literal handler (atoms are less specific)
- [x] 3.3 Match: `{:__aliases__, _, parts}`
- [x] 3.4 Handle single-part and multi-part aliases

### 4.0 Builder Implementation
- [x] 4.1 Implement `build_module_reference/3` function
- [x] 4.2 Create type triple: `expr_iri a Core.ModuleReference`
- [x] 4.3 Extract full module name from parts
- [x] 4.4 Create `moduleName` property
- [x] 4.5 Create `refersToModule` object property with module IRI

### 5.0 Test Updates
- [x] 5.1 Add test for simple module alias (single part)
- [x] 5.2 Add test for nested module alias (multi-part)
- [x] 5.3 Add test for Elixir prefix handling
- [x] 5.4 Add test for moduleName property
- [x] 5.5 Add test for refersToModule property
- [x] 5.6 Run all tests and verify passing

### 6.0 Final Verification
- [x] 6.1 Run all tests and verify no regressions
- [ ] 6.2 Create summary document
- [ ] 6.3 Ask for commit and merge permission

---

## Notes and Considerations

### Design Decisions

1. **Handler ordering**: The module alias handler must come BEFORE the atom literal handler, because atoms are a more general pattern that would also match.

2. **Module IRI format**: The `refersToModule` property will link to a module IRI using the format: `{base_iri}module/{ModuleName}`

3. **Elixir prefix**: Module names starting with `:Elixir` will have the prefix preserved in the module name (e.g., `Elixir.String`).

4. **Reusing existing helpers**: The `extract_module_name/1` helper already exists in the codebase for extracting module names from alias ASTs.

### Testing Strategy

- Test with simple aliases: `MyApp`
- Test with nested aliases: `MyApp.Users.Profile`
- Test with Elixir prefix: `Elixir.String`
- Verify `moduleName` property is set correctly
- Verify `refersToModule` property links to correct IRI

### Known Limitations

1. **Dynamic module references**: Module references computed at runtime cannot be handled with static analysis.

2. **Alias resolution**: This implementation extracts the module name as written in the source code, not its resolved value after aliasing (e.g., if `alias MyApp.Users, as: Users` is used, we still extract `Users`, not `MyApp.Users`).

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
- Created feature branch `feature/phase-29-5-module-reference-extraction`
- Created planning document
- Updated `moduleName` property domain to include `ModuleReference`
- Implemented module reference detection and builder
- Added 7 tests for module references
- All 398 tests passing (including 9 doctests)

**Test Results:**
- 398 expression builder tests + 9 doctests: 0 failures
- 134 control flow builder tests: 0 failures
- Total: 535 tests, 0 failures

---

*Last Updated:* 2026-01-16
*Branch:* feature/phase-29-5-module-reference-extraction
