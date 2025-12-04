# Elixir OTP Ontology Guide

**File**: `elixir-otp.ttl`
**Namespace**: `https://w3id.org/elixir-code/otp#`
**Prefix**: `otp:`

## Overview

The OTP ontology models runtime patterns and BEAM VM abstractions. While `elixir-structure.ttl` captures static code structure, this module captures the dynamic architecture: processes, supervision trees, message passing, and OTP behaviours.

OTP (Open Telecom Platform) is the framework that makes Elixir applications fault-tolerant and scalable.

## Dependencies

```turtle
owl:imports <https://w3id.org/elixir-code/structure>
```

Extends behaviour and module concepts from the structure ontology.

## Process Fundamentals

### The Process Class

Processes are the fundamental unit of concurrency in the BEAM VM:

```turtle
otp:Process a owl:Class ;
    skos:definition "The fundamental unit of concurrency in the BEAM VM."@en .
```

Key characteristics:
- Lightweight (can run millions concurrently)
- Isolated (share nothing)
- Communicate via message passing
- Each has its own heap, stack, and mailbox

### Process Identity

Processes can be identified multiple ways:

```
ProcessIdentity
├── PID              # Process identifier: #PID<0.123.0>
├── RegisteredName   # Atom name
│   ├── LocalRegistration   # Node-local atom
│   └── GlobalRegistration  # Cluster-wide atom
└── ViaRegistration  # Registry-based: {:via, Registry, key}
```

Properties:
- `pidString` - String representation of PID
- `registeredAtom` - Atom name for registered processes
- `viaModule`, `viaKey` - For Registry-based naming

### Process Relationships

```turtle
otp:linkedTo a owl:ObjectProperty, owl:SymmetricProperty ;
    rdfs:comment "Bidirectional process link."@en .

otp:monitors a owl:ObjectProperty ;
    rdfs:comment "Unidirectional monitoring."@en .

otp:spawns a owl:ObjectProperty .
otp:sendsMessageTo a owl:ObjectProperty .
```

**Links vs Monitors**:
- Links are bidirectional—if one process dies, linked processes receive exit signals
- Monitors are unidirectional—monitor receives `:DOWN` message when monitored process exits

### Process Components

```turtle
otp:ProcessMailbox a owl:Class ;
    rdfs:comment "The message queue for a process."@en .

otp:ProcessLinks a owl:Class ;
    rdfs:comment "Bidirectional links between processes."@en .

otp:ProcessMonitor a owl:Class ;
    rdfs:comment "Unidirectional monitoring of a process."@en .
```

## OTP Behaviours

### Behaviour Hierarchy

```
OTPBehaviour (extends struct:Behaviour)
├── GenServer          # Generic server
├── SupervisorBehaviour # Supervision
├── Application        # OTP application
├── Agent              # Simple state wrapper
├── GenStatem          # State machine
└── GenEventManager    # Deprecated
```

### GenServer

The most common OTP behaviour—manages state through callbacks:

```turtle
otp:GenServer a owl:Class ;
    rdfs:subClassOf otp:OTPBehaviour ;
    skos:example """defmodule Counter do
  use GenServer
  def init(count), do: {:ok, count}
  def handle_call(:get, _from, count), do: {:reply, count, count}
end"""@en .
```

#### GenServer Callbacks

```
GenServerCallback
├── InitCallback           # init/1 - initialize state
├── HandleCallCallback     # handle_call/3 - sync requests
├── HandleCastCallback     # handle_cast/2 - async messages
├── HandleInfoCallback     # handle_info/2 - other messages
├── HandleContinueCallback # handle_continue/2 - deferred work
├── TerminateCallback      # terminate/2 - cleanup
└── CodeChangeCallback     # code_change/3 - hot upgrades
```

#### GenServer Messages

```
GenServerMessage
├── Call  # Synchronous, expects reply
├── Cast  # Asynchronous, no reply
└── Info  # Direct mailbox message
```

