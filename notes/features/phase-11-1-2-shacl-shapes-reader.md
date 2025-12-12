# Feature 11.1.2: SHACL Shapes Reader

## Problem Statement

Task 11.1.1 successfully created internal Elixir structs for representing SHACL shapes (NodeShape, PropertyShape, SPARQLConstraint) and validation results (ValidationResult, ValidationReport). However, these structs are currently empty - we need a way to populate them by parsing SHACL shapes from RDF graphs.

The SHACL Shapes Reader must:

1. **Parse elixir-shapes.ttl** - Read the 597-line shapes file containing 29 node shapes with various constraint types
2. **Extract node shapes** - Identify all sh:NodeShape instances and their sh:targetClass declarations
3. **Parse property constraints** - Extract all property shapes with their diverse constraint types (cardinality, type, string, value, qualified)
4. **Parse SPARQL constraints** - Extract the 3 SPARQL-based constraints (SourceLocation, FunctionArityMatch, ProtocolCompliance)
5. **Handle RDF lists** - Parse sh:in constraints that use RDF lists for value enumerations (e.g., supervisor strategies)
6. **Compile regex patterns** - Convert sh:pattern string values into compiled Elixir Regex.t() structs for efficient validation
7. **Preserve blank nodes** - Correctly handle blank node identifiers for property shapes

Without this reader, the SHACL data model structs cannot be populated from actual shapes files, blocking the implementation of the native SHACL validator.

## Solution Overview

Create `lib/elixir_ontologies/shacl/reader.ex` as the RDF-to-struct parsing layer that converts SHACL shapes graphs into Elixir data structures. The reader will use RDF.ex's graph querying capabilities to extract shapes and constraints systematically.

**Architecture:**

```
Input: RDF.Graph (from RDF.Turtle.read_file/1)
  ↓
Reader.parse_shapes/2
  ├─ find_node_shapes/1          → Identify all sh:NodeShape instances
  ├─ parse_node_shape/2          → Extract node shape components
  │   ├─ extract_target_classes/2   → Get sh:targetClass IRIs
  │   ├─ parse_property_shapes/2    → Parse sh:property blank nodes
  │   └─ parse_sparql_constraints/2 → Parse sh:sparql constraints
  ├─ parse_property_shape/2      → Build PropertyShape struct
  │   ├─ extract_cardinality/2      → sh:minCount, sh:maxCount
  │   ├─ extract_type_constraints/2 → sh:datatype, sh:class
  │   ├─ extract_string_constraints/2 → sh:pattern, sh:minLength
  │   ├─ extract_value_constraints/2  → sh:in, sh:hasValue
  │   └─ extract_qualified_constraints/2 → sh:qualifiedValueShape
  └─ parse_sparql_constraint/2   → Build SPARQLConstraint struct
      ├─ extract_select_query/2     → sh:select query string
      └─ extract_prefixes/2         → sh:prefixes reference
  ↓
Output: {:ok, [NodeShape.t()]} or {:error, reason}
```

**Key Design Decisions:**

1. **Use RDF.Graph.description/2** for pivoting around subjects (shapes, property constraints)
2. **Pattern matching on RDF.Literal** for extracting typed values (integers, strings, booleans)
3. **Store compiled Regex.t()** for sh:pattern (not string) to optimize validation performance
4. **Preserve RDF.BlankNode.t()** identities for property shapes (needed for report generation)
5. **Lazy SPARQL parsing** - Store query strings as-is, defer prefix resolution to execution time
6. **Fail fast** - Return {:error, reason} for malformed shapes rather than silently skipping

## Technical Details

### File Structure

```
lib/elixir_ontologies/shacl/
├── model/
│   ├── node_shape.ex          # ✓ Exists (from 11.1.1)
│   ├── property_shape.ex      # ✓ Exists (from 11.1.1)
│   ├── sparql_constraint.ex   # ✓ Exists (from 11.1.1)
│   ├── validation_result.ex   # ✓ Exists (from 11.1.1)
│   └── validation_report.ex   # ✓ Exists (from 11.1.1)
└── reader.ex                  # NEW - This task
```

