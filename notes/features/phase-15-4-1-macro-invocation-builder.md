# Phase 15.4.1: Macro Invocation Builder

## Overview

Create an RDF builder for macro invocations that generates triples representing macro calls in the ontology.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.4.1.1 Create `lib/elixir_ontologies/builders/macro_builder.ex`
- 15.4.1.2 Implement `build_macro_invocation/3` generating invocation IRI
- 15.4.1.3 Generate `rdf:type structure:MacroInvocation` triple
- 15.4.1.4 Generate `structure:invokesMacro` linking to macro definition
- 15.4.1.5 Generate `structure:invokedAt` with source location
- 15.4.1.6 Add macro invocation builder tests

## Input: MacroInvocation Struct

From `lib/elixir_ontologies/extractors/macro_invocation.ex`:

```elixir
@type t :: %__MODULE__{
  macro_module: module() | nil,      # e.g., Kernel, Logger
  macro_name: atom(),                # e.g., :def, :if, :debug
  arity: non_neg_integer(),          # e.g., 2
  arguments: [Macro.t()],            # AST of arguments
  category: category(),              # :definition, :control_flow, etc.
  resolution_status: resolution_status(),  # :resolved, :unresolved, :kernel
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

## Technical Design

### IRI Pattern

```
{base}{module_name}/invocation/{macro_module}.{macro_name}/{line}
```

Example:
```
https://example.org/code#MyApp.Users/invocation/Kernel.def/15
```

For unresolved macros:
```
https://example.org/code#MyApp.Users/invocation/unknown.debug/42
```

### RDF Triples

For a macro invocation, generate:

1. **Type triple**
   ```turtle
   <invocation_iri> rdf:type structure:MacroInvocation .
   ```

2. **Macro name**
   ```turtle
   <invocation_iri> structure:macroName "def" .
   ```

3. **Macro module** (if resolved)
   ```turtle
   <invocation_iri> structure:invokesMacro <macro_definition_iri> .
   ```
   or unresolved:
   ```turtle
   <invocation_iri> structure:macroModule "Logger" .
   ```

4. **Arity**
   ```turtle
   <invocation_iri> structure:macroArity 2 .
   ```

5. **Category**
   ```turtle
   <invocation_iri> structure:macroCategory "definition" .
   ```

6. **Location**
   ```turtle
   <invocation_iri> structure:invokedAt <location_iri> .
   ```

7. **Resolution status**
   ```turtle
   <invocation_iri> structure:resolutionStatus "resolved" .
   ```

### Builder Interface

```elixir
@spec build(MacroInvocation.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(invocation, context)

@spec build_macro_invocation(MacroInvocation.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_macro_invocation(invocation, context, opts \\ [])
```

## Implementation Plan

### Step 1: Create macro_builder.ex
- [ ] Create file with moduledoc
- [ ] Define build/2 main function
- [ ] Import helpers and namespaces

### Step 2: Implement IRI Generation
- [ ] Add for_macro_invocation to IRI module
- [ ] Handle module + name + line pattern
- [ ] Handle unresolved macros

### Step 3: Implement Triple Generation
- [ ] Type triple (MacroInvocation)
- [ ] Macro name triple
- [ ] Macro module/invokesMacro triple
- [ ] Arity triple
- [ ] Category triple
- [ ] Location triple
- [ ] Resolution status triple

### Step 4: Write Tests
- [ ] Test basic invocation build
- [ ] Test with location
- [ ] Test unresolved macros
- [ ] Test different categories

## Success Criteria

- [ ] MacroBuilder module created
- [ ] build/2 returns IRI and triples
- [ ] All required triples generated
- [ ] Tests pass
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix credo --strict` passes
