# Phase 12.1.4: Clause Builder Planning Document

## 1. Problem Statement

Phase 12.1.3 implemented the Function Builder, which creates RDF triples for function-level metadata. Now we need to implement the Clause Builder to represent individual function clauses with their heads (parameters, guards) and bodies.

**The Challenge**: Function clauses are the most complex builder so far, requiring:
- Nested RDF structures with blank nodes for FunctionHead and FunctionBody
- RDF lists for ordered parameter sequences (preserving pattern-match order)
- Multiple parameter types (simple, default, pattern) each requiring different RDF structures
- Guard expressions if present
- Proper 1-indexed ordering (clauseOrder, parameterPosition)

**Current State**:
- Clause extractor exists at `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/clause.ex`
- Parameter extractor exists at `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/parameter.ex`
- `Helpers.build_rdf_list/1` is available for creating RDF lists
- `IRI.for_clause/2` and `IRI.for_parameter/2` are available
- Builder infrastructure and helpers are complete

**The Gap**: We need to:
1. Generate clause IRIs using `IRI.for_clause(function_iri, clause_order)` (0-indexed in IRI, but 1-indexed in RDF)
2. Create FunctionHead blank nodes with parameter lists
3. Create FunctionBody blank nodes
4. Build ordered parameter lists as RDF lists using `build_rdf_list/1`
5. Handle different parameter types (simple, default, pattern)
6. Handle guards if present
7. Link clause to function via `hasClause` property
8. Track clause ordering with `clauseOrder` datatype property (1-indexed)

## 2. Solution Overview

Create a **Clause Builder** that transforms `Clause.t()` structs into RDF triples with proper nested structure.

### 2.1 Core Functionality

The builder will:
- Generate stable IRIs for clauses using `IRI.for_clause(function_iri, order - 1)` (convert 1-indexed to 0-indexed)
- Create blank nodes for FunctionHead and FunctionBody
- Build RDF lists for ordered parameters
- Generate parameter IRIs and their properties
- Handle different parameter types (Parameter, DefaultParameter, PatternParameter)
- Create `hasClause` triple from function to clause
- Support guards if present

### 2.2 RDF Structure Pattern

The key pattern is nested blank nodes with RDF lists:

```turtle
# Clause with parameters
<base#Module/func/1> struct:hasClause <base#Module/func/1/clause/0> .

<base#Module/func/1/clause/0> a struct:FunctionClause ;
    struct:clauseOrder "1"^^xsd:positiveInteger ;
    struct:hasHead _:head1 ;
    struct:hasBody _:body1 .

_:head1 a struct:FunctionHead ;
    struct:hasParameters ( <param0> <param1> ) .  # RDF list

<param0> a core:Parameter ;
    core:parameterName "x"^^xsd:string ;
    core:parameterPosition "1"^^xsd:positiveInteger .

<param1> a struct:DefaultParameter ;
    core:parameterName "timeout"^^xsd:string ;
    core:parameterPosition "2"^^xsd:positiveInteger ;
    struct:hasDefaultValue _:default1 .

_:body1 a struct:FunctionBody .
```

### 2.3 Integration Point

The Clause Builder will be called from Function Builder or a higher-level orchestrator when building complete function representations with clauses.

## 3. Technical Details

### 3.1 Clause Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/clause.ex`:

```elixir
%ElixirOntologies.Extractors.Clause{
  name: atom(),                               # :get_user, :process, etc.
  arity: non_neg_integer(),                   # Number of parameters
  visibility: :public | :private,
  order: pos_integer(),                       # 1-indexed clause order
  head: %{
    parameters: [Macro.t()],                  # List of parameter AST nodes
    guard: Macro.t() | nil                    # Guard expression if present
  },
  body: Macro.t() | nil,                      # Function body AST
  location: SourceLocation.t() | nil,
  metadata: %{
    function_type: :def | :defp,
    has_guard: boolean(),
    bodyless: boolean()
  }
}
```

**Key Points**:
- `order` is 1-indexed (first clause is 1)
- `head.parameters` is a list of AST nodes that need Parameter.extract/2
- `head.guard` may be nil
- `body` may be nil for protocol definitions