### Implementation Details (from notes/research/shacl_engine.md lines 222-270)

#### 1. Main Entry Point: parse_shapes/2

```elixir
@spec parse_shapes(RDF.Graph.t(), keyword()) :: {:ok, [NodeShape.t()]} | {:error, term()}
def parse_shapes(shapes_graph, opts \\ []) do
  with {:ok, shape_iris} <- find_node_shapes(shapes_graph),
       {:ok, shapes} <- parse_all_node_shapes(shapes_graph, shape_iris, opts) do
    {:ok, shapes}
  end
end
```

**Parameters:**
- `shapes_graph` - RDF.Graph.t() loaded from elixir-shapes.ttl
- `opts` - Keyword list for options (reserved for future use)

**Returns:**
- `{:ok, [NodeShape.t()]}` - Successfully parsed shapes
- `{:error, reason}` - Parse error with diagnostic message

#### 2. Finding Node Shapes

```elixir
@spec find_node_shapes(RDF.Graph.t()) :: {:ok, [RDF.IRI.t() | RDF.BlankNode.t()]} | {:error, term()}
defp find_node_shapes(graph) do
  # Query: ?shape rdf:type sh:NodeShape
  shapes =
    graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, o} ->
      p == RDF.type() && o == SH.NodeShape
    end)
    |> Enum.map(fn {s, _p, _o} -> s end)

  {:ok, shapes}
end
```

**Expected Results from elixir-shapes.ttl:**
- 29 node shapes from :ModuleShape to :ChangeSetShape
- All are named IRIs (no blank node shapes in our file)

#### 3. Parsing Individual Node Shapes

```elixir
@spec parse_node_shape(RDF.Graph.t(), RDF.IRI.t() | RDF.BlankNode.t()) ::
  {:ok, NodeShape.t()} | {:error, term()}
defp parse_node_shape(graph, shape_id) do
  desc = RDF.Graph.description(graph, shape_id)

  with {:ok, target_classes} <- extract_target_classes(desc),
       {:ok, property_shapes} <- parse_property_shapes(graph, desc),
       {:ok, sparql_constraints} <- parse_sparql_constraints(graph, shape_id, desc) do
    {:ok, %NodeShape{
      id: shape_id,
      target_classes: target_classes,
      property_shapes: property_shapes,
      sparql_constraints: sparql_constraints
    }}
  end
end
```

#### 4. Extracting Target Classes

```elixir
@spec extract_target_classes(RDF.Description.t()) :: {:ok, [RDF.IRI.t()]} | {:error, term()}
defp extract_target_classes(desc) do
  # sh:targetClass can be single or multiple
  targets = desc[SH.targetClass] |> RDF.Description.objects() |> Enum.to_list()
  {:ok, targets}
end
```

**Examples from elixir-shapes.ttl:**
- `:ModuleShape sh:targetClass struct:Module` → Single target
- Most shapes have exactly one target class
- Some specialized shapes may have multiple targets (future extension)

#### 5. Parsing Property Shapes

```elixir
@spec parse_property_shapes(RDF.Graph.t(), RDF.Description.t()) ::
  {:ok, [PropertyShape.t()]} | {:error, term()}
defp parse_property_shapes(graph, node_shape_desc) do
  # sh:property points to blank nodes
  property_nodes = node_shape_desc[SH.property] |> RDF.Description.objects() |> Enum.to_list()

  property_nodes
  |> Enum.map(&parse_property_shape(graph, &1))
  |> collect_results()  # Helper to aggregate {:ok, ...} or return first {:error, ...}
end

@spec parse_property_shape(RDF.Graph.t(), RDF.BlankNode.t()) ::
  {:ok, PropertyShape.t()} | {:error, term()}
defp parse_property_shape(graph, property_node) do
  desc = RDF.Graph.description(graph, property_node)

  with {:ok, path} <- extract_path(desc),
       {:ok, message} <- extract_message(desc),
       {:ok, cardinality} <- extract_cardinality(desc),
       {:ok, type_constraints} <- extract_type_constraints(desc),
       {:ok, string_constraints} <- extract_string_constraints(desc),
       {:ok, value_constraints} <- extract_value_constraints(graph, desc),
       {:ok, qualified_constraints} <- extract_qualified_constraints(graph, desc) do
    {:ok, %PropertyShape{
      id: property_node,
      path: path,
      message: message,
      min_count: cardinality.min_count,
      max_count: cardinality.max_count,
      datatype: type_constraints.datatype,
      class: type_constraints.class,
      pattern: string_constraints.pattern,
      min_length: string_constraints.min_length,
      in: value_constraints.in,
      has_value: value_constraints.has_value,
      qualified_class: qualified_constraints.qualified_class,
      qualified_min_count: qualified_constraints.qualified_min_count
    }}
  end
end
```

