# Phase 29: Function Call and Reference Expression Extraction

This phase implements extraction for function calls (remote and local), anonymous functions, module references, and the capture operator (&). Calls and references are the primary way Elixir code invokes behavior and creates abstractions.

## 29.1 Remote Call Expression Extraction

This section implements extraction for remote function calls (Module.function) which are the backbone of Elixir's namespacing and modularity.

### 29.1.1 Remote Call Detection
- [ ] 29.1.1.1 Implement `detect_remote_call/1` helper in ExpressionBuilder
- [ ] 29.1.1.2 Match `{{:., _, [module, function]}, _, args}` pattern
- [ ] 29.1.1.3 Match `{:., _, [module, function]}` pattern (no args)
- [ ] 29.1.1.4 Identify module expression (may be atom or alias)
- [ ] 29.1.1.5 Identify function name atom
- [ ] 29.1.1.6 Identify argument list
- [ ] 29.1.1.7 Extract arity from argument count

### 29.1.2 Remote Call Builder Implementation
- [ ] 29.1.2.1 Implement `build_remote_call/4` in ExpressionBuilder
- [ ] 29.1.2.2 Create type triple: `expr_iri a Core.RemoteCall`
- [ ] 29.1.2.3 Extract module name and store in `moduleName` property
- [ ] 29.1.2.4 Extract function name and store in `functionName` property
- [ ] 29.1.2.5 Extract arity and store in `arity` property
- [ ] 29.1.2.6 Create `refersToModule` object property linking to module IRI
- [ ] 29.1.2.7 Create `refersToFunction` object property linking to function IRI
- [ ] 29.1.2.8 Extract each argument expression recursively
- [ ] 29.1.2.9 Link arguments via `hasArgument` property (ordered)

### 29.1.3 Module Expression Extraction
- [ ] 29.1.3.1 Handle atom module: `Module.func()` → module is `:Module`
- [ ] 29.1.3.2 Handle alias module: `Alias.func()` → extract alias AST
- [ ] 29.1.3.3 Handle nested module: `Module.SubModule.func()`
- [ ] 29.1.3.4 Handle module from expression: `module().func()` (rare)
- [ ] 29.1.3.5 Extract module as expression when not simple atom
- [ ] 29.1.3.6 Link via `hasModuleExpression` property

**Section 29.1 Unit Tests:**
- [ ] Test remote call extraction for atom module
- [ ] Test remote call extraction for alias module
- [ ] Test remote call extraction for nested module
- [ ] Test remote call extraction captures function name
- [ ] Test remote call extraction captures arity
- [ ] Test remote call extraction extracts arguments
- [ ] Test remote call extraction handles no arguments
- [ ] Test remote call extraction handles complex arguments

## 29.2 Local Call Expression Extraction

This section implements extraction for local function calls (function_name) which invoke functions within the same module.

### 29.2.1 Local Call Detection
- [ ] 29.2.1.1 Implement `detect_local_call/1` helper in ExpressionBuilder
- [ ] 29.2.1.2 Match `{name, _, args}` where name is atom and args is list
- [ ] 29.2.1.3 Exclude remote calls (already handled)
- [ ] 29.2.1.4 Exclude control flow constructs (if, case, etc.)
- [ ] 29.2.1.5 Identify function name
- [ ] 29.2.1.6 Identify argument list

### 29.2.2 Local Call Builder Implementation
- [ ] 29.2.2.1 Implement `build_local_call/4` in ExpressionBuilder
- [ ] 29.2.2.2 Create type triple: `expr_iri a Core.LocalCall`
- [ ] 29.2.2.3 Extract function name and store in `functionName` property
- [ ] 29.2.2.4 Extract arity and store in `arity` property
- [ ] 29.2.2.5 Create `refersToFunction` object property
- [ ] 29.2.2.6 Note: Local calls reference functions in same module
- [ ] 29.2.2.7 Extract each argument expression recursively
- [ ] 29.2.2.8 Link arguments via `hasArgument` property (ordered)

**Section 29.2 Unit Tests:**
- [ ] Test local call extraction captures function name
- [ ] Test local call extraction captures arity
- [ ] Test local call extraction extracts arguments
- [ ] Test local call extraction handles no arguments
- [ ] Test local call extraction handles complex arguments
- [ ] Test local call is distinguished from remote call

