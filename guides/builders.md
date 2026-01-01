# Builders Guide

**Module**: `ElixirOntologies.Builders`
**Purpose**: Generate RDF triples from Elixir code analysis

## Overview

Builders transform extracted Elixir code structures into RDF triples following the Elixir Ontologies. Each builder takes extraction results (structs from `ElixirOntologies.Extractors`) and produces semantic triples that represent code elements as linked data.

The builder system follows a consistent pattern:

1. **Input**: Extraction struct + Context
2. **Output**: `{iri, triples}` tuple
3. **Orchestration**: Parallel execution for independent builders

## The Builder Pattern

Every builder follows this contract:

```elixir
@spec build(extraction_struct, Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(info, context) do
  # 1. Generate stable IRI
  iri = IRI.for_element(context.base_iri, ...)

  # 2. Build triples
  triples = [
    Helpers.type_triple(iri, NS.Structure.SomeClass),
    Helpers.datatype_property(iri, NS.Structure.someProp(), value, RDF.XSD.String),
    # ... more triples
  ]

  # 3. Return tuple
  {iri, triples}
end
```

### Key Components

| Component | Role | Module |
|-----------|------|--------|
| `Context` | Build configuration (base IRI, file path, metadata) | `Builders.Context` |
| `IRI` | Stable identifier generation | `ElixirOntologies.IRI` |
| `Helpers` | Triple construction utilities | `Builders.Helpers` |
| `NS` | Ontology namespace vocabulary | `ElixirOntologies.NS` |

## Context

The `Context` struct carries build state through the builder pipeline:

```elixir
alias ElixirOntologies.Builders.Context

context = Context.new(
  base_iri: "https://example.org/code#",
  file_path: "lib/my_app/users.ex",
  config: %{include_private: true},
  metadata: %{version: "1.0.0"}
)
```

### Context Fields

| Field | Type | Purpose |
|-------|------|---------|
| `base_iri` | String/RDF.IRI | Base for generating resource IRIs (required) |
| `file_path` | String | Source file being analyzed |
| `parent_module` | RDF.IRI | Parent module for nested modules |
| `config` | Map | Builder configuration options |
| `metadata` | Map | Additional context data |
| `known_modules` | MapSet | Project modules for cross-module linking |

### Context Transformations

```elixir
# Create child context for nested modules
child_context = Context.with_parent_module(context, parent_iri)

# Add metadata
context = Context.with_metadata(context, %{author: "dev"})

# Track known modules for internal vs external detection
context = Context.with_known_modules(context, ["MyApp.Users", "MyApp.Accounts"])
```

## IRI Generation

The `ElixirOntologies.IRI` module generates stable, readable identifiers:

| Element | Pattern | Example |
|---------|---------|---------|
| Module | `{base}{ModuleName}` | `#MyApp.Users` |
| Function | `{base}{Module}/{name}/{arity}` | `#MyApp.Users/get_user/1` |
| Clause | `{function}/clause/{N}` | `#.../get_user/1/clause/0` |
| Parameter | `{clause}/param/{N}` | `#.../clause/0/param/0` |
| Type | `{base}{Module}/type/{name}/{arity}` | `#MyApp/user_t/0` |
| File | `{base}file/{path}` | `#file/lib/users.ex` |
| Location | `{file}/L{start}-{end}` | `#.../users.ex/L10-25` |

### IRI Examples

```elixir
alias ElixirOntologies.IRI

base = "https://example.org/code#"

# Module IRI
IRI.for_module(base, "MyApp.Users")
#=> ~I<https://example.org/code#MyApp.Users>

# Function IRI (special chars escaped)
IRI.for_function(base, "MyApp", "valid?", 1)
#=> ~I<https://example.org/code#MyApp/valid%3F/1>

# Clause IRI (0-indexed)
IRI.for_clause(function_iri, 0)
#=> ~I<https://example.org/code#MyApp/get/1/clause/0>
```

## Helper Functions

The `Builders.Helpers` module provides triple construction utilities:

### Type Triples

```elixir
# rdf:type triple
Helpers.type_triple(module_iri, Structure.Module)
#=> {module_iri, RDF.type(), Structure.Module}

# Dual-typing (base class + specialized class)
Helpers.dual_type_triples(iri, PROV.Activity, Evolution.FeatureAddition)
#=> [{iri, RDF.type(), PROV.Activity}, {iri, RDF.type(), Evolution.FeatureAddition}]
```

### Property Triples

```elixir
# Datatype property with XSD type
Helpers.datatype_property(iri, Structure.moduleName(), "MyApp.Users", RDF.XSD.String)
Helpers.datatype_property(iri, Structure.arity(), 2, RDF.XSD.NonNegativeInteger)

# Object property (linking two resources)
Helpers.object_property(function_iri, Structure.belongsTo(), module_iri)

# Optional properties (return nil if value is nil)
Helpers.optional_string_property(iri, Evolution.commitMessage(), message)
Helpers.optional_datetime_property(iri, PROV.startedAtTime(), datetime)
```

