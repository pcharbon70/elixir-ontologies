# Phase 12.2.2: Behaviour Builder Planning Document

## 1. Problem Statement

Phase 12.2.1 completed the Protocol Builder, handling Elixir's type-based polymorphism. Now we need to implement the Behaviour Builder to handle Elixir's contract-based polymorphism mechanism.

**The Challenge**: The Behaviour extractor (`ElixirOntologies.Extractors.Behaviour`) produces rich structured data about behaviour definitions and implementations, but this data needs to be converted to RDF triples that conform to the `elixir-structure.ttl` ontology while correctly representing Elixir's module-based contract semantics.

**Current State**:
- Behaviour extractor produces two distinct operation modes:
  - `Behaviour.t()` structs for behaviour definitions (@callback declarations)
  - `implementation_result()` maps for behaviour implementations (@behaviour declarations)
- Module Builder generates containment triples but not behaviour-specific semantics
- Protocol Builder established the pattern for polymorphism builders
- Builder infrastructure exists but no behaviour-specific builder

**Why Behaviours Are Important**:
Behaviours are Elixir's primary contract mechanism, enabling:
- Module-based dispatch (vs type-based for protocols)
- Callback contract enforcement
- Optional vs required callbacks
- Default implementations with defoverridable
- OTP behaviour implementations (GenServer, Supervisor, etc.)
- Compile-time verification of implementations

Understanding behaviour relationships is critical for:
- Analyzing OTP patterns and supervision trees
- Tracking contract compliance across modules
- Validating complete callback implementations
- Understanding module-based architecture

**The Gap**: We need to:
1. Generate IRIs for behaviours (using module IRI pattern)
2. Generate IRIs for behaviour implementations (module + behaviour combination)
3. Create `rdf:type` triples for Behaviour, CallbackFunction, and BehaviourImplementation classes
4. Build callback-specific properties (callbackName, callbackArity, isOptional)
5. Build object properties linking behaviours to callbacks (definesCallback)
6. Build implementation relationships (implementsBehaviour, implementsCallback)
7. Handle optional vs required callbacks
8. Handle macro callbacks (@macrocallback)
9. Link implementation functions to behaviour callbacks
10. Support defoverridable metadata

## 2. Solution Overview

Create a **Behaviour Builder** that transforms behaviour and implementation structs into RDF triples representing Elixir's contract semantics.

### 2.1 Core Functionality

The builder will provide two main functions:
- `build_behaviour/2` - Transform behaviour definitions into RDF
- `build_implementation/2` - Transform behaviour implementations into RDF

Both follow the established builder pattern:
```elixir
{behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)
{impl_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)
```

### 2.2 Builder Pattern

**Behaviour Building**:
```elixir
def build_behaviour(behaviour_info, context) do
  # Generate behaviour IRI (uses module pattern)
  behaviour_iri = generate_behaviour_iri(behaviour_info, context)

  # Build all triples
  triples =
    [
      build_type_triple(behaviour_iri, :behaviour),
      build_module_defines_behaviour_triple(behaviour_iri, context)
    ] ++
      build_callback_triples(behaviour_iri, behaviour_info, context) ++
      build_macrocallback_triples(behaviour_iri, behaviour_info, context) ++
      build_docstring_triple(behaviour_iri, behaviour_info)

  {behaviour_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**Implementation Building**:
```elixir
def build_implementation(impl_info, module_iri, context) do
  # Build all triples
  triples =
    build_behaviour_implementation_triples(module_iri, impl_info, context) ++
      build_callback_implementation_triples(module_iri, impl_info, context)

  triples = List.flatten(triples) |> Enum.uniq()
  {module_iri, triples}
end
```

### 2.3 Integration Point

The Behaviour Builder will be called from a higher-level orchestrator (similar to Protocol Builder):

```elixir
# In FileAnalyzer or similar
behaviours = Behaviour.extract_all(module_bodies)
implementations = Behaviour.extract_implementations(module_body)

# Build behaviour definitions
behaviour_triples = Enum.flat_map(behaviours, fn behaviour ->
  {_iri, triples} = BehaviourBuilder.build_behaviour(behaviour, context)
  triples
end)

# Build behaviour implementations
impl_triples =
  {_iri, triples} = BehaviourBuilder.build_implementation(implementations, module_iri, context)
  triples
```

## 3. Technical Details

### 3.1 Behaviour Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/behaviour.ex`:

**Behaviour Definition**:
```elixir
%ElixirOntologies.Extractors.Behaviour{
  # Callbacks (required by default)
  callbacks: [
    %{
      name: atom(),                        # e.g., :init, :handle_call
      arity: non_neg_integer(),           # Number of parameters
      spec: Macro.t(),                    # Full typespec AST
      return_type: Macro.t() | nil,       # Return type AST
      parameters: [Macro.t()],            # Parameter type specs
      is_optional: boolean(),             # Marked in @optional_callbacks
      type: :callback,                    # Always :callback for this list
      doc: String.t() | nil,              # Callback @doc
      location: SourceLocation.t() | nil
    }
  ],

  # Macro callbacks
  macrocallbacks: [
    %{
      # Same structure as callbacks
      type: :macrocallback               # Always :macrocallback for this list
    }
  ],

  # Optional callbacks list (name/arity tuples)
  optional_callbacks: [{atom(), non_neg_integer()}],

  # Documentation
  doc: String.t() | false | nil,         # Behaviour @moduledoc

  # Metadata
  metadata: %{
    callback_count: non_neg_integer(),
    macrocallback_count: non_neg_integer(),
    optional_callback_count: non_neg_integer(),
    has_doc: boolean()
  }
}
```

