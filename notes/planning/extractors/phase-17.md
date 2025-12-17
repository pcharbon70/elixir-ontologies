# Phase 17: Call Graph & Control Flow

This phase implements function call extraction and control flow analysis to build a complete call graph for analyzed code. Understanding which functions call which others, and how control flows through conditionals and exception handling, is essential for comprehensive code understanding. The ontology defines classes for function calls, control flow statements, and exception handling that this phase will populate.

## 17.1 Function Call Extraction

This section implements extraction of function calls, distinguishing between local calls, remote calls, and dynamic calls.

### 17.1.1 Local Function Call Extraction
- [ ] **Task 17.1.1 Pending**

Extract calls to functions defined in the same module (local calls).

- [ ] 17.1.1.1 Create `lib/elixir_ontologies/extractors/call.ex`
- [ ] 17.1.1.2 Define `%FunctionCall{type: :local, name: ..., arity: ..., arguments: ..., location: ...}` struct
- [ ] 17.1.1.3 Implement `extract_local_calls/1` finding all local function calls in AST
- [ ] 17.1.1.4 Distinguish calls from variable references
- [ ] 17.1.1.5 Track call site location
- [ ] 17.1.1.6 Add local call extraction tests

### 17.1.2 Remote Function Call Extraction
- [ ] **Task 17.1.2 Pending**

Extract calls to functions in other modules (remote calls via Module.function).

- [ ] 17.1.2.1 Implement `extract_remote_calls/1` for `Module.function(args)` pattern
- [ ] 17.1.2.2 Define `%FunctionCall{type: :remote, module: ..., name: ..., arity: ...}` fields
- [ ] 17.1.2.3 Handle aliased module calls (resolve alias to full module name)
- [ ] 17.1.2.4 Handle imported function calls (resolve to source module)
- [ ] 17.1.2.5 Track whether module is aliased or full name
- [ ] 17.1.2.6 Add remote call extraction tests

### 17.1.3 Dynamic Call Extraction
- [ ] **Task 17.1.3 Pending**

Extract dynamic function calls using apply/3, Kernel.apply/3, and variable function names.

- [ ] 17.1.3.1 Implement `extract_dynamic_calls/1` for apply patterns
- [ ] 17.1.3.2 Define `%FunctionCall{type: :dynamic, ...}` for unresolved targets
- [ ] 17.1.3.3 Detect `apply(module, function, args)` calls
- [ ] 17.1.3.4 Detect `fun.(args)` anonymous function calls
- [ ] 17.1.3.5 Track known vs unknown targets
- [ ] 17.1.3.6 Add dynamic call extraction tests

### 17.1.4 Pipe Chain Extraction
- [ ] **Task 17.1.4 Pending**

Extract function calls from pipe chains, preserving the pipe structure.

- [ ] 17.1.4.1 Implement `extract_pipe_chain/1` for `|>` operator sequences
- [ ] 17.1.4.2 Define `%PipeChain{steps: [...], start_value: ..., location: ...}` struct
- [ ] 17.1.4.3 Extract each step as a function call with implicit first argument
- [ ] 17.1.4.4 Track pipe chain order and length
- [ ] 17.1.4.5 Handle partial function application in pipes
- [ ] 17.1.4.6 Add pipe chain extraction tests

**Section 17.1 Unit Tests:**
- [ ] Test local function call extraction
- [ ] Test remote function call extraction
- [ ] Test aliased module call resolution
- [ ] Test imported function call resolution
- [ ] Test apply/3 call extraction
- [ ] Test anonymous function call extraction
- [ ] Test pipe chain extraction
- [ ] Test call site location accuracy

## 17.2 Control Flow Extraction

This section extracts control flow structures including conditionals, pattern matching expressions, and comprehensions.

### 17.2.1 Conditional Expression Extraction
- [ ] **Task 17.2.1 Pending**

Extract if/unless/cond expressions with their branches.

- [ ] 17.2.1.1 Update `lib/elixir_ontologies/extractors/control_flow.ex` for detailed extraction
- [ ] 17.2.1.2 Define `%Conditional{type: :if|:unless|:cond, condition: ..., branches: [...]}` struct
- [ ] 17.2.1.3 Extract `if` condition and both branches (true/else)
- [ ] 17.2.1.4 Extract `unless` condition and both branches
- [ ] 17.2.1.5 Extract `cond` with all clause conditions
- [ ] 17.2.1.6 Add conditional extraction tests

