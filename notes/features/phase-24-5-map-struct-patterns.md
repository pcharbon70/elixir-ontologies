# Phase 24.5: Map and Struct Pattern Extraction

**Status:** Planning
**Branch:** `feature/phase-24-5-map-struct-patterns`
**Created:** 2026-01-12
**Target:** Implement map and struct pattern extraction for Phase 24.5

## 1. Problem Statement

Section 24.5 of Phase 24 covers the extraction of map patterns (`%{key: value}`) and struct patterns (`%User{name: value}`) in Elixir pattern matching contexts.

**Current State:**
- Pattern type detection correctly identifies map and struct patterns (Phase 24.1)
- `build_map_pattern/3` and `build_struct_pattern/3` are placeholder implementations returning only type triples
- Map and struct literal expressions are fully implemented (Phase 22.8)
- Tuple and list pattern extraction is implemented (Phase 24.4)

**What Needs Implementation:**
1. Map pattern extraction: capture key-value pairs where values are patterns
2. Struct pattern extraction: capture struct module and field patterns
3. Comprehensive test coverage for all map and struct pattern variations

## 2. Solution Overview

### 2.1 Elixir AST for Map Patterns

Map patterns use the AST form `{:%{}, meta, pairs}` where `pairs` is a keyword list:

```elixir
# Empty map pattern
%{}                    # {:%{}, [], []}

# Map with atom key pattern
%{a: x}               # {:%{}, [], [a: {:x, [], Elixir}]}

# Map with string key pattern
%{"key" => value}     # {:%{}, [], [{"key", {:value, [], Elixir}}]}

# Map with multiple keys
%{a: x, b: y}         # {:%{}, [], [a: {:x, [], Elixir}, b: {:y, [], Elixir}]}
```

**Key Observation:** The pairs are always a flat list alternating keys and values (keyword list format). Keys are literals (atoms or strings), values are pattern ASTs.

### 2.2 Elixir AST for Struct Patterns

Struct patterns use the AST form `{:%, meta, [module_ast, map_ast]}`:

```elixir
# Empty struct pattern
%User{}                      # {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}

# Struct with field pattern
%User{name: name}           # {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:name, [], Elixir}]}]}

# Struct with tuple module reference
%{__MODULE__}{name: n}      # {:%, [], [{:__MODULE__, [], []}, {:%{}, [], [name: {:n, [], Elixir}]}]}
```

**Module Reference Forms:**
- `{:__aliases__, meta, parts}` - Regular alias (e.g., `User`, `MyApp.User`)
- `{:__MODULE__, [], []}` - Current module reference
- `{:{}, meta, parts}` - Nested alias form (rare)

### 2.3 Design Decisions

1. **Key Representation:** Map pattern keys are literals, not patterns. Only values need pattern extraction.
2. **Module Name Extraction:** Extract module name as string for `StructPattern` using `refersToModule` property.
3. **Nested Patterns:** Map and struct values can be any pattern (variable, literal, wildcard, pin, nested structures).
4. **Pattern Consistency:** Follow the same pattern as tuple/list patterns - build child patterns using `build_child_patterns/2`.

## 3. Technical Details

### 3.1 File Locations

**Implementation:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
  - Replace `build_map_pattern/3` placeholder (around line 1479)
  - Replace `build_struct_pattern/3` placeholder (around line 1484)

**Tests:**
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add new test sections after list pattern extraction tests

### 3.2 Ontology Classes

```turtle
:MapPattern a owl:Class ;
    rdfs:label "Map Pattern"@en ;
    rdfs:comment "A pattern matching specific keys in a map."@en ;
    rdfs:subClassOf :Pattern .

:StructPattern a owl:Class ;
    rdfs:label "Struct Pattern"@en ;
    rdfs:comment "A pattern matching a struct with specific field values."@en ;
    rdfs:subClassOf :Pattern .
```

### 3.3 Ontology Properties

**For MapPattern:**
- Currently no specific properties defined for map pattern key-value pairs
- Values will be captured as nested pattern expressions (similar to tuple/list patterns)

**For StructPattern:**
- `refersToModule` - Links the struct pattern to its module (already defined in ontology)
- Module IRI format: `{base_iri}module/{module_name}`

### 3.4 Helper Functions

**From ExpressionBuilder:**
- `build/3` - For building child pattern expressions
- `build_pattern/3` - For converting child AST to pattern triples
- `build_child_patterns/2` - For building multiple child patterns (used in tuple/list)
- `fresh_iri/2` - For generating child IRIs

