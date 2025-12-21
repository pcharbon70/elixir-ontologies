# Phase 16.4.3: Use/Require Dependency Builder

## Overview

Generate RDF triples representing module dependencies from require and use directives. This creates detailed RDF representations for Require and Use instances with proper links to required/used modules and use options.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.4.3.1 Implement `build_require_dependency/3` generating require IRI
- 16.4.3.2 Generate `rdf:type structure:Require` triple
- 16.4.3.3 Implement `build_use_dependency/3` generating use IRI
- 16.4.3.4 Generate `rdf:type structure:Use` triple
- 16.4.3.5 Generate `structure:hasUseOption` for each option
- 16.4.3.6 Add require/use dependency tests

## Research Findings

### Existing Ontology Classes

From `priv/ontologies/elixir-structure.ttl`:

```turtle
:Require a owl:Class ;
    rdfs:label "Require"@en ;
    rdfs:comment """A require directive that ensures a module is compiled before
    the current module, enabling use of its macros."""@en ;
    rdfs:subClassOf core:CodeElement .

:Use a owl:Class ;
    rdfs:label "Use"@en ;
    rdfs:comment """A use directive that invokes the __using__/1 macro of a module,
    enabling code injection patterns common in frameworks."""@en ;
    rdfs:subClassOf core:CodeElement .

:requiresModule a owl:ObjectProperty ;
    rdfs:label "requires module"@en ;
    rdfs:domain :Module ;
    rdfs:range :Module .

:usesModule a owl:ObjectProperty ;
    rdfs:label "uses module"@en ;
    rdfs:domain :Module ;
    rdfs:range :Module .
```

### RequireDirective Struct

From `lib/elixir_ontologies/extractors/directive/require.ex`:

```elixir
@type t :: %__MODULE__{
        module: [atom()] | atom(),
        as: atom() | nil,
        location: SourceLocation.t() | nil,
        scope: :module | :function | :block | nil,
        metadata: map()
      }
```

### UseDirective Struct

From `lib/elixir_ontologies/extractors/directive/use.ex`:

```elixir
@type t :: %__MODULE__{
        module: [atom()] | atom(),
        options: use_options(),  # keyword() | term() | nil
        location: SourceLocation.t() | nil,
        scope: :module | :function | :block | nil,
        metadata: map()
      }
```

### UseOption Struct

```elixir
@type t :: %__MODULE__{
        key: atom() | nil,
        value: term(),
        value_type: value_type(),  # :atom | :string | :integer | :float | :boolean | :nil | :list | :tuple | :module | :dynamic
        dynamic: boolean(),
        raw_ast: Macro.t() | nil
      }
```

### IRI Functions Already Available

From `lib/elixir_ontologies/iri.ex`:

```elixir
def for_require(module_iri, index)  # {module}/require/{index}
def for_use(module_iri, index)      # {module}/use/{index}
```

## Technical Design

### New Ontology Properties Needed

Add to `priv/ontologies/elixir-structure.ttl`:

