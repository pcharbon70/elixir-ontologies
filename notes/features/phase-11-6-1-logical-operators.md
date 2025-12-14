# Phase 11.6.1: SHACL Logical Operators Implementation Plan

**Date**: 2025-12-14
**Status**: Planning Complete, Ready for Implementation
**Branch**: `feature/phase-11-6-1-logical-operators`

## Problem Statement

### Current Status
- **W3C Test Pass Rate:** 47.2% (25/53 tests)
- **Blocked Tests:** 7 W3C tests failing due to missing logical operators
  - `and-001`, `and-002` (sh:and constraint)
  - `or-001` (sh:or constraint)
  - `not-001`, `not-002` (sh:not constraint)
  - `xone-001`, `xone_duplicate` (sh:xone constraint)

### The Gap
Our SHACL implementation supports most core constraints but lacks the four logical constraint operators defined in SHACL specification sections 4.1-4.4. These operators enable complex validation logic by combining multiple shapes.

### Impact
- **Test Coverage:** Implementing logical operators unlocks 7 additional tests
- **Target Pass Rate:** ~60% (32/53 tests, +13%)
- **Specification Compliance:** Core SHACL feature for production use
- **Use Cases:** Essential for validating data with alternative valid structures (e.g., "rectangle must have width+height OR area")

---

## SHACL Specification Details

### 4.1 sh:and - Conjunction (AND)
**Specification:** All shapes in the list must conform

**Example from and-001.ttl:**
```turtle
ex:Rectangle
  rdf:type sh:NodeShape ;
  sh:and (
    [ sh:property [ sh:path ex:width ; sh:minCount 1 ] ]
    [ sh:property [ sh:path ex:height ; sh:minCount 1 ] ]
  ) .

# Valid: Has both width AND height
ex:ValidRectangle ex:width 2 ; ex:height 3 .

# Invalid: Missing height (fails second shape in AND)
ex:InvalidRectangle ex:width 2 .
```

**Validation Algorithm:**
1. Parse RDF list of shape references
2. Validate focus node against each shape
3. If ANY shape fails → violation (sh:AndConstraintComponent)
4. If ALL shapes pass → conforms

### 4.2 sh:or - Disjunction (OR)
**Specification:** At least one shape in the list must conform

**Example from or-001.ttl:**
```turtle
ex:RectangleWithArea
  rdf:type sh:NodeShape ;
  sh:or (
    [ sh:property [ sh:path ex:width ; sh:minCount 1 ]
      sh:property [ sh:path ex:height ; sh:minCount 1 ] ]
    [ sh:property [ sh:path ex:area ; sh:minCount 1 ] ]
  ) .

# Valid: Has width+height (first shape passes)
ex:ValidRect1 ex:width 2 ; ex:height 3 .

# Valid: Has area (second shape passes)
ex:ValidRect2 ex:area 6 .

# Invalid: Has neither (both shapes fail)
ex:InvalidRect ex:depth 10 .
```

**Validation Algorithm:**
1. Parse RDF list of shape references
2. Validate focus node against each shape
3. If ALL shapes fail → violation (sh:OrConstraintComponent)
4. If ANY shape passes → conforms

### 4.3 sh:not - Negation (NOT)
**Specification:** The shape must NOT conform

**Example from not-001.ttl:**
```turtle
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:not [
    sh:property [ sh:path ex:property ; sh:minCount 1 ]
  ] .

# Valid: Does NOT have ex:property (negated shape fails as required)
ex:ValidResource .

# Invalid: HAS ex:property (negated shape passes, but we need it to fail)
ex:InvalidResource ex:property "some value" .
```

**Validation Algorithm:**
1. Parse shape reference (single shape, not a list)
2. Validate focus node against the shape
3. If shape passes → violation (sh:NotConstraintComponent)
4. If shape fails → conforms (negation successful)

### 4.4 sh:xone - Exclusive OR (XOR)
**Specification:** Exactly one shape in the list must conform