**From Helpers:**
- `type_triple/2` - For creating rdf:type triples
- `datatype_property/4` - For creating literal property triples
- `object_property/3` - For creating object property triples

### 3.5 Reference Implementation: Map Literal (Phase 22.8)

```elixir
# From expression_builder.ex lines 805-833
defp build_map_literal(pairs, expr_iri, context) do
  type_triple = Helpers.type_triple(expr_iri, Core.MapLiteral)
  entry_triples = build_map_entries(pairs, expr_iri, context)
  [type_triple | entry_triples]
end

defp build_map_entries(pairs, _expr_iri, _context) when pairs == [], do: []

defp build_map_entries(pairs, _expr_iri, context) do
  regular_pairs = Enum.filter(pairs, fn
    {:|, _, _} -> false
    _ -> true
  end)

  {value_triples, _final_context} =
    build_child_expressions(regular_pairs, context, fn {_key, value} -> value end)

  value_triples
end
```

## 4. Implementation Plan

### Step 1: Implement `build_map_pattern/3`

**Location:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` (line 1479)

Replace the placeholder implementation with:

```elixir
@doc """
Builds RDF triples for a map pattern.

Map patterns match specific keys in a map, with values being any pattern.

## Parameters

- `ast` - The map pattern AST: {:%{}, _, pairs}
- `expr_iri` - The IRI for this pattern expression
- `context` - The builder context

## Returns

A list of RDF triples with:
- Core.MapPattern type triple
- Nested pattern triples for each value in the key-value pairs

## Examples

    iex> # %{a: x, b: y}
    iex> ast = {:%{}, [], [a: {:x, [], Elixir}, b: {:y, [], Elixir}]}
    iex> expr_iri = RDF.iri("ex://pattern/1")
    iex> build_map_pattern(ast, expr_iri, full_mode_context())
    iex> |> Enum.at(0)
    {RDF.iri("ex://pattern/1"), RDF.type(), Core.MapPattern()}

"""
defp build_map_pattern({:%{}, _meta, pairs}, expr_iri, context) do
  # Create the MapPattern type triple
  type_triple = Helpers.type_triple(expr_iri, Core.MapPattern)

  # Extract values from key-value pairs (keys are literals, values are patterns)
  value_patterns = extract_map_pattern_values(pairs)

  # Build child patterns for each value
  {child_triples, _final_context} = build_child_patterns(value_patterns, context)

  # Include type triple and all child pattern triples
  [type_triple | child_triples]
end

# Extract value patterns from map pattern pairs
# Pairs are keyword list format: [key1: value1_ast, key2: value2_ast, ...]
# Or for string keys: [{"key1", value1_ast}, {"key2", value2_ast}]
defp extract_map_pattern_values(pairs) when is_list(pairs) do
  Enum.map(pairs, fn
    {key, _value_ast} = pair when is_atom(key) or is_binary(key) -> pair
    # Handle keyword list tuple format: {:key, value}
    pair -> elem(pair, 1)
  end)
end
```

### Step 2: Implement `build_struct_pattern/3`

**Location:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` (line 1484)

Replace the placeholder implementation with:

```elixir
@doc """
Builds RDF triples for a struct pattern.

Struct patterns match a struct with specific field values.

## Parameters

- `ast` - The struct pattern AST: {:%, _, [module_ast, map_ast]}
- `expr_iri` - The IRI for this pattern expression
- `context` - The builder context

## Returns

A list of RDF triples with:
- Core.StructPattern type triple
- refersToModule property linking to the struct's module
- Nested pattern triples for each field value

## Examples

    iex> # %User{name: name}
    iex> module_ast = {:__aliases__, [], [:User]}
    iex> map_ast = {:%{}, [], [name: {:name, [], Elixir}]}
    iex> ast = {:%, [], [module_ast, map_ast]}
    iex> expr_iri = RDF.iri("ex://pattern/1")
    iex> build_struct_pattern(ast, expr_iri, full_mode_context())
    iex> |> Enum.at(0)
    {RDF.iri("ex://pattern/1"), RDF.type(), Core.StructPattern()}

"""
defp build_struct_pattern({:%, _meta, [module_ast, {:%{}, _map_meta, pairs}]}, expr_iri, context) do
  # Extract module name from module AST
  module_name = extract_struct_module_name(module_ast)

  # Create the StructPattern type triple
  type_triple = Helpers.type_triple(expr_iri, Core.StructPattern)

  # Create refersToModule property
  module_iri_string = "#{context.base_iri}module/#{module_name}"
  module_iri = RDF.IRI.new(module_iri_string)
  refers_to_triple = {expr_iri, Core.refersToModule(), module_iri}

  # Extract field value patterns from the map portion
  field_patterns = extract_map_pattern_values(pairs)

  # Build child patterns for each field value
  {child_triples, _final_context} = build_child_patterns(field_patterns, context)

  # Include type triple, module reference, and all child pattern triples
  [type_triple, refers_to_triple | child_triples]
end

# Extract module name from struct pattern module AST
defp extract_struct_module_name({:__aliases__, _meta, parts}) do
  Enum.join(parts, ".")
end

defp extract_struct_module_name({:__MODULE__, [], []}) do
  "__MODULE__"
end

defp extract_struct_module_name({:{}, _meta, parts}) when is_list(parts) do
  # Handle tuple form module reference
  Enum.map(parts, fn
    part when is_atom(part) -> Atom.to_string(part)
    part -> inspect(part)
  end)
  |> Enum.join(".")
end

defp extract_struct_module_name(other) do
  inspect(other)
end
```

### Step 3: Add Unit Tests

**Location:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

Add after list pattern extraction tests (around line 3450):

#### 3.1 Map Pattern Extraction Tests

```elixir
describe "map pattern extraction" do
  test "builds MapPattern for empty map" do
    context = full_mode_context()
    # Empty map AST: {:%{}, [], []}
    ast = {:%{}, [], []}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Empty map has only type triple (no child patterns)
    assert length(pattern_triples) == 1
  end

  test "builds MapPattern with variable values" do
    context = full_mode_context()
    # %{a: x, b: y}
    ast = {:%{}, [], [a: {:x, [], Elixir}, b: {:y, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have nested VariablePatterns
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds MapPattern with literal values" do
    context = full_mode_context()
    # %{status: :ok, count: 42}
    ast = {:%{}, [], [status: {:ok, [], nil}, count: 42]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have nested LiteralPatterns
    assert has_type?(pattern_triples, Core.LiteralPattern)
  end

  test "builds MapPattern with string keys" do
    context = full_mode_context()
    # %{"key" => value}
    ast = {:%{}, [], [{"key", {:value, [], Elixir}}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have nested VariablePattern
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds MapPattern with wildcard values" do
    context = full_mode_context()
    # %{a: _, b: x}
    ast = {:%{}, [], [a: {:_}, b: {:x, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have WildcardPattern
    assert has_type?(pattern_triples, Core.WildcardPattern)
  end

  test "builds MapPattern with pin pattern values" do
    context = full_mode_context()
    # %{^key => value}
    ast = {:%{}, [], [[{:^, [], [{:key, [], Elixir}]}, {:value, [], Elixir}]]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have PinPattern
    assert has_type?(pattern_triples, Core.PinPattern)
  end

  test "builds MapPattern with nested map patterns" do
    context = full_mode_context()
    # %{outer: %{inner: x}}
    inner_map = {:%{}, [], [inner: {:x, [], Elixir}]}
    ast = {:%{}, [], [outer: inner_map]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Nested maps should create multiple MapPattern instances
    map_pattern_count = Enum.count(pattern_triples, fn {_s, p, o} ->
      p == RDF.type() and o == Core.MapPattern
    end)
    assert map_pattern_count >= 2
  end

  test "builds MapPattern with nested tuple patterns" do
    context = full_mode_context()
    # %{coords: {x, y}}
    tuple_pattern = {{:x, [], Elixir}, {:y, [], Elixir}}
    ast = {:%{}, [], [coords: tuple_pattern]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have MapPattern type
    assert has_type?(pattern_triples, Core.MapPattern)

    # Should have TuplePattern
    assert has_type?(pattern_triples, Core.TuplePattern)
  end
end
```

#### 3.2 Struct Pattern Extraction Tests

