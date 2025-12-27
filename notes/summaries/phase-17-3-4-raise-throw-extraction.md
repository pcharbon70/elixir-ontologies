# Phase 17.3.4: Raise and Throw Extraction - Summary

## Task Completed

Implemented extraction of `raise`, `reraise`, `throw`, and `exit` expressions from Elixir AST. These expressions represent explicit flow control for error signaling and process termination.

## Implementation

### New Structs

Added to `lib/elixir_ontologies/extractors/exception.ex`:

**RaiseExpression**
- `exception` - Exception module, struct, or nil (for message-only raise)
- `message` - Message string or expression
- `attributes` - Keyword list of exception attributes
- `is_reraise` - True if this is a reraise
- `stacktrace` - Stacktrace expression for reraise
- `location` - Source location

**ThrowExpression**
- `value` - The thrown value
- `location` - Source location

**ExitExpression**
- `reason` - The exit reason
- `location` - Source location

### Type Predicates

- `raise_expression?/1` - Check if AST is raise/reraise
- `throw_expression?/1` - Check if AST is throw
- `exit_expression?/1` - Check if AST is exit

### Extraction Functions

- `extract_raise/2` and `extract_raise!/2` - Extract raise/reraise expression
- `extract_throw/2` and `extract_throw!/2` - Extract throw expression
- `extract_exit/2` and `extract_exit!/2` - Extract exit expression

### Bulk Extraction

- `extract_raises/2` - Extract all raise/reraise expressions from AST
- `extract_throws/2` - Extract all throw expressions from AST
- `extract_exits/2` - Extract all exit expressions from AST

### Raise Patterns Supported

1. Message only: `raise "error"` → message string, nil exception
2. Exception module: `raise RuntimeError` → exception module
3. Exception + message: `raise ArgumentError, "msg"` → both fields
4. Exception + keyword opts: `raise RuntimeError, message: "msg"` → includes attributes
5. Exception struct: `raise %RuntimeError{message: "msg"}` → struct as exception
6. Variable message: `raise msg` → expression in message field
7. Reraise: `reraise e, __STACKTRACE__` → is_reraise=true, stacktrace captured

### Files Modified

- `lib/elixir_ontologies/extractors/exception.ex` - Added structs and extraction functions
- `test/elixir_ontologies/extractors/exception_test.exs` - Added 50 new tests

### Test Coverage

Total exception tests: 34 doctests, 100 tests, 0 failures

New test sections:
- `raise_expression?/1` tests (5)
- `extract_raise/2` tests (11)
- `extract_raise!/2` tests (2)
- `extract_raises/2` tests (4)
- `RaiseExpression struct` tests (1)
- `throw_expression?/1` tests (4)
- `extract_throw/2` tests (4)
- `extract_throw!/2` tests (2)
- `extract_throws/2` tests (3)
- `ThrowExpression struct` tests (1)
- `exit_expression?/1` tests (4)
- `extract_exit/2` tests (4)
- `extract_exit!/2` tests (2)
- `extract_exits/2` tests (3)
- `ExitExpression struct` tests (1)

## Verification

```
mix compile --warnings-as-errors  # Passes
mix credo --strict                # Passes (only pre-existing suggestions)
mix test                          # 34 doctests, 100 tests, 0 failures
```

## Next Task

**17.4.1 Function Call Builder** - Generate RDF triples for function calls. This begins the builder phase for call graph representation in the ontology.
