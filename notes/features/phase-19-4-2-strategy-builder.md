# Phase 19.4.2: Strategy Builder

## Overview

Implement `build_supervision_strategy/3` function in SupervisorBuilder to generate RDF triples for supervision strategies extracted from supervisors.

## Task Requirements (from phase-19.md)

- [ ] 19.4.2.1 Implement `build_supervision_strategy/3` generating strategy IRI
- [ ] 19.4.2.2 Generate `rdf:type otp:SupervisionStrategy` triple
- [ ] 19.4.2.3 Generate `otp:strategyType` with strategy enum value
- [ ] 19.4.2.4 Generate `otp:maxRestarts` with restart limit
- [ ] 19.4.2.5 Generate `otp:maxSeconds` with time window
- [ ] 19.4.2.6 Add strategy builder tests

## Current State Analysis

### Existing build_strategy/3 Function

The SupervisorBuilder already has a `build_strategy/3` function (lines 140-153) that:
- Takes a `Strategy.t()` struct, supervisor IRI, and context
- Returns a predefined individual IRI (OneForOne, OneForAll, RestForOne)
- Only generates `otp:hasStrategy` triple linking supervisor to strategy

### What's Missing

The current implementation doesn't generate:
1. Type triple for the strategy itself
2. `otp:maxRestarts` data property
3. `otp:maxSeconds` data property

### Ontology Analysis

From `elixir-otp.ttl`:

**Classes:**
- `otp:SupervisionStrategy` - The class for supervision strategies

**Predefined Individuals:**
- `otp:OneForOne` - a SupervisionStrategy
- `otp:OneForAll` - a SupervisionStrategy
- `otp:RestForOne` - a SupervisionStrategy

**Properties:**
- `otp:hasStrategy` - ObjectProperty linking Supervisor to SupervisionStrategy (domain: Supervisor, range: SupervisionStrategy)
- `otp:maxRestarts` - DatatypeProperty on Supervisor (domain: Supervisor, range: xsd:nonNegativeInteger)
- `otp:maxSeconds` - DatatypeProperty on Supervisor (domain: Supervisor, range: xsd:positiveInteger)

**Important Note:** Per the ontology, `maxRestarts` and `maxSeconds` are properties of the Supervisor, NOT the SupervisionStrategy. This makes sense because the strategy individuals are shared (OneForOne, OneForAll, RestForOne) while restart intensity is per-supervisor.

## Implementation Plan

### Design Decision

Based on ontology analysis:
- The strategy type maps to predefined individuals (already done)
- `maxRestarts` and `maxSeconds` should be added to the **supervisor** triples, not strategy
- The existing `build_strategy/3` is correct for linking supervisor to strategy individual
- We need a new function `build_supervision_strategy/3` that returns both:
  1. The strategy link (from existing `build_strategy/3`)
  2. The restart intensity data properties on the supervisor

### Step 1: Implement build_supervision_strategy/3

New function that combines:
- Strategy type linking (existing `build_strategy/3` behavior)
- `maxRestarts` data property on supervisor
- `maxSeconds` data property on supervisor

```elixir
@spec build_supervision_strategy(Supervisor.Strategy.t(), RDF.IRI.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_supervision_strategy(strategy_info, supervisor_iri, context)
```

### Step 2: Generate Core Triples

1. `{supervisor_iri, otp:hasStrategy, strategy_individual}` - existing
2. `{supervisor_iri, otp:maxRestarts, max_restarts_value}` - NEW
3. `{supervisor_iri, otp:maxSeconds, max_seconds_value}` - NEW

### Step 3: Handle Default Values

Per the Strategy struct:
- `is_default_max_restarts` - indicates if using OTP default (3)
- `is_default_max_seconds` - indicates if using OTP default (5)

Options:
1. Always emit values (effective values)
2. Only emit when explicitly set (not defaults)

**Decision:** Always emit effective values for completeness. The struct tracks whether defaults are used via metadata.

### Step 4: Add Comprehensive Tests

- Test all three strategy types (one_for_one, one_for_all, rest_for_one)
- Test maxRestarts generation with explicit values
- Test maxSeconds generation with explicit values
- Test default value handling (emit effective defaults)
- Test integration with supervisor building

## Files to Modify

1. `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
   - Add `build_supervision_strategy/3`
   - Add helper functions for restart intensity

2. `test/elixir_ontologies/builders/otp/supervisor_builder_test.exs`
   - Add strategy builder tests

## Success Criteria

1. All existing tests continue to pass
2. `build_supervision_strategy/3` generates strategy link
3. `maxRestarts` and `maxSeconds` triples are generated on supervisor
4. All three strategy types are correctly mapped
5. Code compiles without warnings

## Progress

- [x] Step 1: Implement build_supervision_strategy/3
- [x] Step 2: Generate core triples (hasStrategy, maxRestarts, maxSeconds)
- [x] Step 3: Handle default values (use effective OTP defaults: 3/5)
- [x] Step 4: Add comprehensive tests (12 tests)
- [x] Quality checks pass (48 tests total, no warnings)
