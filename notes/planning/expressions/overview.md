# Full Expression Extraction: Overview

This planning series covers the implementation of optional full expression extraction for Elixir AST nodes. The current extraction captures structural metadata (module/function names, arities, parameter counts) but not the actual expression trees for guards, conditions, function bodies, and other code constructs.

## Problem Statement

The current extraction stores **existence flags** rather than **expression content**:

```turtle
# Current (light mode)
<#cond/MyApp/foo/0> core:hasCondition true .

# Desired (full mode)
<#cond/MyApp/foo/0> core:hasCondition <#expr/condition> .
<#expr/condition> a core:ComparisonOperator ;
                 core:operatorSymbol ">" ;
                 core:hasLeftOperand <#expr/left> ;
                 core:hasRightOperand <#expr/right> .
```

## Design Approach: Optional Expression Extraction

- **Default behavior**: Light mode (current) - minimal storage, fast extraction
- **Opt-in behavior**: Full mode (`include_expressions: true`) - complete AST as RDF
- **Backward compatible**: Existing extractions remain valid light representations
- **Gradual rollout**: Implement in phases, each phase independently valuable

## Configuration

```elixir
# lib/elixir_ontologies/config.ex
defstruct include_expressions: false  # NEW: opt-in for full expression extraction
```

## Ontology Coverage

| Ontology | Classes | Current | Full Mode Target |
|----------|---------|---------|------------------|
| elixir-core.ttl | 77 classes | 40% (flags only) | 100% (full AST) |
| Literals | 12 classes | 0% | 100% |
| Operators | 10 classes | 0% | 100% |
| Patterns | 10 classes | 20% | 100% |
| Control Flow | 9 classes | 60% (flags) | 100% |
| Blocks/Scopes | 8 classes | 0% | 100% |

## Phase Roadmap

### Phase 21: Configuration & Expression Infrastructure
Adds the `include_expressions` config option, creates `ExpressionBuilder` module with core AST-to-RDF conversion infrastructure, and updates `Context` to propagate configuration.

**Deliverables:**
- Config option with validation
- ExpressionBuilder module with expression dispatch
- IRI generation for nested expressions
- Helper functions for common patterns
- Tests for light/full mode behavior

### Phase 22: Literal Expressions
Implements extraction for all literal types: atoms, integers, floats, strings, charlists, binaries, lists, tuples, maps, keyword lists, sigils, and ranges.

**Deliverables:**
- Build functions for each literal type
- Value extraction and RDF datatype handling
- Literal pattern matching support
- Unit tests for all literal types

### Phase 23: Operator Expressions
Implements extraction for all operator types: arithmetic, comparison, logical, pipe, match, capture, string concatenation, list, and in operator.

**Deliverables:**
- Binary operator handling (left/right operands)
- Unary operator handling (single operand)
- Operator symbol storage
- Unit tests for all operator types

### Phase 24: Pattern Expressions
Implements extraction for all pattern types: literals, variables, wildcards, pin patterns, tuples, lists, maps, structs, binaries, and as-patterns.

**Deliverables:**
- Pattern AST to RDF conversion
- Nested pattern handling
- Pattern type detection
- Unit tests for all pattern types

### Phase 25: Control Flow with Expressions
Updates ControlFlowBuilder to extract full condition expressions, branch bodies, and clause patterns for if/unless/cond/case/with/receive.

**Deliverables:**
- Condition expression extraction
- Branch body extraction
- Clause pattern + guard extraction
- Integration with light/full mode
- Unit and integration tests

### Phase 26: Function Guards with Expressions
Updates ClauseBuilder to extract full guard expressions when `include_expressions: true`.

**Deliverables:**
- Guard AST to ExpressionBuilder integration
- Compound guard handling (and/or)
- Guard function call extraction (is_*, is_integer, etc.)
- Unit and integration tests

### Phase 27: Function Bodies & Blocks
Implements extraction for do blocks, fn blocks, and general expression sequences.

**Deliverables:**
- Block structure extraction
- Expression ordering
- Return expression identification
- Closure capture detection (future: phase 28)
- Unit and integration tests

### Phase 28: Comprehensions with Expressions
Updates Comprehension extraction to include generator patterns, filter expressions, and collectable expressions.

**Deliverables:**
- Generator pattern extraction
- Filter expression extraction
- :into, :reduce, :uniq option expression extraction
- Unit and integration tests

