# Phase 15.4.2: Attribute Value Builder

## Overview

Create an RDF builder for module attribute values that generates triples representing attribute assignments in the ontology.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.4.2.1 Update or create attribute builder for values
- 15.4.2.2 Generate `structure:hasAttributeValue` with literal values
- 15.4.2.3 Generate `structure:isAccumulating` boolean flag
- 15.4.2.4 Generate `structure:hasDocumentation` for doc attributes
- 15.4.2.5 Handle complex values (serialize to RDF-compatible format)
- 15.4.2.6 Add attribute value builder tests

## Input: Attribute Struct

From `lib/elixir_ontologies/extractors/attribute.ex`:

```elixir
@type t :: %__MODULE__{
  type: attribute_type(),        # :doc_attribute, :deprecated_attribute, etc.
  name: atom(),                  # :doc, :deprecated, :custom, etc.
  value: term(),                 # The raw attribute value
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

Also uses:
- `AttributeValue` - typed value with type classification
- `DocContent` - documentation content with format info
- `CompileOptions` - parsed @compile options
- `CallbackSpec` - @before_compile/@after_compile spec

## Existing Ontology

From `priv/ontologies/elixir-structure.ttl`:

Classes:
- `ModuleAttribute` - base class
- `DocAttribute` - @moduledoc, @doc, @typedoc (subclass)
- `DeprecatedAttribute` - @deprecated
- `SinceAttribute` - @since
- `ExternalResourceAttribute` - @external_resource
- `CompileAttribute` - @compile
- `AccumulatingAttribute` - attributes with accumulate: true
- And more...

Properties:
- `attributeName` - xsd:string
- `attributeValue` - xsd:string
- `isAccumulating` - xsd:boolean
- `docstring` - xsd:string (for DocAttribute)
- `isDocFalse` - xsd:boolean
- `deprecationMessage` - xsd:string
- `sinceVersion` - xsd:string

## Technical Design

### IRI Pattern

```
{base}{module_name}/attribute/{attr_name}
{base}{module_name}/attribute/{attr_name}/{index}  # for accumulated
```

Example:
```
https://example.org/code#MyApp.Users/attribute/moduledoc
https://example.org/code#MyApp.Users/attribute/my_attr/0
```

### RDF Triples

For each attribute, generate:

1. **Type triple** (based on attribute type)
   ```turtle
   <attr_iri> rdf:type structure:DocAttribute .
   ```

2. **Attribute name**
   ```turtle
   <attr_iri> structure:attributeName "doc" .
   ```

3. **Attribute value** (serialized)
   ```turtle
   <attr_iri> structure:attributeValue "42" .
   ```

4. **Accumulating flag** (when applicable)
   ```turtle
   <attr_iri> structure:isAccumulating true .
   ```

5. **Documentation specific** (for doc attributes)
   ```turtle
   <attr_iri> structure:docstring "The actual doc text" .
   <attr_iri> structure:isDocFalse true .  # when @doc false
   ```

6. **Deprecation specific**
   ```turtle
   <attr_iri> structure:deprecationMessage "Use new_func/1" .
   ```

7. **Since specific**
   ```turtle
   <attr_iri> structure:sinceVersion "1.2.0" .
   ```

8. **Location** (when available)
   ```turtle
   <attr_iri> structure:definedAt <location_iri> .
   ```

### Value Serialization

For complex values, serialize to JSON or inspect format:
- Literals: direct string/number
- Lists/Maps: JSON string
- AST: inspect format with marker

### Builder Interface

```elixir
@spec build(Attribute.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(attribute, context)

@spec build_attribute(Attribute.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_attribute(attribute, context, opts \\ [])
```

## Implementation Plan

### Step 1: Add IRI Generation
- [x] Add `for_attribute/4` to IRI module
- [x] Handle indexed attributes for accumulating

### Step 2: Create attribute_builder.ex
- [x] Create file with moduledoc
- [x] Define build/2 main function
- [x] Import helpers and namespaces

### Step 3: Implement Type Classification
- [x] Map attribute types to ontology classes
- [x] Handle DocAttribute subtypes

### Step 4: Implement Triple Generation
- [x] Type triple
- [x] Attribute name triple
- [x] Attribute value triple (with serialization)
- [x] Accumulating flag triple
- [x] Documentation-specific triples
- [x] Deprecation/since triples
- [x] Location triples

### Step 5: Write Tests
- [ ] Test basic attribute build
- [ ] Test doc attribute with content
- [ ] Test doc false handling
- [ ] Test deprecated attribute
- [ ] Test since attribute
- [ ] Test accumulating attribute
- [ ] Test complex value serialization

## Success Criteria

- [ ] AttributeBuilder module created
- [ ] build/2 returns IRI and triples
- [ ] All attribute types handled
- [ ] Value serialization works
- [ ] Tests pass
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix credo --strict` passes
