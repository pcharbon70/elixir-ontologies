# Phase 19.1.1: Child Spec Structure Extraction

## Overview

Enhance child specification extraction from supervisor init/1 callbacks to support all Elixir/OTP child spec formats including map syntax, module-based syntax, and legacy tuple syntax.

## Current State

The supervisor extractor (`lib/elixir_ontologies/extractors/otp/supervisor.ex`) already has:
- `ChildSpec` struct with fields: id, module, restart, shutdown, type, location, metadata
- `extract_children/1` function that extracts child specs from init/1
- Basic support for `{Module, args}` tuple format
- Basic support for `%{id: ..., start: ...}` map format
- Module-only shorthand support

## Task Requirements (from phase-19.md)

- [ ] 19.1.1.1 Update `lib/elixir_ontologies/extractors/otp/supervisor.ex` for child spec extraction
- [ ] 19.1.1.2 Define `%ChildSpec{id: ..., start: ..., restart: ..., shutdown: ..., type: ..., modules: [...]}` struct
- [ ] 19.1.1.3 Extract child spec from map syntax `%{id: ..., start: ...}`
- [ ] 19.1.1.4 Extract child spec from module-based syntax `{Module, arg}`
- [ ] 19.1.1.5 Extract child spec from full tuple syntax `{id, start, restart, shutdown, type, modules}`
- [ ] 19.1.1.6 Add child spec structure tests

## Implementation Plan

### Step 1: Enhance ChildSpec Struct
- Add `start` field to store the full `{Module, :function, args}` tuple
- Add `modules` field to store explicit module list (for code upgrades)
- Update type definitions

### Step 2: Add StartSpec Struct
- Define `%StartSpec{module: ..., function: ..., args: [...]}` for start field
- Provides structured access to start function details

### Step 3: Enhance Map Syntax Extraction
- Better extraction of start function from `start: {M, :start_link, [args]}`
- Extract all optional fields (restart, shutdown, type, modules)

### Step 4: Enhance Module-Based Syntax Extraction
- `{Module, args}` implies `start: {Module, :start_link, [args]}`
- Infer id as module name

### Step 5: Add Legacy Tuple Syntax Support
- Support `{id, start, restart, shutdown, type, modules}` 6-tuple format
- This is the old OTP format before maps were common

### Step 6: Add Comprehensive Tests
- Test all three child spec formats
- Test default value handling
- Test edge cases

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Enhance `ChildSpec` struct
   - Add `StartSpec` struct
   - Update `parse_child_spec/2` for all formats

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add tests for StartSpec
   - Add tests for legacy tuple format
   - Add tests for modules field

## Success Criteria

1. All child spec formats are correctly extracted
2. StartSpec captures start function details
3. Modules list is extracted when present
4. All existing tests continue to pass
5. New tests cover all formats
6. Code compiles without warnings

## Progress

- [x] Step 1: Enhance ChildSpec struct with `start` and `modules` fields
- [x] Step 2: Add StartSpec struct for structured start function info
- [x] Step 3: Enhance map syntax extraction with StartSpec population
- [x] Step 4: Enhance module-based syntax extraction with StartSpec
- [x] Step 5: Add legacy 6-tuple syntax support
- [x] Step 6: Add comprehensive tests (14 new tests)
- [x] Quality checks pass (105 tests total, no warnings)
