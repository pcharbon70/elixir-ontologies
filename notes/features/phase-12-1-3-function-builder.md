# Phase 12.1.3: Function Builder Planning Document

## 1. Problem Statement

Phase 12.1.1 established the builder infrastructure (BuilderContext and Helpers), and Phase 12.1.2 implemented the Module Builder. Now we need to implement the Function Builder to transform Function extractor results into RDF triples.

**The Challenge**: The Function extractor (`ElixirOntologies.Extractors.Function`) produces rich structured data about Elixir functions, but this data needs to be converted to RDF triples that conform to the `elixir-structure.ttl` ontology.

**Current State**:
- Function extractor produces `Function.t()` structs with:
  - Function type (`:function`, `:guard`, `:delegate`)
  - Function name and arity (with min_arity for default parameters)
  - Visibility (`:public`, `:private`)
  - Documentation and metadata
  - Source location information
  - Delegate target information (for delegated functions)
- Module Builder generates `containsFunction` triples linking modules to functions
- Builder infrastructure exists but no function-specific builder

**The Gap**: We need to:
1. Generate IRIs for functions following the `base#Module/name/arity` pattern
2. Create `rdf:type` triples for Function classes (Function, PublicFunction, PrivateFunction, GuardFunction, DelegatedFunction)
3. Build datatype properties (functionName, arity, minArity)
4. Build the `belongsTo` object property linking function to module
5. Generate inverse `containsFunction` triple for the module
6. Handle function visibility (public/private)
7. Handle delegated functions with `delegatesTo` property
8. Add function documentation if present
9. Add source location information

## 2. Solution Overview

Create a **Function Builder** that transforms `Function.t()` structs into RDF triples.

### 2.1 Core Functionality

The builder will:
- Generate stable IRIs for functions using `IRI.for_function/4` (base_iri, module, name, arity)
- Determine correct function class based on type and visibility
- Build all required triples for function representation
- Handle optional elements (documentation, location, delegation)
- Create bidirectional relationship between function and module
- Support guard functions and delegated functions

### 2.2 Builder Pattern

Following the established pattern from Module Builder:

```elixir
def build(function_info, context) do
  # Generate function IRI
  function_iri = generate_function_iri(function_info, context)

  # Build all triples
  triples =
    [
      # Core function triples
      build_type_triple(function_iri, function_info),
      build_name_triple(function_iri, function_info),
      build_arity_triple(function_iri, function_info)
    ] ++
      build_min_arity_triple(function_iri, function_info) ++
      build_belongs_to_triple(function_iri, function_info, context) ++
      build_docstring_triple(function_iri, function_info) ++
      build_delegate_triple(function_iri, function_info, context) ++
      build_location_triple(function_iri, function_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {function_iri, triples}
end
```

### 2.3 Integration Point

The Function Builder will be called from Module Builder or a higher-level orchestrator for complete module RDF generation.

## 3. Technical Details

### 3.1 Function Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/function.ex`:

```elixir
%ElixirOntologies.Extractors.Function{
  # Function classification
  type: :function | :guard | :delegate,

  # Identity components (Module, Name, Arity)
  name: atom(),                               # e.g., :get_user, :valid?, :create!
  arity: non_neg_integer(),                   # Total parameters
  min_arity: non_neg_integer(),               # Minimum arity with defaults

  # Visibility
  visibility: :public | :private,

  # Documentation
  docstring: String.t() | false | nil,        # "Gets a user" | false | nil

  # Source location
  location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    module: [atom()] | nil,                   # e.g., [:MyApp, :Users]
    doc_hidden: boolean(),                    # @doc false
    spec: term(),                             # @spec AST (not used in Phase 12.1.3)
    has_guard: boolean(),                     # Has when clause
    default_args: non_neg_integer(),          # Number of default params
    delegates_to: {module(), atom(), arity()} | nil,  # For defdelegate
    line: pos_integer() | nil                 # Source line number
  }
}
```

**Key Points**:
- Module name is in `metadata.module` (list of atoms)
- `arity` is total arity, `min_arity` accounts for defaults
- `delegates_to` contains `{target_module, target_function, target_arity}`
- Function type determines RDF class (function vs guard vs delegate)
- Visibility determines PublicFunction vs PrivateFunction subclass

### 3.2 IRI Generation Patterns

Using `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`:

| Function Type | Example | IRI Pattern | Output |
|--------------|---------|-------------|--------|
| Regular function | `get_user/1` in `MyApp.Users` | `base#Module/name/arity` | `base#MyApp.Users/get_user/1` |
| Function with special chars | `valid?/1` in `MyApp` | `base#Module/escaped_name/arity` | `base#MyApp/valid%3F/1` |
| Zero-arity function | `hello/0` in `Greeter` | `base#Module/name/arity` | `base#Greeter/hello/0` |
| Private function | `internal/2` in `Utils` | `base#Module/name/arity` | `base#Utils/internal/2` |

**Module Name Conversion** (from metadata):
```elixir
# From metadata module list to string
metadata.module = [:MyApp, :Users] -> "MyApp.Users"

# Helper function
defp module_name_string(module) when is_list(module) do
  Enum.join(module, ".")
end
```

**Function IRI Generation**:
```elixir
# Using IRI module
module_name = module_name_string(function_info.metadata.module)
IRI.for_function(context.base_iri, module_name, function_info.name, function_info.arity)
#=> ~I<https://example.org/code#MyApp.Users/get_user/1>
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Classes

```turtle
:Function a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "Elixir function with (Module, Name, Arity) identity" ;
    owl:hasKey ( :belongsTo :functionName :arity ) .

:PublicFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "Public function defined with def" .

:PrivateFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "Private function defined with defp" .

:GuardFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "Guard function defined with defguard or defguardp" .

:DelegatedFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "Function that delegates to another module's function" .
```

**Class Selection Logic**:
```elixir
defp determine_function_class(function_info) do
  case {function_info.type, function_info.visibility} do
    {:guard, :public} -> Structure.GuardFunction
    {:guard, :private} -> Structure.GuardFunction
    {:delegate, _} -> Structure.DelegatedFunction
    {:function, :public} -> Structure.PublicFunction
    {:function, :private} -> Structure.PrivateFunction
  end
end
```

#### Object Properties

```turtle
:belongsTo a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :Function ;
    rdfs:range :Module ;
    rdfs:comment "Function belongs to a module (functional - exactly one module)" .

:containsFunction a owl:ObjectProperty ;
    rdfs:domain :Module ;
    rdfs:range :Function ;
    owl:inverseOf :belongsTo ;
    rdfs:comment "Module contains functions (inverse of belongsTo)" .

:delegatesTo a owl:ObjectProperty ;
    rdfs:domain :DelegatedFunction ;
    rdfs:range :Function ;
    rdfs:comment "Delegated function delegates to target function" .
```

**Important**: The `containsFunction` inverse triple should be generated by the Function Builder to maintain consistency.

#### Data Properties

```turtle
:functionName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Function ;
    rdfs:range xsd:string ;
    rdfs:comment "Function name as string" .

:arity a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Function ;
    rdfs:range xsd:nonNegativeInteger ;
    rdfs:comment "Function arity (number of parameters) - part of identity" .

:minArity a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Function ;
    rdfs:range xsd:nonNegativeInteger ;
    rdfs:comment "Minimum arity when default arguments create multiple arities" .
```

**Note**: `minArity` is only added if different from `arity`.

### 3.4 Triple Generation Examples

**Simple Public Function**:
```turtle
<base#MyApp/hello/0> a struct:PublicFunction ;
    struct:functionName "hello"^^xsd:string ;
    struct:arity "0"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp> ;
    core:hasSourceLocation <base#file/lib/my_app.ex/L5-7> .

<base#MyApp> struct:containsFunction <base#MyApp/hello/0> .
```

**Function with Documentation**:
```turtle
<base#MyApp.Users/get_user/1> a struct:PublicFunction ;
    struct:functionName "get_user"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Users> ;
    struct:docstring "Retrieves a user by ID"^^xsd:string ;
    core:hasSourceLocation <base#file/lib/users.ex/L20-25> .

<base#MyApp.Users> struct:containsFunction <base#MyApp.Users/get_user/1> .
```

**Private Function**:
```turtle
<base#MyApp/internal_helper/2> a struct:PrivateFunction ;
    struct:functionName "internal_helper"^^xsd:string ;
    struct:arity "2"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp> .

<base#MyApp> struct:containsFunction <base#MyApp/internal_helper/2> .
```

**Function with Default Parameters**:
```turtle
<base#MyApp/greet/1> a struct:PublicFunction ;
    struct:functionName "greet"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:minArity "0"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp> .