### 17.2.2 Case and With Expression Extraction
- [ ] **Task 17.2.2 Pending**

Extract case and with expressions with their pattern matching clauses.

- [ ] 17.2.2.1 Implement `extract_case/1` for case expressions
- [ ] 17.2.2.2 Define `%CaseExpression{subject: ..., clauses: [...], location: ...}` struct
- [ ] 17.2.2.3 Extract each case clause with pattern and guard
- [ ] 17.2.2.4 Implement `extract_with/1` for with expressions
- [ ] 17.2.2.5 Define `%WithExpression{clauses: [...], else: ..., location: ...}` struct
- [ ] 17.2.2.6 Add case/with extraction tests

### 17.2.3 Receive Expression Extraction
- [ ] **Task 17.2.3 Pending**

Extract receive expressions with their message patterns and timeouts.

- [ ] 17.2.3.1 Implement `extract_receive/1` for receive blocks
- [ ] 17.2.3.2 Define `%ReceiveExpression{clauses: [...], after: ..., location: ...}` struct
- [ ] 17.2.3.3 Extract message patterns in receive clauses
- [ ] 17.2.3.4 Extract `after` timeout clause
- [ ] 17.2.3.5 Track receive as potential blocking point
- [ ] 17.2.3.6 Add receive extraction tests

### 17.2.4 Loop Expression Extraction
- [ ] **Task 17.2.4 Pending**

Extract for comprehensions and recursive patterns.

- [ ] 17.2.4.1 Update `lib/elixir_ontologies/extractors/comprehension.ex` for loop semantics
- [ ] 17.2.4.2 Define `%ForLoop{generators: [...], filters: [...], into: ..., body: ...}` struct
- [ ] 17.2.4.3 Extract generators (binding patterns)
- [ ] 17.2.4.4 Extract filters (guard expressions)
- [ ] 17.2.4.5 Extract `into:` accumulator target
- [ ] 17.2.4.6 Add loop extraction tests

**Section 17.2 Unit Tests:**
- [ ] Test if/else extraction
- [ ] Test unless extraction
- [ ] Test cond clause extraction
- [ ] Test case expression extraction
- [ ] Test with expression extraction
- [ ] Test receive extraction with after
- [ ] Test for comprehension extraction
- [ ] Test nested control flow structures

## 17.3 Exception Handling Extraction

This section extracts exception handling constructs including try/rescue/catch/after blocks.

### 17.3.1 Try Block Extraction
- [ ] **Task 17.3.1 Pending**

Extract try blocks with all their clauses.

- [ ] 17.3.1.1 Create `lib/elixir_ontologies/extractors/exception.ex`
- [ ] 17.3.1.2 Define `%TryExpression{body: ..., rescue: [...], catch: [...], else: [...], after: ...}` struct
- [ ] 17.3.1.3 Extract try body expression
- [ ] 17.3.1.4 Track all clause types present
- [ ] 17.3.1.5 Handle try with only some clauses (e.g., try/after without rescue)
- [ ] 17.3.1.6 Add try block extraction tests

### 17.3.2 Rescue Clause Extraction
- [ ] **Task 17.3.2 Pending**

Extract rescue clauses with their exception patterns.

- [ ] 17.3.2.1 Implement `extract_rescue_clauses/1` for rescue blocks
- [ ] 17.3.2.2 Define `%RescueClause{exceptions: [...], variable: ..., body: ...}` struct
- [ ] 17.3.2.3 Extract exception type patterns (e.g., `ArgumentError`)
- [ ] 17.3.2.4 Extract exception variable binding (e.g., `rescue e ->`)
- [ ] 17.3.2.5 Handle bare rescue (catch-all)
- [ ] 17.3.2.6 Add rescue clause extraction tests

### 17.3.3 Catch Clause Extraction
- [ ] **Task 17.3.3 Pending**

Extract catch clauses for throw/exit/error handling.

- [ ] 17.3.3.1 Implement `extract_catch_clauses/1` for catch blocks
- [ ] 17.3.3.2 Define `%CatchClause{type: :throw|:exit|:error, pattern: ..., body: ...}` struct
- [ ] 17.3.3.3 Extract catch type (:throw, :exit, :error)
- [ ] 17.3.3.4 Extract catch pattern
- [ ] 17.3.3.5 Handle catch without explicit type
- [ ] 17.3.3.6 Add catch clause extraction tests

