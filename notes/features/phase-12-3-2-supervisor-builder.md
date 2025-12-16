# Phase 12.3.2: Supervisor Builder Planning Document

## 1. Problem Statement

Phase 12.3.1 completed the GenServer Builder, establishing comprehensive support for GenServer patterns and callbacks in RDF. Now we need to implement the Supervisor Builder to represent OTP supervision trees and fault tolerance patterns.

**The Challenge**: The Supervisor extractor (`ElixirOntologies.Extractors.OTP.Supervisor`) produces rich structured data about Supervisor implementations, supervision strategies, and child specifications. This data needs to be converted to RDF triples that conform to the `elixir-otp.ttl` ontology while correctly representing OTP supervision patterns and semantics.

**Current State**:
- Supervisor extractor exists at `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/otp/supervisor.ex`
- Extractor produces three main result types:
  - `Supervisor.t()` structs for Supervisor detection (use vs @behaviour)
  - `Supervisor.Strategy.t()` structs for supervision strategies
  - `Supervisor.ChildSpec.t()` structs for child specifications
- OTP ontology (`elixir-otp.ttl`) defines Supervisor-specific classes
- GenServer Builder provides OTP builder pattern reference
- Builder infrastructure exists but no Supervisor-specific builder

**Why Supervisors Are Important**:
Supervisors are the cornerstone of OTP's fault tolerance approach, enabling:
- Automatic process restart on failure
- Hierarchical supervision trees
- Different restart strategies (one_for_one, one_for_all, rest_for_one)
- Configurable restart intensity and period
- Child process lifecycle management
- Type-safe child specifications

Understanding Supervisor patterns is critical for:
- Analyzing OTP application architecture
- Building supervision tree visualizations
- Understanding fault tolerance strategies
- Validating restart policies
- Tracking process dependencies
- Documenting system resilience patterns

**The Gap**: We need to:
1. Generate IRIs for Supervisor implementations (using module IRI pattern)
2. Create `rdf:type` triples for Supervisor, DynamicSupervisor, and related classes
3. Build supervision strategy triples (OneForOne, OneForAll, RestForOne)
4. Build child specification triples with restart/shutdown policies
5. Link children to supervisors (hasChildSpec, hasChildren as ordered list)
6. Track max_restarts and max_seconds for restart intensity
7. Support both static Supervisor and DynamicSupervisor
8. Represent child types (worker vs supervisor)
9. Represent shutdown strategies (brutal_kill, infinity, timeout)
10. Link to general Behaviour infrastructure

## 2. Solution Overview

Create a **Supervisor Builder** that transforms Supervisor extractor results into RDF triples representing OTP supervision patterns.

### 2.1 Core Functionality

The builder will provide three main functions:
- `build_supervisor/3` - Transform Supervisor detection into RDF
- `build_strategy/3` - Transform supervision strategy into RDF
- `build_child_spec/3` - Transform child specifications into RDF

All follow the established builder pattern:
```elixir
{supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
{strategy_iri, triples} = SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)
{child_spec_iri, triples} = SupervisorBuilder.build_child_spec(child_info, supervisor_iri, context)
```

### 2.2 Builder Pattern

