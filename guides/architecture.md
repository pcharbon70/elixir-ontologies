# Architecture Overview

This guide explains the internal architecture of Elixir Ontologies, a system that transforms Elixir source code into semantic RDF knowledge graphs.

## High-Level Data Flow

```
+------------------+     +------------------+     +------------------+
|   Source Files   | --> |   Elixir AST     | --> |  Elixir Structs  |
|   (.ex, .exs)    |     |   (Macro.t())    |     |   (Extractors)   |
+------------------+     +------------------+     +------------------+
                                                          |
                                                          v
+------------------+     +------------------+     +------------------+
|  Turtle/RDF      | <-- |   RDF.Graph      | <-- |   RDF Triples    |
|  Serialization   |     |   (rdf_ex)       |     |   (Builders)     |
+------------------+     +------------------+     +------------------+
```

**Complete Pipeline:**
```
Source File --> Parser --> AST --> Extractors --> Structs --> Builders --> RDF Graph
```

## Architectural Layers

```
+==========================================================================+
|                             ANALYZER LAYER                               |
|  FileAnalyzer | ProjectAnalyzer | Parser | Git | Project | ChangeTracker |
+==========================================================================+
                                    |
                                    v
+==========================================================================+
|                             EXTRACTOR LAYER                              |
|  80+ extractors: Function, Module, Protocol, OTP patterns, Evolution... |
+==========================================================================+
                                    |
                                    v
+==========================================================================+
|                              BUILDER LAYER                               |
|  25+ builders: Orchestrator, ModuleBuilder, FunctionBuilder, OTP...     |
+==========================================================================+
                                    |
                                    v
+==========================================================================+
|                              GRAPH LAYER                                 |
|  Graph wrapper around RDF.Graph | Serialization (Turtle) | SPARQL       |
+==========================================================================+
                                    |
                                    v
+==========================================================================+
|                             ONTOLOGY LAYER                               |
|  elixir-core.ttl | elixir-structure.ttl | elixir-otp.ttl | evolution    |
+==========================================================================+
```

## Layer 1: Analyzer Layer

**Location**: `lib/elixir_ontologies/analyzer/`

| Component | Responsibility |
|-----------|----------------|
| `FileAnalyzer` | Analyzes single files, orchestrates extractors |
| `ProjectAnalyzer` | Analyzes entire Mix projects, merges graphs |
| `Parser` | Wraps `Code.string_to_quoted/2` with error handling |
| `Git` | Detects repository context, commits, branches |
| `Project` | Detects Mix project structure |
| `ChangeTracker` | Tracks file modifications for incremental updates |

### FileAnalyzer Pipeline

```
FileAnalyzer.analyze/2
        |
        +---> Parser.parse_file/1      (Source --> AST)
        +---> Git.source_file/1        (Repository context)
        +---> Project.detect/1         (Mix project context)
        |
        v
Context Detection: { git: SourceFile, project: Project }
        |
        v
Module Extraction: For each defmodule, run all extractors
        |
        v
Graph Building: Pipeline.build_graph_for_modules
        |
        v
FileAnalyzer.Result: { file_path, modules, graph, source_file, ... }
```

## Layer 2: Extractor Layer

**Location**: `lib/elixir_ontologies/extractors/`

Extractors pattern-match on AST nodes and produce typed Elixir structs.

### Extractor Categories

```
extractors/
+-- Core: module, function, clause, parameter, pattern, guard, attribute
+-- Type System: function_spec
+-- Metaprogramming: macro, macro_invocation
+-- Control Flow: control_flow, case_with, conditional, comprehension, exception
+-- OTP: otp/genserver, otp/supervisor, otp/agent, otp/task, otp/ets
+-- Protocols: protocol, behaviour
+-- Evolution: evolution/commit, evolution/deprecation, evolution/refactoring
+-- Directives: directive/alias, directive/import, directive/require, directive/use
```

### Extractor Pattern

```elixir
defmodule ElixirOntologies.Extractors.Function do
  defstruct [:type, :name, :arity, :visibility, :docstring, :location, :metadata]

  # Type guard for matching
  def function?({type, _, _}) when type in [:def, :defp, ...], do: true
  def function?(_), do: false

  # Main extraction
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract({:def, meta, [{name, _, args}, body]}, opts) do
    {:ok, %__MODULE__{type: :function, name: name, arity: length(args || []), ...}}
  end
  def extract(_, _), do: {:error, "Not a function definition"}
end
```

## Layer 3: Builder Layer

**Location**: `lib/elixir_ontologies/builders/`

Builders transform Elixir structs into RDF triples.

### Orchestrator Phases

```
Phase 1: Module Builder (Sequential)
    +---> Establishes module IRI
    |
    v
Phase 2: Module-Level Builders (Parallel via Task.async_stream)
    +---> Functions, Protocols, Behaviours, Structs, Types
    +---> OTP Patterns, Calls, Control Flow, Exceptions
    |
    v
Aggregation: Combine all triples into RDF.Graph
```

### Builder Context

