# Phase 12.2.3: Struct Builder Planning Document

## 1. Problem Statement

Phase 12.2.2 completed the Behaviour Builder, handling Elixir's contract-based polymorphism. Now we need to implement the Struct Builder to handle Elixir's structured data mechanism with compile-time guarantees.

**The Challenge**: The Struct extractor (`ElixirOntologies.Extractors.Struct`) produces rich structured data about struct and exception definitions, but this data needs to be converted to RDF triples that conform to the `elixir-structure.ttl` ontology while correctly representing Elixir's struct semantics including fields, defaults, enforced keys, and protocol derivation.

**Current State**:
- Struct extractor produces two distinct types:
  - `Struct.t()` structs for struct definitions (defstruct)
  - `Struct.Exception.t()` structs for exception definitions (defexception)
- Module Builder generates containment triples but not struct-specific semantics
- Protocol and Behaviour Builders established the pattern for polymorphism builders
- Builder infrastructure exists but no struct-specific builder

**Why Structs Are Important**:
Structs are Elixir's primary data modeling mechanism, enabling:
- Compile-time field validation
- Named fields with defaults
- Enforced keys for required fields
- Protocol derivation for automatic implementations
- Exception handling with structured data
- Pattern matching with structural guarantees

Understanding struct relationships is critical for:
- Analyzing data model architecture
- Tracking protocol derivation patterns
- Validating field usage across codebase
- Understanding exception hierarchies
- Detecting data validation requirements

**The Gap**: We need to:
1. Generate IRIs for structs (using module IRI pattern)
2. Generate IRIs for struct fields (struct + field name)
3. Create `rdf:type` triples for Struct, StructField, EnforcedKey, and Exception classes
4. Build struct-specific datatype properties (fieldName, hasDefaultFieldValue)
5. Build object properties linking structs to fields (hasField, hasEnforcedKey)
6. Build protocol derivation relationships (derivesProtocol)
7. Handle enforced keys (fields in @enforce_keys)
8. Handle exception-specific properties (default message, custom message)
9. Preserve field declaration order
10. Support @derive directives for protocol implementations

## 2. Solution Overview

Create a **Struct Builder** that transforms struct and exception definitions into RDF triples representing Elixir's data modeling semantics.

### 2.1 Core Functionality

The builder will provide two main functions:
- `build_struct/2` - Transform struct definitions into RDF
- `build_exception/2` - Transform exception definitions into RDF

Both follow the established builder pattern:
```elixir
{struct_iri, triples} = StructBuilder.build_struct(struct_info, context)
{exception_iri, triples} = StructBuilder.build_exception(exception_info, context)
```

### 2.2 Builder Pattern

**Struct Building**:
```elixir
def build_struct(struct_info, context) do
  # Use module IRI as struct IRI (structs are module-scoped)
  struct_iri = generate_struct_iri(context)

  # Build all triples
  triples =
    [
      build_type_triple(struct_iri, :struct),
      build_module_contains_struct_triple(struct_iri, context)
    ] ++
      build_field_triples(struct_iri, struct_info, context) ++
      build_enforced_key_triples(struct_iri, struct_info, context) ++
      build_derives_triples(struct_iri, struct_info, context)

  {struct_iri, List.flatten(triples) |> Enum.uniq()}
end
```

**Exception Building**:
```elixir
def build_exception(exception_info, context) do
  # Use module IRI as exception IRI (exceptions are module-scoped)
  exception_iri = generate_exception_iri(context)

  # Build all triples
  triples =
    [
      build_type_triple(exception_iri, :exception),
      build_module_contains_struct_triple(exception_iri, context)
    ] ++
      build_field_triples(exception_iri, exception_info, context) ++
      build_enforced_key_triples(exception_iri, exception_info, context) ++
      build_derives_triples(exception_iri, exception_info, context) ++
      build_exception_specific_triples(exception_iri, exception_info)

  {exception_iri, List.flatten(triples) |> Enum.uniq()}
end
```

### 2.3 Integration Point

The Struct Builder will be called from a higher-level orchestrator:

```elixir
# In FileAnalyzer or similar
# Check if module defines struct
if Struct.defines_struct?(module_body) do
  struct_info = Struct.extract_from_body(module_body)
  {_iri, struct_triples} = StructBuilder.build_struct(struct_info, context)
  struct_triples
else
  []
end

# Check if module defines exception
if Struct.defines_exception?(module_body) do
  exception_info = Struct.extract_exception_from_body(module_body)
  {_iri, exception_triples} = StructBuilder.build_exception(exception_info, context)
  exception_triples
else
  []
end
```

## 3. Technical Details