**Behaviour Implementation**:
```elixir
%{
  # List of @behaviour declarations
  behaviours: [
    %{
      behaviour: module() | atom(),          # e.g., GenServer, Plug
      behaviour_alias: Macro.t(),            # AST for behaviour reference
      location: SourceLocation.t() | nil
    }
  ],

  # Defoverridable declarations
  overridables: [
    %{
      name: atom(),
      arity: non_neg_integer(),
      source: :list | :module,               # From keyword list or module
      location: SourceLocation.t() | nil
    }
  ],

  # Functions defined in module
  functions: [{atom(), non_neg_integer()}]  # {name, arity} tuples
}
```

**Key Points**:
- Behaviour is tied to a module (extracted from module body)
- Callbacks and macrocallbacks are separate lists
- `is_optional` flag on each callback indicates optional status
- Implementation includes list of behaviours + defined functions
- `functions` list allows matching implementations to callbacks
- Overridables can come from keyword list or behaviour module reference

### 3.2 IRI Generation Patterns

**Behaviour IRIs** (same as module IRI since behaviour IS a module):
```elixir
# Behaviour uses module IRI pattern (behaviour is defined by a module)
# Need module name from context (behaviour extractor doesn't include it)
module_name = context.module_name  # e.g., "GenServer", "MyApp.Behaviour"
IRI.for_module(context.base_iri, module_name)

# Examples:
GenServer behaviour -> "base#GenServer"
MyApp.CustomBehaviour -> "base#MyApp.CustomBehaviour"
```

**Callback IRIs** (use function pattern with behaviour module):
```elixir
# Callback IRI uses function pattern
behaviour_module = context.module_name
IRI.for_function(context.base_iri, behaviour_module, callback.name, callback.arity)

# Examples:
GenServer.init/1 -> "base#GenServer/init/1"
GenServer.handle_call/3 -> "base#GenServer/handle_call/3"
Plug.init/1 -> "base#Plug/init/1"
```

**Implementation IRIs** (module implementing the behaviour):
```elixir
# Implementation uses implementing module's IRI
implementing_module = module_name  # The module with @behaviour
IRI.for_module(context.base_iri, implementing_module)

# Examples:
MyServer (implements GenServer) -> "base#MyServer"
MyPlug (implements Plug) -> "base#MyPlug"
```

**Callback Implementation IRIs** (function in implementing module):
```elixir
# Implementation function uses standard function IRI
implementing_module = module_name
IRI.for_function(context.base_iri, implementing_module, func_name, func_arity)

# Examples:
MyServer.init/1 -> "base#MyServer/init/1"
MyServer.handle_call/3 -> "base#MyServer/handle_call/3"
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Classes

```turtle
:Behaviour a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "An Elixir behaviour defining a contract of callback functions" .

:CallbackFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "A function that must or may be implemented by behaviour implementors" .

:RequiredCallback a owl:Class ;
    rdfs:subClassOf :CallbackFunction ;
    rdfs:comment "A callback that must be implemented" .

:OptionalCallback a owl:Class ;
    rdfs:subClassOf :CallbackFunction ;
    rdfs:comment "A callback that may optionally be implemented" .

:MacroCallback a owl:Class ;
    rdfs:subClassOf :CallbackFunction ;
    rdfs:comment "A macro callback defined with @macrocallback" .

:BehaviourImplementation a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "A module that implements a behaviour via @behaviour" .
```

**Class Selection Logic**:
```elixir
# For behaviour - always Behaviour class
defp determine_behaviour_class(_behaviour_info), do: Structure.Behaviour

# For callbacks - check optional and type
defp determine_callback_class(callback) do
  cond do
    callback.type == :macrocallback -> Structure.MacroCallback
    callback.is_optional -> Structure.OptionalCallback
    true -> Structure.RequiredCallback
  end
end

# For implementations - use BehaviourImplementation
defp determine_implementation_class(_impl_info), do: Structure.BehaviourImplementation
```

#### Object Properties

```turtle
# Module -> Behaviour relationship
:definesBehaviour a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :Module ;
    rdfs:range :Behaviour .

# Behaviour -> Callback relationship
:definesCallback a owl:ObjectProperty ;
    rdfs:domain :Behaviour ;
    rdfs:range :CallbackFunction .

# Module -> Behaviour relationship (implementation)
:implementsBehaviour a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Behaviour .

# Function -> Callback relationship (implementation)
:implementsCallback a owl:ObjectProperty ;
    rdfs:domain :Function ;
    rdfs:range :CallbackFunction .

# Function -> Function relationship (overrides)
:overridesDefault a owl:ObjectProperty ;
    rdfs:label "overrides default" .
```

#### Data Properties

```turtle
# Callback properties
:callbackName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :CallbackFunction ;
    rdfs:range xsd:string .

:callbackArity a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :CallbackFunction ;
    rdfs:range xsd:nonNegativeInteger .
```

### 3.4 Triple Generation Examples

**Simple Behaviour**:
```turtle
<base#MyBehaviour> a struct:Behaviour ;
    struct:moduleName "MyBehaviour"^^xsd:string ;
    struct:definesCallback <base#MyBehaviour/init/1> ;
    struct:definesCallback <base#MyBehaviour/handle/2> ;
    core:hasSourceLocation <base#file/lib/my_behaviour.ex/L1-20> .

<base#Module.MyBehaviour> struct:definesBehaviour <base#MyBehaviour> .

