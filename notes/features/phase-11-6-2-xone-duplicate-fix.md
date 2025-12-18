# Phase 11.6.2: xone-duplicate Test Fix - Implementation Plan

**Date**: 2025-12-15
**Status**: Complete
**Branch**: `feature/phase-11-6-2-property-logical-operators`
**Original Goal**: Implement property-level logical operators
**Actual Implementation**: Fix xone-duplicate test (test infrastructure improvements)

## Problem Statement

The `xone-duplicate` W3C test was failing with the following error:
```
Expected: conforms = false
Actual:   conforms = true
Expected result count: 2
Actual result count:   0
```

### Initial Analysis

The test was labeled "Test of validation report for shape xone-duplicate by property constraints" which suggested it tested property-level logical operators. However, upon investigation, the test actually validates a **node-level edge case**: duplicate shape references in sh:xone lists.

## Root Cause Analysis

Three issues were discovered:

### Issue 1: Missing Test Files

The xone-duplicate test referenced external files that weren't downloaded:
- `xone-duplicate-data.ttl`
- `xone-duplicate-shapes.ttl`

These files existed in the W3C repository but weren't included in our fixtures.

### Issue 2: Test Runner Doesn't Support External Files

The W3C test runner (`w3c_test_runner.ex`) assumed all test data and shapes were inline in the manifest file. It didn't handle external file references via `sht:dataGraph` and `sht:shapesGraph`.

### Issue 3: Reader Doesn't Parse Non-Typed Shape References

The Reader only parsed shapes explicitly typed as `sh:NodeShape`. The xone-duplicate test includes a shape reference (`ex:s2`) that isn't typed:

```turtle
ex:s1 a sh:NodeShape ;
  sh:targetClass ex:C1 ;
  sh:xone ( ex:s2 ex:s2 ) .  # References ex:s2

ex:s2 sh:class ex:C2 .  # NOT typed as sh:NodeShape
```

The Reader's inline shape parser only looked for blank nodes, not IRIs.

## Solution Overview

### 1. Download Missing Test Files ✅

Downloaded external test files from W3C repository:
```bash
curl https://raw.githubusercontent.com/w3c/data-shapes/gh-pages/data-shapes-test-suite/tests/core/node/xone-duplicate-shapes.ttl
curl https://raw.githubusercontent.com/w3c/data-shapes/gh-pages/data-shapes-test-suite/tests/core/node/xone-duplicate-data.ttl
```

### 2. Update Test Runner for External Files ✅

Modified `lib/elixir_ontologies/shacl/w3c_test_runner.ex`:

**Changes:**
- Added `load_data_graph/3` - Loads external data file or falls back to manifest
- Added `load_shapes_graph/3` - Loads external shapes file or falls back to manifest
- Added `load_external_graph/3` - Resolves and loads .ttl files relative to manifest
- Updated `parse_test_file/1` - Calls new loaders instead of using manifest for both

**Key Logic:**
```elixir
# Extract sht:dataGraph and sht:shapesGraph from mf:action
# Resolve relative file paths (e.g., <xone-duplicate-data.ttl>)
# Load external file if it exists
# Fall back to manifest graph if file doesn't exist
```

### 3. Update Reader to Parse Referenced IRI Shapes ✅

Modified `lib/elixir_ontologies/shacl/reader.ex`:

**Changes:**
- Updated `parse_inline_shapes_recursive/4` to handle both BlankNode and IRI references
- Changed filter from `match?(%RDF.BlankNode{}, ref)` to `(match?(%RDF.BlankNode{}, ref) || match?(%RDF.IRI{}, ref))`
- Updated comments to reflect IRI support

**Impact:**
Shapes referenced in logical operators (sh:and, sh:or, sh:xone, sh:not) are now parsed even if:
- They're not explicitly typed as `sh:NodeShape`
- They're IRI references (not just blank nodes)

### 4. Exclude Test Data Files from Test Generation ✅

Modified `test/elixir_ontologies/w3c_test.exs`:

**Changes:**
- Added filter to reject files ending with `-data.ttl` or `-shapes.ttl`
- Prevents ExUnit from treating test data files as test manifests

```elixir
@core_test_files Path.wildcard(Path.join(@core_dir, "*.ttl"))
                 |> Enum.reject(fn file ->
                   String.ends_with?(file, "-data.ttl") or
                   String.ends_with?(file, "-shapes.ttl")
                 end)
```

## Test Case Details

### xone-duplicate Test Structure

