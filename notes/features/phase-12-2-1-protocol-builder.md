# Phase 12.2.1: Protocol Builder Planning Document

## 1. Problem Statement

Phase 12.1 completed the basic builders (Module, Function, Clause), establishing a solid foundation for RDF triple generation. Now we need to implement builders for Elixir's polymorphism mechanism: protocols.

**The Challenge**: The Protocol extractor (`ElixirOntologies.Extractors.Protocol`) produces rich structured data about protocol definitions and implementations, but this data needs to be converted to RDF triples that conform to the `elixir-structure.ttl` ontology while correctly representing Elixir's type-based polymorphism semantics.

**Current State**:
- Protocol extractor produces two distinct types:
  - `Protocol.t()` structs for protocol definitions (defprotocol)
  - `Protocol.Implementation.t()` structs for implementations (defimpl)
- Module Builder generates containment triples but not protocol-specific semantics
- Builder infrastructure exists but no protocol-specific builder

**Why Protocols Are Important**:
Protocols are Elixir's primary polymorphism mechanism, enabling:
- Type-based dispatch on the first argument
- Polymorphic behavior without inheritance
- Protocol consolidation for runtime performance
- Fallback implementations with `@fallback_to_any`
- Automatic protocol derivation with `@derive`

Understanding protocol relationships is critical for:
- Analyzing polymorphic code patterns
- Tracking protocol adoption across types
- Validating complete protocol implementations
- Understanding type-based architecture

**The Gap**: We need to:
1. Generate IRIs for protocols (following module IRI pattern)
2. Generate IRIs for protocol implementations (protocol + type combination)
3. Create `rdf:type` triples for Protocol and ProtocolImplementation classes
4. Build protocol-specific datatype properties (protocolName, fallbackToAny)
5. Build object properties linking protocols to functions (definesProtocolFunction)
6. Build implementation relationships (implementsProtocol, forDataType)
7. Handle special implementation types (Any, Derived)
8. Link implementation functions to protocol functions
9. Support protocol consolidation metadata

## 2. Solution Overview

Create a **Protocol Builder** that transforms protocol and implementation structs into RDF triples representing Elixir's polymorphism semantics.

### 2.1 Core Functionality

The builder will provide two main functions:
- `build_protocol/2` - Transform protocol definitions into RDF
- `build_implementation/2` - Transform protocol implementations into RDF

Both follow the established builder pattern:
```elixir
{entity_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)
{impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)
```

### 2.2 Builder Pattern

**Protocol Building**:
```elixir
def build_protocol(protocol_info, context) do
  # Generate protocol IRI (uses module pattern)
  protocol_iri = generate_protocol_iri(protocol_info, context)

  # Build all triples
  triples =
    [
      build_type_triple(protocol_iri, protocol_info),
      build_name_triple(protocol_iri, protocol_info),
      build_fallback_triple(protocol_iri, protocol_info)
    ] ++
      build_protocol_function_triples(protocol_iri, protocol_info, context) ++
      build_docstring_triple(protocol_iri, protocol_info) ++
      build_location_triple(protocol_iri, protocol_info, context)

  {protocol_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**Implementation Building**:
```elixir
def build_implementation(impl_info, context) do
  # Generate implementation IRI (protocol + type)
  impl_iri = generate_implementation_iri(impl_info, context)

  # Build all triples
  triples =
    [
      build_type_triple(impl_iri, impl_info),
      build_implements_triple(impl_iri, impl_info, context),
      build_for_type_triple(impl_iri, impl_info, context)
    ] ++
      build_implementation_function_triples(impl_iri, impl_info, context) ++
      build_location_triple(impl_iri, impl_info, context)

  {impl_iri, List.flatten(triples) |> Enum.uniq()}
end
```

### 2.3 Integration Point

The Protocol Builder will be called from a higher-level orchestrator (similar to Module Builder):

```elixir
# In FileAnalyzer or similar
protocols = Protocol.extract_all(ast)
implementations = Protocol.extract_all_implementations(ast)

protocol_triples = Enum.flat_map(protocols, fn proto ->
  {_iri, triples} = ProtocolBuilder.build_protocol(proto, context)
  triples
end)

impl_triples = Enum.flat_map(implementations, fn impl ->
  {_iri, triples} = ProtocolBuilder.build_implementation(impl, context)
  triples
end)
```

## 3. Technical Details

### 3.1 Protocol Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/protocol.ex`:

**Protocol Definition**:
```elixir
%ElixirOntologies.Extractors.Protocol{
  # Identity
  name: [atom()],                          # e.g., [:Enumerable], [:String, :Chars]

  # Protocol functions (signatures only, no bodies)
  functions: [
    %{
      name: atom(),                        # e.g., :count, :reduce
      arity: non_neg_integer(),           # Number of parameters
      parameters: [atom()],               # Parameter names
      doc: String.t() | nil,              # Function @doc
      spec: Macro.t() | nil,              # Function @spec AST
      location: SourceLocation.t() | nil
    }
  ],

  # Protocol attributes
  fallback_to_any: boolean(),             # @fallback_to_any true

  # Documentation
  doc: String.t() | false | nil,          # Protocol @moduledoc
  typedoc: String.t() | nil,              # Protocol @typedoc

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    function_count: non_neg_integer(),
    has_doc: boolean(),
    has_typedoc: boolean(),
    line: pos_integer() | nil
  }
}
```