## 29.3 Anonymous Function Call Extraction

This section implements extraction for calls to anonymous functions (stored in variables).

### 29.3.1 Anonymous Function Call Detection
- [ ] 29.3.1.1 Match `{var, _, args}` where var is variable expression
- [ ] 29.3.1.2 Match `{{:., _, [var, func]}, _, args}` for captured calls
- [ ] 29.3.1.3 Identify anonymous function variable
- [ ] 29.3.1.4 Distinguish from local calls
- [ ] 29.3.1.5 Identify arguments

### 29.3.2 Anonymous Function Call Builder
- [ ] 29.3.2.1 Implement `build_anon_call/4` in ExpressionBuilder
- [ ] 29.3.2.2 Create type triple: `expr_iri a Core.AnonymousFunctionCall`
- [ ] 29.3.2.3 Extract function variable expression
- [ ] 29.3.2.4 Link via `hasFunctionExpression` property
- [ ] 29.3.2.5 Extract each argument expression recursively
- [ ] 29.3.2.6 Link arguments via `hasArgument` property (ordered)
- [ ] 29.3.2.7 Handle dynamic function calls: `apply(mod, fun, args)`

**Section 29.3 Unit Tests:**
- [ ] Test anonymous function call extraction
- [ ] Test anonymous function call captures function variable
- [ ] Test anonymous function call extracts arguments
- [ ] Test anonymous function call handles no arguments
- [ ] Test anonymous function call handles captured calls

## 29.4 Capture Operator Extraction

This section implements extraction for the capture operator (&) which creates anonymous function references.

### 29.4.1 Capture Operator Detection
- [ ] 29.4.1.1 Implement `detect_capture/1` helper in ExpressionBuilder
- [ ] 29.4.1.2 Match `:&1`, `:&2`, etc. (captured arguments)
- [ ] 29.4.1.3 Match `:&Mod.fun/arity` (function reference)
- [ ] 29.4.1.4 Match `:&Mod.fun` (function reference, arity inferred)
- [ ] 29.4.1.5 Match `:&local_fun/arity` (local function reference)
- [ ] 29.4.1.6 Identify capture type

### 29.4.2 Argument Capture Extraction
- [ ] 29.4.2.1 Implement `build_arg_capture/4` for `&N` captures
- [ ] 29.4.2.2 Create type triple: `expr_iri a Core.CaptureOperator`
- [ ] 29.4.2.3 Create `operatorSymbol` triple with "&"
- [ ] 29.4.2.4 Extract argument index: 1, 2, 3, etc.
- [ ] 29.4.2.5 Create `argumentIndex` property
- [ ] 29.4.2.6 Document: Captures Nth argument in anonymous function

### 29.4.3 Function Reference Capture Extraction
- [ ] 29.4.3.1 Implement `build_fun_capture/4` for `&Mod.fun/arity`
- [ ] 29.4.3.2 Create type triple: `expr_iri a Core.CaptureOperator`
- [ ] 29.4.3.3 Extract module name (if present)
- [ ] 29.4.3.4 Extract function name
- [ ] 29.4.3.5 Extract arity (explicit or inferred)
- [ ] 29.4.3.6 Create `refersToModule` property if remote
- [ ] 29.4.3.7 Create `refersToFunction` property
- [ ] 29.4.3.8 Handle local captures: `&local_func/arity`

**Section 29.4 Unit Tests:**
- [ ] Test capture operator extraction for &1
- [ ] Test capture operator extraction for &2, &3, etc.
- [ ] Test capture operator extraction for &Mod.fun/arity
- [ ] Test capture operator extraction for &Mod.fun
- [ ] Test capture operator extraction for &local_func/arity
- [ ] Test capture operator extraction distinguishes types
- [ ] Test capture operator extraction captures arity

## 29.5 Module Reference Extraction

This section implements extraction for module references and aliases used in expressions.

### 29.5.1 Module Alias Detection
- [ ] 29.5.1.1 Match `{:__aliases__, _, parts}` module alias AST
- [ ] 29.5.1.2 Extract alias parts: `[:Module, :SubModule]`
- [ ] 29.5.1.3 Reconstruct full module name
- [ ] 29.5.1.4 Handle single-part aliases: `[:Module]`
- [ ] 29.5.1.5 Handle multi-part aliases: `[:Module, :Sub, :Deep]`

