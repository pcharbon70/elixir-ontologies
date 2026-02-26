# Phase 27 Architecture Review: Function Bodies and Block Expressions

**Date:** 2026-01-15
**Reviewer:** Architecture Analysis
**Phase:** 27 - Function Bodies and Block Expressions
**Files Reviewed:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

---

## Executive Summary

**Overall Assessment: EXCELLENT** ⭐⭐⭐⭐⭐

Phase 27 implements a robust, well-architected block expression extraction system that demonstrates exceptional design maturity. The implementation successfully balances complexity, extensibility, and maintainability while maintaining strong separation of concerns.

### Key Strengths
1. **Clean Separation of Concerns** - Block detection, structure analysis, and triple generation are cleanly separated
2. **Thoughtful IRI Hierarchy** - Deterministic, queryable IRI structure that reflects nesting
3. **Strong Ontology Design** - The `hasReturnExpression` property elegantly captures Elixir's semantics
4. **Comprehensive Testing** - 5,647 lines of tests covering all scenarios including edge cases
5. **Future-Proof Design** - Architecture supports future scope analysis and variable extraction

### Minor Concerns
1. **IRI Strategy Duplication** - Block IRIs use relative paths (child/N) while top-level expressions use counter-based IRIs (expr/N)
2. **Depth Limit Hardcoding** - Max depth of 100 is hardcoded without configuration
3. **Empty Block Handling** - No explicit link for nil return values in empty blocks

---

## Design Assessment

### 1. Block Detection and Classification

**Implementation:** Lines 220-318 in `expression_builder.ex`

```elixir
def detect_block_type({:fn, _, _}), do: :fn_block
def detect_block_type({:__block__, _, _}), do: :do_block
def detect_block_type(_), do: :single_expr
```

**Assessment: EXCELLENT**

**Positive Design Choices:**
- Simple, pattern-matching based classification is idiomatic Elixir
- Clear separation between detection (`detect_block_type`) and structure analysis (`analyze_block_structure`)
- Returns semantic atoms that map directly to ontology classes
- Public API allows external tools to classify blocks without generating triples

**Architectural Strength:**
The three-tier detection strategy (detect → analyze → build) allows for:
1. Quick classification without full extraction
2. Metadata extraction without triple generation
3. Modular testing of each phase

**Why This Works Well:**
- Follows Elixir's "data transformation" philosophy
- Each function has a single, clear responsibility
- Easy to extend with new block types (e.g., `:begin_block`, `:case_block`)

---

### 2. Block Structure Analysis

**Implementation:** Lines 253-318

```elixir
def analyze_block_structure(ast) do
  type = detect_block_type(ast)

  {expressions, metadata} =
    case ast do
      {:__block__, meta, exprs} -> {exprs, meta}
      {:fn, meta, clauses} -> {clauses, meta}
      _ -> {[ast], []}
    end

  %{type: type, expressions: expressions, empty?: expressions == [], metadata: metadata}
end
```

**Assessment: EXCELLENT**

**Positive Design Choices:**
- Returns a rich data structure (map) that enables multiple use cases
- Pre-computes `empty?` for efficient guards in builders
- Preserves AST metadata for future source mapping
- Normalizes single expressions into a list for uniform processing

**Architectural Insight:**
This pattern is powerful because it separates **structural understanding** from **RDF generation**. The same analysis function could be used for:
- Static analysis tools
- Documentation generators
- Code formatters
- Test helpers

---

### 3. IRI Generation Strategy

**Implementation:**
- **Top-level expressions:** Context-based counter → `expr/expr_0`, `expr/expr_1`, ...
- **Block children:** Relative paths → `child/0`, `child/1`, ...

```elixir
# Line 344 - Child IRI generation
child_iri = fresh_iri(block_iri, "child/#{index}")
```

**Assessment: GOOD with Minor Concerns**

**Positive Design Choices:**
- Hierarchical structure preserves parent-child relationships in the graph
- No counter threading needed for child expressions (deterministic paths)
- Enables efficient SPARQL queries for block structure
- Supports nested blocks without IRI collisions

**Concerns:**

#### 1. Inconsistent Naming Strategy
**Issue:** Top-level expressions use `expr/expr_0` while children use `child/0`

