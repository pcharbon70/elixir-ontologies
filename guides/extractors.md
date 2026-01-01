# Extractors

The Extractors module provides a comprehensive system for analyzing Elixir AST (Abstract Syntax Tree) nodes and extracting structured information about code constructs. Each extractor is purpose-built to recognize and decompose specific Elixir language features into typed structs suitable for ontology population.

## Overview

Extractors transform raw AST nodes into structured data that maps to the Elixir Ontology classes defined in the TTL files. They follow a consistent API pattern making them composable and predictable.

```
Source Code -> AST (via Code.string_to_quoted/1) -> Extractor -> Typed Struct
```

## The Extractor Pattern

Every extractor follows a consistent pattern with these core functions:

### Type Detection Predicates

Each extractor provides one or more predicate functions that identify whether an AST node matches its domain:

```elixir
# Check if AST represents a function definition
Function.function?({:def, [], [{:hello, [], nil}, [do: :ok]]})
# => true

# Check specific function types
Function.guard?({:defguard, [], [{:is_valid, [], [{:x, [], nil}]}]})
# => true

Function.delegate?({:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]})
# => true
```

Predicates return `true` or `false` and are designed for filtering AST nodes.

### Safe Extraction with `extract/2`

The primary extraction function returns a tagged tuple:

```elixir
{:ok, result} = Function.extract(ast)
{:error, reason} = Function.extract(invalid_ast)
```

This pattern enables safe composition with `with` expressions:

```elixir
with {:ok, func} <- Function.extract(func_ast),
     {:ok, spec} <- FunctionSpec.extract(spec_ast) do
  # Both extractions succeeded
  combine(func, spec)
end
```

### Raising Variant with `extract!/2`

For contexts where extraction must succeed:

```elixir
result = Function.extract!(ast)
# Raises ArgumentError if not a valid function
```

### Batch Extraction with `extract_all/1`

Many extractors provide batch extraction from a module body:

```elixir
macros = Macro.extract_all(module_body)
# Returns list of all extracted macros, skipping invalid nodes
```

## Result Structs

Each extractor defines a result struct with typed fields:

```elixir
%ElixirOntologies.Extractors.Function{
  type: :function | :guard | :delegate,
  name: atom(),
  arity: non_neg_integer(),
  min_arity: non_neg_integer(),
  visibility: :public | :private,
  docstring: String.t() | false | nil,
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

Common fields across extractors:

| Field | Type | Description |
|-------|------|-------------|
| `location` | `SourceLocation.t()` | Source line/column information |
| `metadata` | `map()` | Extractor-specific additional data |

## Extractor Categories

### Basic Extractors

#### Function Extractor

Handles `def`, `defp`, `defguard`, `defguardp`, and `defdelegate`:

```elixir
alias ElixirOntologies.Extractors.Function

ast = quote do
  def greet(name \\ "World"), do: "Hello, #{name}"
end

{:ok, func} = Function.extract(ast)
func.name       # => :greet
func.arity      # => 1
func.min_arity  # => 0 (due to default argument)
func.visibility # => :public

Function.has_defaults?(func)  # => true
Function.function_id(func)    # => "greet/1"
```

#### Pattern Extractor

Recognizes all 10 pattern types plus guard clauses:

```elixir
alias ElixirOntologies.Extractors.Pattern

# Variable pattern
{:ok, p} = Pattern.extract({:name, [], Elixir})
p.type                    # => :variable
p.bindings                # => [:name]
p.metadata.variable_name  # => :name

# Struct pattern
ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:n, [], nil}]}]}
{:ok, p} = Pattern.extract(ast)
p.type                # => :struct
p.metadata.struct_name # => [:User]
p.bindings            # => [:n]

# Collect all bindings from complex patterns
Pattern.collect_bindings([{:x, [], nil}, {:_, [], nil}, {:y, [], nil}])
# => [:x, :y]  (wildcards excluded)
```

Pattern types: `:variable`, `:wildcard`, `:pin`, `:literal`, `:tuple`, `:list`, `:map`, `:struct`, `:binary`, `:as`, `:guard`

#### FunctionSpec Extractor

Extracts `@spec`, `@callback`, and `@macrocallback` type specifications.

#### TypeDefinition Extractor

Handles `@type`, `@typep`, and `@opaque` definitions.

#### Struct Extractor

Processes `defstruct` and `defexception` definitions.

#### Attribute Extractor

Extracts module attributes (`@attr value`).

### Control Flow Extractors

#### ControlFlow Extractor

Unified extraction for all control flow constructs:

```elixir
alias ElixirOntologies.Extractors.ControlFlow

# Case expression
ast = {:case, [], [{:x, [], nil}, [do: [
  {:->, [], [[:ok], :success]},
  {:->, [], [[:error], :failure]}
]]]}

{:ok, cf} = ControlFlow.extract(ast)
cf.type         # => :case
cf.condition    # => {:x, [], nil}
length(cf.clauses)  # => 2

