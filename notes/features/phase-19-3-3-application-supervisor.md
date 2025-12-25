# Phase 19.3.3: Application Supervisor Extraction

## Overview

Implement extraction of Application root supervisor configuration. This detects modules using `use Application` and extracts the root supervisor started in the `start/2` callback.

## Task Requirements (from phase-19.md)

- [x] 19.3.3.1 Detect Application.start/2 callback
- [x] 19.3.3.2 Extract root supervisor module
- [x] 19.3.3.3 Track application → supervisor relationship
- [N/A] 19.3.3.4 Handle :mod option in mix.exs application config (requires file system access)
- [x] 19.3.3.5 Create `%ApplicationSupervisor{}` struct
- [x] 19.3.3.6 Add application supervisor tests (39 tests)

## Implementation Design

### ApplicationSupervisor Struct

```elixir
defmodule ApplicationSupervisor do
  @typedoc """
  Application supervisor extraction result.

  - `:app_module` - The Application module (containing use Application)
  - `:supervisor_module` - The root supervisor module (if detected from Supervisor.start_link)
  - `:supervisor_name` - The :name option passed to Supervisor.start_link
  - `:supervisor_strategy` - Strategy if inline (not using a supervisor module)
  - `:uses_inline_supervisor` - True if supervisor is started inline (not a separate module)
  - `:detection_method` - :use or :behaviour
  - `:location` - Source location of the start/2 callback
  - `:metadata` - Additional info
  """
  defstruct app_module: nil,
            supervisor_module: nil,
            supervisor_name: nil,
            supervisor_strategy: nil,
            uses_inline_supervisor: false,
            detection_method: :use,
            location: nil,
            metadata: %{}
end
```

### Detection Patterns

#### Pattern 1: Inline Supervisor (most common)
```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [...]
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

In this pattern:
- `supervisor_module` = nil
- `supervisor_name` = MyApp.Supervisor
- `uses_inline_supervisor` = true
- `supervisor_strategy` = :one_for_one

#### Pattern 2: Dedicated Supervisor Module
```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    MyApp.Supervisor.start_link(name: MyApp.Supervisor)
  end
end
```

In this pattern:
- `supervisor_module` = MyApp.Supervisor
- `uses_inline_supervisor` = false

#### Pattern 3: Module with child_spec
```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [MyApp.Supervisor]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

In this pattern:
- Children list contains the supervisor as the root
- `uses_inline_supervisor` = true (but children reference supervisor module)

### Functions to Implement

1. `application?/1` - Check if module body uses Application
2. `extract/1` - Extract ApplicationSupervisor from module body
3. `extract!/1` - Same but raises on error
4. `extract_start_callback/1` - Extract the start/2 function
5. `extract_supervisor_call/1` - Extract Supervisor.start_link or Module.start_link call

### Location in Codebase

Create new file: `lib/elixir_ontologies/extractors/otp/application.ex`

### Test File

Create: `test/elixir_ontologies/extractors/otp/application_test.exs`

## Progress

- [x] Create ApplicationSupervisor struct
- [x] Implement application?/1 detection
- [x] Implement extract/1 for inline supervisor pattern
- [x] Implement extract/1 for dedicated supervisor module pattern
- [x] Handle edge cases (no start/2, dynamic children, etc.)
- [x] Add comprehensive tests (39 tests)
- [x] Update phase-19.md with completion status
