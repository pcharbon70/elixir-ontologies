# Phase 18: Anonymous Functions & Closures

This phase implements extraction and building for anonymous functions, capture operators, and closure semantics. Anonymous functions are fundamental to Elixir's functional programming style, and understanding their captured variables and scope is essential for complete code analysis. The ontology defines AnonymousFunction, Closure, and related classes that this phase will populate.

## 18.1 Anonymous Function Extraction

This section implements extraction of anonymous function definitions using fn/end syntax.

### 18.1.1 Basic Anonymous Function Extraction
- [ ] **Task 18.1.1 Pending**

Extract anonymous function definitions with their clauses.

- [ ] 18.1.1.1 Create `lib/elixir_ontologies/extractors/anonymous_function.ex`
- [ ] 18.1.1.2 Define `%AnonymousFunction{clauses: [...], arity: ..., location: ..., captured_vars: [...]}` struct
- [ ] 18.1.1.3 Implement `extract_anonymous_function/1` for `fn -> end` AST pattern
- [ ] 18.1.1.4 Extract all clauses of multi-clause anonymous functions
- [ ] 18.1.1.5 Calculate arity from parameters
- [ ] 18.1.1.6 Add basic anonymous function tests

### 18.1.2 Anonymous Function Clause Extraction
- [ ] **Task 18.1.2 Pending**

Extract individual clauses of anonymous functions with their patterns and guards.

- [ ] 18.1.2.1 Define `%AnonymousFunctionClause{parameters: [...], guard: ..., body: ...}` struct
- [ ] 18.1.2.2 Extract parameter patterns for each clause
- [ ] 18.1.2.3 Extract guard expressions (when clauses)
- [ ] 18.1.2.4 Extract clause body
- [ ] 18.1.2.5 Track clause order for pattern matching semantics
- [ ] 18.1.2.6 Add clause extraction tests

### 18.1.3 Capture Operator Extraction
- [ ] **Task 18.1.3 Pending**

Extract capture operator expressions (&) for creating function references.

- [ ] 18.1.3.1 Implement `extract_capture/1` for `&func/arity` pattern
- [ ] 18.1.3.2 Define `%Capture{type: :named|:anonymous, target: ..., arity: ...}` struct
- [ ] 18.1.3.3 Extract named function captures (`&Module.function/arity`)
- [ ] 18.1.3.4 Extract local function captures (`&function/arity`)
- [ ] 18.1.3.5 Extract shorthand captures (`&(&1 + &2)`)
- [ ] 18.1.3.6 Add capture operator tests

### 18.1.4 Capture Placeholder Analysis
- [ ] **Task 18.1.4 Pending**

Analyze capture placeholders (&1, &2, etc.) in shorthand captures.

- [ ] 18.1.4.1 Implement `extract_capture_placeholders/1` finding all &N references
- [ ] 18.1.4.2 Track highest placeholder number (determines arity)
- [ ] 18.1.4.3 Detect gaps in placeholder numbering
- [ ] 18.1.4.4 Track placeholder positions in expressions
- [ ] 18.1.4.5 Create `%CapturePlaceholder{position: ..., usage_locations: [...]}` struct
- [ ] 18.1.4.6 Add placeholder analysis tests

**Section 18.1 Unit Tests:**
- [ ] Test single-clause anonymous function extraction
- [ ] Test multi-clause anonymous function extraction
- [ ] Test anonymous function guard extraction
- [ ] Test named function capture (`&func/1`)
- [ ] Test remote function capture (`&Module.func/2`)
- [ ] Test shorthand capture (`&(&1 + 1)`)
- [ ] Test placeholder counting
- [ ] Test capture arity calculation

## 18.2 Closure Variable Tracking

This section implements tracking of variables captured by closures from their enclosing scope.

### 18.2.1 Free Variable Detection
- [ ] **Task 18.2.1 Pending**

Detect free variables in anonymous functions that reference outer scope.

- [ ] 18.2.1.1 Implement `detect_free_variables/2` comparing inner/outer scopes
- [ ] 18.2.1.2 Track all variable references in anonymous function body
- [ ] 18.2.1.3 Track variables bound in function parameters
- [ ] 18.2.1.4 Identify variables that must be captured (free variables)
- [ ] 18.2.1.5 Create `%FreeVariable{name: ..., binding_location: ..., captured_at: ...}` struct
- [ ] 18.2.1.6 Add free variable detection tests

### 18.2.2 Closure Scope Analysis
- [ ] **Task 18.2.2 Pending**

Analyze the scope from which variables are captured.