# Each clause has patterns, guard, and body
hd(cf.clauses).patterns  # => [:ok]
hd(cf.clauses).body      # => :success
```

Supported types: `:if`, `:unless`, `:case`, `:cond`, `:with`, `:try`, `:receive`, `:raise`, `:throw`

Convenience predicates:
- `ControlFlow.has_else?(result)` - Check for else branch
- `ControlFlow.has_timeout?(result)` - Check receive timeout
- `ControlFlow.has_rescue?(result)` - Check try rescue clause

#### Comprehension Extractor

Specialized for `for` comprehensions:

```elixir
alias ElixirOntologies.Extractors.Comprehension

ast = quote do
  for x <- [1, 2, 3], x > 1, into: %{}, do: {x, x * 2}
end

{:ok, comp} = Comprehension.extract(ast)
length(comp.generators)     # => 1
length(comp.filters)        # => 1
comp.options.into          # => {:%{}, [], []}

# Generator details
gen = hd(comp.generators)
gen.type       # => :generator
gen.pattern    # => {:x, [], _}
gen.enumerable # => [1, 2, 3]
```

#### Guard Extractor

Extracts guard expressions from function clauses.

### Metaprogramming Extractors

#### Macro Extractor

Handles `defmacro` and `defmacrop`:

```elixir
alias ElixirOntologies.Extractors.Macro

ast = {:defmacro, [], [{:unless, [], [{:condition, [], nil}, {:block, [], nil}]},
       [do: {:quote, [], [[do: :ok]]}]]}

{:ok, macro} = Macro.extract(ast)
macro.name        # => :unless
macro.arity       # => 2
macro.visibility  # => :public
macro.is_hygienic # => true (no var! usage detected)

Macro.macro_id(macro)  # => "unless/2"
```

#### Quote Extractor

Analyzes `quote`, `unquote`, and `unquote_splicing` for hygiene tracking.

#### Behaviour Extractor

Extracts `@behaviour` declarations and `@callback` definitions.

#### Protocol Extractor

Handles both protocol definitions and implementations:

```elixir
alias ElixirOntologies.Extractors.Protocol

# Protocol definition
proto_ast = quote do
  defprotocol Stringable do
    @doc "Convert to string"
    def to_string(data)
  end
end

{:ok, proto} = Protocol.extract(proto_ast)
proto.name                     # => [:Stringable]
proto.fallback_to_any          # => false
length(proto.functions)        # => 1
hd(proto.functions).name       # => :to_string

# Protocol implementation
impl_ast = quote do
  defimpl Stringable, for: Integer do
    def to_string(i), do: Integer.to_string(i)
  end
end

{:ok, impl} = Protocol.extract_implementation(impl_ast)
impl.protocol   # => [:Stringable]
impl.for_type   # => [:Integer]
impl.is_any     # => false
```

### Directive Extractors

Located in `ElixirOntologies.Extractors.Directive.*`:

#### Alias Extractor

```elixir
alias ElixirOntologies.Extractors.Directive.Alias

# Simple alias
ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}
{:ok, directive} = Alias.extract(ast)
directive.source      # => [:MyApp, :Users]
directive.as          # => :Users
directive.explicit_as # => false

# With explicit as:
ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}, [as: {:__aliases__, [], [:U]}]]}
{:ok, directive} = Alias.extract(ast)
directive.as          # => :U
directive.explicit_as # => true

# Multi-alias expansion
ast = # alias MyApp.{Users, Accounts}
{:ok, directives} = Alias.extract_multi_alias(ast)
# Returns list of individual AliasDirective structs
```

Similar extractors exist for `Import`, `Require`, and `Use` directives.

### OTP Extractors

Located in `ElixirOntologies.Extractors.OTP.*`:

#### GenServer Extractor

Detects and analyzes GenServer implementations:

```elixir
alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor

# Check if module uses GenServer
body = # module body with `use GenServer`
GenServerExtractor.genserver?(body)  # => true

# Extract implementation details
{:ok, gs} = GenServerExtractor.extract(body)
gs.detection_method  # => :use or :behaviour
gs.use_options       # => [restart: :transient] or nil

# Extract callbacks
callbacks = GenServerExtractor.extract_callbacks(body)
# Returns list of Callback structs for init, handle_call, etc.

init_cb = Enum.find(callbacks, & &1.type == :init)
init_cb.arity    # => 1
init_cb.clauses  # => number of function clauses
init_cb.has_impl # => true if @impl annotation present
```

Other OTP extractors: `Supervisor`, `Agent`, `Task`, `ETS`, `Application`

### Evolution Extractors

Located in `ElixirOntologies.Extractors.Evolution.*`:

These extractors support the PROV-O based evolution tracking layer:

- **Activity** - Tracks development activities
- **Agent** - Developer/tool attribution
- **Deprecation** - `@deprecated` annotations
- **Commit/FileHistory** - Git integration
- **Refactoring** - Tracks code transformations

## The Helpers Module

`ElixirOntologies.Extractors.Helpers` provides shared utilities:

```elixir
alias ElixirOntologies.Extractors.Helpers

# Location extraction
location = Helpers.extract_location({:def, [line: 5, column: 3], []})
# => %SourceLocation{start_line: 5, start_column: 3}

