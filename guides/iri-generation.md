# IRI Generation Guide

**Module**: `ElixirOntologies.IRI`
**File**: `lib/elixir_ontologies/iri.ex`

## Overview

The IRI module generates stable, path-based Internationalized Resource Identifiers (IRIs) for Elixir code elements. IRIs serve as unique identifiers in the RDF knowledge graph, enabling precise references to modules, functions, clauses, and other code constructs.

The IRI scheme reflects Elixir's identity model: functions are identified by the composite key `(Module, Name, Arity)`, and nested elements extend this path hierarchically.

## Design Principles

### 1. Deterministic

The same code element always produces the same IRI. Given `MyApp.Users.get_user/1`, the IRI will be identical across multiple analysis runs, different machines, and over time. This enables:

- Linking knowledge graphs across analyses
- Tracking code evolution through version control
- Caching and incremental updates

### 2. Readable

IRIs mirror the code structure, making them human-understandable:

```
https://example.org/code#MyApp.Users/get_user/1/clause/0/param/0
                         ├─ Module ─┤├─ Name ─┤│ Arity│ Clause│ Param
```

### 3. Reversible

Any IRI can be parsed back into its constituent parts using `IRI.parse/1`:

```elixir
{:ok, parsed} = IRI.parse(~I<https://example.org/code#MyApp/valid?/1>)
# => %{type: :function, module: "MyApp", function: "valid?", arity: 1, base_iri: "..."}
```

### 4. URL-Safe

Special characters in Elixir identifiers (like `?`, `!`, operators) are properly encoded:

| Character | Encoded |
|-----------|---------|
| `?` | `%3F` |
| `!` | `%21` |
| `\|>` | `%7C%3E` |

## IRI Patterns

### Code Elements

| Element | Pattern | Example |
|---------|---------|---------|
| Module | `{base}#ModuleName` | `https://example.org/code#MyApp.Users` |
| Function | `{base}#Module/name/arity` | `https://example.org/code#MyApp.Users/get_user/1` |
| Clause | `{function_iri}/clause/{N}` | `.../get_user/1/clause/0` |
| Parameter | `{clause_iri}/param/{N}` | `.../clause/0/param/0` |
| Type | `{base}#Module/type/name/arity` | `https://example.org/code#MyApp/type/user_t/0` |
| Attribute | `{module_iri}/attribute/{name}[/{index}]` | `.../MyApp/attribute/moduledoc` |

### Anonymous Functions and Closures

| Element | Pattern | Example |
|---------|---------|---------|
| Anonymous Function | `{context_iri}/anon/{N}` | `.../get_user/1/anon/0` |
| Anonymous Clause | `{anon_iri}/clause/{N}` | `.../anon/0/clause/0` |
| Captured Variable | `{anon_iri}/capture/{name}` | `.../anon/0/capture/x` |
| Capture Operator | `{context_iri}/&/{N}` | `.../MyApp/&/0` |

### Module Directives

| Element | Pattern | Example |
|---------|---------|---------|
| Alias | `{module_iri}/alias/{N}` | `.../MyApp/alias/0` |
| Import | `{module_iri}/import/{N}` | `.../MyApp/import/0` |
| Require | `{module_iri}/require/{N}` | `.../MyApp/require/0` |
| Use | `{module_iri}/use/{N}` | `.../MyApp/use/0` |
| Use Option | `{use_iri}/option/{N}` | `.../use/0/option/0` |

### Macros and Metaprogramming

| Element | Pattern | Example |
|---------|---------|---------|
| Macro Invocation | `{base}#Module/invocation/{macro}/{N}` | `.../MyApp/invocation/Logger.debug/0` |
| Quote Block | `{base}#Module/quote/{N}` | `.../MyApp.Macros/quote/0` |
| Unquote | `{quote_iri}/unquote/{N}` | `.../quote/0/unquote/0` |
| Hygiene Violation | `{quote_iri}/hygiene/{N}` | `.../quote/0/hygiene/0` |

### Source Provenance

| Element | Pattern | Example |
|---------|---------|---------|
| File | `{base}#file/{path}` | `https://example.org/code#file/lib/users.ex` |
| Location | `{file_iri}/L{start}-{end}` | `.../users.ex/L10-25` |
| Repository | `{base}#repo/{hash}` | `https://example.org/code#repo/a1b2c3d4` |
| Commit | `{repo_iri}/commit/{sha}` | `.../repo/a1b2c3d4/commit/abc123` |

### OTP Elements

| Element | Pattern | Example |
|---------|---------|---------|
| Supervision Tree | `{base}#tree/{app_name}` | `https://example.org/code#tree/my_app` |
| Child Spec | `{supervisor_iri}/child/{id}/{N}` | `.../MySupervisor/child/worker1/0` |

## Usage Examples

### Basic Usage

```elixir
alias ElixirOntologies.IRI

base = "https://example.org/code#"

# Generate a module IRI
IRI.for_module(base, "MyApp.Users")
#=> ~I<https://example.org/code#MyApp.Users>

# Works with atoms too
IRI.for_module(base, MyApp.Users)
#=> ~I<https://example.org/code#MyApp.Users>

# Generate a function IRI
IRI.for_function(base, "MyApp.Users", "get_user", 1)
#=> ~I<https://example.org/code#MyApp.Users/get_user/1>

# Special characters are automatically escaped
IRI.for_function(base, "MyApp", "valid?", 1)
#=> ~I<https://example.org/code#MyApp/valid%3F/1>
```

### Building Hierarchical IRIs

