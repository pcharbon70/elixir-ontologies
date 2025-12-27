# Phase 16.4.1: Dependency Graph Builder

## Overview

Generate RDF triples representing module dependencies from alias directives. This creates detailed RDF representations for ModuleAlias instances with proper links to source and aliased modules.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.4.1.1 Create `lib/elixir_ontologies/builders/dependency_builder.ex`
- 16.4.1.2 Implement `build_alias_dependency/3` generating alias IRI and triples
- 16.4.1.3 Generate `rdf:type structure:ModuleAlias` triple
- 16.4.1.4 Generate `structure:aliasesModule` linking to aliased module
- 16.4.1.5 Generate `structure:aliasedAs` with the short name
- 16.4.1.6 Add alias dependency tests

## Research Findings

### Existing Ontology Classes and Properties

From `priv/ontologies/elixir-structure.ttl`:

```turtle
:ModuleAlias a owl:Class ;
    rdfs:label "Module Alias"@en ;
    rdfs:comment "An alias directive that creates a shortened reference to a module" ;
    rdfs:subClassOf core:CodeElement .

:aliasesModule a owl:ObjectProperty ;
    rdfs:label "aliases module"@en ;
    rdfs:domain :Module ;
    rdfs:range :Module .

:aliasName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "alias name"@en ;
    rdfs:domain :ModuleAlias ;
    rdfs:range xsd:string .
```

### Current ModuleBuilder Pattern

The existing `ModuleBuilder` (line 214-221) creates simple triples:
```elixir
defp build_alias_triples(module_iri, aliases, context) do
  Enum.flat_map(aliases, fn alias_info ->
    aliased_module = module_name_string(alias_info.module)
    aliased_iri = IRI.for_module(context.base_iri, aliased_module)
    [Helpers.object_property(module_iri, Structure.aliasesModule(), aliased_iri)]
  end)
end
```

### New DependencyBuilder Pattern

Create dedicated dependency instances as first-class RDF resources:

```turtle
# Current simple pattern (from ModuleBuilder):
:MyApp aliasesModule :MyApp.Users .

# New detailed pattern (from DependencyBuilder):
:MyApp_alias_0 a struct:ModuleAlias ;
    struct:aliasName "Users" ;
    struct:aliasedModule :MyApp.Users ;
    struct:inModule :MyApp .
```

## Technical Design

### IRI Generation

Need to add IRI generation for dependencies. Pattern: `{base}#{module}_alias_{index}`

```elixir
# Example IRIs
"https://example.org/code#MyApp_alias_0"       # First alias
"https://example.org/code#MyApp_alias_1"       # Second alias
```

### Build Function Signatures

```elixir
@spec build_alias_dependency(AliasDirective.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}

@spec build_alias_dependencies(module_iri, aliases, context) :: [RDF.Triple.t()]
```

### Triple Generation

For each alias, generate:
1. `{alias_iri, rdf:type, Structure.ModuleAlias}` - Type classification
2. `{alias_iri, Structure.aliasName(), "ShortName"}` - Alias short name
3. `{alias_iri, Structure.aliasedModule(), target_module_iri}` - Target module
4. `{module_iri, Structure.hasAlias(), alias_iri}` - Module-to-alias link

## Implementation Plan

### Step 1: Add IRI Generation
- [x] Add `for_alias/3` function to IRI module
- [x] Add `for_import/3` function to IRI module (for future)
- [x] Add `for_require/3` function to IRI module (for future)
- [x] Add `for_use/3` function to IRI module (for future)

### Step 2: Create DependencyBuilder Module
- [x] Create `lib/elixir_ontologies/builders/dependency_builder.ex`
- [x] Add module documentation
- [x] Implement `build_alias_dependency/4`
- [x] Implement `build_alias_dependencies/3`

### Step 3: Write Tests
- [x] Test alias IRI generation
- [x] Test type triple generation
- [x] Test aliasName property
- [x] Test aliasedModule linking
- [x] Test module-to-alias linking
- [x] Test multiple aliases

## Success Criteria

- [x] DependencyBuilder module created
- [x] `build_alias_dependency/4` generates correct triples
- [x] IRI generation for aliases works
- [x] Tests pass (3 doctests, 14 tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only refactoring suggestions)
