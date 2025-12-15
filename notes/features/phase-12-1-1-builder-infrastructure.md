# Phase 12.1.1: Builder Infrastructure Planning Document

## 1. Problem Statement

Currently, the `FileAnalyzer.build_graph/3` function (line 554 in `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/analyzer/file_analyzer.ex`) is a stub that returns an empty graph:

```elixir
defp build_graph(modules, _context, _config) do
  graph = Graph.new()
  _ = length(modules)
  graph
end
```

**The Challenge**: We need to transform extractor results (structs like `Module.t()`, `Function.t()`, etc.) into RDF triples that conform to our ontology defined in `priv/ontologies/elixir-structure.ttl`.

**The Gap**: There is no infrastructure to:
1. Maintain builder context across graph construction
2. Generate IRIs for code elements consistently
3. Create RDF statements from extractor structs
4. Handle shared utilities (location conversion, namespace access, etc.)
5. Track and reuse already-generated IRIs to avoid duplication

## 2. Solution Overview

Create a **Builder Infrastructure** layer that provides:

### 2.1 BuilderContext (`lib/elixir_ontologies/builders/context.ex`)
A struct that holds all contextual information needed during graph building:
- Base IRI for the current analysis
- Configuration settings
- Git and project metadata
- IRI cache for deduplication
- Namespace shortcuts

### 2.2 Builder Helpers (`lib/elixir_ontologies/builders/helpers.ex`)
A utility module providing common operations:
- RDF triple construction helpers
- Location-to-IRI conversion
- Literal value sanitization
- Type checking and validation
- IRI caching and retrieval

### 2.3 Integration Pattern
Builders will follow a consistent pattern:
```elixir
def build_module(module_info, context) do
  module_iri = IRI.for_module(context.base_iri, module_name(module_info))

  context
  |> add_type_triple(module_iri, Structure.Module)
  |> add_property_triple(module_iri, Structure.moduleName(), module_name)
  |> add_location(module_iri, module_info.location)
  |> build_functions(module_info.functions, module_iri)
end
```

## 3. Technical Details

### 3.1 File Locations
```
lib/elixir_ontologies/
├── builders/
│   ├── context.ex          # BuilderContext struct
│   ├── helpers.ex          # Utility functions
│   └── .gitkeep            # (already exists)
├── graph.ex                # Existing - Graph API wrapper
├── iri.ex                  # Existing - IRI generation
├── ns.ex                   # Existing - Namespace definitions
└── config.ex               # Existing - Configuration
```

### 3.2 Existing APIs to Leverage

#### Graph API (`/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/graph.ex`)
- `Graph.new/0`, `Graph.new/1` - Create new graph with options
- `Graph.add/2` - Add single triple `{subject, predicate, object}`
- `Graph.add_all/2` - Add multiple triples at once
- `Graph.merge/2` - Merge graphs together
- Wraps `RDF.Graph` with domain-specific API

#### IRI Generation (`/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`)
- `IRI.for_module/2` - Generate module IRI
- `IRI.for_function/4` - Generate function IRI (module, name, arity)
- `IRI.for_clause/2` - Generate clause IRI from function IRI
- `IRI.for_parameter/2` - Generate parameter IRI from clause IRI
- `IRI.for_source_file/2` - Generate file IRI
- `IRI.for_source_location/3` - Generate location IRI (file_iri, start, end)
- `IRI.escape_name/1` - URL-encode special characters (e.g., `valid?` → `valid%3F`)

#### Namespaces (`/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex`)
- `NS.Core` - Core AST primitives
- `NS.Structure` - Elixir-specific (Module, Function, etc.)
- `NS.OTP` - OTP patterns
- `NS.Evolution` - Provenance/temporal
- `RDF.type()` - Standard RDF type predicate
- `NS.prefix_map/0` - Get all prefixes for serialization

#### Configuration (`/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/config.ex`)
```elixir
%Config{
  base_iri: "https://example.org/code#",
  include_source_text: false,
  include_git_info: true,
  output_format: :turtle
}
```

### 3.3 Extractor Struct Formats