<base#MyBehaviour/init/1> a struct:RequiredCallback ;
    struct:callbackName "init"^^xsd:string ;
    struct:callbackArity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyBehaviour> .

<base#MyBehaviour/handle/2> a struct:RequiredCallback ;
    struct:callbackName "handle"^^xsd:string ;
    struct:callbackArity "2"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyBehaviour> .
```

**Behaviour with Optional Callbacks**:
```turtle
<base#GenServer> a struct:Behaviour ;
    struct:moduleName "GenServer"^^xsd:string ;
    struct:definesCallback <base#GenServer/init/1> ;
    struct:definesCallback <base#GenServer/handle_call/3> ;
    struct:definesCallback <base#GenServer/terminate/2> ;
    struct:docstring "Generic server behaviour"^^xsd:string .

<base#GenServer/init/1> a struct:RequiredCallback ;
    struct:callbackName "init"^^xsd:string ;
    struct:callbackArity "1"^^xsd:nonNegativeInteger .

<base#GenServer/handle_call/3> a struct:RequiredCallback ;
    struct:callbackName "handle_call"^^xsd:string ;
    struct:callbackArity "3"^^xsd:nonNegativeInteger .

<base#GenServer/terminate/2> a struct:OptionalCallback ;
    struct:callbackName "terminate"^^xsd:string ;
    struct:callbackArity "2"^^xsd:nonNegativeInteger .
```

**Macro Callback**:
```turtle
<base#MyBehaviour/before_compile/1> a struct:MacroCallback ;
    struct:callbackName "before_compile"^^xsd:string ;
    struct:callbackArity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyBehaviour> .

<base#MyBehaviour> struct:definesCallback <base#MyBehaviour/before_compile/1> .
```

**Behaviour Implementation**:
```turtle
<base#MyServer> a struct:Module ;
    struct:moduleName "MyServer"^^xsd:string ;
    struct:implementsBehaviour <base#GenServer> ;
    struct:containsFunction <base#MyServer/init/1> ;
    struct:containsFunction <base#MyServer/handle_call/3> .

<base#MyServer/init/1> a struct:Function ;
    struct:functionName "init"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyServer> ;
    struct:implementsCallback <base#GenServer/init/1> .

<base#MyServer/handle_call/3> a struct:Function ;
    struct:functionName "handle_call"^^xsd:string ;
    struct:arity "3"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyServer> ;
    struct:implementsCallback <base#GenServer/handle_call/3> .
```

**Multiple Behaviour Implementation**:
```turtle
<base#MyModule> a struct:Module ;
    struct:implementsBehaviour <base#GenServer> ;
    struct:implementsBehaviour <base#Plug> .

<base#MyModule/init/1>
    struct:implementsCallback <base#GenServer/init/1> ;
    struct:implementsCallback <base#Plug/init/1> .
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple
Helpers.type_triple(behaviour_iri, Structure.Behaviour)
#=> {behaviour_iri, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Behaviour>}

# Callback type
Helpers.type_triple(callback_iri, Structure.RequiredCallback)
Helpers.type_triple(callback_iri, Structure.OptionalCallback)
Helpers.type_triple(callback_iri, Structure.MacroCallback)

# Datatype property (string)
Helpers.datatype_property(callback_iri, Structure.callbackName(), "init", RDF.XSD.String)
#=> {callback_iri, Structure.callbackName(), RDF.XSD.String.new("init")}

# Datatype property (integer)
Helpers.datatype_property(callback_iri, Structure.callbackArity(), 1, RDF.XSD.NonNegativeInteger)
#=> {callback_iri, Structure.callbackArity(), RDF.XSD.NonNegativeInteger.new(1)}

# Object property
Helpers.object_property(behaviour_iri, Structure.definesCallback(), callback_iri)
#=> {behaviour_iri, Structure.definesCallback(), callback_iri}

# Implementation relationships
Helpers.object_property(module_iri, Structure.implementsBehaviour(), behaviour_iri)
#=> {module_iri, Structure.implementsBehaviour(), behaviour_iri}

Helpers.object_property(func_iri, Structure.implementsCallback(), callback_iri)
#=> {func_iri, Structure.implementsCallback(), callback_iri}
```

### 3.6 Handling Edge Cases

#### Module Name Context

Since behaviour extractor doesn't include the module name, we need it from context:

```elixir
defp build_behaviour(behaviour_info, context) do
  # Require module_name in context
  module_name = context.module_name ||
    raise "module_name required in context for behaviour building"

  behaviour_iri = IRI.for_module(context.base_iri, module_name)

  # Build triples...
end
```

#### Optional Callbacks

The extractor marks callbacks with `is_optional: true`. We use this to determine class:

```elixir
defp build_callback_triple(behaviour_iri, callback, context) do
  callback_iri = generate_callback_iri(behaviour_iri, callback, context)

  # Determine class based on is_optional flag
  class = if callback.is_optional do
    Structure.OptionalCallback
  else
    Structure.RequiredCallback
  end

  [
    Helpers.type_triple(callback_iri, class),
    # ... other triples
  ]
end
```

#### Macro Callbacks

Separate list in extractor, but similar handling:

```elixir
defp build_macrocallback_triples(behaviour_iri, behaviour_info, context) do
  Enum.flat_map(behaviour_info.macrocallbacks, fn callback ->
    callback_iri = generate_callback_iri(behaviour_iri, callback, context)

    [
      # Always MacroCallback class
      Helpers.type_triple(callback_iri, Structure.MacroCallback),
      # ... other properties
    ]
  end)
