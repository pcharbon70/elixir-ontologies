# Phase 15.2.2: Documentation Attribute Values

## Problem Statement

The current `Attribute` extractor captures documentation attributes (@doc, @moduledoc, @typedoc) but doesn't provide structured access to documentation content. We need to:
- Extract the actual text content from documentation attributes
- Handle different documentation formats (strings, heredocs, sigils)
- Detect hidden documentation (`@doc false`)
- Provide typed access to documentation metadata

**Impact**: Structured documentation extraction enables:
- Building documentation browsers and analyzers
- Extracting docstrings for RDF representation
- Identifying undocumented or hidden functions
- Cross-referencing documentation with code elements

## Solution Overview

Extend the `Attribute` module with documentation-specific extraction functions:
1. Add `extract_doc_content/1` function for documentation text extraction
2. Handle heredoc strings (`"""..."""`) and sigil strings (`~S`, `~s`)
3. Create `DocContent` struct for structured documentation data
4. Add helpers for detecting hidden docs and extracting doc metadata

## Technical Details

### Files to Modify
- **Modify**: `lib/elixir_ontologies/extractors/attribute.ex`
- **Modify**: `test/elixir_ontologies/extractors/attribute_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### DocContent Struct

```elixir
defmodule ElixirOntologies.Extractors.Attribute.DocContent do
  defstruct [
    :content,       # The documentation text (string)
    :format,        # :string | :heredoc | :sigil | :false | :nil
    :sigil_type,    # For sigils: :S, :s, etc.
    hidden: false   # Whether doc is hidden (@doc false)
  ]
end
```

### Documentation Formats

1. **Plain string**: `@doc "Simple documentation"`
2. **Heredoc**: `@doc """ Multi-line docs """`
3. **Sigil S**: `@doc ~S(docs with \n literal)` - no interpolation
4. **Sigil s**: `@doc ~s(docs with #{interpolation})`
5. **Hidden**: `@doc false`
6. **Nil/Missing**: No documentation

### Design Decisions

- `extract_doc_content/1` takes an extracted Attribute struct
- Returns `DocContent` with parsed content and format
- Hidden docs (`@doc false`) return `DocContent{hidden: true, content: nil}`
- Preserves original format information for accurate representation

## Implementation Plan

### Step 1: Define DocContent Struct
- [x] Create `DocContent` nested module inside Attribute
- [x] Add typespec for format types
- [x] Add constructor function `new/1`

### Step 2: Extract Documentation Content
- [x] Implement `extract_doc_content/1` for Attribute structs
- [x] Handle plain string documentation
- [x] Handle heredoc documentation
- [x] Handle sigil documentation (S, s)
- [x] Handle `@doc false`

### Step 3: Documentation Helpers
- [x] Add `doc_content/1` accessor
- [x] Add `doc_hidden?/1` predicate
- [x] Add `has_doc?/1` predicate
- [x] Add `doc_format/1` accessor

### Step 4: Write Tests
- [x] Test DocContent struct creation
- [x] Test plain string doc extraction
- [x] Test heredoc doc extraction
- [x] Test sigil doc extraction
- [x] Test @doc false detection
- [x] Test @moduledoc extraction
- [x] Test @typedoc extraction

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass
- [x] Documentation extraction works for all formats

## Notes

- Heredocs in AST are represented as plain strings after parsing
- Sigils may have modifiers that affect interpretation
- Some sigils like ~S preserve literal backslashes
- The AST doesn't preserve the original quote style (single vs double)