- [ ] 18.2.2.1 Implement `analyze_closure_scope/2` for scope tracking
- [ ] 18.2.2.2 Track enclosing function scope
- [ ] 18.2.2.3 Track enclosing module scope (module attributes)
- [ ] 18.2.2.4 Handle nested closures (capture from intermediate scope)
- [ ] 18.2.2.5 Create `%ClosureScope{level: ..., variables: [...], parent: ...}` struct
- [ ] 18.2.2.6 Add closure scope tests

### 18.2.3 Capture Mutation Detection
- [ ] **Task 18.2.3 Pending**

Detect potential issues with captured variable mutation patterns.

- [ ] 18.2.3.1 Implement `detect_mutation_patterns/1` for captured variables
- [ ] 18.2.3.2 Track whether captured variable is rebound in closure
- [ ] 18.2.3.3 Detect patterns that might cause confusion (shadowing)
- [ ] 18.2.3.4 Track variable rebinding after closure definition
- [ ] 18.2.3.5 Create `%MutationPattern{variable: ..., type: :shadow|:rebind|:immutable}` struct
- [ ] 18.2.3.6 Add mutation detection tests

**Section 18.2 Unit Tests:**
- [ ] Test free variable detection
- [ ] Test captured variable from function scope
- [ ] Test captured variable from module attribute
- [ ] Test nested closure capture
- [ ] Test shadowed variable detection
- [ ] Test variable rebinding detection
- [ ] Test closure with no captures
- [ ] Test closure with multiple captures

## 18.3 Anonymous Function Builder

This section implements RDF builders for anonymous functions and closures.

### 18.3.1 Anonymous Function Builder
- [ ] **Task 18.3.1 Pending**

Generate RDF triples for anonymous function definitions.

- [ ] 18.3.1.1 Create `lib/elixir_ontologies/builders/anonymous_function_builder.ex`
- [ ] 18.3.1.2 Implement `build_anonymous_function/3` generating unique IRI
- [ ] 18.3.1.3 Generate `rdf:type structure:AnonymousFunction` triple
- [ ] 18.3.1.4 Generate `structure:hasArity` with arity value
- [ ] 18.3.1.5 Generate `structure:hasClause` for each clause
- [ ] 18.3.1.6 Add anonymous function builder tests

### 18.3.2 Closure Builder
- [ ] **Task 18.3.2 Pending**

Generate RDF triples for closure semantics and captured variables.

- [ ] 18.3.2.1 Implement `build_closure/3` generating closure IRI
- [ ] 18.3.2.2 Generate `rdf:type structure:Closure` triple
- [ ] 18.3.2.3 Generate `structure:capturesVariable` for each captured variable
- [ ] 18.3.2.4 Generate `structure:capturedFrom` linking to enclosing scope
- [ ] 18.3.2.5 Generate `structure:captureBindingLocation` for each capture
- [ ] 18.3.2.6 Add closure builder tests

### 18.3.3 Capture Builder
- [ ] **Task 18.3.3 Pending**

Generate RDF triples for capture operator expressions.

- [ ] 18.3.3.1 Implement `build_capture/3` generating capture IRI
- [ ] 18.3.3.2 Generate `rdf:type structure:CaptureExpression` triple
- [ ] 18.3.3.3 Generate `structure:capturesFunction` for named captures
- [ ] 18.3.3.4 Generate `structure:hasExpression` for shorthand captures
- [ ] 18.3.3.5 Generate `structure:derivedArity` for shorthand capture arity
- [ ] 18.3.3.6 Add capture builder tests

**Section 18.3 Unit Tests:**
- [ ] Test anonymous function RDF generation
- [ ] Test multi-clause function RDF
- [ ] Test closure RDF with captured variables
- [ ] Test capture expression RDF
- [ ] Test shorthand capture RDF
- [ ] Test named function capture RDF
- [ ] Test closure-to-scope linking
- [ ] Test SHACL validation of anonymous function RDF

## Phase 18 Integration Tests

- [ ] **Phase 18 Integration Tests** (12+ tests)

- [ ] Test complete anonymous function extraction for complex module
- [ ] Test closure variable tracking accuracy
- [ ] Test capture operator coverage
- [ ] Test anonymous function RDF validates against shapes
- [ ] Test Pipeline integration with anonymous function extractors
- [ ] Test Orchestrator coordinates closure builders
- [ ] Test nested anonymous functions
- [ ] Test closures in comprehensions
- [ ] Test captures in pipe chains
- [ ] Test multi-clause anonymous function handling
- [ ] Test backward compatibility with existing extractors
- [ ] Test error handling for complex closure patterns