### 3.1 Struct Extractor Output Format

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/struct.ex`:

**Struct Definition**:
```elixir
%ElixirOntologies.Extractors.Struct{
  # Field definitions
  fields: [
    %{
      name: atom(),                        # e.g., :name, :email, :age
      has_default: boolean(),              # Whether field has default value
      default_value: term() | nil,         # The default value (nil if no default)
      location: SourceLocation.t() | nil   # Typically nil for fields
    }
  ],

  # Enforced keys (@enforce_keys)
  enforce_keys: [atom()],                  # e.g., [:name, :email]

  # Derived protocols (@derive)
  derives: [
    %Helpers.DeriveInfo{
      protocols: [
        %{
          protocol: [atom()] | atom(),     # e.g., [:Inspect], :Enumerable
          options: keyword() | nil         # Protocol-specific options
        }
      ],
      location: SourceLocation.t() | nil
    }
  ],

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    field_count: non_neg_integer(),
    fields_with_defaults: non_neg_integer(),
    line: pos_integer() | nil
  }
}
```

**Exception Definition**:
```elixir
%ElixirOntologies.Extractors.Struct.Exception{
  # Same fields as Struct
  fields: [field()],
  enforce_keys: [atom()],
  derives: [DeriveInfo.t()],

  # Exception-specific
  has_custom_message: boolean(),           # Whether module defines message/1
  default_message: String.t() | nil,       # Default message if :message field has string default

  # Source location
  location: SourceLocation.t() | nil,

  # Metadata
  metadata: %{
    field_count: non_neg_integer(),
    has_default_message: boolean(),
    line: pos_integer() | nil
  }
}
```

**Key Points**:
- Struct is tied to a module (extracted from module body)
- Fields can have default values (has_default flag)
- enforce_keys lists fields that must be provided at construction
- derives lists protocols to auto-implement
- Exceptions are special structs with additional properties
- Field order is preserved in the fields list

### 3.2 IRI Generation Patterns

**Struct IRIs** (same as module IRI since struct IS the module):
```elixir
# Struct uses module IRI pattern (struct is defined by a module)
# Need module name from context (struct extractor doesn't include it)
module_name = context.module_name  # e.g., "User", "MyApp.Data.Customer"
IRI.for_module(context.base_iri, module_name)

# Examples:
User struct -> "base#User"
MyApp.Data.Customer -> "base#MyApp.Data.Customer"
MyError exception -> "base#MyError"
```

**Field IRIs** (struct + field name):
```elixir
# Field IRI combines struct IRI and field name
struct_iri = IRI.for_module(context.base_iri, context.module_name)
field_name_string = Atom.to_string(field.name)

# Pattern: base#Module/field/fieldname
field_iri = RDF.IRI.new("#{struct_iri}/field/#{field_name_string}")

# Examples:
User.name field -> "base#User/field/name"
User.email field -> "base#User/field/email"
Customer.balance field -> "base#MyApp.Data.Customer/field/balance"
MyError.message field -> "base#MyError/field/message"
```

**Protocol IRIs for @derive** (reference existing protocols):
```elixir
# @derive references existing protocols
protocol_name = normalize_protocol_name(protocol)
IRI.for_module(context.base_iri, protocol_name)

# Examples:
@derive Inspect -> "base#Inspect"
@derive [Enumerable, String.Chars] -> ["base#Enumerable", "base#String.Chars"]
@derive {Jason.Encoder, only: [:name]} -> "base#Jason.Encoder"
```

**Protocol Name Normalization**:
```elixir
defp normalize_protocol_name(protocol) when is_list(protocol) do
  # Protocol as list: [:String, :Chars] -> "String.Chars"
  Enum.join(protocol, ".")
end

defp normalize_protocol_name(protocol) when is_atom(protocol) do
  # Protocol as atom: :Inspect -> "Inspect"
  Atom.to_string(protocol)
end

defp normalize_protocol_name({protocol, _opts}) do
  # Protocol with options: {Jason.Encoder, only: [:name]} -> "Jason.Encoder"
  normalize_protocol_name(protocol)
end
```

### 3.3 Ontology Classes and Properties

From `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`:

#### Classes

```turtle
:Struct a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "An Elixir struct - a map with a fixed set of keys" .

:StructField a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    rdfs:comment "A field in a struct definition, with optional default value" .

:EnforcedKey a owl:Class ;
    rdfs:subClassOf :StructField ;
    rdfs:comment "A struct field listed in @enforce_keys that must be provided" .

:Exception a owl:Class ;
    rdfs:subClassOf :Struct ;
    rdfs:comment "An Elixir exception module defined with defexception" .
```

**Class Selection Logic**:
```elixir
# For structs - always Struct class
defp determine_struct_class(_struct_info), do: Structure.Struct

# For exceptions - always Exception class
defp determine_exception_class(_exception_info), do: Structure.Exception

# For fields - check if enforced
defp determine_field_class(field, struct_info) do
  if field.name in struct_info.enforce_keys do
    Structure.EnforcedKey
  else
    Structure.StructField
  end
end
```

#### Object Properties

```turtle
# Module -> Struct relationship
:containsStruct a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain :Module ;
    rdfs:range :Struct .

# Struct -> Field relationship
:hasField a owl:ObjectProperty ;
    rdfs:domain :Struct ;
    rdfs:range :StructField .

# Struct -> EnforcedKey relationship (subproperty of hasField)
:hasEnforcedKey a owl:ObjectProperty ;
    rdfs:subPropertyOf :hasField ;
    rdfs:domain :Struct ;
    rdfs:range :EnforcedKey .

# Struct -> Protocol relationship (for @derive)
:derivesProtocol a owl:ObjectProperty ;
    rdfs:domain :Struct ;
    rdfs:range :Protocol .
```

#### Data Properties

```turtle
# Field properties
:fieldName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :StructField ;
    rdfs:range xsd:string .

:hasDefaultFieldValue a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :StructField ;
    rdfs:range xsd:boolean .

# Exception properties
:exceptionMessage a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Exception ;
    rdfs:range xsd:string .

:hasCustomMessage a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:domain :Exception ;
    rdfs:range xsd:boolean .
```

### 3.4 Triple Generation Examples

**Simple Struct**:
```turtle
<base#User> a struct:Struct ;
    struct:moduleName "User"^^xsd:string ;
    struct:hasField <base#User/field/name> ;
    struct:hasField <base#User/field/email> ;
    struct:hasField <base#User/field/age> ;
    core:hasSourceLocation <base#file/lib/user.ex/L1-5> .

<base#Module.User> struct:containsStruct <base#User> .

<base#User/field/name> a struct:StructField ;
    struct:fieldName "name"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .

<base#User/field/email> a struct:StructField ;
    struct:fieldName "email"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .

<base#User/field/age> a struct:StructField ;
    struct:fieldName "age"^^xsd:string ;
    struct:hasDefaultFieldValue "true"^^xsd:boolean .
```

**Struct with Enforced Keys**:
```turtle
<base#Account> a struct:Struct ;
    struct:moduleName "Account"^^xsd:string ;
    struct:hasEnforcedKey <base#Account/field/username> ;
    struct:hasEnforcedKey <base#Account/field/password> ;
    struct:hasField <base#Account/field/active> .

<base#Account/field/username> a struct:EnforcedKey ;
    struct:fieldName "username"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .

<base#Account/field/password> a struct:EnforcedKey ;
    struct:fieldName "password"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .

<base#Account/field/active> a struct:StructField ;
    struct:fieldName "active"^^xsd:string ;
    struct:hasDefaultFieldValue "true"^^xsd:boolean .
```

**Struct with Protocol Derivation**:
```turtle
<base#Product> a struct:Struct ;
    struct:moduleName "Product"^^xsd:string ;
    struct:derivesProtocol <base#Inspect> ;
    struct:derivesProtocol <base#Jason.Encoder> ;
    struct:hasField <base#Product/field/name> ;
    struct:hasField <base#Product/field/price> .

<base#Inspect> a struct:Protocol .
<base#Jason.Encoder> a struct:Protocol .

<base#Product/field/name> a struct:StructField ;
    struct:fieldName "name"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .

<base#Product/field/price> a struct:StructField ;
    struct:fieldName "price"^^xsd:string ;
    struct:hasDefaultFieldValue "true"^^xsd:boolean .
```

**Exception**:
```turtle
<base#NotFoundError> a struct:Exception ;
    struct:moduleName "NotFoundError"^^xsd:string ;
    struct:exceptionMessage "Resource not found"^^xsd:string ;
    struct:hasCustomMessage "false"^^xsd:boolean ;
    struct:hasField <base#NotFoundError/field/message> ;
    struct:hasField <base#NotFoundError/field/resource_id> .

<base#Module.NotFoundError> struct:containsStruct <base#NotFoundError> .

<base#NotFoundError/field/message> a struct:StructField ;
    struct:fieldName "message"^^xsd:string ;
    struct:hasDefaultFieldValue "true"^^xsd:boolean .

<base#NotFoundError/field/resource_id> a struct:StructField ;
    struct:fieldName "resource_id"^^xsd:string ;
    struct:hasDefaultFieldValue "false"^^xsd:boolean .
```

**Exception with Custom Message**:
```turtle
<base#ValidationError> a struct:Exception ;
    struct:moduleName "ValidationError"^^xsd:string ;
    struct:hasCustomMessage "true"^^xsd:boolean ;
    struct:hasField <base#ValidationError/field/errors> .

# Note: hasCustomMessage indicates module defines custom message/1 function
```

### 3.5 Builder Helpers Usage

From `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`:

```elixir
# Type triple
Helpers.type_triple(struct_iri, Structure.Struct)
#=> {struct_iri, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Struct>}

# Field type
Helpers.type_triple(field_iri, Structure.StructField)
Helpers.type_triple(field_iri, Structure.EnforcedKey)

# Exception type
Helpers.type_triple(exception_iri, Structure.Exception)

# Datatype property (string)
Helpers.datatype_property(field_iri, Structure.fieldName(), "name", RDF.XSD.String)
#=> {field_iri, Structure.fieldName(), RDF.XSD.String.new("name")}

# Datatype property (boolean)
Helpers.datatype_property(field_iri, Structure.hasDefaultFieldValue(), true, RDF.XSD.Boolean)
#=> {field_iri, Structure.hasDefaultFieldValue(), RDF.XSD.Boolean.new(true)}

# Object property
Helpers.object_property(struct_iri, Structure.hasField(), field_iri)
#=> {struct_iri, Structure.hasField(), field_iri}

# Enforced key relationship
Helpers.object_property(struct_iri, Structure.hasEnforcedKey(), field_iri)
#=> {struct_iri, Structure.hasEnforcedKey(), field_iri}

# Protocol derivation
Helpers.object_property(struct_iri, Structure.derivesProtocol(), protocol_iri)
#=> {struct_iri, Structure.derivesProtocol(), protocol_iri}

# Exception properties
Helpers.datatype_property(exception_iri, Structure.exceptionMessage(), "not found", RDF.XSD.String)
Helpers.datatype_property(exception_iri, Structure.hasCustomMessage(), false, RDF.XSD.Boolean)
```

### 3.6 Handling Edge Cases

#### Module Name Context

Since struct extractor doesn't include the module name, we need it from context:

```elixir
defp build_struct(struct_info, context) do
  # Require module_name in context
  module_name = context.module_name ||
    raise ArgumentError, "module_name required in context for struct building"

  struct_iri = IRI.for_module(context.base_iri, module_name)

  # Build triples...
end
```

#### Enforced Keys

Fields in enforce_keys list should be typed as EnforcedKey and use hasEnforcedKey property:

```elixir
defp build_field_triple(struct_iri, field, struct_info, context) do
  field_iri = generate_field_iri(struct_iri, field)

  # Determine class and property based on enforcement
  {field_class, field_property} = if field.name in struct_info.enforce_keys do
    {Structure.EnforcedKey, Structure.hasEnforcedKey()}
  else
    {Structure.StructField, Structure.hasField()}
  end

  [
    # Type
    Helpers.type_triple(field_iri, field_class),
    # Name
    Helpers.datatype_property(field_iri, Structure.fieldName(),
                              Atom.to_string(field.name), RDF.XSD.String),
    # Has default
    Helpers.datatype_property(field_iri, Structure.hasDefaultFieldValue(),
                              field.has_default, RDF.XSD.Boolean),
    # Link to struct
    Helpers.object_property(struct_iri, field_property, field_iri)
  ]