#### GenServer Replies

```
GenServerReply
├── ReplyTuple    # {:reply, reply, state}
├── NoReplyTuple  # {:noreply, state}
└── StopTuple     # {:stop, reason, state}
```

### Agent

Simple state wrapper built on GenServer:

```turtle
otp:Agent a owl:Class ;
    rdfs:subClassOf otp:OTPBehaviour ;
    skos:example "Agent.start_link(fn -> 0 end)"@en .
```

Provides `get/update/get_and_update` without explicit callbacks.

### Task

For single async computations:

```turtle
otp:Task a owl:Class ;
    rdfs:subClassOf otp:Process ;
    skos:example "Task.async(fn -> expensive_computation() end)"@en .
```

Used with `Task.async/await` pattern for parallel work.

## Supervision

### Supervisor

Supervisors monitor and restart child processes:

```turtle
otp:Supervisor a owl:Class ;
    rdfs:subClassOf otp:Process .
```

Properties:
- `hasStrategy` - Restart strategy
- `hasChildSpec` - Child specifications
- `hasChildren` - Ordered list of children
- `maxRestarts` - Max restarts in time window
- `maxSeconds` - Time window for restart counting

### Supervision Strategies

```turtle
otp:OneForOne a otp:SupervisionStrategy ;
    rdfs:comment "Only restart the failed child."@en .

otp:OneForAll a otp:SupervisionStrategy ;
    rdfs:comment "Restart all children if one fails."@en .

otp:RestForOne a otp:SupervisionStrategy ;
    rdfs:comment "Restart failed child and all started after it."@en .
```

When to use each:
- **one_for_one**: Children are independent
- **one_for_all**: Children are interdependent
- **rest_for_one**: Children have ordered dependencies

### Child Specifications

```turtle
otp:ChildSpec a owl:Class .
```

Properties:
- `childId` - Unique identifier
- `startModule` - Module to start
- `startFunction` - Function to call (usually `start_link`)
- `hasRestartStrategy` - How to restart
- `hasChildType` - Worker or supervisor
- `hasShutdownStrategy` - How to terminate

### Restart Strategies

```turtle
otp:Permanent a otp:RestartStrategy ;
    rdfs:comment "Always restart."@en .

otp:Temporary a otp:RestartStrategy ;
    rdfs:comment "Never restart."@en .

otp:Transient a otp:RestartStrategy ;
    rdfs:comment "Restart only on abnormal exit."@en .
```

### Child Types

```turtle
otp:WorkerType a otp:ChildType ;
    rdfs:comment "A worker process."@en .

otp:SupervisorType a otp:ChildType ;
    rdfs:comment "A supervisor process."@en .
```

### Shutdown Strategies

```turtle
otp:BrutalKill a otp:ShutdownStrategy ;
    rdfs:comment "Kill immediately with :kill signal."@en .

otp:InfiniteShutdown a otp:ShutdownStrategy ;
    rdfs:comment "Wait indefinitely for termination."@en .

otp:TimeoutShutdown a owl:Class ;
    rdfs:subClassOf otp:ShutdownStrategy .
```

`TimeoutShutdown` has `shutdownTimeout` property for milliseconds to wait.

### Supervision Tree

```turtle
otp:SupervisionTree a owl:Class .
```

Properties:
- `rootSupervisor` - The top-level supervisor
- `partOfTree` - Links processes to their tree

### Dynamic Supervisors

```turtle
otp:DynamicSupervisor a owl:Class ;
    rdfs:subClassOf otp:Supervisor .
```

For dynamically starting/stopping children. Constrained to `:one_for_one`:

```turtle
otp:DynamicSupervisor rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty otp:hasStrategy ;
    owl:hasValue otp:OneForOne
] .
```

### Specialized Supervisors