#### 6. Constraint Extraction Functions

**Cardinality (sh:minCount, sh:maxCount):**

```elixir
defp extract_cardinality(desc) do
  min_count = desc[SH.minCount] |> extract_integer()
  max_count = desc[SH.maxCount] |> extract_integer()
  {:ok, %{min_count: min_count, max_count: max_count}}
end

defp extract_integer(nil), do: nil
defp extract_integer(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
```

**Type Constraints (sh:datatype, sh:class):**

```elixir
defp extract_type_constraints(desc) do
  datatype = desc[SH.datatype] |> extract_iri()
  class = desc[SH.class] |> extract_iri()
  {:ok, %{datatype: datatype, class: class}}
end

defp extract_iri(nil), do: nil
defp extract_iri(%RDF.IRI{} = iri), do: iri
```

**String Constraints (sh:pattern, sh:minLength):**

```elixir
defp extract_string_constraints(desc) do
  pattern_string = desc[SH.pattern] |> extract_string()
  pattern = if pattern_string, do: Regex.compile!(pattern_string), else: nil

  min_length = desc[SH.minLength] |> extract_integer()

  {:ok, %{pattern: pattern, min_length: min_length}}
end

defp extract_string(nil), do: nil
defp extract_string(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
```

**Examples from elixir-shapes.ttl:**
- `sh:pattern "^[A-Z][A-Za-z0-9_]*(\\.[A-Z][A-Za-z0-9_]*)*$"` → Module name pattern
- `sh:pattern "^[a-z_][a-z0-9_]*[!?]?$"` → Function name pattern
- `sh:pattern "^[a-f0-9]{40}$"` → Git commit hash pattern

#### 7. Value Constraints (sh:in, sh:hasValue)

**RDF List Parsing for sh:in:**

```elixir
defp extract_value_constraints(graph, desc) do
  # sh:in points to an RDF list (rdf:first, rdf:rest)
  in_list_head = desc[SH.in] |> extract_iri()
  in_values = if in_list_head, do: parse_rdf_list(graph, in_list_head), else: []

  has_value = desc[SH.hasValue] |> extract_term()

  {:ok, %{in: in_values, has_value: has_value}}
end

@spec parse_rdf_list(RDF.Graph.t(), RDF.IRI.t() | RDF.BlankNode.t()) :: [RDF.Term.t()]
defp parse_rdf_list(graph, list_node) do
  case RDF.Graph.description(graph, list_node) do
    nil -> []
    desc ->
      first = desc[RDF.first()] |> extract_term()
      rest = desc[RDF.rest()] |> extract_iri()

      case rest do
        RDF.nil() -> [first]
        next_node -> [first | parse_rdf_list(graph, next_node)]
      end
  end
end

defp extract_term(nil), do: nil
defp extract_term(term), do: term  # Can be IRI, Literal, or BlankNode
```

**Examples from elixir-shapes.ttl (lines 332, 369, 376, 411, 417):**

