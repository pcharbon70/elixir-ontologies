# Phase 12.3.1: GenServer Builder Planning Document

## 1. Problem Statement

Phase 12.2 completed the Advanced Builders (Protocol, Behaviour, Struct, Type System), establishing comprehensive support for Elixir's polymorphism and type systems. Now we need to move into Phase 12.3: OTP Pattern RDF Builders, starting with the GenServer Builder.

**The Challenge**: The GenServer extractor (`ElixirOntologies.Extractors.OTP.GenServer`) produces rich structured data about GenServer implementations and their callbacks, but this data needs to be converted to RDF triples that conform to the `elixir-otp.ttl` ontology while correctly representing OTP GenServer patterns and semantics.

**Current State**:
- GenServer extractor exists and produces two operation modes:
  - `GenServer.t()` structs for GenServer detection (use vs @behaviour)
  - `GenServer.Callback.t()` structs for individual callbacks
- Behaviour Builder handles general behaviour implementations
- OTP ontology (`elixir-otp.ttl`) defines GenServer-specific classes
- Builder infrastructure exists but no GenServer-specific builder

**Why GenServers Are Important**:
GenServers are the foundation of Elixir/OTP applications, enabling:
- Stateful server processes with managed lifecycle
- Synchronous request/reply (handle_call/3)
- Asynchronous messages (handle_cast/2)
- Generic message handling (handle_info/2)
- State initialization and cleanup (init/1, terminate/2)
- Hot code upgrades (code_change/3)
- Continuation support (handle_continue/2)

Understanding GenServer patterns is critical for:
- Analyzing OTP application architecture
- Tracking state management patterns
- Building supervision tree visualizations
- Understanding process lifecycle and message flows
- Validating GenServer callback implementations

**The Gap**: We need to:
1. Generate IRIs for GenServer implementations (using module IRI pattern)
2. Create `rdf:type` triples for GenServerImplementation and GenServerCallback classes
3. Build GenServer-specific properties (detection method, use options)
4. Build callback type triples (InitCallback, HandleCallCallback, etc.)
5. Link callbacks to GenServer implementation (hasGenServerCallback)
6. Handle @impl annotations on callbacks
7. Track use options (restart strategy, shutdown timeout, etc.)
8. Support all 8 GenServer callbacks (init, handle_call, handle_cast, handle_info, handle_continue, terminate, code_change, format_status)
9. Link to general Behaviour infrastructure
10. Support multi-clause callbacks

## 2. Solution Overview

Create a **GenServer Builder** that transforms GenServer extractor results into RDF triples representing OTP GenServer patterns.

### 2.1 Core Functionality

The builder will provide two main functions:
- `build_genserver/3` - Transform GenServer detection into RDF
- `build_callback/3` - Transform individual GenServer callbacks into RDF

Both follow the established builder pattern:
```elixir
{genserver_iri, triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)
{callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)
```

### 2.2 Builder Pattern

**GenServer Implementation Building**:
```elixir
def build_genserver(genserver_info, module_iri, context) do
  # GenServer IRI is the module IRI (GenServer implementation IS a module)
  genserver_iri = module_iri

  # Build all triples
  triples =
    [
      # Core GenServer triples
      build_type_triple(genserver_iri, :genserver_implementation),
      build_implements_otp_behaviour_triple(genserver_iri),
      build_detection_method_triple(genserver_iri, genserver_info)
    ] ++
      build_use_options_triples(genserver_iri, genserver_info) ++
      build_location_triple(genserver_iri, genserver_info, context)

  {genserver_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**GenServer Callback Building**:
```elixir
def build_callback(callback_info, module_iri, context) do
  # Generate callback IRI (function pattern)
  callback_iri = generate_callback_iri(callback_info, module_iri, context)

  # Determine callback-specific class
  callback_class = determine_callback_class(callback_info.type)

  # Build all triples
  triples =
    [
      # Type triple (InitCallback, HandleCallCallback, etc.)
      build_type_triple(callback_iri, callback_class),
      # Also type as GenServerCallback
      build_type_triple(callback_iri, :genserver_callback),
      # Link to GenServer implementation
      build_has_callback_triple(module_iri, callback_iri),
      # Callback properties
      build_clause_count_triple(callback_iri, callback_info),
      build_has_impl_triple(callback_iri, callback_info)
    ] ++
      build_location_triple(callback_iri, callback_info, context)

  {callback_iri, List.flatten(triples) |> Enum.uniq()}
end
```

### 2.3 Integration Point

The GenServer Builder will be called from a higher-level orchestrator:

```elixir
# In FileAnalyzer or ModuleBuilder
if GenServerExtractor.genserver?(module_body) do
  # Extract GenServer information
  {:ok, genserver_info} = GenServerExtractor.extract(module_body)
  callbacks = GenServerExtractor.extract_callbacks(module_body)

  # Build GenServer implementation
  {_iri, genserver_triples} =
    GenServerBuilder.build_genserver(genserver_info, module_iri, context)

  # Build each callback
  callback_triples = Enum.flat_map(callbacks, fn callback ->
    {_iri, triples} = GenServerBuilder.build_callback(callback, module_iri, context)
    triples
  end)

  all_triples ++ genserver_triples ++ callback_triples