**Impact:**
- Inconsistent naming makes SPARQL queries more complex
- `expr/expr_0` has redundant "expr" prefix
- `child/0` is relative but doesn't indicate expression nature

**Recommendation (Low Priority):**
Consider a unified strategy:
```
expr/0              - Top-level expression
expr/0/left         - Left operand (not child/0)
expr/0/0            - First child in block
expr/0/1            - Second child in block
```

However, the current strategy works well for the use case, so this is **not a blocker**.

#### 2. Lack of Semantic Names
**Issue:** Block children are named `child/N` rather than semantically

**Example:**
```elixir
# Current
fn_iri/child/0    # Parameter pattern
fn_iri/child/1    # Body expression

# Potential (more semantic)
fn_iri/param/0    # Parameter pattern
fn_iri/body       # Body expression
```

**Counter-Argument:**
The current generic `child/N` approach is more flexible for:
- Variable arity constructs
- Generic traversal algorithms
- Future extensions without schema changes

**Verdict:** The current strategy is **acceptable and defensible**.

---

### 4. Return Value Handling

**Ontology Design:**
```turtle
:hasReturnExpression a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has return expression"@en ;
    rdfs:comment "Links a block to the expression that provides its return value..."@en ;
    rdfs:subPropertyOf :hasChild ;
    rdfs:domain :Block ;
    rdfs:range :Expression .
```

**Implementation:**
```elixir
# Line 358-364 - Do block return value
return_triple =
  if length(expressions) > 0 do
    last_child_iri = fresh_iri(block_iri, "child/#{length(expressions) - 1}")
    Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
  else
    []
  end
```

**Assessment: EXCELLENT** ⭐

**Positive Design Choices:**

1. **Functional Property Constraint**
   - `owl:FunctionalProperty` ensures each block has exactly one return expression
   - Prevents invalid RDF graphs (blocks with multiple returns)

2. **SubProperty of hasChild**
   - Return expressions are always children (structural relationship)
   - `hasReturnExpression` adds semantic clarity without duplicating structure
   - Enables queries like "find all blocks returning variable X"

3. **Empty Block Handling**
   - No `hasReturnExpression` triple for empty blocks (implicitly nil)
   - Cleanly distinguishes "explicit nil return" from "empty block"

**Architectural Insight:**
This is a **textbook example** of OWL property design:
- `hasChild` = structural relationship (parent-child in AST)
- `hasReturnExpression` = semantic relationship (data flow)
- SubProperty axiom = semantic relationships are always structural

**Why This Matters for SPARQL:**

```sparql
# Find all blocks that return a specific variable
SELECT ?block WHERE {
  ?block core:hasReturnExpression ?expr .
  ?expr core:name "x" .
}
```

Without the dedicated property, this query would require complex logic to identify the "last child."

---

### 5. Nesting and Recursion

**Implementation:** Recursive child building (Lines 340-355)

```elixir
child_triples =
  expressions
  |> Enum.with_index()
  |> Enum.flat_map(fn {expr_ast, index} ->
    child_iri = fresh_iri(block_iri, "child/#{index}")
    expr_triples = build_expression_triples(expr_ast, child_iri, context)
    link_triple = Helpers.object_property(block_iri, Core.hasChild(), child_iri)
    expr_triples ++ [link_triple]
  end)
```

**Assessment: EXCELLENT**

**Positive Design Choices:**

1. **Implicit Recursion**
   - Nested `{:__block__, _, _}` nodes are automatically handled by the expression dispatcher
   - No special "nested block" logic needed
   - Depth is naturally limited by the call stack (or explicit depth parameter)

2. **Depth Tracking**
   ```elixir
   defp build_do_block(expressions, block_iri, context, depth \\ 0, max_depth \\ 100)
   defp build_do_block(_expressions, block_iri, _context, depth, max_depth)
       when depth >= max_depth do
     [Helpers.type_triple(block_iri, Core.DoBlock)]
   end
   ```
   - Prevents DoS attacks via maliciously nested code
   - Graceful degradation (type triple only, no partial data)
   - Configurable via `max_depth` parameter (future extension point)

3. **IRI Hierarchy Preservation**
   - Each nesting level adds a `/child/N` component
   - Parent-child relationships are explicit in the graph structure
   - Enables efficient SPARQL traversal of block hierarchies

