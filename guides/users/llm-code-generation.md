# LLM-Assisted Code Generation with Ontology Knowledge

This guide explains how LLMs can leverage the semantic knowledge graph produced by ElixirOntologies to generate better, more targeted code that fits naturally within an existing codebase.

## Why Ontology-Based Context?

Traditional LLM code generation relies on:
- Raw source files (unstructured text)
- File paths and directory structure
- Comments and documentation

The ontology provides **structured semantic knowledge**:
- Explicit relationships between code elements
- Type constraints and contracts
- Architectural patterns and conventions
- Cross-module dependencies

This structured knowledge enables LLMs to reason about code rather than pattern-match against text.

## Key Insights for Code Generation

### 1. Function Identity and Arity

Elixir functions are identified by `(Module, Name, Arity)`. The ontology makes this explicit:

```turtle
ex:MyModule/process/2 a struct:PublicFunction ;
    struct:functionName "process" ;
    struct:arity "2"^^xsd:nonNegativeInteger ;
    struct:belongsTo ex:MyModule .

ex:MyModule/process/3 a struct:PublicFunction ;
    struct:functionName "process" ;
    struct:arity "3"^^xsd:nonNegativeInteger ;
    struct:belongsTo ex:MyModule .
```

**LLM Benefit**: When generating a call to `process`, the LLM knows both variants exist and can choose the appropriate arity based on available arguments.

### 2. Module Dependencies and Import Patterns

The ontology captures how modules relate:

```turtle
ex:MyController a struct:Module ;
    struct:importsModule ex:MyRepo ;
    struct:aliasesModule ex:MyApp.Accounts.User ;
    struct:usesModule ex:Phoenix.Controller .
```

**LLM Benefit**: When generating code in `MyController`, the LLM knows:
- `Repo` functions are available (imported)
- `User` can be referenced directly (aliased)
- Phoenix controller macros like `action_fallback` are available (used)

### 3. Protocol Contracts

Protocols define polymorphic interfaces:

```turtle
ex:Serializable a struct:Protocol ;
    struct:definesFunction ex:Serializable/serialize/1 ;
    struct:definesFunction ex:Serializable/deserialize/1 .

ex:Serializable_for_User a struct:ProtocolImplementation ;
    struct:implementsProtocol ex:Serializable ;
    struct:forType "User" .
```

**LLM Benefit**: When asked to "make User serializable", the LLM knows exactly which functions to implement and their expected arities.

### 4. Behaviour Callbacks

Behaviours define module contracts:

```turtle
ex:MyWorker a struct:Module ;
    struct:implementsBehaviour ex:GenServer .

ex:GenServer a struct:Behaviour ;
    struct:definesCallback ex:GenServer/init/1 ;
    struct:definesCallback ex:GenServer/handle_call/3 ;
    struct:definesCallback ex:GenServer/handle_cast/2 .
```

**LLM Benefit**: When generating a new GenServer, the LLM knows the required callbacks and their exact signatures.

### 5. Type Specifications

Function specs provide type constraints:

```turtle
ex:calculate/2 a struct:PublicFunction ;
    struct:hasSpec ex:calculate/2_spec .

ex:calculate/2_spec a struct:FunctionSpec ;
    struct:parameterTypes ( ex:IntegerType ex:IntegerType ) ;
    struct:returnType ex:IntegerType .
```

**LLM Benefit**: Generated code will use correct types, avoiding runtime errors and enabling dialyzer compliance.

### 6. Struct Fields and Enforced Keys

Structs define data shapes:

```turtle
ex:User a struct:Struct ;
    struct:hasField ex:User_email ;
    struct:hasField ex:User_name ;
    struct:hasEnforcedKey ex:User_email .

ex:User_email a struct:StructField ;
    struct:fieldName "email" ;
    struct:defaultValue "nil" .
```

**LLM Benefit**: When creating a `%User{}`, the LLM knows `email` is required and what fields are available.

### 7. OTP Supervision Trees

The ontology captures supervision hierarchies:

```turtle
ex:MyApp.Supervisor a otp:Supervisor ;
    otp:supervises ex:MyApp.Repo ;
    otp:supervises ex:MyApp.Cache ;
    otp:strategy "one_for_one" .
```

**LLM Benefit**: When adding a new supervised process, the LLM understands the existing tree structure and restart strategies.

### 8. Function Delegation Patterns

Delegation relationships are explicit:

```turtle
ex:MyFacade/get_user/1 a struct:PublicFunction ;
    struct:delegatesTo ex:MyRepo/get_user/1 .
```

**LLM Benefit**: The LLM can identify facade patterns and maintain consistency when adding new delegated functions.

## Practical Query Patterns

### Find All Public Functions in a Module

```sparql
SELECT ?func ?name ?arity WHERE {
  ?func struct:belongsTo ex:MyModule ;
        a struct:PublicFunction ;
        struct:functionName ?name ;
        struct:arity ?arity .
}
```

### Find Modules That Depend on a Target

```sparql
SELECT ?module WHERE {
  { ?module struct:importsModule ex:TargetModule }
  UNION
  { ?module struct:usesModule ex:TargetModule }
  UNION
  { ?module struct:aliasesModule ex:TargetModule }
}
```

### Find All GenServer Implementations