### Phase 29: Calls & References
Implements extraction for remote calls, local calls, module references, and function references including capture operator (&).

**Deliverables:**
- Remote call extraction (Module.func)
- Local call extraction (func)
- Capture operator extraction (&1, &Mod.fun/arity)
- Reference handling
- Unit and integration tests

### Phase 30: Try, Raise, Throw, Exception Handling
Implements extraction for try/rescue/catch/after/raise/throw expressions with full pattern matching on rescued exceptions.

**Deliverables:**
- Try expression extraction
- Rescue pattern extraction
- Catch pattern extraction
- After block extraction
- Raise/throw expression extraction
- Unit and integration tests

### Phase 31: Git History and Evolution Integration
Implements optional git history integration that constructs ontology individuals across multiple versions, leveraging the evolution ontology and PROV-O for provenance tracking.

**Deliverables:**
- Git repository analysis and commit/tag traversal
- Per-version extraction with named graphs
- Changeset generation from git diffs
- Provenance metadata extraction (author, time, message)
- SPARQL queries for temporal analysis
- Optional `history_depth` configuration (`:tags_only`, `:all_commits`, `:none`)
- Unit and integration tests

**Note:** Phase 31 is entirely optional and independent of expression extraction. When `include_history: false`, extraction works on the current codebase state only.

## Storage Impact Estimates

### For Dependencies (always light mode, no history)
| Scale | Storage |
|-------|---------|
| 15k packages | ~750 MB |

### For Project Code (varies by configuration)
| Mode | Expressions | History | Project (100 funcs) | Large (1000 funcs) |
|------|-------------|---------|---------------------|-------------------|
| **Light** | ✗ | ✗ | ~50 KB | ~500 KB |
| **Full** | ✓ | ✗ | ~500 KB - 2 MB | ~5 MB - 20 MB |
| **Historical** | ✗ | Tags (50) | ~2.5 MB | ~25 MB |
| **Complete** | ✓ | Tags (50) | ~25 MB - 100 MB | ~250 MB - 1 GB |

**Note:** History storage scales linearly with number of versions extracted. A 5-year project with 50 releases at ~5 MB per version = ~250 MB for complete historical analysis.

## Configuration Matrix

```elixir
config :elixir_ontologies,
  # Expression extraction (Phases 21-30)
  include_expressions: false,  # Full AST for project code only

  # History extraction (Phase 31) - entirely optional
  include_history: false,      # Extract git history
  history_depth: :none,        # :tags_only | :all_commits
  history_limit: nil,          # Max commits to process
  max_versions: 100            # Max named graphs to generate
```

## Success Metrics

- **Expression Coverage**: 100% of elixir-core.ttl expression classes extractable
- **Light Mode**: No regression in performance or storage
- **Full Mode**: Complete, queryable AST representation
- **History Mode**: Complete version tracking with named graphs
- **Test Coverage**: 100% of new code has unit and integration tests
- **Documentation**: Full API docs with examples
- **SPARQL Queryability**: All entities navigable across time periods

## Prerequisites

- Phase 17 (ControlFlowBuilder) complete
- Phase 14-20 (extractors) complete
- All existing tests passing

## Document Structure

Each phase document follows the established pattern:
1. Phase introduction paragraph
2. Numbered sections (X.1, X.2) with descriptive paragraphs
3. Tasks (X.1.1, X.1.2) with subtask checkboxes
4. Section unit tests
5. Phase integration tests

## Phase Summary

| Phase | Topic | Sections | Status |
|-------|-------|----------|--------|
| 21 | Configuration & Expression Infrastructure | 6 | Planned |
| 22 | Literal Expressions | 10 | Planned |
| 23 | Operator Expressions | 7 | Planned |
| 24 | Pattern Expressions | 7 | Planned |
| 25 | Control Flow with Expressions | 7 | Planned |
| 26 | Function Guards with Expressions | 5 | Planned |
| 27 | Function Bodies and Block Expressions | 6 | Planned |
| 28 | Comprehension with Expressions | 6 | Planned |
| 29 | Calls and References | 7 | Planned |
| 30 | Try, Raise, Throw, Exception Handling | 8 | Planned |
| 31 | Git History and Evolution Integration | 8 | Planned |

**Total**: 11 phases, 77 sections, ~450 implementation tasks

All phases are optional and independently valuable. Phases 21-30 focus on expression extraction for current code. Phase 31 focuses on historical analysis across versions.
