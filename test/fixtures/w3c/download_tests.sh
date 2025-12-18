#!/bin/bash

# Download W3C SHACL Test Suite - Curated Selection
# Source: https://github.com/w3c/data-shapes/tree/gh-pages/data-shapes-test-suite

BASE_URL="https://raw.githubusercontent.com/w3c/data-shapes/gh-pages/data-shapes-test-suite/tests"

# Core Node Tests (testing node shapes and basic constraints)
NODE_TESTS=(
  "class-001" "class-002" "class-003"
  "datatype-001" "datatype-002"
  "minInclusive-001" "minInclusive-002" "minInclusive-003"
  "maxInclusive-001"
  "minExclusive-001"
  "maxExclusive-001"
  "minLength-001"
  "maxLength-001"
  "pattern-001" "pattern-002"
  "nodeKind-001"
  "hasValue-001"
  "in-001"
  "languageIn-001"
  "and-001" "and-002"
  "or-001"
  "not-001" "not-002"
  "xone-001" "xone-duplicate"
  "closed-001" "closed-002"
  "equals-001"
  "disjoint-001"
  "node-001"
  "qualified-001"
)

# Core Property Tests (testing property shapes)
PROPERTY_TESTS=(
  "class-001"
  "datatype-001"
  "minCount-001"
  "maxCount-001"
  "minLength-001"
  "maxLength-001"
  "pattern-001"
  "uniqueLang-001"
)

# Core Path Tests (testing property paths)
PATH_TESTS=(
  "path-sequence-001"
  "path-alternative-001"
  "path-inverse-001"
  "path-zeroOrMore-001"
  "path-oneOrMore-001"
)

# Core Target Tests (testing target mechanisms)
TARGET_TESTS=(
  "targetNode-001"
  "targetClass-001"
  "targetSubjectsOf-001"
  "targetObjectsOf-001"
)

# SPARQL Tests (testing SPARQL-based constraints)
SPARQL_TESTS=(
  "component-001"
  "pre-binding-001"
  "select-001"
)

echo "Downloading W3C SHACL Test Suite..."
echo "===================================="

# Download Node tests
echo "Downloading node tests..."
cd core
for test in "${NODE_TESTS[@]}"; do
  url="${BASE_URL}/core/node/${test}.ttl"
  echo "  $test.ttl"
  curl -s "$url" -o "${test}.ttl"
done

# Download Property tests
echo "Downloading property tests..."
for test in "${PROPERTY_TESTS[@]}"; do
  url="${BASE_URL}/core/property/${test}.ttl"
  echo "  property-$test.ttl"
  curl -s "$url" -o "property-${test}.ttl"
done

# Download Path tests
echo "Downloading path tests..."
for test in "${PATH_TESTS[@]}"; do
  url="${BASE_URL}/core/path/${test}.ttl"
  echo "  $test.ttl"
  curl -s "$url" -o "${test}.ttl"
done

# Download Target tests
echo "Downloading target tests..."
for test in "${TARGET_TESTS[@]}"; do
  url="${BASE_URL}/core/targets/${test}.ttl"
  echo "  $test.ttl"
  curl -s "$url" -o "${test}.ttl"
done

# Download SPARQL tests
echo "Downloading SPARQL tests..."
cd ../sparql
for test in "${SPARQL_TESTS[@]}"; do
  url="${BASE_URL}/sparql/node/${test}.ttl"
  echo "  $test.ttl"
  curl -s "$url" -o "${test}.ttl"
done

cd ..
echo ""
echo "Download complete!"
echo "Core tests: $(ls core/*.ttl 2>/dev/null | wc -l)"
echo "SPARQL tests: $(ls sparql/*.ttl 2>/dev/null | wc -l)"