**Protocol Implementation**:
```elixir
%ElixirOntologies.Extractors.Protocol.Implementation{
  # Identity
  protocol: [atom()],                     # e.g., [:Enumerable]
  for_type: [atom()] | atom(),           # e.g., [:List], :Any, :__MODULE__

  # Implemented functions (with bodies)
  functions: [
    %{
      name: atom(),
      arity: non_neg_integer(),
      has_body: boolean(),
      location: SourceLocation.t() | nil
    }
  ],

  # Special flags
  is_any: boolean(),                      # for: Any implementation

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    function_count: non_neg_integer(),
    inline: boolean(),                    # defimpl inside module (no for:)
    line: pos_integer() | nil
  }
}
```

**Key Points**:
- Protocol name is a list of atoms (can be namespaced: `String.Chars`)
- Protocol functions have no bodies (just signatures)
- Implementation functions must match protocol function signatures
- `for_type` can be a list (Elixir module), atom (built-in type), or `:__MODULE__`
- `is_any` flag indicates fallback implementation
- Inline implementations have `for_type: :__MODULE__`

### 3.2 IRI Generation Patterns

**Protocol IRIs** (follow module pattern):
```elixir
# Protocol IRI uses module IRI pattern
protocol_name = Enum.join(protocol_info.name, ".")
IRI.for_module(context.base_iri, protocol_name)

# Examples:
[:Enumerable] -> "base#Enumerable"
[:String, :Chars] -> "base#String.Chars"
[:MyApp, :Protocols, :Sizeable] -> "base#MyApp.Protocols.Sizeable"
```

**Implementation IRIs** (protocol + type combination):
```elixir
# Implementation IRI combines protocol and type
protocol_name = Enum.join(impl_info.protocol, ".")
type_name = normalize_type_name(impl_info.for_type)

# Pattern: base#Protocol.for.Type
impl_name = "#{protocol_name}.for.#{type_name}"
IRI.for_module(context.base_iri, impl_name)

# Examples:
Enumerable for List -> "base#Enumerable.for.List"
String.Chars for Integer -> "base#String.Chars.for.Integer"
Enumerable for Any -> "base#Enumerable.for.Any"
```

**Protocol Function IRIs** (use function pattern):
```elixir
# Protocol functions use standard function IRI pattern
protocol_name = Enum.join(protocol_info.name, ".")
IRI.for_function(context.base_iri, protocol_name, func.name, func.arity)

# Examples:
Enumerable.count/1 -> "base#Enumerable/count/1"
String.Chars.to_string/1 -> "base#String.Chars/to_string/1"
```

**Type Name Normalization**:
```elixir
defp normalize_type_name(type) when is_list(type) do
  # Elixir module: [:MyApp, :User] -> "MyApp.User"
  Enum.join(type, ".")
end

defp normalize_type_name(:Any), do: "Any"
defp normalize_type_name(:__MODULE__), do: "__MODULE__"

defp normalize_type_name(atom) when is_atom(atom) do
  # Built-in types: :Integer, :List, :Map, etc.
  Atom.to_string(atom)
end
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Classes

```turtle
:Protocol a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "An Elixir protocol defining polymorphic behavior based on data type" .

:ProtocolFunction a owl:Class ;
    rdfs:subClassOf :Function ;
    rdfs:comment "A function declared within a protocol definition" .

:ProtocolImplementation a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "An implementation of a protocol for a specific data type" .

:AnyImplementation a owl:Class ;
    rdfs:subClassOf :ProtocolImplementation ;
    rdfs:comment "A fallback implementation for the Any type" .

:DerivedImplementation a owl:Class ;
    rdfs:subClassOf :ProtocolImplementation ;
    rdfs:comment "A protocol implementation automatically generated via @derive" .
```

**Class Selection Logic**:
```elixir
# For protocols - always Protocol class
defp determine_protocol_class(_protocol_info), do: Structure.Protocol

# For implementations - check for Any or Derived
defp determine_implementation_class(impl_info) do
  cond do
    impl_info.is_any -> Structure.AnyImplementation
    impl_info.metadata[:derived] -> Structure.DerivedImplementation
    true -> Structure.ProtocolImplementation
  end
end
```

#### Object Properties

```turtle
# Protocol -> Function relationship
:definesProtocolFunction a owl:ObjectProperty ;
    rdfs:domain :Protocol ;
    rdfs:range :ProtocolFunction .

# Implementation -> Protocol relationship
:implementsProtocol a owl:ObjectProperty ;
    rdfs:domain :ProtocolImplementation ;
    rdfs:range :Protocol .

# Implementation -> Type relationship
:forDataType a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :ProtocolImplementation ;
    rdfs:comment "The data type this protocol implementation handles" .

# Struct -> Protocol relationship (for @derive)
:derivesProtocol a owl:ObjectProperty ;
    rdfs:domain :Struct ;
    rdfs:range :Protocol .
```

#### Data Properties

```turtle
# Protocol properties
:protocolName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Protocol ;
    rdfs:range xsd:string .