```

**Guard Function**:
```turtle
<base#MyApp/is_valid/1> a struct:GuardFunction ;
    struct:functionName "is_valid"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp> .
```

**Delegated Function**:
```turtle
<base#MyApp.Users/list_all/0> a struct:DelegatedFunction ;
    struct:functionName "list_all"^^xsd:string ;
    struct:arity "0"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Users> ;
    struct:delegatesTo <base#MyApp.Accounts/list/0> .

<base#MyApp.Accounts/list/0> a struct:PublicFunction ;
    struct:functionName "list"^^xsd:string ;
    struct:arity "0"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp.Accounts> .
```

**Function with Special Characters**:
```turtle
<base#MyApp/valid%3F/1> a struct:PublicFunction ;
    struct:functionName "valid?"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#MyApp> .
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple
Helpers.type_triple(function_iri, Structure.PublicFunction)
#=> {function_iri, RDF.type(), ~I<https://w3id.org/elixir-code/structure#PublicFunction>}

# Datatype property (string)
Helpers.datatype_property(function_iri, Structure.functionName(), "get_user", RDF.XSD.String)
#=> {function_iri, Structure.functionName(), RDF.XSD.String.new("get_user")}

# Datatype property (integer)
Helpers.datatype_property(function_iri, Structure.arity(), 1, RDF.XSD.NonNegativeInteger)
#=> {function_iri, Structure.arity(), RDF.XSD.NonNegativeInteger.new(1)}

# Object property
Helpers.object_property(function_iri, Structure.belongsTo(), module_iri)
#=> {function_iri, Structure.belongsTo(), module_iri}
```

### 3.6 Handling Edge Cases

#### Missing Module Information

```elixir
defp build_belongs_to_triple(function_iri, function_info, context) do
  case function_info.metadata.module do
    nil ->
      # Log warning: function without module context
      []

    module_name_list ->
      module_name = module_name_string(module_name_list)
      module_iri = IRI.for_module(context.base_iri, module_name)

      [
        # Function -> Module
        Helpers.object_property(function_iri, Structure.belongsTo(), module_iri),
        # Module -> Function (inverse)
        Helpers.object_property(module_iri, Structure.containsFunction(), function_iri)
      ]
  end