end
```

## 3. Technical Details

### 3.1 GenServer Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/otp/genserver.ex`:

**GenServer Detection Result**:
```elixir
%ElixirOntologies.Extractors.OTP.GenServer{
  # How GenServer was detected
  detection_method: :use | :behaviour,

  # Options from `use GenServer, opts` (nil if via @behaviour)
  use_options: keyword() | nil,
  # Example: [restart: :transient, shutdown: 5000]

  # Source location of detection point
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    otp_behaviour: :genserver,
    has_options: boolean()
  }
}
```

**GenServer Callback Result**:
```elixir
%ElixirOntologies.Extractors.OTP.GenServer.Callback{
  # Callback type
  type: :init | :handle_call | :handle_cast | :handle_info |
        :handle_continue | :terminate | :code_change | :format_status,

  # Function name (always matches type)
  name: atom(),

  # Function arity (fixed per callback type)
  arity: non_neg_integer(),

  # Number of function clauses
  clauses: non_neg_integer(),

  # Whether @impl annotation is present
  has_impl: boolean(),

  # Source location of first clause
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    clause_count: non_neg_integer()
  }
}
```

**Callback Specifications**:
```elixir
@genserver_callbacks [
  {:init, 1, :init},
  {:handle_call, 3, :handle_call},
  {:handle_cast, 2, :handle_cast},
  {:handle_info, 2, :handle_info},
  {:handle_continue, 2, :handle_continue},
  {:terminate, 2, :terminate},
  {:code_change, 3, :code_change},
  {:format_status, 1, :format_status}
]
```

**Key Points**:
- GenServer is detected via `use GenServer` or `@behaviour GenServer`
- Use options are captured only for `use` detection
- Callbacks are extracted with clause counts
- @impl annotations are tracked
- Callbacks always have fixed name/arity pairs
- Multiple clauses are counted per callback

### 3.2 IRI Generation Patterns

**GenServer Implementation IRI** (same as module IRI):
```elixir
# GenServer implementation uses module IRI pattern
module_name = "MyApp.MyServer"
IRI.for_module(context.base_iri, module_name)

# Examples:
MyApp.Counter -> "base#MyApp.Counter"
MyApp.UserServer -> "base#MyApp.UserServer"
```

**GenServer Callback IRIs** (use function pattern):
```elixir
# Callback IRI follows function pattern: module/name/arity
module_name = "MyApp.MyServer"
IRI.for_function(context.base_iri, module_name, callback.name, callback.arity)

# Examples:
MyApp.Counter.init/1 -> "base#MyApp.Counter/init/1"
MyApp.Counter.handle_call/3 -> "base#MyApp.Counter/handle_call/3"
MyApp.Counter.handle_cast/2 -> "base#MyApp.Counter/handle_cast/2"
```

**GenServer Behaviour IRI** (references the GenServer module):
```elixir
# GenServer behaviour itself (the Elixir.GenServer module)
IRI.for_module(context.base_iri, "GenServer")

# Example:
GenServer -> "base#GenServer"
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-otp.ttl`:

#### Classes

```turtle
:GenServer a owl:Class ;
    rdfs:label "GenServer"@en ;
    rdfs:comment "The generic server behaviour."@en ;
    rdfs:subClassOf :OTPBehaviour .

:GenServerImplementation a owl:Class ;
    rdfs:label "GenServer Implementation"@en ;
    rdfs:comment "A module that implements the GenServer behaviour."@en ;
    rdfs:subClassOf struct:BehaviourImplementation .

:GenServerCallback a owl:Class ;
    rdfs:label "GenServer Callback"@en ;
    rdfs:comment "A callback function in a GenServer implementation."@en ;
    rdfs:subClassOf struct:CallbackFunction .

:InitCallback a owl:Class ;
    rdfs:label "Init Callback"@en ;
    rdfs:comment "The init/1 callback initializing GenServer state."@en ;
    rdfs:subClassOf :GenServerCallback .

:HandleCallCallback a owl:Class ;
    rdfs:label "Handle Call Callback"@en ;
    rdfs:comment "The handle_call/3 callback for synchronous requests."@en ;
    rdfs:subClassOf :GenServerCallback .

:HandleCastCallback a owl:Class ;
    rdfs:label "Handle Cast Callback"@en ;
    rdfs:comment "The handle_cast/2 callback for asynchronous messages."@en ;
    rdfs:subClassOf :GenServerCallback .

:HandleInfoCallback a owl:Class ;
    rdfs:label "Handle Info Callback"@en ;
    rdfs:comment "The handle_info/2 callback for all other messages."@en ;
    rdfs:subClassOf :GenServerCallback .

:HandleContinueCallback a owl:Class ;
    rdfs:label "Handle Continue Callback"@en ;
    rdfs:comment "The handle_continue/2 callback for deferred work."@en ;
    rdfs:subClassOf :GenServerCallback .

:TerminateCallback a owl:Class ;
    rdfs:label "Terminate Callback"@en ;
    rdfs:comment "The terminate/2 callback for cleanup before process exits."@en ;
    rdfs:subClassOf :GenServerCallback .

:CodeChangeCallback a owl:Class ;
    rdfs:label "Code Change Callback"@en ;
    rdfs:comment "The code_change/3 callback for hot code upgrades."@en ;
    rdfs:subClassOf :GenServerCallback .
```