:fallbackToAny a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Protocol ;
    rdfs:range xsd:boolean .

:isConsolidated a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Protocol ;
    rdfs:range xsd:boolean .
```

### 3.4 Triple Generation Examples

**Simple Protocol**:
```turtle
<base#Stringable> a struct:Protocol ;
    struct:protocolName "Stringable"^^xsd:string ;
    struct:fallbackToAny "false"^^xsd:boolean ;
    struct:definesProtocolFunction <base#Stringable/to_string/1> ;
    core:hasSourceLocation <base#file/lib/stringable.ex/L1-5> .

<base#Stringable/to_string/1> a struct:ProtocolFunction ;
    struct:functionName "to_string"^^xsd:string ;
    struct:arity "1"^^xsd:nonNegativeInteger ;
    struct:belongsTo <base#Stringable> .
```

**Protocol with Fallback**:
```turtle
<base#Enumerable> a struct:Protocol ;
    struct:protocolName "Enumerable"^^xsd:string ;
    struct:fallbackToAny "true"^^xsd:boolean ;
    struct:definesProtocolFunction <base#Enumerable/count/1> ;
    struct:definesProtocolFunction <base#Enumerable/reduce/3> ;
    struct:docstring "Protocol for enumerable collections"^^xsd:string .
```

**Protocol Implementation**:
```turtle
<base#String.Chars.for.Integer> a struct:ProtocolImplementation ;
    struct:implementsProtocol <base#String.Chars> ;
    struct:forDataType <base#Integer> ;
    core:hasSourceLocation <base#file/lib/string_chars.ex/L10-20> .

<base#String.Chars> a struct:Protocol ;
    struct:protocolName "String.Chars"^^xsd:string ;
    struct:definesProtocolFunction <base#String.Chars/to_string/1> .
```

**Any Implementation**:
```turtle
<base#Enumerable.for.Any> a struct:AnyImplementation ;
    struct:implementsProtocol <base#Enumerable> ;
    struct:forDataType <base#Any> .

<base#Enumerable> struct:fallbackToAny "true"^^xsd:boolean .
```

**Implementation Function Linkage**:
```turtle
# Implementation contains its own function
<base#String.Chars.for.Integer> struct:containsFunction <base#String.Chars.for.Integer/to_string/1> .

# Implementation function implements protocol function
<base#String.Chars.for.Integer/to_string/1> struct:implementsProtocolFunction <base#String.Chars/to_string/1> .

# Protocol function belongs to protocol
<base#String.Chars/to_string/1> struct:belongsTo <base#String.Chars> .
```

**Namespaced Protocol**:
```turtle
<base#MyApp.Protocols.Sizeable> a struct:Protocol ;
    struct:protocolName "MyApp.Protocols.Sizeable"^^xsd:string ;
    struct:definesProtocolFunction <base#MyApp.Protocols.Sizeable/size/1> .

<base#MyApp.Protocols.Sizeable.for.List> a struct:ProtocolImplementation ;
    struct:implementsProtocol <base#MyApp.Protocols.Sizeable> ;
    struct:forDataType <base#List> .
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple
Helpers.type_triple(protocol_iri, Structure.Protocol)
#=> {protocol_iri, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Protocol>}

# Datatype property (string)
Helpers.datatype_property(protocol_iri, Structure.protocolName(), "Enumerable", RDF.XSD.String)
#=> {protocol_iri, Structure.protocolName(), RDF.XSD.String.new("Enumerable")}

# Datatype property (boolean)
Helpers.datatype_property(protocol_iri, Structure.fallbackToAny(), true, RDF.XSD.Boolean)
#=> {protocol_iri, Structure.fallbackToAny(), RDF.XSD.Boolean.new(true)}

# Object property
Helpers.object_property(protocol_iri, Structure.definesProtocolFunction(), func_iri)
#=> {protocol_iri, Structure.definesProtocolFunction(), func_iri}

# Implementation relationships
Helpers.object_property(impl_iri, Structure.implementsProtocol(), protocol_iri)
#=> {impl_iri, Structure.implementsProtocol(), protocol_iri}

Helpers.object_property(impl_iri, Structure.forDataType(), type_iri)
#=> {impl_iri, Structure.forDataType(), type_iri}
```

### 3.6 Handling Edge Cases

#### Inline Implementations

```elixir
# defimpl inside module (for_type: :__MODULE__)
defp build_for_type_triple(impl_iri, impl_info, context) do
  case impl_info.for_type do
    :__MODULE__ ->
      # Need to resolve __MODULE__ from context or metadata
      # For now, we can skip or use a placeholder
      []

    type ->
      type_iri = generate_type_iri(type, context)
      [Helpers.object_property(impl_iri, Structure.forDataType(), type_iri)]
  end
end
```

#### Built-in Types vs Custom Types

```elixir
defp generate_type_iri(type, context) when is_list(type) do
  # Custom Elixir module
  type_name = Enum.join(type, ".")
  IRI.for_module(context.base_iri, type_name)
end

defp generate_type_iri(type, context) when is_atom(type) do
  # Built-in type (Integer, List, Map, Any, etc.)
  type_name = Atom.to_string(type)
  IRI.for_module(context.base_iri, type_name)