```turtle
otp:TaskSupervisor a owl:Class ;
    rdfs:subClassOf otp:Supervisor .

otp:PartitionSupervisor a owl:Class ;
    rdfs:subClassOf otp:Supervisor .
```

- `TaskSupervisor` - For dynamic Task children
- `PartitionSupervisor` - Partitions children across schedulers

## Registry

```turtle
otp:Registry a owl:Class ;
    rdfs:subClassOf otp:GenServer .
```

Properties:
- `registryType` - `"unique"` or `"duplicate"`
- `registryPartitions` - Number of partitions

Relationships:
- `registeredIn` - Process registered in this registry
- `registeredWithKey` - The registration key

## Application

```turtle
otp:Application a owl:Class ;
    rdfs:subClassOf otp:OTPBehaviour .
```

OTP applications are components that can be started/stopped as units. Implements `start/2` and optionally `stop/1`, `prep_stop/1`.

## ETS Tables

### ETSTable

```turtle
otp:ETSTable a owl:Class ;
    rdfs:comment "Erlang Term Storage - in-memory storage."@en .
```

Properties:
- `tableName` - Atom or reference
- `isNamedTable` - Whether table has atom name
- `ownedByProcess` - Owning process
- `heirProcess` - Process that inherits on owner death
- `hasTableType` - Storage type
- `hasAccessType` - Access control
- `keyPosition` - Position of key in tuples
- `readConcurrency`, `writeConcurrency` - Optimization flags
- `compressData` - Whether to compress

### Table Types

```turtle
otp:SetTable a otp:ETSTableType ;
    rdfs:comment "One object per key."@en .

otp:OrderedSetTable a otp:ETSTableType ;
    rdfs:comment "Set with keys in term order."@en .

otp:BagTable a otp:ETSTableType ;
    rdfs:comment "Multiple objects per key, no duplicates."@en .

otp:DuplicateBagTable a otp:ETSTableType ;
    rdfs:comment "Multiple objects including duplicates."@en .
```

### Access Types

```turtle
otp:PublicTable a otp:ETSAccessType ;
    rdfs:comment "Any process can read and write."@en .

otp:ProtectedTable a otp:ETSAccessType ;
    rdfs:comment "Any process can read, only owner writes."@en .

otp:PrivateTable a otp:ETSAccessType ;
    rdfs:comment "Only owner can read and write."@en .
```

### DETS

```turtle
otp:DETSTable a owl:Class ;
    rdfs:comment "Disk-based ETS table."@en .
```

## Distribution

### Nodes and Clusters

```turtle
otp:Node a owl:Class ;
    rdfs:comment "A running BEAM VM instance."@en .

otp:Cluster a owl:Class ;
    rdfs:comment "Connected Erlang nodes."@en .
```

Properties:
- `nodeName` - Node name (e.g., `"myapp@host"`)
- `nodeHost` - Hostname
- `connectedTo` - Symmetric connection relationship
- `partOfCluster` - Cluster membership
- `cookie` - Authentication cookie

### Distributed Processes

```turtle
otp:DistributedProcess a owl:Class ;
    rdfs:subClassOf otp:Process .

otp:GlobalProcess a owl:Class ;
    rdfs:subClassOf otp:DistributedProcess .
```

Properties:
- `runsOn` - Which node the process runs on

### Remote Calls

```turtle
otp:RemoteCall a owl:Class ;
    rdfs:comment "Function call to a remote node."@en .
```

## Telemetry

### Events and Handlers

```turtle
otp:TelemetryEvent a owl:Class ;
    rdfs:comment "A Telemetry event named by atom list."@en .

otp:TelemetryHandler a owl:Class ;
    rdfs:comment "A function handling Telemetry events."@en .

otp:TelemetrySpan a owl:Class ;
    rdfs:comment "Duration measurement with start/stop/exception."@en .
```

