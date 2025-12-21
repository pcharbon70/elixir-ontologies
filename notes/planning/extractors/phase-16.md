# Phase 16: Module Directives & Scope Analysis

This phase implements comprehensive extraction for module directives (alias, import, require, use) and lexical scope tracking. While the Module extractor captures directive existence, it does not extract the full details needed to build a complete module dependency graph. This phase enables understanding of how modules relate to each other through their directive declarations.

## 16.1 Alias Directive Extraction

This section implements detailed extraction of alias directives including multi-alias forms, as options, and scope tracking.

### 16.1.1 Basic Alias Extraction
- [x] **Task 16.1.1 Complete**

Extract basic alias directives with their source and target module names.

- [x] 16.1.1.1 Create `lib/elixir_ontologies/extractors/directive/alias.ex`
- [x] 16.1.1.2 Define `%AliasDirective{source: ..., as: ..., location: ..., scope: ...}` struct
- [x] 16.1.1.3 Extract `alias Module.Name` simple form
- [x] 16.1.1.4 Extract `alias Module.Name, as: Short` explicit form
- [x] 16.1.1.5 Extract computed alias name when `as:` not specified
- [x] 16.1.1.6 Add basic alias tests

### 16.1.2 Multi-Alias Extraction
- [x] **Task 16.1.2 Complete**

Extract multi-alias forms using the curly brace syntax.

- [x] 16.1.2.1 Implement `extract_multi_alias/1` for `alias Module.{A, B, C}` syntax
- [x] 16.1.2.2 Expand multi-alias into individual alias directives
- [x] 16.1.2.3 Track source location for each expanded alias
- [x] 16.1.2.4 Handle nested multi-alias (e.g., `alias Module.{Sub.{A, B}, C}`)
- [x] 16.1.2.5 Preserve relationship to original multi-alias form
- [x] 16.1.2.6 Add multi-alias tests

### 16.1.3 Alias Scope Tracking
- [x] **Task 16.1.3 Complete**

Track the lexical scope of alias directives (module-level, function-level, block-level).

- [x] 16.1.3.1 Implement scope detection for alias directives
- [x] 16.1.3.2 Track module-level aliases (top of module)
- [x] 16.1.3.3 Track function-level aliases (inside function bodies)
- [x] 16.1.3.4 Track block-level aliases (inside blocks, comprehensions)
- [x] 16.1.3.5 Create `%LexicalScope{type: ..., start_line: ..., end_line: ...}` struct
- [x] 16.1.3.6 Add scope tracking tests

**Section 16.1 Unit Tests:**
- [x] Test simple alias extraction
- [x] Test alias with explicit `as:` option
- [x] Test multi-alias expansion
- [x] Test nested multi-alias
- [x] Test module-level alias scope
- [x] Test function-level alias scope
- [x] Test alias source location extraction
- [x] Test computed alias name derivation

## 16.2 Import Directive Extraction

This section implements detailed extraction of import directives including selective imports with only/except options.

### 16.2.1 Basic Import Extraction
- [x] **Task 16.2.1 Complete**

Extract basic import directives with their module references.

- [x] 16.2.1.1 Create `lib/elixir_ontologies/extractors/directive/import.ex`
- [x] 16.2.1.2 Define `%ImportDirective{module: ..., only: ..., except: ..., location: ..., scope: ...}` struct
- [x] 16.2.1.3 Extract `import Module` full import form
- [x] 16.2.1.4 Extract imported module reference
- [x] 16.2.1.5 Track import location
- [x] 16.2.1.6 Add basic import tests

### 16.2.2 Selective Import Extraction
- [x] **Task 16.2.2 Complete**

Extract selective imports using only/except options.

- [x] 16.2.2.1 Extract `import Module, only: [func: arity]` form
- [x] 16.2.2.2 Extract `import Module, except: [func: arity]` form
- [x] 16.2.2.3 Extract `import Module, only: :functions` form
- [x] 16.2.2.4 Extract `import Module, only: :macros` form
- [x] 16.2.2.5 Parse function/arity lists into structured data
- [x] 16.2.2.6 Add selective import tests

### 16.2.3 Import Conflict Detection
- [x] **Task 16.2.3 Complete**

Detect potential import conflicts where multiple imports define the same function.

- [x] 16.2.3.1 Implement `detect_import_conflicts/1` analyzing all imports
- [x] 16.2.3.2 Track function names imported from each module
- [x] 16.2.3.3 Identify overlapping function definitions
- [x] 16.2.3.4 Create `%ImportConflict{function: ..., modules: [...]}` struct
- [x] 16.2.3.5 Report conflicts with their locations
- [x] 16.2.3.6 Add conflict detection tests

**Section 16.2 Unit Tests:**
- [x] Test full import extraction
- [x] Test `only:` selective import
- [x] Test `except:` selective import
- [x] Test `only: :functions` type import
- [x] Test `only: :macros` type import
- [x] Test import conflict detection
- [x] Test import scope tracking
- [x] Test multi-arity function imports

## 16.3 Require and Use Directive Extraction

This section implements extraction for require and use directives, including use options.

### 16.3.1 Require Extraction
- [x] **Task 16.3.1 Complete**

Extract require directives needed for macro availability.

- [x] 16.3.1.1 Create `lib/elixir_ontologies/extractors/directive/require.ex`
- [x] 16.3.1.2 Define `%RequireDirective{module: ..., as: ..., location: ..., scope: ...}` struct
- [x] 16.3.1.3 Extract `require Module` form
- [x] 16.3.1.4 Extract `require Module, as: Short` form
- [x] 16.3.1.5 Track which macros become available via require (noted in metadata - full tracking requires module analysis)
- [x] 16.3.1.6 Add require extraction tests