```turtle
# Supervisor strategies (line 332)
sh:in ( otp:OneForOne otp:OneForAll otp:RestForOne )

# Child restart strategies (line 369)
sh:in ( otp:Permanent otp:Temporary otp:Transient )

# Child types (line 376)
sh:in ( otp:WorkerType otp:SupervisorType )

# ETS table types (line 411)
sh:in ( otp:SetTable otp:OrderedSetTable otp:BagTable otp:DuplicateBagTable )

# ETS access types (line 417)
sh:in ( otp:PublicTable otp:ProtectedTable otp:PrivateTable )
```

#### 8. Qualified Constraints (sh:qualifiedValueShape)

```elixir
defp extract_qualified_constraints(graph, desc) do
  # sh:qualifiedValueShape points to a blank node with sh:class
  qualified_shape_node = desc[SH.qualifiedValueShape] |> extract_iri()

  qualified_class =
    if qualified_shape_node do
      qualified_desc = RDF.Graph.description(graph, qualified_shape_node)
      qualified_desc[SH.class] |> extract_iri()
    else
      nil
    end

  qualified_min_count = desc[SH.qualifiedMinCount] |> extract_integer()

  {:ok, %{
    qualified_class: qualified_class,
    qualified_min_count: qualified_min_count
  }}
end
```

**Example from elixir-shapes.ttl (lines 390-396):**

```turtle
:GenServerImplementationShape a sh:NodeShape ;
    sh:targetClass otp:GenServerImplementation ;
    sh:property [
        sh:path otp:hasGenServerCallback ;
        sh:qualifiedValueShape [
            sh:class otp:InitCallback
        ] ;
        sh:qualifiedMinCount 1 ;
        sh:message "GenServer implementation should have init/1 callback"@en
    ] .
```

#### 9. Parsing SPARQL Constraints

```elixir
@spec parse_sparql_constraints(RDF.Graph.t(), RDF.IRI.t(), RDF.Description.t()) ::
  {:ok, [SPARQLConstraint.t()]} | {:error, term()}
defp parse_sparql_constraints(graph, shape_id, node_shape_desc) do
  # sh:sparql points to blank nodes with sh:select and sh:message
  sparql_nodes = node_shape_desc[SH.sparql] |> RDF.Description.objects() |> Enum.to_list()

  sparql_nodes
  |> Enum.map(&parse_sparql_constraint(graph, shape_id, &1))
  |> collect_results()
end

@spec parse_sparql_constraint(RDF.Graph.t(), RDF.IRI.t(), RDF.BlankNode.t()) ::
  {:ok, SPARQLConstraint.t()} | {:error, term()}
defp parse_sparql_constraint(graph, shape_id, sparql_node) do
  desc = RDF.Graph.description(graph, sparql_node)

  message = desc[SH.message] |> extract_string()
  select_query = desc[SH.select] |> extract_string()
  prefixes_ref = desc[SH.prefixes] |> extract_iri()

  # For now, store prefixes_ref but don't resolve (defer to execution time)
  {:ok, %SPARQLConstraint{
    source_shape_id: shape_id,
    message: message,
    select_query: select_query,
    prefixes_graph: nil  # Will be populated by validator when needed
  }}
end
```

**Examples from elixir-shapes.ttl:**

**1. SourceLocationShape (lines 309-320):**

```turtle
sh:sparql [
    sh:message "End line must be >= start line" ;
    sh:prefixes <https://w3id.org/elixir-code/shapes> ;
    sh:select """
        SELECT $this ?startLine ?endLine
        WHERE {
            $this core:startLine ?startLine .
            $this core:endLine ?endLine .
            FILTER (?endLine < ?startLine)
        }
    """
] .
```

**2. FunctionArityMatchShape (lines 556-576):**

```turtle
sh:sparql [
    sh:message "Function arity should match parameter count in first clause" ;
    sh:prefixes <https://w3id.org/elixir-code/shapes> ;
    sh:select """
        SELECT $this ?arity ?paramCount
        WHERE {
            $this struct:arity ?arity .
            $this struct:hasClause ?clause .
            ?clause struct:clauseOrder 1 .
            ?clause struct:hasHead ?head .
            {
                SELECT ?head (COUNT(?param) AS ?paramCount)
                WHERE {
                    ?head struct:hasParameter ?param .
                }
                GROUP BY ?head
            }
            FILTER (?arity != ?paramCount)
        }
    """
] .
```

