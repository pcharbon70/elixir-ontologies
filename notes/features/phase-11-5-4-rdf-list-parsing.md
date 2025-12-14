# Phase 11.5.4: RDF List Parsing for sh:in and sh:languageIn Constraints - Implementation Plan

**Date**: 2025-12-14
**Status**: Planning Complete, Ready for Implementation
**Branch**: `feature/phase-11-5-4-rdf-list-parsing`

## Problem Statement

We've achieved 43.4% W3C test pass rate, but **RDF list parsing** was deliberately deferred in Phase 11.5.2. This is now blocking 2 W3C tests (in-001 and languageIn-001) that use `sh:in` and `sh:languageIn` constraints with RDF list syntax.

**Current State**:
- NodeShape has `node_in` and `node_language_in` fields
- Reader has placeholder functions returning `nil`
- Validators check these fields but they're always `nil`

**Impact**: 2 W3C tests failing unnecessarily

## Solution Overview

Implement proper RDF list parsing by:
1. Updating Reader function signatures to pass `graph` through call chain
2. Reusing existing `parse_rdf_list/3` implementation (lines 583-608)
3. Adding `sh:languageIn` validation logic to String validator
4. Unlocking 2 W3C tests (+3.6% pass rate)

## Current State Analysis

### What's Already Working ✅

**NodeShape Model** - Fully ready:
- Fields exist: `node_in: [RDF.Term.t()] | nil`
- Fields exist: `node_language_in: [String.t()] | nil`
- Type specs correct

**Value Validator** - Fully ready:
- `check_node_in/3` exists and validates `node_in` (lines 283-317)
- No changes needed

**Validator Orchestration** - Fully ready:
- Calls both Type, String, and Value validators
- No changes needed

### What's Broken ❌

**Reader - Function Signatures**:
- `extract_node_constraints(desc)` - needs `graph` parameter
- `extract_optional_language_in(desc)` - needs `graph` parameter
- Can't parse RDF lists without graph access

**Reader - Hardcoded nil**:
- Line 250: `in: nil` - should parse `sh:in` list
- Needs new `extract_node_in_values/2` helper

**String Validator - Missing Logic**:
- No `check_node_language_in/3` function
- `validate_node/3` doesn't call language validation

## RDF List Format

```turtle
# Turtle shorthand
sh:in (ex:A ex:B ex:C)

# Expands to triples
_:list1 rdf:first ex:A ;
        rdf:rest _:list2 .
_:list2 rdf:first ex:B ;
        rdf:rest _:list3 .
_:list3 rdf:first ex:C ;
        rdf:rest rdf:nil .
```

Existing parser (lines 583-608) already handles this correctly with depth protection.

## Implementation Plan

### Step 1: Update Reader Function Signatures ⏳

**File**: `lib/elixir_ontologies/shacl/reader.ex`

**Change 1.1**: Update `parse_node_shape` call (line 138)
```elixir
# Before:
{:ok, node_constraints} <- extract_node_constraints(desc),

# After:
{:ok, node_constraints} <- extract_node_constraints(graph, desc),
```

**Change 1.2**: Update `extract_node_constraints` signature (line 221)
```elixir
# Before:
defp extract_node_constraints(desc) do

# After:
defp extract_node_constraints(graph, desc) do
```

**Change 1.3**: Update `extract_optional_language_in` call (line 235)
```elixir
# Before:
{:ok, language_in} <- extract_optional_language_in(desc) do

# After:
{:ok, language_in} <- extract_optional_language_in(graph, desc) do
```

**Estimated**: 10 minutes

---

### Step 2: Implement sh:in Parsing ⏳

**File**: `lib/elixir_ontologies/shacl/reader.ex`

