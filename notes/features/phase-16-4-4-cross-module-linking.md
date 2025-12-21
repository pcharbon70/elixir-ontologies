# Phase 16.4.4: Cross-Module Linking

## Overview

This task implements cross-module linking for directives, connecting module references in directives (alias, import, require, use) to actual module definitions when they exist within the analysis scope. For external dependencies (e.g., Elixir stdlib, third-party libraries), we mark these references appropriately.

## Current State

The dependency builder currently generates IRIs for referenced modules but doesn't distinguish between:
- Modules defined within the project (in analysis scope)
- External modules (Elixir stdlib, hex packages)

All module references use `IRI.for_module/2` which generates an IRI regardless of whether the module exists in the RDF graph.

## Goals

1. Track which modules are known/defined in the analysis scope
2. Link directives to actual module definitions when available
3. Mark external/unresolved module references appropriately
4. Enable queries to distinguish internal vs external dependencies

## Design Decisions

### Module Resolution Strategy

We'll use a **known modules registry** passed through the builder context. This registry is populated during project analysis before dependency building.

```elixir
# Context enhancement
%Context{
  # ... existing fields
  known_modules: MapSet.t(String.t())  # Set of module names in analysis scope
}
```

### Resolution vs External Marking

Rather than trying to resolve aliases at build time (which would require tracking alias scope), we take a simpler approach:

1. **isExternalModule** - Boolean property indicating if the referenced module is outside analysis scope
2. The existing `aliasedModule`, `importsModule`, `requireModule`, `useModule` properties continue to point to the IRI (internal or external)

This means:
- Query for internal dependencies: filter where `isExternalModule = false`
- Query for external dependencies: filter where `isExternalModule = true`

### Ontology Properties

Add to `priv/ontologies/elixir-structure.ttl`:

```turtle
# External module marking for directives
:isExternalModule a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "is external module"@en ;
    rdfs:comment "Indicates if the referenced module is outside the analysis scope (external dependency)."@en ;
    rdfs:range xsd:boolean .
```

Note: We don't need a `referencesExternalModule` object property since we already have `aliasedModule`, `importsModule`, etc. The boolean flag is sufficient to distinguish.

### __using__ Macro Linking

For use directives, we can optionally link to the `__using__/1` macro if it exists in the target module. This requires:
1. The target module is in analysis scope
2. The `__using__/1` macro was extracted from that module

New property:
```turtle
:invokesUsing a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "invokes using"@en ;
    rdfs:comment "Links a use directive to the __using__/1 macro it invokes."@en ;
    rdfs:domain :Use ;
    rdfs:range :Macro .
```

## Implementation Plan

### 16.4.4.1 Context Enhancement for Known Modules

Extend `Context` struct to track known modules:

```elixir
defstruct [
  # ... existing
  known_modules: MapSet.new()  # Module names that exist in analysis scope
]
```

Add helper functions:
```elixir
def with_known_modules(context, modules)
def module_known?(context, module_name)
```

### 16.4.4.2 External Module Detection

Add to `DependencyBuilder`:

```elixir
def build_external_module_triple(iri, module_name, context)
```

This generates:
- `{directive_iri, struct:isExternalModule, true/false}` based on context lookup

### 16.4.4.3 Update Existing Dependency Builders

Modify each builder function to:
1. Check if target module is known
2. Add `isExternalModule` triple

Affected functions:
- `build_alias_dependency/4`
- `build_import_dependency/4`
- `build_require_dependency/4`
- `build_use_dependency/4`

### 16.4.4.4 __using__ Macro Linking (Optional Enhancement)

For use directives where target module is known:
1. Check if `__using__/1` macro IRI can be generated
2. Add `invokesUsing` triple if appropriate

This is optional because macro extraction may not always be available.

### 16.4.4.5 Tests

Add tests for:
- External module detection (Elixir stdlib modules)
- Internal module detection (modules in scope)
- Mixed dependencies (some internal, some external)
- Context with/without known modules
- Use directive with `__using__` linking

## Files to Modify

1. `priv/ontologies/elixir-structure.ttl` - Add properties
2. `lib/elixir_ontologies/ns.ex` - Add property accessors (if needed)
3. `lib/elixir_ontologies/builders/context.ex` - Add known_modules field
4. `lib/elixir_ontologies/builders/dependency_builder.ex` - Add external module detection
5. `test/elixir_ontologies/builders/dependency_builder_test.exs` - Add tests

## Backwards Compatibility

The changes are additive:
- New optional field in Context (defaults to empty MapSet)
- New triples generated (queries still work, just more information)
- Existing behavior preserved when no known_modules provided

## Example Usage

```elixir
# During project analysis, collect known modules
known = MapSet.new(["MyApp.Users", "MyApp.Accounts", "MyApp.Repo"])

context = Context.new(
  base_iri: "https://example.org/code#",
  known_modules: known
)

# For `alias MyApp.Users, as: U`
# Generates: isExternalModule = false (in scope)

# For `import Enum`
# Generates: isExternalModule = true (stdlib, not in scope)

# For `use GenServer`
# Generates: isExternalModule = true (stdlib, not in scope)
```

## Next Steps After This Task

- 16.4 section unit tests for cross-module linking
- Phase 16 integration tests