**3. ProtocolComplianceShape (lines 581-596):**

```turtle
sh:sparql [
    sh:message "Protocol implementation should implement all protocol functions" ;
    sh:prefixes <https://w3id.org/elixir-code/shapes> ;
    sh:select """
        SELECT $this ?protocol ?missingFunc
        WHERE {
            $this struct:implementsProtocol ?protocol .
            ?protocol struct:definesProtocolFunction ?missingFunc .
            FILTER NOT EXISTS {
                $this struct:containsFunction ?implFunc .
                ?implFunc struct:functionName ?name .
                ?missingFunc struct:functionName ?name .
            }
        }
    """
] .
```

### SHACL Vocabulary Constants

Create a namespace module for SHACL predicates:

```elixir
# In reader.ex or separate shacl/vocabulary.ex
defmodule ElixirOntologies.SHACL.Vocabulary do
  use RDF.Vocabulary.Namespace

  defvocab SH,
    base_iri: "http://www.w3.org/ns/shacl#",
    terms: [
      :NodeShape,
      :targetClass,
      :property,
      :path,
      :message,
      :minCount,
      :maxCount,
      :datatype,
      :class,
      :pattern,
      :minLength,
      :in,
      :hasValue,
      :qualifiedValueShape,
      :qualifiedMinCount,
      :sparql,
      :select,
      :prefixes
    ]
end
```

### Error Handling Strategy

The reader should be strict and fail-fast:

```elixir
# Missing required fields
{:error, "Property shape missing required sh:path"}
{:error, "Node shape #{inspect(id)} missing sh:targetClass"}

# Invalid data types
{:error, "sh:minCount must be non-negative integer, got: #{inspect(value)}"}
{:error, "sh:pattern must be valid regex, compilation failed: #{inspect(error)}"}

# Malformed RDF lists
{:error, "sh:in list is malformed at node #{inspect(node)}"}
```

### Performance Considerations

1. **RDF.Graph.description/2** - O(1) lookup by subject, efficient for pivoting
2. **Regex compilation** - Done once at parse time, not per-validation
3. **Lazy SPARQL prefix resolution** - Deferred to execution time (avoid unnecessary work)
4. **No graph traversal** - Direct property access via predicates, no recursive walking

**Expected Performance:**
- Parse elixir-shapes.ttl (29 shapes, ~100 property shapes, 3 SPARQL constraints) in <100ms
- Memory overhead: ~50KB for parsed shape structs (vs ~150KB for raw RDF graph)

## Success Criteria

### Functional Requirements

1. **Parse all 29 node shapes** from elixir-shapes.ttl correctly
2. **Extract all target classes** (sh:targetClass) for each shape
3. **Parse all property shapes** including:
   - Cardinality constraints (sh:minCount, sh:maxCount) - 70+ occurrences
   - Type constraints (sh:datatype, sh:class) - 60+ occurrences
   - String constraints (sh:pattern, sh:minLength) - 15+ patterns, 1 minLength
   - Value constraints (sh:in, sh:hasValue) - 5 RDF lists, 1 hasValue
   - Qualified constraints (sh:qualifiedValueShape) - 1 occurrence
4. **Parse all 3 SPARQL constraints** with correct query strings and messages
5. **Handle all 5 RDF lists** used in sh:in constraints
6. **Compile all 15+ regex patterns** from sh:pattern constraints
7. **Preserve blank node identities** for property shapes
8. **Return meaningful errors** for malformed shapes

### Test Coverage

**Target: 20+ tests**

#### Node Shape Parsing Tests (5 tests)
- Parse simple node shape with single target class
- Parse node shape with multiple property shapes
- Parse node shape with SPARQL constraints
- Handle node shape without target class (should succeed, empty list)
- Handle malformed node shape structure