### 17.3.4 Raise and Throw Extraction
- [ ] **Task 17.3.4 Pending**

Extract raise and throw expressions.

- [ ] 17.3.4.1 Implement `extract_raise/1` for raise expressions
- [ ] 17.3.4.2 Define `%RaiseExpression{exception: ..., message: ..., attributes: ...}` struct
- [ ] 17.3.4.3 Extract exception module being raised
- [ ] 17.3.4.4 Implement `extract_throw/1` for throw expressions
- [ ] 17.3.4.5 Define `%ThrowExpression{value: ..., location: ...}` struct
- [ ] 17.3.4.6 Add raise/throw extraction tests

**Section 17.3 Unit Tests:**
- [ ] Test try/rescue extraction
- [ ] Test try/catch extraction
- [ ] Test try/after extraction
- [ ] Test try/else extraction
- [ ] Test rescue exception pattern extraction
- [ ] Test catch type extraction
- [ ] Test raise expression extraction
- [ ] Test throw expression extraction

## 17.4 Call Graph Builder

This section implements the RDF builder for function calls and control flow.

### 17.4.1 Function Call Builder
- [ ] **Task 17.4.1 Pending**

Generate RDF triples for function calls.

- [ ] 17.4.1.1 Create `lib/elixir_ontologies/builders/call_graph_builder.ex`
- [ ] 17.4.1.2 Implement `build_function_call/3` generating call IRI
- [ ] 17.4.1.3 Generate `rdf:type core:FunctionCall` triple
- [ ] 17.4.1.4 Generate `core:callsFunction` linking to target function
- [ ] 17.4.1.5 Generate `core:calledFrom` linking to calling function
- [ ] 17.4.1.6 Add function call builder tests

### 17.4.2 Control Flow Builder
- [ ] **Task 17.4.2 Pending**

Generate RDF triples for control flow structures.

- [ ] 17.4.2.1 Implement `build_conditional/3` for if/unless/cond
- [ ] 17.4.2.2 Generate `rdf:type core:ConditionalExpression` triple
- [ ] 17.4.2.3 Generate `core:hasCondition` linking to condition expression
- [ ] 17.4.2.4 Generate `core:hasBranch` for each branch
- [ ] 17.4.2.5 Implement `build_case_expression/3` for case/with
- [ ] 17.4.2.6 Add control flow builder tests

### 17.4.3 Exception Builder
- [ ] **Task 17.4.3 Pending**

Generate RDF triples for exception handling.

- [ ] 17.4.3.1 Implement `build_try_expression/3` generating try IRI
- [ ] 17.4.3.2 Generate `rdf:type core:TryExpression` triple
- [ ] 17.4.3.3 Generate `core:hasRescueClause` for rescue clauses
- [ ] 17.4.3.4 Generate `core:hasCatchClause` for catch clauses
- [ ] 17.4.3.5 Generate `core:hasAfterClause` for after block
- [ ] 17.4.3.6 Add exception builder tests

**Section 17.4 Unit Tests:**
- [ ] Test function call RDF generation
- [ ] Test local vs remote call distinction
- [ ] Test control flow RDF generation
- [ ] Test conditional branch linking
- [ ] Test try/rescue/catch RDF generation
- [ ] Test call graph completeness
- [ ] Test SHACL validation of call graph
- [ ] Test integration with existing function builder

## Phase 17 Integration Tests

- [ ] **Phase 17 Integration Tests** (15+ tests)

- [ ] Test complete call graph extraction for complex module
- [ ] Test cross-module call graph
- [ ] Test control flow extraction accuracy
- [ ] Test exception handling coverage
- [ ] Test call graph RDF validates against shapes
- [ ] Test Pipeline integration with call extractors
- [ ] Test Orchestrator coordinates call graph builder
- [ ] Test pipe chain representation
- [ ] Test recursive function detection
- [ ] Test dynamic call handling
- [ ] Test receive expression in GenServer
- [ ] Test comprehension extraction
- [ ] Test nested control flow structures
- [ ] Test backward compatibility with existing extractors
- [ ] Test error handling for complex AST patterns