end
```

#### Protocol Functions

```elixir
defp build_protocol_function_triples(protocol_iri, protocol_info, context) do
  protocol_name = protocol_name_string(protocol_info.name)

  Enum.flat_map(protocol_info.functions, fn func ->
    # Generate function IRI
    func_iri = IRI.for_function(context.base_iri, protocol_name, func.name, func.arity)

    # Protocol function triples
    func_triples = [
      # Type
      Helpers.type_triple(func_iri, Structure.ProtocolFunction),
      # Name
      Helpers.datatype_property(func_iri, Structure.functionName(), Atom.to_string(func.name), RDF.XSD.String),
      # Arity
      Helpers.datatype_property(func_iri, Structure.arity(), func.arity, RDF.XSD.NonNegativeInteger),
      # Belongs to protocol
      Helpers.object_property(func_iri, Structure.belongsTo(), protocol_iri)
    ] ++
      # Optional doc
      build_func_docstring(func_iri, func)

    # Link protocol -> function
    protocol_link = Helpers.object_property(protocol_iri, Structure.definesProtocolFunction(), func_iri)

    [protocol_link | func_triples]
  end)
end
```

#### Implementation Functions

```elixir
defp build_implementation_function_triples(impl_iri, impl_info, context) do
  # Need to match implementation functions to protocol functions
  protocol_iri = generate_protocol_iri_from_name(impl_info.protocol, context)
  protocol_name = Enum.join(impl_info.protocol, ".")

  Enum.flat_map(impl_info.functions, fn func ->
    # Generate IRI for this implementation's function
    impl_func_iri = IRI.for_function(context.base_iri, impl_name_string(impl_info), func.name, func.arity)

    # Generate IRI for corresponding protocol function
    proto_func_iri = IRI.for_function(context.base_iri, protocol_name, func.name, func.arity)

    [
      # Implementation contains this function
      Helpers.object_property(impl_iri, Structure.containsFunction(), impl_func_iri),
      # This function implements the protocol function
      Helpers.object_property(impl_func_iri, Structure.implementsProtocolFunction(), proto_func_iri)
    ]
  end)
end

defp impl_name_string(impl_info) do
  protocol_name = Enum.join(impl_info.protocol, ".")
  type_name = normalize_type_name(impl_info.for_type)
  "#{protocol_name}.for.#{type_name}"
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Protocol Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/protocol_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build_protocol/2` and `build_implementation/2` function signatures
3. Add helper functions for name conversion
4. Import necessary namespaces (Helpers, IRI, Structure, Core)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.ProtocolBuilder do
  @moduledoc """
  Builds RDF triples for Elixir protocols and protocol implementations.

  This module transforms protocol-related extractor results into RDF triples
  following the elixir-structure.ttl ontology. It handles:

  - Protocol definitions (defprotocol)
  - Protocol functions (function signatures in protocols)
  - Protocol implementations (defimpl)
  - Implementation types (Any, Derived, regular)
  - Protocol-to-function relationships (definesProtocolFunction)
  - Implementation-to-protocol relationships (implementsProtocol)
  - Implementation-to-type relationships (forDataType)
  - Protocol attributes (fallbackToAny)

  ## Usage

      alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
      alias ElixirOntologies.Extractors.Protocol

      # Build protocol
      protocol_info = %Protocol{name: [:Enumerable], ...}
      context = Context.new(base_iri: "https://example.org/code#")
      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Build implementation
      impl_info = %Protocol.Implementation{protocol: [:Enumerable], for_type: [:List], ...}
      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Protocol, as: ProtocolExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a protocol definition.
  """
  @spec build_protocol(ProtocolExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_protocol(protocol_info, context)

  @doc """
  Builds RDF triples for a protocol implementation.
  """
  @spec build_implementation(ProtocolExtractor.Implementation.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_implementation(impl_info, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp protocol_name_string(name_list)
  defp normalize_type_name(type)
  defp generate_protocol_iri(protocol_info, context)
  defp generate_implementation_iri(impl_info, context)
  # ... etc
end
```

### 4.2 Step 2: Implement Protocol Triple Generation (2 hours)

Implement functions for protocol definition triples:

1. **IRI Generation**:
```elixir
defp generate_protocol_iri(protocol_info, context) do
  protocol_name = protocol_name_string(protocol_info.name)
  IRI.for_module(context.base_iri, protocol_name)
end

defp protocol_name_string(name) when is_list(name) do
  Enum.join(name, ".")
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(protocol_iri, _protocol_info) do
  Helpers.type_triple(protocol_iri, Structure.Protocol)
end
```

3. **Name Property**:
```elixir
defp build_name_triple(protocol_iri, protocol_info) do
  protocol_name = protocol_name_string(protocol_info.name)
  Helpers.datatype_property(protocol_iri, Structure.protocolName(), protocol_name, RDF.XSD.String)
end
```

4. **Fallback Property**:
```elixir
defp build_fallback_triple(protocol_iri, protocol_info) do
  Helpers.datatype_property(
    protocol_iri,
    Structure.fallbackToAny(),
    protocol_info.fallback_to_any,
    RDF.XSD.Boolean
  )
end
```