end
```

#### Documentation Handling

```elixir
defp build_docstring_triple(function_iri, function_info) do
  case function_info.docstring do
    nil ->
      []

    false ->
      # @doc false - intentionally hidden, no triple
      []

    doc when is_binary(doc) ->
      [Helpers.datatype_property(function_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end
```

#### Delegate Target

```elixir
defp build_delegate_triple(function_iri, function_info, context) do
  case function_info.metadata.delegates_to do
    nil ->
      []

    {target_module, target_function, target_arity} ->
      # Generate IRI for target function
      target_module_name = module_atom_to_string(target_module)
      target_iri = IRI.for_function(
        context.base_iri,
        target_module_name,
        target_function,
        target_arity
      )

      [Helpers.object_property(function_iri, Structure.delegatesTo(), target_iri)]
  end
end

defp module_atom_to_string(module) when is_atom(module) do
  module
  |> Atom.to_string()
  |> String.replace_prefix("Elixir.", "")
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Function Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/function_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build/2` function signature
3. Add helper functions for name conversion
4. Import necessary namespaces (Helpers, IRI, Structure, Core)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.FunctionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir functions.

  This module transforms `ElixirOntologies.Extractors.Function` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Function and subclass types (PublicFunction, PrivateFunction, GuardFunction, DelegatedFunction)
  - Function identity (belongsTo, functionName, arity)
  - Default parameters (minArity)
  - Function delegation (delegatesTo)
  - Function documentation (docstring)
  - Source location information

  ## Usage

      alias ElixirOntologies.Builders.{FunctionBuilder, Context}
      alias ElixirOntologies.Extractors.Function

      function_info = %Function{
        type: :function,
        name: :get_user,
        arity: 1,
        visibility: :public,
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # function_iri => ~I<https://example.org/code#MyApp.Users/get_user/1>
      # triples => [
      #   {function_iri, RDF.type(), Structure.PublicFunction},
      #   {function_iri, Structure.functionName(), "get_user"},
      #   ...
      # ]
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Function, as: FunctionExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a function.

  Takes a function extraction result and builder context, returns the function IRI
  and a list of RDF triples representing the function in the ontology.

  ## Parameters

  - `function_info` - Function extraction result from `Extractors.Function.extract/1`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{function_iri, triples}` where:
  - `function_iri` - The IRI of the function
  - `triples` - List of RDF triples describing the function

  ## Examples

      iex> alias ElixirOntologies.Builders.{FunctionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Function
      iex> function_info = %Function{
      ...>   type: :function,
      ...>   name: :hello,
      ...>   arity: 0,
      ...>   min_arity: 0,
      ...>   visibility: :public,
      ...>   docstring: "Says hello",
      ...>   location: nil,
      ...>   metadata: %{module: [:Greeter]}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {function_iri, triples} = FunctionBuilder.build(function_info, context)
      iex> to_string(function_iri)
      "https://example.org/code#Greeter/hello/0"
  """
  @spec build(FunctionExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(function_info, context)

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  defp generate_function_iri(function_info, context)
  defp build_type_triple(function_iri, function_info)
  defp build_name_triple(function_iri, function_info)
  defp build_arity_triple(function_iri, function_info)
  defp build_min_arity_triple(function_iri, function_info)
  defp build_belongs_to_triple(function_iri, function_info, context)
  defp build_docstring_triple(function_iri, function_info)
  defp build_delegate_triple(function_iri, function_info, context)
  defp build_location_triple(function_iri, function_info, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp module_name_string(name_list)
  defp module_atom_to_string(module_atom)
  defp determine_function_class(function_info)
end
```

### 4.2 Step 2: Implement Core Triple Generation (2 hours)

Implement functions for basic function triples:

1. **IRI Generation**:
```elixir
defp generate_function_iri(function_info, context) do
  module_name = module_name_string(function_info.metadata.module)
  IRI.for_function(context.base_iri, module_name, function_info.name, function_info.arity)
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(function_iri, function_info) do
  class = determine_function_class(function_info)
  Helpers.type_triple(function_iri, class)
end

defp determine_function_class(function_info) do
  case {function_info.type, function_info.visibility} do
    {:guard, _} -> Structure.GuardFunction
    {:delegate, _} -> Structure.DelegatedFunction
    {:function, :public} -> Structure.PublicFunction
    {:function, :private} -> Structure.PrivateFunction
  end
end
```

3. **Name Property**:
```elixir
defp build_name_triple(function_iri, function_info) do
  function_name = Atom.to_string(function_info.name)
  Helpers.datatype_property(function_iri, Structure.functionName(), function_name, RDF.XSD.String)
end
```

4. **Arity Property**:
```elixir
defp build_arity_triple(function_iri, function_info) do
  Helpers.datatype_property(function_iri, Structure.arity(), function_info.arity, RDF.XSD.NonNegativeInteger)
end
```

5. **Min Arity Property** (conditional):
```elixir
defp build_min_arity_triple(function_iri, function_info) do
  # Only add minArity if different from arity (indicates default parameters)
  if function_info.min_arity < function_info.arity do
    [Helpers.datatype_property(function_iri, Structure.minArity(), function_info.min_arity, RDF.XSD.NonNegativeInteger)]
  else
    []
  end
end
```

### 4.3 Step 3: Implement Module Relationship (1.5 hours)

Handle belongsTo and containsFunction relationships:

```elixir
defp build_belongs_to_triple(function_iri, function_info, context) do
  case function_info.metadata.module do
    nil ->
      # Function without module context - log warning and skip
      []

    module_name_list ->
      module_name = module_name_string(module_name_list)
      module_iri = IRI.for_module(context.base_iri, module_name)

      [
        # Function -> Module relationship
        Helpers.object_property(function_iri, Structure.belongsTo(), module_iri),
        # Module -> Function relationship (inverse)
        Helpers.object_property(module_iri, Structure.containsFunction(), function_iri)
      ]
  end
end

# Convert module name list to string
defp module_name_string(nil), do: raise "Function must have module context"
defp module_name_string(name_list) when is_list(name_list) do
  Enum.join(name_list, ".")
end
```

### 4.4 Step 4: Implement Documentation Handling (0.5 hours)

Add docstring triple if present:

```elixir
defp build_docstring_triple(function_iri, function_info) do
  case function_info.docstring do
    nil ->
      []

    false ->
      # @doc false - intentionally hidden
      []

    doc when is_binary(doc) ->
      [Helpers.datatype_property(function_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end
```

### 4.5 Step 5: Implement Delegate Handling (1 hour)

Handle delegatesTo for delegated functions:

```elixir
defp build_delegate_triple(function_iri, function_info, context) do
  case function_info.metadata.delegates_to do
    nil ->
      []

    {target_module, target_function, target_arity} ->
      # Convert target module atom to string
      target_module_name = module_atom_to_string(target_module)

      # Generate target function IRI
      target_iri = IRI.for_function(
        context.base_iri,
        target_module_name,
        target_function,
        target_arity
      )

      [Helpers.object_property(function_iri, Structure.delegatesTo(), target_iri)]
  end
end

# Convert module atom to string (handles Elixir. prefix)
defp module_atom_to_string(module) when is_atom(module) do
  module
  |> Atom.to_string()
  |> String.replace_prefix("Elixir.", "")
end
```

### 4.6 Step 6: Implement Location Handling (1 hour)

Add source location triples if present:

```elixir
defp build_location_triple(function_iri, function_info, context) do
  case {function_info.location, context.file_path} do
    {nil, _} ->
      []

    {_location, nil} ->
      # Location exists but no file path in context
      []

    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)

      # Need end line - use start line if end not available
      end_line = location.end_line || location.start_line

      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

      [Helpers.object_property(function_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.7 Step 7: Integrate All Components (1 hour)

Complete the main `build/2` function:

```elixir
@spec build(FunctionExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build(function_info, context) do
  # Generate function IRI
  function_iri = generate_function_iri(function_info, context)

  # Build all triples
  triples =
    [
      # Core function triples (always present)
      build_type_triple(function_iri, function_info),
      build_name_triple(function_iri, function_info),
      build_arity_triple(function_iri, function_info)
    ] ++
      # Optional/conditional triples
      build_min_arity_triple(function_iri, function_info) ++
      build_belongs_to_triple(function_iri, function_info, context) ++
      build_docstring_triple(function_iri, function_info) ++
      build_delegate_triple(function_iri, function_info, context) ++
      build_location_triple(function_iri, function_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {function_iri, triples}
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/function_builder_test.exs`)

**Target**: 25+ comprehensive tests covering all scenarios

#### Test Categories

1. **Basic Function Building** (3 tests):
   - Simple public function with minimal data
   - Function with all optional fields populated
   - Function with nil module (error handling)

2. **Function Types** (5 tests):
   - Public function (def) → PublicFunction
   - Private function (defp) → PrivateFunction
   - Public guard (defguard) → GuardFunction
   - Private guard (defguardp) → GuardFunction
   - Delegated function (defdelegate) → DelegatedFunction

3. **Documentation Handling** (3 tests):
   - Function with documentation string
   - Function with @doc false
   - Function with nil documentation

4. **Arity Handling** (4 tests):
   - Zero-arity function
   - Function with arity > 0
   - Function with default parameters (arity != min_arity)
   - Function with all default parameters (min_arity = 0)

5. **Module Relationships** (3 tests):
   - belongsTo triple generation
   - containsFunction inverse triple generation
   - Both triples present in output

6. **Delegation** (3 tests):
   - Delegated function with target
   - delegatesTo triple generation
   - Target IRI format validation

7. **Source Location** (3 tests):
   - Function with location information
   - Function without location (nil)
   - Function with location but no file path in context

8. **Special Characters** (2 tests):
   - Function names with ? (valid?)
   - Function names with ! (create!)

9. **IRI Generation** (3 tests):
   - Verify correct IRI format for simple functions
   - Verify IRI escaping for special characters
   - Verify IRI format for nested modules

10. **Triple Validation** (3 tests):
    - Verify all expected triples are generated
    - Verify no duplicate triples
    - Verify triple count for different scenarios

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.FunctionBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{FunctionBuilder, Context}
  alias ElixirOntologies.Extractors.Function
  alias ElixirOntologies.NS.Structure
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest FunctionBuilder

  describe "build/2 basic function" do
    test "builds minimal public function" do
      function_info = %Function{
        type: :function,
        name: :hello,
        arity: 0,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:Greeter]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Verify IRI format
      assert to_string(function_iri) == "https://example.org/code#Greeter/hello/0"

      # Verify type triple
      assert {function_iri, RDF.type(), Structure.PublicFunction} in triples

      # Verify name triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.functionName() and
                   RDF.Literal.value(obj) == "hello"

               _ ->
                 false
             end)

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and
                   RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)

      # Should have at least type, name, arity, belongsTo, containsFunction
      assert length(triples) >= 5
    end

    test "builds function with all fields" do
      function_info = %Function{
        type: :function,
        name: :get_user,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: "Retrieves a user by ID",
        location: %SourceLocation{
          start_line: 10,
          start_column: 3,
          end_line: 15,
          end_column: 5
        },
        metadata: %{module: [:MyApp, :Users]}
      }

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/users.ex")

      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should have many triples
      assert length(triples) > 5

      # Verify docstring
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Retrieves a user by ID"

               _ ->
                 false
             end)

      # Verify location
      assert Enum.any?(triples, fn
               {^function_iri, pred, _obj} ->
                 pred == NS.Core.hasSourceLocation()

               _ ->
                 false
             end)
    end
  end

  describe "build/2 function types" do
    test "builds private function with PrivateFunction type" do
      function_info = %Function{
        type: :function,
        name: :internal_helper,
        arity: 2,
        min_arity: 2,
        visibility: :private,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.PrivateFunction} in triples
    end

    test "builds guard function with GuardFunction type" do
      function_info = %Function{
        type: :guard,
        name: :is_valid,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.GuardFunction} in triples
    end

    test "builds delegated function with DelegatedFunction type" do
      function_info = %Function{
        type: :delegate,
        name: :list_all,
        arity: 0,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{
          module: [:MyApp, :Users],
          delegates_to: {MyApp.Accounts, :list, 0}
        }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      assert {function_iri, RDF.type(), Structure.DelegatedFunction} in triples
    end
  end

  describe "build/2 arity handling" do
    test "builds function with default parameters (minArity < arity)" do
      function_info = %Function{
        type: :function,
        name: :greet,
        arity: 1,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:Greeter]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should have both arity and minArity
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.arity() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.minArity() and RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)
    end

    test "does not add minArity when equal to arity" do
      function_info = %Function{
        type: :function,
        name: :get,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {_function_iri, triples} = FunctionBuilder.build(function_info, context)

      # Should not have minArity triple
      refute Enum.any?(triples, fn
               {_, pred, _} -> pred == Structure.minArity()
             end)
    end
  end

  describe "build/2 module relationships" do
    test "generates belongsTo triple" do
      function_info = %Function{
        type: :function,
        name: :foo,
        arity: 0,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      module_iri = ~I<https://example.org/code#MyApp>
      assert {function_iri, Structure.belongsTo(), module_iri} in triples
    end

    test "generates inverse containsFunction triple" do
      function_info = %Function{
        type: :function,
        name: :bar,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      module_iri = ~I<https://example.org/code#MyApp>
      assert {module_iri, Structure.containsFunction(), function_iri} in triples
    end
  end

  describe "build/2 delegation" do
    test "generates delegatesTo triple" do
      function_info = %Function{
        type: :delegate,
        name: :get_all,
        arity: 0,
        min_arity: 0,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{
          module: [:MyApp],
          delegates_to: {OtherModule, :fetch_all, 0}
        }
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      target_iri = ~I<https://example.org/code#OtherModule/fetch_all/0>
      assert {function_iri, Structure.delegatesTo(), target_iri} in triples
    end
  end

  describe "build/2 special characters" do
    test "handles function names with question mark" do
      function_info = %Function{
        type: :function,
        name: :valid?,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, triples} = FunctionBuilder.build(function_info, context)

      # IRI should have escaped question mark
      assert to_string(function_iri) == "https://example.org/code#MyApp/valid%3F/1"

      # Function name should be unescaped in literal
      assert Enum.any?(triples, fn
               {^function_iri, pred, obj} ->
                 pred == Structure.functionName() and
                   RDF.Literal.value(obj) == "valid?"

               _ ->
                 false
             end)
    end

    test "handles function names with exclamation mark" do
      function_info = %Function{
        type: :function,
        name: :create!,
        arity: 1,
        min_arity: 1,
        visibility: :public,
        docstring: nil,
        location: nil,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {function_iri, _triples} = FunctionBuilder.build(function_info, context)

      # IRI should have escaped exclamation mark
      assert to_string(function_iri) == "https://example.org/code#MyApp/create%21/1"
    end
  end
end
```

### 5.3 Property-Based Tests

Use StreamData for:
- Generating valid function names (including special characters)
- Testing IRI consistency across multiple builds
- Verifying no duplicate triples
- Testing with various arity values

### 5.4 Integration Tests

Test the complete flow from extractor to builder:
```elixir
test "integration: extract and build real function" do
  ast = quote do
    def get_user(id) do
      # ... implementation
    end
  end

  # Extract
  {:ok, function_info} = Function.extract(ast, module: [:MyApp, :Users])

  # Build
  context = Context.new(base_iri: "https://example.org/code#")
  {function_iri, triples} = FunctionBuilder.build(function_info, context)

  # Verify complete graph
  assert length(triples) >= 5
  # ... more assertions
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `FunctionBuilder` module exists with complete documentation
2. ✅ `build/2` function correctly transforms `Function.t()` to RDF triples
3. ✅ All function classes are correctly assigned (PublicFunction, PrivateFunction, GuardFunction, DelegatedFunction)
4. ✅ All datatype properties are correctly generated (functionName, arity, minArity)
5. ✅ All object properties are correctly generated (belongsTo, delegatesTo)
6. ✅ Inverse containsFunction triple is generated for module
7. ✅ Function visibility is correctly mapped to classes
8. ✅ Delegated functions generate delegatesTo triples
9. ✅ Documentation is added when present
10. ✅ Source location information is added when available
11. ✅ Special characters in function names are properly escaped in IRIs
12. ✅ Function names are unescaped in literal values
13. ✅ minArity is only added when different from arity
14. ✅ All functions have @spec typespecs
15. ✅ Test suite passes with 25+ comprehensive tests
16. ✅ 100% code coverage for FunctionBuilder
17. ✅ Documentation includes clear usage examples
18. ✅ No regressions in existing tests

## 7. Risk Mitigation

### Risk 1: Missing Module Context
**Issue**: Function might not have module information in metadata.
**Mitigation**:
- Check for nil module in `build_belongs_to_triple/3`
- Return empty list if module is nil
- Document that functions should have module context
- Add warning logging for missing module

### Risk 2: Delegate Target Module Format
**Issue**: `delegates_to` uses module atom, needs conversion to IRI.
**Mitigation**:
- Implement `module_atom_to_string/1` helper
- Handle both Elixir and Erlang module formats
- Test with various module formats

### Risk 3: Location Information Without File Path
**Issue**: Function has location but context lacks file path.
**Mitigation**:
- Check for both location and file_path before generating location triple
- Skip location if either is missing
- Document this behavior in function documentation

### Risk 4: Duplicate Triples
**Issue**: belongsTo and containsFunction might be duplicated if module builder also adds them.
**Mitigation**:
- Use `Enum.uniq()` to deduplicate triples
- Document that Function Builder generates inverse triple
- Coordinate with Module Builder to avoid conflicts

## 8. Future Enhancements

### Phase 12.1.4 Dependencies
After this phase, we can implement:
- Function clause builder (FunctionClause RDF)
- Parameter builder (Parameter RDF)
- Complete function graph with clauses and parameters

### Later Optimizations
- Cache function IRIs to avoid regeneration
- Batch triple generation for multiple functions
- Support for function specs (@spec) in RDF

### Enhanced Features
- Generate triples for function guards
- Link to callback implementations
- Track function call graphs

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Core triple generation | 2 hours | Skeleton |
| Module relationships | 1.5 hours | Core |
| Documentation handling | 0.5 hours | Core |
| Delegate handling | 1 hour | Core |
| Location handling | 1 hour | Core |
| Integration and polish | 1 hour | All above |
| Unit tests (25+ tests) | 5 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 2 hours | All above |
| **Total** | **17 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/function.ex` - Function extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/module_builder.ex` - Module builder (reference implementation)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Ontology definitions

### Related Phase Documents
- `notes/features/phase-12-1-1-builder-infrastructure.md` - Builder infrastructure (completed)
- `notes/features/phase-12-1-2-module-builder.md` - Module builder (completed)

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Elixir Function documentation: https://hexdocs.pm/elixir/Kernel.html#def/2