end
```

#### Callback Implementation Matching

Match functions to callbacks by name/arity:

```elixir
defp build_callback_implementation_triples(module_iri, impl_info, context) do
  # For each behaviour this module implements
  Enum.flat_map(impl_info.behaviours, fn behaviour_impl ->
    behaviour_iri = generate_behaviour_iri_from_module(behaviour_impl.behaviour, context)

    # Match module functions to behaviour callbacks
    # This would require loading behaviour definition or inferring from function list
    # For now, we can create implementsCallback triples based on known patterns

    build_callback_matches(module_iri, behaviour_iri, impl_info.functions, context)
  end)
end

defp build_callback_matches(module_iri, behaviour_iri, functions, context) do
  # This is complex - we need to know what callbacks the behaviour defines
  # Option 1: Query existing RDF graph for behaviour callbacks
  # Option 2: Store callback info in context
  # Option 3: Generate implementsCallback links only for known OTP behaviours
  # For V1: Skip this, let SHACL validation catch missing implementations
  []
end
```

#### Defoverridable Support

Handle overridable functions:

```elixir
defp build_overridable_triples(module_iri, impl_info, context) do
  Enum.flat_map(impl_info.overridables, fn overridable ->
    case overridable.source do
      :list ->
        # Explicit list: defoverridable [init: 1]
        func_iri = IRI.for_function(context.base_iri, context.module_name,
                                     overridable.name, overridable.arity)

        # Mark as overridable (could use custom property or annotation)
        [Helpers.datatype_property(func_iri, Structure.isOverridable(), true, RDF.XSD.Boolean)]

      :module ->
        # Module reference: defoverridable MyBehaviour
        # This makes all behaviour functions overridable
        []  # Skip for now, would need behaviour introspection
    end
  end)
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Behaviour Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/behaviour_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build_behaviour/2` and `build_implementation/2` function signatures
3. Add helper functions for IRI generation
4. Import necessary namespaces (Helpers, IRI, Structure, Core)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.BehaviourBuilder do
  @moduledoc """
  Builds RDF triples for Elixir behaviours and behaviour implementations.

  This module transforms behaviour-related extractor results into RDF triples
  following the elixir-structure.ttl ontology. It handles:

  - Behaviour definitions (modules with @callback/@macrocallback)
  - Callback specifications (required vs optional)
  - Macro callbacks (@macrocallback)
  - Behaviour implementations (@behaviour declarations)
  - Callback implementations (functions matching behaviour callbacks)
  - Defoverridable declarations

  ## Usage

      alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      alias ElixirOntologies.Extractors.Behaviour

      # Build behaviour definition
      behaviour_info = %Behaviour{callbacks: [...], ...}
      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyBehaviour")
      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Build behaviour implementation
      impl_info = Behaviour.extract_implementations(module_body)
      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyServer")
      {module_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)

  ## Behaviour vs Protocol

  **Behaviours** are module-based contracts:
  - Define required/optional callbacks modules must implement
  - Used for GenServer, Supervisor, Plug, etc.
  - Module implements via @behaviour declaration

  **Protocols** are type-based polymorphism:
  - Define functions dispatched on data type
  - Implemented via defimpl for specific types
  - Type-based dispatch at runtime
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Behaviour, as: BehaviourExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Behaviour Definition Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a behaviour definition.

  Takes a behaviour extraction result (containing callbacks and macrocallbacks)
  and builder context, returns the behaviour IRI and a list of RDF triples.

  ## Parameters

  - `behaviour_info` - Behaviour extraction result from `Behaviour.extract_from_body/1`
  - `context` - Builder context with base IRI and module name

  ## Returns

  A tuple `{behaviour_iri, triples}` where:
  - `behaviour_iri` - The IRI of the behaviour (same as module IRI)
  - `triples` - List of RDF triples describing the behaviour and callbacks

  ## Context Requirements

  The context MUST include `module_name` field, as the behaviour extractor
  doesn't capture the module name itself.

  ## Examples

      iex> alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> behaviour_info = %Behaviour{
      ...>   callbacks: [
      ...>     %{name: :init, arity: 1, is_optional: false, type: :callback,
      ...>       spec: nil, return_type: nil, parameters: [], doc: nil, location: nil}
      ...>   ],
      ...>   macrocallbacks: [],
      ...>   optional_callbacks: [],
      ...>   doc: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#", module_name: "MyBehaviour")
      iex> {behaviour_iri, _triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)
      iex> to_string(behaviour_iri)
      "https://example.org/code#MyBehaviour"
  """
  @spec build_behaviour(BehaviourExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_behaviour(behaviour_info, context)

  # ===========================================================================
  # Public API - Behaviour Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for behaviour implementations.

  Takes an implementation result (containing @behaviour declarations and functions)
  and builder context, returns the module IRI and implementation triples.

  ## Parameters

  - `impl_info` - Implementation result from `Behaviour.extract_implementations/1`
  - `context` - Builder context with base IRI and module name

  ## Returns

  A tuple `{module_iri, triples}` where:
  - `module_iri` - The IRI of the implementing module
  - `triples` - List of RDF triples describing behaviour implementations

  ## Examples

      iex> alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
      iex> impl_info = %{
      ...>   behaviours: [
      ...>     %{behaviour: GenServer, behaviour_alias: {:__aliases__, [], [:GenServer]}, location: nil}
      ...>   ],
      ...>   overridables: [],
      ...>   functions: [{:init, 1}, {:handle_call, 3}]
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#", module_name: "MyServer")
      iex> {module_iri, _triples} = BehaviourBuilder.build_implementation(impl_info, context)
      iex> to_string(module_iri)
      "https://example.org/code#MyServer"
  """
  @spec build_implementation(BehaviourExtractor.implementation_result(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_implementation(impl_info, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp generate_behaviour_iri(module_name, context)
  defp generate_callback_iri(behaviour_iri, callback, context)
  defp generate_behaviour_iri_from_module(behaviour_module, context)
  defp module_name_from_atom(module_atom)
  # ... etc
end
```