5. **Documentation** (optional):
```elixir
defp build_docstring_triple(protocol_iri, protocol_info) do
  case protocol_info.doc do
    nil -> []
    false -> []
    doc when is_binary(doc) ->
      [Helpers.datatype_property(protocol_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end
```

### 4.3 Step 3: Implement Protocol Function Handling (2 hours)

Generate triples for protocol functions and their relationships:

```elixir
defp build_protocol_function_triples(protocol_iri, protocol_info, context) do
  protocol_name = protocol_name_string(protocol_info.name)

  Enum.flat_map(protocol_info.functions, fn func ->
    # Generate function IRI
    func_iri = IRI.for_function(context.base_iri, protocol_name, func.name, func.arity)

    # Build function triples
    func_triples = [
      # rdf:type
      Helpers.type_triple(func_iri, Structure.ProtocolFunction),
      # functionName
      Helpers.datatype_property(func_iri, Structure.functionName(), Atom.to_string(func.name), RDF.XSD.String),
      # arity
      Helpers.datatype_property(func_iri, Structure.arity(), func.arity, RDF.XSD.NonNegativeInteger),
      # belongsTo protocol
      Helpers.object_property(func_iri, Structure.belongsTo(), protocol_iri)
    ] ++ build_func_doc(func_iri, func) ++ build_func_location(func_iri, func, context)

    # Protocol -> function relationship
    protocol_link = Helpers.object_property(protocol_iri, Structure.definesProtocolFunction(), func_iri)

    [protocol_link | func_triples]
  end)
end

defp build_func_doc(func_iri, func) do
  case func.doc do
    nil -> []
    doc when is_binary(doc) ->
      [Helpers.datatype_property(func_iri, Structure.docstring(), doc, RDF.XSD.String)]
  end
end

defp build_func_location(func_iri, func, context) do
  case {func.location, context.file_path} do
    {nil, _} -> []
    {_, nil} -> []
    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)
      [Helpers.object_property(func_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.4 Step 4: Implement Implementation Triple Generation (2 hours)

Implement functions for protocol implementation triples:

1. **Implementation IRI Generation**:
```elixir
defp generate_implementation_iri(impl_info, context) do
  impl_name = implementation_name_string(impl_info)
  IRI.for_module(context.base_iri, impl_name)
end

defp implementation_name_string(impl_info) do
  protocol_name = protocol_name_string(impl_info.protocol)
  type_name = normalize_type_name(impl_info.for_type)
  "#{protocol_name}.for.#{type_name}"
end

defp normalize_type_name(type) when is_list(type) do
  Enum.join(type, ".")
end

defp normalize_type_name(:__MODULE__), do: "__MODULE__"
defp normalize_type_name(atom) when is_atom(atom), do: Atom.to_string(atom)
```

2. **Implementation Type**:
```elixir
defp build_impl_type_triple(impl_iri, impl_info) do
  class = determine_implementation_class(impl_info)
  Helpers.type_triple(impl_iri, class)
end

defp determine_implementation_class(impl_info) do
  cond do
    impl_info.is_any -> Structure.AnyImplementation
    # Could check metadata for :derived flag
    true -> Structure.ProtocolImplementation
  end
end
```

3. **Protocol Relationship**:
```elixir
defp build_implements_triple(impl_iri, impl_info, context) do
  protocol_iri = generate_protocol_iri_from_name(impl_info.protocol, context)
  Helpers.object_property(impl_iri, Structure.implementsProtocol(), protocol_iri)
end

defp generate_protocol_iri_from_name(protocol_name, context) do
  name_string = protocol_name_string(protocol_name)
  IRI.for_module(context.base_iri, name_string)
end
```

4. **Type Relationship**:
```elixir
defp build_for_type_triple(impl_iri, impl_info, context) do
  case impl_info.for_type do
    :__MODULE__ ->
      # Inline implementation - skip for now or use placeholder
      []

    type ->
      type_iri = generate_type_iri(type, context)
      [Helpers.object_property(impl_iri, Structure.forDataType(), type_iri)]
  end
end

defp generate_type_iri(type, context) when is_list(type) do
  # Custom module
  type_name = Enum.join(type, ".")
  IRI.for_module(context.base_iri, type_name)
end

defp generate_type_iri(type, context) when is_atom(type) do
  # Built-in type
  type_name = Atom.to_string(type)
  IRI.for_module(context.base_iri, type_name)
end
```

### 4.5 Step 5: Implement Implementation Function Linkage (2 hours)

Link implementation functions to protocol functions:

```elixir
defp build_implementation_function_triples(impl_iri, impl_info, context) do
  impl_name = implementation_name_string(impl_info)
  protocol_name = protocol_name_string(impl_info.protocol)

  Enum.flat_map(impl_info.functions, fn func ->
    # IRI for this implementation's function
    impl_func_iri = IRI.for_function(context.base_iri, impl_name, func.name, func.arity)

    # IRI for corresponding protocol function
    proto_func_iri = IRI.for_function(context.base_iri, protocol_name, func.name, func.arity)

    [
      # Implementation contains function
      Helpers.object_property(impl_iri, Structure.containsFunction(), impl_func_iri),
      # Function implements protocol function
      Helpers.object_property(impl_func_iri, Structure.implementsProtocolFunction(), proto_func_iri)
    ]
  end)
