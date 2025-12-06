# Phase 4: Structure Extractors (elixir-structure.ttl)

This phase implements extractors for Elixir-specific constructs: modules, functions, parameters, type specs, and macros.

## 4.1 Module Extractor

This section extracts module definitions including nested modules and module attributes.

### 4.1.1 Module Extractor Module
- [x] **Task 4.1.1 Complete**

Create comprehensive module extraction with all properties.

- [x] 4.1.1.1 Create `lib/elixir_ontologies/extractors/module.ex`
- [x] 4.1.1.2 Implement `Module.extract/2` accepting AST and context
- [x] 4.1.1.3 Extract `moduleName` from defmodule argument
- [x] 4.1.1.4 Detect `NestedModule` when parent module exists
- [x] 4.1.1.5 Extract `@moduledoc` as `docstring`
- [x] 4.1.1.6 Extract `alias` directives as `ModuleAlias`
- [x] 4.1.1.7 Extract `import` directives as `Import` with `:only`/`:except`
- [x] 4.1.1.8 Extract `require` directives as `Require`
- [x] 4.1.1.9 Extract `use` directives as `Use`
- [x] 4.1.1.10 Link via `aliasesModule`, `importsFrom`, `requiresModule`, `usesModule`
- [x] 4.1.1.11 Collect contained functions, macros, types via `containsFunction`, `containsMacro`, `containsType`
- [x] 4.1.1.12 Write module extraction tests (success: 61 tests - 14 doctests + 47 unit tests)

### 4.1.2 Module Attribute Extractor
- [x] **Task 4.1.2 Complete**

Extract module attributes with their various types.

- [x] 4.1.2.1 Create attribute extraction in module.ex or separate file
- [x] 4.1.2.2 Extract generic `ModuleAttribute` with `attributeName`, `attributeValue`
- [x] 4.1.2.3 Classify `@doc`, `@moduledoc`, `@typedoc` as DocAttribute subtypes
- [x] 4.1.2.4 Extract `@deprecated` as `DeprecatedAttribute` with message
- [x] 4.1.2.5 Extract `@since` as `SinceAttribute` with version
- [x] 4.1.2.6 Extract `@external_resource` as `ExternalResourceAttribute`
- [x] 4.1.2.7 Extract `@compile` as `CompileAttribute`
- [x] 4.1.2.8 Extract `@behaviour` as `implementsBehaviour` relationship
- [x] 4.1.2.9 Write attribute tests (success: 72 tests - 20 doctests + 52 unit tests)

**Section 4.1 Unit Tests:**
- [x] Test simple module extraction
- [x] Test nested module extraction with parentModule link
- [x] Test module with @moduledoc
- [x] Test module with alias/import/require/use
- [x] Test module attribute extraction
- [x] Test @behaviour extraction
- [x] Test @deprecated extraction

## 4.2 Function Extractor

This section extracts functions with full detail: clauses, heads, bodies, parameters, guards, and return expressions.

### 4.2.1 Function Definition Extractor
- [x] **Task 4.2.1 Complete**

Extract function definitions with identity and classification.

- [x] 4.2.1.1 Create `lib/elixir_ontologies/extractors/function.ex`
- [x] 4.2.1.2 Extract `functionName` from def/defp AST
- [x] 4.2.1.3 Calculate `arity` from parameter count
- [x] 4.2.1.4 Classify as `PublicFunction` (def) or `PrivateFunction` (defp)
- [x] 4.2.1.5 Detect `GuardFunction` (defguard/defguardp)
- [x] 4.2.1.6 Detect `DelegatedFunction` (defdelegate) with `delegatesTo`
- [x] 4.2.1.7 Generate path-based IRI: `Module/name/arity`
- [x] 4.2.1.8 Add `belongsTo` linking to module
- [x] 4.2.1.9 Extract `@doc` as `docstring`
- [x] 4.2.1.10 Extract `@spec` as `hasSpec` relationship
- [x] 4.2.1.11 Handle `@doc false` as `isDocFalse`
- [x] 4.2.1.12 Detect default parameters and set `minArity`
- [x] 4.2.1.13 Write function definition tests (success: 80 tests - 28 doctests + 52 unit tests)

### 4.2.2 Function Clause Extractor
- [x] **Task 4.2.2 Complete**