**Class Selection Logic**:
```elixir
# For GenServer implementation
defp determine_genserver_class(_genserver_info), do: OTP.GenServerImplementation

# For callbacks - map type to specific class
defp determine_callback_class(callback_type) do
  case callback_type do
    :init -> OTP.InitCallback
    :handle_call -> OTP.HandleCallCallback
    :handle_cast -> OTP.HandleCastCallback
    :handle_info -> OTP.HandleInfoCallback
    :handle_continue -> OTP.HandleContinueCallback
    :terminate -> OTP.TerminateCallback
    :code_change -> OTP.CodeChangeCallback
    :format_status -> OTP.GenServerCallback  # No specific class for format_status
  end
end
```

#### Object Properties

```turtle
# Module -> OTP Behaviour relationship
:implementsOTPBehaviour a owl:ObjectProperty ;
    rdfs:label "implements OTP behaviour"@en ;
    rdfs:domain struct:Module ;
    rdfs:range :OTPBehaviour .

# GenServer Implementation -> Callback relationship
:hasGenServerCallback a owl:ObjectProperty ;
    rdfs:label "has GenServer callback"@en ;
    rdfs:domain :GenServerImplementation ;
    rdfs:range :GenServerCallback .
```

#### Data Properties

There are no GenServer-specific data properties in the current ontology. We'll use:
- From `structure.ttl`: `functionName`, `arity`, `docstring`
- From `core.ttl`: `hasSourceLocation`
- Custom properties for GenServer-specific metadata (if needed)

### 3.4 Triple Generation Examples

**Simple GenServer (via use)**:
```turtle
<base#MyApp.Counter> a otp:GenServerImplementation ;
    struct:moduleName "MyApp.Counter"^^xsd:string ;
    struct:implementsBehaviour <base#GenServer> ;
    otp:implementsOTPBehaviour <base#GenServer> ;
    core:hasSourceLocation <base#file/lib/counter.ex/L1-50> .

<base#MyApp.Counter/init/1> a otp:InitCallback, otp:GenServerCallback ;
    struct:functionName "init"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Counter> ;
    core:hasSourceLocation <base#file/lib/counter.ex/L5-7> .

<base#MyApp.Counter> otp:hasGenServerCallback <base#MyApp.Counter/init/1> .

<base#MyApp.Counter/handle_call/3> a otp:HandleCallCallback, otp:GenServerCallback ;
    struct:functionName "handle_call"^^xsd:string ;
    struct:arity "3"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Counter> ;
    core:hasSourceLocation <base#file/lib/counter.ex/L9-15> .

<base#MyApp.Counter> otp:hasGenServerCallback <base#MyApp.Counter/handle_call/3> .
```

**GenServer via @behaviour**:
```turtle
<base#MyApp.CustomServer> a otp:GenServerImplementation ;
    struct:moduleName "MyApp.CustomServer"^^xsd:string ;
    struct:implementsBehaviour <base#GenServer> ;
    otp:implementsOTPBehaviour <base#GenServer> .
```

**GenServer Callback with @impl**:
```turtle
<base#MyApp.Server/handle_cast/2> a otp:HandleCastCallback, otp:GenServerCallback ;
    struct:functionName "handle_cast"^^xsd:string ;
    struct:arity "2"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Server> .

# @impl annotation could be tracked via metadata
# For V1, we just note its presence in has_impl field
```

**GenServer Callback with Multiple Clauses**:
```turtle
<base#MyApp.Server/handle_call/3> a otp:HandleCallCallback, otp:GenServerCallback ;
    struct:functionName "handle_call"^^xsd:string ;
    struct:arity "3"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Server> .

# The callback itself represents all clauses
# Individual clauses would be handled by ClauseBuilder if needed
# Clause count: 3 (stored in callback metadata)
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple for GenServer implementation
Helpers.type_triple(genserver_iri, OTP.GenServerImplementation)
#=> {genserver_iri, RDF.type(), ~I<https://w3id.org/elixir-code/otp#GenServerImplementation>}

# Type triple for callback
Helpers.type_triple(callback_iri, OTP.InitCallback)
Helpers.type_triple(callback_iri, OTP.HandleCallCallback)
Helpers.type_triple(callback_iri, OTP.GenServerCallback)

# Object property - implements behaviour
Helpers.object_property(genserver_iri, Structure.implementsBehaviour(), genserver_behaviour_iri)
#=> {genserver_iri, Structure.implementsBehaviour(), <base#GenServer>}

Helpers.object_property(genserver_iri, OTP.implementsOTPBehaviour(), genserver_behaviour_iri)
#=> {genserver_iri, OTP.implementsOTPBehaviour(), <base#GenServer>}

# Object property - has callback
Helpers.object_property(genserver_iri, OTP.hasGenServerCallback(), callback_iri)
#=> {genserver_iri, OTP.hasGenServerCallback(), callback_iri}

# Datatype properties (reuse from structure)
Helpers.datatype_property(callback_iri, Structure.functionName(), "init", RDF.XSD.String)
Helpers.datatype_property(callback_iri, Structure.arity(), 1, RDF.XSD.NonNegativeInteger)
```