### 3.2 Parameter Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/parameter.ex`:

```elixir
%ElixirOntologies.Extractors.Parameter{
  position: non_neg_integer(),                # 0-indexed position
  name: atom() | nil,                         # Parameter name (nil for patterns)
  type: :simple | :default | :pattern | :pin,
  expression: Macro.t(),                      # Full parameter AST
  default_value: Macro.t() | nil,             # For default parameters
  location: SourceLocation.t() | nil,
  metadata: %{
    has_default: boolean(),
    is_pattern: boolean(),
    is_ignored: boolean(),
    pattern_type: atom() | nil
  }
}
```

**Parameter Types**:
- `:simple` → `core:Parameter`
- `:default` → `struct:DefaultParameter` (subclass of Parameter)
- `:pattern` → `struct:PatternParameter` (subclass of Parameter)
- `:pin` → `struct:PatternParameter` (pin is a form of pattern)

### 3.3 IRI Generation Patterns

Using `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`:

| Element | Pattern | Example | Notes |
|---------|---------|---------|-------|
| Clause | `{function_iri}/clause/{N}` | `base#Module/func/1/clause/0` | N is 0-indexed |
| Parameter | `{clause_iri}/param/{N}` | `.../clause/0/param/0` | N is 0-indexed |

**Important**: IRIs use 0-indexed ordering, but RDF properties use 1-indexed:
- `clauseOrder` is 1-indexed (first clause = 1)
- `parameterPosition` is 1-indexed (first param = 1)
- IRI paths use 0-indexed (clause/0, param/0)

```elixir
# Clause with order=1 (first clause)
clause_iri = IRI.for_clause(function_iri, 0)  # 0-indexed for IRI
clauseOrder_value = 1  # 1-indexed for RDF property

# Parameter at position 0 (first param)
param_iri = IRI.for_parameter(clause_iri, 0)  # 0-indexed for IRI
parameterPosition_value = 1  # 1-indexed for RDF property
```

### 3.4 Ontology Classes and Properties

#### Classes

```turtle
struct:FunctionClause a owl:Class ;
    rdfs:comment "Individual function clause with head and body" .

struct:FunctionHead a owl:Class ;
    rdfs:comment "Function clause head with parameters and optional guard" .

struct:FunctionBody a owl:Class ;
    rdfs:comment "Function clause body expression" .

core:Parameter a owl:Class ;
    rdfs:comment "Function parameter" .

struct:DefaultParameter a owl:Class ;
    rdfs:subClassOf core:Parameter ;
    rdfs:comment "Parameter with default value" .

struct:PatternParameter a owl:Class ;
    rdfs:subClassOf core:Parameter ;
    rdfs:comment "Pattern-matching parameter" .
```

#### Object Properties

```turtle
struct:hasClause a owl:ObjectProperty ;
    rdfs:domain struct:Function ;
    rdfs:range struct:FunctionClause ;
    rdfs:comment "Function has clause" .

struct:hasHead a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain struct:FunctionClause ;
    rdfs:range struct:FunctionHead ;
    rdfs:comment "Clause has function head" .

struct:hasBody a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain struct:FunctionClause ;
    rdfs:range struct:FunctionBody ;
    rdfs:comment "Clause has function body" .

struct:hasParameters a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain struct:FunctionHead ;
    rdfs:range rdf:List ;
    rdfs:comment "Head has ordered parameter list" .

struct:hasGuard a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain struct:FunctionHead ;
    rdfs:comment "Head has guard expression" .
```

#### Data Properties

```turtle
struct:clauseOrder a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain struct:FunctionClause ;
    rdfs:range xsd:positiveInteger ;
    rdfs:comment "1-indexed clause order (pattern-match order)" .

core:parameterName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain core:Parameter ;
    rdfs:range xsd:string .

core:parameterPosition a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain core:Parameter ;
    rdfs:range xsd:positiveInteger ;
    rdfs:comment "1-indexed parameter position" .
```

### 3.5 Triple Generation Examples