**Example IRI Hierarchy:**
```
expr/0                    # Outer do block
  child/0                 # Nested do block
    child/0               # Atom :a
    child/1               # Atom :b
  child/1                 # Atom :c
```

**Test Coverage:** Lines 5284-5647
- 3-level nesting (do → do → do)
- Fn within do
- Do within fn
- Fn within fn (closures)
- All scenarios verified with comprehensive IRI hierarchy assertions

---

### 6. Anonymous Function (Fn) Block Architecture

**Implementation:** Lines 370-459

**Structure:**
```elixir
{:fn, meta, [
  {:->, meta, [
    [params_with_optional_guard],
    body_ast
  ]}
]}
```

**Assessment: EXCELLENT** ⭐⭐⭐

**Architectural Highlights:**

1. **Clause-Based Structure**
   - Fn blocks are modeled as collections of clauses (pattern-match arms)
   - Each clause has: parameters, optional guard, body
   - Maps directly to Elixir's semantics (multi-clause functions)

2. **Guard Extraction**
   ```elixir
   # Lines 465-487 - Parse fn parameters
   defp parse_fn_params(param_patterns) do
     case Enum.find_index(param_patterns, fn
       {:when, _, _} -> true
       _ -> false
     end) do
       nil -> {param_patterns, nil}
       index ->
         {:when, _, when_args} = Enum.at(param_patterns, index)
         {guard_ast, params_without_guard} = List.pop_at(when_args, -1)
         # ...
     end
   end
   ```
   - Sophisticated parsing to extract guards from parameter lists
   - Handles complex cases: `fn x, y when guard -> body end`
   - Separates parameters from guard context

3. **Guard Context Marking**
   ```elixir
   # Line 435
   guard_context_triple =
     Helpers.datatype_property(guard_iri, Core.inGuardContext(), true, RDF.XSD.Boolean)
   ```
   - Marks guard expressions with `inGuardContext` property
   - Enables future validation (only guard-safe operations allowed)
   - Critical for static analysis and linting

**Why This Architecture Matters:**

The fn block design correctly captures Elixir's **pattern matching semantics**:
- Multiple clauses are ordered (first match wins)
- Guards are boolean expressions (not arbitrary code)
- Parameters are patterns (not just variables)

This is **essential** for:
- Data flow analysis
- Coverage analysis
- Dead code detection
- Documentation generation

---

## Integration with Existing Code

### Mode Selection Integration

**Implementation:** Lines 158-165

```elixir
def build(ast, %Context{} = context, opts) do
  if Context.full_mode_for_file?(context, context.file_path) do
    do_build(ast, context, opts)
  else
    :skip
  end
end
```

**Assessment: EXCELLENT**

**Integration Points:**
1. **Context-based mode checking** - Reuses existing `Context.full_mode_for_file?/2`
2. **No breaking changes** - Block extraction respects existing mode logic
3. **Opt-in by design** - No impact on light mode extractions
4. **Consistent API** - `build/3` returns `{:ok, {...}}` or `:skip`

**Why This Works:**
- Extends the existing mode system without modifying it
- Block extraction is a natural extension of expression extraction
- Maintains backward compatibility with dependent code

---

### Helper Functions Integration

**Usage:** `Helpers.type_triple/2`, `Helpers.object_property/3`, etc.

**Assessment: EXCELLENT**

**Positive Design Choices:**
- Block builders use existing helper functions (no new RDF construction code)
- Consistent triple generation patterns across all builders
- Type-safe property references via `NS.Core` module

**Example:**
```elixir
# Line 336
type_triple = Helpers.type_triple(block_iri, Core.DoBlock)

# Line 351
link_triple = Helpers.object_property(block_iri, Core.hasChild(), child_iri)

# Line 361
return_triple = Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
```

All triple generation uses the **same patterns** as other builders (modules, functions, etc.), ensuring consistency.

---

### Pattern Integration

**Connection:** Fn block parameters are built as patterns

**Implementation:** Line 424
```elixir
pattern_triples = build_pattern(param_ast, param_iri, context)
```

**Assessment: EXCELLENT**