### 16.3.2 Use Extraction
- [x] **Task 16.3.2 Complete**

Extract use directives with their options, which invoke __using__ macros.

- [x] 16.3.2.1 Create `lib/elixir_ontologies/extractors/directive/use.ex`
- [x] 16.3.2.2 Define `%UseDirective{module: ..., options: [...], location: ..., scope: ...}` struct
- [x] 16.3.2.3 Extract `use Module` form
- [x] 16.3.2.4 Extract `use Module, option: value` form with all options
- [x] 16.3.2.5 Track use as macro invocation of __using__/1 (noted in metadata - options passed to __using__/1)
- [x] 16.3.2.6 Add use extraction tests

### 16.3.3 Use Option Analysis
- [x] **Task 16.3.3 Complete**

Analyze use options to understand configuration passed to __using__ callbacks.

- [x] 16.3.3.1 Parse keyword options in use directives
- [x] 16.3.3.2 Track common option patterns (e.g., `use GenServer, restart: :temporary`)
- [x] 16.3.3.3 Extract literal option values
- [x] 16.3.3.4 Handle dynamic option values (mark as unresolved)
- [x] 16.3.3.5 Create `%UseOption{key: ..., value: ..., dynamic: boolean()}` struct
- [x] 16.3.3.6 Add use option analysis tests

**Section 16.3 Unit Tests:**
- [x] Test require extraction
- [x] Test require with `as:` option
- [x] Test simple use extraction
- [x] Test use with keyword options
- [x] Test use option parsing
- [x] Test dynamic use option handling
- [x] Test scope tracking for require/use
- [x] Test multiple use directives

## 16.4 Module Dependency Graph

This section builds the module dependency graph connecting modules through their directive relationships.

### 16.4.1 Dependency Graph Builder
- [ ] **Task 16.4.1 Pending**

Generate RDF triples representing module dependencies from directives.

- [ ] 16.4.1.1 Create `lib/elixir_ontologies/builders/dependency_builder.ex`
- [ ] 16.4.1.2 Implement `build_alias_dependency/3` generating alias IRI and triples
- [ ] 16.4.1.3 Generate `rdf:type structure:ModuleAlias` triple
- [ ] 16.4.1.4 Generate `structure:aliasesModule` linking to aliased module
- [ ] 16.4.1.5 Generate `structure:aliasedAs` with the short name
- [ ] 16.4.1.6 Add alias dependency tests

### 16.4.2 Import Dependency Builder
- [ ] **Task 16.4.2 Pending**

Generate RDF triples for import dependencies.

- [ ] 16.4.2.1 Implement `build_import_dependency/3` generating import IRI
- [ ] 16.4.2.2 Generate `rdf:type structure:Import` triple
- [ ] 16.4.2.3 Generate `structure:importsModule` linking to imported module
- [ ] 16.4.2.4 Generate `structure:importsFunction` for each imported function
- [ ] 16.4.2.5 Generate `structure:excludesFunction` for excluded functions
- [ ] 16.4.2.6 Add import dependency tests

### 16.4.3 Use/Require Dependency Builder
- [ ] **Task 16.4.3 Pending**

Generate RDF triples for use and require dependencies.

- [ ] 16.4.3.1 Implement `build_require_dependency/3` generating require IRI
- [ ] 16.4.3.2 Generate `rdf:type structure:Require` triple
- [ ] 16.4.3.3 Implement `build_use_dependency/3` generating use IRI
- [ ] 16.4.3.4 Generate `rdf:type structure:Use` triple
- [ ] 16.4.3.5 Generate `structure:hasUseOption` for each option
- [ ] 16.4.3.6 Add require/use dependency tests

### 16.4.4 Cross-Module Linking
- [ ] **Task 16.4.4 Pending**

Link directives to actual module definitions when available in analysis scope.

- [ ] 16.4.4.1 Implement module resolution for aliased modules
- [ ] 16.4.4.2 Link imports to actual module IRIs
- [ ] 16.4.4.3 Link use directives to __using__ macro definitions
- [ ] 16.4.4.4 Handle unresolved references (external dependencies)
- [ ] 16.4.4.5 Generate `structure:referencesExternalModule` for unresolved
- [ ] 16.4.4.6 Add cross-module linking tests

**Section 16.4 Unit Tests:**
- [ ] Test alias dependency RDF generation
- [ ] Test import dependency RDF generation
- [ ] Test require dependency RDF generation
- [ ] Test use dependency RDF generation
- [ ] Test cross-module linking
- [ ] Test external module reference handling
- [ ] Test dependency graph completeness
- [ ] Test SHACL validation of dependency graph

## Phase 16 Integration Tests

- [ ] **Phase 16 Integration Tests** (15+ tests)

- [ ] Test complete directive extraction for complex module
- [ ] Test module dependency graph generation
- [ ] Test multi-module analysis with cross-references
- [ ] Test directive RDF validates against shapes
- [ ] Test Pipeline integration with directive extractors
- [ ] Test Orchestrator coordinates dependency builders
- [ ] Test alias resolution across modules
- [ ] Test import conflict detection accuracy
- [ ] Test use option extraction completeness
- [ ] Test lexical scope tracking accuracy
- [ ] Test external dependency marking
- [ ] Test circular dependency detection
- [ ] Test multi-alias expansion correctness
- [ ] Test backward compatibility with existing module extraction
- [ ] Test error handling for malformed directives