```elixir
describe "struct pattern extraction" do
  test "builds StructPattern for empty struct" do
    context = full_mode_context()
    # %User{}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], []}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Should have module reference
    assert Enum.any?(pattern_triples, fn {s, p, _o} ->
      s == expr_iri and p == Core.refersToModule()
    end)

    # Empty struct has type triple and module reference (no field patterns)
    assert length(pattern_triples) == 2
  end

  test "builds StructPattern with simple module alias" do
    context = full_mode_context()
    # %User{name: name}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], [name: {:name, [], Elixir}]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Module reference should point to "User"
    assert Enum.any?(pattern_triples, fn {s, p, o} ->
      s == expr_iri and p == Core.refersToModule() and
        String.contains?(RDF.IRI.to_string(o), "User")
    end)

    # Should have nested VariablePattern
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds StructPattern with nested module alias" do
    context = full_mode_context()
    # %MyApp.User{name: name}
    module_ast = {:__aliases__, [], [:MyApp, :User]}
    map_ast = {:%{}, [], [name: {:name, [], Elixir}]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Module reference should point to "MyApp.User"
    assert Enum.any?(pattern_triples, fn {s, p, o} ->
      s == expr_iri and p == Core.refersToModule() and
        String.contains?(RDF.IRI.to_string(o), "MyApp.User")
    end)
  end

  test "builds StructPattern with __MODULE__" do
    context = full_mode_context()
    # %{__MODULE__}{name: name}
    module_ast = {:__MODULE__, [], []}
    map_ast = {:%{}, [], [name: {:name, [], Elixir}]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Module reference should point to "__MODULE__"
    assert Enum.any?(pattern_triples, fn {s, p, o} ->
      s == expr_iri and p == Core.refersToModule() and
        String.contains?(RDF.IRI.to_string(o), "__MODULE__")
    end)
  end

  test "builds StructPattern with multiple fields" do
    context = full_mode_context()
    # %User{name: name, age: age, email: email}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], [
      name: {:name, [], Elixir},
      age: {:age, [], Elixir},
      email: {:email, [], Elixir}
    ]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Should have multiple nested VariablePatterns
    variable_pattern_count = Enum.count(pattern_triples, fn {_s, p, o} ->
      p == RDF.type() and o == Core.VariablePattern
    end)
    assert variable_pattern_count == 3
  end

  test "builds StructPattern with literal field values" do
    context = full_mode_context()
    # %User{role: :admin}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], [role: {:admin, [], nil}]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Should have nested LiteralPattern
    assert has_type?(pattern_triples, Core.LiteralPattern)
  end

  test "builds StructPattern with wildcard fields" do
    context = full_mode_context()
    # %User{name: _, age: age}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], [name: {:_}, age: {:age, [], Elixir}]}
    ast = {:%, [], [module_ast, map_ast]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have StructPattern type
    assert has_type?(pattern_triples, Core.StructPattern)

    # Should have WildcardPattern
    assert has_type?(pattern_triples, Core.WildcardPattern)

    # Should have VariablePattern
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "distinguishes StructPattern from MapPattern" do
    context = full_mode_context()

    # Struct pattern: %User{}
    module_ast = {:__aliases__, [], [:User]}
    map_ast = {:%{}, [], []}
    struct_ast = {:%, [], [module_ast, map_ast]}
    {:ok, {struct_iri, _, _}} = ExpressionBuilder.build(struct_ast, context, [])
    struct_triples = ExpressionBuilder.build_pattern(struct_ast, struct_iri, context)

    # Map pattern: %{}
    map_pattern_ast = {:%{}, [], []}
    {:ok, {map_iri, _, _}} = ExpressionBuilder.build(map_pattern_ast, context, [])
    map_triples = ExpressionBuilder.build_pattern(map_pattern_ast, map_iri, context)

    # Struct should have StructPattern type
    assert has_type?(struct_triples, Core.StructPattern)
    refute has_type?(struct_triples, Core.MapPattern)

    # Map should have MapPattern type
    assert has_type?(map_triples, Core.MapPattern)
    refute has_type?(map_triples, Core.StructPattern)

    # Struct should have module reference, map should not
    assert Enum.any?(struct_triples, fn {_s, p, _o} -> p == Core.refersToModule() end)
    refute Enum.any?(map_triples, fn {_s, p, _o} -> p == Core.refersToModule() end)
  end
end
```

### Step 4: Run Verification

4.1 Run tests:
```bash
mix test test/elixir_ontologies/builders/expression_builder_test.exs
```

4.2 Verify all new tests pass

4.3 Verify no regressions in existing tests

## 5. Success Criteria