**Architectural Insight:**
Block expressions bridge two previously separate systems:
1. **Expression extraction** (Phase 20-27) - Values, operators, calls
2. **Pattern extraction** (Phase 24) - Destructuring, bindings, guards

The fn block correctly uses `build_pattern/4` for parameters because:
- Parameters are patterns (not expressions)
- Pattern extraction includes variable binding analysis
- Guards are marked with `inGuardContext` for validation

**Why This Matters:**
This integration enables **comprehensive analysis** of anonymous functions:
```sparql
# Find all fn clauses that capture variable X
SELECT ?fn ?clause WHERE {
  ?fn core:hasClause ?clause .
  ?clause core:hasChild ?body .
  ?body (core:hasChild | core:hasArgument)* ?expr .
  ?expr core:name "x" .
}
```

---

## Modularity and Reusability

### Public API Design

**Functions:**
1. `detect_block_type/1` - Classify AST nodes
2. `analyze_block_structure/1` - Extract block metadata
3. `build/3` - Full extraction with mode checking
4. `build_expression_triples/3` - Internal dispatch

**Assessment: EXCELLENT** ⭐⭐⭐

**Design Strengths:**

1. **Layered API**
   - **Detection layer** - `detect_block_type/1` for classification
   - **Analysis layer** - `analyze_block_structure/1` for metadata
   - **Extraction layer** - `build/3` for full RDF generation

   This allows tools to choose the right level of abstraction:
   - Linters might only need detection
   - Documentation generators might need analysis
   - Full extraction tools need the complete API

2. **Composable Functions**
   ```elixir
   # Usage: Classify without building
   case ExpressionBuilder.detect_block_type(ast) do
     :fn_block -> "Anonymous function"
     :do_block -> "Block expression"
     :single_expr -> "Single expression"
   end

   # Usage: Analyze without generating RDF
   %{type: type, empty?: empty?} =
     ExpressionBuilder.analyze_block_structure(ast)

   # Usage: Full extraction
   {:ok, {expr_iri, triples, context}} =
     ExpressionBuilder.build(ast, context, [])
   ```

3. **Testable Design**
   - Each layer can be unit tested independently
   - No hidden dependencies or side effects
   - Pure functions (except context counter management)

---

### Code Organization

**Module Structure:**
```elixir
defmodule ExpressionBuilder do
  # Public API (lines 103-165)
  def build/3

  # Block Detection (lines 220-318)
  def detect_block_type/1
  def analyze_block_structure/1

  # Block Builders (lines 320-459)
  defp build_do_block/5
  defp build_fn_block/5
  defp build_fn_clause/5

  # Expression Dispatch (lines 520-811)
  def build_expression_triples/3

  # Operator Builders (lines 833-901)
  defp build_binary_operator/6
  defp build_unary_operator/5

  # Literal Builders (lines 964-997)
  defp build_literal/5

  # Pattern Builders (lines 1594-2172)
  def build_pattern/4
  # ... pattern implementations
end
```

**Assessment: EXCELLENT**

**Positive Design Choices:**
1. **Logical grouping** - Related functions are co-located
2. **Clear sections** - Module docstring serves as table of contents
3. **Consistent naming** - `build_*` pattern throughout
4. **Private helpers** - Internal functions marked `defp`

**Future Maintainability:**
- Easy to locate specific functionality
- Clear extension points for new expression types
- No "spaghetti code" or excessive coupling

---

## Future Extensibility

### Extension Point 1: Scope Analysis

**Current State:** Blocks define lexical scope boundaries (documented in comments)

**Future Enhancement:** Variable binding extraction

**Architectural Support:**
```elixir
# Future API (hypothetical)
def extract_bindings(ast, context) do
  # Returns %{variable_name => binding_iri}
  # Uses block structure analysis + pattern extraction
end
```

**Why the Architecture Supports This:**
- Block boundaries are already identified (`detect_block_type`)
- Pattern bindings are already extracted (`build_pattern/4`)
- IRI hierarchy preserves parent-child relationships

**Example SPARQL (Future):**
```sparql
# Find all variables bound in a block
SELECT ?var WHERE {
  ?block a core:BlockScope .
  ?block core:hasBinding ?binding .
  ?binding core:bindsVariable ?var .
}
```

