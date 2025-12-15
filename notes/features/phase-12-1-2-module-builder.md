# Phase 12.1.2: Module Builder Planning Document

## 1. Problem Statement

Phase 12.1.1 established the builder infrastructure (BuilderContext and Helpers), but we still need to implement the actual builders that transform extractor results into RDF triples.

**The Challenge**: The Module extractor (`ElixirOntologies.Extractors.Module`) produces rich structured data about Elixir modules, but this data needs to be converted to RDF triples that conform to the `elixir-structure.ttl` ontology.

**Current State**:
- Module extractor produces `Module.t()` structs with:
  - Module type (`:module` or `:nested_module`)
  - Module name as list of atoms (e.g., `[:MyApp, :Users]`)
  - Module documentation
  - Directives (aliases, imports, requires, uses)
  - Contained elements (functions, macros, types)
  - Source location information
- Builder infrastructure exists but no module-specific builder

**The Gap**: We need to:
1. Generate IRIs for modules following the `base#ModuleName` pattern
2. Create `rdf:type` triples for Module/NestedModule classes
3. Build datatype properties (moduleName, docstring)
4. Handle nested module relationships (parentModule property)
5. Build containment relationships (containsFunction, containsMacro, containsType)
6. Handle module directives (aliases, imports, requires, uses)
7. Add source location information

## 2. Solution Overview

Create a **Module Builder** that transforms `Module.t()` structs into RDF triples.

### 2.1 Core Functionality

The builder will:
- Generate stable IRIs for modules using `IRI.for_module/2`
- Determine correct module class (Module vs NestedModule)
- Build all required triples for module representation
- Handle optional elements (documentation, directives)
- Link to contained elements (functions, macros, types)
- Support nested module hierarchies

### 2.2 Builder Pattern

```elixir
def build(module_info, context) do
  {module_iri, triples} =
    context
    |> generate_module_iri(module_info)
    |> build_type_triple(module_info)
    |> build_name_property(module_info)
    |> build_docstring(module_info)
    |> build_nested_relationships(module_info)
    |> build_directive_relationships(module_info)
    |> build_containment_relationships(module_info)
    |> build_location(module_info)
    |> extract_result()

  {module_iri, triples}
end
```

### 2.3 Integration Point

The Module Builder will be called from `FileAnalyzer.build_graph/3`:

```elixir
defp build_graph(modules, context, config) do
  builder_context = Context.new(
    base_iri: config.base_iri,
    config: config
  )

  Enum.reduce(modules, [], fn module_analysis, acc_triples ->
    {_module_iri, triples} = ModuleBuilder.build(module_analysis, builder_context)
    acc_triples ++ triples
  end)
  |> Graph.new()
  |> Graph.add_all(triples)
end
```

## 3. Technical Details

### 3.1 Module Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/module.ex`:

```elixir
%ElixirOntologies.Extractors.Module{
  # Core identification
  type: :module | :nested_module,
  name: [atom()],                          # e.g., [:MyApp, :Users]

  # Documentation
  docstring: String.t() | false | nil,     # "User management" | false | nil

  # Module directives
  aliases: [
    %{module: [atom()], as: atom() | nil, location: SourceLocation.t() | nil}
  ],
  imports: [
    %{module: [atom()] | atom(), only: keyword() | nil,
      except: keyword() | nil, location: SourceLocation.t() | nil}
  ],
  requires: [
    %{module: [atom()] | atom(), as: atom() | nil, location: SourceLocation.t() | nil}
  ],
  uses: [
    %{module: [atom()] | atom(), opts: keyword() | Macro.t(),
      location: SourceLocation.t() | nil}
  ],

  # Contained elements (summary only - full extraction handled by other builders)
  functions: [
    %{name: atom(), arity: non_neg_integer(), visibility: :public | :private}
  ],
  macros: [
    %{name: atom(), arity: non_neg_integer(), visibility: :public | :private}
  ],
  types: [
    %{name: atom(), arity: non_neg_integer(),
      visibility: :public | :private | :opaque}
  ],

  # Source location
  location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    parent_module: [atom()] | nil,         # For nested modules
    has_moduledoc: boolean(),
    nested_modules: [[atom()]]             # Names of nested modules
  }
}
```

### 3.2 IRI Generation Patterns

Using `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`:

| Element | Function | Input | Output |
|---------|----------|-------|--------|
| Module | `IRI.for_module/2` | `"MyApp.Users"` | `base#MyApp.Users` |
| Nested Module | `IRI.for_module/2` | `"MyApp.Users.Admin"` | `base#MyApp.Users.Admin` |
| Module with special chars | `IRI.for_module/2` | `"MyApp.Foo_Bar"` | `base#MyApp.Foo_Bar` |

**Module Name Conversion**:
```elixir
# From name list to string
[:MyApp, :Users] -> "MyApp.Users"

# Helper function
defp module_name_string(name) when is_list(name) do
  Enum.join(name, ".")
end
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Classes
```turtle
:Module a owl:Class ;
    rdfs:subClassOf core:CodeElement .

:NestedModule a owl:Class ;
    rdfs:subClassOf :Module .
```

#### Object Properties
```turtle
# Nested module relationship
:hasNestedModule a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :NestedModule .

:parentModule a owl:ObjectProperty, owl:FunctionalProperty ;
    owl:inverseOf :hasNestedModule ;
    rdfs:domain :NestedModule ;
    rdfs:range :Module .

# Containment relationships
:containsFunction a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Function .

:containsMacro a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Macro .

:containsType a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :TypeSpec .

# Directive relationships
:aliasesModule a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Module .

:importsFrom a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Module .

:requiresModule a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Module .

:usesModule a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Module .
```

#### Data Properties
```turtle
:moduleName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Module ;
    rdfs:range xsd:string .

:docstring a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Module ;
    rdfs:range xsd:string .
```

### 3.4 Triple Generation Examples

**Simple Module**:
```turtle
<base#MyApp> a struct:Module ;
    struct:moduleName "MyApp"^^xsd:string ;
    core:hasSourceLocation <base#file/lib/my_app.ex/L1-50> .
```

**Module with Documentation**:
```turtle
<base#MyApp.Users> a struct:Module ;
    struct:moduleName "MyApp.Users"^^xsd:string ;
    struct:docstring "User management"^^xsd:string ;
    core:hasSourceLocation <base#file/lib/users.ex/L1-100> .
```

**Nested Module**:
```turtle
<base#MyApp.Users.Admin> a struct:NestedModule ;
    struct:moduleName "MyApp.Users.Admin"^^xsd:string ;
    struct:parentModule <base#MyApp.Users> ;
    core:hasSourceLocation <base#file/lib/users/admin.ex/L1-50> .

<base#MyApp.Users> struct:hasNestedModule <base#MyApp.Users.Admin> .
```

**Module with Containment**:
```turtle
<base#MyApp.Users> a struct:Module ;
    struct:moduleName "MyApp.Users"^^xsd:string ;
    struct:containsFunction <base#MyApp.Users/list/0> ;
    struct:containsFunction <base#MyApp.Users/get/1> ;
    struct:containsMacro <base#MyApp.Users/ensure_user/1> .
```

**Module with Directives**:
```turtle
<base#MyApp.Users> a struct:Module ;
    struct:moduleName "MyApp.Users"^^xsd:string ;
    struct:aliasesModule <base#MyApp.Accounts> ;
    struct:importsFrom <base#Ecto.Query> ;
    struct:requiresModule <base#Logger> ;
    struct:usesModule <base#GenServer> .
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple
Helpers.type_triple(module_iri, Structure.Module)
#=> {module_iri, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Module>}

# Datatype property
Helpers.datatype_property(module_iri, Structure.moduleName(), "MyApp.Users", RDF.XSD.String)
#=> {module_iri, Structure.moduleName(), RDF.XSD.String.new("MyApp.Users")}

# Object property
Helpers.object_property(nested_iri, Structure.parentModule(), parent_iri)
#=> {nested_iri, Structure.parentModule(), parent_iri}
```

### 3.6 Builder Context Threading

The builder will receive and return context, but primarily work with triples:

```elixir
def build(module_info, context) do
  # Generate module IRI
  module_iri = IRI.for_module(context.base_iri, module_name_string(module_info.name))

  # Build all triples
  triples = []
    |> add_type_triple(module_iri, module_info)
    |> add_name_triple(module_iri, module_info)
    |> add_docstring_triple(module_iri, module_info)
    |> add_parent_triple(module_iri, module_info, context)
    |> add_directive_triples(module_iri, module_info, context)
    |> add_containment_triples(module_iri, module_info, context)
    |> add_location_triple(module_iri, module_info, context)

  # Return IRI and triples
  {module_iri, triples}
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Module Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/module_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build/2` function signature
3. Add helper functions for module name conversion
4. Import necessary namespaces (Helpers, IRI, Structure)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.ModuleBuilder do
  @moduledoc """
  Builds RDF triples for Elixir modules.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Module, as: ModuleExtractor
  alias NS.Structure

  @spec build(ModuleExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(module_info, context)

  # Helper functions
  defp module_name_string(name_list)
  defp determine_module_type(module_info)
  defp build_type_triple(module_iri, module_info)
  # ... etc
end
```