**Simple Clause with Parameters**:
```turtle
<base#MyApp/get/2> struct:hasClause <base#MyApp/get/2/clause/0> .

<base#MyApp/get/2/clause/0> a struct:FunctionClause ;
    struct:clauseOrder "1"^^xsd:positiveInteger ;
    struct:hasHead _:head1 ;
    struct:hasBody _:body1 .

_:head1 a struct:FunctionHead ;
    struct:hasParameters _:list1 .

_:list1 rdf:first <base#MyApp/get/2/clause/0/param/0> ;
    rdf:rest _:list2 .

_:list2 rdf:first <base#MyApp/get/2/clause/0/param/1> ;
    rdf:rest rdf:nil .

<base#MyApp/get/2/clause/0/param/0> a core:Parameter ;
    core:parameterName "id"^^xsd:string ;
    core:parameterPosition "1"^^xsd:positiveInteger .

<base#MyApp/get/2/clause/0/param/1> a core:Parameter ;
    core:parameterName "opts"^^xsd:string ;
    core:parameterPosition "2"^^xsd:positiveInteger .

_:body1 a struct:FunctionBody .
```

**Clause with Default Parameter**:
```turtle
<base#MyApp/fetch/1/clause/0/param/0> a struct:DefaultParameter ;
    core:parameterName "timeout"^^xsd:string ;
    core:parameterPosition "1"^^xsd:positiveInteger .
```

**Clause with Pattern Parameter**:
```turtle
<base#MyApp/handle/1/clause/0/param/0> a struct:PatternParameter ;
    core:parameterName "msg"^^xsd:string ;
    core:parameterPosition "1"^^xsd:positiveInteger .
```

**Clause with Guard**:
```turtle
_:head1 a struct:FunctionHead ;
    struct:hasParameters _:list1 ;
    struct:hasGuard _:guard1 .

_:guard1 a core:GuardExpression .
```

### 3.6 Builder Helpers Usage

```elixir
# Type triple
Helpers.type_triple(clause_iri, Structure.FunctionClause)

# Datatype property (1-indexed integer)
Helpers.datatype_property(clause_iri, Structure.clauseOrder(), 1, RDF.XSD.PositiveInteger)

# Object property
Helpers.object_property(function_iri, Structure.hasClause(), clause_iri)

# Blank node
head_bnode = Helpers.blank_node("function_head")

# RDF list
{list_head, list_triples} = Helpers.build_rdf_list([param_iri_1, param_iri_2])
Helpers.object_property(head_bnode, Structure.hasParameters(), list_head)
```

## 4. Implementation Steps

### 4.1 Step 1: Create Clause Builder Skeleton (1 hour)

Create `lib/elixir_ontologies/builders/clause_builder.ex`:
- Module documentation with examples
- `build_clause/3` function signature: `(clause_info, function_iri, context) → {clause_iri, triples}`
- Import necessary modules (Helpers, IRI, Structure, Core)
- Define helper function stubs

### 4.2 Step 2: Implement Core Clause Triple Generation (1.5 hours)

Implement basic clause structure:
- Generate clause IRI (convert 1-indexed order to 0-indexed)
- Build `rdf:type struct:FunctionClause` triple
- Build `clauseOrder` property (1-indexed)
- Build `hasClause` triple from function to clause
- Create blank nodes for head and body
- Build `hasHead` and `hasBody` object properties

### 4.3 Step 3: Implement Parameter Building (2.5 hours)

Implement `build_parameters/3`:
- Extract parameters using `Parameter.extract_all/1`
- Generate parameter IRIs for each parameter
- Determine parameter class (Parameter, DefaultParameter, PatternParameter)
- Build parameter type triples
- Build `parameterName` properties
- Build `parameterPosition` properties (1-indexed)
- Collect all parameter triples

### 4.4 Step 4: Implement RDF List Generation (1.5 hours)

Connect parameters via RDF list:
- Create list of parameter IRIs
- Use `Helpers.build_rdf_list/1` to generate list structure
- Link list to FunctionHead via `hasParameters` property
- Verify proper rdf:first/rdf:rest/rdf:nil structure

### 4.5 Step 5: Implement FunctionHead Building (1 hour)