#### Module (`ElixirOntologies.Extractors.Module.t()`)
```elixir
%Module{
  type: :module | :nested_module,
  name: [atom()],                    # e.g., [:MyApp, :Users]
  docstring: String.t() | false | nil,
  aliases: [alias_info()],
  imports: [import_info()],
  requires: [require_info()],
  uses: [use_info()],
  functions: [function_info()],      # Just metadata
  macros: [macro_info()],
  types: [type_info()],
  location: SourceLocation.t() | nil,
  metadata: %{
    parent_module: [atom()] | nil,
    has_moduledoc: boolean(),
    nested_modules: [[atom()]]
  }
}
```

#### Function (`ElixirOntologies.Extractors.Function.t()`)
```elixir
%Function{
  type: :function | :guard | :delegate,
  name: atom(),
  arity: non_neg_integer(),
  min_arity: non_neg_integer(),
  visibility: :public | :private,
  docstring: String.t() | false | nil,
  location: SourceLocation.t() | nil,
  metadata: %{
    module: [atom()] | nil,
    doc_hidden: boolean(),
    spec: term(),
    has_guard: boolean(),
    default_args: non_neg_integer(),
    delegates_to: {module(), atom(), arity()} | nil
  }
}
```

#### SourceLocation (`ElixirOntologies.Analyzer.Location.SourceLocation.t()`)
```elixir
%SourceLocation{
  start_line: pos_integer(),
  start_column: pos_integer(),
  end_line: pos_integer() | nil,
  end_column: pos_integer() | nil
}
```

### 3.4 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Key Classes
- `:Module` - Elixir module
- `:Function` - Function with (Module, Name, Arity) identity
- `:PublicFunction`, `:PrivateFunction` - Function visibility
- `:FunctionClause` - Individual clause
- `:Parameter` - Function parameter
- `:ModuleAttribute` - @attributes

#### Key Properties (Object Properties)
- `:belongsTo` - Function → Module (functional)
- `:hasClause` - Function → FunctionClause
- `:hasClauses` - Function → rdf:List (ordered clauses)
- `:hasParameter` - FunctionHead → Parameter
- `:hasParameters` - FunctionHead → rdf:List (ordered)
- `:hasAttribute` - Module → ModuleAttribute

#### Key Properties (Data Properties)
- `:moduleName` - Module name (xsd:string)
- `:functionName` - Function name (xsd:string)
- `:arity` - Function arity (xsd:nonNegativeInteger)
- `:docstring` - Documentation text (xsd:string)
- `:parameterName` - Parameter name (xsd:string)
- `:parameterPosition` - Parameter index (xsd:nonNegativeInteger)

#### Identity Keys
From ontology line 261:
```turtle
:Function owl:hasKey ( :belongsTo :functionName :arity )
```
Functions are uniquely identified by (Module, Name, Arity).

### 3.5 BuilderContext Specification

```elixir
defmodule ElixirOntologies.Builders.Context do
  @moduledoc """
  Context struct holding state during RDF graph construction.

  Provides access to configuration, IRIs, and accumulated graph.
  Tracks generated IRIs to enable reuse and prevent duplication.
  """

  alias ElixirOntologies.{Config, Graph, IRI}
  alias ElixirOntologies.Analyzer.{Git, Project}

  @type iri_cache :: %{cache_key() => RDF.IRI.t()}
  @type cache_key ::
    {:module, module_name :: String.t()} |
    {:function, module :: String.t(), name :: atom(), arity :: non_neg_integer()} |
    {:file, path :: String.t()}

  @type t :: %__MODULE__{
    # Configuration
    config: Config.t(),
    base_iri: String.t(),

    # Context metadata
    source_file: Git.SourceFile.t() | nil,
    project: Project.Project.t() | nil,

    # Graph accumulation
    graph: Graph.t(),

    # IRI caching for deduplication
    iri_cache: iri_cache(),

    # Namespace shortcuts
    ns: %{
      core: module(),
      structure: module(),
      otp: module(),
      evolution: module()
    }
  }

  defstruct [:config, :base_iri, :source_file, :project, :graph,
             iri_cache: %{}, ns: %{}]
end
```