```turtle
# Require properties
:requireModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "require module"@en ;
    rdfs:comment "The module being required."@en ;
    rdfs:domain :Require ;
    rdfs:range :Module .

:hasRequire a owl:ObjectProperty ;
    rdfs:label "has require"@en ;
    rdfs:comment "Links a module to its require directives."@en ;
    rdfs:domain :Module ;
    rdfs:range :Require .

:requireAlias a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "require alias"@en ;
    rdfs:comment "The alias name for the required module (from as: option)."@en ;
    rdfs:domain :Require ;
    rdfs:range xsd:string .

# Use properties
:useModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "use module"@en ;
    rdfs:comment "The module being used (whose __using__/1 is invoked)."@en ;
    rdfs:domain :Use ;
    rdfs:range :Module .

:hasUse a owl:ObjectProperty ;
    rdfs:label "has use"@en ;
    rdfs:comment "Links a module to its use directives."@en ;
    rdfs:domain :Module ;
    rdfs:range :Use .

:hasUseOption a owl:ObjectProperty ;
    rdfs:label "has use option"@en ;
    rdfs:comment "Links a use directive to its option resources."@en ;
    rdfs:domain :Use ;
    rdfs:range :UseOption .

# UseOption class and properties
:UseOption a owl:Class ;
    rdfs:label "Use Option"@en ;
    rdfs:comment "An option passed to a use directive's __using__/1 callback."@en ;
    rdfs:subClassOf core:CodeElement .

:optionKey a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "option key"@en ;
    rdfs:comment "The key of a use option (nil for positional options)."@en ;
    rdfs:domain :UseOption ;
    rdfs:range xsd:string .

:optionValue a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "option value"@en ;
    rdfs:comment "The string representation of the option value."@en ;
    rdfs:domain :UseOption ;
    rdfs:range xsd:string .

:optionValueType a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "option value type"@en ;
    rdfs:comment "The type of the option value (atom, string, integer, etc.)."@en ;
    rdfs:domain :UseOption ;
    rdfs:range xsd:string .

:isDynamicOption a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "is dynamic option"@en ;
    rdfs:comment "True if the option value cannot be determined at analysis time."@en ;
    rdfs:domain :UseOption ;
    rdfs:range xsd:boolean .
```

### Triple Generation

#### For Require Directive:
1. `{require_iri, rdf:type, struct:Require}` - Type classification
2. `{require_iri, struct:requireModule, module_iri}` - Required module
3. `{module_iri, struct:hasRequire, require_iri}` - Module-to-require link
4. Optional: `{require_iri, struct:requireAlias, "alias_name"}` - If `as:` is present

#### For Use Directive:
1. `{use_iri, rdf:type, struct:Use}` - Type classification
2. `{use_iri, struct:useModule, module_iri}` - Used module
3. `{module_iri, struct:hasUse, use_iri}` - Module-to-use link
4. For each option: `{use_iri, struct:hasUseOption, option_iri}`

#### For UseOption:
1. `{option_iri, rdf:type, struct:UseOption}` - Type classification
2. `{option_iri, struct:optionKey, "key"}` - Option key (or nil for positional)
3. `{option_iri, struct:optionValue, "value_string"}` - Value as string
4. `{option_iri, struct:optionValueType, "type"}` - Value type
5. `{option_iri, struct:isDynamicOption, bool}` - Dynamic flag

## Implementation Plan

### Step 1: Add Ontology Properties
- [x] Add require properties (requireModule, hasRequire, requireAlias)
- [x] Add use properties (useModule, hasUse, hasUseOption)
- [x] Add UseOption class and properties

### Step 2: Implement Require Builder
- [x] Add `build_require_dependency/4` function
- [x] Add `build_require_dependencies/3` function
- [x] Handle optional `as:` alias

### Step 3: Implement Use Builder
- [x] Add `build_use_dependency/4` function
- [x] Add `build_use_dependencies/3` function
- [x] Add IRI generation for UseOption (`for_use_option/2`)
- [x] Handle keyword options
- [x] Handle positional options (non-keyword)
- [x] Handle dynamic option values

### Step 4: Write Tests
- [x] Test require IRI generation
- [x] Test require type triple
- [x] Test requireModule linking
- [x] Test hasRequire linking
- [x] Test require with `as:` option
- [x] Test use IRI generation
- [x] Test use type triple
- [x] Test useModule linking
- [x] Test hasUse linking
- [x] Test use option generation
- [x] Test multiple options
- [x] Test dynamic options
- [x] Test positional (non-keyword) options
- [x] Test multiple requires/uses

## Success Criteria

- [x] All ontology properties added
- [x] `build_require_dependency/4` generates correct triples
- [x] `build_use_dependency/4` generates correct triples
- [x] Use options correctly represented
- [x] Tests pass (12 doctests, 74 tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only refactoring suggestions)