### RDF Lists

Function clauses and parameters use ordered RDF lists:

```elixir
items = [param1_iri, param2_iri, param3_iri]
{list_head, list_triples} = Helpers.build_rdf_list(items)

# list_head is the blank node for the list head
# list_triples contains rdf:first/rdf:rest structure
```

### Automatic Type Conversion

```elixir
Helpers.to_literal(42)        #=> xsd:integer
Helpers.to_literal(3.14)      #=> xsd:double
Helpers.to_literal(true)      #=> xsd:boolean
Helpers.to_literal("hello")   #=> xsd:string
Helpers.to_literal(~D[2025-01-15]) #=> xsd:date
```

## Namespace Vocabulary

The `ElixirOntologies.NS` module provides typed access to ontology terms:

```elixir
alias ElixirOntologies.NS.{Core, Structure, OTP, Evolution, PROV}

# Classes
Structure.Module        #=> ~I<https://w3id.org/elixir-code/structure#Module>
OTP.GenServerImplementation

# Properties
Structure.moduleName()  #=> ~I<https://w3id.org/elixir-code/structure#moduleName>
Core.hasSourceLocation()
PROV.wasGeneratedBy()
```

## Builder Categories

### Core Builders

**ModuleBuilder** - Generates triples for Elixir modules:
- Module type (Module vs NestedModule)
- Name, documentation, source location
- Directives (alias, import, require, use)
- Containment relationships (functions, macros, types)

```elixir
alias ElixirOntologies.Builders.ModuleBuilder

{module_iri, triples} = ModuleBuilder.build(module_info, context)
# module_iri => ~I<https://example.org/code#MyApp.Users>
```

**FunctionBuilder** - Generates triples for functions:
- Function subtype (PublicFunction, PrivateFunction, GuardFunction, DelegatedFunction)
- Name, arity, minArity (for defaults)
- Module relationships (belongsTo/containsFunction)
- Delegation targets

```elixir
{function_iri, triples} = FunctionBuilder.build(function_info, context)
```

**ClauseBuilder** - Generates triples for function clauses:
- Clause ordering (clauseOrder property, 1-indexed)
- FunctionHead with parameter list
- FunctionBody as block
- Guard expressions

### Type System Builders

**TypeSystemBuilder** - Type definitions and specs:
- @type, @typep, @opaque declarations
- @spec function specifications
- Type expression structure

**ProtocolBuilder** - Protocols and implementations:
- Protocol definitions with function signatures
- Protocol implementations (defimpl)
- fallbackToAny property
- forDataType relationships

**BehaviourBuilder** - Behaviour callbacks:
- Behaviour definitions
- @callback declarations
- @optional_callbacks
- Implementation tracking

**StructBuilder** - Struct definitions:
- Struct fields and defaults
- @enforce_keys constraints

### OTP Builders

**GenServerBuilder** - GenServer patterns:
- GenServerImplementation type
- Callback classification (InitCallback, HandleCallCallback, etc.)
- OTP behaviour relationships

**SupervisorBuilder** - Supervision trees:
- Supervisor strategy (one_for_one, rest_for_one, one_for_all)
- Child specifications
- Supervision tree structure

**AgentBuilder** / **TaskBuilder** - Other OTP patterns

### Control Flow Builders

**ControlFlowBuilder** - Control structures:
- Conditionals (if/unless/cond)
- Case expressions with branches
- With expressions (monadic binding)
- Receive expressions
- Comprehensions

**CallGraphBuilder** - Function call tracking:
- Caller/callee relationships
- Local vs remote calls
- Dynamic calls

**ExceptionBuilder** - Exception handling:
- Try/rescue/catch/after blocks
- Raise expressions
- Throw/exit expressions

### Metaprogramming Builders

**MacroBuilder** - Macro definitions
**QuoteBuilder** - Quote expressions with unquote tracking
**CaptureBuilder** - Function capture (&) expressions
**ClosureBuilder** - Anonymous functions with closure analysis

### Evolution Builders

Located in `builders/evolution/`:

**CommitBuilder** - Git commit metadata
**ActivityBuilder** - Development activities (PROV-O alignment)
**AgentBuilder** - Developers, bots, LLM agents
**ChangeSetBuilder** - Code changes between versions

## Orchestrator

The `Orchestrator` coordinates all builders for complete module graphs:

```elixir
alias ElixirOntologies.Builders.{Orchestrator, Context}

# Analysis from extractors
analysis = %{
  module: module_extraction,
  functions: [func1, func2],
  protocols: [],
  behaviours: [],
  structs: [struct_result],
  types: [type1, type2],
  genservers: [genserver_result],
  supervisors: [],
  agents: [],
  tasks: [],
  calls: [],
  control_flow: %{},
  exceptions: %{}
}

context = Context.new(base_iri: "https://example.org/code#")
{:ok, graph} = Orchestrator.build_module_graph(analysis, context)
```