Extract function clauses with ordering and structure.

- [x] 4.2.2.1 Group consecutive def/defp with same name/arity as clauses
- [x] 4.2.2.2 Create `FunctionClause` for each clause
- [x] 4.2.2.3 Set `clauseOrder` (1-indexed)
- [x] 4.2.2.4 Link clauses via `hasClauses` as rdf:List (preserving order)
- [x] 4.2.2.5 Also link via `hasClause` for simple queries
- [x] 4.2.2.6 Extract `FunctionHead` with `hasHead`
- [x] 4.2.2.7 Extract `FunctionBody` with `hasBody`
- [x] 4.2.2.8 Handle bodyless clauses (protocol functions)
- [x] 4.2.2.9 Write clause extraction tests (success: 60 tests - 20 doctests + 40 unit tests)

### 4.2.3 Parameter Extractor
- [x] **Task 4.2.3 Complete**

Extract function parameters with patterns and types.

- [x] 4.2.3.1 Create `lib/elixir_ontologies/extractors/parameter.ex`
- [x] 4.2.3.2 Extract each parameter as `Parameter` instance
- [x] 4.2.3.3 Set `parameterPosition` (0-indexed)
- [x] 4.2.3.4 Extract `parameterName` when simple variable
- [x] 4.2.3.5 Detect `DefaultParameter` (\\\\) with `hasDefaultValue`
- [x] 4.2.3.6 Detect `PatternParameter` for destructuring parameters
- [x] 4.2.3.7 Link to pattern via `hasPatternExpression`
- [x] 4.2.3.8 Link to type via `hasTypeAnnotation` (from @spec) - deferred to TypeSpec extractor
- [x] 4.2.3.9 Create ordered parameter list via `hasParameters` (rdf:List)
- [x] 4.2.3.10 Write parameter tests (success: 73 tests - 22 doctests + 51 unit tests)

### 4.2.4 Return Expression Extractor
- [x] **Task 4.2.4 Complete**

Extract the return expression from function bodies.

- [x] 4.2.4.1 Identify last expression in function body
- [x] 4.2.4.2 Create `ReturnExpression` or link to expression type
- [x] 4.2.4.3 Link via `returnsExpression` from FunctionBody
- [x] 4.2.4.4 Handle single-expression functions (do: expr)
- [x] 4.2.4.5 Handle multi-expression bodies (do...end)
- [x] 4.2.4.6 Write return expression tests (success: 60 tests - 16 doctests + 44 unit tests)

### 4.2.5 Guard Extractor
- [x] **Task 4.2.5 Complete**

Extract guard clauses from function heads.

- [x] 4.2.5.1 Detect `when` clause in function head
- [x] 4.2.5.2 Create `GuardClause` linking to function head
- [x] 4.2.5.3 Extract guard expressions (may be combined with `and`/`or`)
- [x] 4.2.5.4 Link via `hasGuard` property
- [x] 4.2.5.5 Write guard extraction tests (success: 66 tests - 22 doctests + 44 unit tests)

**Section 4.2 Unit Tests:**
- [ ] Test simple public function extraction
- [ ] Test private function classification
- [ ] Test function with multiple clauses
- [ ] Test clause ordering preservation
- [ ] Test parameter extraction with positions
- [ ] Test default parameter detection
- [ ] Test pattern parameter extraction ({a, b} style)
- [ ] Test return expression identification
- [ ] Test guard clause extraction
- [ ] Test defdelegate extraction

## 4.3 Type Spec Extractor

This section extracts @type, @spec, @callback definitions.

### 4.3.1 Type Definition Extractor
- [x] **Task 4.3.1 Complete**

Extract type definitions (@type, @typep, @opaque).

- [x] 4.3.1.1 Create `lib/elixir_ontologies/extractors/type_definition.ex`
- [x] 4.3.1.2 Extract `@type` as `PublicType`
- [x] 4.3.1.3 Extract `@typep` as `PrivateType`
- [x] 4.3.1.4 Extract `@opaque` as `OpaqueType`
- [x] 4.3.1.5 Extract `typeName` and `typeArity`
- [x] 4.3.1.6 Extract type parameters as `TypeVariable`
- [x] 4.3.1.7 Parse type expression structure
- [x] 4.3.1.8 Write type definition tests (success: 60 tests - 20 doctests + 40 unit tests)

