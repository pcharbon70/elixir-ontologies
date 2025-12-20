# Phase 15: Metaprogramming Support

This phase implements comprehensive extraction and building for Elixir's metaprogramming capabilities. While the Macro extractor exists, it does not capture macro invocations, quote/unquote semantics, or the compile-time code generation patterns. This phase bridges that gap to fully represent metaprogramming in the RDF graph.

## 15.1 Macro Invocation Tracking

This section implements extraction of macro invocations (calls to macros from other modules), distinguishing them from regular function calls and tracking their expansion sites.

### 15.1.1 Macro Call Detection
- [x] **Task 15.1.1 Complete**

Detect and extract macro invocations in module bodies, identifying calls to known macros from standard library and external modules.

- [x] 15.1.1.1 Create `lib/elixir_ontologies/extractors/macro_invocation.ex`
- [x] 15.1.1.2 Define `%MacroInvocation{}` struct with fields: macro_module, macro_name, arity, arguments, location
- [x] 15.1.1.3 Implement detection of standard library macros (defmodule, def, defmacro, etc.)
- [x] 15.1.1.4 Implement detection of Kernel macros (if, unless, case, cond, with, for, etc.)
- [x] 15.1.1.5 Track call site location for each macro invocation
- [x] 15.1.1.6 Add macro invocation detection tests

### 15.1.2 Custom Macro Invocation
- [x] **Task 15.1.2 Complete**

Track invocations of user-defined macros, linking calls to their definitions when available.

- [x] 15.1.2.1 Implement `extract_custom_macro_call/2` detecting non-Kernel macro calls
- [x] 15.1.2.2 Track imported macros via `import Module, only: [macro: arity]`
- [x] 15.1.2.3 Track required macros via `require Module`
- [x] 15.1.2.4 Attempt to link invocations to definitions within same analysis scope
- [x] 15.1.2.5 Mark unresolved macro calls for cross-module analysis
- [x] 15.1.2.6 Add custom macro invocation tests

### 15.1.3 Macro Expansion Context
- [x] **Task 15.1.3 Complete**

Capture the expansion context of macro invocations including the caller environment.

- [x] 15.1.3.1 Extract `__CALLER__` context information when available
- [x] 15.1.3.2 Track expansion module (where macro expands)
- [x] 15.1.3.3 Track expansion file and line
- [x] 15.1.3.4 Create `%MacroContext{module: ..., file: ..., line: ...}` struct
- [x] 15.1.3.5 Associate context with macro invocations
- [x] 15.1.3.6 Add macro context tests

**Section 15.1 Unit Tests:**
- [x] Test detection of `def`/`defp` as macro invocations
- [x] Test detection of `if`/`unless`/`case` as macro invocations
- [x] Test custom macro invocation detection
- [x] Test imported macro tracking
- [x] Test required macro tracking
- [x] Test macro call site location extraction
- [x] Test expansion context capture
- [x] Test unresolved macro call handling

## 15.2 Module Attribute Values

This section enhances attribute extraction to capture the actual values assigned to module attributes, not just their existence.

### 15.2.1 Compile-time Value Extraction
- [x] **Task 15.2.1 Complete**

Extract the compile-time values assigned to module attributes, handling literals and simple expressions.

- [x] 15.2.1.1 Update `lib/elixir_ontologies/extractors/attribute.ex` for value extraction
- [x] 15.2.1.2 Extract literal values (atoms, integers, strings, lists, maps)
- [x] 15.2.1.3 Handle keyword list values for complex attributes
- [x] 15.2.1.4 Track attribute accumulation (`@attr` vs `Module.register_attribute(:attr, accumulate: true)`)
- [x] 15.2.1.5 Create `%AttributeValue{type: ..., value: ..., accumulated: boolean()}` struct
- [x] 15.2.1.6 Add attribute value extraction tests

### 15.2.2 Documentation Attribute Values
- [x] **Task 15.2.2 Complete**

Extract documentation content from @moduledoc, @doc, and @typedoc attributes.

- [x] 15.2.2.1 Implement `extract_doc_content/1` for @moduledoc values
- [x] 15.2.2.2 Implement `extract_doc_content/1` for @doc values
- [x] 15.2.2.3 Implement `extract_doc_content/1` for @typedoc values
- [x] 15.2.2.4 Handle heredoc strings and sigils
- [x] 15.2.2.5 Extract @doc false markers
- [x] 15.2.2.6 Add documentation value tests

### 15.2.3 Compile Attribute Values
- [x] **Task 15.2.3 Complete**

Extract values from compile-time attributes like @compile, @on_definition, @before_compile.

- [x] 15.2.3.1 Extract @compile directive values (inline, no_warn, etc.)
- [x] 15.2.3.2 Extract @on_definition callback module/function
- [x] 15.2.3.3 Extract @before_compile callback specification
- [x] 15.2.3.4 Extract @after_compile callback specification
- [x] 15.2.3.5 Extract @external_resource file paths
- [x] 15.2.3.6 Add compile attribute value tests

**Section 15.2 Unit Tests:**
- [x] Test literal attribute value extraction
- [x] Test complex attribute value extraction (lists, maps)
- [x] Test accumulated attribute handling
- [x] Test @moduledoc content extraction
- [x] Test @doc content extraction
- [x] Test @doc false handling
- [x] Test @compile option extraction
- [x] Test @before_compile/@after_compile extraction

## 15.3 Quote/Unquote Semantics

This section enhances the Quote extractor to capture the full semantics of Elixir's quote/unquote system.

