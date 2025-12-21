# Phase 16.4.3: Use/Require Dependency Builder - Summary

## Completed

Implemented RDF triple generation for require and use directives, creating first-class Require and Use resources in the RDF graph with proper links to required/used modules and comprehensive use option representation.

## Changes Made

### Ontology Extensions

Added to `priv/ontologies/elixir-structure.ttl`:

```turtle
# Require properties
:requireModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :Require ;
    rdfs:range :Module .

:hasRequire a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Require .

:requireAlias a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Require ;
    rdfs:range xsd:string .

# Use properties
:useModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :Use ;
    rdfs:range :Module .

:hasUse a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Use .

:hasUseOption a owl:ObjectProperty ;
    rdfs:domain :Use ;
    rdfs:range :UseOption .

# UseOption class and properties
:UseOption a owl:Class ;
    rdfs:subClassOf core:CodeElement .

:optionKey a owl:DatatypeProperty, owl:FunctionalProperty .
:optionValue a owl:DatatypeProperty, owl:FunctionalProperty .
:optionValueType a owl:DatatypeProperty, owl:FunctionalProperty .
:isDynamicOption a owl:DatatypeProperty, owl:FunctionalProperty .
```

### IRI Functions

Added to `lib/elixir_ontologies/iri.ex`:

```elixir
def for_use_option(use_iri, index)  # {use_iri}/option/{index}
```

### DependencyBuilder Functions

Extended `lib/elixir_ontologies/builders/dependency_builder.ex`:

```elixir
# Require functions
build_require_dependency(require_info, module_iri, context, index)
build_require_dependencies(requires, module_iri, context)

# Use functions
build_use_dependency(use_info, module_iri, context, index)
build_use_dependencies(uses, module_iri, context)
```

### Generated Triples

#### For Require Directive:
1. `{require_iri, rdf:type, struct:Require}`
2. `{require_iri, struct:requireModule, target_module_iri}`
3. `{module_iri, struct:hasRequire, require_iri}`
4. Optional: `{require_iri, struct:requireAlias, "alias_name"}`

#### For Use Directive:
1. `{use_iri, rdf:type, struct:Use}`
2. `{use_iri, struct:useModule, target_module_iri}`
3. `{module_iri, struct:hasUse, use_iri}`
4. For each option: `{use_iri, struct:hasUseOption, option_iri}`

#### For UseOption:
1. `{option_iri, rdf:type, struct:UseOption}`
2. `{option_iri, struct:optionKey, "key"}` (empty for positional)
3. `{option_iri, struct:optionValue, "value_string"}`
4. `{option_iri, struct:optionValueType, "type"}`
5. `{option_iri, struct:isDynamicOption, boolean}`

### Supported Option Value Types

- `atom` - Elixir atoms (e.g., `:temporary`)
- `string` - Strings (e.g., `"my_server"`)
- `integer` - Integers (e.g., `5000`)
- `float` - Floats (e.g., `1.5`)
- `boolean` - Booleans (`true`/`false`)
- `nil` - Nil value
- `list` - Lists (serialized via `inspect/1`)
- `tuple` - Tuples (serialized via `inspect/1`)
- `dynamic` - Non-literal values marked as dynamic

## Files Modified

- `priv/ontologies/elixir-structure.ttl` - Added 11 require/use-related properties
- `lib/elixir_ontologies/iri.ex` - Added `for_use_option/2`
- `lib/elixir_ontologies/builders/dependency_builder.ex` - Added require/use builders
- `test/elixir_ontologies/builders/dependency_builder_test.exs` - Added 36 tests
- `notes/planning/extractors/phase-16.md` - Marked 16.4.3 complete
- `notes/features/phase-16-4-3-use-require-dependency-builder.md` - Updated

## Test Results

- 12 doctests, 74 tests, 0 failures
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes (only refactoring suggestions)

## Usage Examples

### Require
```elixir
alias ElixirOntologies.Builders.{DependencyBuilder, Context}
alias ElixirOntologies.Extractors.Directive.Require.RequireDirective

require_info = %RequireDirective{module: [:Logger], as: :L}
module_iri = RDF.iri("https://example.org/code#MyApp")
context = Context.new(base_iri: "https://example.org/code#")

{require_iri, triples} = DependencyBuilder.build_require_dependency(
  require_info, module_iri, context, 0
)
# require_iri => ~I<https://example.org/code#MyApp/require/0>
```

### Use
```elixir
alias ElixirOntologies.Builders.{DependencyBuilder, Context}
alias ElixirOntologies.Extractors.Directive.Use.UseDirective

use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
module_iri = RDF.iri("https://example.org/code#MyApp")
context = Context.new(base_iri: "https://example.org/code#")

{use_iri, triples} = DependencyBuilder.build_use_dependency(
  use_info, module_iri, context, 0
)
# use_iri => ~I<https://example.org/code#MyApp/use/0>
# Option at: ~I<https://example.org/code#MyApp/use/0/option/0>
```

## Next Task

**16.4.4 Cross-Module Linking** - Link directives to actual module definitions when available in analysis scope.
