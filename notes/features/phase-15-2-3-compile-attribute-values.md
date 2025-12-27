# Phase 15.2.3: Compile Attribute Values

## Problem Statement

The `Attribute` extractor handles compile-time attributes but doesn't provide structured extraction of their values. We need to:
- Extract @compile directive values (inline, no_warn_undefined, etc.)
- Extract @on_definition callback specifications
- Extract @before_compile and @after_compile callback specifications
- Extract @external_resource file paths

**Impact**: Structured compile attribute extraction enables:
- Understanding module compilation behavior
- Tracking compile-time dependencies
- Identifying hook functions and callbacks
- Building complete module metadata for RDF

## Solution Overview

Add specialized extraction functions for compile-time attributes:
1. `extract_compile_options/1` - Parse @compile directive values
2. `extract_callback_spec/1` - Parse callback module/function specifications
3. `extract_external_resources/1` - Collect @external_resource paths from module body
4. Create `CompileOptions` and `CallbackSpec` structs for structured data

## Technical Details

### Files to Modify
- **Modify**: `lib/elixir_ontologies/extractors/attribute.ex`
- **Modify**: `test/elixir_ontologies/extractors/attribute_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### CompileOptions Struct

```elixir
defmodule ElixirOntologies.Extractors.Attribute.CompileOptions do
  defstruct [
    :inline,           # List of {name, arity} or true
    :no_warn_undefined, # List of modules/MFAs or true
    :warnings_as_errors, # boolean
    :debug_info,       # boolean
    raw_options: []    # Original options list
  ]
end
```

### CallbackSpec Struct

```elixir
defmodule ElixirOntologies.Extractors.Attribute.CallbackSpec do
  defstruct [
    :module,      # Target module
    :function,    # Function name (atom)
    :arity        # Function arity (if known)
  ]
end
```

### @compile Directive Values

Common @compile options:
- `inline: [{:foo, 1}, {:bar, 2}]` - Functions to inline
- `inline: true` - Inline all functions
- `no_warn_undefined: [SomeModule]` - Suppress undefined warnings
- `{:no_warn_undefined, {Mod, :fun, 2}}` - Specific MFA
- `:warnings_as_errors` - Treat warnings as errors
- `:debug_info` - Include debug info

### Design Decisions

- CompileOptions normalizes various @compile formats
- CallbackSpec works for @on_definition, @before_compile, @after_compile
- Functions return nil for non-applicable attributes
- Preserve raw options for complete representation

## Implementation Plan

### Step 1: Define CompileOptions Struct
- [x] Create `CompileOptions` nested module
- [x] Add fields for common compile options
- [x] Add constructor and parser

### Step 2: Define CallbackSpec Struct
- [x] Create `CallbackSpec` nested module
- [x] Handle module, function, arity extraction
- [x] Parse various callback formats

### Step 3: Extract @compile Values
- [x] Implement `extract_compile_options/1`
- [x] Handle atom options (`:debug_info`)
- [x] Handle keyword options (`inline: [...]`)
- [x] Handle list of options

### Step 4: Extract Callback Specs
- [x] Implement `extract_callback_spec/1`
- [x] Handle `{Module, :function}` format
- [x] Handle `Module` only format
- [x] Handle `__MODULE__` references

### Step 5: Extract @external_resource
- [x] Implement `extract_external_resources/1`
- [x] Collect all @external_resource from module body
- [x] Return list of file paths

### Step 6: Write Tests
- [x] Test CompileOptions struct
- [x] Test @compile with atom options
- [x] Test @compile with keyword options
- [x] Test CallbackSpec struct
- [x] Test @on_definition extraction
- [x] Test @before_compile extraction
- [x] Test @after_compile extraction
- [x] Test @external_resource extraction

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass
- [x] Compile attribute extraction works for all formats

## Notes

- @compile can take atoms, keyword lists, or lists of options
- Callback specs can reference __MODULE__ which needs special handling
- @external_resource values are strings (file paths)
- Some options like :inline can be boolean or list