### 15.3.1 Quote Block Analysis
- [x] **Task 15.3.1 Complete**

Enhance quote block extraction to capture options and the quoted AST structure.

- [x] 15.3.1.1 Update `lib/elixir_ontologies/extractors/quote.ex` for quote options
- [x] 15.3.1.2 Extract `quote bind_quoted: [...]` bindings
- [x] 15.3.1.3 Extract `quote unquote: false` option
- [x] 15.3.1.4 Extract `quote location: :keep` option
- [x] 15.3.1.5 Extract `quote context: Module` option
- [x] 15.3.1.6 Add quote option tests

### 15.3.2 Unquote Detection
- [x] **Task 15.3.2 Complete**

Detect and extract unquote and unquote_splicing calls within quote blocks.

- [x] 15.3.2.1 Implement `extract_unquotes/1` finding all unquote calls in AST
- [x] 15.3.2.2 Extract unquoted expression for each unquote call
- [x] 15.3.2.3 Detect `unquote_splicing` calls
- [x] 15.3.2.4 Track unquote nesting depth (for nested quotes)
- [x] 15.3.2.5 Create `%Unquote{expression: ..., splicing: boolean(), depth: ...}` struct
- [x] 15.3.2.6 Add unquote detection tests

### 15.3.3 Macro Hygiene Analysis
- [ ] **Task 15.3.3 Pending**

Analyze macro hygiene aspects including var!/2 usage and context manipulation.

- [ ] 15.3.3.1 Detect `var!/1` and `var!/2` usage in quote blocks
- [ ] 15.3.3.2 Track unhygienic variable introductions
- [ ] 15.3.3.3 Detect `Macro.escape/1` usage
- [ ] 15.3.3.4 Track context parameter manipulation
- [ ] 15.3.3.5 Create `%HygieneViolation{variable: ..., context: ...}` struct
- [ ] 15.3.3.6 Add hygiene analysis tests

**Section 15.3 Unit Tests:**
- [x] Test quote block option extraction
- [x] Test bind_quoted extraction
- [x] Test unquote detection
- [x] Test unquote_splicing detection
- [x] Test nested quote/unquote handling
- [ ] Test var! detection
- [ ] Test Macro.escape detection
- [ ] Test hygiene violation tracking

## 15.4 Metaprogramming Builder

This section implements RDF builders for all metaprogramming constructs.

### 15.4.1 Macro Invocation Builder
- [ ] **Task 15.4.1 Pending**

Generate RDF triples for macro invocations and their relationships.

- [ ] 15.4.1.1 Create `lib/elixir_ontologies/builders/macro_builder.ex` (rename/extend existing)
- [ ] 15.4.1.2 Implement `build_macro_invocation/3` generating invocation IRI
- [ ] 15.4.1.3 Generate `rdf:type structure:MacroInvocation` triple
- [ ] 15.4.1.4 Generate `structure:invokesMacro` linking to macro definition
- [ ] 15.4.1.5 Generate `structure:invokedAt` with source location
- [ ] 15.4.1.6 Add macro invocation builder tests

### 15.4.2 Attribute Value Builder
- [ ] **Task 15.4.2 Pending**

Generate RDF triples for module attribute values.

- [ ] 15.4.2.1 Update or create attribute builder for values
- [ ] 15.4.2.2 Generate `structure:hasAttributeValue` with literal values
- [ ] 15.4.2.3 Generate `structure:isAccumulating` boolean flag
- [ ] 15.4.2.4 Generate `structure:hasDocumentation` for doc attributes
- [ ] 15.4.2.5 Handle complex values (serialize to RDF-compatible format)
- [ ] 15.4.2.6 Add attribute value builder tests

### 15.4.3 Quote Builder
- [ ] **Task 15.4.3 Pending**

Generate RDF triples for quote blocks and unquote expressions.

- [ ] 15.4.3.1 Implement `build_quote_block/3` generating quote IRI
- [ ] 15.4.3.2 Generate `rdf:type structure:QuoteBlock` triple
- [ ] 15.4.3.3 Generate `structure:hasQuoteOption` for each option
- [ ] 15.4.3.4 Generate `structure:containsUnquote` linking to unquote expressions
- [ ] 15.4.3.5 Generate `structure:hasHygieneViolation` for var! usage
- [ ] 15.4.3.6 Add quote builder tests

**Section 15.4 Unit Tests:**
- [ ] Test macro invocation RDF generation
- [ ] Test macro-to-definition linking
- [ ] Test attribute value RDF generation
- [ ] Test accumulated attribute RDF
- [ ] Test documentation attribute RDF
- [ ] Test quote block RDF generation
- [ ] Test unquote RDF generation
- [ ] Test hygiene violation RDF

## Phase 15 Integration Tests

- [ ] **Phase 15 Integration Tests** (15+ tests)

- [ ] Test complete metaprogramming extraction for macro-heavy module
- [ ] Test macro invocation tracking across multiple modules
- [ ] Test attribute value extraction for all attribute types
- [ ] Test quote/unquote extraction in macro definitions
- [ ] Test metaprogramming RDF validates against shapes
- [ ] Test Pipeline integration with metaprogramming extractors
- [ ] Test Orchestrator coordinates metaprogramming builders
- [ ] Test cross-module macro invocation linking
- [ ] Test accumulated attribute representation
- [ ] Test documentation content preservation
- [ ] Test compile attribute extraction
- [ ] Test nested quote handling
- [ ] Test hygiene analysis accuracy
- [ ] Test backward compatibility with existing macro extraction
- [ ] Test error handling for complex AST patterns