# Conditional location (respects opts)
Helpers.extract_location_if(node, include_location: true)

# Body normalization
Helpers.normalize_body({:__block__, [], [:a, :b]})  # => [:a, :b]
Helpers.normalize_body(nil)                          # => []
Helpers.normalize_body(:single)                      # => [:single]

# Extract do block body
Helpers.extract_do_body([do: {:__block__, [], [:a, :b]}])  # => [:a, :b]

# Guard combination
guards = [{:is_integer, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]
Helpers.combine_guards(guards)
# => {:and, [], [first_guard, second_guard]}

# Error formatting with truncation
Helpers.format_error("Not a pattern", large_ast_node)

# Special form detection
Helpers.special_form?(:def)           # => true
Helpers.special_form?(:my_function)   # => false

# Module AST conversion
Helpers.module_ast_to_atom({:__aliases__, [], [:MyApp, :Users]})
# => MyApp.Users
```

## Composing Extractors

Extractors are designed to work together:

```elixir
defmodule ModuleAnalyzer do
  alias ElixirOntologies.Extractors.{Function, Macro, Protocol, ControlFlow}
  alias ElixirOntologies.Extractors.Helpers

  def analyze(module_body) do
    statements = Helpers.normalize_body(module_body)

    %{
      functions: extract_where(statements, &Function.function?/1, &Function.extract/1),
      macros: extract_where(statements, &Macro.macro?/1, &Macro.extract/1),
      protocols: extract_where(statements, &Protocol.protocol?/1, &Protocol.extract/1),
      control_flow: find_control_flow(statements)
    }
  end

  defp extract_where(statements, predicate, extractor) do
    statements
    |> Enum.filter(predicate)
    |> Enum.map(fn node ->
      case extractor.(node) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp find_control_flow(statements) do
    # Walk AST to find all control flow expressions
    {_, results} = Macro.prewalk(statements, [], fn
      node, acc ->
        if ControlFlow.control_flow?(node) do
          case ControlFlow.extract(node) do
            {:ok, cf} -> {node, [cf | acc]}
            _ -> {node, acc}
          end
        else
          {node, acc}
        end
    end)

    Enum.reverse(results)
  end
end
```

## Error Handling

Extractors use tagged tuples for explicit error handling:

```elixir
case Function.extract(unknown_ast) do
  {:ok, func} ->
    process_function(func)

  {:error, reason} ->
    Logger.warning("Skipping invalid function: #{reason}")
end
```

Error messages include truncated AST representation for debugging:

```elixir
{:error, "Not a function definition: {:defmodule, [], [...]}"}
```

## Location Tracking

All extractors support location extraction from AST metadata:

```elixir
# Locations require line metadata in AST
code = """
def hello, do: :world
"""

{:ok, ast} = Code.string_to_quoted(code, columns: true)
{:ok, func} = Function.extract(ast)

func.location
# => %SourceLocation{start_line: 1, start_column: 1, end_line: nil, end_column: nil}
```

Control location extraction with options:

```elixir
Function.extract(ast, include_location: false)
# location field will be nil
```

## Metadata Fields

The `metadata` field contains extractor-specific information:

```elixir
# Function metadata
func.metadata
# => %{
#   module: [:MyApp, :Greeter],
#   doc_hidden: false,
#   spec: nil,
#   has_guard: true,
#   default_args: 1,
#   line: 5
# }

# Protocol metadata
proto.metadata
# => %{
#   function_count: 3,
#   has_doc: true,
#   has_typedoc: false,
#   line: 1
# }

# Comprehension metadata
comp.metadata
# => %{
#   generator_count: 2,
#   filter_count: 1,
#   has_into: true,
#   has_reduce: false,
#   has_uniq: false
# }
```

## Best Practices

1. **Use predicates first** - Filter with `function?/1` before calling `extract/1`
2. **Handle errors** - Use `{:ok, _}` / `{:error, _}` pattern matching
3. **Prefer `extract_all/1`** - When processing module bodies, batch extraction handles filtering
4. **Check metadata** - Additional context often lives in the metadata map
5. **Compose extractors** - Build analysis pipelines combining multiple extractors

## Mapping to Ontology Classes

Extractors produce structs that map to ontology classes:

| Extractor | Ontology Class | TTL File |
|-----------|----------------|----------|
| Function | `Function`, `PublicFunction`, `PrivateFunction` | elixir-structure.ttl |
| Macro | `Macro`, `PublicMacro`, `PrivateMacro` | elixir-structure.ttl |
| Protocol | `Protocol`, `ProtocolImplementation` | elixir-structure.ttl |
| Pattern | `Pattern` subclasses | elixir-core.ttl |
| ControlFlow | `ControlFlowExpression` subclasses | elixir-core.ttl |
| Comprehension | `Comprehension` | elixir-core.ttl |
| GenServer | `GenServerImplementation` | elixir-otp.ttl |
| Supervisor | `SupervisorModule` | elixir-otp.ttl |

See the ontology TTL files for complete class definitions and properties.