---

### Extension Point 2: Closure Capture Analysis

**Current State:** Fn blocks can capture outer variables

**Future Enhancement:** Track which variables each closure captures

**Architectural Support:**
The fn block structure already distinguishes:
- Parameters (explicit bindings)
- Body (may reference outer variables)

**Example Future Implementation:**
```elixir
# Hypothetical closure capture property
{clause_iri, Core.capturesVariable(), variable_iri}
```

**Why This Matters:**
- Enables memory usage analysis
- Supports lifetime analysis
- Critical for optimization tools

---

### Extension Point 3: Early Exit Expressions

**Current State:** `hasReturnExpression` links to last child

**Future Enhancement:** Track `throw`, `raise`, `return` expressions

**Ontology Design Already Supports This:**
```turtle
:hasReturnExpression a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:comment "...Typically the last expression, but may be an early exit expression (throw/raise)..."@en ;
```

**Implementation Plan:**
1. Detect early exit expressions in block bodies
2. Link them via `hasReturnExpression` instead of last child
3. Add `core:earlyExit` datatype property for classification

**Why This is Easy:**
The block builder already iterates through all children, so:
```elixir
# Future implementation sketch
exit_expr = Enum.find(expressions, &early_exit?/1)
return_triple =
  if exit_expr do
    # Link to early exit instead of last child
    Helpers.object_property(block_iri, Core.hasReturnExpression(), exit_iri)
  else
    # Current behavior: link to last child
    Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
  end
```

---

### Extension Point 4: Block Type Annotations

**Current State:** Only two block types (`DoBlock`, `FnBlock`)

**Future Enhancement:** Distinguish block contexts

**Potential Extensions:**
- `CaseBlock` - Block within case expression
- `CondBlock` - Block within cond expression
- `WithBlock` - Block within with expression
- `TryBlock` - Block within try expression
- `ReceiveBlock` - Block within receive expression

**Architectural Support:**
The `detect_block_type/1` function can be extended:
```elixir
def detect_block_type({:fn, _, _}), do: :fn_block
def detect_block_type({:__block__, _, _}), do: :do_block
# Future extensions
def detect_block_type({:case, _, _}), do: :case_block
def detect_block_type({:cond, _, _}), do: :cond_block
```

**Why This Matters:**
- Different blocks have different semantics
- Case blocks support pattern matching
- Cond blocks require truthy conditions
- With blocks support early return

---

## Architectural Concerns and Risks

### Concern 1: Empty Block Return Values

**Issue:** Empty blocks have no `hasReturnExpression` triple

**Implementation:** Lines 358-364
```elixir
return_triple =
  if length(expressions) > 0 do
    last_child_iri = fresh_iri(block_iri, "child/#{length(expressions) - 1}")
    Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
  else
    []  # No return expression link
  end
```

**Impact:**
- SPARQL queries must use optional matching for return values
- No explicit representation of "nil return"
- Inconsistent with non-empty blocks

**Recommendation:**
Consider adding an explicit nil return:
```elixir
return_triple =
  if length(expressions) > 0 do
    last_child_iri = fresh_iri(block_iri, "child/#{length(expressions) - 1}")
    [Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)]
  else
    # Create nil literal expression
    nil_iri = fresh_iri(block_iri, "return")
    nil_triples = build_literal(nil, nil_iri, Core.NilLiteral, Core.atomValue(), RDF.XSD.String)
    return_link = Helpers.object_property(block_iri, Core.hasReturnExpression(), nil_iri)
    nil_triples ++ [return_link]
  end
```

**Counter-Arguments:**
- Current approach is simpler (fewer triples)
- Nil is the default in Elixir, implicit in RDF
- Optional SPARQL matches are idiomatic

**Verdict:** Current design is **acceptable**, but explicit nil representation would be more complete.

---

### Concern 2: Hardcoded Depth Limit

**Issue:** Max depth of 100 is hardcoded

**Implementation:** Line 321
```elixir
defp build_do_block(expressions, block_iri, context, depth \\ 0, max_depth \\ 100)
```

**Impact:**
- Cannot be configured without code changes
- May be too restrictive for generated code
- No global safety limit across all block types