### 4.3.2 Function Spec Extractor
- [x] **Task 4.3.2 Complete**

Extract @spec with parameter types and return type.

- [x] 4.3.2.1 Extract `@spec` as `FunctionSpec`
- [x] 4.3.2.2 Link to function via `hasSpec`
- [x] 4.3.2.3 Extract parameter types as `hasParameterTypes` (rdf:List)
- [x] 4.3.2.4 Extract return type as `hasReturnType`
- [x] 4.3.2.5 Parse type expressions into TypeExpression subclasses
- [x] 4.3.2.6 Handle union types (|)
- [x] 4.3.2.7 Handle `when` clauses in specs
- [x] 4.3.2.8 Write spec extraction tests (success: 62 tests - 19 doctests + 43 unit tests)

### 4.3.3 Type Expression Parser
- [x] **Task 4.3.3 Complete**

Parse type expressions into appropriate TypeExpression subclasses.

- [x] 4.3.3.1 Parse `BasicType` (atom(), integer(), binary(), etc.)
- [x] 4.3.3.2 Parse `UnionType` (type1 | type2)
- [x] 4.3.3.3 Parse `TupleType` ({type1, type2})
- [x] 4.3.3.4 Parse `ListType` ([type])
- [x] 4.3.3.5 Parse `MapType` (%{key => value})
- [x] 4.3.3.6 Parse `FunctionType` ((args -> return))
- [x] 4.3.3.7 Parse `ParameterizedType` (Enumerable.t(element))
- [x] 4.3.3.8 Handle remote types (Module.type())
- [x] 4.3.3.9 Write type expression tests (success: 87 tests - 22 doctests + 65 unit tests)

**Section 4.3 Unit Tests:**
- [x] Test @type extraction
- [x] Test @typep and @opaque classification
- [x] Test @spec extraction with simple types
- [x] Test @spec with union types
- [x] Test @spec with complex nested types
- [x] Test type expression parsing for all TypeExpression subclasses

## 4.4 Macro Extractor

This section extracts macro definitions with their metaprogramming constructs.

### 4.4.1 Macro Definition Extractor
- [x] **Task 4.4.1 Complete**

Extract defmacro and defmacrop definitions.

- [x] 4.4.1.1 Create `lib/elixir_ontologies/extractors/macro.ex`
- [x] 4.4.1.2 Extract `defmacro` as `PublicMacro`
- [x] 4.4.1.3 Extract `defmacrop` as `PrivateMacro`
- [x] 4.4.1.4 Extract `macroName` and `macroArity`
- [x] 4.4.1.5 Detect hygiene settings (`Macro.escape`, `var!`)
- [x] 4.4.1.6 Set `isHygienic` property
- [x] 4.4.1.7 Extract macro clauses similar to functions
- [x] 4.4.1.8 Write macro extraction tests (success: 58 tests - 18 doctests + 40 unit tests)

### 4.4.2 Quote/Unquote Extractor
- [ ] **Task 4.4.2 Complete**

Extract metaprogramming constructs.

- [ ] 4.4.2.1 Detect `quote do...end` blocks
- [ ] 4.4.2.2 Create `QuotedExpression` with `quotesExpression`
- [ ] 4.4.2.3 Extract `quoteContext` option (:match, :guard)
- [ ] 4.4.2.4 Detect `unquote()` calls as `UnquoteExpression`
- [ ] 4.4.2.5 Detect `unquote_splicing()` as `UnquoteSplicingExpression`
- [ ] 4.4.2.6 Link via `unquotesValue`
- [ ] 4.4.2.7 Write quote/unquote tests (success: 8 tests)

**Section 4.4 Unit Tests:**
- [ ] Test defmacro extraction
- [ ] Test defmacrop classification
- [ ] Test macro arity calculation
- [ ] Test quote block detection
- [ ] Test unquote detection inside quote
- [ ] Test unquote_splicing detection

## Phase 4 Integration Tests

- [ ] Test full module extraction with functions, specs, and attributes
- [ ] Test extraction of GenServer module with callbacks
- [ ] Test multi-clause function extraction preserves order
- [ ] Test parameter-to-type linking via specs
- [ ] Test macro extraction in metaprogramming-heavy module