**Change 2.1**: Add `extract_node_in_values` helper (after line 256)
```elixir
# Helper: Extract sh:in values from RDF list (for node-level constraints)
@spec extract_node_in_values(RDF.Graph.t(), RDF.Description.t()) ::
        {:ok, [RDF.Term.t()] | nil} | {:error, term()}
defp extract_node_in_values(graph, desc) do
  values = desc |> RDF.Description.get(SHACL.in_values()) |> normalize_to_list()

  case values do
    [] ->
      {:ok, nil}
    [list_head | _] ->
      case parse_rdf_list(graph, list_head, 0) do
        {:ok, []} -> {:ok, nil}  # Empty list = no constraint
        {:ok, items} -> {:ok, items}
        error -> error
      end
  end
end
```

**Change 2.2**: Update `extract_node_constraints` to call it (line 235)
```elixir
# Before:
{:ok, pattern} <- extract_optional_pattern(desc),
{:ok, has_value} <- extract_optional_term(desc, SHACL.has_value()),
{:ok, language_in} <- extract_optional_language_in(graph, desc) do

# After:
{:ok, pattern} <- extract_optional_pattern(desc),
{:ok, in_values} <- extract_node_in_values(graph, desc),
{:ok, has_value} <- extract_optional_term(desc, SHACL.has_value()),
{:ok, language_in} <- extract_optional_language_in(graph, desc) do
```

**Change 2.3**: Return parsed values instead of nil (line 250)
```elixir
# Before:
in: nil,  # Will implement in values extraction later if needed

# After:
in: in_values,
```

**Estimated**: 20 minutes

---

### Step 3: Implement sh:languageIn Parsing ⏳

**File**: `lib/elixir_ontologies/shacl/reader.ex`

**Change 3.1**: Update `extract_optional_language_in` signature and implementation (lines 669-694)
```elixir
# Before:
@spec extract_optional_language_in(RDF.Description.t()) :: {:ok, [String.t()] | nil}
defp extract_optional_language_in(desc) do
  case RDF.Description.get(desc, SHACL.language_in()) do
    nil -> {:ok, nil}
    list_node when is_list(list_node) ->
      parse_rdf_list(List.first(list_node))
    list_node ->
      parse_rdf_list(list_node)
  end
end

# After:
@spec extract_optional_language_in(RDF.Graph.t(), RDF.Description.t()) ::
        {:ok, [String.t()] | nil} | {:error, term()}
defp extract_optional_language_in(graph, desc) do
  values = desc |> RDF.Description.get(SHACL.language_in()) |> normalize_to_list()

  case values do
    [] ->
      {:ok, nil}
    [list_head | _] ->
      case parse_rdf_list(graph, list_head, 0) do
        {:ok, []} -> {:ok, nil}
        {:ok, literals} ->
          # Extract language tags as strings
          language_tags = Enum.map(literals, fn lit ->
            case lit do
              %RDF.Literal{} -> RDF.Literal.value(lit)
              other -> to_string(other)
            end
          end)
          {:ok, language_tags}
        error -> error
      end
  end
end
```

**Change 3.2**: Remove placeholder `parse_rdf_list` overloads (lines 686-694)
```elixir
# DELETE these three placeholder functions:
defp parse_rdf_list(nil), do: {:ok, nil}
defp parse_rdf_list(%RDF.IRI{} = _node), do: {:ok, nil}
defp parse_rdf_list(_), do: {:ok, nil}
```

**Estimated**: 30 minutes

---

### Step 4: Add sh:languageIn Validation ⏳

**File**: `lib/elixir_ontologies/shacl/validators/string.ex`

**Change 4.1**: Update `validate_node` to call language check (line 248)
```elixir
# Before:
def validate_node(_data_graph, focus_node, node_shape) do
  []
  |> check_node_pattern(focus_node, node_shape)
  |> check_node_min_length(focus_node, node_shape)
  |> check_node_max_length(focus_node, node_shape)
end

# After:
def validate_node(_data_graph, focus_node, node_shape) do
  []
  |> check_node_pattern(focus_node, node_shape)
  |> check_node_min_length(focus_node, node_shape)
  |> check_node_max_length(focus_node, node_shape)
  |> check_node_language_in(focus_node, node_shape)
end
```