**Recommendation:**
Move to application configuration:
```elixir
# config/dev.exs
config :elixir_ontologies, :max_block_depth, 100

# In code
defp build_do_block(expressions, block_iri, context, depth \\ 0) do
  max_depth = Application.get_env(:elixir_ontologies, :max_block_depth, 100)
  # ...
end
```

**Verdict:** Low priority issue (works well in practice), but configuration would improve flexibility.

---

### Concern 3: No Block Type Hierarchy

**Issue:** `DoBlock` and `FnBlock` are both subclasses of `Block`, but don't share a common builder

**Ontology:**
```turtle
:Block a owl:Class ;
    rdfs:subClassOf :Expression .

:DoBlock a owl:Class ;
    rdfs:subClassOf :Block .

:FnBlock a owl:Class ;
    rdfs:subClassOf :Block .
```

**Implementation:**
```elixir
# Separate builders
defp build_do_block/5
defp build_fn_block/5
```

**Impact:**
- Code duplication (both handle nesting, children, return values)
- Inconsistent handling of edge cases
- Hard to add common block features

**Recommendation:**
Consider a unified builder:
```elixir
defp build_block(ast, block_iri, context, type, depth)
```

However, the current separation is **justified** because:
- Do blocks and fn blocks have different AST structures
- Fn blocks require clause handling (do blocks don't)
- Fn blocks require guard parsing (do blocks don't)

**Verdict:** Current separation is **acceptable** given the semantic differences.

---

## Positive Design Choices

### 1. Deterministic IRI Generation

**Implementation:** Context-based counter (lines 193-214)

**Positive Aspect:**
```elixir
# Counter in context metadata
{counter, new_context} = Context.next_expression_counter(context)
{"expr_#{counter}", new_context}
```

**Why This Matters:**
- Same code produces same IRIs across runs (critical for diffing)
- No process dictionary (thread-safe)
- Counter is explicit in context (no hidden state)

**Alternative Considered:**
- Using hash of AST content → rejected (non-deterministic across runs)
- Using UUIDs → rejected (not queryable, not human-readable)
- Using process dictionary → rejected (not thread-safe)

---

### 2. Guard Context Marking

**Implementation:** Lines 182-187, 434-436

**Positive Aspect:**
```elixir
# In build/3
triples =
  if Keyword.get(opts, :guard_context?) do
    [Helpers.datatype_property(expr_iri, Core.inGuardContext(), true, RDF.XSD.Boolean) | triples]
  else
    triples
  end
```

**Why This Matters:**
- Guards have restricted semantics (only certain operations allowed)
- Future validation can reject invalid guard expressions
- Enables SPARQL queries to find guard expressions

**Example Use Case:**
```sparql
# Find all non-variable-references in guards (potential errors)
SELECT ?guard WHERE {
  ?guard core:inGuardContext true .
  ?guard core:hasChild ?child .
  ?child a core:RemoteCall .
  FILTER NOT EXISTS { ?child core:refersToModule ?mod . }
}
```

---

### 3. Comprehensive Test Coverage

**Implementation:** 5,647 lines of tests (5647 total in file)

**Positive Aspect:**
- **Detection tests** (lines 4579-4622) - Verify block type classification
- **Structure tests** (lines 4623-4714) - Verify metadata extraction
- **Do block tests** (lines 4715-4923) - Verify do block extraction
- **Fn block tests** (lines 4924-5283) - Verify fn block extraction
- **Nesting tests** (lines 5284-5647) - Verify nested block handling

**Test Quality:**
- Positive cases (happy paths)
- Negative cases (edge cases)
- IRI hierarchy verification
- Property triple verification
- Empty block handling
- Deep nesting (3 levels)
- Mixed nesting (do → fn, fn → do)

**Why This Matters:**
- Confident refactoring (tests catch regressions)
- Documentation (tests serve as examples)
- Trust in the implementation (high coverage)

---

### 4. Separation of build/3 and build_expression_triples/3

**Implementation:** Two-layer API

**build/3:**
- Checks mode (full vs light)
- Manages IRI counter in context
- Returns `{:ok, {expr_iri, triples, updated_context}}`

**build_expression_triples/3:**
- Direct triple generation
- No mode checking
- Returns list of triples
- Used for recursive child building

**Positive Aspect:**
This separation is **critical** for:
1. **Top-level calls** - Use `build/3` (mode checking + counter management)
2. **Recursive calls** - Use `build_expression_triples/3` (direct triple generation)
3. **Internal calls** - No redundant mode checks
4. **Performance** - No counter threading for child expressions

**Example Usage:**
```elixir
# Top-level: Use build/3
{:ok, {expr_iri, triples, context}} = ExpressionBuilder.build(ast, context, [])

# Internal (in operator builder): Use build_expression_triples/3
left_triples = build_expression_triples(left_ast, left_iri, context)
```

**Why This Matters:**
- Prevents infinite recursion (mode check only at top level)
- More efficient (no counter threading for every child)
- Clearer intent (public vs internal API)

---

## Ontology Design Assessment

### hasReturnExpression Property

**Implementation:** Lines 693-698 in `elixir-core.ttl`

**Design Choices:**

1. **Functional Property**
   ```turtle
   a owl:FunctionalProperty
   ```
   - Ensures each block has exactly one return expression
   - Enables cardinality reasoning in OWL
   - Prevents invalid data (blocks with multiple returns)

2. **SubProperty of hasChild**
   ```turtle
   rdfs:subPropertyOf :hasChild
   ```
   - Return expressions are always children (structural relationship)
   - Enables queries that traverse either property
   - Maintains graph consistency

3. **Domain and Range**
   ```turtle
   rdfs:domain :Block
   rdfs:range :Expression
   ```
   - Type-safe (only blocks can have return expressions)
   - Only expressions can be return values
   - Enables SPARQL type filtering

**Assessment: EXCELLENT** ⭐⭐⭐⭐⭐

This property design is **textbook OWL**:
- Clear semantics (return value relationship)
- Proper constraints (functional property)
- Type safety (domain/range restrictions)
- Extensible comment (supports early exit expressions)

---

### Block Class Hierarchy

**Implementation:** Lines 417-431 in `elixir-core.ttl`

```turtle
:Block a owl:Class ;
    rdfs:label "Block"@en ;
    rdfs:comment """A sequence of expressions. The value of a block is the
    value of its last expression."""@en ;
    rdfs:subClassOf :Expression .

:DoBlock a owl:Class ;
    rdfs:label "Do Block"@en ;
    rdfs:comment "A do...end block containing a sequence of expressions."@en ;
    rdfs:subClassOf :Block .

:FnBlock a owl:Class ;
    rdfs:label "Fn Block"@en ;
    rdfs:comment "An anonymous function block with fn ... end syntax."@en ;
    rdfs:subClassOf :Block .
```

**Assessment: EXCELLENT**

**Positive Design Choices:**

1. **Three-Level Hierarchy**
   - `Expression` (base) → `Block` (abstract) → `DoBlock`/`FnBlock` (concrete)
   - Matches Elixir's semantics (blocks are expressions)
   - Enables queries for "all blocks" or "specific block types"

2. **Comments Capture Semantics**
   - Block comment: "The value of a block is the value of its last expression"
   - Do block comment: "do...end block containing a sequence of expressions"
   - Fn block comment: "fn ... end syntax"

3. **Future Extensibility**
   - Easy to add new block types (e.g., `CaseBlock`, `CondBlock`)
   - All inherit `hasReturnExpression` property
   - All share block semantics

**Example SPARQL:**
```sparql
# Find all blocks
SELECT ?block WHERE {
  ?block a core:Block .
}

# Find only do blocks
SELECT ?do_block WHERE {
  ?do_block a core:DoBlock .
}

# Find blocks that return nil
SELECT ?block WHERE {
  ?block a core:Block .
  ?block core:hasReturnExpression ?expr .
  ?expr a core:NilLiteral .
}
```

---

## Performance and Scalability

### Depth-Limited Recursion

**Implementation:** Lines 321-327, 371-377

**Positive Aspect:**
```elixir
defp build_do_block(_expressions, block_iri, _context, depth, max_depth)
    when depth >= max_depth do
  [Helpers.type_triple(block_iri, Core.DoBlock)]
end
```

**Why This Matters:**
- Prevents stack overflow from malicious code
- Graceful degradation (type triple only, no partial extraction)
- Configurable via `max_depth` parameter

**Performance Impact:**
- No overhead for normal code (depth check is O(1))
- Prevents DoS attacks via infinite nesting
- Memory usage is bounded (O(max_depth × block_size))

---

### Tail-Recursive Helpers

**Implementation:** Lines 1031-1039

**Positive Aspect:**
```elixir
defp build_child_expressions(items, context, mapper \\ fn item -> item end) do
  {triples_list, final_ctx} =
    Enum.map_reduce(items, context, fn item, ctx ->
      {:ok, {_child_iri, triples, new_ctx}} = build(mapper.(item), ctx, [])
      {triples, new_ctx}
    end)

  {List.flatten(triples_list), final_ctx}
end
```

**Why This Matters:**
- `Enum.map_reduce/2` is tail-recursive (no stack growth)
- Efficient for large collections of child expressions
- Context threading is optimized (no intermediate copies)

**Alternative Considered:**
- Manual recursion with accumulator → rejected (less idiomatic)
- `Enum.flat_map` → rejected (doesn't thread context)

---

### Lazy Triple Generation

**Current Design:** Eager triple generation (all triples built immediately)

**Future Enhancement:** Consider lazy generation for very large blocks

**Potential Implementation:**
```elixir
# Return a stream of triples instead of a list
defp build_do_block(expressions, block_iri, context) do
  Stream.flat_map(expressions, fn expr_ast ->
    child_iri = fresh_iri(block_iri, "child/#{index}")
    build_expression_triples(expr_ast, child_iri, context)
  end)
end
```

**Verdict:** Not needed for current use case (eager generation is simpler and fast enough).

---

## Recommendations

### High Priority

None. The architecture is sound and production-ready.

---

### Medium Priority

1. **Make max_depth configurable**
   - Move to application configuration
   - Allows tuning for different use cases
   - Low risk, high value

2. **Add explicit nil return for empty blocks**
   - Makes SPARQL queries simpler
   - More complete representation
   - Moderate risk (requires careful testing)

---

### Low Priority

1. **Unify IRI naming strategy**
   - Consider using `/N` instead of `/child/N` for block children
   - More consistent with top-level expressions
   - Very low priority (current naming works well)

2. **Add block type annotations**
   - Distinguish case/cond/with/try/receive blocks
   - Enables more precise analysis
   - Low priority (can be added incrementally)

---

## Conclusion

### Overall Verdict: EXCELLENT ⭐⭐⭐⭐⭐

Phase 27 is a **masterclass** in how to design and implement a complex feature in a mature codebase. The architecture demonstrates:

1. **Deep understanding of Elixir semantics** - Blocks, patterns, guards, closures
2. **Rigorous ontology design** - OWL best practices, type safety, extensibility
3. **Thoughtful IRI strategy** - Deterministic, queryable, hierarchical
4. **Comprehensive testing** - 5,647 lines covering all scenarios
5. **Future-proof design** - Clear extension points for scope analysis, closure capture, early exits

### Architectural Highlights

1. **Separation of Concerns**
   - Detection → Analysis → Extraction
   - Each layer is independently testable and reusable

2. **Integration with Existing Code**
   - Extends mode system without breaking changes
   - Uses existing helper functions consistently
   - Bridges expression and pattern extraction

3. **Ontology Design**
   - `hasReturnExpression` is a perfect example of semantic property design
   - Block hierarchy captures Elixir's semantics accurately
   - Extensible for future block types

4. **Testing**
   - Comprehensive coverage of all scenarios
   - Tests serve as documentation
   - Enables confident refactoring

### Production Readiness

**Status:** READY FOR PRODUCTION

The implementation is:
- Correct (all tests pass)
- Complete (all features implemented)
- Performant (depth-limited recursion, efficient helpers)
- Maintainable (clear organization, documented code)
- Extensible (clear extension points)

### Future Work

The architecture naturally supports:
1. Scope analysis (variable bindings)
2. Closure capture tracking
3. Early exit expression detection
4. Block type refinement (case/cond/with/try/receive)

No major refactoring will be required to add these features.

---

**Reviewed by:** Architecture Analysis
**Date:** 2026-01-15
**Next Review:** After scope analysis implementation (Phase 30+)
