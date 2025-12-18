# Phase 13.1.2: Full Pipeline Integration Planning Document

## 1. Problem Statement

Phase 13.1.1 implemented the Builder Orchestrator to coordinate all 11 RDF builders. However, the existing FileAnalyzer and ProjectAnalyzer modules have a placeholder `build_graph/3` function that returns an empty graph. We need to integrate the Orchestrator into the analysis pipeline to generate complete RDF graphs.

**The Challenge**:
- FileAnalyzer extracts information but doesn't use the Builder Orchestrator
- The `build_graph/3` function is a stub that returns an empty graph
- ModuleAnalysis structs don't match the format expected by Orchestrator
- Need to bridge the gap between extractors and builders

**Current State**:
- FileAnalyzer.analyze/2 returns `Result` with modules and empty graph
- ModuleAnalysis contains: module_info, functions, types, specs, protocols, behaviors, otp_patterns, attributes, macros
- Orchestrator expects: module, functions, protocols, behaviours, structs, types, genservers, supervisors, agents, tasks

## 2. Solution Overview

Create a **Pipeline** module that:

1. **Bridges Extraction and Building**: Converts ModuleAnalysis structs to Orchestrator-compatible format
2. **Integrates with FileAnalyzer**: Replaces the stub `build_graph/3` with real implementation
3. **Supports Parallel Execution**: Leverages Orchestrator's parallel capabilities
4. **Provides High-Level API**: Simple functions for common use cases

### 2.1 Architecture

```
Source File/String
       ↓
   Parser (AST)
       ↓
   FileAnalyzer
       ↓
   Extract modules → ModuleAnalysis structs
       ↓
   Pipeline.build_graph_for_modules/3 (NEW)
       ↓
   For each module:
     - Convert ModuleAnalysis to Orchestrator format
     - Call Orchestrator.build_module_graph/3
       ↓
   Merge all module graphs
       ↓
   Complete RDF.Graph / ElixirOntologies.Graph
```

### 2.2 Key Design Decisions

1. **New Pipeline Module**: Create `ElixirOntologies.Pipeline` as the integration layer
2. **Conversion Functions**: Map ModuleAnalysis fields to Orchestrator input format
3. **Parallel Module Processing**: Process multiple modules in parallel
4. **Update FileAnalyzer**: Replace stub with Pipeline call
5. **Maintain Backward Compatibility**: Keep existing API, just fix implementation

## 3. Technical Details

### 3.1 Pipeline Module API

```elixir
defmodule ElixirOntologies.Pipeline do
  @spec build_graph_for_modules([ModuleAnalysis.t()], Context.t()) :: RDF.Graph.t()
  def build_graph_for_modules(modules, context)

  @spec build_graph_for_modules([ModuleAnalysis.t()], Context.t(), keyword()) :: RDF.Graph.t()
  def build_graph_for_modules(modules, context, opts)

  @spec analyze_and_build(String.t(), Config.t()) :: {:ok, Result.t()} | {:error, term()}
  def analyze_and_build(file_path, config \\ Config.default())

  @spec analyze_string_and_build(String.t(), Config.t()) :: {:ok, Result.t()} | {:error, term()}
  def analyze_string_and_build(source_code, config \\ Config.default())
end
```

### 3.2 ModuleAnalysis to Orchestrator Format Conversion

```elixir
# ModuleAnalysis struct:
%ModuleAnalysis{
  name: atom(),
  module_info: map(),           # → :module
  functions: list(),            # → :functions (already compatible)
  types: list(),                # → :types (already compatible)
  specs: list(),                # → (specs are separate, may need handling)
  protocols: %{},               # → :protocols (need to extract list)
  behaviors: %{},               # → :behaviours (need to extract list)
  otp_patterns: %{},            # → :genservers, :supervisors, :agents, :tasks
  attributes: list(),           # → (not used by Orchestrator)
  macros: list()                # → (not used by Orchestrator)
}

# Orchestrator expects:
%{
  module: Module.t(),           # ← from module_info
  functions: [Function.t()],    # ← direct mapping
  protocols: [Protocol.t()],    # ← from protocols map
  behaviours: [Behaviour.t()],  # ← from behaviors map
  structs: [Struct.t()],        # ← extract from attributes or separate
  types: [TypeDefinition.t()],  # ← direct mapping
  genservers: [GenServer.t()],  # ← from otp_patterns[:genserver]
  supervisors: [Supervisor.t()], # ← from otp_patterns[:supervisor]
  agents: [Agent.t()],          # ← from otp_patterns[:agent]
  tasks: [Task.t()]             # ← from otp_patterns[:task]
}
```

### 3.3 Options

- `:parallel` - Enable/disable parallel module processing (default: true)
- `:timeout` - Timeout for parallel tasks (default: 5000ms)
- `:include` - List of builders to include
- `:exclude` - List of builders to exclude

## 4. Success Criteria

- [✅] Pipeline module exists with complete documentation
- [✅] `build_graph_for_modules/3` converts and builds graphs correctly
- [✅] `analyze_and_build/2` provides end-to-end file analysis
- [✅] `analyze_string_and_build/2` provides end-to-end string analysis
- [✅] FileAnalyzer.build_graph/3 updated to use Pipeline
- [✅] Parallel module processing works correctly
- [✅] **25 tests passing** (target: 15+, achieved: 167%)

## 5. Implementation Plan

### Phase 1: Research (✅ COMPLETE)
- [✅] Understand FileAnalyzer structure
- [✅] Understand ModuleAnalysis format
- [✅] Understand Orchestrator input format
- [✅] Identify conversion requirements

### Phase 2: Design (✅ COMPLETE)
- [✅] Define Pipeline API
- [✅] Plan conversion functions
- [✅] Design parallel processing strategy

### Phase 3: Implementation (✅ COMPLETE)
- [✅] Create `lib/elixir_ontologies/pipeline.ex`
- [✅] Implement `convert_module_analysis/1` helper
- [✅] Implement `build_graph_for_modules/3`
- [✅] Implement `analyze_and_build/2`
- [✅] Implement `analyze_string_and_build/2`
- [✅] Update FileAnalyzer.build_graph/3

### Phase 4: Testing (✅ COMPLETE)
- [✅] Create comprehensive test suite (25 tests)
- [✅] Test conversion functions
- [✅] Test parallel processing
- [✅] Test end-to-end pipeline
- [✅] Test edge cases

### Phase 5: Documentation (✅ COMPLETE)
- [✅] Write summary document
- [ ] Ask for permission to commit

## 6. References

- `lib/elixir_ontologies/analyzer/file_analyzer.ex`
- `lib/elixir_ontologies/builders/orchestrator.ex`
- `lib/elixir_ontologies/builders/context.ex`
- `lib/elixir_ontologies/graph.ex`
- `lib/elixir_ontologies/config.ex`

---

**Status**: ✅ COMPLETE - Ready to Commit
