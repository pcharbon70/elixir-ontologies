# Phase 16.4.4: Cross-Module Linking - Summary

## Completed

Implemented cross-module linking for module directive dependency building, enabling detection of internal vs external module references and linking use directives to their `__using__/1` macros.

## Changes Made

### Ontology Extensions

Added to `priv/ontologies/elixir-structure.ttl`:

```turtle
# Cross-module linking properties
:isExternalModule a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "is external module"@en ;
    rdfs:comment "Indicates if the referenced module is outside the analysis scope."@en ;
    rdfs:range xsd:boolean .

:invokesUsing a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "invokes using"@en ;
    rdfs:comment "Links a use directive to the __using__/1 macro it invokes."@en ;
    rdfs:domain :Use ;
    rdfs:range :Macro .
```

### Context Enhancement

Extended `lib/elixir_ontologies/builders/context.ex` with:

```elixir
# New field
defstruct [
  # ... existing fields
  known_modules: nil  # MapSet.t(String.t()) | nil
]

# New functions
with_known_modules(context, modules)  # Set known modules from MapSet or list
module_known?(context, module_name)   # Check if module is in analysis scope
cross_module_linking_enabled?(context) # Check if linking is configured
```

### DependencyBuilder Functions

Extended `lib/elixir_ontologies/builders/dependency_builder.ex`:

```elixir
# Private helpers added
build_external_module_triple(directive_iri, module_name, context)
build_invokes_using_triple(use_iri, module_name, context)
```

### Generated Triples

#### For All Directives (when cross-module linking enabled):
- `{directive_iri, struct:isExternalModule, true/false}` - Indicates if target module is external

#### For Use Directives (when target module is known):
- `{use_iri, struct:invokesUsing, module/__using__/1}` - Links to the `__using__/1` macro

### Behavior

1. **Cross-module linking disabled** (known_modules = nil):
   - No `isExternalModule` or `invokesUsing` triples generated
   - Backwards compatible with existing code

2. **Cross-module linking enabled** (known_modules = MapSet):
   - Each directive gets `isExternalModule` triple
   - Known modules: `isExternalModule = false`
   - External modules: `isExternalModule = true`
   - Use directives to known modules also get `invokesUsing` triple

## Files Modified

- `priv/ontologies/elixir-structure.ttl` - Added 2 properties
- `lib/elixir_ontologies/builders/context.ex` - Added known_modules field and helpers
- `lib/elixir_ontologies/builders/dependency_builder.ex` - Added external module detection
- `test/elixir_ontologies/builders/dependency_builder_test.exs` - Added 16 tests
- `notes/planning/extractors/phase-16.md` - Marked 16.4.4 complete
- `notes/features/phase-16-4-4-cross-module-linking.md` - Feature planning document

## Test Results

- 71 doctests, 531 builder tests, 0 failures
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes (only pre-existing refactoring suggestions)

## Usage Examples

### Basic Usage
```elixir
alias ElixirOntologies.Builders.{DependencyBuilder, Context}
alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective

# Define known modules in analysis scope
known_modules = MapSet.new(["MyApp.Users", "MyApp.Accounts"])
context = Context.new(base_iri: "https://example.org/code#", known_modules: known_modules)

# Alias to internal module
alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
{alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)
# triples includes: {alias_iri, struct:isExternalModule, false}

# Alias to external module (Enum is not in known_modules)
alias_info = %AliasDirective{source: [:Enum], as: :E}
{alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)
# triples includes: {alias_iri, struct:isExternalModule, true}
```

### Use Directive with __using__ Linking
```elixir
alias ElixirOntologies.Extractors.Directive.Use.UseDirective

known_modules = MapSet.new(["MyApp.Behaviour"])
context = Context.new(base_iri: "https://example.org/code#", known_modules: known_modules)

use_info = %UseDirective{module: [:MyApp, :Behaviour]}
{use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)
# triples includes:
#   {use_iri, struct:isExternalModule, false}
#   {use_iri, struct:invokesUsing, ~I<.../MyApp.Behaviour/__using__/1>}
```

## Design Decisions

1. **Opted for `isExternalModule` instead of `referencesExternalModule`**: A boolean property is simpler and can be applied to any directive. The module reference already exists via `aliasedModule`, `importsModule`, etc.

2. **Linking disabled by default**: When `known_modules` is nil, no cross-module linking triples are generated. This maintains backwards compatibility.

3. **`invokesUsing` only for known modules**: We only link to `__using__/1` when the target module is in the analysis scope, as we can't verify the macro exists in external modules.

## Next Task

Phase 16 is now feature-complete. Remaining work:
- **Phase 16 Integration Tests** - Multi-module analysis, dependency graph completeness, SHACL validation