### 3.6 Builder Helpers Specification

```elixir
defmodule ElixirOntologies.Builders.Helpers do
  @moduledoc """
  Utility functions for RDF graph construction.

  Provides helpers for:
  - Triple construction
  - IRI generation and caching
  - Location handling
  - Literal value conversion
  - Type assertions
  """

  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.{Graph, IRI}
  alias ElixirOntologies.NS.{Core, Structure}
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # Triple construction
  @spec add_type(Context.t(), RDF.IRI.t(), RDF.IRI.t()) :: Context.t()
  @spec add_property(Context.t(), RDF.IRI.t(), RDF.IRI.t(), term()) :: Context.t()
  @spec add_triple(Context.t(), RDF.Statement.t()) :: Context.t()

  # IRI generation with caching
  @spec get_or_create_module_iri(Context.t(), String.t()) :: {RDF.IRI.t(), Context.t()}
  @spec get_or_create_function_iri(Context.t(), String.t(), atom(), non_neg_integer()) ::
    {RDF.IRI.t(), Context.t()}

  # Location handling
  @spec add_location(Context.t(), RDF.IRI.t(), SourceLocation.t() | nil) :: Context.t()
  @spec location_iri(Context.t(), String.t(), SourceLocation.t()) :: RDF.IRI.t()

  # Literal conversion
  @spec to_literal(String.t()) :: RDF.Literal.t()
  @spec to_literal(atom()) :: RDF.Literal.t()
  @spec to_literal(integer()) :: RDF.Literal.t()
  @spec to_literal(boolean()) :: RDF.Literal.t()

  # Module name utilities
  @spec module_name_string([atom()]) :: String.t()
  @spec module_name_atom([atom()]) :: atom()
end
```

### 3.7 Expected Usage Pattern

```elixir
# In file_analyzer.ex build_graph/3:
defp build_graph(modules, context_info, config) do
  # Initialize builder context
  context = Context.new(
    config: config,
    base_iri: config.base_iri,
    source_file: context_info.git,
    project: context_info.project
  )

  # Build graph for all modules
  context = Enum.reduce(modules, context, fn module_analysis, ctx ->
    ModuleBuilder.build(module_analysis, ctx)
  end)

  # Extract final graph
  context.graph
end

# In module_builder.ex (Phase 12.1.2):
def build(module_analysis, context) do
  import Helpers

  {module_iri, context} =
    get_or_create_module_iri(context, module_name_string(module_analysis.name))

  context
  |> add_type(module_iri, Structure.Module)
  |> add_property(module_iri, Structure.moduleName(),
                  module_name_string(module_analysis.name))
  |> add_location(module_iri, module_analysis.location)
  |> maybe_add_docstring(module_iri, module_analysis.docstring)
end
```

## 4. Success Criteria

### 4.1 Functional Requirements
- [ ] `Context.new/1` creates valid context from config and metadata
- [ ] `Context` struct maintains graph, cache, and namespace references
- [ ] `Helpers.add_type/3` adds `rdf:type` triples correctly
- [ ] `Helpers.add_property/4` adds data/object property triples
- [ ] `Helpers.get_or_create_module_iri/2` caches IRIs to prevent duplication
- [ ] `Helpers.add_location/3` creates SourceLocation IRIs when location present
- [ ] `Helpers.to_literal/1` converts Elixir types to RDF literals correctly
- [ ] All functions maintain context immutability (return updated context)

### 4.2 Quality Requirements
- [ ] 100% documentation coverage with @moduledoc and @doc
- [ ] All functions have @spec typespecs
- [ ] Comprehensive doctests for all public functions
- [ ] Integration tests showing end-to-end context usage
- [ ] Error handling for nil/invalid inputs

### 4.3 Integration Requirements
- [ ] Works with existing Graph, IRI, NS modules
- [ ] Compatible with extractor result structs
- [ ] Follows project coding style and conventions
- [ ] No breaking changes to existing APIs

## 5. Implementation Plan