#### Property Shape Parsing Tests (10 tests)
- Parse cardinality constraints (minCount, maxCount)
- Parse datatype constraint (xsd:string, xsd:nonNegativeInteger, etc.)
- Parse class constraint (struct:Module, otp:Process, etc.)
- Parse pattern constraint and verify Regex.t() compilation
- Parse minLength constraint
- Parse sh:in with RDF list (supervisor strategies)
- Parse sh:hasValue constraint (DynamicSupervisor strategy)
- Parse qualified constraint (GenServer init callback)
- Handle property shape missing required path (error)
- Handle invalid regex pattern (error)

#### SPARQL Constraint Parsing Tests (3 tests)
- Parse SourceLocationShape SPARQL constraint
- Parse FunctionArityMatchShape SPARQL constraint with aggregation
- Parse ProtocolComplianceShape SPARQL constraint with FILTER NOT EXISTS

#### RDF List Parsing Tests (2 tests)
- Parse simple RDF list (3 items: OneForOne, OneForAll, RestForOne)
- Parse nested/complex RDF list if present in shapes

#### Integration Tests (2+ tests)
- Parse entire elixir-shapes.ttl file and verify shape count (29 shapes)
- Parse elixir-shapes.ttl and verify specific shape details:
  - ModuleShape has 4 property shapes
  - FunctionShape has 4 property shapes + 1 SPARQL constraint
  - SupervisorShape has sh:in with 3 strategies
  - GenServerImplementationShape has qualified constraint

#### Error Handling Tests (3 tests)
- Invalid shapes graph (empty, malformed TTL)
- Missing required fields (path, targetClass)
- Invalid data types (non-integer for minCount, invalid regex)

### Quality Requirements

1. **Comprehensive documentation** with @moduledoc and @doc for all public functions
2. **Type specifications** with @spec for all functions
3. **Property-based examples** in documentation showing actual elixir-shapes.ttl patterns
4. **Error messages** that are actionable (include shape ID, constraint type, reason)
5. **Code organization** with clear separation of concerns (finding vs parsing vs extracting)

### Integration Points

The reader must integrate with:

1. **SHACL.Model modules** - Produce valid NodeShape.t(), PropertyShape.t(), SPARQLConstraint.t() structs
2. **RDF.ex** - Use RDF.Graph, RDF.Description, RDF.IRI, RDF.Literal, RDF.BlankNode correctly
3. **Future SHACL.Validator** - Parsed shapes will be consumed by validation engine
4. **Future SHACL.Writer** - Blank node IDs must be preserved for round-trip serialization

## Implementation Plan

### Step 1: Setup and Vocabulary (11.1.2.1)

**Time Estimate: 30 minutes**

1. Create `lib/elixir_ontologies/shacl/reader.ex`
2. Define SHACL vocabulary constants (SH namespace)
3. Add basic module structure with aliases and module documentation
4. Define helper functions: `extract_integer/1`, `extract_string/1`, `extract_iri/1`, `extract_term/1`
5. Create `collect_results/1` helper for aggregating {:ok, ...} results

**Deliverable:** Module skeleton with vocabulary and utility functions

### Step 2: Node Shape Discovery (11.1.2.2 - parse_shapes/2)

**Time Estimate: 45 minutes**

1. Implement `parse_shapes/2` main entry point
2. Implement `find_node_shapes/1` to query for sh:NodeShape instances
3. Implement `parse_all_node_shapes/3` to map over shape IRIs
4. Implement `parse_node_shape/2` to extract target classes (simple version, no properties/SPARQL yet)
5. Write tests:
   - Parse elixir-shapes.ttl and count shapes (29 expected)
   - Parse simple node shape with target class
   - Handle empty graph
   - Handle graph with no node shapes

**Deliverable:** Basic node shape extraction working, tests passing

### Step 3: Property Shape Parsing (11.1.2.3)

**Time Estimate: 2 hours**