end
```

#### Protocol Derivation

Handle @derive directives with protocol references:

```elixir
defp build_derives_triples(struct_iri, struct_info, context) do
  Enum.flat_map(struct_info.derives, fn derive_info ->
    Enum.flat_map(derive_info.protocols, fn protocol_spec ->
      # Extract protocol name (may be atom, list, or tuple with options)
      protocol_name = extract_protocol_name(protocol_spec.protocol)
      protocol_iri = IRI.for_module(context.base_iri, protocol_name)

      [
        # Struct derives protocol
        Helpers.object_property(struct_iri, Structure.derivesProtocol(), protocol_iri)
      ]
    end)
  end)
end

defp extract_protocol_name(protocol) when is_list(protocol) do
  Enum.join(protocol, ".")
end

defp extract_protocol_name(protocol) when is_atom(protocol) do
  Atom.to_string(protocol)
end

defp extract_protocol_name({protocol, _opts}) do
  extract_protocol_name(protocol)
end
```

#### Exception Default Message

Extract default message from :message field:

```elixir
defp build_exception_specific_triples(exception_iri, exception_info) do
  triples = []

  # Add default message if present
  triples = if exception_info.default_message do
    [Helpers.datatype_property(exception_iri, Structure.exceptionMessage(),
                               exception_info.default_message, RDF.XSD.String) | triples]
  else
    triples
  end

  # Add custom message flag
  triples = [
    Helpers.datatype_property(exception_iri, Structure.hasCustomMessage(),
                             exception_info.has_custom_message, RDF.XSD.Boolean)
    | triples
  ]

  triples
end
```

#### Field Order Preservation

Fields are already ordered in the extractor's fields list. Preserve this when generating triples:

```elixir
defp build_field_triples(struct_iri, struct_info, context) do
  # Enum.map preserves order
  Enum.map(struct_info.fields, fn field ->
    build_field_triple(struct_iri, field, struct_info, context)
  end)
