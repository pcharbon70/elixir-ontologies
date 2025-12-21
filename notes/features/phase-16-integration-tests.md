# Phase 16 Integration Tests

## Overview

This task implements comprehensive integration tests for Phase 16 (Module Directives & Scope Analysis). The tests verify end-to-end functionality across all directive extractors, dependency builders, and the complete pipeline integration.

## Scope

Based on the planning document, we need 15+ integration tests covering:

1. Complete directive extraction for complex modules
2. Module dependency graph generation
3. Multi-module analysis with cross-references
4. Directive RDF validates against SHACL shapes
5. Pipeline integration with directive extractors
6. Orchestrator coordinates dependency builders
7. Alias resolution across modules
8. Import conflict detection accuracy
9. Use option extraction completeness
10. Lexical scope tracking accuracy
11. External dependency marking
12. Circular dependency detection
13. Multi-alias expansion correctness
14. Backward compatibility with existing module extraction
15. Error handling for malformed directives

Additionally, two remaining Section 16.4 unit tests:
- Test dependency graph completeness
- Test SHACL validation of dependency graph

## Test Structure

Following the established pattern from other phase integration tests (Phase 14, Phase 15), tests will:
- Use `use ExUnit.Case, async: true`
- Define test modules as heredoc strings
- Parse modules with `Code.string_to_quoted/1`
- Extract using directive extractors
- Build RDF using dependency builder
- Verify triples using helper functions

## Implementation Plan

### Step 1: Create Test File Structure
Create `test/elixir_ontologies/extractors/phase_16_integration_test.exs` with:
- Test helpers for extraction and verification
- Complex module fixtures covering all directive types

### Step 2: Directive Extraction Tests
- Test complete directive extraction for complex module
- Test multi-alias expansion correctness
- Test lexical scope tracking accuracy
- Test use option extraction completeness
- Test error handling for malformed directives

### Step 3: Dependency Graph Tests
- Test module dependency graph generation
- Test dependency graph completeness
- Test external dependency marking
- Test cross-module linking

### Step 4: Multi-Module Analysis Tests
- Test multi-module analysis with cross-references
- Test alias resolution across modules
- Test circular dependency detection
- Test import conflict detection accuracy

### Step 5: Pipeline/Orchestrator Integration
- Test Pipeline integration with directive extractors
- Test Orchestrator coordinates dependency builders
- Test backward compatibility with existing module extraction

### Step 6: SHACL Validation Tests
- Test directive RDF validates against shapes
- Test SHACL validation of dependency graph

## Test Fixtures

### Complex Module with All Directives
```elixir
defmodule ComplexDirectives do
  alias MyApp.{Users, Accounts}
  alias MyApp.Helpers, as: H

  import Enum, only: [map: 2, filter: 2]
  import Logger, only: :macros

  require Logger
  require MyApp.Macros, as: M

  use GenServer, restart: :temporary
  use MyApp.Behaviour, option: :value

  # Functions that use the aliases/imports
  def process(data) do
    alias MyApp.LocalModule  # function-level alias
    data |> map(&H.transform/1) |> filter(&Users.valid?/1)
  end
end
```

### Multi-Module Cross-Reference Test
```elixir
defmodule ModuleA do
  alias ModuleB
  import ModuleC, only: [helper: 1]
  use ModuleD
end

defmodule ModuleB do
  alias ModuleA
  require ModuleC
end

defmodule ModuleC do
  def helper(x), do: x
end

defmodule ModuleD do
  defmacro __using__(_opts) do
    quote do
      import ModuleC
    end
  end
end
```

## Files to Create/Modify

1. `test/elixir_ontologies/extractors/phase_16_integration_test.exs` - Main integration tests
2. `notes/planning/extractors/phase-16.md` - Mark tests complete
3. `notes/summaries/phase-16-integration-tests.md` - Summary document

## Success Criteria

- All 15+ integration tests pass
- Tests cover all items from the planning document
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes
- Tests run in under 30 seconds