```elixir
%Context{
  base_iri: "https://w3id.org/elixir-code/",
  file_path: "lib/my_app/users.ex",
  parent_module: ~I<...#MyApp>,
  config: %{include_source_text: true},
  known_modules: MapSet.new(["MyApp.Users", "MyApp.Accounts"])
}
```

### Builder Pattern

```elixir
defmodule ElixirOntologies.Builders.FunctionBuilder do
  @spec build(Function.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(function_info, context) do
    function_iri = generate_iri(function_info, context)
    triples = [
      {function_iri, RDF.type(), Structure.Function},
      {function_iri, Structure.functionName(), function_info.name},
      {function_iri, Structure.arity(), function_info.arity},
      ...
    ]
    {function_iri, triples}
  end
end
```

### Builder Categories

| Category | Builders | Ontology |
|----------|----------|----------|
| Core | ModuleBuilder, FunctionBuilder, ClauseBuilder | elixir-structure.ttl |
| OTP | GenServerBuilder, SupervisorBuilder, AgentBuilder, TaskBuilder | elixir-otp.ttl |
| Evolution | VersionBuilder, CommitBuilder, ActivityBuilder | elixir-evolution.ttl |
| Control Flow | ControlFlowBuilder, CallGraphBuilder, ExceptionBuilder | elixir-core.ttl |

## Layer 4: Graph Layer

**Location**: `lib/elixir_ontologies/graph.ex`

Wrapper around `RDF.Graph` from the `rdf_ex` library.

```elixir
# Creation and manipulation
graph = Graph.new(base_iri: "https://example.org/code#")
graph = Graph.add(graph, {subject, predicate, object})

# Querying
subjects = Graph.subjects(graph)
description = Graph.describe(graph, subject_iri)

# Serialization
{:ok, turtle} = Graph.to_turtle(graph)
:ok = Graph.save(graph, "output.ttl")
{:ok, graph} = Graph.load("input.ttl")
```

## Layer 5: Ontology Layer

**Location**: `priv/ontologies/`

```
elixir-core.ttl          (AST primitives, expressions, patterns)
    |
    v owl:imports
elixir-structure.ttl     (Module, Function, Protocol, Behaviour)
    |
    v owl:imports
elixir-otp.ttl           (GenServer, Supervisor, Agent, Task)
    |
    v owl:imports
elixir-evolution.ttl     (PROV-O, version tracking)

elixir-shapes.ttl        (SHACL validation, cross-cutting)
```

## IRI Generation

```
Base IRI: https://w3id.org/elixir-code/

Module:     {base}#MyApp.Users
Function:   {base}#MyApp.Users/get_user/1
Clause:     {base}#MyApp.Users/get_user/1/clause/0
SourceFile: {base}files/lib/my_app/users.ex
Location:   {base}files/lib/my_app/users.ex#L10-L25
```

## Namespace Registry

The `NS` module defines RDF vocabularies:

```elixir
defmodule ElixirOntologies.NS do
  use RDF.Vocabulary.Namespace

  defvocab Core, base_iri: "https://w3id.org/elixir-code/core#", ...
  defvocab Structure, base_iri: "https://w3id.org/elixir-code/structure#", ...
  defvocab OTP, base_iri: "https://w3id.org/elixir-code/otp#", ...
  defvocab Evolution, base_iri: "https://w3id.org/elixir-code/evolution#", ...
end
```

## Incremental Analysis

```
Initial Analysis --> capture_state/1 --> Store file hashes in Result.metadata
                                              |
                                        Time passes, files change
                                              |
                                              v
                                        detect_changes/2
                                              |
                                              v
                     Changes { changed: [...], new: [...], deleted: [...], unchanged: [...] }
                                              |
                                              v
                                    Re-analyze only changed/new files
```

## Error Handling

**Hard Errors** (abort): File not found, parse failures, invalid config
```elixir
case Parser.parse_file(path) do
  {:ok, result} -> continue
  {:error, reason} -> {:error, reason}
end
```

**Soft Errors** (continue with logging): Extractor failures, missing Git context
```elixir
defp safe_extract(extractor_fn) do
  case extractor_fn.() do
    {:ok, result} -> result
    {:error, _} -> nil
  end
rescue
  e -> Logger.debug("Extractor failed: #{inspect(e)}"); nil
end
```

## Extension Points

### Adding a New Extractor

1. Create `lib/elixir_ontologies/extractors/my_extractor.ex`
2. Define result struct with typed fields
3. Implement `my_feature?/1` predicate and `extract/2`
4. Add to `FileAnalyzer` extraction pipeline

### Adding a New Builder

1. Create `lib/elixir_ontologies/builders/my_builder.ex`
2. Implement `build/2` returning `{iri, triples}`
3. Register in `Orchestrator.build_phase_2/7`

### Extending the Ontology

1. Add classes/properties to appropriate `.ttl` file
2. Add terms to `NS` vocabulary module
3. Add SHACL shapes to `elixir-shapes.ttl`
4. Update builders to generate new triples

## Performance

- **Parallel Execution**: Phase 2 builders run concurrently via `Task.async_stream`
- **Incremental Updates**: ChangeTracker enables re-analysis of only modified files
- **Memory**: Stream processing for large projects; graph merging is additive