end
```

Note: This creates the linkage but doesn't build the full function triples. Those would be built by FunctionBuilder if needed.

### 4.6 Step 6: Implement Location Handling (1 hour)

Add source location triples for protocols and implementations:

```elixir
defp build_location_triple(entity_iri, entity_info, context) do
  case {entity_info.location, context.file_path} do
    {nil, _} ->
      []

    {_location, nil} ->
      []

    {location, file_path} ->
      file_iri = IRI.for_source_file(context.base_iri, file_path)
      end_line = location.end_line || location.start_line
      location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

      [Helpers.object_property(entity_iri, Core.hasSourceLocation(), location_iri)]
  end
end
```

### 4.7 Step 7: Integrate All Components (1 hour)

Complete the main `build_protocol/2` and `build_implementation/2` functions:

```elixir
@spec build_protocol(ProtocolExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_protocol(protocol_info, context) do
  # Generate protocol IRI
  protocol_iri = generate_protocol_iri(protocol_info, context)

  # Build all triples
  triples =
    [
      # Core protocol triples
      build_type_triple(protocol_iri, protocol_info),
      build_name_triple(protocol_iri, protocol_info),
      build_fallback_triple(protocol_iri, protocol_info)
    ] ++
      # Protocol functions
      build_protocol_function_triples(protocol_iri, protocol_info, context) ++
      # Optional fields
      build_docstring_triple(protocol_iri, protocol_info) ++
      build_location_triple(protocol_iri, protocol_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {protocol_iri, triples}
end

@spec build_implementation(ProtocolExtractor.Implementation.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_implementation(impl_info, context) do
  # Generate implementation IRI
  impl_iri = generate_implementation_iri(impl_info, context)

  # Build all triples
  triples =
    [
      # Core implementation triples
      build_impl_type_triple(impl_iri, impl_info),
      build_implements_triple(impl_iri, impl_info, context)
    ] ++
      # Type relationship
      build_for_type_triple(impl_iri, impl_info, context) ++
      # Implementation functions
      build_implementation_function_triples(impl_iri, impl_info, context) ++
      # Location
      build_location_triple(impl_iri, impl_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {impl_iri, triples}
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/protocol_builder_test.exs`)

**Target**: 20+ comprehensive tests covering protocols and implementations

#### Test Categories

**Protocol Building Tests** (10 tests):

1. **Basic Protocol Building** (3 tests):
   - Simple protocol with one function
   - Protocol with multiple functions
   - Protocol with no functions (edge case)

2. **Protocol Attributes** (2 tests):
   - Protocol with @fallback_to_any true
   - Protocol with @fallback_to_any false (default)

3. **Protocol Documentation** (2 tests):
   - Protocol with documentation
   - Protocol without documentation

4. **Protocol Functions** (3 tests):
   - Protocol function triples (type, name, arity, belongsTo)
   - definesProtocolFunction relationship
   - Multiple protocol functions

**Implementation Building Tests** (10 tests):

5. **Basic Implementation Building** (3 tests):
   - Simple implementation with one function
   - Implementation with multiple functions
   - Implementation for built-in type (Integer, List)

6. **Implementation Types** (3 tests):
   - Regular ProtocolImplementation
   - AnyImplementation (is_any: true)
   - Implementation for custom type (module)

7. **Implementation Relationships** (2 tests):
   - implementsProtocol triple
   - forDataType triple

8. **Implementation Functions** (2 tests):
   - containsFunction triples for implementation
   - implementsProtocolFunction linkage

**Integration Tests** (5+ tests):

9. **Namespaced Protocols** (1 test):
   - Protocol with namespaced name (String.Chars)

10. **Complex Scenarios** (2 tests):
    - Protocol + multiple implementations
    - Protocol with functions + implementation with all functions

11. **IRI Generation** (2 tests):
    - Verify protocol IRI format
    - Verify implementation IRI format (protocol.for.type)

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.ProtocolBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
  alias ElixirOntologies.Extractors.Protocol
  alias ElixirOntologies.NS.Structure

  describe "build_protocol/2 basic protocol" do
    test "builds minimal protocol with one function" do
      protocol_info = %Protocol{
        name: [:Stringable],
        functions: [
          %{name: :to_string, arity: 1, parameters: [:data], doc: nil, spec: nil, location: nil}
        ],
        fallback_to_any: false,
        doc: nil,
        typedoc: nil,
        location: nil,
        metadata: %{function_count: 1, has_doc: false, has_typedoc: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify protocol IRI
      assert to_string(protocol_iri) == "https://example.org/code#Stringable"

      # Verify protocol type
      assert {protocol_iri, RDF.type(), Structure.Protocol} in triples

      # Verify protocol name
      assert Enum.any?(triples, fn
               {^protocol_iri, pred, obj} ->
                 pred == Structure.protocolName() and
                   RDF.Literal.value(obj) == "Stringable"

               _ ->
                 false
             end)

      # Verify fallback_to_any
      assert Enum.any?(triples, fn
               {^protocol_iri, pred, obj} ->
                 pred == Structure.fallbackToAny() and
                   RDF.Literal.value(obj) == false

               _ ->
                 false
             end)

      # Verify protocol function exists
      func_iri = ~I<https://example.org/code#Stringable/to_string/1>
      assert {protocol_iri, Structure.definesProtocolFunction(), func_iri} in triples

      # Verify protocol function type
      assert {func_iri, RDF.type(), Structure.ProtocolFunction} in triples
    end

    test "builds protocol with fallback_to_any" do
      protocol_info = %Protocol{
        name: [:Enumerable],
        functions: [
          %{name: :count, arity: 1, parameters: [:enumerable], doc: nil, spec: nil, location: nil}
        ],
        fallback_to_any: true,
        doc: "Protocol for enumerable collections",
        typedoc: nil,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify fallback_to_any is true
      assert Enum.any?(triples, fn
               {^protocol_iri, pred, obj} ->
                 pred == Structure.fallbackToAny() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)

      # Verify docstring
      assert Enum.any?(triples, fn
               {^protocol_iri, pred, obj} ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Protocol for enumerable collections"

               _ ->
                 false
             end)
    end
  end

  describe "build_implementation/2 basic implementation" do
    test "builds simple implementation for built-in type" do
      impl_info = %Protocol.Implementation{
        protocol: [:String, :Chars],
        for_type: :Integer,
        functions: [
          %{name: :to_string, arity: 1, has_body: true, location: nil}
        ],
        is_any: false,
        location: nil,
        metadata: %{function_count: 1, inline: false}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify implementation IRI
      assert to_string(impl_iri) == "https://example.org/code#String.Chars.for.Integer"

      # Verify implementation type
      assert {impl_iri, RDF.type(), Structure.ProtocolImplementation} in triples

      # Verify implementsProtocol
      protocol_iri = ~I<https://example.org/code#String.Chars>
      assert {impl_iri, Structure.implementsProtocol(), protocol_iri} in triples

      # Verify forDataType
      type_iri = ~I<https://example.org/code#Integer>
      assert {impl_iri, Structure.forDataType(), type_iri} in triples
    end

    test "builds Any implementation" do
      impl_info = %Protocol.Implementation{
        protocol: [:Enumerable],
        for_type: :Any,
        functions: [
          %{name: :count, arity: 1, has_body: true, location: nil}
        ],
        is_any: true,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify AnyImplementation type
      assert {impl_iri, RDF.type(), Structure.AnyImplementation} in triples

      # Verify IRI contains "for.Any"
      assert to_string(impl_iri) == "https://example.org/code#Enumerable.for.Any"
    end

    test "builds implementation for custom type" do
      impl_info = %Protocol.Implementation{
        protocol: [:Enumerable],
        for_type: [:MyApp, :CustomList],
        functions: [
          %{name: :count, arity: 1, has_body: true, location: nil},
          %{name: :reduce, arity: 3, has_body: true, location: nil}
        ],
        is_any: false,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify IRI
      assert to_string(impl_iri) == "https://example.org/code#Enumerable.for.MyApp.CustomList"

      # Verify forDataType points to custom module
      type_iri = ~I<https://example.org/code#MyApp.CustomList>
      assert {impl_iri, Structure.forDataType(), type_iri} in triples
    end
  end

  describe "build_implementation/2 function linkage" do
    test "creates containsFunction and implementsProtocolFunction triples" do
      impl_info = %Protocol.Implementation{
        protocol: [:Stringable],
        for_type: [:MyStruct],
        functions: [
          %{name: :to_string, arity: 1, has_body: true, location: nil}
        ],
        is_any: false,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Implementation function IRI
      impl_func_iri = ~I<https://example.org/code#Stringable.for.MyStruct/to_string/1>

      # Protocol function IRI
      proto_func_iri = ~I<https://example.org/code#Stringable/to_string/1>

      # Verify containsFunction
      assert {impl_iri, Structure.containsFunction(), impl_func_iri} in triples

      # Verify implementsProtocolFunction
      assert {impl_func_iri, Structure.implementsProtocolFunction(), proto_func_iri} in triples
    end
  end

  describe "build_protocol/2 namespaced protocols" do
    test "builds protocol with namespaced name" do
      protocol_info = %Protocol{
        name: [:MyApp, :Protocols, :Sizeable],
        functions: [
          %{name: :size, arity: 1, parameters: [:data], doc: nil, spec: nil, location: nil}
        ],
        fallback_to_any: false,
        doc: nil,
        typedoc: nil,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify IRI
      assert to_string(protocol_iri) == "https://example.org/code#MyApp.Protocols.Sizeable"

      # Verify protocol name
      assert Enum.any?(triples, fn
               {^protocol_iri, pred, obj} ->
                 pred == Structure.protocolName() and
                   RDF.Literal.value(obj) == "MyApp.Protocols.Sizeable"

               _ ->
                 false
             end)
    end
  end
end
```

### 5.3 Property-Based Tests

Use StreamData for:
- Generating valid protocol names
- Testing IRI consistency across multiple builds
- Verifying no duplicate triples
- Testing various type name formats

### 5.4 Integration Tests

Test the complete flow from extractor to builder:
```elixir
test "integration: extract and build real protocol" do
  ast = quote do
    defprotocol Stringable do
      @doc "Convert to string"
      def to_string(data)
    end
  end

  # Extract
  {:ok, protocol_info} = Protocol.extract(ast)

  # Build
  context = Context.new(base_iri: "https://example.org/code#")
  {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

  # Verify complete graph
  assert length(triples) >= 5
  # ... more assertions
end

test "integration: extract and build implementation" do
  code = "defimpl String.Chars, for: Integer do def to_string(i), do: Integer.to_string(i) end"
  {:ok, ast} = Code.string_to_quoted(code)

  # Extract
  {:ok, impl_info} = Protocol.extract_implementation(ast)

  # Build
  context = Context.new(base_iri: "https://example.org/code#")
  {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

  # Verify
  assert length(triples) >= 4
  # ... more assertions
end
```

## 6. Success Criteria

This phase is complete when:

1. ✅ `ProtocolBuilder` module exists with complete documentation
2. ✅ `build_protocol/2` correctly transforms `Protocol.t()` to RDF triples
3. ✅ `build_implementation/2` correctly transforms `Implementation.t()` to RDF triples
4. ✅ Protocol class is correctly assigned
5. ✅ Implementation classes are correctly assigned (ProtocolImplementation, AnyImplementation)
6. ✅ Protocol datatype properties are generated (protocolName, fallbackToAny)
7. ✅ Protocol function triples are generated with ProtocolFunction type
8. ✅ definesProtocolFunction relationships are created
9. ✅ implementsProtocol relationships are created
10. ✅ forDataType relationships are created
11. ✅ Implementation function linkage works (implementsProtocolFunction)
12. ✅ Protocol IRIs follow module pattern
13. ✅ Implementation IRIs follow protocol.for.type pattern
14. ✅ Built-in types and custom types are handled correctly
15. ✅ Any implementations are correctly typed
16. ✅ Documentation is added when present
17. ✅ Source location information is added when available
18. ✅ All functions have @spec typespecs
19. ✅ Test suite passes with 20+ comprehensive tests
20. ✅ 100% code coverage for ProtocolBuilder
21. ✅ Documentation includes clear usage examples
22. ✅ No regressions in existing tests

## 7. Risk Mitigation

### Risk 1: __MODULE__ in Inline Implementations
**Issue**: `for_type: :__MODULE__` needs runtime module context.
**Mitigation**:
- Skip forDataType triple for :__MODULE__ or use placeholder
- Document this limitation
- Consider enhancing context to include current module
- Add warning logging for skipped inline implementations

### Risk 2: Missing Protocol Function Implementation
**Issue**: Implementation might not implement all protocol functions.
**Mitigation**:
- Builder doesn't validate completeness (that's SHACL's job)
- Generate triples for available functions only
- SHACL shapes will catch incomplete implementations
- Document that validation happens at graph level

### Risk 3: Protocol Consolidation Metadata
**Issue**: Extractor doesn't currently capture consolidation info.
**Mitigation**:
- Add isConsolidated property when extractor supports it
- For now, skip consolidation metadata
- Document as future enhancement
- Add TODO comment for consolidation support

### Risk 4: Built-in Type IRIs
**Issue**: Built-in types (Integer, List) might need special handling.
**Mitigation**:
- Treat built-in types same as modules for IRI generation
- Use simple module pattern: base#Integer, base#List
- Document this convention
- Consider future alignment with Elixir type system ontology

### Risk 5: implementsProtocolFunction Property
**Issue**: This property doesn't exist in current ontology.
**Mitigation**:
- Verify property exists in elixir-structure.ttl
- If missing, add to ontology before implementation
- Use standard containsFunction for now if needed
- Update planning doc if property name differs

## 8. Future Enhancements

### Phase 12.2.2 Dependencies
After this phase, we can implement:
- Behaviour builder (similar to protocols but module-based)
- Struct builder (with protocol derivation support)
- Complete polymorphism graph

### Later Optimizations
- Cache protocol IRIs to avoid regeneration
- Batch triple generation for related protocols and implementations
- Parallel building of independent protocols

### Enhanced Features
- Generate triples for @derive directives
- Link derived implementations to source structs
- Track protocol consolidation status
- Generate protocol dispatch tables in RDF
- Support for @impl attribute on implementation functions
- Validation of protocol function signature matches

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Protocol triple generation | 2 hours | Skeleton |
| Protocol function handling | 2 hours | Protocol triples |
| Implementation triple generation | 2 hours | Skeleton |
| Implementation function linkage | 2 hours | Implementation triples |
| Location handling | 1 hour | All above |
| Integration and polish | 1 hour | All above |
| Unit tests (20+ tests) | 4 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 2 hours | All above |
| **Total** | **19 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/protocol.ex` - Protocol extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/module_builder.ex` - Module builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Protocol ontology definitions

### Related Phase Documents
- `notes/features/phase-12-1-1-builder-infrastructure.md` - Builder infrastructure
- `notes/features/phase-12-1-2-module-builder.md` - Module builder
- `notes/features/phase-12-1-3-function-builder.md` - Function builder
- `notes/features/phase-12-1-4-clause-builder.md` - Clause builder

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Elixir Protocol documentation: https://hexdocs.pm/elixir/Protocol.html
- Elixir Protocol Guide: https://elixir-lang.org/getting-started/protocols.html