```elixir
# Start with a function
func_iri = IRI.for_function(base, "MyApp", "process", 2)

# Add a clause (first clause, index 0)
clause_iri = IRI.for_clause(func_iri, 0)
#=> ~I<https://example.org/code#MyApp/process/2/clause/0>

# Add a parameter to the clause
param_iri = IRI.for_parameter(clause_iri, 0)
#=> ~I<https://example.org/code#MyApp/process/2/clause/0/param/0>

# Add an anonymous function within the clause
anon_iri = IRI.for_anonymous_function(clause_iri, 0)
#=> ~I<https://example.org/code#MyApp/process/2/clause/0/anon/0>
```

### Source Location IRIs

```elixir
# Create a file IRI
file_iri = IRI.for_source_file(base, "lib/my_app/users.ex")
#=> ~I<https://example.org/code#file/lib/my_app/users.ex>

# Add a location span (lines 10 to 25)
location_iri = IRI.for_source_location(file_iri, 10, 25)
#=> ~I<https://example.org/code#file/lib/my_app/users.ex/L10-25>
```

### Version Control IRIs

```elixir
# Create a repository IRI (URL is hashed for brevity)
repo_iri = IRI.for_repository(base, "https://github.com/myorg/myapp")
#=> ~I<https://example.org/code#repo/a1b2c3d4>

# Add a specific commit
commit_iri = IRI.for_commit(repo_iri, "abc123def456789")
#=> ~I<https://example.org/code#repo/a1b2c3d4/commit/abc123def456789>
```

## Parsing IRIs

The `parse/1` function decomposes an IRI back into its components:

```elixir
# Parse a function IRI
{:ok, parsed} = IRI.parse(~I<https://example.org/code#MyApp.Users/get_user/1>)
# => %{
#      type: :function,
#      base_iri: "https://example.org/code#",
#      module: "MyApp.Users",
#      function: "get_user",
#      arity: 1
#    }

# Parse a clause IRI
{:ok, parsed} = IRI.parse(~I<https://example.org/code#MyApp/get/1/clause/0>)
# => %{type: :clause, module: "MyApp", function: "get", arity: 1, clause: 0, ...}

# Parse a location IRI
{:ok, parsed} = IRI.parse(~I<https://example.org/code#file/lib/users.ex/L10-25>)
# => %{type: :location, path: "lib/users.ex", start_line: 10, end_line: 25, ...}
```

### Convenience Extractors

```elixir
# Extract just the module name
IRI.module_from_iri(~I<https://example.org/code#MyApp.Users/get_user/1>)
#=> {:ok, "MyApp.Users"}

# Works on clause IRIs too (traverses up the hierarchy)
IRI.module_from_iri(~I<https://example.org/code#MyApp/get/1/clause/0>)
#=> {:ok, "MyApp"}

# Extract function signature
IRI.function_from_iri(~I<https://example.org/code#MyApp/valid%3F/1>)
#=> {:ok, {"MyApp", "valid?", 1}}  # Note: automatically unescaped
```

## Name Escaping

Elixir allows characters in identifiers that are not URL-safe. The module handles this automatically:

```elixir
# Escape special characters
IRI.escape_name("valid?")  #=> "valid%3F"
IRI.escape_name("update!") #=> "update%21"
IRI.escape_name("|>")      #=> "%7C%3E"
IRI.escape_name("normal")  #=> "normal"

# Unescape (reverse operation)
IRI.unescape_name("valid%3F")  #=> "valid?"
IRI.unescape_name("update%21") #=> "update!"
```

Safe characters that do not need encoding: `a-z`, `A-Z`, `0-9`, `_`, `.`, `-`

## Why Stability Matters

### Linking Across Analyses

When analyzing code at different points in time, stable IRIs allow you to link related elements:

```turtle
# Analysis at commit A
<https://example.org/code#MyApp/get_user/1>
    prov:wasGeneratedBy <analysis-A> ;
    :sourceLocation "L10-25" .

# Analysis at commit B (same IRI, different location)
<https://example.org/code#MyApp/get_user/1>
    prov:wasGeneratedBy <analysis-B> ;
    :sourceLocation "L15-30" .
```

### Knowledge Graph Integration

External systems can reference your code elements by IRI:

```turtle
# Documentation system
<https://docs.example.org/api#user-lookup>
    :implementedBy <https://example.org/code#MyApp.Users/get_user/1> .

# Issue tracker
<https://issues.example.org/bug-42>
    :affectsFunction <https://example.org/code#MyApp.Users/get_user/1> .
```

### Caching and Incremental Updates

Stable IRIs enable efficient incremental analysis:

```elixir
# Only re-analyze changed files
changed_modules = get_changed_files()
|> Enum.map(&IRI.for_source_file(base, &1))

# Invalidate cache entries for changed IRIs
Cache.invalidate(changed_modules)
```

## Best Practices

1. **Use a consistent base IRI** for your organization: `https://yourcompany.org/code#`

2. **Prefer atoms for module names** when available: `IRI.for_module(base, MyApp.Users)`

3. **Store the base IRI in configuration** rather than hardcoding it

4. **Use `parse/1` for IRI inspection** rather than string manipulation

5. **Handle encoding automatically** - let the module escape/unescape as needed

## Erlang Module Support

The module supports both Elixir and Erlang-style module names:

```elixir
# Elixir-style (uppercase start)
IRI.for_module(base, "MyApp.Users")
#=> ~I<https://example.org/code#MyApp.Users>

# Erlang-style (lowercase start)
IRI.for_module(base, "gen_server")
#=> ~I<https://example.org/code#gen_server>

IRI.for_function(base, ":erlang", "binary_to_term", 1)
#=> ~I<https://example.org/code#:erlang/binary_to_term/1>
```

## Related Modules

- `ElixirOntologies.Graph` - Uses IRIs as subjects in RDF triples
- `ElixirOntologies.Pipeline` - Generates IRIs during code analysis
- `ElixirOntologies.Utils.IdGenerator` - Generates short hashes for repository IRIs