### 4.2 Step 2: Implement Behaviour Triple Generation (2 hours)

Implement functions for behaviour definition triples:

1. **IRI Generation**:
```elixir
defp generate_behaviour_iri(context) do
  # Behaviour IRI is same as module IRI
  module_name = context.module_name ||
    raise ArgumentError, "module_name required in context for behaviour building"

  IRI.for_module(context.base_iri, module_name)
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(behaviour_iri) do
  Helpers.type_triple(behaviour_iri, Structure.Behaviour)
end
```

3. **Module Defines Behaviour Relationship**:
```elixir
defp build_module_defines_behaviour_triple(behaviour_iri, context) do
  module_iri = IRI.for_module(context.base_iri, context.module_name)
  Helpers.object_property(module_iri, Structure.definesBehaviour(), behaviour_iri)
end
```

4. **Documentation** (optional):
```elixir
defp build_docstring_triple(behaviour_iri, behaviour_info) do
  case behaviour_info.doc do
    nil -> []
    false -> []
    doc when is_binary(doc) ->
      [Helpers.datatype_property(behaviour_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end
```

### 4.3 Step 3: Implement Callback Handling (2 hours)

Generate triples for callbacks and their relationships:

```elixir
defp build_callback_triples(behaviour_iri, behaviour_info, context) do
  module_name = context.module_name

  Enum.flat_map(behaviour_info.callbacks, fn callback ->
    # Generate callback IRI
    callback_iri = IRI.for_function(context.base_iri, module_name,
                                     callback.name, callback.arity)

    # Determine callback class
    class = if callback.is_optional do
      Structure.OptionalCallback
    else
      Structure.RequiredCallback
    end

    # Build callback triples
    callback_triples = [
      # rdf:type (RequiredCallback or OptionalCallback)
      Helpers.type_triple(callback_iri, class),
      # callbackName
      Helpers.datatype_property(callback_iri, Structure.callbackName(),
                                Atom.to_string(callback.name), RDF.XSD.String),
      # callbackArity
      Helpers.datatype_property(callback_iri, Structure.callbackArity(),
                                callback.arity, RDF.XSD.NonNegativeInteger),
      # belongsTo behaviour
      Helpers.object_property(callback_iri, Structure.belongsTo(), behaviour_iri)
    ] ++
      build_callback_doc(callback_iri, callback) ++
      build_callback_location(callback_iri, callback, context)

    # Behaviour -> callback relationship
    behaviour_link = Helpers.object_property(behaviour_iri, Structure.definesCallback(),
                                              callback_iri)

    [behaviour_link | callback_triples]
  end)
end

defp build_callback_doc(callback_iri, callback) do
  case callback.doc do
    nil -> []
    doc when is_binary(doc) ->
      [Helpers.datatype_property(callback_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end

defp build_callback_location(callback_iri, callback, context) do
  case {callback.location, context.file_path} do
    {nil, _} -> []
    {_, nil} -> []
    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)
      [Helpers.object_property(callback_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.4 Step 4: Implement Macro Callback Handling (1 hour)

Similar to callbacks but always MacroCallback class:

```elixir
defp build_macrocallback_triples(behaviour_iri, behaviour_info, context) do
  module_name = context.module_name

  Enum.flat_map(behaviour_info.macrocallbacks, fn callback ->
    # Generate callback IRI
    callback_iri = IRI.for_function(context.base_iri, module_name,
                                     callback.name, callback.arity)

    # Build macrocallback triples
    callback_triples = [
      # rdf:type (always MacroCallback)
      Helpers.type_triple(callback_iri, Structure.MacroCallback),
      # callbackName
      Helpers.datatype_property(callback_iri, Structure.callbackName(),
                                Atom.to_string(callback.name), RDF.XSD.String),
      # callbackArity
      Helpers.datatype_property(callback_iri, Structure.callbackArity(),
                                callback.arity, RDF.XSD.NonNegativeInteger),
      # belongsTo behaviour
      Helpers.object_property(callback_iri, Structure.belongsTo(), behaviour_iri)
    ] ++
      build_callback_doc(callback_iri, callback) ++
      build_callback_location(callback_iri, callback, context)

    # Behaviour -> macrocallback relationship
    behaviour_link = Helpers.object_property(behaviour_iri, Structure.definesCallback(),
                                              callback_iri)

    [behaviour_link | callback_triples]
  end)
end
```

### 4.5 Step 5: Implement Implementation Triple Generation (2 hours)

Build triples for behaviour implementations:

```elixir
defp build_behaviour_implementation_triples(module_iri, impl_info, context) do
  Enum.flat_map(impl_info.behaviours, fn behaviour_impl ->
    # Generate behaviour IRI
    behaviour_iri = generate_behaviour_iri_from_module(behaviour_impl.behaviour, context)

    [
      # Module implementsBehaviour Behaviour
      Helpers.object_property(module_iri, Structure.implementsBehaviour(), behaviour_iri)
    ]
  end)
end

defp generate_behaviour_iri_from_module(behaviour_module, context) do
  # Convert module atom to string
  module_name = module_name_from_atom(behaviour_module)
  IRI.for_module(context.base_iri, module_name)
end

