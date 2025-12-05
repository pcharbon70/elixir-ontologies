# Phase 1: Core Infrastructure & RDF Foundation

This phase establishes the project foundation, configures dependencies, and implements the core RDF infrastructure. We'll create namespace definitions matching all ontologies, implement IRI generation strategies, and build the Graph wrapper for CRUD operations.

## 1.1 Project Structure and Dependencies

This section sets up the Elixir project structure with all necessary dependencies and configuration files. The module structure will mirror the architectural design, with clear separation between graph operations, analysis, and building.

### 1.1.1 Extend Existing Project Structure
- [x] **Task 1.1.1 Complete**

Extend the existing mix.exs to add RDF dependencies and create the analyzer module structure.

- [x] 1.1.1.1 Add `{:rdf, "~> 2.0"}` to deps in `mix.exs`
- [x] 1.1.1.2 Add `{:sparql, "~> 0.3", optional: true}` for query support
- [x] 1.1.1.3 Create `lib/elixir_ontologies/graph/` directory for graph operations
- [x] 1.1.1.4 Create `lib/elixir_ontologies/analyzer/` directory for code analysis
- [x] 1.1.1.5 Create `lib/elixir_ontologies/builders/` directory for RDF construction
- [x] 1.1.1.6 Create `lib/elixir_ontologies/extractors/` directory for AST extraction
- [x] 1.1.1.7 Run `mix deps.get` and verify compilation (success: `mix compile` exits 0)

### 1.1.2 Configuration Structure
- [x] **Task 1.1.2 Complete**

Establish configuration options for the analyzer including base IRI, output options, and feature flags.

- [x] 1.1.2.1 Create `lib/elixir_ontologies/config.ex` with configuration schema
- [x] 1.1.2.2 Define `%Config{base_iri, include_source_text, include_git_info, output_format}` struct
- [x] 1.1.2.3 Implement `Config.default/0` returning sensible defaults
- [x] 1.1.2.4 Implement `Config.merge/2` for combining user options with defaults
- [x] 1.1.2.5 Add config validation with clear error messages
- [x] 1.1.2.6 Write config tests (success: 14 tests pass covering all options)

**Section 1.1 Unit Tests:**
- [x] Test project compiles with all dependencies
- [x] Test Config struct creation and defaults
- [x] Test Config.merge/2 with various option combinations
- [x] Test Config validation rejects invalid options

## 1.2 RDF Namespace Definitions

This section defines RDF namespaces matching all ontology prefixes. These namespaces enable proper IRI construction and provide a clean API for building RDF statements.

### 1.2.1 Core Ontology Namespaces
- [ ] **Task 1.2.1 Complete**

Define namespace modules for each ontology using RDF.ex's namespace definition macros.

- [ ] 1.2.1.1 Create `lib/elixir_ontologies/namespaces.ex` as central namespace registry
- [ ] 1.2.1.2 Define `ElixirOntologies.NS.Core` for `https://w3id.org/elixir-code/core#`
- [ ] 1.2.1.3 Define `ElixirOntologies.NS.Structure` for `https://w3id.org/elixir-code/structure#`
- [ ] 1.2.1.4 Define `ElixirOntologies.NS.OTP` for `https://w3id.org/elixir-code/otp#`
- [ ] 1.2.1.5 Define `ElixirOntologies.NS.Evolution` for `https://w3id.org/elixir-code/evolution#`
- [ ] 1.2.1.6 Include standard namespaces: RDF, RDFS, OWL, XSD, PROV, BFO, IAO
- [ ] 1.2.1.7 Create helper function `prefix_map/0` returning all prefixes for serialization
- [ ] 1.2.1.8 Write namespace tests (success: all IRIs resolve correctly)

### 1.2.2 Namespace Term Definitions
- [ ] **Task 1.2.2 Complete**

Define individual terms within each namespace for type-safe RDF construction.

- [ ] 1.2.2.1 Define Core namespace terms: `CodeElement`, `SourceFile`, `SourceLocation`, `Repository`, `CommitRef`, all AST classes
- [ ] 1.2.2.2 Define Structure namespace terms: `Module`, `Function`, `Parameter`, `FunctionClause`, all Elixir constructs
- [ ] 1.2.2.3 Define OTP namespace terms: `GenServer`, `Supervisor`, `Process`, all OTP patterns
- [ ] 1.2.2.4 Define Evolution namespace terms: `Commit`, `DevelopmentActivity`, all provenance classes
- [ ] 1.2.2.5 Define property terms for all object and data properties
- [ ] 1.2.2.6 Write term definition tests (success: 50+ terms defined and accessible)

**Section 1.2 Unit Tests:**
- [ ] Test each namespace module is defined
- [ ] Test IRI generation for class terms
- [ ] Test IRI generation for property terms
- [ ] Test prefix_map/0 returns complete mapping
- [ ] Test namespace terms match ontology definitions

## 1.3 IRI Generation

This section implements the path-based IRI generation strategy. IRIs must be stable, readable, and reflect Elixir's identity model (Module, Function/Arity for functions).

### 1.3.1 IRI Builder Module
- [ ] **Task 1.3.1 Complete**

Create the IRI builder that generates consistent, path-based IRIs for all code elements.

