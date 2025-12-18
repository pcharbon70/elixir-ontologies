# W3C SHACL Test Suite

This directory contains a curated subset of the official W3C SHACL Test Suite for validating the native Elixir SHACL implementation.

## Source

Tests are downloaded from: https://github.com/w3c/data-shapes/tree/gh-pages/data-shapes-test-suite

**Version**: gh-pages branch (W3C SHACL Recommendation test suite)
**Downloaded**: 2025-12-13
**License**: W3C Software and Document License

## Test Organization

### Core Tests (49 tests)

Located in `core/` directory:

#### Node Constraint Tests (32 tests)
- **Class constraints**: class-001, class-002, class-003
- **Datatype constraints**: datatype-001, datatype-002
- **Numeric range**: minInclusive-*, maxInclusive-*, minExclusive-*, maxExclusive-*
- **String constraints**: minLength-*, maxLength-*, pattern-*
- **Value constraints**: hasValue-*, in-*, languageIn-*
- **Node kind**: nodeKind-001
- **Logical operators**: and-*, or-*, not-*, xone-*
- **Shape combinations**: closed-*, equals-*, disjoint-*, node-*, qualified-*

#### Property Constraint Tests (8 tests)
- **Property-specific constraints**: property-class-*, property-datatype-*
- **Cardinality**: property-minCount-*, property-maxCount-*
- **String constraints**: property-minLength-*, property-maxLength-*, property-pattern-*
- **Language uniqueness**: property-uniqueLang-*

#### Path Tests (5 tests)
- **Path types**: sequence, alternative, inverse, zeroOrMore, oneOrMore

#### Target Tests (4 tests)
- **Target mechanisms**: targetNode, targetClass, targetSubjectsOf, targetObjectsOf

### SPARQL Tests (3 tests)

Located in `sparql/` directory:

- **component-001**: SPARQL component definition
- **pre-binding-001**: Pre-binding of variables
- **select-001**: SPARQL SELECT-based constraint

## Test Format

Each test file is in Turtle (.ttl) format and contains:

1. **Test metadata**:
   - Type: `sht:Validate`
   - Label: Human-readable test description
   - Status: `sht:approved`

2. **Test action**:
   - Data graph (inline or reference)
   - Shapes graph (inline or reference)

3. **Expected result**:
   - Conformance boolean (`sh:conforms`)
   - Expected validation results (focus nodes, constraint components, etc.)

## Usage

Tests are used by:
1. `lib/elixir_ontologies/shacl/w3c_test_runner.ex` - Manifest parser
2. `test/elixir_ontologies/w3c_test.exs` - Dynamic ExUnit test generation

## Compliance Levels

Per W3C spec, implementations can report:

- **Partial compliance**: Conformance checking only (boolean `sh:conforms` matching)
- **Full compliance**: Complete validation report matching via graph isomorphism

Our implementation targets **partial compliance** with focus on:
- Correct conformance boolean (sh:conforms)
- Correct violation count
- Correct constraint components identified

## Known Limitations

See `LIMITATIONS.md` in the project root for documented limitations of the native SHACL implementation, particularly:

- SPARQL.ex library limitations with nested subqueries
- Complex FILTER NOT EXISTS patterns
- Expected pass rates: >90% for core tests, >50% for SPARQL tests

## Updating Tests

To re-download tests:

```bash
cd test/fixtures/w3c
./download_tests.sh
```

## Attribution

Tests copyright © W3C (MIT, ERCIM, Keio, Beihang). Used under W3C Software and Document License.
See: https://www.w3.org/Consortium/Legal/2015/copyright-software-and-document