1. Implement `parse_property_shapes/2` to find sh:property blank nodes
2. Implement `parse_property_shape/2` skeleton
3. Implement `extract_path/1` (required field)
4. Implement `extract_message/1` (optional field)
5. Implement `extract_cardinality/1` (sh:minCount, sh:maxCount)
6. Implement `extract_type_constraints/1` (sh:datatype, sh:class)
7. Write tests:
   - Parse ModuleShape property shapes (4 properties)
   - Parse FunctionShape property shapes (4 properties)
   - Verify cardinality constraints
   - Verify datatype constraints (xsd:string, xsd:nonNegativeInteger)
   - Verify class constraints (struct:Module, struct:Function)
   - Handle missing sh:path (error)

**Deliverable:** Basic property shape parsing with cardinality and type constraints

### Step 4: String and Value Constraints (11.1.2.5, 11.1.2.6)

**Time Estimate: 1.5 hours**

1. Implement `extract_string_constraints/1` (sh:pattern, sh:minLength)
2. Add regex compilation for sh:pattern with error handling
3. Implement `extract_value_constraints/2` (sh:in, sh:hasValue) - stub RDF list parsing
4. Implement `parse_rdf_list/2` to walk rdf:first/rdf:rest chains
5. Write tests:
   - Parse and compile module name pattern regex
   - Parse and compile function name pattern regex
   - Parse and compile commit hash pattern regex
   - Handle invalid regex pattern (error)
   - Parse SupervisorShape sh:in list (3 strategies)
   - Parse ChildSpecShape restart strategies (3 values)
   - Parse DynamicSupervisorShape sh:hasValue (OneForOne)
   - Parse nested RDF list correctly

**Deliverable:** Complete property shape parsing including patterns and RDF lists

### Step 5: Qualified Constraints (11.1.2.3 continued)

**Time Estimate: 45 minutes**

1. Implement `extract_qualified_constraints/2`
2. Handle sh:qualifiedValueShape blank node traversal
3. Extract sh:class from qualified shape
4. Extract sh:qualifiedMinCount
5. Write tests:
   - Parse GenServerImplementationShape qualified constraint
   - Verify qualified_class is otp:InitCallback
   - Verify qualified_min_count is 1
   - Handle missing qualified shape gracefully

**Deliverable:** Complete PropertyShape parsing with all constraint types

### Step 6: SPARQL Constraint Parsing (11.1.2.4)

**Time Estimate: 1 hour**

1. Implement `parse_sparql_constraints/3`
2. Implement `parse_sparql_constraint/4`
3. Extract sh:message, sh:select, sh:prefixes
4. Store query string with $this placeholder intact
5. Write tests:
   - Parse SourceLocationShape SPARQL constraint
   - Parse FunctionArityMatchShape SPARQL constraint
   - Parse ProtocolComplianceShape SPARQL constraint
   - Verify message strings
   - Verify query strings contain $this placeholder
   - Verify shape_id reference is correct

**Deliverable:** Complete SPARQL constraint parsing

### Step 7: Integration Testing (11.1.2.7)

**Time Estimate: 1.5 hours**

1. Create comprehensive integration test
2. Parse full elixir-shapes.ttl file
3. Verify all 29 shapes are parsed
4. Verify specific shape structures:
   - ModuleShape: 4 properties, 0 SPARQL
   - FunctionShape: 4 properties, 1 SPARQL
   - SupervisorShape: sh:in with 3 values
   - SourceLocationShape: 1 SPARQL constraint
5. Create test fixtures for edge cases
6. Add error handling tests
7. Document all test cases clearly

**Deliverable:** 20+ comprehensive tests, all passing

### Step 8: Documentation and Polish (11.1.2.1 continued)

**Time Estimate: 1 hour**

1. Write comprehensive @moduledoc with examples
2. Add @doc to all public functions
3. Add @spec to all functions (public and private)
4. Add inline comments for complex logic (RDF list parsing, qualified constraints)
5. Add examples from elixir-shapes.ttl to documentation
6. Review error messages for clarity
7. Run Credo and Dialyzer
8. Update this planning document with completion notes

**Deliverable:** Fully documented, type-specified, production-ready reader module