### 4.2 Step 2: Implement Core Triple Generation (2 hours)

Implement functions for basic module triples:

1. **IRI Generation**:
```elixir
defp generate_module_iri(module_info, context) do
  module_name = module_name_string(module_info.name)
  IRI.for_module(context.base_iri, module_name)
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(module_iri, module_info) do
  class = case module_info.type do
    :module -> Structure.Module()
    :nested_module -> Structure.NestedModule()
  end

  Helpers.type_triple(module_iri, class)
end
```

3. **Name Property**:
```elixir
defp build_name_triple(module_iri, module_info) do
  module_name = module_name_string(module_info.name)
  Helpers.datatype_property(module_iri, Structure.moduleName(),
                            module_name, RDF.XSD.String)
end
```

4. **Docstring Property** (optional):
```elixir
defp build_docstring_triple(module_iri, module_info) do
  case module_info.docstring do
    nil -> []
    false -> []  # @moduledoc false - intentionally hidden
    doc when is_binary(doc) ->
      [Helpers.datatype_property(module_iri, Structure.docstring(),
                                 doc, RDF.XSD.String)]
  end
end
```

### 4.3 Step 3: Implement Nested Module Support (1.5 hours)

Handle parent module relationships:

```elixir
defp build_parent_triple(module_iri, module_info, context) do
  case module_info.metadata.parent_module do
    nil ->
      []

    parent_name_list ->
      parent_name = module_name_string(parent_name_list)
      parent_iri = IRI.for_module(context.base_iri, parent_name)

      [
        # nested -> parent relationship
        Helpers.object_property(module_iri, Structure.parentModule(), parent_iri),
        # parent -> nested relationship (inverse)
        Helpers.object_property(parent_iri, Structure.hasNestedModule(), module_iri)
      ]
  end
end
```

### 4.4 Step 4: Implement Directive Handling (2 hours)

Build triples for module directives:

1. **Alias Directives**:
```elixir
defp build_alias_triples(module_iri, aliases, context) do
  Enum.flat_map(aliases, fn alias_info ->
    aliased_module = module_name_string(alias_info.module)
    aliased_iri = IRI.for_module(context.base_iri, aliased_module)

    [Helpers.object_property(module_iri, Structure.aliasesModule(), aliased_iri)]
  end)
end
```

2. **Import Directives**:
```elixir
defp build_import_triples(module_iri, imports, context) do
  Enum.flat_map(imports, fn import_info ->
    imported_module = normalize_module_name(import_info.module)
    imported_iri = IRI.for_module(context.base_iri, imported_module)

    [Helpers.object_property(module_iri, Structure.importsFrom(), imported_iri)]
  end)
end

# Handle both atom and list module names
defp normalize_module_name(module) when is_list(module), do: module_name_string(module)
defp normalize_module_name(module) when is_atom(module), do: to_string(module)
```

3. **Require Directives**:
```elixir
defp build_require_triples(module_iri, requires, context) do
  Enum.flat_map(requires, fn require_info ->
    required_module = normalize_module_name(require_info.module)
    required_iri = IRI.for_module(context.base_iri, required_module)

    [Helpers.object_property(module_iri, Structure.requiresModule(), required_iri)]
  end)
end
```

4. **Use Directives**:
```elixir
defp build_use_triples(module_iri, uses, context) do
  Enum.flat_map(uses, fn use_info ->
    used_module = normalize_module_name(use_info.module)
    used_iri = IRI.for_module(context.base_iri, used_module)

    [Helpers.object_property(module_iri, Structure.usesModule(), used_iri)]
  end)
end
```

### 4.5 Step 5: Implement Containment Relationships (1.5 hours)

Link to contained functions, macros, and types:

```elixir
defp build_containment_triples(module_iri, module_info, context) do
  function_triples = build_function_containment(module_iri, module_info.functions, context)
  macro_triples = build_macro_containment(module_iri, module_info.macros, context)
  type_triples = build_type_containment(module_iri, module_info.types, context)

  function_triples ++ macro_triples ++ type_triples
end

defp build_function_containment(module_iri, functions, context) do
  module_name = extract_module_name(module_iri)

  Enum.flat_map(functions, fn func_info ->
    func_iri = IRI.for_function(context.base_iri, module_name,
                                 func_info.name, func_info.arity)
    [Helpers.object_property(module_iri, Structure.containsFunction(), func_iri)]
  end)
end

defp build_macro_containment(module_iri, macros, context) do
  module_name = extract_module_name(module_iri)

  Enum.flat_map(macros, fn macro_info ->
    # Macros use the same IRI pattern as functions but different type
    macro_iri = IRI.for_function(context.base_iri, module_name,
                                  macro_info.name, macro_info.arity)
    [Helpers.object_property(module_iri, Structure.containsMacro(), macro_iri)]
  end)
end

defp build_type_containment(module_iri, types, context) do
  module_name = extract_module_name(module_iri)

  Enum.flat_map(types, fn type_info ->
    # Types also use function-like IRI pattern
    type_iri = IRI.for_function(context.base_iri, module_name,
                                type_info.name, type_info.arity)
    [Helpers.object_property(module_iri, Structure.containsType(), type_iri)]
  end)
end

# Extract module name from module IRI
defp extract_module_name(module_iri) do
  case IRI.module_from_iri(module_iri) do
    {:ok, module_name} -> module_name
    {:error, _} -> raise "Invalid module IRI: #{module_iri}"
  end
end
```

### 4.6 Step 6: Implement Location Handling (1 hour)

Add source location triples if present:

```elixir
defp build_location_triple(module_iri, module_info, context) do
  case {module_info.location, context.file_path} do
    {nil, _} ->
      []

    {location, nil} ->
      # Location exists but no file path - skip location triple
      []

    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)

      # Need end line - use start line if end not available
      end_line = location.end_line || location.start_line

      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

      [Helpers.object_property(module_iri, NS.Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.7 Step 7: Integrate All Components (1 hour)

Complete the main `build/2` function:

```elixir
@doc """
Builds RDF triples for a module.

Takes a module extraction result and builder context, returns the module IRI
and a list of RDF triples representing the module in the ontology.

## Parameters

- `module_info` - Module extraction result from `Extractors.Module.extract/1`
- `context` - Builder context with base IRI and configuration

## Returns

A tuple `{module_iri, triples}` where:
- `module_iri` - The IRI of the module
- `triples` - List of RDF triples describing the module

## Examples

    iex> module_info = %Module{
    ...>   type: :module,
    ...>   name: [:MyApp],
    ...>   docstring: "Main application module"
    ...> }
    iex> context = Context.new(base_iri: "https://example.org/code#")
    iex> {iri, triples} = ModuleBuilder.build(module_info, context)
    iex> to_string(iri)
    "https://example.org/code#MyApp"
"""
@spec build(ModuleExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(module_info, context) do
  # Generate module IRI
  module_iri = generate_module_iri(module_info, context)

  # Build all triples
  triples = [
    # Core module triples
    build_type_triple(module_iri, module_info),
    build_name_triple(module_iri, module_info)
  ] ++
  build_docstring_triple(module_iri, module_info) ++
  build_parent_triple(module_iri, module_info, context) ++
  build_directive_triples(module_iri, module_info, context) ++
  build_containment_triples(module_iri, module_info, context) ++
  build_location_triple(module_iri, module_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {module_iri, triples}
end

# Aggregator for all directive triples
defp build_directive_triples(module_iri, module_info, context) do
  build_alias_triples(module_iri, module_info.aliases, context) ++
  build_import_triples(module_iri, module_info.imports, context) ++
  build_require_triples(module_iri, module_info.requires, context) ++
  build_use_triples(module_iri, module_info.uses, context)
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/module_builder_test.exs`)

**Target**: 20+ comprehensive tests covering all scenarios

#### Test Categories

1. **Basic Module Building** (3 tests):
   - Simple module with minimal data
   - Module with all optional fields populated
   - Module with empty name list (edge case)

2. **Module Types** (2 tests):
   - Regular module (type `:module`)
   - Nested module (type `:nested_module`)

3. **Documentation Handling** (3 tests):
   - Module with documentation string
   - Module with `@moduledoc false`
   - Module with `nil` documentation

4. **Nested Module Relationships** (3 tests):
   - Nested module with parent reference
   - Multiple nested modules under same parent
   - Multi-level nesting (grandparent -> parent -> child)

5. **Module Directives** (5 tests):
   - Module with aliases
   - Module with imports (with and without :only/:except)
   - Module with requires
   - Module with uses
   - Module with all directive types

6. **Containment Relationships** (4 tests):
   - Module containing functions
   - Module containing macros
   - Module containing type definitions
   - Module containing all three types

7. **Source Location** (3 tests):
   - Module with location information
   - Module without location (nil)
   - Module with location but no file path in context

8. **Edge Cases** (3 tests):
   - Module with special characters in name (escaped properly)
   - Empty module (no functions, no directives)
   - Module with Erlang module references

9. **IRI Generation** (2 tests):
   - Verify correct IRI format for simple modules
   - Verify correct IRI format for deeply nested modules

10. **Triple Validation** (2 tests):
    - Verify all expected triples are generated
    - Verify no duplicate triples

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.ModuleBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{ModuleBuilder, Context}
  alias ElixirOntologies.Extractors.Module
  alias ElixirOntologies.NS.Structure

  describe "build/2 basic module" do
    test "builds minimal module with required fields" do
      module_info = %Module{
        type: :module,
        name: [:MyApp],
        docstring: nil,
        aliases: [],
        imports: [],
        requires: [],
        uses: [],
        functions: [],
        macros: [],
        types: [],
        location: nil,
        metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify IRI format
      assert to_string(module_iri) == "https://example.org/code#MyApp"

      # Verify type triple
      assert {module_iri, RDF.type(), Structure.Module()} in triples

      # Verify name triple
      assert Enum.any?(triples, fn
        {^module_iri, pred, obj} ->
          pred == Structure.moduleName() and
          RDF.Literal.value(obj) == "MyApp"
        _ -> false
      end)

      # Should have at least type and name
      assert length(triples) >= 2
    end

    test "builds module with documentation" do
      module_info = %Module{
        type: :module,
        name: [:MyApp, :Users],
        docstring: "User management module",
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify docstring triple exists
      assert Enum.any?(triples, fn
        {^module_iri, pred, obj} ->
          pred == Structure.docstring() and
          RDF.Literal.value(obj) == "User management module"
        _ -> false
      end)
    end

    test "does not build docstring triple for @moduledoc false" do
      module_info = %Module{
        type: :module,
        name: [:MyApp],
        docstring: false,
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Should not have docstring triple
      refute Enum.any?(triples, fn
        {_, pred, _} -> pred == Structure.docstring()
      end)
    end
  end

  describe "build/2 nested modules" do
    test "builds nested module with parent reference" do
      module_info = %Module{
        type: :nested_module,
        name: [:MyApp, :Users, :Admin],
        # ... other fields
        metadata: %{
          parent_module: [:MyApp, :Users],
          has_moduledoc: false,
          nested_modules: []
        }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify NestedModule type
      assert {module_iri, RDF.type(), Structure.NestedModule()} in triples

      # Verify parent relationship exists
      parent_iri = RDF.iri("https://example.org/code#MyApp.Users")
      assert {module_iri, Structure.parentModule(), parent_iri} in triples

      # Verify inverse relationship
      assert {parent_iri, Structure.hasNestedModule(), module_iri} in triples
    end
  end

  describe "build/2 directives" do
    test "builds alias relationships" do
      module_info = %Module{
        type: :module,
        name: [:MyApp],
        aliases: [
          %{module: [:MyApp, :Users], as: :U, location: nil},
          %{module: [:MyApp, :Accounts], as: nil, location: nil}
        ],
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify alias triples
      users_iri = RDF.iri("https://example.org/code#MyApp.Users")
      accounts_iri = RDF.iri("https://example.org/code#MyApp.Accounts")

      assert {module_iri, Structure.aliasesModule(), users_iri} in triples
      assert {module_iri, Structure.aliasesModule(), accounts_iri} in triples
    end
  end

  describe "build/2 containment" do
    test "builds function containment relationships" do
      module_info = %Module{
        type: :module,
        name: [:MyApp],
        functions: [
          %{name: :hello, arity: 0, visibility: :public},
          %{name: :greet, arity: 1, visibility: :public}
        ],
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Verify containsFunction triples
      hello_iri = RDF.iri("https://example.org/code#MyApp/hello/0")
      greet_iri = RDF.iri("https://example.org/code#MyApp/greet/1")

      assert {module_iri, Structure.containsFunction(), hello_iri} in triples
      assert {module_iri, Structure.containsFunction(), greet_iri} in triples
    end
  end
end
```

### 5.3 Property-Based Tests

Use StreamData for:
- Generating valid module names
- Testing IRI consistency across multiple builds
- Verifying no duplicate triples

### 5.4 Integration Tests

Test the complete flow from extractor to builder:
```elixir
test "integration: extract and build real module" do
  ast = quote do
    defmodule MyApp.Users do
      @moduledoc "User management"

      alias MyApp.Accounts
      import Ecto.Query

      def list(), do: []
      def get(id), do: nil
    end
  end

  # Extract
  {:ok, module_info} = Module.extract(ast)

  # Build
  context = Context.new(base_iri: "https://example.org/code#")
  {module_iri, triples} = ModuleBuilder.build(module_info, context)

  # Verify complete graph
  assert length(triples) > 5
  # ... more assertions
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `ModuleBuilder` module exists with complete documentation
2. ✅ `build/2` function correctly transforms `Module.t()` to RDF triples
3. ✅ All ontology classes are correctly assigned (Module vs NestedModule)
4. ✅ All datatype properties are correctly generated (moduleName, docstring)
5. ✅ All object properties are correctly generated (parent, directives, containment)
6. ✅ Nested module relationships work correctly (parent/child)
7. ✅ Module directives generate correct relationship triples
8. ✅ Containment relationships correctly link to functions/macros/types
9. ✅ Source location information is added when available
10. ✅ Special characters in module names are properly escaped
11. ✅ All functions have @spec typespecs
12. ✅ Test suite passes with 20+ comprehensive tests
13. ✅ 100% code coverage for ModuleBuilder
14. ✅ Documentation includes clear usage examples
15. ✅ No regressions in existing tests

## 7. Risk Mitigation

### Risk 1: Circular Dependencies in Nested Modules
**Issue**: Parent module might not exist yet when building nested module.
**Mitigation**:
- Generate parent IRI without requiring parent to exist first
- Document that builders are order-independent
- Validation happens at graph level, not builder level

### Risk 2: Erlang Module References
**Issue**: Directives may reference Erlang modules (atoms without namespace).
**Mitigation**:
- Handle both `[atom()]` (Elixir) and `atom()` (Erlang) formats
- Test with Erlang module examples (`:crypto`, `:ets`)

### Risk 3: Missing File Path in Context
**Issue**: Location requires file path, but context may not have it.
**Mitigation**:
- Check for both location and file_path before generating location triple
- Skip location if either is missing
- Document this behavior clearly

### Risk 4: Large Number of Directives/Functions
**Issue**: Module with many directives could generate many triples.
**Mitigation**:
- Profile with realistic module sizes
- Consider batch triple generation if performance issues
- Document expected performance characteristics

## 8. Future Enhancements

### Phase 12.1.3 Dependencies
After this phase, we can implement:
- `FunctionBuilder.build/2` - Build function RDF (uses module IRIs)
- `MacroBuilder.build/2` - Build macro RDF
- `TypeBuilder.build/2` - Build type definition RDF

### Later Optimizations
- Cache module IRIs to avoid regeneration
- Parallel building of independent modules
- Incremental updates for changed modules only

### Enhanced Features
- Generate triples for module attributes (@behaviour, @derive)
- Link to protocol implementations
- Track module dependencies graph

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Core triple generation | 2 hours | Skeleton |
| Nested module support | 1.5 hours | Core |
| Directive handling | 2 hours | Core |
| Containment relationships | 1.5 hours | Core |
| Location handling | 1 hour | Core |
| Integration and polish | 1 hour | All above |
| Unit tests (20+ tests) | 4 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 2 hours | All above |
| **Total** | **18 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/module.ex` - Module extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Ontology definitions

### Related Phase Documents
- `notes/features/phase-12-1-1-builder-infrastructure.md` - Builder infrastructure (completed)

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Elixir Module documentation: https://hexdocs.pm/elixir/Module.html