1. **Map pattern extraction works:**
   - Empty map patterns return type triple only
   - Map patterns with atom keys extract value patterns correctly
   - Map patterns with string keys extract value patterns correctly
   - Map patterns support nested structures (maps, tuples, lists)

2. **Struct pattern extraction works:**
   - Empty struct patterns include module reference
   - Struct patterns with field patterns extract correctly
   - Module name extraction works for all forms (aliases, __MODULE__)
   - Struct patterns are distinguished from map patterns

3. **Tests pass:**
   - All map pattern extraction tests pass
   - All struct pattern extraction tests pass
   - No regressions in existing ExpressionBuilder tests
   - Total test count increases by at least 16 new tests

4. **Code quality:**
   - Functions follow existing code style
   - Proper documentation added with examples
   - Code is consistent with tuple/list pattern implementations
   - Edge cases are handled (empty patterns, nested patterns)

## 6. Notes and Considerations

### 6.1 Map Update Syntax

Map update syntax (`%{map | key: value}`) uses the `{:|, _, [original, updates]}` pattern in the pairs list. The current implementation filters these out using `Enum.filter`. For pattern matching purposes, map update is not typically used, so this filtering is appropriate.

### 6.2 Module Reference in Struct Patterns

The module AST in struct patterns can take several forms:
- `{:__aliases__, [], [:User]}` - Simple alias
- `{:__aliases__, [], [:MyApp, :User]}` - Nested alias
- `{:__MODULE__, [], []}` - Current module reference
- `{:{}, _, [...]}` - Tuple form (rare, but exists)

The `extract_struct_module_name/1` helper function must handle all these cases.

### 6.3 Pattern vs Expression Context

The same AST structure can represent either a pattern or an expression:
- `{:%{}, [], [a: 1]}` as expression: map literal with integer value
- `{:%{}, [], [a: {:x, [], Elixir}]}` as pattern: map pattern with variable binding

The `build_pattern/3` function assumes the caller knows this is a pattern context. For struct patterns, the presence of variables in the map portion indicates a pattern context.

### 6.4 Future Integration Points

The map/struct pattern extraction will be used by:
- Function clause parameter extraction (when parameters are maps/structs)
- Case expression clause extraction
- Match expression handling
- For comprehension generator extraction (when generators produce maps)

### 6.5 Relationship to Existing Implementations

**Reuses existing patterns:**
- Similar to `build_tuple_pattern/3` for element extraction
- Similar to `build_list_pattern/3` for item processing
- Similar to `build_struct_literal/4` for module name extraction

**New considerations:**
- Map pattern values are always patterns (not expressions)
- Map keys are always literals (not patterns)
- Struct patterns require module reference property

## 7. Progress Tracking

- [x] 7.1 Create feature branch `feature/phase-24-5-map-struct-patterns`
- [x] 7.2 Create planning document
- [ ] 7.3 Implement `build_map_pattern/3` function
- [ ] 7.4 Implement `extract_map_pattern_values/1` helper
- [ ] 7.5 Implement `build_struct_pattern/3` function
- [ ] 7.6 Implement `extract_struct_module_name/1` helper
- [ ] 7.7 Add map pattern extraction tests (8 tests)
- [ ] 7.8 Add struct pattern extraction tests (8 tests)
- [ ] 7.9 Run test suite and verify all pass
- [ ] 7.10 Check for test regressions
- [ ] 7.11 Create summary document
- [ ] 7.12 Ask for permission to commit and merge

## 8. Status Log

### 2026-01-12 - Initial Planning
- Analyzed Phase 24.5 requirements
- Studied existing map/struct literal implementations (Phase 22.8)
- Examined tuple/list pattern implementations (Phase 24.4)
- Investigated Elixir AST for map/struct patterns
- Reviewed ontology pattern class definitions
- Created planning document

---

### Critical Files for Implementation

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` - Main implementation file; replace `build_map_pattern/3` at line 1479 and `build_struct_pattern/3` at line 1484

- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs` - Test file; add map and struct pattern extraction tests after list pattern extraction tests (around line 3450)

- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` - Reference for MapPattern (line 380) and StructPattern (line 385) class definitions; refersToModule property is already defined at line 701

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` (lines 1333-1476) - Reference implementations for `build_tuple_pattern/3` and `build_list_pattern/3`; follow the same pattern for map/struct patterns

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` (lines 773-833) - Reference implementations for `build_struct_literal/4` and `build_map_literal/3`; use module extraction logic from `build_struct_literal/4`