**Change 4.2**: Add `check_node_language_in` helper (after line 378)
```elixir
# Check sh:languageIn constraint on the focus node itself
@spec check_node_language_in([ValidationResult.t()], RDF.Term.t(), NodeShape.t()) ::
        [ValidationResult.t()]
defp check_node_language_in(results, focus_node, node_shape) do
  case node_shape.node_language_in do
    nil ->
      results

    [] ->
      results

    allowed_languages ->
      case focus_node do
        %RDF.Literal{language: nil} ->
          # Plain literal without language tag - violation
          violation =
            Helpers.build_node_violation(
              focus_node,
              node_shape,
              "Focus node must have a language tag",
              %{
                constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
                allowed_languages: allowed_languages,
                actual_value: focus_node
              }
            )
          [violation | results]

        %RDF.Literal{language: lang} when is_binary(lang) ->
          if lang in allowed_languages do
            results
          else
            violation =
              Helpers.build_node_violation(
                focus_node,
                node_shape,
                "Language tag '#{lang}' is not in the allowed list",
                %{
                  constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
                  allowed_languages: allowed_languages,
                  actual_language: lang,
                  actual_value: focus_node
                }
              )
            [violation | results]
          end

        _other ->
          # Not a literal - violation
          violation =
            Helpers.build_node_violation(
              focus_node,
              node_shape,
              "Focus node must be a literal with a language tag",
              %{
                constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
                allowed_languages: allowed_languages,
                actual_value: focus_node
              }
            )
          [violation | results]
      end
  end
end
```

**Estimated**: 40 minutes

---

### Step 5: Run W3C Tests ⏳

**Commands**:
```bash
# Compile
mix compile

# Run target tests
mix test test/elixir_ontologies/w3c_test.exs

# Check specific tests
grep "in_001\|languageIn_001" test results
```

**Expected Results**:
- in-001: PASS ✅
- languageIn-001: PASS ✅
- W3C pass rate: 43.4% → ~47%
- No regressions in other tests

**Estimated**: 30 minutes

---

### Step 6: Write Summary Document ⏳

**File**: `notes/summaries/phase-11-5-4-rdf-list-parsing.md`

**Contents**:
- Implementation summary
- Test results with before/after
- Files modified
- Next steps

**Estimated**: 30 minutes

---

## Expected Outcomes

**Test Results**:
- Current: 43.4% pass rate (23/53 tests)
- After: ~47% pass rate (25/53 tests)
- Improvement: +2 tests, +3.6 percentage points

**Files Modified** (2 files):
1. `lib/elixir_ontologies/shacl/reader.ex` - RDF list parsing (~40 lines modified/added)
2. `lib/elixir_ontologies/shacl/validators/string.ex` - languageIn validation (~60 lines added)

**Total Changes**: ~100 lines

**Time Estimate**: 2.5-3 hours total

## Validation Checklist

Before considering Phase 11.5.4 complete:

- [ ] Reader parses sh:in RDF lists for node shapes
- [ ] Reader parses sh:languageIn RDF lists
- [ ] String validator checks language tags against allowed list
- [ ] W3C test in-001 passes
- [ ] W3C test languageIn-001 passes
- [ ] W3C pass rate is ~47% (25/53 tests)
- [ ] No regression in existing tests
- [ ] Compilation clean with no warnings

## Implementation Status

- [⏳] Step 1: Update Reader function signatures
- [⏳] Step 2: Implement sh:in parsing
- [⏳] Step 3: Implement sh:languageIn parsing
- [⏳] Step 4: Add sh:languageIn validation
- [⏳] Step 5: Run W3C tests
- [⏳] Step 6: Write summary document

## Notes

- Reuses proven `parse_rdf_list/3` implementation (lines 583-608)
- Maintains depth limit protection (@max_list_depth = 100)
- Minimal changes - only Reader and String validator
- Quick win - unlocks 2 tests with ~3 hours effort
- Completes node-level constraint implementation from Phase 11.5.2