### 3.6 Relationship to Behaviour Builder

The GenServer Builder complements the Behaviour Builder:

**Behaviour Builder** handles:
- Generic behaviour implementations (@behaviour declarations)
- Callback definitions in behaviour modules
- implementsBehaviour relationships
- implementsCallback relationships (for known OTP behaviours)

**GenServer Builder** handles:
- GenServer-specific implementation details
- GenServer callback typing (InitCallback, HandleCallCallback, etc.)
- Detection method tracking (use vs @behaviour)
- Use options metadata
- hasGenServerCallback relationships
- OTP-specific semantics

**Integration**:
```elixir
# Both builders may generate triples for the same module
module_triples = ModuleBuilder.build(module_info, context)
behaviour_triples = BehaviourBuilder.build_implementation(impl_info, module_iri, context)
genserver_triples = GenServerBuilder.build_genserver(genserver_info, module_iri, context)

# Combine all triples (deduplicated)
all_triples =
  (module_triples ++ behaviour_triples ++ genserver_triples)
  |> List.flatten()
  |> Enum.uniq()
```

### 3.7 Handling Edge Cases

#### Detection Method Variants

The extractor tracks both `use GenServer` and `@behaviour GenServer`:

```elixir
defp build_detection_method_metadata(genserver_info) do
  # Store detection method in triple metadata
  # Could use custom property or RDF-star annotation
  # For V1, just track in implementation metadata
  case genserver_info.detection_method do
    :use -> "via use GenServer"
    :behaviour -> "via @behaviour GenServer"
  end
end
```

#### Use Options

When GenServer is used with options, capture them:

```elixir
# use GenServer, restart: :transient, shutdown: 5000
defp build_use_options_triples(genserver_iri, genserver_info) do
  case genserver_info.use_options do
    nil -> []
    [] -> []
    opts ->
      # Could store as child spec properties
      # For V1, skip detailed use options
      # These would be captured by Supervisor builder
      []
  end
end
```

#### Callback Clause Counts

Callbacks can have multiple clauses (pattern matching):

```elixir
# Track clause count in metadata
defp build_clause_count_triple(callback_iri, callback_info) do
  # Could add as custom property
  # For V1, this is in callback metadata, not as triple
  # Individual clauses would be built by ClauseBuilder if detailed
  []
end
```

#### @impl Annotations

Track whether @impl is present:

```elixir
defp build_has_impl_triple(callback_iri, callback_info) do
  # Could add as boolean property
  # For V1, track in metadata only
  # @impl presence: callback_info.has_impl
  []
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create GenServer Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/genserver_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build_genserver/3` and `build_callback/3` function signatures
3. Add helper functions for IRI generation
4. Import necessary namespaces (Helpers, IRI, Structure, Core, OTP)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.GenServerBuilder do
  @moduledoc """
  Builds RDF triples for GenServer implementations and callbacks.

  This module transforms GenServer extractor results into RDF triples
  following the elixir-otp.ttl ontology. It handles:

  - GenServer implementations (use GenServer or @behaviour GenServer)
  - GenServer callback functions (init/1, handle_call/3, etc.)
  - Callback type classification
  - Detection method tracking
  - Use options metadata
  - Callback clause counts
  - @impl annotations

  ## Usage

      alias ElixirOntologies.Builders.{GenServerBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor

      # Extract GenServer information
      {:ok, genserver_info} = GenServerExtractor.extract(module_body)
      callbacks = GenServerExtractor.extract_callbacks(module_body)

      # Build GenServer implementation
      module_iri = IRI.for_module(context.base_iri, "MyApp.MyServer")
      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Build callbacks
      callback_triples = Enum.flat_map(callbacks, fn callback ->
        {_iri, triples} = GenServerBuilder.build_callback(callback, module_iri, context)
        triples
      end)

  ## GenServer vs Behaviour Builder

  **GenServer Builder** (this module):
  - GenServer-specific implementation details
  - Callback type classification (InitCallback, HandleCallCallback, etc.)
  - OTP-specific relationships (implementsOTPBehaviour, hasGenServerCallback)

  **Behaviour Builder**:
  - Generic behaviour implementation relationships
  - General callback definitions
  - implementsBehaviour, implementsCallback relationships

  Both builders can be used together for complete GenServer RDF representation.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
  alias NS.{Structure, Core, OTP}

  # ===========================================================================
  # Public API - GenServer Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a GenServer implementation.

  Takes a GenServer extraction result and builder context, returns the
  GenServer IRI and a list of RDF triples.

  ## Parameters

  - `genserver_info` - GenServer extraction result from `GenServerExtractor.extract/1`
  - `module_iri` - The IRI of the implementing module
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{genserver_iri, triples}` where:
  - `genserver_iri` - The IRI of the GenServer (same as module_iri)
  - `triples` - List of RDF triples describing the GenServer implementation

  ## Examples

      iex> alias ElixirOntologies.Builders.{GenServerBuilder, Context}
      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> genserver_info = %GenServerExtractor{
      ...>   detection_method: :use,
      ...>   use_options: [],
      ...>   location: nil,
      ...>   metadata: %{otp_behaviour: :genserver}
      ...> }
      iex> module_iri = ~I<https://example.org/code#MyServer>
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {genserver_iri, _triples} = GenServerBuilder.build_genserver(genserver_info, module_iri, context)
      iex> genserver_iri == module_iri
      true
  """
  @spec build_genserver(GenServerExtractor.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_genserver(genserver_info, module_iri, context)

  # ===========================================================================
  # Public API - GenServer Callback Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a GenServer callback.

  Takes a callback extraction result and builder context, returns the
  callback IRI and a list of RDF triples.

  ## Parameters

  - `callback_info` - Callback extraction result from `GenServerExtractor.extract_callbacks/1`
  - `module_iri` - The IRI of the GenServer module
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{callback_iri, triples}` where:
  - `callback_iri` - The IRI of the callback function
  - `triples` - List of RDF triples describing the callback

  ## Examples

      iex> alias ElixirOntologies.Builders.{GenServerBuilder, Context}
      iex> alias ElixirOntologies.Extractors.OTP.GenServer.Callback
      iex> callback_info = %Callback{
      ...>   type: :init,
      ...>   name: :init,
      ...>   arity: 1,
      ...>   clauses: 1,
      ...>   has_impl: false,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = ~I<https://example.org/code#MyServer>
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {callback_iri, _triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)
      iex> to_string(callback_iri)
      "https://example.org/code#MyServer/init/1"
  """
  @spec build_callback(GenServerExtractor.Callback.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_callback(callback_info, module_iri, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp generate_callback_iri(callback_info, module_iri, context)
  defp determine_callback_class(callback_type)
  defp extract_module_name_from_iri(module_iri)
  # ... etc
end
```

### 4.2 Step 2: Implement GenServer Implementation Triple Generation (2 hours)

Implement functions for GenServer implementation triples:

1. **IRI Generation**:
```elixir
# GenServer IRI is the module IRI
def build_genserver(genserver_info, module_iri, context) do
  genserver_iri = module_iri
  # ...
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(genserver_iri, :genserver_implementation) do
  Helpers.type_triple(genserver_iri, OTP.GenServerImplementation)
end
```

3. **Implements OTP Behaviour**:
```elixir
defp build_implements_otp_behaviour_triple(genserver_iri, context) do
  # Reference the GenServer behaviour
  genserver_behaviour_iri = IRI.for_module(context.base_iri, "GenServer")

  [
    # OTP-specific relationship
    Helpers.object_property(genserver_iri, OTP.implementsOTPBehaviour(),
                           genserver_behaviour_iri),
    # Also general behaviour relationship (compatibility)
    Helpers.object_property(genserver_iri, Structure.implementsBehaviour(),
                           genserver_behaviour_iri)
  ]
end
```

4. **Location Triple**:
```elixir
defp build_location_triple(genserver_iri, genserver_info, context) do
  case {genserver_info.location, context.file_path} do
    {nil, _} -> []
    {_, nil} -> []
    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)
      [Helpers.object_property(genserver_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.3 Step 3: Implement Callback Triple Generation (3 hours)

Generate triples for GenServer callbacks:

```elixir
def build_callback(callback_info, module_iri, context) do
  # Generate callback IRI (function pattern)
  module_name = extract_module_name_from_iri(module_iri)
  callback_iri = IRI.for_function(context.base_iri, module_name,
                                   callback_info.name, callback_info.arity)

  # Determine specific callback class
  callback_class = determine_callback_class(callback_info.type)

  # Build all triples
  triples =
    [
      # Type as specific callback (InitCallback, HandleCallCallback, etc.)
      Helpers.type_triple(callback_iri, callback_class),
      # Also type as GenServerCallback
      Helpers.type_triple(callback_iri, OTP.GenServerCallback),
      # Function name and arity (reuse structure properties)
      Helpers.datatype_property(callback_iri, Structure.functionName(),
                                Atom.to_string(callback_info.name), RDF.XSD.String),
      Helpers.datatype_property(callback_iri, Structure.arity(),
                                callback_info.arity, RDF.XSD.NonNegativeInteger),
      # Link to module (belongsTo)
      Helpers.object_property(callback_iri, Structure.belongsTo(), module_iri),
      # Link from GenServer to callback
      Helpers.object_property(module_iri, OTP.hasGenServerCallback(), callback_iri)
    ] ++
      build_location_triple(callback_iri, callback_info, context)

  {callback_iri, List.flatten(triples) |> Enum.uniq()}
end

defp determine_callback_class(callback_type) do
  case callback_type do
    :init -> OTP.InitCallback
    :handle_call -> OTP.HandleCallCallback
    :handle_cast -> OTP.HandleCastCallback
    :handle_info -> OTP.HandleInfoCallback
    :handle_continue -> OTP.HandleContinueCallback
    :terminate -> OTP.TerminateCallback
    :code_change -> OTP.CodeChangeCallback
    :format_status -> OTP.GenServerCallback  # Generic for format_status
  end
end

# Extract module name from module IRI
defp extract_module_name_from_iri(module_iri) do
  # Module IRI format: base#ModuleName
  # Extract the fragment after #
  module_iri
  |> to_string()
  |> String.split("#")
  |> List.last()
  |> URI.decode()
end
```

### 4.4 Step 4: Integrate All Components (1 hour)

Complete the main functions:

```elixir
@spec build_genserver(GenServerExtractor.t(), RDF.IRI.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_genserver(genserver_info, module_iri, context) do
  # GenServer IRI is the module IRI
  genserver_iri = module_iri

  # Build all triples
  triples =
    [
      # Core GenServer implementation type
      build_type_triple(genserver_iri, :genserver_implementation)
    ] ++
      # Implements GenServer behaviour
      build_implements_otp_behaviour_triple(genserver_iri, context) ++
      # Source location
      build_location_triple(genserver_iri, genserver_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {genserver_iri, triples}
end

@spec build_callback(GenServerExtractor.Callback.t(), RDF.IRI.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_callback(callback_info, module_iri, context) do
  # (Already implemented in Step 3)
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/genserver_builder_test.exs`)

**Target**: 12+ comprehensive tests covering GenServer implementations and callbacks

#### Test Categories

**GenServer Implementation Tests** (4 tests):

1. **Basic GenServer Building** (2 tests):
   - GenServer via `use GenServer`
   - GenServer via `@behaviour GenServer`

2. **Implementation Details** (2 tests):
   - GenServer with use options
   - GenServer with source location

**Callback Tests** (6 tests):

3. **Callback Type Coverage** (6 tests):
   - InitCallback (init/1)
   - HandleCallCallback (handle_call/3)
   - HandleCastCallback (handle_cast/2)
   - HandleInfoCallback (handle_info/2)
   - TerminateCallback (terminate/2)
   - CodeChangeCallback (code_change/3)

**Integration Tests** (2+ tests):

4. **Complete GenServer** (2 tests):
   - Extract and build simple GenServer
   - Extract and build GenServer with multiple callbacks

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.GenServerBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.GenServerBuilder

  alias ElixirOntologies.Builders.{GenServerBuilder, Context}
  alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
  alias ElixirOntologies.Extractors.OTP.GenServer.Callback
  alias ElixirOntologies.NS.{OTP, Structure, Core}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "MyServer")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_genserver(opts \\ []) do
    %GenServerExtractor{
      detection_method: Keyword.get(opts, :detection_method, :use),
      use_options: Keyword.get(opts, :use_options, []),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{otp_behaviour: :genserver})
    }
  end

  defp build_test_callback(opts \\ []) do
    %Callback{
      type: Keyword.get(opts, :type, :init),
      name: Keyword.get(opts, :name, :init),
      arity: Keyword.get(opts, :arity, 1),
      clauses: Keyword.get(opts, :clauses, 1),
      has_impl: Keyword.get(opts, :has_impl, false),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # GenServer Implementation Building Tests
  # ===========================================================================

  describe "build_genserver/3 - basic building" do
    test "builds GenServer via use" do
      genserver_info = build_test_genserver(detection_method: :use)
      module_iri = build_test_module_iri()
      context = build_test_context()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify IRI (same as module)
      assert genserver_iri == module_iri

      # Verify type triple
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples

      # Verify implements GenServer
      genserver_behaviour_iri = RDF.iri("https://example.org/code#GenServer")
      assert {genserver_iri, OTP.implementsOTPBehaviour(), genserver_behaviour_iri} in triples
      assert {genserver_iri, Structure.implementsBehaviour(), genserver_behaviour_iri} in triples
    end

    test "builds GenServer via @behaviour" do
      genserver_info = build_test_genserver(detection_method: :behaviour, use_options: nil)
      module_iri = build_test_module_iri()
      context = build_test_context()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify type
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
    end

    test "builds GenServer with use options" do
      genserver_info = build_test_genserver(
        detection_method: :use,
        use_options: [restart: :transient, shutdown: 5000]
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {_genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify basic triples exist
      # Use options handling is for future enhancement
      assert length(triples) >= 3
    end

    test "builds GenServer with source location" do
      location = %{start_line: 1, end_line: 50}
      genserver_info = build_test_genserver(location: location)
      module_iri = build_test_module_iri()
      context = build_test_context(file_path: "lib/my_server.ex")

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify location triple exists
      assert Enum.any?(triples, fn
        {^genserver_iri, pred, _obj} -> pred == Core.hasSourceLocation()
        _ -> false
      end)
    end
  end

  # ===========================================================================
  # Callback Building Tests
  # ===========================================================================

  describe "build_callback/3 - callback types" do
    test "builds InitCallback" do
      callback_info = build_test_callback(type: :init, name: :init, arity: 1)
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify IRI
      assert to_string(callback_iri) == "https://example.org/code#MyServer/init/1"

      # Verify types
      assert {callback_iri, RDF.type(), OTP.InitCallback} in triples
      assert {callback_iri, RDF.type(), OTP.GenServerCallback} in triples

      # Verify properties
      assert Enum.any?(triples, fn
        {^callback_iri, pred, obj} ->
          pred == Structure.functionName() and RDF.Literal.value(obj) == "init"
        _ -> false
      end)

      assert Enum.any?(triples, fn
        {^callback_iri, pred, obj} ->
          pred == Structure.arity() and RDF.Literal.value(obj) == 1
        _ -> false
      end)

      # Verify hasGenServerCallback
      assert {module_iri, OTP.hasGenServerCallback(), callback_iri} in triples
    end

    test "builds HandleCallCallback" do
      callback_info = build_test_callback(
        type: :handle_call,
        name: :handle_call,
        arity: 3
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      assert {callback_iri, RDF.type(), OTP.HandleCallCallback} in triples
      assert {callback_iri, RDF.type(), OTP.GenServerCallback} in triples
    end

    test "builds HandleCastCallback" do
      callback_info = build_test_callback(
        type: :handle_cast,
        name: :handle_cast,
        arity: 2
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      assert {callback_iri, RDF.type(), OTP.HandleCastCallback} in triples
    end

    test "builds HandleInfoCallback" do
      callback_info = build_test_callback(
        type: :handle_info,
        name: :handle_info,
        arity: 2
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      assert {callback_iri, RDF.type(), OTP.HandleInfoCallback} in triples
    end

    test "builds TerminateCallback" do
      callback_info = build_test_callback(
        type: :terminate,
        name: :terminate,
        arity: 2
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      assert {callback_iri, RDF.type(), OTP.TerminateCallback} in triples
    end

    test "builds CodeChangeCallback" do
      callback_info = build_test_callback(
        type: :code_change,
        name: :code_change,
        arity: 3
      )
      module_iri = build_test_module_iri()
      context = build_test_context()

      {callback_iri, triples} =
        GenServerBuilder.build_callback(callback_info, module_iri, context)

      assert {callback_iri, RDF.type(), OTP.CodeChangeCallback} in triples
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration tests" do
    test "extract and build simple GenServer" do
      code = """
      defmodule MyServer do
        use GenServer

        def init(args), do: {:ok, args}
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract GenServer
      {:ok, genserver_info} = GenServerExtractor.extract(body)
      callbacks = GenServerExtractor.extract_callbacks(body)

      # Build
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_genserver_iri, genserver_triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      callback_triples = Enum.flat_map(callbacks, fn callback ->
        {_iri, triples} = GenServerBuilder.build_callback(callback, module_iri, context)
        triples
      end)

      # Verify
      all_triples = genserver_triples ++ callback_triples
      assert length(all_triples) >= 8

      # Verify GenServer implementation
      assert {module_iri, RDF.type(), OTP.GenServerImplementation} in all_triples

      # Verify init callback
      init_iri = RDF.iri("https://example.org/code#MyServer/init/1")
      assert {init_iri, RDF.type(), OTP.InitCallback} in all_triples
    end

    test "extract and build GenServer with multiple callbacks" do
      code = """
      defmodule Counter do
        use GenServer

        def init(count), do: {:ok, count}

        def handle_call(:get, _from, count) do
          {:reply, count, count}
        end

        def handle_cast(:increment, count) do
          {:noreply, count + 1}
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract
      {:ok, genserver_info} = GenServerExtractor.extract(body)
      callbacks = GenServerExtractor.extract_callbacks(body)

      # Build
      context = build_test_context()
      module_iri = RDF.iri("https://example.org/code#Counter")

      {_genserver_iri, genserver_triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      callback_triples = Enum.flat_map(callbacks, fn callback ->
        {_iri, triples} = GenServerBuilder.build_callback(callback, module_iri, context)
        triples
      end)

      # Verify all callback types
      all_triples = genserver_triples ++ callback_triples

      init_iri = RDF.iri("https://example.org/code#Counter/init/1")
      call_iri = RDF.iri("https://example.org/code#Counter/handle_call/3")
      cast_iri = RDF.iri("https://example.org/code#Counter/handle_cast/2")

      assert {init_iri, RDF.type(), OTP.InitCallback} in all_triples
      assert {call_iri, RDF.type(), OTP.HandleCallCallback} in all_triples
      assert {cast_iri, RDF.type(), OTP.HandleCastCallback} in all_triples
    end
  end
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `GenServerBuilder` module exists with complete documentation
2. ✅ `build_genserver/3` correctly transforms GenServer extraction to RDF triples
3. ✅ `build_callback/3` correctly transforms callback extraction to RDF triples
4. ✅ GenServerImplementation class is correctly assigned
5. ✅ All callback classes are correctly assigned (InitCallback, HandleCallCallback, etc.)
6. ✅ implementsOTPBehaviour relationships are created
7. ✅ hasGenServerCallback relationships are created
8. ✅ Callback function properties are generated (functionName, arity)
9. ✅ Source locations are included when available
10. ✅ GenServer IRI uses module IRI pattern
11. ✅ Callback IRIs use function IRI pattern
12. ✅ Both `use GenServer` and `@behaviour GenServer` are supported
13. ✅ All 8 GenServer callback types are supported
14. ✅ All functions have @spec typespecs
15. ✅ Test suite passes with 12+ comprehensive tests
16. ✅ 100% code coverage for GenServerBuilder
17. ✅ Documentation includes clear usage examples
18. ✅ No regressions in existing tests
19. ✅ Integration with Behaviour Builder is documented
20. ✅ Triple deduplication works correctly

## 7. Risk Mitigation

### Risk 1: Overlap with Behaviour Builder
**Issue**: Both builders may generate similar triples for GenServer implementations.
**Mitigation**:
- GenServer Builder focuses on OTP-specific semantics
- Behaviour Builder handles general behaviour relationships
- Use triple deduplication to handle overlap
- Document which builder generates which triples
- Both can be used together without conflicts

### Risk 2: Module Name Extraction from IRI
**Issue**: Need to extract module name from module IRI for callback generation.
**Mitigation**:
- Implement robust IRI parsing helper
- Handle URL-encoded characters correctly
- Test with various module name formats
- Fallback to passing module name explicitly if needed

### Risk 3: OTP Namespace Classes Missing
**Issue**: Some OTP classes might not exist in current ontology.
**Mitigation**:
- Verify all classes exist before implementation:
  - GenServerImplementation ✅
  - GenServerCallback ✅
  - InitCallback ✅
  - HandleCallCallback ✅
  - HandleCastCallback ✅
  - HandleInfoCallback ✅
  - TerminateCallback ✅
  - CodeChangeCallback ✅
- If missing, update ontology first
- Document any workarounds

### Risk 4: format_status and handle_continue Edge Cases
**Issue**: format_status/1 and handle_continue/2 are newer callbacks.
**Mitigation**:
- Support both in callback type mapping
- Use generic GenServerCallback for format_status if no specific class
- Test with code using these callbacks
- Document coverage

## 8. Future Enhancements

### Phase 12.3.2+ Dependencies
After this phase, we can implement:
- Supervisor builder (similar pattern)
- Agent builder (simpler OTP abstraction)
- Task builder (async/await patterns)
- Application builder (OTP application lifecycle)

### Later Optimizations
- Capture use options in detail (restart strategies, shutdown timeouts)
- Link @impl attributes to specific behaviour callbacks
- Track callback return type patterns
- Generate state transition diagrams
- Detect common GenServer anti-patterns

### Enhanced Features
- Validate callback signatures match GenServer specs
- Track state type evolution across callbacks
- Detect unused callbacks
- Generate callback coverage metrics
- Support custom GenServer wrappers
- Analyze message flow patterns

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| GenServer implementation triples | 2 hours | Skeleton |
| Callback triple generation | 3 hours | Skeleton |
| Integration and polish | 1 hour | All above |
| Unit tests (12+ tests) | 3 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 1 hour | All above |
| **Total** | **13 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/otp/genserver.ex` - GenServer extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/behaviour_builder.ex` - Behaviour builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-otp.ttl` - GenServer ontology definitions
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Structure ontology

### Related Phase Documents
- `notes/features/phase-12-2-2-behaviour-builder.md` - Behaviour builder (complementary)
- `notes/features/phase-12-2-1-protocol-builder.md` - Protocol builder (similar pattern)
- `notes/features/phase-12-1-3-function-builder.md` - Function builder
- `notes/features/phase-12-1-2-module-builder.md` - Module builder

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- GenServer documentation: https://hexdocs.pm/elixir/GenServer.html
- OTP Design Principles: https://www.erlang.org/doc/design_principles/gen_server_concepts.html
- Elixir behaviours guide: https://elixir-lang.org/getting-started/typespecs-and-behaviours.html