**Supervisor Implementation Building**:
```elixir
def build_supervisor(supervisor_info, module_iri, context) do
  # Supervisor IRI is the module IRI (Supervisor implementation IS a module)
  supervisor_iri = module_iri

  # Determine supervisor type (Supervisor vs DynamicSupervisor)
  supervisor_class = determine_supervisor_class(supervisor_info)

  # Build all triples
  triples =
    [
      # Core Supervisor triples
      build_type_triple(supervisor_iri, supervisor_class),
      build_implements_otp_behaviour_triple(supervisor_iri),
      build_detection_method_metadata(supervisor_iri, supervisor_info)
    ] ++
      build_location_triple(supervisor_iri, supervisor_info, context)

  {supervisor_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**Strategy Building**:
```elixir
def build_strategy(strategy_info, supervisor_iri, context) do
  # Strategy is represented by individual (OneForOne, OneForAll, RestForOne)
  strategy_iri = determine_strategy_individual(strategy_info.type)

  # Build all triples
  triples =
    [
      # Link supervisor to strategy
      build_has_strategy_triple(supervisor_iri, strategy_iri),
      # Restart intensity properties
      build_max_restarts_triple(supervisor_iri, strategy_info),
      build_max_seconds_triple(supervisor_iri, strategy_info)
    ] ++
      build_location_triple(strategy_iri, strategy_info, context)

  {strategy_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**Child Spec Building**:
```elixir
def build_child_spec(child_spec_info, supervisor_iri, context) do
  # Generate blank node for child spec
  child_spec_iri = RDF.bnode("child_spec_#{child_spec_info.id}")

  # Determine child type and restart/shutdown strategies
  child_type_iri = determine_child_type_individual(child_spec_info.type)
  restart_iri = determine_restart_strategy_individual(child_spec_info.restart)
  shutdown_iri = determine_shutdown_strategy(child_spec_info.shutdown)

  # Build all triples
  triples =
    [
      # Type triple
      build_type_triple(child_spec_iri, OTP.ChildSpec),
      # Link to supervisor
      build_has_child_spec_triple(supervisor_iri, child_spec_iri),
      # Child spec properties
      build_child_id_triple(child_spec_iri, child_spec_info),
      build_start_module_triple(child_spec_iri, child_spec_info),
      # Link to strategies
      build_has_child_type_triple(child_spec_iri, child_type_iri),
      build_has_restart_strategy_triple(child_spec_iri, restart_iri),
      build_has_shutdown_strategy_triple(child_spec_iri, shutdown_iri)
    ] ++
      build_location_triple(child_spec_iri, child_spec_info, context)

  {child_spec_iri, List.flatten(triples) |> Enum.uniq()}
end
```

### 2.3 Integration Point

The Supervisor Builder will be called from a higher-level orchestrator:

```elixir
# In FileAnalyzer or ModuleBuilder
if SupervisorExtractor.supervisor?(module_body) do
  # Extract Supervisor information
  {:ok, supervisor_info} = SupervisorExtractor.extract(module_body)

  # Build Supervisor implementation
  {_iri, supervisor_triples} =
    SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

  # Extract and build strategy
  strategy_triples = case SupervisorExtractor.extract_strategy(module_body) do
    {:ok, strategy} ->
      {_iri, triples} = SupervisorBuilder.build_strategy(strategy, module_iri, context)
      triples
    {:error, _} -> []
  end

  # Extract and build children
  {:ok, children} = SupervisorExtractor.extract_children(module_body)
  children_triples = Enum.flat_map(children, fn child ->
    {_iri, triples} = SupervisorBuilder.build_child_spec(child, module_iri, context)
    triples
  end)

  all_triples ++ supervisor_triples ++ strategy_triples ++ children_triples
end
```

## 3. Technical Details

### 3.1 Supervisor Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/otp/supervisor.ex`:

**Supervisor Detection Result**:
```elixir
%ElixirOntologies.Extractors.OTP.Supervisor{
  # Type of supervisor
  supervisor_type: :supervisor | :dynamic_supervisor,

  # How Supervisor was detected
  detection_method: :use | :behaviour,

  # Options from `use Supervisor, opts` (nil if via @behaviour)
  use_options: keyword() | nil,

  # Source location of detection point
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    otp_behaviour: :supervisor,
    is_dynamic: boolean(),
    has_options: boolean()
  }
}
```

**Strategy Result**:
```elixir
%ElixirOntologies.Extractors.OTP.Supervisor.Strategy{
  # Strategy type
  type: :one_for_one | :one_for_all | :rest_for_one,

  # Restart intensity limits
  max_restarts: non_neg_integer() | nil,  # default: 3
  max_seconds: non_neg_integer() | nil,   # default: 5

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    source: :supervisor_init | :dynamic_supervisor_init | :tuple_return,
    has_max_restarts: boolean(),
    has_max_seconds: boolean()
  }
}
```

**ChildSpec Result**:
```elixir
%ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec{
  # Child identifier (atom or term)
  id: atom() | term(),

  # Module implementing the child
  module: atom() | nil,

  # Restart policy
  restart: :permanent | :temporary | :transient,

  # Shutdown strategy
  shutdown: non_neg_integer() | :infinity | :brutal_kill | nil,

  # Child type
  type: :worker | :supervisor,

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    format: :tuple | :map | :module_only | :unknown,
    has_args: boolean(),
    has_start: boolean()
  }
}
```

**Key Points**:
- Supervisor is detected via `use Supervisor` or `@behaviour Supervisor`
- DynamicSupervisor is detected similarly
- Strategy extracted from init/1 callback
- Children extracted from init/1 callback's children list
- Default values: max_restarts=3, max_seconds=5, restart=:permanent, type=:worker

### 3.2 IRI Generation Patterns

**Supervisor Implementation IRI** (same as module IRI):
```elixir
# Supervisor implementation uses module IRI pattern
module_name = "MyApp.MySupervisor"
IRI.for_module(context.base_iri, module_name)

# Examples:
MyApp.Supervisor -> "base#MyApp.Supervisor"
MyApp.TreeSupervisor -> "base#MyApp.TreeSupervisor"
```

**Supervision Strategy IRI** (use named individuals from ontology):
```elixir
# Strategy IRIs are predefined in the ontology
OTP.OneForOne   # :OneForOne individual
OTP.OneForAll   # :OneForAll individual
OTP.RestForOne  # :RestForOne individual

# These are instances, not classes
```

**Child Spec IRI** (use blank nodes):
```elixir
# Child specs are anonymous nodes linked to supervisor
RDF.bnode("child_spec_#{child_id}")

# Examples:
_:child_spec_MyWorker
_:child_spec_ChildSup
```

**Restart Strategy IRI** (use named individuals):
```elixir
# Restart strategy IRIs are predefined
OTP.Permanent   # :Permanent individual
OTP.Temporary   # :Temporary individual
OTP.Transient   # :Transient individual
```

**Child Type IRI** (use named individuals):
```elixir
# Child type IRIs are predefined
OTP.WorkerType      # :WorkerType individual
OTP.SupervisorType  # :SupervisorType individual
```

**Shutdown Strategy IRI** (use individuals or blank nodes):
```elixir
# Predefined individuals
OTP.BrutalKill       # :BrutalKill individual
OTP.InfiniteShutdown # :InfiniteShutdown individual

# For timeout values, create blank node with shutdownTimeout property
# _:timeout_5000 with otp:shutdownTimeout "5000"^^xsd:nonNegativeInteger
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-otp.ttl`:

#### Classes

```turtle
# Supervisor types
:Supervisor a owl:Class ;
    rdfs:label "Supervisor"@en ;
    rdfs:comment "A process that monitors and manages child processes."@en ;
    rdfs:subClassOf :Process .

:DynamicSupervisor a owl:Class ;
    rdfs:label "Dynamic Supervisor"@en ;
    rdfs:comment "A supervisor for dynamically starting and stopping children."@en ;
    rdfs:subClassOf :Supervisor .

:SupervisorBehaviour a owl:Class ;
    rdfs:label "Supervisor Behaviour"@en ;
    rdfs:comment "The supervisor behaviour for building supervision trees."@en ;
    rdfs:subClassOf :OTPBehaviour .

# Supervision strategy
:SupervisionStrategy a owl:Class ;
    rdfs:label "Supervision Strategy"@en ;
    rdfs:comment "The restart strategy used by a supervisor."@en .

:OneForOne a :SupervisionStrategy ;
    rdfs:label "One For One"@en ;
    rdfs:comment "Only restart the failed child."@en .

:OneForAll a :SupervisionStrategy ;
    rdfs:label "One For All"@en ;
    rdfs:comment "Restart all children on any failure."@en .

:RestForOne a :SupervisionStrategy ;
    rdfs:label "Rest For One"@en ;
    rdfs:comment "Restart failed child and all started after it."@en .

# Child specification
:ChildSpec a owl:Class ;
    rdfs:label "Child Spec"@en ;
    rdfs:comment "Specification for a child process in a supervisor."@en .

# Restart strategies
:RestartStrategy a owl:Class ;
    rdfs:label "Restart Strategy"@en ;
    rdfs:comment "How a child should be restarted when it exits."@en .

:Permanent a :RestartStrategy ;
    rdfs:label "Permanent"@en ;
    rdfs:comment "Always restart the child when it terminates."@en .

:Temporary a :RestartStrategy ;
    rdfs:label "Temporary"@en ;
    rdfs:comment "Never restart the child when it terminates."@en .

:Transient a :RestartStrategy ;
    rdfs:label "Transient"@en ;
    rdfs:comment "Restart only if child terminates abnormally."@en .

# Child types
:ChildType a owl:Class ;
    rdfs:label "Child Type"@en ;
    rdfs:comment "The type of a supervised child process."@en .

:WorkerType a :ChildType ;
    rdfs:label "Worker Type"@en ;
    rdfs:comment "A worker process (not a supervisor)."@en .

:SupervisorType a :ChildType ;
    rdfs:label "Supervisor Type"@en ;
    rdfs:comment "A supervisor process."@en .

# Shutdown strategies
:ShutdownStrategy a owl:Class ;
    rdfs:label "Shutdown Strategy"@en ;
    rdfs:comment "How a child should be terminated during shutdown."@en .

:BrutalKill a :ShutdownStrategy ;
    rdfs:label "Brutal Kill"@en ;
    rdfs:comment "Kill the process immediately."@en .

:InfiniteShutdown a :ShutdownStrategy ;
    rdfs:label "Infinite Shutdown"@en ;
    rdfs:comment "Wait indefinitely for termination."@en .

:TimeoutShutdown a owl:Class ;
    rdfs:label "Timeout Shutdown"@en ;
    rdfs:comment "Wait for specified milliseconds before brutal kill."@en ;
    rdfs:subClassOf :ShutdownStrategy .
```

**Class Selection Logic**:
```elixir
# For Supervisor implementation
defp determine_supervisor_class(supervisor_info) do
  case supervisor_info.supervisor_type do
    :supervisor -> OTP.Supervisor
    :dynamic_supervisor -> OTP.DynamicSupervisor
  end
end

# For supervision strategy (use individuals, not classes)
defp determine_strategy_individual(strategy_type) do
  case strategy_type do
    :one_for_one -> OTP.OneForOne
    :one_for_all -> OTP.OneForAll
    :rest_for_one -> OTP.RestForOne
  end
end

# For restart strategy (use individuals)
defp determine_restart_strategy_individual(restart_type) do
  case restart_type do
    :permanent -> OTP.Permanent
    :temporary -> OTP.Temporary
    :transient -> OTP.Transient
  end
end

# For child type (use individuals)
defp determine_child_type_individual(child_type) do
  case child_type do
    :worker -> OTP.WorkerType
    :supervisor -> OTP.SupervisorType
  end
end
```

#### Object Properties

```turtle
# Supervision relationships
:supervisedBy a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "supervised by"@en ;
    rdfs:domain :Process ;
    rdfs:range :Supervisor .

:supervises a owl:ObjectProperty ;
    rdfs:label "supervises"@en ;
    owl:inverseOf :supervisedBy ;
    rdfs:domain :Supervisor ;
    rdfs:range :Process .

:hasStrategy a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has strategy"@en ;
    rdfs:domain :Supervisor ;
    rdfs:range :SupervisionStrategy .

:hasChildSpec a owl:ObjectProperty ;
    rdfs:label "has child spec"@en ;
    rdfs:domain :Supervisor ;
    rdfs:range :ChildSpec .

:hasChildren a owl:ObjectProperty ;
    rdfs:label "has children"@en ;
    rdfs:comment "Ordered list of child specs."@en ;
    rdfs:domain :Supervisor ;
    rdfs:range rdf:List .

:specForProcess a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "spec for process"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range :Process .

:hasRestartStrategy a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has restart strategy"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range :RestartStrategy .

:hasChildType a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has child type"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range :ChildType .

:hasShutdownStrategy a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has shutdown strategy"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range :ShutdownStrategy .

# OTP Behaviour relationships
:implementsOTPBehaviour a owl:ObjectProperty ;
    rdfs:label "implements OTP behaviour"@en ;
    rdfs:domain struct:Module ;
    rdfs:range :OTPBehaviour .
```

#### Data Properties

```turtle
# Supervisor properties
:maxRestarts a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "max restarts"@en ;
    rdfs:domain :Supervisor ;
    rdfs:range xsd:nonNegativeInteger .

:maxSeconds a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "max seconds"@en ;
    rdfs:domain :Supervisor ;
    rdfs:range xsd:positiveInteger .

# Child spec properties
:childId a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "child id"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range xsd:string .

:startModule a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "start module"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range xsd:string .

:startFunction a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "start function"@en ;
    rdfs:domain :ChildSpec ;
    rdfs:range xsd:string .

:shutdownTimeout a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "shutdown timeout"@en ;
    rdfs:domain :TimeoutShutdown ;
    rdfs:range xsd:nonNegativeInteger .
```

### 3.4 Triple Generation Examples

**Simple Supervisor (via use)**:
```turtle
<base#MyApp.AppSupervisor> a otp:Supervisor ;
    struct:moduleName "MyApp.AppSupervisor"^^xsd:string ;
    struct:implementsBehaviour <base#Supervisor> ;
    otp:implementsOTPBehaviour otp:SupervisorBehaviour ;
    otp:hasStrategy otp:OneForOne ;
    otp:maxRestarts "3"^^xsd:nonNegativeInteger ;
    otp:maxSeconds "5"^^xsd:positiveInteger ;
    core:hasSourceLocation <base#file/lib/app_supervisor.ex/L1-30> .

# Child spec as blank node
_:child_spec_worker1 a otp:ChildSpec ;
    otp:childId "MyApp.Worker1"^^xsd:string ;
    otp:startModule "MyApp.Worker1"^^xsd:string ;
    otp:hasRestartStrategy otp:Permanent ;
    otp:hasChildType otp:WorkerType ;
    otp:hasShutdownStrategy otp:InfiniteShutdown .

<base#MyApp.AppSupervisor> otp:hasChildSpec _:child_spec_worker1 .
```

**DynamicSupervisor**:
```turtle
<base#MyApp.DynSup> a otp:DynamicSupervisor ;
    struct:moduleName "MyApp.DynSup"^^xsd:string ;
    struct:implementsBehaviour <base#DynamicSupervisor> ;
    otp:implementsOTPBehaviour otp:SupervisorBehaviour ;
    otp:hasStrategy otp:OneForOne ;
    otp:maxRestarts "10"^^xsd:nonNegativeInteger ;
    otp:maxSeconds "60"^^xsd:positiveInteger .
```

**Supervisor with Multiple Children (ordered list)**:
```turtle
<base#MyApp.TreeSup> a otp:Supervisor ;
    otp:hasStrategy otp:OneForAll ;
    otp:hasChildren (
        _:child_spec_worker1
        _:child_spec_worker2
        _:child_spec_supervisor
    ) ;
    otp:hasChildSpec _:child_spec_worker1 ;
    otp:hasChildSpec _:child_spec_worker2 ;
    otp:hasChildSpec _:child_spec_supervisor .

_:child_spec_worker1 a otp:ChildSpec ;
    otp:childId "Worker1"^^xsd:string ;
    otp:startModule "MyApp.Worker1"^^xsd:string ;
    otp:hasRestartStrategy otp:Permanent ;
    otp:hasChildType otp:WorkerType .

_:child_spec_worker2 a otp:ChildSpec ;
    otp:childId "Worker2"^^xsd:string ;
    otp:startModule "MyApp.Worker2"^^xsd:string ;
    otp:hasRestartStrategy otp:Transient ;
    otp:hasChildType otp:WorkerType .

_:child_spec_supervisor a otp:ChildSpec ;
    otp:childId "SubSup"^^xsd:string ;
    otp:startModule "MyApp.SubSup"^^xsd:string ;
    otp:hasRestartStrategy otp:Permanent ;
    otp:hasChildType otp:SupervisorType .
```

**Child Spec with Timeout Shutdown**:
```turtle
_:child_spec_worker a otp:ChildSpec ;
    otp:childId "Worker"^^xsd:string ;
    otp:hasShutdownStrategy _:shutdown_5000 .

_:shutdown_5000 a otp:TimeoutShutdown ;
    otp:shutdownTimeout "5000"^^xsd:nonNegativeInteger .
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple for Supervisor implementation
Helpers.type_triple(supervisor_iri, OTP.Supervisor)
#=> {supervisor_iri, RDF.type(), ~I<https://w3id.org/elixir-code/otp#Supervisor>}

# Type triple for DynamicSupervisor
Helpers.type_triple(supervisor_iri, OTP.DynamicSupervisor)

# Type triple for ChildSpec
Helpers.type_triple(child_spec_iri, OTP.ChildSpec)

# Object property - implements behaviour
Helpers.object_property(supervisor_iri, Structure.implementsBehaviour(), supervisor_behaviour_iri)

Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour)

# Object property - has strategy
Helpers.object_property(supervisor_iri, OTP.hasStrategy(), OTP.OneForOne)

# Object property - has child spec
Helpers.object_property(supervisor_iri, OTP.hasChildSpec(), child_spec_iri)

# Datatype properties - restart intensity
Helpers.datatype_property(supervisor_iri, OTP.maxRestarts(), 3, RDF.XSD.NonNegativeInteger)
Helpers.datatype_property(supervisor_iri, OTP.maxSeconds(), 5, RDF.XSD.PositiveInteger)

# Datatype properties - child spec
Helpers.datatype_property(child_spec_iri, OTP.childId(), "MyWorker", RDF.XSD.String)
Helpers.datatype_property(child_spec_iri, OTP.startModule(), "MyApp.Worker", RDF.XSD.String)

# RDF list for ordered children
{list_head, list_triples} = Helpers.build_rdf_list([child1, child2, child3])
Helpers.object_property(supervisor_iri, OTP.hasChildren(), list_head)
```

### 3.6 Relationship to Behaviour Builder

The Supervisor Builder complements the Behaviour Builder:

**Behaviour Builder** handles:
- Generic behaviour implementations (@behaviour declarations)
- Callback definitions in behaviour modules
- implementsBehaviour relationships
- implementsCallback relationships

**Supervisor Builder** handles:
- Supervisor-specific implementation details
- Supervision strategy configuration
- Child specification details
- Restart intensity configuration
- OTP-specific relationships (hasStrategy, hasChildSpec)
- Ordered child lists
- Child lifecycle policies

**Integration**:
```elixir
# Both builders may generate triples for the same module
module_triples = ModuleBuilder.build(module_info, context)
behaviour_triples = BehaviourBuilder.build_implementation(impl_info, module_iri, context)
supervisor_triples = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

# Combine all triples (deduplicated)
all_triples =
  (module_triples ++ behaviour_triples ++ supervisor_triples)
  |> List.flatten()
  |> Enum.uniq()
```

### 3.7 Handling Edge Cases

#### Detection Method Variants

The extractor tracks both `use Supervisor` and `@behaviour Supervisor`:

```elixir
defp build_detection_method_metadata(supervisor_info) do
  # Store detection method in triple metadata
  # For V1, track in implementation metadata only
  case supervisor_info.detection_method do
    :use -> "via use Supervisor"
    :behaviour -> "via @behaviour Supervisor"
  end
end
```

#### Supervisor Type (Static vs Dynamic)

```elixir
defp determine_supervisor_class(supervisor_info) do
  case supervisor_info.supervisor_type do
    :supervisor -> OTP.Supervisor
    :dynamic_supervisor -> OTP.DynamicSupervisor
  end
end
```

#### Default Strategy Values

When strategy extraction fails or uses defaults:

```elixir
defp build_max_restarts_triple(supervisor_iri, strategy_info) do
  # Use explicit value or skip if nil (ontology has default)
  case strategy_info.max_restarts do
    nil -> []
    value -> [Helpers.datatype_property(supervisor_iri, OTP.maxRestarts(), value, RDF.XSD.NonNegativeInteger)]
  end
end
```

#### Shutdown Timeout Values

Handle different shutdown strategies:

```elixir
defp determine_shutdown_strategy(shutdown) do
  case shutdown do
    :brutal_kill -> OTP.BrutalKill
    :infinity -> OTP.InfiniteShutdown
    timeout when is_integer(timeout) ->
      # Create blank node for timeout shutdown
      shutdown_iri = RDF.bnode("shutdown_#{timeout}")
      # Return {shutdown_iri, extra_triples}
      {shutdown_iri, [
        Helpers.type_triple(shutdown_iri, OTP.TimeoutShutdown),
        Helpers.datatype_property(shutdown_iri, OTP.shutdownTimeout(), timeout, RDF.XSD.NonNegativeInteger)
      ]}
    nil -> nil
  end
end
```

#### Ordered Children List

Children must be represented as ordered RDF list:

```elixir
defp build_children_list_triple(supervisor_iri, children_iris) do
  case children_iris do
    [] -> []
    iris ->
      {list_head, list_triples} = Helpers.build_rdf_list(iris)
      [Helpers.object_property(supervisor_iri, OTP.hasChildren(), list_head)] ++ list_triples
  end
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Supervisor Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build_supervisor/3`, `build_strategy/3`, and `build_child_spec/3` signatures
3. Add helper functions for IRI generation and class determination
4. Import necessary namespaces (Helpers, IRI, Structure, Core, OTP)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.OTP.SupervisorBuilder do
  @moduledoc """
  Builds RDF triples for OTP Supervisor implementations.

  This module transforms Supervisor extractor results into RDF triples
  following the elixir-otp.ttl ontology. It handles:

  - Supervisor implementations (use Supervisor or @behaviour Supervisor)
  - DynamicSupervisor implementations
  - Supervision strategies (one_for_one, one_for_all, rest_for_one)
  - Child specifications with restart/shutdown policies
  - Restart intensity configuration (max_restarts, max_seconds)
  - Ordered child lists

  ## Usage

      alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor

      # Extract Supervisor information
      {:ok, supervisor_info} = SupervisorExtractor.extract(module_body)
      {:ok, strategy} = SupervisorExtractor.extract_strategy(module_body)
      {:ok, children} = SupervisorExtractor.extract_children(module_body)

      # Build Supervisor implementation
      module_iri = IRI.for_module(context.base_iri, "MyApp.Supervisor")
      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Build strategy
      {_iri, strategy_triples} =
        SupervisorBuilder.build_strategy(strategy, supervisor_iri, context)

      # Build children
      children_triples = Enum.flat_map(children, fn child ->
        {_iri, triples} = SupervisorBuilder.build_child_spec(child, supervisor_iri, context)
        triples
      end)

  ## Supervisor vs GenServer Builder

  **Supervisor Builder** (this module):
  - Supervisor-specific implementation details
  - Supervision strategy configuration
  - Child specifications and restart policies
  - OTP fault tolerance patterns

  **GenServer Builder**:
  - GenServer callback implementations
  - Message handling patterns
  - State management

  Both builders use similar OTP infrastructure (implementsOTPBehaviour, etc.).
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.Supervisor
  alias NS.{OTP, Core, Structure}

  # ===========================================================================
  # Public API - Supervisor Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a Supervisor implementation.
  """
  @spec build_supervisor(Supervisor.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_supervisor(supervisor_info, module_iri, context)

  # ===========================================================================
  # Public API - Strategy Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a supervision strategy.
  """
  @spec build_strategy(Supervisor.Strategy.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_strategy(strategy_info, supervisor_iri, context)

  # ===========================================================================
  # Public API - Child Spec Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a child specification.
  """
  @spec build_child_spec(Supervisor.ChildSpec.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t() | RDF.BlankNode.t(), [RDF.Triple.t()]}
  def build_child_spec(child_spec_info, supervisor_iri, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp determine_supervisor_class(supervisor_info)
  defp determine_strategy_individual(strategy_type)
  defp determine_restart_strategy_individual(restart_type)
  defp determine_child_type_individual(child_type)
  defp determine_shutdown_strategy(shutdown)
  # ... etc
end
```

### 4.2 Step 2: Implement Supervisor Implementation Triple Generation (2 hours)

Implement functions for Supervisor implementation triples:

1. **IRI Generation**:
```elixir
def build_supervisor(supervisor_info, module_iri, context) do
  # Supervisor IRI is the module IRI
  supervisor_iri = module_iri

  # Determine class (Supervisor vs DynamicSupervisor)
  supervisor_class = determine_supervisor_class(supervisor_info)
  # ...
end

defp determine_supervisor_class(supervisor_info) do
  case supervisor_info.supervisor_type do
    :supervisor -> OTP.Supervisor
    :dynamic_supervisor -> OTP.DynamicSupervisor
  end
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(supervisor_iri, supervisor_class) do
  Helpers.type_triple(supervisor_iri, supervisor_class)
end
```

3. **Implements OTP Behaviour**:
```elixir
defp build_implements_otp_behaviour_triple(supervisor_iri) do
  [
    # OTP-specific relationship
    Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour),
    # Also general behaviour relationship (compatibility)
    Helpers.object_property(supervisor_iri, Structure.implementsBehaviour(),
                           IRI.for_module(context.base_iri, "Supervisor"))
  ]
end
```

4. **Location Triple**:
```elixir
defp build_location_triple(subject_iri, location_info, context) do
  case {location_info.location, context.file_path} do
    {nil, _} -> []
    {_, nil} -> []
    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)
      [Helpers.object_property(subject_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.3 Step 3: Implement Strategy Triple Generation (2 hours)

Generate triples for supervision strategies:

```elixir
def build_strategy(strategy_info, supervisor_iri, context) do
  # Strategy is represented by individual (not a new IRI)
  strategy_iri = determine_strategy_individual(strategy_info.type)

  # Build all triples
  triples =
    [
      # Link supervisor to strategy
      Helpers.object_property(supervisor_iri, OTP.hasStrategy(), strategy_iri)
    ] ++
      build_max_restarts_triple(supervisor_iri, strategy_info) ++
      build_max_seconds_triple(supervisor_iri, strategy_info)

  {strategy_iri, List.flatten(triples) |> Enum.uniq()}
end

defp determine_strategy_individual(strategy_type) do
  case strategy_type do
    :one_for_one -> OTP.OneForOne
    :one_for_all -> OTP.OneForAll
    :rest_for_one -> OTP.RestForOne
  end
end

defp build_max_restarts_triple(supervisor_iri, strategy_info) do
  case strategy_info.max_restarts do
    nil -> []
    value ->
      [Helpers.datatype_property(supervisor_iri, OTP.maxRestarts(),
                                  value, RDF.XSD.NonNegativeInteger)]
  end
end

defp build_max_seconds_triple(supervisor_iri, strategy_info) do
  case strategy_info.max_seconds do
    nil -> []
    value ->
      [Helpers.datatype_property(supervisor_iri, OTP.maxSeconds(),
                                  value, RDF.XSD.PositiveInteger)]
  end
end
```

### 4.4 Step 4: Implement Child Spec Triple Generation (3 hours)

Generate triples for child specifications:

```elixir
def build_child_spec(child_spec_info, supervisor_iri, context) do
  # Generate blank node for child spec
  child_id_str = to_string(child_spec_info.id)
  child_spec_iri = RDF.bnode("child_spec_#{child_id_str}")

  # Determine individuals
  child_type_iri = determine_child_type_individual(child_spec_info.type)
  restart_iri = determine_restart_strategy_individual(child_spec_info.restart)

  # Handle shutdown (may create additional triples)
  {shutdown_iri, shutdown_triples} = determine_shutdown_strategy(child_spec_info.shutdown)

  # Build all triples
  triples =
    [
      # Type triple
      Helpers.type_triple(child_spec_iri, OTP.ChildSpec),
      # Link to supervisor
      Helpers.object_property(supervisor_iri, OTP.hasChildSpec(), child_spec_iri),
      # Child ID
      Helpers.datatype_property(child_spec_iri, OTP.childId(),
                               child_id_str, RDF.XSD.String),
      # Child type
      Helpers.object_property(child_spec_iri, OTP.hasChildType(), child_type_iri),
      # Restart strategy
      Helpers.object_property(child_spec_iri, OTP.hasRestartStrategy(), restart_iri)
    ] ++
      build_start_module_triple(child_spec_iri, child_spec_info) ++
      build_shutdown_strategy_triple(child_spec_iri, shutdown_iri) ++
      shutdown_triples ++
      build_location_triple(child_spec_iri, child_spec_info, context)

  {child_spec_iri, List.flatten(triples) |> Enum.uniq()}
end

defp determine_child_type_individual(child_type) do
  case child_type do
    :worker -> OTP.WorkerType
    :supervisor -> OTP.SupervisorType
  end
end

defp determine_restart_strategy_individual(restart_type) do
  case restart_type do
    :permanent -> OTP.Permanent
    :temporary -> OTP.Temporary
    :transient -> OTP.Transient
  end
end

defp determine_shutdown_strategy(shutdown) do
  case shutdown do
    :brutal_kill ->
      {OTP.BrutalKill, []}
    :infinity ->
      {OTP.InfiniteShutdown, []}
    timeout when is_integer(timeout) ->
      # Create blank node for timeout shutdown
      shutdown_iri = RDF.bnode("shutdown_#{timeout}")
      triples = [
        Helpers.type_triple(shutdown_iri, OTP.TimeoutShutdown),
        Helpers.datatype_property(shutdown_iri, OTP.shutdownTimeout(),
                                 timeout, RDF.XSD.NonNegativeInteger)
      ]
      {shutdown_iri, triples}
    nil ->
      {nil, []}
  end
end

defp build_start_module_triple(child_spec_iri, child_spec_info) do
  case child_spec_info.module do
    nil -> []
    module ->
      module_str = module |> to_string() |> String.replace_prefix("Elixir.", "")
      [Helpers.datatype_property(child_spec_iri, OTP.startModule(),
                                module_str, RDF.XSD.String)]
  end
end

defp build_shutdown_strategy_triple(child_spec_iri, nil), do: []
defp build_shutdown_strategy_triple(child_spec_iri, shutdown_iri) do
  [Helpers.object_property(child_spec_iri, OTP.hasShutdownStrategy(), shutdown_iri)]
end
```

### 4.5 Step 5: Implement Ordered Children List (1 hour)

Build ordered RDF list for children:

```elixir
@doc """
Builds RDF triples for all children with ordered list.

Takes a list of child specs, builds each one, and creates an ordered
RDF list linking them to the supervisor.
"""
@spec build_children(list(Supervisor.ChildSpec.t()), RDF.IRI.t(), Context.t()) ::
        {[RDF.IRI.t() | RDF.BlankNode.t()], [RDF.Triple.t()]}
def build_children(children, supervisor_iri, context) do
  # Build each child spec
  {child_iris, child_triples} =
    Enum.map_reduce(children, [], fn child, acc_triples ->
      {child_iri, triples} = build_child_spec(child, supervisor_iri, context)
      {child_iri, acc_triples ++ triples}
    end)

  # Build ordered list
  {list_head, list_triples} = Helpers.build_rdf_list(child_iris)

  # Add hasChildren property
  children_triples = case child_iris do
    [] -> []
    _ -> [Helpers.object_property(supervisor_iri, OTP.hasChildren(), list_head)]
  end

  all_triples = child_triples ++ list_triples ++ children_triples

  {child_iris, all_triples}
end
```

### 4.6 Step 6: Integrate All Components (1 hour)

Complete the main functions:

```elixir
@spec build_supervisor(Supervisor.t(), RDF.IRI.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_supervisor(supervisor_info, module_iri, context) do
  # Supervisor IRI is the module IRI
  supervisor_iri = module_iri

  # Determine supervisor class
  supervisor_class = determine_supervisor_class(supervisor_info)

  # Build all triples
  triples =
    [
      # Core Supervisor type
      build_type_triple(supervisor_iri, supervisor_class)
    ] ++
      # Implements Supervisor behaviour
      build_implements_otp_behaviour_triple(supervisor_iri) ++
      # Source location
      build_location_triple(supervisor_iri, supervisor_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {supervisor_iri, triples}
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/otp/supervisor_builder_test.exs`)

**Target**: 15+ comprehensive tests covering Supervisor implementations, strategies, and child specs

#### Test Categories

**Supervisor Implementation Tests** (4 tests):

1. **Basic Supervisor Building** (2 tests):
   - Supervisor via `use Supervisor`
   - DynamicSupervisor via `use DynamicSupervisor`

2. **Implementation Details** (2 tests):
   - Supervisor via `@behaviour Supervisor`
   - Supervisor with source location

**Strategy Tests** (3 tests):

3. **Strategy Types** (3 tests):
   - OneForOne strategy
   - OneForAll strategy
   - RestForOne strategy

4. **Restart Intensity** (1 test):
   - Strategy with max_restarts and max_seconds

**Child Spec Tests** (6 tests):

5. **Child Types** (2 tests):
   - Worker child spec
   - Supervisor child spec

6. **Restart Strategies** (3 tests):
   - Permanent restart
   - Temporary restart
   - Transient restart

7. **Shutdown Strategies** (3 tests):
   - Brutal kill shutdown
   - Infinity shutdown
   - Timeout shutdown

**Integration Tests** (2+ tests):

8. **Complete Supervisor** (2 tests):
   - Extract and build simple supervisor
   - Extract and build supervisor with multiple children

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.OTP.SupervisorBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.OTP.SupervisorBuilder

  alias ElixirOntologies.Builders.OTP.SupervisorBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.OTP.Supervisor
  alias ElixirOntologies.Extractors.OTP.Supervisor.{Strategy, ChildSpec}
  alias ElixirOntologies.NS.{OTP, Structure, Core}

  # Test helpers
  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "MySupervisor")
    RDF.iri("#{base_iri}#{module_name}")
  end

  describe "build_supervisor/3 - basic building" do
    test "builds Supervisor via use" do
      supervisor_info = %Supervisor{
        supervisor_type: :supervisor,
        detection_method: :use,
        use_options: [],
        location: nil,
        metadata: %{otp_behaviour: :supervisor}
      }
      module_iri = build_test_module_iri()
      context = build_test_context()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify IRI (same as module)
      assert supervisor_iri == module_iri

      # Verify type triple
      assert {supervisor_iri, RDF.type(), OTP.Supervisor} in triples

      # Verify implements behaviour
      assert {supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour} in triples
    end

    test "builds DynamicSupervisor" do
      supervisor_info = %Supervisor{
        supervisor_type: :dynamic_supervisor,
        detection_method: :use,
        use_options: [],
        location: nil,
        metadata: %{is_dynamic: true}
      }
      module_iri = build_test_module_iri()
      context = build_test_context()

      {supervisor_iri, triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      # Verify DynamicSupervisor type
      assert {supervisor_iri, RDF.type(), OTP.DynamicSupervisor} in triples
    end
  end

  describe "build_strategy/3" do
    test "builds OneForOne strategy" do
      strategy_info = %Strategy{
        type: :one_for_one,
        max_restarts: 3,
        max_seconds: 5,
        location: nil,
        metadata: %{}
      }
      supervisor_iri = build_test_module_iri()
      context = build_test_context()

      {strategy_iri, triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      # Verify strategy IRI is OneForOne individual
      assert strategy_iri == OTP.OneForOne

      # Verify hasStrategy relationship
      assert {supervisor_iri, OTP.hasStrategy(), OTP.OneForOne} in triples

      # Verify restart intensity
      assert Enum.any?(triples, fn
        {^supervisor_iri, pred, obj} ->
          pred == OTP.maxRestarts() and RDF.Literal.value(obj) == 3
        _ -> false
      end)

      assert Enum.any?(triples, fn
        {^supervisor_iri, pred, obj} ->
          pred == OTP.maxSeconds() and RDF.Literal.value(obj) == 5
        _ -> false
      end)
    end

    test "builds OneForAll strategy" do
      strategy_info = %Strategy{type: :one_for_all}
      supervisor_iri = build_test_module_iri()
      context = build_test_context()

      {strategy_iri, _triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      assert strategy_iri == OTP.OneForAll
    end

    test "builds RestForOne strategy" do
      strategy_info = %Strategy{type: :rest_for_one}
      supervisor_iri = build_test_module_iri()
      context = build_test_context()

      {strategy_iri, _triples} =
        SupervisorBuilder.build_strategy(strategy_info, supervisor_iri, context)

      assert strategy_iri == OTP.RestForOne
    end
  end

  describe "build_child_spec/3" do
    test "builds worker child spec" do
      child_spec_info = %ChildSpec{
        id: :worker1,
        module: MyApp.Worker1,
        restart: :permanent,
        shutdown: :infinity,
        type: :worker,
        location: nil,
        metadata: %{}
      }
      supervisor_iri = build_test_module_iri()
      context = build_test_context()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec_info, supervisor_iri, context)

      # Verify blank node
      assert RDF.BlankNode.blank_node?(child_spec_iri)

      # Verify type
      assert {child_spec_iri, RDF.type(), OTP.ChildSpec} in triples

      # Verify linked to supervisor
      assert {supervisor_iri, OTP.hasChildSpec(), child_spec_iri} in triples

      # Verify child ID
      assert Enum.any?(triples, fn
        {^child_spec_iri, pred, obj} ->
          pred == OTP.childId() and RDF.Literal.value(obj) == "worker1"
        _ -> false
      end)

      # Verify child type
      assert {child_spec_iri, OTP.hasChildType(), OTP.WorkerType} in triples

      # Verify restart strategy
      assert {child_spec_iri, OTP.hasRestartStrategy(), OTP.Permanent} in triples

      # Verify shutdown strategy
      assert {child_spec_iri, OTP.hasShutdownStrategy(), OTP.InfiniteShutdown} in triples
    end

    test "builds child spec with timeout shutdown" do
      child_spec_info = %ChildSpec{
        id: :worker,
        module: MyApp.Worker,
        restart: :transient,
        shutdown: 5000,
        type: :worker
      }
      supervisor_iri = build_test_module_iri()
      context = build_test_context()

      {child_spec_iri, triples} =
        SupervisorBuilder.build_child_spec(child_spec_info, supervisor_iri, context)

      # Find shutdown strategy IRI
      shutdown_iris = Enum.filter(triples, fn
        {^child_spec_iri, pred, _obj} -> pred == OTP.hasShutdownStrategy()
        _ -> false
      end)
      |> Enum.map(fn {_, _, obj} -> obj end)

      assert length(shutdown_iris) == 1
      shutdown_iri = hd(shutdown_iris)

      # Verify timeout shutdown type
      assert {shutdown_iri, RDF.type(), OTP.TimeoutShutdown} in triples

      # Verify timeout value
      assert Enum.any?(triples, fn
        {^shutdown_iri, pred, obj} ->
          pred == OTP.shutdownTimeout() and RDF.Literal.value(obj) == 5000
        _ -> false
      end)
    end
  end

  describe "integration tests" do
    test "extract and build simple supervisor" do
      code = """
      defmodule MySupervisor do
        use Supervisor

        def init(_) do
          children = [
            {MyWorker, []}
          ]
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract
      {:ok, supervisor_info} = Supervisor.extract(body)
      {:ok, strategy} = Supervisor.extract_strategy(body)
      {:ok, children} = Supervisor.extract_children(body)

      # Build
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_iri, supervisor_triples} =
        SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

      {_iri, strategy_triples} =
        SupervisorBuilder.build_strategy(strategy, module_iri, context)

      {_iris, children_triples} =
        SupervisorBuilder.build_children(children, module_iri, context)

      # Verify
      all_triples = supervisor_triples ++ strategy_triples ++ children_triples
      assert length(all_triples) >= 10

      # Verify Supervisor implementation
      assert {module_iri, RDF.type(), OTP.Supervisor} in all_triples

      # Verify strategy
      assert {module_iri, OTP.hasStrategy(), OTP.OneForOne} in all_triples

      # Verify at least one child spec
      assert Enum.any?(all_triples, fn
        {^module_iri, pred, _obj} -> pred == OTP.hasChildSpec()
        _ -> false
      end)
    end
  end
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `SupervisorBuilder` module exists with complete documentation
2. ✅ `build_supervisor/3` correctly transforms Supervisor extraction to RDF triples
3. ✅ `build_strategy/3` correctly transforms strategy extraction to RDF triples
4. ✅ `build_child_spec/3` correctly transforms child spec extraction to RDF triples
5. ✅ `build_children/3` creates ordered RDF lists for children
6. ✅ Supervisor and DynamicSupervisor classes are correctly assigned
7. ✅ All strategy individuals are correctly used (OneForOne, OneForAll, RestForOne)
8. ✅ All restart strategy individuals are correctly used (Permanent, Temporary, Transient)
9. ✅ All child type individuals are correctly used (WorkerType, SupervisorType)
10. ✅ Shutdown strategies are handled (BrutalKill, Infinity, TimeoutShutdown)
11. ✅ implementsOTPBehaviour relationships are created
12. ✅ hasStrategy relationships are created
13. ✅ hasChildSpec and hasChildren relationships are created
14. ✅ Restart intensity properties (maxRestarts, maxSeconds) are generated
15. ✅ Child spec properties are generated (childId, startModule, etc.)
16. ✅ Source locations are included when available
17. ✅ Supervisor IRI uses module IRI pattern
18. ✅ Child spec IRIs use blank nodes
19. ✅ Both `use Supervisor` and `@behaviour Supervisor` are supported
20. ✅ All functions have @spec typespecs
21. ✅ Test suite passes with 15+ comprehensive tests
22. ✅ 100% code coverage for SupervisorBuilder
23. ✅ Documentation includes clear usage examples
24. ✅ No regressions in existing tests
25. ✅ Integration with Behaviour Builder is documented
26. ✅ Triple deduplication works correctly

## 7. Risk Mitigation

### Risk 1: Blank Node Management for Child Specs
**Issue**: Child specs use blank nodes which need unique identifiers.
**Mitigation**:
- Use child ID in blank node label for uniqueness
- Handle duplicate child IDs gracefully
- Test with various child spec formats
- Document blank node generation strategy

### Risk 2: Ordered List Complexity
**Issue**: RDF lists for ordered children add complexity.
**Mitigation**:
- Reuse `Helpers.build_rdf_list/1` from builder helpers
- Test with different list sizes (0, 1, many children)
- Verify list order is preserved
- Document list construction pattern

### Risk 3: Shutdown Strategy Polymorphism
**Issue**: Shutdown can be atom or integer, requiring different RDF representations.
**Mitigation**:
- Implement helper returning {iri, extra_triples} tuple
- Test all shutdown variants
- Handle nil shutdown gracefully
- Document shutdown IRI generation

### Risk 4: Strategy Default Values
**Issue**: Extractor may not capture default max_restarts/max_seconds.
**Mitigation**:
- Only generate triples for explicit values
- Document that nil means use OTP defaults
- Test with and without explicit values
- Don't override ontology-defined defaults

### Risk 5: Module Name in Start Spec
**Issue**: Child spec module may be nil or in different formats.
**Mitigation**:
- Handle nil module gracefully (skip startModule triple)
- Strip "Elixir." prefix from module atoms
- Test with various module formats
- Document module name handling

## 8. Future Enhancements

### Phase 12.3.3+ Dependencies
After this phase, we can implement:
- Agent builder (simpler state abstraction)
- Task builder (async/await patterns)
- Application builder (OTP application lifecycle)
- Registry builder (process registration)

### Later Optimizations
- Link child specs to actual process modules (if they exist in codebase)
- Track supervision tree depth and breadth metrics
- Detect supervision tree anti-patterns
- Generate supervision tree visualizations
- Validate restart intensity against best practices

### Enhanced Features
- Detect circular supervision dependencies
- Track child start order significance
- Analyze failure propagation paths
- Generate fault tolerance coverage metrics
- Support custom supervisor wrappers
- Analyze supervision strategy effectiveness

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Supervisor implementation triples | 2 hours | Skeleton |
| Strategy triple generation | 2 hours | Skeleton |
| Child spec triple generation | 3 hours | Skeleton |
| Ordered children list | 1 hour | Child spec |
| Integration and polish | 1 hour | All above |
| Unit tests (15+ tests) | 4 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 1 hour | All above |
| **Total** | **17 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/otp/supervisor.ex` - Supervisor extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/otp/genserver_builder.ex` - GenServer builder (reference pattern)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-otp.ttl` - Supervisor ontology definitions
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Structure ontology

### Related Phase Documents
- `notes/features/phase-12-3-1-genserver-builder.md` - GenServer builder (OTP pattern reference)
- `notes/features/phase-12-2-2-behaviour-builder.md` - Behaviour builder (complementary)
- `notes/features/phase-12-1-3-function-builder.md` - Function builder
- `notes/features/phase-12-1-2-module-builder.md` - Module builder

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Supervisor documentation: https://hexdocs.pm/elixir/Supervisor.html
- DynamicSupervisor documentation: https://hexdocs.pm/elixir/DynamicSupervisor.html
- OTP Design Principles - Supervisor: https://www.erlang.org/doc/design_principles/sup_princ.html
- Elixir behaviours guide: https://elixir-lang.org/getting-started/typespecs-and-behaviours.html