end
```

## 4. Implementation Steps

### 4.1 Step 1: Create Struct Builder Skeleton (1 hour)

**File**: `lib/elixir_ontologies/builders/struct_builder.ex`

Tasks:
1. Create module with @moduledoc documentation
2. Define `build_struct/2` and `build_exception/2` function signatures
3. Add helper functions for IRI generation
4. Import necessary namespaces (Helpers, IRI, Structure, Core)
5. Add basic structure with placeholder implementations

**Code Structure**:
```elixir
defmodule ElixirOntologies.Builders.StructBuilder do
  @moduledoc """
  Builds RDF triples for Elixir structs and exceptions.

  This module transforms struct-related extractor results into RDF triples
  following the elixir-structure.ttl ontology. It handles:

  - Struct definitions (defstruct) with fields and defaults
  - Struct fields (StructField and EnforcedKey)
  - Enforced keys (@enforce_keys)
  - Protocol derivation (@derive)
  - Exception definitions (defexception)
  - Exception-specific properties (default message, custom message)

  ## Struct vs Exception

  **Structs** are Elixir's data modeling mechanism:
  - Define named fields with optional defaults
  - Support @enforce_keys for required fields
  - Can derive protocol implementations with @derive
  - Module-scoped (one struct per module)

  **Exceptions** are special structs:
  - Subclass of Struct in ontology
  - Always have :message field
  - Can have default message string
  - Can define custom message/1 function
  - Implement Exception behaviour

  ## Usage

      alias ElixirOntologies.Builders.{StructBuilder, Context}
      alias ElixirOntologies.Extractors.Struct

      # Build struct definition
      struct_info = %Struct{fields: [...], enforce_keys: [...], derives: [...]}
      context = Context.new(base_iri: "https://example.org/code#", module_name: "User")
      {struct_iri, triples} = StructBuilder.build_struct(struct_info, context)

      # Build exception definition
      exception_info = %Struct.Exception{fields: [...], default_message: "..."}
      context = Context.new(base_iri: "https://example.org/code#", module_name: "MyError")
      {exception_iri, triples} = StructBuilder.build_exception(exception_info, context)
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Struct, as: StructExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Struct Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a struct definition.

  Takes a struct extraction result and builder context, returns the struct IRI
  and a list of RDF triples representing the struct, fields, enforced keys,
  and derived protocols.

  ## Parameters

  - `struct_info` - Struct extraction result from `Struct.extract_from_body/1`
  - `context` - Builder context with base IRI and module name

  ## Returns

  A tuple `{struct_iri, triples}` where:
  - `struct_iri` - The IRI of the struct (same as module IRI)
  - `triples` - List of RDF triples describing the struct and fields

  ## Context Requirements

  The context MUST include `module_name` field, as the struct extractor
  doesn't capture the module name itself.

  ## Examples

      iex> alias ElixirOntologies.Builders.{StructBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Struct
      iex> struct_info = %Struct{
      ...>   fields: [
      ...>     %{name: :name, has_default: false, default_value: nil, location: nil}
      ...>   ],
      ...>   enforce_keys: [:name],
      ...>   derives: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#", module_name: "User")
      iex> {struct_iri, _triples} = StructBuilder.build_struct(struct_info, context)
      iex> to_string(struct_iri)
      "https://example.org/code#User"
  """
  @spec build_struct(StructExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_struct(struct_info, context)

  # ===========================================================================
  # Public API - Exception Building
  # ===========================================================================

  @doc """
  Builds RDF triples for an exception definition.

  Takes an exception extraction result and builder context, returns the exception IRI
  and a list of RDF triples representing the exception as a special struct.

  ## Parameters

  - `exception_info` - Exception extraction result from `Struct.extract_exception_from_body/1`
  - `context` - Builder context with base IRI and module name

  ## Returns

  A tuple `{exception_iri, triples}` where:
  - `exception_iri` - The IRI of the exception (same as module IRI)
  - `triples` - List of RDF triples describing the exception

  ## Examples

      iex> alias ElixirOntologies.Builders.{StructBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Struct
      iex> exception_info = %Struct.Exception{
      ...>   fields: [
      ...>     %{name: :message, has_default: true, default_value: "error", location: nil}
      ...>   ],
      ...>   enforce_keys: [],
      ...>   derives: [],
      ...>   has_custom_message: false,
      ...>   default_message: "error",
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#", module_name: "MyError")
      iex> {exception_iri, _triples} = StructBuilder.build_exception(exception_info, context)
      iex> to_string(exception_iri)
      "https://example.org/code#MyError"
  """
  @spec build_exception(StructExtractor.Exception.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_exception(exception_info, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp generate_struct_iri(context)
  defp generate_field_iri(struct_iri, field)
  defp extract_protocol_name(protocol)
  # ... etc
end
```

### 4.2 Step 2: Implement Struct Triple Generation (2 hours)

Implement functions for struct definition triples:

1. **IRI Generation**:
```elixir
defp generate_struct_iri(context) do
  # Struct IRI is same as module IRI
  module_name = context.module_name ||
    raise ArgumentError, "module_name required in context for struct building"

  IRI.for_module(context.base_iri, module_name)
end
```

2. **Type Triple**:
```elixir
defp build_type_triple(struct_iri, :struct) do
  Helpers.type_triple(struct_iri, Structure.Struct)
end

defp build_type_triple(exception_iri, :exception) do
  Helpers.type_triple(exception_iri, Structure.Exception)
end
```

3. **Module Contains Struct Relationship**:
```elixir
defp build_module_contains_struct_triple(struct_iri, context) do
  module_iri = IRI.for_module(context.base_iri, context.module_name)
  Helpers.object_property(module_iri, Structure.containsStruct(), struct_iri)
end
```

### 4.3 Step 3: Implement Field Handling (2 hours)

Generate triples for struct fields:

```elixir
defp build_field_triples(struct_iri, struct_info, context) do
  Enum.flat_map(struct_info.fields, fn field ->
    build_field_triple(struct_iri, field, struct_info, context)
  end)
end

defp build_field_triple(struct_iri, field, struct_info, context) do
  # Generate field IRI
  field_iri = generate_field_iri(struct_iri, field)

  # Determine if field is enforced
  is_enforced = field.name in struct_info.enforce_keys

  # Choose class and property based on enforcement
  {field_class, field_property} = if is_enforced do
    {Structure.EnforcedKey, Structure.hasEnforcedKey()}
  else
    {Structure.StructField, Structure.hasField()}
  end

  # Build field triples
  [
    # rdf:type (StructField or EnforcedKey)
    Helpers.type_triple(field_iri, field_class),
    # fieldName
    Helpers.datatype_property(field_iri, Structure.fieldName(),
                              Atom.to_string(field.name), RDF.XSD.String),
    # hasDefaultFieldValue
    Helpers.datatype_property(field_iri, Structure.hasDefaultFieldValue(),
                              field.has_default, RDF.XSD.Boolean),
    # Link to struct (hasField or hasEnforcedKey)
    Helpers.object_property(struct_iri, field_property, field_iri)
  ]
end

defp generate_field_iri(struct_iri, field) do
  field_name = Atom.to_string(field.name)
  RDF.IRI.new("#{struct_iri}/field/#{field_name}")
end
```

### 4.4 Step 4: Implement Enforced Keys Handling (1 hour)

Enforced keys are handled in field generation above, but we can add helper:

```elixir
defp build_enforced_key_triples(struct_iri, struct_info, context) do
  # Already handled in build_field_triples
  # This function is called separately for clarity but doesn't add new triples
  []
end
```

### 4.5 Step 5: Implement Protocol Derivation (2 hours)

Build triples for @derive directives:

```elixir
defp build_derives_triples(struct_iri, struct_info, context) do
  Enum.flat_map(struct_info.derives, fn derive_info ->
    Enum.flat_map(derive_info.protocols, fn protocol_spec ->
      # Extract protocol name (handles different formats)
      protocol_name = extract_protocol_name(protocol_spec.protocol)
      protocol_iri = IRI.for_module(context.base_iri, protocol_name)

      [
        # Struct derivesProtocol Protocol
        Helpers.object_property(struct_iri, Structure.derivesProtocol(), protocol_iri)
      ]
    end)
  end)
end

defp extract_protocol_name(protocol) when is_list(protocol) do
  # Protocol as list: [:String, :Chars] -> "String.Chars"
  Enum.join(protocol, ".")
end

defp extract_protocol_name(protocol) when is_atom(protocol) do
  # Protocol as atom: :Inspect -> "Inspect"
  # Strip Elixir. prefix if present
  protocol
  |> Atom.to_string()
  |> String.trim_leading("Elixir.")
end

defp extract_protocol_name({protocol, _opts}) do
  # Protocol with options: {Jason.Encoder, only: [:name]}
  extract_protocol_name(protocol)
end
```

### 4.6 Step 6: Implement Exception Handling (2 hours)

Add exception-specific triples:

```elixir
defp build_exception_specific_triples(exception_iri, exception_info) do
  [
    # hasCustomMessage boolean
    Helpers.datatype_property(exception_iri, Structure.hasCustomMessage(),
                             exception_info.has_custom_message, RDF.XSD.Boolean)
  ] ++
    build_default_message_triple(exception_iri, exception_info)
end

defp build_default_message_triple(exception_iri, exception_info) do
  case exception_info.default_message do
    nil ->
      []

    message when is_binary(message) ->
      [Helpers.datatype_property(exception_iri, Structure.exceptionMessage(),
                                 message, RDF.XSD.String)]
  end
end
```

### 4.7 Step 7: Integrate All Components (1 hour)

Complete the main `build_struct/2` and `build_exception/2` functions:

```elixir
@spec build_struct(StructExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_struct(struct_info, context) do
  # Generate struct IRI (same as module IRI)
  struct_iri = generate_struct_iri(context)

  # Build all triples
  triples =
    [
      # Core struct triple
      build_type_triple(struct_iri, :struct),
      # Module contains struct relationship
      build_module_contains_struct_triple(struct_iri, context)
    ] ++
      # Fields (includes enforced keys)
      build_field_triples(struct_iri, struct_info, context) ++
      # Protocol derivation
      build_derives_triples(struct_iri, struct_info, context)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {struct_iri, triples}
end

@spec build_exception(StructExtractor.Exception.t(), Context.t()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_exception(exception_info, context) do
  # Generate exception IRI (same as module IRI)
  exception_iri = generate_struct_iri(context)

  # Build all triples
  triples =
    [
      # Core exception triple (Exception is subclass of Struct)
      build_type_triple(exception_iri, :exception),
      # Module contains struct relationship
      build_module_contains_struct_triple(exception_iri, context)
    ] ++
      # Fields (includes enforced keys)
      build_field_triples(exception_iri, exception_info, context) ++
      # Protocol derivation
      build_derives_triples(exception_iri, exception_info, context) ++
      # Exception-specific properties
      build_exception_specific_triples(exception_iri, exception_info)

  # Flatten and deduplicate
  triples = List.flatten(triples) |> Enum.uniq()

  {exception_iri, triples}
end
```

## 5. Testing Strategy

### 5.1 Unit Tests (File: `test/elixir_ontologies/builders/struct_builder_test.exs`)

**Target**: 18+ comprehensive tests covering structs and exceptions

#### Test Categories

**Struct Building Tests** (10 tests):

1. **Basic Struct Building** (3 tests):
   - Simple struct with fields without defaults
   - Struct with fields with defaults
   - Struct with no fields (edge case)

2. **Enforced Keys** (3 tests):
   - Struct with enforced keys (EnforcedKey class)
   - Struct with hasEnforcedKey property
   - Mix of enforced and non-enforced fields

3. **Protocol Derivation** (2 tests):
   - Struct with single @derive
   - Struct with multiple @derive directives

4. **Field Properties** (2 tests):
   - Field without default (hasDefaultFieldValue: false)
   - Field with default (hasDefaultFieldValue: true)

**Exception Building Tests** (8 tests):

5. **Basic Exception Building** (2 tests):
   - Simple exception with :message field
   - Exception with multiple fields

6. **Exception Messages** (3 tests):
   - Exception with default message
   - Exception with custom message/1 (hasCustomMessage: true)
   - Exception without default message

7. **Exception as Struct** (2 tests):
   - Exception has Exception class (subclass of Struct)
   - Exception fields work like struct fields

8. **Exception with Enforced Keys** (1 test):
   - Exception with @enforce_keys

**Integration Tests** (2+ tests):

9. **Complete Struct** (1 test):
   - Extract and build real struct with all features

10. **Complete Exception** (1 test):
    - Extract and build real exception

### 5.2 Example Test Cases

```elixir
defmodule ElixirOntologies.Builders.StructBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{StructBuilder, Context}
  alias ElixirOntologies.Extractors.Struct
  alias ElixirOntologies.NS.Structure

  describe "build_struct/2 basic struct" do
    test "builds struct with fields" do
      struct_info = %Struct{
        fields: [
          %{name: :name, has_default: false, default_value: nil, location: nil},
          %{name: :email, has_default: false, default_value: nil, location: nil},
          %{name: :age, has_default: true, default_value: 0, location: nil}
        ],
        enforce_keys: [],
        derives: [],
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "User")

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, context)

      # Verify struct IRI
      assert to_string(struct_iri) == "https://example.org/code#User"

      # Verify struct type
      assert {struct_iri, RDF.type(), Structure.Struct} in triples

      # Verify module containsStruct
      module_iri = ~I<https://example.org/code#Module.User>
      assert {module_iri, Structure.containsStruct(), struct_iri} in triples

      # Verify fields exist
      name_field_iri = ~I<https://example.org/code#User/field/name>
      email_field_iri = ~I<https://example.org/code#User/field/email>
      age_field_iri = ~I<https://example.org/code#User/field/age>

      assert {struct_iri, Structure.hasField(), name_field_iri} in triples
      assert {struct_iri, Structure.hasField(), email_field_iri} in triples
      assert {struct_iri, Structure.hasField(), age_field_iri} in triples

      # Verify field types
      assert {name_field_iri, RDF.type(), Structure.StructField} in triples
      assert {email_field_iri, RDF.type(), Structure.StructField} in triples
      assert {age_field_iri, RDF.type(), Structure.StructField} in triples

      # Verify field names
      assert Enum.any?(triples, fn
               {^name_field_iri, pred, obj} ->
                 pred == Structure.fieldName() and RDF.Literal.value(obj) == "name"

               _ ->
                 false
             end)

      # Verify hasDefaultFieldValue for age
      assert Enum.any?(triples, fn
               {^age_field_iri, pred, obj} ->
                 pred == Structure.hasDefaultFieldValue() and RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "builds struct with enforced keys" do
      struct_info = %Struct{
        fields: [
          %{name: :username, has_default: false, default_value: nil, location: nil},
          %{name: :password, has_default: false, default_value: nil, location: nil},
          %{name: :active, has_default: true, default_value: true, location: nil}
        ],
        enforce_keys: [:username, :password],
        derives: [],
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "Account")

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, context)

      # Verify enforced keys
      username_iri = ~I<https://example.org/code#Account/field/username>
      password_iri = ~I<https://example.org/code#Account/field/password>
      active_iri = ~I<https://example.org/code#Account/field/active>

      # Enforced keys should be EnforcedKey class
      assert {username_iri, RDF.type(), Structure.EnforcedKey} in triples
      assert {password_iri, RDF.type(), Structure.EnforcedKey} in triples

      # Non-enforced field should be StructField
      assert {active_iri, RDF.type(), Structure.StructField} in triples

      # Enforced keys use hasEnforcedKey property
      assert {struct_iri, Structure.hasEnforcedKey(), username_iri} in triples
      assert {struct_iri, Structure.hasEnforcedKey(), password_iri} in triples

      # Non-enforced uses hasField
      assert {struct_iri, Structure.hasField(), active_iri} in triples
    end

    test "builds struct with protocol derivation" do
      struct_info = %Struct{
        fields: [
          %{name: :name, has_default: false, default_value: nil, location: nil}
        ],
        enforce_keys: [],
        derives: [
          %ElixirOntologies.Extractors.Helpers.DeriveInfo{
            protocols: [
              %{protocol: :Inspect, options: nil},
              %{protocol: [:Jason, :Encoder], options: [only: [:name]]}
            ],
            location: nil
          }
        ],
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "Product")

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, context)

      # Verify protocol derivation
      inspect_iri = ~I<https://example.org/code#Inspect>
      jason_encoder_iri = ~I<https://example.org/code#Jason.Encoder>

      assert {struct_iri, Structure.derivesProtocol(), inspect_iri} in triples
      assert {struct_iri, Structure.derivesProtocol(), jason_encoder_iri} in triples
    end
  end

  describe "build_exception/2 basic exception" do
    test "builds simple exception" do
      exception_info = %Struct.Exception{
        fields: [
          %{name: :message, has_default: true, default_value: "not found", location: nil}
        ],
        enforce_keys: [],
        derives: [],
        has_custom_message: false,
        default_message: "not found",
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "NotFoundError")

      {exception_iri, triples} = StructBuilder.build_exception(exception_info, context)

      # Verify exception IRI
      assert to_string(exception_iri) == "https://example.org/code#NotFoundError"

      # Verify exception type (subclass of Struct)
      assert {exception_iri, RDF.type(), Structure.Exception} in triples

      # Verify exception message
      assert Enum.any?(triples, fn
               {^exception_iri, pred, obj} ->
                 pred == Structure.exceptionMessage() and
                   RDF.Literal.value(obj) == "not found"

               _ ->
                 false
             end)

      # Verify hasCustomMessage
      assert Enum.any?(triples, fn
               {^exception_iri, pred, obj} ->
                 pred == Structure.hasCustomMessage() and
                   RDF.Literal.value(obj) == false

               _ ->
                 false
             end)
    end

    test "builds exception with custom message" do
      exception_info = %Struct.Exception{
        fields: [
          %{name: :errors, has_default: false, default_value: nil, location: nil}
        ],
        enforce_keys: [],
        derives: [],
        has_custom_message: true,
        default_message: nil,
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#", module_name: "ValidationError")

      {exception_iri, triples} = StructBuilder.build_exception(exception_info, context)

      # Verify hasCustomMessage is true
      assert Enum.any?(triples, fn
               {^exception_iri, pred, obj} ->
                 pred == Structure.hasCustomMessage() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)

      # Should not have exceptionMessage triple (no default)
      refute Enum.any?(triples, fn
               {^exception_iri, pred, _obj} ->
                 pred == Structure.exceptionMessage()

               _ ->
                 false
             end)
    end
  end

  describe "integration tests" do
    test "extract and build real struct" do
      code = """
      defmodule User do
        @enforce_keys [:name]
        @derive Inspect
        defstruct [:name, :email, age: 0]
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract
      struct_info = Struct.extract_from_body!(body)

      # Build
      context = Context.new(base_iri: "https://example.org/code#", module_name: "User")
      {struct_iri, triples} = StructBuilder.build_struct(struct_info, context)

      # Verify complete graph
      assert length(triples) >= 10

      # Verify struct exists
      assert {struct_iri, RDF.type(), Structure.Struct} in triples

      # Verify fields
      name_iri = ~I<https://example.org/code#User/field/name>
      email_iri = ~I<https://example.org/code#User/field/email>
      age_iri = ~I<https://example.org/code#User/field/age>

      assert {struct_iri, Structure.hasEnforcedKey(), name_iri} in triples
      assert {struct_iri, Structure.hasField(), email_iri} in triples
      assert {struct_iri, Structure.hasField(), age_iri} in triples

      # Verify protocol derivation
      inspect_iri = ~I<https://example.org/code#Inspect>
      assert {struct_iri, Structure.derivesProtocol(), inspect_iri} in triples
    end

    test "extract and build real exception" do
      code = """
      defmodule NotFoundError do
        defexception [:message, :resource_id]

        def message(error) do
          "Resource \#{error.resource_id} not found"
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract
      exception_info = Struct.extract_exception_from_body!(body)

      # Build
      context = Context.new(base_iri: "https://example.org/code#", module_name: "NotFoundError")
      {exception_iri, triples} = StructBuilder.build_exception(exception_info, context)

      # Verify exception type
      assert {exception_iri, RDF.type(), Structure.Exception} in triples

      # Verify hasCustomMessage (has custom message/1)
      assert Enum.any?(triples, fn
               {^exception_iri, pred, obj} ->
                 pred == Structure.hasCustomMessage() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end
  end
end
```

### 5.3 Integration Tests

Test the complete flow from extractor to builder with real code examples covering:
- Struct with all features (fields, defaults, enforced keys, derives)
- Exception with default and custom messages
- Edge cases (empty struct, struct with only enforced fields)

## 6. Success Criteria

This phase is complete when:

1. StructBuilder module exists with complete documentation
2. `build_struct/2` correctly transforms `Struct.t()` to RDF triples
3. `build_exception/2` correctly transforms `Exception.t()` to RDF triples
4. Struct class is correctly assigned
5. Exception class is correctly assigned (subclass of Struct)
6. StructField and EnforcedKey classes are correctly assigned
7. Field datatype properties are generated (fieldName, hasDefaultFieldValue)
8. hasField and hasEnforcedKey relationships are created correctly
9. Protocol derivation relationships work (derivesProtocol)
10. Struct IRIs follow module pattern
11. Field IRIs follow struct/field pattern
12. Enforced keys are correctly typed and linked
13. Exception-specific properties work (exceptionMessage, hasCustomMessage)
14. Field order is preserved
15. All functions have @spec typespecs
16. Test suite passes with 18+ comprehensive tests
17. 100% code coverage for StructBuilder
18. Documentation includes clear usage examples
19. No regressions in existing tests

## 7. Risk Mitigation

### Risk 1: Module Name Not in Extractor
**Issue**: Struct extractor doesn't capture the module name.
**Mitigation**:
- Require `module_name` in context
- Document this requirement clearly
- Raise clear error if module_name missing
- Consistent with Protocol and Behaviour builders

### Risk 2: Field IRI Pattern
**Issue**: Field IRI pattern (struct/field/name) not documented in ontology.
**Mitigation**:
- Use clear, hierarchical pattern
- Document pattern in builder
- Consider adding to IRI module if used elsewhere
- Consistent with other builders' patterns

### Risk 3: Protocol Derivation References
**Issue**: @derive creates references to protocols that may not exist yet.
**Mitigation**:
- Generate IRIs without validating protocol existence
- SHACL validation will catch invalid references
- Document that derivesProtocol creates soft references
- Consistent with other reference patterns (implementsProtocol, etc.)

### Risk 4: Default Value Complexity
**Issue**: Default values can be complex expressions, not just literals.
**Mitigation**:
- For V1, only track boolean hasDefaultFieldValue
- Don't serialize actual default value (too complex for RDF)
- Add TODO for future enhancement if needed
- Document limitation

### Risk 5: Protocol Derivation Options
**Issue**: @derive can include protocol-specific options.
**Mitigation**:
- For V1, only track protocol reference, ignore options
- Options are compile-time configuration, not structural
- Document that options are not captured
- Can be enhanced later if needed

## 8. Future Enhancements

### Phase 12.2.4 Dependencies
After this phase, we can implement:
- Type system builder (uses structs for @type definitions)
- Complete data modeling graph
- Struct validation rules in SHACL

### Later Optimizations
- Cache field IRIs for reuse
- Batch triple generation for related structs
- Parallel building of independent structs

### Enhanced Features
- Capture default values as RDF literals (for simple cases)
- Capture @derive options as structured data
- Link exception to Exception behaviour implementation
- Track struct usage patterns (where instantiated)
- Generate struct validation SHACL shapes from enforced keys
- Support for embedded structs (@embedded_schema)

## 9. Estimated Timeline

| Task | Estimated Time | Dependencies |
|------|----------------|--------------|
| Create skeleton | 1 hour | None |
| Struct triple generation | 2 hours | Skeleton |
| Field handling | 2 hours | Struct triples |
| Enforced keys handling | 1 hour | Field handling |
| Protocol derivation | 2 hours | Struct triples |
| Exception handling | 2 hours | Struct triples |
| Integration and polish | 1 hour | All above |
| Unit tests (18+ tests) | 4 hours | All above |
| Integration tests | 1 hour | Unit tests |
| Documentation and examples | 1 hour | All above |
| Code review and fixes | 2 hours | All above |
| **Total** | **19 hours** | |

## 10. References

### Internal Documentation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/struct.ex` - Struct extractor
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Builder helpers
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex` - Builder context
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/protocol_builder.ex` - Protocol builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/behaviour_builder.ex` - Behaviour builder (reference)
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` - IRI generation
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/ns.ex` - Namespaces
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl` - Struct ontology definitions

### Related Phase Documents
- `/home/ducky/.claude/plans/parsed-nibbling-thimble.md` - Phase 12 master plan (section 12.2.3)
- `/home/ducky/code/elixir-ontologies/notes/features/phase-12-2-1-protocol-builder.md` - Protocol builder (similar pattern)
- `/home/ducky/code/elixir-ontologies/notes/features/phase-12-2-2-behaviour-builder.md` - Behaviour builder (most recent)
- `/home/ducky/code/elixir-ontologies/notes/features/phase-12-1-2-module-builder.md` - Module builder
- `/home/ducky/code/elixir-ontologies/notes/features/phase-12-1-3-function-builder.md` - Function builder

### External Resources
- RDF.ex documentation: https://hexdocs.pm/rdf/
- W3C RDF Primer: https://www.w3.org/TR/rdf11-primer/
- Elixir Structs documentation: https://hexdocs.pm/elixir/Kernel.html#defstruct/1
- Elixir Exceptions guide: https://hexdocs.pm/elixir/exceptions.html
- Elixir Protocol derivation: https://hexdocs.pm/elixir/Protocol.html#module-deriving