**Example from xone-001.ttl:**
```turtle
ex:PersonShape
  rdf:type sh:NodeShape ;
  sh:xone (
    [ sh:property [ sh:path ex:fullName ; sh:minCount 1 ] ]
    [ sh:property [ sh:path ex:firstName ; sh:minCount 1 ]
      sh:property [ sh:path ex:lastName ; sh:minCount 1 ] ]
  ) .

# Valid: Has fullName ONLY (exactly 1 shape passes)
ex:Carla ex:fullName "Carla Miller" .

# Valid: Has firstName+lastName ONLY (exactly 1 shape passes)
ex:Bob ex:firstName "Robert" ; ex:lastName "Coin" .

# Invalid: Has BOTH fullName AND firstName+lastName (2 shapes pass, need exactly 1)
ex:Dory ex:fullName "Dory Dunce" ; ex:firstName "Dory" ; ex:lastName "Dunce" .
```

**Validation Algorithm:**
1. Parse RDF list of shape references
2. Validate focus node against each shape
3. Count how many shapes passed
4. If count != 1 → violation (sh:XoneConstraintComponent)
5. If count == 1 → conforms

---

## Implementation Plan

### Step 1: Update Vocabulary ⏳
**File:** `lib/elixir_ontologies/shacl/vocabulary.ex`

Add IRIs for logical operators and constraint components.

**Estimated**: 1 hour

---

### Step 2: Update Reader to Parse Logical Operators ⏳
**File:** `lib/elixir_ontologies/shacl/reader.ex`

Implement parsing functions for sh:and, sh:or, sh:xone, sh:not.

**Estimated**: 3-4 hours

---

### Step 3: Create LogicalOperators Validator ⏳
**File:** `lib/elixir_ontologies/shacl/validators/logical_operators.ex` (NEW)

Create new validator module with recursive shape validation.

**Estimated**: 4-6 hours

---

### Step 4: Update Validator Orchestration ⏳
**File:** `lib/elixir_ontologies/shacl/validator.ex`

Build shape_map and integrate LogicalOperators validator.

**Estimated**: 2-3 hours

---

### Step 5: Handle Inline Blank Node Shapes ⏳
**File:** `lib/elixir_ontologies/shacl/reader.ex`

Parse inline blank node shapes in logical operator RDF lists.

**Estimated**: 3-4 hours

---

### Step 6: W3C Test Integration ⏳
Run and debug W3C test suite for logical operators.

**Estimated**: 4-6 hours

---

### Step 7: Edge Cases & Recursion Limits ⏳
Handle circular references and deep nesting.

**Estimated**: 2-3 hours

---

### Step 8: Documentation ⏳
Update moduledocs and CHANGELOG.

**Estimated**: 2 hours

---

## Expected Outcomes

**Test Results**:
- Current: 47.2% pass rate (25/53 tests)
- After: ~60% pass rate (32/53 tests)
- Improvement: +7 tests, +13 percentage points

**Files Modified** (4 files):
1. `lib/elixir_ontologies/shacl/vocabulary.ex` - Logical operator IRIs
2. `lib/elixir_ontologies/shacl/reader.ex` - Parsing logic
3. `lib/elixir_ontologies/shacl/validators/logical_operators.ex` - NEW validator
4. `lib/elixir_ontologies/shacl/validator.ex` - Orchestration updates

**Total Estimated Effort**: 21-29 hours (3-4 working days)

## Validation Checklist

Before considering Phase 11.6.1 complete:

- [ ] Vocabulary has all logical operator IRIs
- [ ] Reader parses sh:and, sh:or, sh:xone, sh:not
- [ ] LogicalOperators validator implements all four operators
- [ ] Validator orchestration builds shape_map
- [ ] Inline blank node shapes are parsed
- [ ] W3C test and-001 passes
- [ ] W3C test and-002 passes
- [ ] W3C test or-001 passes
- [ ] W3C test not-001 passes
- [ ] W3C test not-002 passes
- [ ] W3C test xone-001 passes
- [ ] W3C test xone_duplicate passes
- [ ] W3C pass rate is ~60% (32/53 tests)
- [ ] No regression in existing tests
- [ ] Recursion depth limit enforced
- [ ] Compilation clean with no warnings

## Implementation Status

- [⏳] Step 1: Update Vocabulary
- [⏳] Step 2: Update Reader parsing
- [⏳] Step 3: Create LogicalOperators validator
- [⏳] Step 4: Update Validator orchestration
- [⏳] Step 5: Handle inline blank node shapes
- [⏳] Step 6: W3C test integration
- [⏳] Step 7: Edge cases & recursion limits
- [⏳] Step 8: Documentation
