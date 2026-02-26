# Phase 25.7: Raise and Throw Expression Integration

**Feature Branch:** `feature/phase-25-7-raise-throw-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.7 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.7 of the expressions plan calls for implementing extraction for raise and throw expressions.

Currently, there are NO `build_raise/3` or `build_throw/3` functions in ControlFlowBuilder. The full implementation needs to be created from scratch, including:
1. Raise expression extraction (message, exception, reraise)
2. Throw expression extraction (thrown value)

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex`

**Status:** Neither `build_raise/3` nor `build_throw/3` exist. These are new implementations.

### RaiseExpression Structure

```elixir
%ElixirOntologies.Extractors.Exception.RaiseExpression{
  exception: atom() | Macro.t() | nil,  # Exception module or struct
  message: String.t() | Macro.t() | nil,  # Message string or expression
  attributes: keyword() | nil,            # Exception attributes
  is_reraise: boolean(),
  stacktrace: Macro.t() | nil,
  location: %{}
}
```

### ThrowExpression Structure

```elixir
%ElixirOntologies.Extractors.Exception.ThrowExpression{
  value: Macro.t(),    # The thrown value
  location: %{}
}
```

---

## Solution Overview

Create `build_raise/3` and `build_throw/3` in ControlFlowBuilder to support full expression extraction for raise and throw expressions.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasCondition` for raise argument | `hasCondition` is the standard property for arguments/expression |
| Use `hasCondition` for throw value | `hasCondition` is the standard property for values |
| Extract exception as atom literal | Exception modules are atoms like RuntimeError |
| Extract message as expression | Message can be string literal or expression |
| Handle reraise specially | reraise has different structure (stacktrace) |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

**Note:** The planning document specifies `hasArgument` and `hasValue` properties, but these do not exist in the ontology. Using `hasCondition` which is the standard property for conditions/arguments/expression values.

---

## Implementation Plan

### Step 1: Implement build_raise/3

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex`

**New function** to build raise expression triples

```elixir
@doc """
Builds RDF triples for a raise expression.

## Parameters

- `raise_expr` - RaiseExpression extraction result
- `context` - Builder context with base IRI
- `opts` - Options:
  - `:containing_function` - IRI fragment of containing function
  - `:index` - Expression index within the function (default: 0)
  - `:expression_builder` - Expression builder for full mode

## Returns

A tuple `{expr_iri, triples}`.
"""
@spec build_raise(RaiseExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_raise(%RaiseExpression{} = raise_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = raise_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.RaiseExpression)
    |> add_raise_argument_triple(expr_iri, raise_expr, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, raise_expr.location)

  {expr_iri, triples}
end
```

### Step 2: Implement raise_iri/3

**New function** to generate raise expression IRI

```elixir
@doc """
Generates an IRI for a raise expression.

## Examples

    iex> ElixirOntologies.Builders.ControlFlowBuilder.raise_iri("https://example.org/code#", "MyApp/foo/1", 0)
    ~I<https://example.org/code#raise/MyApp/foo/1/0>
"""
@spec raise_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
def raise_iri(base_iri, containing_function, index) when is_binary(base_iri) do
  RDF.iri("#{base_iri}raise/#{containing_function}/#{index}")
end

def raise_iri(%RDF.IRI{value: base}, containing_function, index) do
  raise_iri(base, containing_function, index)
end
```

### Step 3: Implement build_throw/3

**New function** to build throw expression triples

```elixir
@doc """
Builds RDF triples for a throw expression.

## Parameters

- `throw_expr` - ThrowExpression extraction result
- `context` - Builder context with base IRI
- `opts` - Options:
  - `:containing_function` - IRI fragment of containing function
  - `:index` - Expression index within the function (default: 0)
  - `:expression_builder` - Expression builder for full mode

## Returns

A tuple `{expr_iri, triples}`.
"""
@spec build_throw(ThrowExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_throw(%ThrowExpression{} = throw_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = throw_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.ThrowExpression)
    |> add_throw_value_triple(expr_iri, throw_expr.value, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, throw_expr.location)

  {expr_iri, triples}
end
```

### Step 4: Implement throw_iri/3

```elixir
@spec throw_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
def throw_iri(base_iri, containing_function, index) when is_binary(base_iri) do
  RDF.iri("#{base_iri}throw/#{containing_function}/#{index}")
end

def throw_iri(%RDF.IRI{value: base}, containing_function, index) do
  throw_iri(base, containing_function, index)
end
```

### Step 5: Implement helper functions

```elixir
# Extract raise argument (message or exception expression)
defp add_raise_argument_triple(triples, expr_iri, raise_expr, expression_builder, build_expressions?, context) do
  if build_expressions? do
    # For raise, we extract the message as the primary expression
    # If there's an exception module, we can add it as an atom
    message_triples =
      if not is_nil(raise_expr.message) do
        case expression_builder.build(raise_expr.message, context, suffix: "message") do
          {:ok, {msg_iri, msg_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), msg_iri)
            msg_triples ++ [link_triple]

          {:ok, {msg_iri, msg_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), msg_iri)
            msg_triples ++ [link_triple]

          :skip ->
            []
        end
      else
        []
      end

    triples ++ message_triples
  else
    triples
  end
end

# Extract throw value
defp add_throw_value_triple(triples, expr_iri, value, expression_builder, build_expressions?, context) do
  if build_expressions? do
    case expression_builder.build(value, context, suffix: "value") do
      {:ok, {value_iri, value_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), value_iri)
        value_triples ++ [link_triple | triples]

      {:ok, {value_iri, value_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), value_iri)
        value_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  else
    triples
  end
end
```

---

## Success Criteria

- [ ] 25.7.1.1: Implement `build_raise/3` in ControlFlowBuilder
- [ ] 25.7.1.2: Match raise AST from RaiseExpression struct
- [ ] 25.7.1.3: Extract exception argument expression
- [ ] 25.7.1.4: Create type triple for RaiseExpression
- [ ] 25.7.1.5: Link argument via `hasCondition` (hasArgument doesn't exist)
- [ ] 25.7.1.6: Handle `raise message` vs `raise Exception, message`
- [ ] 25.7.2.1: Implement `build_throw/3` in ControlFlowBuilder
- [ ] 25.7.2.2: Match throw AST from ThrowExpression struct
- [ ] 25.7.2.3: Extract thrown value expression
- [ ] 25.7.2.4: Create type triple for ThrowExpression
- [ ] 25.7.2.5: Link value via `hasCondition` (hasValue doesn't exist)
- [ ] All 5 unit tests pass

---

## Test Coverage

New tests needed:
1. Test raise expression extraction with message
2. Test raise expression extraction with exception and message
3. Test raise expression extraction with reraise
4. Test throw expression extraction for value
5. Test raise/throw extraction handles complex expressions

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Add `build_raise/3`, `build_throw/3`, IRIs, and helpers |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 5 new tests for raise/throw expression integration |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| New implementations from scratch | Follow patterns from try expression implementation |
| hasArgument/hasValue don't exist | Use `hasCondition` instead |
| Complex raise expressions | Focus on message extraction, exception can be added later |
| Breaking existing tests | All new tests, existing tests unchanged |

---

## Implementation Status

- [x] Planning document complete
- [x] Implementation complete
- [x] Tests passing (5 new tests, all passing)
- [x] Documentation updated
- [x] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-7-raise-throw-expression-integration