Complete FunctionHead structure:
- Create blank node for head
- Build type triple for FunctionHead
- Link parameters list to head
- Handle guard if present (create blank node, link via `hasGuard`)
- Collect all head-related triples

### 4.6 Step 6: Implement FunctionBody Building (0.5 hours)

Complete FunctionBody structure:
- Create blank node for body
- Build type triple for FunctionBody
- Handle bodyless clauses (protocol definitions)

### 4.7 Step 7: Integration and Testing (2 hours)

Complete the main `build_clause/3` function:
- Integrate all components
- Flatten and deduplicate triples
- Test with various clause types
- Add comprehensive doctests

## 5. Testing Strategy

**Target**: 30+ comprehensive tests covering all scenarios

### Test Categories

1. **Basic Clause Building** (4 tests):
   - Simple clause with no parameters
   - Clause with single parameter
   - Clause with multiple parameters
   - Clause ordering (clauseOrder property)

2. **Parameter Types** (5 tests):
   - Simple parameters → Parameter class
   - Default parameters → DefaultParameter class
   - Pattern parameters → PatternParameter class
   - Pin parameters → PatternParameter class
   - Mixed parameter types in one clause

3. **RDF List Structure** (4 tests):
   - Empty parameter list (rdf:nil)
   - Single parameter list
   - Multiple parameter list
   - Verify rdf:first/rdf:rest/rdf:nil structure

4. **Parameter Properties** (4 tests):
   - parameterName generation
   - parameterPosition generation (1-indexed)
   - Parameter IRI format
   - Position consistency across parameters

5. **FunctionHead Structure** (4 tests):
   - Blank node creation
   - hasHead property linking
   - hasParameters property with list
   - Head without guard

6. **Guard Handling** (3 tests):
   - Clause with guard
   - Clause without guard
   - Guard blank node structure

7. **FunctionBody Structure** (3 tests):
   - Blank node creation
   - hasBody property linking
   - Bodyless clause handling

8. **Clause-Function Relationship** (2 tests):
   - hasClause triple generation
   - Correct clause IRI format

9. **IRI Generation** (3 tests):
   - Clause IRI format (0-indexed path)
   - Parameter IRI format (0-indexed path)
   - Multiple clauses have different IRIs

10. **Triple Validation** (3 tests):
    - Verify all expected triples present
    - No duplicate triples
    - Triple count for different scenarios

11. **Edge Cases** (2 tests):
    - Zero-arity function clause
    - Multi-clause function (multiple orders)

### Example Test Structure

```elixir
describe "build_clause/3 basic clause" do
  test "builds simple clause with parameters" do
    clause_info = %Clause{
      name: :get_user,
      arity: 1,
      visibility: :public,
      order: 1,
      head: %{
        parameters: [{:id, [], nil}],
        guard: nil
      },
      body: quote do: :ok,
      location: nil,
      metadata: %{}
    }

    function_iri = ~I<https://example.org/code#MyApp/get_user/1>
    context = Context.new(base_iri: "https://example.org/code#")

    {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

    # Verify clause IRI (0-indexed)
    assert to_string(clause_iri) == "https://example.org/code#MyApp/get_user/1/clause/0"

    # Verify clauseOrder (1-indexed)
    assert Enum.any?(triples, fn
      {^clause_iri, pred, obj} ->
        pred == Structure.clauseOrder() and RDF.Literal.value(obj) == 1
      _ -> false
    end)

    # Verify hasClause from function
    assert {function_iri, Structure.hasClause(), clause_iri} in triples

    # Verify parameter exists
    param_iri = ~I<https://example.org/code#MyApp/get_user/1/clause/0/param/0>
    assert Enum.any?(triples, fn
      {^param_iri, pred, _} -> pred == RDF.type()
      _ -> false
    end)
  end
end
```

## 6. Success Criteria

This phase is complete when:

1. ClauseBuilder module exists with complete documentation
2. `build_clause/3` correctly transforms Clause.t() to RDF triples
3. Clause IRIs use 0-indexed ordering in path
4. clauseOrder property uses 1-indexed values
5. FunctionHead blank nodes are created correctly
6. FunctionBody blank nodes are created correctly
7. Parameter IRIs are generated correctly (0-indexed)
8. parameterPosition uses 1-indexed values
9. RDF lists are built correctly using build_rdf_list/1
10. Different parameter types map to correct classes
11. Guards are handled when present
12. Bodyless clauses are handled correctly
13. hasClause triple links function to clause
14. All nested structures have proper blank nodes
15. Test suite passes with 30+ comprehensive tests
16. 100% code coverage for ClauseBuilder
17. Documentation includes clear examples
18. No regressions in existing tests

## 7. Key Implementation Details

### 7.1 Index Conversion Helper

```elixir
# Convert 1-indexed order to 0-indexed for IRI
defp clause_order_to_index(order) when is_integer(order) and order > 0 do
  order - 1
end

# Parameter position is 0-indexed in extractor, but 1-indexed in RDF
defp position_to_rdf_index(position) when is_integer(position) and position >= 0 do
  position + 1
end
```

### 7.2 Parameter Type Determination

```elixir
defp determine_parameter_class(%Parameter{type: :simple}), do: Core.Parameter
defp determine_parameter_class(%Parameter{type: :default}), do: Structure.DefaultParameter
defp determine_parameter_class(%Parameter{type: :pattern}), do: Structure.PatternParameter
defp determine_parameter_class(%Parameter{type: :pin}), do: Structure.PatternParameter
```

### 7.3 Triple Accumulation Pattern

```elixir
def build_clause(clause_info, function_iri, context) do
  clause_iri = generate_clause_iri(clause_info, function_iri)

  # Accumulate triples from different builders
  triples = []

  # Core clause triples
  triples = triples ++ build_clause_core_triples(clause_iri, clause_info, function_iri)

  # Head triples (includes parameters and guard)
  {head_bnode, head_triples} = build_function_head(clause_iri, clause_info, context)
  triples = triples ++ head_triples ++ [build_has_head_triple(clause_iri, head_bnode)]

  # Body triples
  {body_bnode, body_triples} = build_function_body(clause_info)
  triples = triples ++ body_triples ++ [build_has_body_triple(clause_iri, body_bnode)]

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {clause_iri, triples}
end
```

## 8. Risk Mitigation

### Risk 1: RDF List Complexity
**Issue**: RDF lists are complex nested structures that may be error-prone.
**Mitigation**:
- Use tested `Helpers.build_rdf_list/1` function
- Write extensive tests for list structure
- Test with empty, single, and multiple element lists

### Risk 2: Index Confusion (0 vs 1-indexed)
**Issue**: Mixing 0-indexed and 1-indexed values could cause errors.
**Mitigation**:
- Clear helper functions for conversion
- Document index conventions in code
- Comprehensive tests verifying both IRI paths and property values

### Risk 3: Blank Node Management
**Issue**: Too many blank nodes may become hard to track.
**Mitigation**:
- Use descriptive labels for blank nodes during debugging
- Clear naming convention for blank node variables
- Test blank node structure separately

### Risk 4: Parameter Extraction Order
**Issue**: Parameter order must be preserved for pattern matching semantics.
**Mitigation**:
- Use `Parameter.extract_all/1` which preserves order
- Verify parameter positions in tests
- Test RDF list maintains order

## 9. Estimated Timeline

| Task | Estimated Time |
|------|----------------|
| Create skeleton | 1 hour |
| Core clause triples | 1.5 hours |
| Parameter building | 2.5 hours |
| RDF list generation | 1.5 hours |
| FunctionHead building | 1 hour |
| FunctionBody building | 0.5 hours |
| Integration and polish | 2 hours |
| Unit tests (30+ tests) | 6 hours |
| Documentation | 1 hour |
| **Total** | **17 hours** |

## 10. References

### Internal Files
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/clause.ex` - Clause extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/parameter.ex` - Parameter extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers (build_rdf_list/1)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/function_builder.ex` - Function builder pattern
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation (for_clause, for_parameter)

### Related Phase Documents
- `notes/features/phase-12-1-1-builder-infrastructure.md` - Builder infrastructure
- `notes/features/phase-12-1-2-module-builder.md` - Module builder
- `notes/features/phase-12-1-3-function-builder.md` - Function builder