defp module_name_from_atom(module) when is_atom(module) do
  # Handle both Elixir.GenServer and GenServer
  module
  |> Atom.to_string()
  |> String.trim_leading("Elixir.")
end
```

### 4.6 Step 6: Implement Callback Implementation Linkage (2 hours)

Link implementation functions to behaviour callbacks:

```elixir
defp build_callback_implementation_triples(module_iri, impl_info, context) do
  # For each behaviour this module implements
  Enum.flat_map(impl_info.behaviours, fn behaviour_impl ->
    behaviour_module_name = module_name_from_atom(behaviour_impl.behaviour)

    # For each function in the module, check if it matches a known callback
    Enum.flat_map(impl_info.functions, fn {func_name, func_arity} ->
      # Generate function IRI in implementing module
      func_iri = IRI.for_function(context.base_iri, context.module_name,
                                   func_name, func_arity)

      # Generate potential callback IRI in behaviour module
      callback_iri = IRI.for_function(context.base_iri, behaviour_module_name,
                                       func_name, func_arity)

      # Create implementsCallback link
      # Note: This assumes function matches callback by name/arity
      # SHACL validation will verify the callback actually exists
      if should_link_callback?(func_name, func_arity, behaviour_impl.behaviour) do
        [Helpers.object_property(func_iri, Structure.implementsCallback(), callback_iri)]
      else
        []
      end
    end)
  end)
end

# Helper to determine if we should create callback link
# For V1, link common OTP callbacks, otherwise skip
defp should_link_callback?(func_name, _func_arity, behaviour_module) do
  known_callbacks = get_known_callbacks(behaviour_module)
  func_name in known_callbacks
end

defp get_known_callbacks(module) do
  case module do
    GenServer -> [:init, :handle_call, :handle_cast, :handle_info, :terminate, :code_change]
    Supervisor -> [:init]
    Application -> [:start, :stop]
    _ -> []  # For unknown behaviours, skip linking (let SHACL validate)
  end
