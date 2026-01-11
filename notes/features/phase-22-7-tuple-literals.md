# Phase 22.7: Tuple Literal Extraction

**Status:** ✅ Complete
**Branch:** `feature/phase-22-7-tuple-literals`
**Created:** 2025-01-10
**Completed:** 2025-01-10
**Target:** Implement tuple literal extraction

## 1. Problem Statement

Section 22.7 of the expressions plan specifies implementation of tuple literal extraction. Tuples in Elixir are denoted with `{}` syntax and can contain heterogeneous elements. Unlike lists, tuples have a fixed size and are commonly used for tagged tuples (where the first element is an atom).

**Current State:**
- `TupleLiteral` class exists in ontology (line 152-155 of `elixir-core.ttl`)
- No `hasElement` property, but `hasChild` property exists for generic AST linking
- ExpressionBuilder has no tuple handler
- Tuples are currently caught by the fallback `build_generic_expression/1`

**Elixir AST Behavior:**
- Empty tuple `{}` is represented as: `{:{}, [], []}`
- 2-tuple `{a, b}` is represented as: `{a, b}` (special form - direct tuple)
- 3+ tuple `{a, b, c}` is represented as: `{:{}, [], [a, b, c]}`
- Nested tuples `{{1, 2}, {3, 4}}` are nested tuple structures
- Tagged tuples `{:ok, value}` have an atom as first element

**Key Challenge:**

The 2-tuple is a special case in Elixir AST - it's represented directly as a tuple with 2 elements, not as a 3-tuple AST node. This means we need to detect:

1. `{:{}, [], elements}` pattern - 3+ tuples and empty tuple
2. Direct 2-element tuples `{left, right}` - need to distinguish from other AST patterns

The challenge is that the 2-tuple pattern `{left, right}` could also match:
- `{:{}, [], [a, b]}` - a 2-tuple in general form
- Other AST patterns that happen to be 2-element tuples

**Solution Approach:**

We need to detect tuples by:
1. Matching `{:{}, _, elements}` pattern for 3+ tuples and empty tuple
2. For 2-tuples, we need a guard to distinguish from the `{:{}, _, [a, b]}` pattern

The key insight is that we need to place the tuple handler **before** the local call handler (which matches `{atom, meta, args}`), otherwise a 2-tuple like `{:ok, 42}` would be matched as a local call.

## 2. Solution Overview

The solution involves:

1. **Add tuple handler before local call handler** to ensure tuples are matched correctly
2. **Detect empty tuple** `{:{}, [], []}`
3. **Detect general tuple** `{:{}, _, elements}` (3+ elements)
4. **Handle 2-tuple** as special case or as part of general pattern
5. **Add comprehensive tests** for tuple extraction

### Implementation Details

#### Tuple Handler Strategy

For tuples, we need to:

1. **Match `{:{}, meta, elements}`** pattern for tuples with explicit tuple constructor
2. **Extract tuple elements recursively** using `build_expression_triples/3`
3. **Link elements via `hasChild` property** (generic AST linking property)
4. **Handle empty tuples** as `TupleLiteral` with no children

#### 2-Tuple Handling

The 2-tuple `{left, right}` in Elixir AST is represented directly as a 2-element tuple. This creates ambiguity:
- `{a, b}` - Is this a 2-tuple literal?
- `{function, meta, args}` - Or is this a function call?

The solution is to check the first element:
- If first element is `:{}`, it's a tuple in general form
- If first element is any other atom, it's a local call

However, direct 2-tuples like `{1, 2}` appear as `{1, 2}` in the AST, which would be matched by the local call pattern `{function, meta, args}` if function=1, meta=2, args=undefined.

To handle this, we need to:
1. Place tuple handler before local call handler
2. Use guards to distinguish tuples from function calls

## 3. Agent Consultations Performed

