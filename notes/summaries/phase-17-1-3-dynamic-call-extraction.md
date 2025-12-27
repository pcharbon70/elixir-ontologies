# Phase 17.1.3: Dynamic Call Extraction - Summary

## Completed

Implemented extraction of dynamic function calls from Elixir AST, extending the call extractor to handle `apply/2`, `apply/3`, `Kernel.apply`, and anonymous function invocations.

## Changes Made

### 1. Dynamic Call Type Detection

Implemented `dynamic_call?/1` predicate handling:
- `apply/3`: `apply(Module, :func, args)` with module and function
- `apply/2`: `apply(fun, args)` with function reference
- `Kernel.apply/3`: Remote call to Kernel.apply
- `Kernel.apply/2`: Remote call to Kernel.apply with function
- Anonymous function calls: `fun.(args)` syntax

### 2. Dynamic Call Extraction Functions

- `extract_dynamic/2` - Extract single dynamic call with metadata
- `extract_dynamic!/2` - Raising version
- `extract_dynamic_calls/2` - Bulk extraction from AST
- Updated `extract_all_calls/2` to include dynamic calls

### 3. Metadata Tracking

Each dynamic call type stores relevant metadata:
- apply/3 with known module: `%{dynamic_type: :apply_3, known_module: [:M], known_function: :f}`
- apply/3 with variables: `%{dynamic_type: :apply_3, module_variable: :mod, function_variable: :func}`
- apply/2: `%{dynamic_type: :apply_2, function_variable: :fun}`
- apply/2 with capture: `%{dynamic_type: :apply_2, function_capture: {:&, ...}}`
- Anonymous call: `%{dynamic_type: :anonymous_call, function_variable: :callback}`

### 4. Updated Recursive Extraction

Modified `extract_calls_recursive/5` to support a `mode` parameter:
- `:local` - Extract only local calls
- `:remote` - Extract only remote calls
- `:dynamic` - Extract only dynamic calls
- `:all` - Extract all types

Added new pattern handlers:
- Anonymous function call pattern (single-element dot call)
- apply/2 and apply/3 call patterns
- Kernel.apply detection in remote call handler

## Test Results

- 35 doctests pass
- 115 unit tests pass (65 new dynamic call tests)
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` shows only pre-existing refactoring suggestions

## Files Modified

### Modified Files
1. `lib/elixir_ontologies/extractors/call.ex` - Extended with dynamic call support
2. `test/elixir_ontologies/extractors/call_test.exs` - Added 65 new tests
3. `notes/planning/extractors/phase-17.md` - Marked task 17.1.3 as complete

### Files Already Created (previous session)
1. `notes/features/phase-17-1-3-dynamic-call-extraction.md` - Planning document
2. `notes/summaries/phase-17-1-3-dynamic-call-extraction.md` - This summary

## Test Coverage

| Category | Tests |
|----------|-------|
| `dynamic_call?/1` predicate | 14 tests |
| `extract_dynamic/2` | 18 tests |
| `extract_dynamic!/2` | 2 tests |
| `extract_dynamic_calls/2` | 10 tests |
| Combined `extract_all_calls/2` | 3 tests |
| New doctests | 7 tests |
| **New Total** | **54 new tests** |

## Dynamic Call AST Patterns

```elixir
# apply/3: apply(Module, :func, args)
{:apply, meta, [{:__aliases__, [], [:Module]}, :func, [1, 2]]}

# apply/2: apply(fun, args)
{:apply, meta, [{:fun, [], Elixir}, [1, 2]]}

# Kernel.apply/3
{{:., [], [{:__aliases__, [], [:Kernel]}, :apply]}, [], [module, func, args]}

# Kernel.apply/2
{{:., [], [{:__aliases__, [], [:Kernel]}, :apply]}, [], [fun, args]}

# Anonymous function call: fun.(args)
{{:., [], [{:callback, [], Elixir}]}, [], [1, 2, 3]}
```

## Key Design Decisions

1. **Dynamic calls set name to `:apply` or `:anonymous`** - Since the actual target is unknown
2. **Arity reflects actual args count** - Not the apply signature (e.g., apply/3 with 2-element list has arity 2)
3. **Known values tracked in metadata** - When module/function are literals, store them
4. **Variable names tracked** - When targets are variables, track the variable name
5. **Function captures tracked** - apply/2 with `&func/1` stores the capture AST

## Next Task

**Task 17.1.4: Pipe Chain Extraction**
- Implement `extract_pipe_chain/1` for `|>` operator sequences
- Define `%PipeChain{steps: [...], start_value: ..., location: ...}` struct
- Extract each step as a function call with implicit first argument
- Track pipe chain order and length