Properties:
- `eventName` - Dot-separated atom list
- `handlerModule`, `handlerFunction` - Handler location
- `emitsEvent` - Process emitting events
- `handlesEvent` - Handler-event relationship

## OWL Axioms

### Strategy Constraints

```turtle
# Strategies are mutually exclusive
[] a owl:AllDifferent ;
    owl:distinctMembers ( otp:OneForOne otp:OneForAll otp:RestForOne ) .

# Every supervisor has exactly one strategy
otp:Supervisor rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty otp:hasStrategy ;
    owl:cardinality 1
] .
```

### Child Spec Requirements

```turtle
otp:ChildSpec rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty otp:hasRestartStrategy ;
    owl:cardinality 1
] , [
    a owl:Restriction ;
    owl:onProperty otp:hasChildType ;
    owl:cardinality 1
] .
```

### ETS Ownership

```turtle
otp:ETSTable rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty otp:ownedByProcess ;
    owl:cardinality 1
] .
```

### Symmetric Links

```turtle
otp:linkedTo a owl:SymmetricProperty .
otp:connectedTo a owl:SymmetricProperty .
```

## Relationship to Other Modules

### Imports

- `elixir-structure.ttl` - For `Behaviour`, `BehaviourImplementation`, `Module`

### Imported By

- `elixir-evolution.ttl` - Indirectly via import chain

### Extension Pattern

OTP behaviours extend the structure module's Behaviour class:

```turtle
otp:OTPBehaviour a owl:Class ;
    rdfs:subClassOf struct:Behaviour .

otp:GenServerImplementation a owl:Class ;
    rdfs:subClassOf struct:BehaviourImplementation .
```

## Usage Examples

### Modeling a Supervision Tree

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def init(_) do
    children = [
      {MyApp.Worker, []},
      {MyApp.Cache, name: MyApp.Cache}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

```turtle
ex:myAppSupervisor a otp:Supervisor ;
    otp:hasStrategy otp:OneForOne ;
    otp:maxRestarts 3 ;
    otp:maxSeconds 5 ;
    otp:hasChildren ( ex:workerSpec ex:cacheSpec ) .

ex:workerSpec a otp:ChildSpec ;
    otp:childId "worker" ;
    otp:startModule "MyApp.Worker" ;
    otp:hasRestartStrategy otp:Permanent ;
    otp:hasChildType otp:WorkerType .

ex:cacheSpec a otp:ChildSpec ;
    otp:childId "cache" ;
    otp:startModule "MyApp.Cache" ;
    otp:hasRestartStrategy otp:Permanent ;
    otp:hasChildType otp:WorkerType .
```

### Modeling a GenServer

```elixir
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
```

```turtle
ex:counterModule a struct:Module ;
    struct:moduleName "Counter" ;
    struct:implementsBehaviour otp:GenServer .

ex:counterImpl a otp:GenServerImplementation ;
    otp:hasGenServerCallback ex:counterInit,
                              ex:counterHandleCall,
                              ex:counterHandleCast .

ex:counterInit a otp:InitCallback .
ex:counterHandleCall a otp:HandleCallCallback .
ex:counterHandleCast a otp:HandleCastCallback .
```

### Modeling Process Communication

```turtle
ex:workerProcess a otp:Process ;
    otp:hasIdentity ex:workerPid ;
    otp:supervisedBy ex:myAppSupervisor ;
    otp:sendsMessageTo ex:cacheProcess ;
    otp:monitors ex:externalService .

ex:workerPid a otp:PID ;
    otp:pidString "#PID<0.123.0>" .
```

## Design Rationale

1. **Process-centric**: Processes are first-class entities with identity, relationships, and state
2. **Supervision hierarchy**: Trees modeled with ordered children and typed strategies
3. **Behaviour contracts**: OTP behaviours extend the structure module's behaviour model
4. **Runtime vs static**: Complements static structure with dynamic relationships
5. **Storage modeling**: ETS/DETS with access control and ownership semantics