### Total Time Estimate: 8-9 hours

## Notes and Considerations

### RDF.ex API Usage

The reader relies on these RDF.ex functions:

```elixir
# Graph querying
RDF.Graph.triples(graph)              # Get all triples
RDF.Graph.description(graph, subject) # Get all statements about subject

# Description access
desc[predicate]                       # Get objects for predicate
RDF.Description.objects(desc)         # Get all objects as enumerable

# Type checking and extraction
RDF.Literal.value(literal)            # Extract Elixir value from literal
RDF.type()                            # rdf:type IRI
RDF.first()                           # rdf:first for lists
RDF.rest()                            # rdf:rest for lists
RDF.nil()                             # rdf:nil terminal
```

### Known Limitations

1. **Simple paths only** - Currently assumes sh:path is always a single IRI, not a property path expression
2. **No sh:or/sh:and/sh:not** - Complex logical constraints not supported (not used in elixir-shapes.ttl)
3. **No sh:node** - Recursive shape references not supported (not used in our shapes)
4. **No sh:targetNode/sh:targetSubjectsOf** - Only sh:targetClass is supported
5. **Simplified qualified shapes** - Only handles sh:qualifiedValueShape with sh:class, not nested constraints

These limitations are acceptable because elixir-shapes.ttl doesn't use these advanced features.

### Future Extensions

When needed, the reader can be extended to support:

1. **Complex property paths** - sh:inversePath, sh:alternativePath, etc.
2. **Logical operators** - sh:or, sh:and, sh:not, sh:xone
3. **Shape composition** - sh:node for referencing other shapes
4. **Additional target types** - sh:targetNode, sh:targetSubjectsOf, sh:targetObjectsOf
5. **Severity levels** - sh:severity (currently defaults to sh:Violation)
6. **Deactivated shapes** - sh:deactivated flag

### Relationship to Other Tasks

**Depends On:**
- 11.1.1 SHACL Data Model ✓ Complete (provides structs)

**Enables:**
- 11.1.3 Validation Report Writer (uses NodeShape IDs for reporting)
- 11.2.1 Core Constraint Validators (consumes PropertyShape structs)
- 11.2.2 Main Validator Engine (consumes NodeShape list)
- 11.3.1 SPARQL Constraint Evaluator (consumes SPARQLConstraint structs)

**Integration Point:**
- All parsed shapes will be loaded once at validator initialization
- Shapes can be cached/memoized for repeated validations
- Reader is stateless - pure function from RDF.Graph to [NodeShape.t()]

### Testing Strategy

**Unit Tests (15 tests):**
- Test each extraction function in isolation
- Test RDF list parsing edge cases
- Test regex compilation error handling
- Test blank node handling

**Integration Tests (5 tests):**
- Parse real elixir-shapes.ttl file
- Verify specific shape structures
- Test with modified shapes for edge cases

**Property-Based Tests (Future):**
- Generate random valid SHACL graphs
- Verify parser never crashes
- Verify round-trip: Graph → Shapes → Graph (when writer exists)

### Performance Benchmarks

Target benchmarks for reader performance:

```
Parsing elixir-shapes.ttl:
- Load TTL file:        ~20ms
- Parse to shapes:      ~50ms
- Total:                ~70ms

Memory usage:
- RDF.Graph:            ~150KB
- Parsed shapes:        ~50KB
- Total overhead:       ~200KB
```

These are acceptable for a shapes file that's loaded once at application startup.

### Documentation Examples

Each public function should have examples using actual data from elixir-shapes.ttl:

```elixir
## Examples

    iex> {:ok, graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")
    iex> {:ok, shapes} = Reader.parse_shapes(graph)
    iex> length(shapes)
    29

    iex> module_shape = Enum.find(shapes, &(&1.id == ~I<https://w3id.org/elixir-code/shapes#ModuleShape>))
    iex> length(module_shape.property_shapes)
    4
    iex> module_shape.target_classes
    [~I<https://w3id.org/elixir-code/structure#Module>]
```

This makes documentation immediately practical and testable.