### 29.5.2 Module Reference Builder
- [ ] 29.5.2.1 Implement `build_module_reference/4` in ExpressionBuilder
- [ ] 29.5.2.2 Create type triple: `expr_iri a Core.ModuleReference`
- [ ] 29.5.2.3 Extract full module name
- [ ] 29.5.2.4 Create `moduleName` property
- [ ] 29.5.2.5 Create `refersToModule` object property
- [ ] 29.5.2.6 Link to module IRI in RDF
- [ ] 29.5.2.7 Handle Elixir module prefix (implicit `Elixir.`)

**Section 29.5 Unit Tests:**
- [ ] Test module reference extraction for simple alias
- [ ] Test module reference extraction for nested alias
- [ ] Test module reference extraction captures module name
- [ ] Test module reference extraction links to module
- [ ] Test module reference extraction handles Elixir prefix

## 29.6 Named Function Reference Extraction

This section implements extraction for references to named functions (not calls, just references).

### 29.6.1 Function Reference Detection
- [ ] 29.6.1.1 Detect function references in expressions
- [ ] 29.6.1.2 Match `&Mod.fun/arity` as reference (already captured)
- [ ] 29.6.1.3 Detect function name atoms used as values
- [ ] 29.6.1.4 Distinguish from function calls

### 29.6.2 Function Reference Builder
- [ ] 29.6.2.1 Implement `build_function_reference/4` in ExpressionBuilder
- [ ] 29.6.2.2 Create type triple: `expr_iri a Core.FunctionReference`
- [ ] 29.6.2.3 Extract module (if remote)
- [ ] 29.6.2.4 Extract function name
- [ ] 29.6.2.5 Extract arity (if known)
- [ ] 29.6.2.6 Create `refersToFunction` object property
- [ ] 29.6.2.7 Handle anonymous function references

**Section 29.6 Unit Tests:**
- [ ] Test function reference extraction for remote function
- [ ] Test function reference extraction for local function
- [ ] Test function reference extraction captures arity
- [ ] Test function reference extraction links to function
- [ ] Test function reference is distinguished from call

## 29.7 Call Nesting and Complexity

This section ensures that the call and reference extraction system handles nested calls and complex scenarios.

### 29.7.1 Nested Call Support
- [ ] 29.7.1.1 Test nested remote calls: `Mod.fun(Other.fun(x))`
- [ ] 29.7.1.2 Test calls within blocks
- [ ] 29.7.1.3 Test calls within control flow (if, case, etc.)
- [ ] 29.7.1.4 Test chained calls: `Mod.fun(x) |> Other.func()`
- [ ] 29.7.1.5 Verify nested call IRIs follow hierarchy

### 29.7.2 Complex Call Scenarios
- [ ] 29.7.2.1 Test calls with complex argument expressions
- [ ] 29.7.2.2 Test calls with spread operators
- [ ] 29.7.2.3 Test calls with default arguments (in definition)
- [ ] 29.7.2.4 Test calls with keyword arguments
- [ ] 29.7.2.5 Verify extraction preserves call semantics

**Section 29.7 Unit Tests:**
- [ ] Test nested call extraction creates correct hierarchy
- [ ] Test call extraction handles complex arguments
- [ ] Test call extraction handles keyword arguments
- [ ] Test call extraction within pipe operator
- [ ] Test call extraction preserves call semantics

## Phase 29 Integration Tests

- [ ] Test complete call extraction: remote, local, anonymous, capture
- [ ] Test remote call extraction with full arguments
- [ ] Test local call extraction within modules
- [ ] Test anonymous function call extraction
- [ ] Test capture operator extraction for all types
- [ ] Test module reference extraction
- [ ] Test nested call extraction
- [ ] Test SPARQL queries find calls by type
- [ ] Test SPARQL queries find calls by module/function
- [ ] Test SPARQL queries navigate call arguments
- [ ] Test call extraction in light mode (backward compat)
- [ ] Test call extraction in full mode (full expression tree)

**Integration Test Summary:**
- 12 integration tests covering all call and reference types
- Tests verify call extraction completeness and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/call_expression_test.exs`