- [ ] 1.3.1.1 Create `lib/elixir_ontologies/iri.ex` module
- [ ] 1.3.1.2 Implement `IRI.for_module(base_iri, module_name)` → `base:ModuleName`
- [ ] 1.3.1.3 Implement `IRI.for_function(base_iri, module, name, arity)` → `base:Module/name/arity`
- [ ] 1.3.1.4 Implement `IRI.for_clause(base_iri, function_iri, clause_order)` → `function_iri/clause/N`
- [ ] 1.3.1.5 Implement `IRI.for_parameter(base_iri, clause_iri, position)` → `clause_iri/param/N`
- [ ] 1.3.1.6 Implement `IRI.for_source_file(base_iri, relative_path)` → `base:file/path/to/file.ex`
- [ ] 1.3.1.7 Implement `IRI.for_source_location(file_iri, start_line, end_line)` → `file_iri/L{start}-{end}`
- [ ] 1.3.1.8 Implement `IRI.for_repository(base_iri, repo_url)` → `base:repo/hash`
- [ ] 1.3.1.9 Implement `IRI.for_commit(repo_iri, sha)` → `repo_iri/commit/sha`
- [ ] 1.3.1.10 Handle special characters in names (escape `!`, `?`, operators)
- [ ] 1.3.1.11 Write IRI generation tests (success: 20 tests covering all patterns)

### 1.3.2 IRI Utilities
- [ ] **Task 1.3.2 Complete**

Implement utility functions for IRI manipulation and validation.

- [ ] 1.3.2.1 Implement `IRI.parse/1` to extract components from an IRI
- [ ] 1.3.2.2 Implement `IRI.valid?/1` to validate IRI format
- [ ] 1.3.2.3 Implement `IRI.escape_name/1` for safe IRI component encoding
- [ ] 1.3.2.4 Implement `IRI.module_from_iri/1` to extract module name
- [ ] 1.3.2.5 Implement `IRI.function_from_iri/1` to extract {module, name, arity}
- [ ] 1.3.2.6 Write utility tests (success: 12 tests pass)

**Section 1.3 Unit Tests:**
- [ ] Test IRI generation for modules with nested names
- [ ] Test IRI generation for functions with special characters (!, ?)
- [ ] Test IRI generation for operators (+, -, |>, etc.)
- [ ] Test IRI parsing extracts correct components
- [ ] Test IRI escaping handles all edge cases
- [ ] Test round-trip: generate → parse → components match

## 1.4 Graph CRUD Operations

This section implements the Graph wrapper providing clean APIs for creating, loading, saving, and manipulating RDF graphs.

### 1.4.1 Graph Module
- [ ] **Task 1.4.1 Complete**

Create the main Graph module wrapping RDF.ex functionality with a domain-specific API.

- [ ] 1.4.1.1 Create `lib/elixir_ontologies/graph.ex` module
- [ ] 1.4.1.2 Define `%Graph{}` struct wrapping `RDF.Graph`
- [ ] 1.4.1.3 Implement `Graph.new/1` accepting optional base_iri
- [ ] 1.4.1.4 Implement `Graph.add/2` for adding single statements
- [ ] 1.4.1.5 Implement `Graph.add_all/2` for adding multiple statements
- [ ] 1.4.1.6 Implement `Graph.merge/2` for combining graphs
- [ ] 1.4.1.7 Implement `Graph.subjects/1` returning all subjects
- [ ] 1.4.1.8 Implement `Graph.describe/2` returning all triples for a subject
- [ ] 1.4.1.9 Implement `Graph.query/2` for SPARQL queries (when sparql available)
- [ ] 1.4.1.10 Write graph manipulation tests (success: 15 tests pass)

### 1.4.2 Graph Serialization
- [ ] **Task 1.4.2 Complete**

Implement graph serialization to Turtle format with proper prefix handling.

- [ ] 1.4.2.1 Implement `Graph.to_turtle/1` serializing to Turtle string
- [ ] 1.4.2.2 Implement `Graph.to_turtle/2` with options (prefixes, base)
- [ ] 1.4.2.3 Implement `Graph.save/2` writing to file path
- [ ] 1.4.2.4 Implement `Graph.save/3` with format option
- [ ] 1.4.2.5 Ensure all ontology prefixes are included in output
- [ ] 1.4.2.6 Write serialization tests (success: output is valid Turtle)

### 1.4.3 Graph Loading
- [ ] **Task 1.4.3 Complete**

Implement graph loading from Turtle files.

- [ ] 1.4.3.1 Implement `Graph.load/1` loading from file path
- [ ] 1.4.3.2 Implement `Graph.load/2` with format option
- [ ] 1.4.3.3 Implement `Graph.from_turtle/1` parsing Turtle string
- [ ] 1.4.3.4 Handle parse errors with clear messages
- [ ] 1.4.3.5 Write loading tests with sample Turtle files (success: 8 tests pass)

**Section 1.4 Unit Tests:**
- [ ] Test Graph.new/0 creates empty graph
- [ ] Test Graph.add/2 adds triples correctly
- [ ] Test Graph.merge/2 combines graphs without duplicates
- [ ] Test Graph.to_turtle/1 produces valid output
- [ ] Test Graph.save/2 writes to file
- [ ] Test Graph.load/1 reads from file
- [ ] Test round-trip: save → load → graphs equal

## Phase 1 Integration Tests

- [ ] Test complete workflow: create graph → add triples → save → load → verify
- [ ] Test namespace resolution in serialized output
- [ ] Test IRI generation integrates with graph operations
- [ ] Test configuration flows through all components