```sparql
SELECT ?module ?callback WHERE {
  ?module struct:implementsBehaviour otp:GenServer .
  ?module struct:containsFunction ?func .
  ?func struct:functionName ?callback .
  FILTER(?callback IN ("init", "handle_call", "handle_cast", "handle_info"))
}
```

### Find Functions With Missing Specs

```sparql
SELECT ?func ?name WHERE {
  ?func a struct:PublicFunction ;
        struct:functionName ?name .
  FILTER NOT EXISTS { ?func struct:hasSpec ?spec }
}
```

## Context Window Optimization

The ontology enables **selective context loading**:

1. **Relevant modules only**: Instead of loading entire files, load only modules related to the task
2. **Interface-first**: Load function signatures and types without implementation details
3. **Dependency chain**: Trace imports/uses to understand what's available
4. **Pattern matching**: Find similar code patterns across the codebase

### Example: Adding a New API Endpoint

Traditional approach loads entire controller files. With ontology:

```elixir
# Load only what's needed:
# 1. Controller's existing actions (names, arities)
# 2. Context module's public API
# 3. Schema struct fields
# 4. Similar endpoints for pattern matching
```

## Generating Idiomatic Code

### Matching Existing Patterns

The ontology reveals codebase conventions:

```sparql
# Find naming patterns for context functions
SELECT ?name (COUNT(?func) as ?count) WHERE {
  ?func struct:belongsTo ?mod ;
        struct:functionName ?name .
  ?mod struct:moduleName ?modName .
  FILTER(CONTAINS(?modName, "Context"))
}
GROUP BY ?name
ORDER BY DESC(?count)
```

Common patterns emerge: `get_`, `list_`, `create_`, `update_`, `delete_`.

### Understanding Error Handling

```sparql
# Find exception types used in the codebase
SELECT ?exception ?module WHERE {
  ?exception a struct:Exception ;
             struct:belongsTo ?module .
}
```

The LLM can then raise appropriate, project-specific exceptions.

### Matching Documentation Style

```sparql
# Find docstring patterns
SELECT ?func ?doc WHERE {
  ?func a struct:PublicFunction ;
        struct:docstring ?doc .
}
LIMIT 10
```

Generated code can match existing documentation conventions.

## Evolution-Aware Generation

The evolution layer adds temporal context:

```turtle
ex:MyModule_v2 a evo:ModuleVersion ;
    evo:wasRevisionOf ex:MyModule_v1 ;
    prov:wasAttributedTo ex:developer_alice ;
    prov:generatedAtTime "2024-01-15"^^xsd:dateTime .
```

**LLM Benefit**:
- Identify active maintainers for code review suggestions
- Understand recent changes to avoid conflicts
- Match coding style of original authors

## Integration Strategies

### 1. Pre-Generation Analysis

Before generating code, query the ontology to understand:
- Available modules and their purposes
- Function signatures and types
- Existing patterns and conventions
- Dependencies and imports

### 2. Post-Generation Validation

After generating code, validate against:
- SHACL constraints for naming conventions
- Type compatibility with existing specs
- Proper use of available imports
- Correct arity for function calls

### 3. Incremental Context

Start with high-level ontology (modules, relationships), then drill down:
1. Module structure overview
2. Relevant function signatures
3. Type specifications
4. Implementation details (only if needed)

## Example Workflow

**Task**: "Add a `deactivate_user/1` function to the Accounts context"

**Ontology-Informed Steps**:

1. **Query existing patterns**:
   ```sparql
   SELECT ?func ?arity WHERE {
     ?func struct:belongsTo ex:Accounts ;
           struct:functionName ?name .
     FILTER(CONTAINS(?name, "user"))
   }
   ```
   Result: `get_user/1`, `create_user/1`, `update_user/2`, `delete_user/1`

2. **Identify User struct**:
   ```sparql
   SELECT ?field WHERE {
     ex:User struct:hasField ?f .
     ?f struct:fieldName ?field .
   }
   ```
   Result: `id`, `email`, `name`, `active`, `inserted_at`

3. **Check for existing specs**:
   ```sparql
   SELECT ?ret WHERE {
     ex:Accounts/update_user/2 struct:hasSpec ?spec .
     ?spec struct:returnType ?ret .
   }
   ```
   Result: `{:ok, User.t()} | {:error, Ecto.Changeset.t()}`

4. **Generate with full context**:
   ```elixir
   @doc """
   Deactivates a user account.
   """
   @spec deactivate_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
   def deactivate_user(%User{} = user) do
     update_user(user, %{active: false})
   end
   ```

The generated code:
- Follows existing naming conventions (`verb_noun/1`)
- Uses the correct return type pattern
- Leverages existing `update_user/2` function
- Includes documentation matching project style

## Summary

The ontology transforms code generation from pattern-matching against text to reasoning about semantics:

| Aspect | Text-Based | Ontology-Based |
|--------|------------|----------------|
| Function calls | Guess arity from examples | Know exact signatures |
| Imports | Hope they're available | Verify dependencies |
| Types | Infer from usage | Use explicit specs |
| Patterns | Copy similar code | Query for conventions |
| Validation | Runtime errors | Pre-generation checks |

By providing structured knowledge about code relationships, types, and patterns, the ontology enables LLMs to generate code that fits naturally within an existing codebase.