### 5.1 Step 1: Create BuilderContext Module (2 hours)
**File**: `lib/elixir_ontologies/builders/context.ex`

Tasks:
1. Define `Context` struct with all required fields
2. Implement `new/1` function accepting config and optional metadata
3. Add namespace shortcut initialization
4. Add IRI cache management functions:
   - `put_iri/3` - Cache an IRI
   - `get_iri/2` - Retrieve cached IRI
   - `has_iri?/2` - Check if IRI cached
5. Write comprehensive @moduledoc and @doc
6. Add @spec for all functions
7. Write doctests for basic usage

**Expected Output**:
```elixir
context = Context.new(
  config: Config.default(),
  base_iri: "https://example.org/code#"
)

{iri, updated_context} = Context.get_or_put_iri(
  context,
  {:module, "MyApp"},
  fn -> IRI.for_module(context.base_iri, "MyApp") end
)
```

### 5.2 Step 2: Create Builder Helpers Module (4 hours)
**File**: `lib/elixir_ontologies/builders/helpers.ex`

Tasks:
1. Implement triple construction helpers:
   - `add_type/3` - Add rdf:type triple
   - `add_property/4` - Add property triple (data or object)
   - `add_triple/2` - Add raw triple
   - `add_triples/2` - Add multiple triples

2. Implement IRI generation with caching:
   - `get_or_create_module_iri/2`
   - `get_or_create_function_iri/4`
   - `get_or_create_file_iri/2`

3. Implement location handling:
   - `add_location/3` - Add hasSourceLocation property
   - `location_iri/3` - Generate location IRI
   - `source_file_iri/2` - Generate file IRI

4. Implement literal conversion:
   - `to_literal/1` with overloads for string, atom, integer, boolean
   - `sanitize_string/1` - Clean string for RDF

5. Implement utility functions:
   - `module_name_string/1` - Convert name list to string
   - `module_name_atom/1` - Convert name list to atom
   - `function_signature/3` - Format function signature

6. Add comprehensive documentation
7. Add extensive doctests

**Expected Output**:
```elixir
context = Context.new(config: config, base_iri: "https://ex.org/")

{mod_iri, context} = Helpers.get_or_create_module_iri(context, "MyApp")
# => {~I<https://ex.org/MyApp>, context}

context = Helpers.add_type(context, mod_iri, Structure.Module)
context = Helpers.add_property(context, mod_iri,
                                Structure.moduleName(), "MyApp")
```

### 5.3 Step 3: Write Comprehensive Tests (3 hours)
**File**: `test/elixir_ontologies/builders/context_test.exs`
**File**: `test/elixir_ontologies/builders/helpers_test.exs`

Tasks:
1. Context tests:
   - Context initialization
   - IRI caching behavior
   - Graph accumulation
   - Namespace access

2. Helpers tests:
   - Triple construction
   - IRI generation and caching
   - Location handling
   - Literal conversion
   - Error cases (nil values, invalid types)

3. Integration tests:
   - Full builder workflow
   - Context threading through multiple operations
   - Cache hit/miss scenarios
   - Graph merging

**Test Coverage Target**: 100% line coverage

### 5.4 Step 4: Integration Testing (2 hours)
**File**: `test/elixir_ontologies/builders/integration_test.exs`

Tasks:
1. Create sample extractor results
2. Build graph using Context and Helpers
3. Validate generated triples
4. Verify IRI deduplication
5. Check namespace usage
6. Validate against SHACL shapes (if available)

**Example Integration Test**:
```elixir
test "builds graph for simple module with function" do
  module_info = %Module{
    name: [:MyApp],
    type: :module,
    docstring: "Test module",
    functions: [%{name: :hello, arity: 1, visibility: :public}],
    location: %SourceLocation{start_line: 1, start_column: 1}
  }

  context = Context.new(config: Config.default())
  context = ModuleBuilder.build(module_info, context)

  assert Graph.statement_count(context.graph) > 0

  # Verify module triple exists
  subjects = Graph.subjects(context.graph)
  assert Enum.any?(subjects, &String.ends_with?(to_string(&1), "MyApp"))
end
```

