# Phase 15.4.1: Macro Invocation Builder - Summary

## Overview

Implemented an RDF builder for macro invocations that generates triples representing macro calls in the ontology.

## Files Created

### lib/elixir_ontologies/builders/macro_builder.ex

New builder module that transforms `MacroInvocation` structs into RDF triples:

- **`build/2`**: Main entry point taking invocation and context
- **`build_macro_invocation/3`**: Extended version with options for index/module override
- Generates triples for:
  - `rdf:type structure:MacroInvocation`
  - `structure:macroName` - the macro name (e.g., "def", "if")
  - `structure:macroArity` - the macro arity
  - `structure:macroCategory` - category (definition, control_flow, etc.)
  - `structure:resolutionStatus` - resolution status (kernel, resolved, unresolved)
  - `structure:macroModule` - the macro's defining module (when resolved)
  - `structure:invokedAt` - link to source location

### test/elixir_ontologies/builders/macro_builder_test.exs

Comprehensive test coverage including:
- Basic Kernel macro invocation tests
- Control flow macro tests
- Library macro invocation tests
- Location tracking tests
- Edge cases (unresolved macros, quote category, nested modules)
- Options override tests

## Files Modified

### lib/elixir_ontologies/iri.ex

Added `for_macro_invocation/4` function to generate IRIs in the pattern:
```
{base}{module_name}/invocation/{macro_module}.{macro_name}/{index}
```

### priv/ontologies/elixir-structure.ttl

Added ontology support:
- `MacroInvocation` class (subclass of `core:CodeElement`)
- `macroCategory` datatype property
- `macroModule` datatype property
- `resolutionStatus` datatype property
- `invokesMacro` object property (linking invocation to definition)
- `invokedAt` object property (linking to source location)

## Design Decisions

1. **Module from metadata**: The module context comes from `invocation.metadata.module` (as a list of atoms like `[:MyApp, :Users]`), following the pattern used by FunctionBuilder.

2. **Index fallback chain**: Invocation index is determined by: options > metadata.invocation_index > location.start_line > 0

3. **Unresolved macros**: Macros with `nil` module use "unknown" in the IRI path

4. **Location as nested IRI**: Source locations get their own IRI pattern `{invocation_iri}/L{start_line}-{end_line}`

## Test Results

All tests pass:
- 3 doctests
- 9 unit tests
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes

## Next Steps

- 15.4.2: Attribute Value Builder
- 15.4.3: Quote Builder