**Self-Analysis:**
- Verified Elixir AST representation of tuples using test script
- Confirmed that 2-tuples appear as direct tuples in AST
- Confirmed that 3+ tuples use `{:{}, [], elements}` pattern
- Confirmed that empty tuple uses `{:{}, [], []}` pattern
- Checked ontology for TupleLiteral class (exists at line 152-155)
- Checked ontology for `hasElement` property (doesn't exist)
- Found `hasChild` property as generic AST linking property
- Verified current ExpressionBuilder has no tuple handler
- Identified that local call handler could conflict with 2-tuple detection

## 4. Technical Details

### Elixir AST Tuple Representations

| Source Code | AST Representation | Notes |
|-------------|-------------------|-------|
| `{}` | `{:{}, [], []}` | Empty tuple |
| `{1, 2}` | `{1, 2}` | 2-tuple (special form) |
| `{1, 2, 3}` | `{:{}, [], [1, 2, 3]}` | 3-tuple |
| `{1, 2, 3, 4}` | `{:{}, [], [1, 2, 3, 4]}` | 4-tuple |
| `{{1, 2}, {3, 4}}` | `{{1, 2}, {3, 4}}` | Nested 2-tuples |
| `{:ok, 42}` | `{:ok, 42}` | Tagged 2-tuple |

### Tuple Detection Strategy

A tuple is detected when:
1. The AST is a tuple (using `is_tuple/1`)
2. AND one of the following:
   - First element is `:{}` (general form: `{:{}, meta, elements}`)
   - The tuple has exactly 2 elements and first is NOT an atom with list second element (distinguish from local call)

Actually, the simplest approach is:
1. Match `{:{}, _, elements}` pattern - covers empty tuple and 3+ tuples
2. For 2-tuples, we need a separate pattern that comes BEFORE the local call pattern

Let me reconsider. The local call pattern is:
```elixir
{function, meta, args} when is_atom(function) and is_list(meta) and is_list(args)
```

A direct 2-tuple `{1, 2}` would match this if 1 is considered an atom (it's not), so it wouldn't match.

Actually, `is_atom(1)` returns false, so `{1, 2}` would NOT match the local call pattern.

But `{:ok, 42}` would match the local call pattern because:
- `is_atom(:ok)` = true
- `is_atom([])` = true (empty meta is common)
- `is_list(42)` = false... so it wouldn't match!

Wait, let me verify this. Actually the local call pattern requires `is_list(args)`, and 42 is not a list, so `{:ok, 42}` would NOT match the local call pattern.

But what about `{:ok, [1, 2]}`?
- `is_atom(:ok)` = true
- `is_atom([])` = true
- `is_list([1, 2])` = true
So this WOULD match the local call pattern!

Actually, looking at the Elixir AST output:
- `{:ok, 42}` is represented as `{:ok, 42}` - a 2-tuple
- But the local call pattern is `{function, meta, args}` where meta is the metadata list

Let me check the actual AST more carefully. The output from my test showed:
```
2-tuple:
{1, 2}
```

This means `{1, 2}` is literally a 2-element tuple in the AST, not a 3-tuple AST node.

The local call pattern `{function, meta, args}` is for a 3-tuple, not a 2-tuple. So:
- `{function, meta, args}` - 3-tuple (function call)
- `{left, right}` - 2-tuple (tuple literal)

These are different sizes, so they won't conflict!

Wait, but `quote do: foo()` gives `{:foo, [], []}` which is a 3-tuple. Let me verify.

Actually, I need to be more careful here. Let me re-examine the AST output:
- Empty tuple: `{:{}, [], []}` - 3-tuple
- 2-tuple: `{1, 2}` - 2-tuple
- 3-tuple: `{:{}, [], [1, 2, 3]}` - 3-tuple

So the local call pattern `{function, meta, args}` is for 3-tuples, and 2-tuples are actual 2-tuples in the AST.

This means:
- `{function, meta, args}` - 3-tuple (function call)
- `{left, right}` - 2-tuple (tuple literal)
- `{:{}, meta, elements}` - 3-tuple (tuple literal, 0 or 3+ elements)

The pattern matching in Elixir distinguishes by tuple size, so there's no conflict!

However, we need to handle the 2-tuple case. The pattern `{:{}, _, elements}` only matches tuples with first element `:{}`, which doesn't match `{1, 2}`.

So we need a separate clause for 2-tuples:
```elixir
def build_expression_triples({left, right}, expr_iri, context) when is_tuple({left, right}) do
  build_tuple_literal([left, right], expr_iri, context)
end
```

But wait, this pattern matches ANY 2-tuple. We need to make sure we don't match things that should be matched by other patterns.

Actually, looking at the function clauses order:
1. Operators (3-tuples like `{:==, meta, [left, right]}`)
2. Local calls (3-tuples like `{function, meta, args}`)
3. Variables (3-tuples like `{name, meta, ctx}`)

These all match 3-tuples. Our 2-tuple handler would match 2-tuples.

But we also need to match `{:{}, meta, elements}` for 3+ tuples.

Let me re-order:
1. Match `{:{}, meta, elements}` - general tuple form (empty and 3+)
2. Match 2-tuples directly
3. Other patterns

### Ontology Classes

Already defined in `ontology/elixir-core.ttl`:

```turtle
:TupleLiteral a owl:Class ;
    rdfs:label "Tuple Literal"@en ;
    rdfs:comment "A tuple literal containing a fixed number of elements."@en ;
    rdfs:subClassOf :Literal .

:hasChild a owl:ObjectProperty ;
    rdfs:label "has child"@en ;
    rdfs:comment "Links a node to its children in the AST."@en ;
    rdfs:domain :ASTNode ;
    rdfs:range :ASTNode .
```

## 5. Success Criteria

1. **ExpressionBuilder handles tuple literals:**
   - Empty tuple `{}` creates `TupleLiteral`
   - 2-tuple creates `TupleLiteral` with 2 children
   - 3+ tuple creates `TupleLiteral` with correct number of children

2. **Elements are linked correctly:**
   - Each element is extracted as a child expression
   - Elements are linked via `hasChild` property
   - Order is preserved through multiple `hasChild` triples

3. **Comprehensive test coverage:**
   - Empty tuple
   - 2-tuple
   - 3-tuple
   - 4+ tuple
   - Nested tuples
   - Heterogeneous tuples
   - Tagged tuples (first element is atom)

4. **All tests pass**

## 6. Implementation Plan

### Step 1: Add Tuple Handler
- [x] 1.1 Add `build_tuple_literal/3` helper function
- [x] 1.2 Add handler for `{:{}, meta, elements}` pattern
- [x] 1.3 Add handler for 2-tuple pattern `{left, right}`
- [x] 1.4 Place tuple handlers before local call handler

### Step 2: Implement Tuple Literal Extraction
- [x] 2.1 Create `build_tuple_literal/3` to extract tuples as TupleLiteral
- [x] 2.2 Add element extraction for tuple items
- [x] 2.3 Return type triple + child expression triples

### Step 3: Add Comprehensive Tests
- [x] 3.1 Test for empty tuple
- [x] 3.2 Test for 2-tuple
- [x] 3.3 Test for 3-tuple
- [x] 3.4 Test for 4+ tuple
- [x] 3.5 Test for nested tuple
- [x] 3.6 Test for heterogeneous tuple
- [x] 3.7 Test for tagged tuple

### Step 4: Run Tests
- [x] 4.1 Run ExpressionBuilder tests
- [x] 4.2 Run full test suite
- [x] 4.3 Verify no regressions

## 7. Notes/Considerations

### 2-Tuple vs Local Call Ambiguity

After analysis, 2-tuples and local calls are different:
- Local call: 3-tuple `{function, meta, args}`
- 2-tuple: 2-tuple `{left, right}`

Pattern matching in Elixir distinguishes by tuple size, so there's no conflict at the structural level.

However, we must place the 2-tuple handler BEFORE other patterns that might match 2-element tuples if any exist.

### Tuple Order Preservation

For tuples like `{1, 2, 3}`, order is preserved by the tuple structure itself. When extracting elements recursively, each element gets its own expression IRI. The `hasChild` property links the parent tuple to each child, but order is implicit through child extraction sequence.

### Tagged Tuples

Tagged tuples like `{:ok, value}` are commonly used in Elixir for return values. These should be extracted as regular `TupleLiteral` - the fact that the first element is an atom doesn't require special handling in the literal extraction phase.

## 8. Progress Tracking

- [x] 8.1 Create feature branch
- [x] 8.2 Create planning document
- [x] 8.3 Implement tuple literal extraction
- [x] 8.4 Add comprehensive tests
- [x] 8.5 Run tests
- [x] 8.6 Write summary document
- [ ] 8.7 Ask for permission to commit and merge

## 9. Status Log

### 2025-01-10 - Initial Planning
- Created feature branch `feature/phase-22-7-tuple-literals`
- Analyzed Elixir AST representation of tuples
- Confirmed that 2-tuples appear as direct 2-tuples in AST
- Confirmed that 3+ tuples use `{:{}, [], elements}` pattern
- Confirmed that empty tuple uses `{:{}, [], []}` pattern
- Confirmed TupleLiteral class exists in ontology
- Confirmed `hasChild` property exists for linking
- Identified that 2-tuples and local calls are structurally different
- Created planning document

### 2025-01-10 - Implementation Complete ✅
- **ExpressionBuilder Implementation:**
  - Added handler for `{:{}, _meta, elements}` pattern (empty and 3+ tuples)
  - Added handler for `{left, right}` pattern (2-tuples)
  - Added `build_tuple_literal/3` helper to extract tuples as TupleLiteral
  - Tuple elements are recursively extracted as child expressions

- **Test Implementation:**
  - Added 8 new tests for tuple literals
  - Tests cover: empty tuple, 2-tuple, 3-tuple, 4+ tuple, nested tuples, heterogeneous tuples, tagged tuples
  - Updated "unknown expressions" test that used 2-element tuple

- **Key Discovery - Quote vs Literal:**
  - Tests must use `quote do: ...` to get proper AST representation
  - Literal tuples like `{}` are 0-tuples, while AST tuples from `quote` are 3-tuples `{:{}, [], []}`
  - All tuple tests updated to use `quote do: ...`

- **Test Results:**
  - ExpressionBuilder tests: 124 tests (up from 116), 0 failures
  - Full test suite: 7156 tests (up from 7148), 0 failures, 361 excluded