**Shapes (`xone-duplicate-shapes.ttl`):**
```turtle
ex:s1 a sh:NodeShape ;
  sh:targetClass ex:C1 ;
  sh:xone ( ex:s2 ex:s2 ) .  # DUPLICATE reference!

ex:s2 sh:class ex:C2 .
```

**Data (`xone-duplicate-data.ttl`):**
```turtle
ex:i a ex:C1 .          # Only C1 (not C2)
ex:j a ex:C1 , ex:C2 .  # Both C1 and C2
```

**Expected Violations:**
1. `ex:i`: Conforms to ex:s2 **0 times** (not type C2) → Need exactly 1 → VIOLATION
2. `ex:j`: Conforms to ex:s2 **2 times** (type C2, but counted twice due to duplicate) → Need exactly 1 → VIOLATION

### Why Our Implementation Handles This Correctly

Our `LogicalOperators.validate_xone/5` implementation:
```elixir
pass_count =
  Enum.count(shape_refs, fn shape_ref ->
    results = validate_against_shape(...)
    length(results) == 0
  end)
```

This correctly counts each element in the `shape_refs` list, including duplicates:
- For `ex:i`: Checks ex:s2 twice, both fail → pass_count = 0 → VIOLATION ✓
- For `ex:j`: Checks ex:s2 twice, both pass → pass_count = 2 → VIOLATION ✓

## Results

### Test Pass Rate
- **Before**: 64.2% (34/53 tests passing)
- **After**: 66.0% (35/53 tests passing)
- **Improvement**: +1.8 percentage points

### xone-duplicate Test
- **Status**: ✅ PASSING
- **No warnings**: ex:s2 shape now correctly parsed and resolved

### Code Quality
- **Compiler warnings**: 0
- **All existing tests**: Still passing
- **New functionality**: External file loading, IRI shape references

## Files Modified

1. **lib/elixir_ontologies/shacl/w3c_test_runner.ex** (+98 lines)
   - Added external file loading support
   - Three new helper functions

2. **lib/elixir_ontologies/shacl/reader.ex** (+2 lines)
   - Extended inline shape parser to handle IRIs
   - Updated filter condition and comments

3. **test/elixir_ontologies/w3c_test.exs** (+2 lines)
   - Added file exclusion filter
   - Prevents -data/-shapes files from being treated as tests

4. **test/fixtures/w3c/core/** (+2 files)
   - Downloaded xone-duplicate-shapes.ttl (191 bytes)
   - Downloaded xone-duplicate-data.ttl (86 bytes)

## Key Learnings

### 1. Test Labeling Can Be Misleading
The test was labeled "by property constraints" but actually tested node-level logic with duplicate references. Always analyze the actual test content.

### 2. SHACL Shapes Don't Require Explicit Typing
The SHACL spec allows shapes to be referenced without `rdf:type sh:NodeShape`. Implementations must handle implicit shapes.

### 3. W3C Tests Use External Files
Some W3C tests split data/shapes into separate files. Test infrastructure must support:
- Parsing `sht:dataGraph` and `sht:shapesGraph` references
- Resolving relative file paths
- Loading external Turtle files

### 4. Test Fixtures Need Completeness
Missing test files can cause tests to pass incorrectly (false positives). Always verify test data is complete.

## Future Improvements

### Considered But Not Implemented

**Property-Level Logical Operators:**
Not implemented in this phase because:
- xone-duplicate doesn't actually test property-level operators
- No W3C tests currently failing due to missing property-level support
- Would require PropertyShape model extension and additional validator logic

### Potential Future Work

1. **Full W3C Test Suite Download**
   - Update `download_tests.sh` to include -data and -shapes files
   - Document which tests require external files

2. **Property-Level Logical Operators** (Future Phase)
   - Add `property_and`, `property_or`, `property_xone`, `property_not` to PropertyShape
   - Extend LogicalOperators validator for property-level validation
   - Would enable validation like: "value must be string XOR integer"

3. **Test Infrastructure Improvements**
   - Better detection of incomplete test files
   - Warning when external files are referenced but missing
   - Automatic test file dependency resolution

## Conclusion

This phase successfully fixed the xone-duplicate test failure by improving test infrastructure rather than implementing new SHACL features. The improvements benefit all W3C tests:

1. **External file support** enables more comprehensive W3C test coverage
2. **IRI shape reference parsing** handles real-world SHACL patterns
3. **Better test file filtering** prevents false test failures

The W3C pass rate improved from 64.2% to 66.0%, and the foundation is now stronger for future SHACL feature additions.

**Next recommended task**: Phase 11 Integration Tests (end-to-end validation testing)