end
```

### 4.7 Step 7: Integrate All Components (1 hour)

Complete the main `build_behaviour/2` and `build_implementation/2` functions:

```elixir
@spec build_behaviour(BehaviourExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_behaviour(behaviour_info, context) do
  # Generate behaviour IRI (same as module IRI)
  behaviour_iri = generate_behaviour_iri(context)

  # Build all triples
  triples =
    [
      # Core behaviour triple
      build_type_triple(behaviour_iri),
      # Module defines behaviour relationship
      build_module_defines_behaviour_triple(behaviour_iri, context)
    ] ++
      # Callbacks
      build_callback_triples(behaviour_iri, behaviour_info, context) ++
      # Macro callbacks
      build_macrocallback_triples(behaviour_iri, behaviour_info, context) ++
      # Optional documentation
      build_docstring_triple(behaviour_iri, behaviour_info)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {behaviour_iri, triples}
end

@spec build_implementation(BehaviourExtractor.implementation_result(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_implementation(impl_info, context) do
  # Generate module IRI
  module_iri = IRI.for_module(context.base_iri, context.module_name)

  # Build all triples
  triples =
    # Behaviour implementation relationships
    build_behaviour_implementation_triples(module_iri, impl_info, context) ++
      # Callback implementation linkages
      build_callback_implementation_triples(module_iri, impl_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {module_iri, triples}
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/behaviour_builder_test.exs`)

**Target**: 15+ comprehensive tests covering behaviours and implementations

#### Test Categories

**Behaviour Building Tests** (7 tests):

1. **Basic Behaviour Building** (3 tests):
   - Simple behaviour with one required callback
   - Behaviour with multiple callbacks
   - Behaviour with no callbacks (edge case)

2. **Callback Types** (3 tests):
   - Required callback (default)
   - Optional callback (is_optional: true)
   - Macro callback (@macrocallback)

3. **Behaviour Documentation** (1 test):
   - Behaviour with @moduledoc

**Implementation Building Tests** (8 tests):

4. **Basic Implementation Building** (3 tests):
   - Single behaviour implementation (GenServer)
   - Multiple behaviour implementations
   - Implementation with no behaviours (no triples)

5. **Callback Implementation Linkage** (3 tests):
   - Function implements callback (name/arity match)
   - Multiple functions implement multiple callbacks
   - Function doesn't match any callback (no link)

6. **Known OTP Behaviours** (2 tests):
   - GenServer implementation links (init, handle_call, etc.)
   - Supervisor implementation links (init)

**Integration Tests** (2+ tests):

7. **Complete Behaviour Definition** (1 test):
   - Extract and build real behaviour with callbacks

8. **Complete Implementation** (1 test):
   - Extract and build real GenServer implementation

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.BehaviourBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
  alias ElixirOntologies.Extractors.Behaviour
  alias ElixirOntologies.NS.Structure

  describe "build_behaviour/2 basic behaviour" do
    test "builds behaviour with one required callback" do
      behaviour_info = %Behaviour{
        callbacks: [
          %{
            name: :init,
            arity: 1,
            spec: nil,
            return_type: nil,
            parameters: [],
            is_optional: false,
            type: :callback,
            doc: nil,
            location: nil
          }
        ],
        macrocallbacks: [],
        optional_callbacks: [],
        doc: nil,
        metadata: %{callback_count: 1, macrocallback_count: 0}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyBehaviour")

      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Verify behaviour IRI
      assert to_string(behaviour_iri) == "https://example.org/code#MyBehaviour"

      # Verify behaviour type
      assert {behaviour_iri, RDF.type(), Structure.Behaviour} in triples

      # Verify callback exists
      callback_iri = ~I<https://example.org/code#MyBehaviour/init/1>
      assert {behaviour_iri, Structure.definesCallback(), callback_iri} in triples

      # Verify callback type (RequiredCallback)
      assert {callback_iri, RDF.type(), Structure.RequiredCallback} in triples

      # Verify callback properties
      assert Enum.any?(triples, fn
               {^callback_iri, pred, obj} ->
                 pred == Structure.callbackName() and RDF.Literal.value(obj) == "init"

               _ ->
                 false
             end)

      assert Enum.any?(triples, fn
               {^callback_iri, pred, obj} ->
                 pred == Structure.callbackArity() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)
    end

    test "builds behaviour with optional callback" do
      behaviour_info = %Behaviour{
        callbacks: [
          %{
            name: :terminate,
            arity: 2,
            is_optional: true,
            type: :callback,
            spec: nil,
            return_type: nil,
            parameters: [],
            doc: nil,
            location: nil
          }
        ],
        macrocallbacks: [],
        optional_callbacks: [{:terminate, 2}],
        doc: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "GenServer")

      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Verify callback type (OptionalCallback)
      callback_iri = ~I<https://example.org/code#GenServer/terminate/2>
      assert {callback_iri, RDF.type(), Structure.OptionalCallback} in triples
    end

    test "builds behaviour with macro callback" do
      behaviour_info = %Behaviour{
        callbacks: [],
        macrocallbacks: [
          %{
            name: :before_compile,
            arity: 1,
            is_optional: false,
            type: :macrocallback,
            spec: nil,
            return_type: nil,
            parameters: [],
            doc: nil,
            location: nil
          }
        ],
        optional_callbacks: [],
        doc: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyBehaviour")

      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Verify macrocallback type
      callback_iri = ~I<https://example.org/code#MyBehaviour/before_compile/1>
      assert {callback_iri, RDF.type(), Structure.MacroCallback} in triples
    end
  end

  describe "build_implementation/2 basic implementation" do
    test "builds simple GenServer implementation" do
      impl_info = %{
        behaviours: [
          %{
            behaviour: GenServer,
            behaviour_alias: {:__aliases__, [], [:GenServer]},
            location: nil
          }
        ],
        overridables: [],
        functions: [{:init, 1}, {:handle_call, 3}]
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyServer")

      {module_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)

      # Verify module IRI
      assert to_string(module_iri) == "https://example.org/code#MyServer"

      # Verify implementsBehaviour
      behaviour_iri = ~I<https://example.org/code#GenServer>
      assert {module_iri, Structure.implementsBehaviour(), behaviour_iri} in triples

      # Verify callback implementations
      init_iri = ~I<https://example.org/code#MyServer/init/1>
      callback_iri = ~I<https://example.org/code#GenServer/init/1>
      assert {init_iri, Structure.implementsCallback(), callback_iri} in triples

      handle_call_iri = ~I<https://example.org/code#MyServer/handle_call/3>
      handle_call_callback_iri = ~I<https://example.org/code#GenServer/handle_call/3>
      assert {handle_call_iri, Structure.implementsCallback(), handle_call_callback_iri} in triples
    end

    test "builds multiple behaviour implementation" do
      impl_info = %{
        behaviours: [
          %{behaviour: GenServer, behaviour_alias: nil, location: nil},
          %{behaviour: Plug, behaviour_alias: nil, location: nil}
        ],
        overridables: [],
        functions: [{:init, 1}]
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyModule")

      {module_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)

      # Verify both behaviours implemented
      genserver_iri = ~I<https://example.org/code#GenServer>
      plug_iri = ~I<https://example.org/code#Plug>

      assert {module_iri, Structure.implementsBehaviour(), genserver_iri} in triples
      assert {module_iri, Structure.implementsBehaviour(), plug_iri} in triples
    end

    test "builds implementation with no behaviours" do
      impl_info = %{
        behaviours: [],
        overridables: [],
        functions: [{:foo, 0}]
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyModule")

      {_module_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)

      # No behaviour triples generated
      assert triples == []
    end
  end

  describe "build_behaviour/2 documentation" do
    test "includes behaviour documentation" do
      behaviour_info = %Behaviour{
        callbacks: [],
        macrocallbacks: [],
        optional_callbacks: [],
        doc: "A custom behaviour for handling events",
        metadata: %{has_doc: true}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "EventHandler")

      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Verify docstring
      assert Enum.any?(triples, fn
               {^behaviour_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "A custom behaviour for handling events"

               _ ->
                 false
             end)
    end
  end

  describe "integration tests" do
    test "extract and build real behaviour" do
      code = """
      defmodule MyBehaviour do
        @doc "Initialize the handler"
        @callback init(args :: term()) :: {:ok, state :: term()}

        @callback handle(event :: term(), state :: term()) :: {:ok, term()}

        @optional_callbacks [handle: 2]
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract
      behaviour_info = Behaviour.extract_from_body(body)

      # Build
      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyBehaviour")
      {behaviour_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, context)

      # Verify complete graph
      assert length(triples) >= 6

      # Verify both callbacks exist
      init_iri = ~I<https://example.org/code#MyBehaviour/init/1>
      handle_iri = ~I<https://example.org/code#MyBehaviour/handle/2>

      assert {behaviour_iri, Structure.definesCallback(), init_iri} in triples
      assert {behaviour_iri, Structure.definesCallback(), handle_iri} in triples

      # Verify callback types
      assert {init_iri, RDF.type(), Structure.RequiredCallback} in triples
      assert {handle_iri, RDF.type(), Structure.OptionalCallback} in triples
    end
  end
end
```

### 5.3 Integration Tests

Test the complete flow from extractor to builder:

```elixir
test "integration: extract and build GenServer implementation" do
  code = """
  defmodule MyServer do
    use GenServer

    @impl true
    def init(args), do: {:ok, args}

    @impl true
    def handle_call(:ping, _from, state), do: {:reply, :pong, state}
  end
  """

  {:ok, ast} = Code.string_to_quoted(code)
  {:defmodule, _, [_, [do: body]]} = ast

  # Extract
  impl_info = Behaviour.extract_implementations(body)

  # Build
  context = Context.new(base_iri: "https://example.org/code#", module_name: "MyServer")
  {module_iri, triples} = BehaviourBuilder.build_implementation(impl_info, context)

  # Verify
  assert length(triples) >= 3

  # Verify GenServer behaviour
  genserver_iri = ~I<https://example.org/code#GenServer>
  assert {module_iri, Structure.implementsBehaviour(), genserver_iri} in triples
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `BehaviourBuilder` module exists with complete documentation
2. ✅ `build_behaviour/2` correctly transforms `Behaviour.t()` to RDF triples
3. ✅ `build_implementation/2` correctly transforms implementation results to RDF triples
4. ✅ Behaviour class is correctly assigned
5. ✅ Callback classes are correctly assigned (RequiredCallback, OptionalCallback, MacroCallback)
6. ✅ Callback datatype properties are generated (callbackName, callbackArity)
7. ✅ definesCallback relationships are created
8. ✅ implementsBehaviour relationships are created
9. ✅ implementsCallback relationships are created for known OTP callbacks
10. ✅ Optional callbacks are correctly typed as OptionalCallback
11. ✅ Macro callbacks are correctly typed as MacroCallback
12. ✅ Behaviour IRIs follow module pattern
13. ✅ Callback IRIs follow function pattern
14. ✅ Multiple behaviour implementations are handled correctly
15. ✅ Documentation is added when present
16. ✅ All functions have @spec typespecs
17. ✅ Test suite passes with 15+ comprehensive tests
18. ✅ 100% code coverage for BehaviourBuilder
19. ✅ Documentation includes clear usage examples
20. ✅ No regressions in existing tests

## 7. Risk Mitigation

### Risk 1: Module Name Not in Extractor
**Issue**: Behaviour extractor doesn't capture the module name.
**Mitigation**:
- Require `module_name` in context
- Document this requirement clearly
- Raise clear error if module_name missing
- Update Context struct to include module_name as required field

### Risk 2: Callback Implementation Matching Without Introspection
**Issue**: We don't know what callbacks a behaviour defines without loading it.
**Mitigation**:
- For V1, link only known OTP behaviour callbacks (GenServer, Supervisor, etc.)
- For unknown behaviours, skip implementsCallback links
- SHACL validation will catch missing implementations
- Document limitation and plan for V2 enhancement
- Consider adding callback registry or querying existing RDF graph

### Risk 3: Defoverridable Complexity
**Issue**: Defoverridable can reference entire behaviour modules.
**Mitigation**:
- For V1, handle only explicit keyword lists
- Skip module references in defoverridable
- Add TODO comment for future enhancement
- Document this limitation

### Risk 4: Missing Properties in Ontology
**Issue**: Some properties might not exist in current ontology.
**Mitigation**:
- Verify all properties exist before implementation:
  - callbackName ✅
  - callbackArity ✅
  - definesCallback ✅
  - implementsBehaviour ✅
  - implementsCallback ✅
- If missing, add to ontology or adjust builder
- Document any workarounds

## 8. Future Enhancements

### Phase 12.2.3 Dependencies
After this phase, we can implement:
- Struct builder (uses behaviours for validation)
- Complete OTP builder (GenServer, Supervisor use behaviours)
- Behaviour validation rules in SHACL

### Later Optimizations
- Callback implementation inference from RDF graph
- Support defoverridable module references
- Link @impl attribute metadata to callbacks
- Generate callback implementation completeness metrics

### Enhanced Features
- Validate callback signature matches (parameter types, return types)
- Track default implementations in behaviours
- Support behaviour composition patterns
- Generate behaviour dependency graphs
- Detect behaviour conflicts (multiple behaviours with same callback)

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Behaviour triple generation | 2 hours | Skeleton |
| Callback handling | 2 hours | Behaviour triples |
| Macro callback handling | 1 hour | Callback handling |
| Implementation triple generation | 2 hours | Skeleton |
| Callback implementation linkage | 2 hours | Implementation triples |
| Integration and polish | 1 hour | All above |
| Unit tests (15+ tests) | 3 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 2 hours | All above |
| **Total** | **18 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/behaviour.ex` - Behaviour extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/protocol_builder.ex` - Protocol builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/module_builder.ex` - Module builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Behaviour ontology definitions

### Related Phase Documents
- `/home/ducky/.claude/plans/parsed-nibbling-thimble.md` - Phase 12 master plan (section 12.2.2)
- `notes/features/phase-12-2-1-protocol-builder.md` - Protocol builder (similar pattern)
- `notes/features/phase-12-1-2-module-builder.md` - Module builder
- `notes/features/phase-12-1-3-function-builder.md` - Function builder

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Elixir Behaviours documentation: https://hexdocs.pm/elixir/behaviours.html
- Elixir Typespecs and behaviours guide: https://elixir-lang.org/getting-started/typespecs-and-behaviours.html
- GenServer documentation: https://hexdocs.pm/elixir/GenServer.html