### Parallel Execution

The orchestrator runs builders in phases:

1. **Phase 1**: Module builder (establishes module IRI)
2. **Phase 2**: All other builders in parallel
3. **Aggregation**: Combine, deduplicate, create RDF.Graph

### Orchestrator Options

```elixir
Orchestrator.build_module_graph(analysis, context,
  parallel: true,           # Enable parallel execution (default)
  timeout: 5_000,           # Task timeout in ms
  include: [:functions, :types],  # Only run these builders
  exclude: [:genservers]    # Skip these builders
)
```

## Writing a Custom Builder

To add a new builder:

### 1. Define the Builder Module

```elixir
defmodule ElixirOntologies.Builders.MyBuilder do
  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias NS.Structure

  @spec build(MyExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(info, context) do
    # Generate IRI
    iri = IRI.for_module(context.base_iri, info.name)

    # Build triples
    triples = [
      Helpers.type_triple(iri, Structure.MyClass),
      Helpers.datatype_property(iri, Structure.myProp(), info.value, RDF.XSD.String)
    ] ++ build_optional_triples(iri, info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {iri, triples}
  end

  defp build_optional_triples(iri, info, context) do
    case info.optional_field do
      nil -> []
      value -> [Helpers.datatype_property(iri, Structure.optionalProp(), value, RDF.XSD.String)]
    end
  end
end
```

### 2. Handle Location Information

```elixir
defp build_location_triple(iri, info, context) do
  case {info.location, context.file_path} do
    {nil, _} -> []
    {_location, nil} -> []
    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

      [Helpers.object_property(iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 3. Register with Orchestrator

Add your builder to `Orchestrator.build_phase_2/7`:

```elixir
builders = [
  # ... existing builders
  {:my_elements, &build_my_elements/3}
]

defp build_my_elements(analysis, _module_iri, context) do
  analysis
  |> Map.get(:my_elements, [])
  |> Enum.flat_map(fn element ->
    {_iri, triples} = MyBuilder.build(element, context)
    triples
  end)
end
```

## Complete Example

Building triples for a simple module:

```elixir
alias ElixirOntologies.Builders.{ModuleBuilder, FunctionBuilder, Context}
alias ElixirOntologies.Extractors.{Module, Function}

# Extraction results
module_info = %Module{
  type: :module,
  name: [:MyApp, :Users],
  docstring: "User management module",
  aliases: [],
  imports: [],
  requires: [],
  uses: [],
  functions: [],
  macros: [],
  types: [],
  location: %{start_line: 1, end_line: 50},
  metadata: %{parent_module: nil, has_moduledoc: true, nested_modules: []}
}

function_info = %Function{
  type: :function,
  name: :get_user,
  arity: 1,
  min_arity: 1,
  visibility: :public,
  docstring: "Fetches a user by ID",
  location: %{start_line: 10, end_line: 15},
  metadata: %{module: [:MyApp, :Users]}
}

# Build context
context = Context.new(
  base_iri: "https://example.org/code#",
  file_path: "lib/my_app/users.ex"
)

# Build module triples
{module_iri, module_triples} = ModuleBuilder.build(module_info, context)

# Build function triples
{function_iri, function_triples} = FunctionBuilder.build(function_info, context)

# Combine into graph
all_triples = module_triples ++ function_triples

graph = Enum.reduce(all_triples, RDF.Graph.new(), fn triple, g ->
  RDF.Graph.add(g, triple)
end)

# Serialize to Turtle
turtle = RDF.Turtle.write_string!(graph, prefixes: ElixirOntologies.NS.prefix_map())
```

Output (excerpt):
```turtle
@prefix struct: <https://w3id.org/elixir-code/structure#> .

<https://example.org/code#MyApp.Users> a struct:Module ;
    struct:moduleName "MyApp.Users" ;
    struct:docstring "User management module" ;
    struct:containsFunction <https://example.org/code#MyApp.Users/get_user/1> .

<https://example.org/code#MyApp.Users/get_user/1> a struct:Function, struct:PublicFunction ;
    struct:functionName "get_user" ;
    struct:arity 1 ;
    struct:belongsTo <https://example.org/code#MyApp.Users> ;
    struct:docstring "Fetches a user by ID" .
```

## Design Principles

1. **Deterministic IRIs**: Same code element always produces the same IRI
2. **Separation of Concerns**: Extractors analyze, builders serialize
3. **Composability**: Builders are independent and can be combined
4. **Parallel-safe**: Builders are read-only, enabling parallel execution
5. **Ontology Alignment**: Triples conform to the Elixir Ontologies schema
6. **Location Tracking**: Every element can link to source location