### 5.5 Step 5: Documentation and Examples (1 hour)
**File**: `lib/elixir_ontologies/builders/context.ex` (update)
**File**: `lib/elixir_ontologies/builders/helpers.ex` (update)

Tasks:
1. Add comprehensive usage examples to @moduledoc
2. Add cross-references between Context and Helpers
3. Document caching strategy
4. Document threading pattern for context
5. Add troubleshooting section
6. Update CHANGELOG.md

## 6. Testing Strategy

### 6.1 Unit Tests
**Target**: 100% coverage for Context and Helpers modules

Test categories:
- **Context Creation**: Valid/invalid configurations
- **IRI Caching**: Cache hits, misses, updates
- **Triple Addition**: Type triples, property triples, raw triples
- **Location Handling**: With location, without location, partial location
- **Literal Conversion**: All supported types, edge cases (empty strings, special chars)
- **Module Name Utilities**: Various formats, nested modules

### 6.2 Property-Based Tests
Use StreamData for:
- Module name generation and conversion
- IRI generation consistency
- Context immutability under operations

### 6.3 Integration Tests
- Build graph from real extractor results
- Verify graph structure matches ontology
- Check IRI uniqueness across multiple modules
- Validate RDF serialization

### 6.4 Doctest Coverage
- All public functions have working doctests
- Doctests show common usage patterns
- Edge cases documented in examples

### 6.5 Test Files Structure
```
test/
└── elixir_ontologies/
    └── builders/
        ├── context_test.exs           # Context unit tests
        ├── helpers_test.exs           # Helpers unit tests
        ├── integration_test.exs       # End-to-end tests
        └── property_test.exs          # StreamData tests
```

## 7. Risk Mitigation

### Risk 1: IRI Cache Memory Growth
**Mitigation**:
- Document expected cache size for typical projects
- Consider cache size limits or LRU eviction for very large projects
- Add cache statistics to Context (cache_hits, cache_size)

### Risk 2: Context Threading Complexity
**Mitigation**:
- Provide clear examples in documentation
- Use consistent naming (always `context`)
- Consider pipe-friendly helper variants

### Risk 3: Namespace Import Conflicts
**Mitigation**:
- Always use qualified calls (e.g., `Structure.Module`)
- Document namespace usage patterns
- Provide `ns` shortcuts in Context for convenience

### Risk 4: Performance Overhead
**Mitigation**:
- Profile graph building with realistic data
- Optimize hot paths (triple addition, IRI lookup)
- Consider batch operations for multiple triples

## 8. Future Enhancements

### Phase 12.1.2 Dependencies
After this phase, we can implement:
- `ModuleBuilder.build/2` - Build module RDF
- `FunctionBuilder.build/2` - Build function RDF
- `TypeBuilder.build/2` - Build type definition RDF

### Later Optimizations
- Parallel graph building for independent modules
- Graph streaming for very large codebases
- Incremental graph updates (track changes only)

### Monitoring and Metrics
- Track builder performance (triples/sec)
- Monitor cache hit rates
- Log warnings for missing data

## 9. Acceptance Criteria

This phase is complete when:

1. ✅ `Context` module exists with complete documentation
2. ✅ `Helpers` module exists with all utility functions
3. ✅ All functions have typespecs and doctests
4. ✅ Test suite passes with 100% coverage
5. ✅ Integration test demonstrates full workflow
6. ✅ Documentation shows clear usage examples
7. ✅ Code review approved
8. ✅ No regressions in existing tests

## 10. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| BuilderContext module | 2 hours | None |
| Builder Helpers module | 4 hours | BuilderContext |
| Unit tests | 2 hours | Context, Helpers |
| Integration tests | 1 hour | Unit tests |
| Documentation | 1 hour | All modules |
| Code review and fixes | 2 hours | All tasks |
| **Total** | **12 hours** | |

## 11. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/graph.ex` - Graph API
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Ontology

### Extractor Modules
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/module.ex`
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/function.ex`
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/analyzer/location.ex`

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- OWL 2 Web Ontology Language: https://www.w3.org/TR/owl2-overview/
