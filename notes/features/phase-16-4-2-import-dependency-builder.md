# Phase 16.4.2: Import Dependency Builder

## Overview

Generate RDF triples representing module dependencies from import directives. This creates detailed RDF representations for Import instances with proper links to imported modules and function specifications.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.4.2.1 Implement `build_import_dependency/3` generating import IRI
- 16.4.2.2 Generate `rdf:type structure:Import` triple
- 16.4.2.3 Generate `structure:importsModule` linking to imported module
- 16.4.2.4 Generate `structure:importsFunction` for each imported function
- 16.4.2.5 Generate `structure:excludesFunction` for excluded functions
- 16.4.2.6 Add import dependency tests

## Research Findings

### Existing Ontology Classes and Properties

From `priv/ontologies/elixir-structure.ttl`:

```turtle
:Import a owl:Class ;
    rdfs:label "Import"@en ;
    rdfs:comment """An import directive that brings functions from another module
    into the local namespace. Can be scoped with :only or :except."""@en ;
    rdfs:subClassOf core:CodeElement .

:importsFrom a owl:ObjectProperty ;
    rdfs:label "imports from"@en ;
    rdfs:domain :Module ;
    rdfs:range :Module .
```

### ImportDirective Struct

From `lib/elixir_ontologies/extractors/directive/import.ex`:

```elixir
@type t :: %__MODULE__{
        module: [atom()] | atom(),
        only: import_selector(),  # list of {name, arity}, :functions, :macros, :sigils, or nil
        except: [{atom(), non_neg_integer()}] | nil,
        location: SourceLocation.t() | nil,
        scope: :module | :function | :block | nil,
        metadata: map()
      }
```

### Pattern from Alias Builder

Following the pattern from `build_alias_dependency/4`:

```elixir
def build_alias_dependency(alias_info, module_iri, context, index) do
  alias_iri = IRI.for_alias(module_iri, index)
  # ... build triples
  {alias_iri, triples}
end
```

## Technical Design

### New Ontology Properties Needed

Need to add to `priv/ontologies/elixir-structure.ttl`:

```turtle
:importsModule a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "imports module"@en ;
    rdfs:comment "The module from which functions are imported"@en ;
    rdfs:domain :Import ;
    rdfs:range :Module .

:hasImport a owl:ObjectProperty ;
    rdfs:label "has import"@en ;
    rdfs:comment "Links a module to an import directive it contains"@en ;
    rdfs:domain :Module ;
    rdfs:range :Import .

:importsFunction a owl:ObjectProperty ;
    rdfs:label "imports function"@en ;
    rdfs:comment "A function explicitly imported via only: option"@en ;
    rdfs:domain :Import ;
    rdfs:range :Function .

:excludesFunction a owl:ObjectProperty ;
    rdfs:label "excludes function"@en ;
    rdfs:comment "A function explicitly excluded via except: option"@en ;
    rdfs:domain :Import ;
    rdfs:range :Function .

:importType a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "import type"@en ;
    rdfs:comment "Type-based import selector: 'functions', 'macros', or 'sigils'"@en ;
    rdfs:domain :Import ;
    rdfs:range xsd:string .

:isFullImport a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "is full import"@en ;
    rdfs:comment "True if this import has no only/except restrictions"@en ;
    rdfs:domain :Import ;
    rdfs:range xsd:boolean .
```

### IRI Generation

Already have `IRI.for_import/2` from Phase 16.4.1:
```elixir
def for_import(module_iri, index) when is_integer(index) and index >= 0 do
  append_to_iri(module_iri, "import/#{index}")
end
```

### Triple Generation

For each import directive, generate:
1. `{import_iri, rdf:type, Structure.Import}` - Type classification
2. `{import_iri, Structure.importsModule(), target_module_iri}` - Target module
3. `{module_iri, Structure.hasImport(), import_iri}` - Module-to-import link
4. `{import_iri, Structure.isFullImport(), true/false}` - Full import flag

For selective imports (`only:` with function list):
5. `{import_iri, Structure.importsFunction(), function_iri}` for each function

For exclusion imports (`except:`):
6. `{import_iri, Structure.excludesFunction(), function_iri}` for each excluded function

For type-based imports (`only: :functions`):
7. `{import_iri, Structure.importType(), "functions"}` etc.

### Function IRI Pattern

For imported functions, use pattern: `{base}#{ImportedModule}.{function_name}/{arity}`

Example: `https://example.org/code#Enum.map/2`

## Implementation Plan

### Step 1: Add Ontology Properties
- [x] Add `importsModule` property
- [x] Add `hasImport` property
- [x] Add `importsFunction` property
- [x] Add `excludesFunction` property
- [x] Add `importType` property
- [x] Add `isFullImport` property

### Step 2: Implement Builder Functions
- [x] Implement `build_import_dependency/4`
- [x] Implement `build_import_dependencies/3`
- [x] Handle full imports
- [x] Handle selective imports (only:)
- [x] Handle exclusion imports (except:)
- [x] Handle type-based imports

### Step 3: Write Tests
- [x] Test import IRI generation
- [x] Test type triple generation
- [x] Test importsModule linking
- [x] Test hasImport linking
- [x] Test full import flag
- [x] Test selective import function triples
- [x] Test exclusion import function triples
- [x] Test type-based import triples
- [x] Test multiple imports

## Example Output

For `import Enum, only: [map: 2, filter: 2]`:

```turtle
ex:MyApp/import/0 a struct:Import ;
    struct:importsModule ex:Enum ;
    struct:isFullImport false ;
    struct:importsFunction ex:Enum.map/2 ;
    struct:importsFunction ex:Enum.filter/2 .

ex:MyApp struct:hasImport ex:MyApp/import/0 .
```

For `import Kernel, only: :macros`:

```turtle
ex:MyApp/import/0 a struct:Import ;
    struct:importsModule ex:Kernel ;
    struct:isFullImport false ;
    struct:importType "macros" .

ex:MyApp struct:hasImport ex:MyApp/import/0 .
```

## Success Criteria

- [x] All ontology properties added
- [x] `build_import_dependency/4` generates correct triples
- [x] All import types handled (full, selective, exclusion, type-based)
- [x] Tests pass (6 doctests, 38 tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only refactoring suggestions)
