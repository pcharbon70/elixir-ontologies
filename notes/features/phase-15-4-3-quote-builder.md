# Phase 15.4.3: Quote Builder

## Overview

Create an RDF builder for quote blocks and unquote expressions that generates triples representing metaprogramming constructs in the ontology.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.4.3.1 Implement `build_quote_block/3` generating quote IRI
- 15.4.3.2 Generate `rdf:type structure:QuotedExpression` triple
- 15.4.3.3 Generate `structure:hasQuoteOption` for each option
- 15.4.3.4 Generate `structure:containsUnquote` linking to unquote expressions
- 15.4.3.5 Generate `structure:hasHygieneViolation` for var! usage
- 15.4.3.6 Add quote builder tests

## Input: Quote Extractor Structs

From `lib/elixir_ontologies/extractors/quote.ex`:

### QuotedExpression
```elixir
%QuotedExpression{
  body: Macro.t(),                    # The quoted AST
  options: QuoteOptions.t(),          # Quote options
  unquotes: [UnquoteExpression.t()],  # Unquote calls in this quote
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

### QuoteOptions
```elixir
%QuoteOptions{
  bind_quoted: keyword() | nil,       # [x: value] bindings
  context: module() | atom() | nil,   # :match, :guard, or Module
  location: :keep | nil,              # :keep to preserve line info
  unquote: boolean(),                 # Whether unquote enabled (default true)
  line: pos_integer() | nil,          # Override line
  file: String.t() | nil,             # Override file
  generated: boolean() | nil          # Compiler-generated marker
}
```

### UnquoteExpression
```elixir
%UnquoteExpression{
  kind: :unquote | :unquote_splicing,
  value: Macro.t(),                   # The unquoted expression
  depth: pos_integer(),               # Nesting level (1 = inside one quote)
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

### HygieneViolation
```elixir
%HygieneViolation{
  type: :var_bang | :macro_escape,
  variable: atom() | nil,             # Variable name for var!
  context: atom() | module() | nil,   # Context for var!/2
  expression: Macro.t() | nil,
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

## Existing Ontology

From `priv/ontologies/elixir-structure.ttl`:

Classes:
- `QuotedExpression` - An AST representation created with quote
- `UnquoteExpression` - An unquote() call
- `UnquoteSplicingExpression` - Subclass of UnquoteExpression
- `Binding` - A variable binding in quote with bind_quoted
- `Hygiene` - Macro hygiene context

Properties:
- `quotesExpression` - Links quote to its body (object property)
- `unquotesValue` - Links unquote to its value (object property)
- `quoteContext` - Context option as string (datatype property)

## Technical Design

### IRI Patterns

```
{base}{module_name}/quote/{index}
{base}{module_name}/quote/{index}/unquote/{unquote_index}
{base}{module_name}/quote/{index}/hygiene/{violation_index}
```

Example:
```
https://example.org/code#MyApp.Macros/quote/0
https://example.org/code#MyApp.Macros/quote/0/unquote/0
https://example.org/code#MyApp.Macros/quote/0/hygiene/0
```

### RDF Triples

For each quote block:

1. **Type triple**
   ```turtle
   <quote_iri> rdf:type structure:QuotedExpression .
   ```

2. **Quote options** (when present)
   ```turtle
   <quote_iri> structure:quoteContext "match" .
   <quote_iri> structure:hasBindQuoted true .
   <quote_iri> structure:locationKeep true .
   <quote_iri> structure:unquoteEnabled false .
   <quote_iri> structure:isGenerated true .
   ```

3. **Unquote links**
   ```turtle
   <quote_iri> structure:containsUnquote <unquote_iri> .
   ```

4. **Location** (when available)
   ```turtle
   <quote_iri> core:hasSourceLocation <location_iri> .
   ```

For each unquote:

1. **Type triple**
   ```turtle
   <unquote_iri> rdf:type structure:UnquoteExpression .
   # or for splicing:
   <unquote_iri> rdf:type structure:UnquoteSplicingExpression .
   ```

2. **Depth**
   ```turtle
   <unquote_iri> structure:unquoteDepth 1 .
   ```

3. **Location**
   ```turtle
   <unquote_iri> core:hasSourceLocation <location_iri> .
   ```

For hygiene violations:

1. **Type and details**
   ```turtle
   <violation_iri> rdf:type structure:Hygiene .
   <violation_iri> structure:violationType "var_bang" .
   <violation_iri> structure:unhygienicVariable "x" .
   <violation_iri> structure:hygieneContext "match" .
   ```

2. **Link from quote**
   ```turtle
   <quote_iri> structure:hasHygieneViolation <violation_iri> .
   ```

### Builder Interface

```elixir
@spec build(QuotedExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(quote_expr, context, opts \\ [])

@spec build_unquote(UnquoteExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_unquote(unquote_expr, context, opts \\ [])

@spec build_hygiene_violation(HygieneViolation.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_hygiene_violation(violation, context, opts \\ [])
```

## Implementation Plan

### Step 1: Add IRI Generation
- [ ] Add `for_quote/3` to IRI module
- [ ] Add `for_unquote/4` to IRI module
- [ ] Add `for_hygiene_violation/4` to IRI module

### Step 2: Create quote_builder.ex
- [ ] Create file with moduledoc
- [ ] Import helpers and namespaces
- [ ] Define build/3 main function

### Step 3: Implement Triple Generation
- [ ] Type triple for QuotedExpression
- [ ] Quote options triples (context, bind_quoted, location, etc.)
- [ ] Unquote building and linking
- [ ] Hygiene violation building and linking
- [ ] Location triples

### Step 4: Write Tests
- [ ] Test basic quote block build
- [ ] Test quote with options (context, bind_quoted, etc.)
- [ ] Test unquote RDF generation
- [ ] Test unquote_splicing type
- [ ] Test hygiene violation RDF
- [ ] Test nested quote handling

## Success Criteria

- [ ] QuoteBuilder module created
- [ ] build/3 returns IRI and triples
- [ ] All quote options handled
- [ ] Unquotes properly linked
- [ ] Hygiene violations captured
- [ ] Tests pass
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix credo --strict` passes
