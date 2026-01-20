# Developer Getting Started Guide

## Overview

This guide explains how to extend the Elixir Ontologies system - adding new code constructs to the ontology, implementing extractors and builders, and creating validation rules.

**Audience**: Developers who want to extend the system to support new Elixir language features or custom analysis capabilities.

## Table of Contents

- [Development Setup](#development-setup)
- [Understanding the Architecture](#understanding-the-architecture)
- [Adding to the Ontology](#adding-to-the-ontology)
- [Implementing an Extractor](#implementing-an-extractor)
- [Implementing a Builder](#implementing-a-builder)
- [Adding Validation Rules](#adding-validation-rules)
- [Testing Your Changes](#testing-your-changes)
- [Integration Workflow](#integration-workflow)

## Development Setup

### Prerequisites

```bash
# Clone repository
git clone https://github.com/your-org/elixir-ontologies.git
cd elixir-ontologies

# Install dependencies
mix deps.get

# Run tests
mix test

# Compile
mix compile
```

### Development Workflow

```bash
# Create a feature branch
git checkout -b feature/my-new-construct

# Make changes and test
mix test.watch

# Format code
mix format

# Run type checker (optional)
mix dialyzer
```

## Understanding the Architecture

Before extending the system, understand the data flow:

```mermaid
graph LR
    Source[Elixir Source] --> Parser[Parser]
    Parser --> AST[AST]
    AST --> Extractor[Extractor]
    Extractor --> Structured[Structured Data]
    Structured --> Builder[Builder]
    Builder --> RDF[RDF Triples]
    RDF --> Validator[Validator]
    Validator --> Report[Validation Report]

    style Extractor fill:#ffe1f5
    style Builder fill:#e1ffe1
    style Validator fill:#e1f5ff
```

**Key Principle**: Separation of concerns
- **Extractors**: Transform AST → Structured data (no RDF)
- **Builders**: Transform Structured data → RDF triples
- **Validators**: Validate RDF against ontology constraints

## Adding to the Ontology

### 1. Identify the Ontology Layer

Choose which ontology file to modify:

| Ontology | Purpose | When to Add |
|----------|---------|-------------|
| `elixir-core.ttl` | AST primitives | New expression/statement types |
| `elixir-structure.ttl` | Elixir constructs | New module/function types |
| `elixir-otp.ttl` | OTP patterns | New OTP behaviors |
| `elixir-evolution.ttl` | Provenance | New metadata types |
| `elixir-shapes.ttl` | Validation | New validation rules |

### 2. Define Classes and Properties

Add to the appropriate `.ttl` file:

```turtle
@prefix : <https://w3id.org/elixir-code/structure#> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

# Define a new class
:MyConstruct a owl:Class ;
    rdfs:label "My Construct"@en ;
    rdfs:comment "Description of my new construct."@en ;
    rdfs:subClassOf :Expression .

# Define a property for the class
:myProperty a owl:DatatypeProperty ;
    rdfs:label "my property"@en ;
    rdfs:comment "Description of this property."@en ;
    rdfs:domain :MyConstruct ;
    rdfs:range xsd:string .
```

### 3. Add to Namespace Module

Update `lib/elixir_ontologies/ns.ex`:

```elixir
defmodule ElixirOntologies.NS.Structure do
  # ... existing definitions

  @my_construct RDF.iri("https://w3id.org/elixir-code/structure#MyConstruct")
  @my_property RDF.iri("https://w3id.org/elixir-code/structure#myProperty")

  def my_construct, do: @my_construct
  def my_property, do: @my_property
end
```

### 4. Add SHACL Validation (Optional)

Add to `elixir-shapes.ttl`:

```turtle
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix struct: <https://w3id.org/elixir-code/structure#> .

:MyConstructShape a sh:NodeShape ;
    sh:targetClass struct:MyConstruct ;
    sh:property [
        sh:path struct:myProperty ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
```

## Implementing an Extractor

### Step 1: Create the Extractor Module

Create `lib/elixir_ontologies/extractors/my_construct.ex`:

```elixir
defmodule ElixirOntologies.Extractors.MyConstruct do
  @moduledoc """
  Extracts my custom construct from Elixir AST.

  This extractor identifies and parses the `:my_construct` AST node,
  returning structured data for building RDF triples.
  """

  alias ElixirOntologies.Analyzer.Location

  @type t :: %__MODULE__{
          type: :my_construct,
          name: atom(),
          options: keyword(),
          location: Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :type,
    :name,
    :options,
    :location,
    :metadata
  ]

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Checks if AST node represents this construct.
  """
  @spec my_construct?(term()) :: boolean()
  def my_construct?({:my_construct, _meta, _args}), do: true
  def my_construct?(_), do: false

  @doc """
  Extracts construct from AST node.
  """
  @spec extract(term(), map()) :: {:ok, t()} | {:error, term()}
  def extract({:my_construct, meta, args}, context) do
    location = Location.extract(meta, context)
    {name, options} = parse_args(args)

    result = %__MODULE__{
      type: :my_construct,
      name: name,
      options: options,
      location: location,
      metadata: extract_metadata(meta)
    }

    {:ok, result}
  end

  def extract(_ast, _context), do: {:error, :not_my_construct}

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp parse_args(args) when is_list(args) do
    case args do
      [name | options] when is_atom(name) -> {name, options}
      _ -> {:default, []}
    end
  end

  defp parse_args(_), do: {:default, []}

  defp extract_metadata(meta) do
    %{
      line: Keyword.get(meta, :line),
      column: Keyword.get(meta, :column)
    }
  end
end
```

### Step 2: Register in NodeMatchers

Update `lib/elixir_ontologies/analyzer/matchers.ex`:

```elixir
defmodule ElixirOntologies.Analyzer.Matchers do
  alias ElixirOntologies.Extractors.MyConstruct

  # ... existing matchers

  def my_construct?(ast), do: MyConstruct.my_construct?(ast)
end
```

### Step 3: Add to ASTWalker

The ASTWalker will automatically call your extractor during tree traversal.

### Step 4: Write Tests

Create `test/elixir_ontologies/extractors/my_construct_test.exs`:

```elixir
defmodule ElixirOntologies.Extractors.MyConstructTest do
  use ExUnit.Case
  alias ElixirOntologies.Extractors.MyConstruct

  describe "my_construct?/1" do
    test "returns true for my_construct nodes" do
      ast = {:my_construct, [line: 1], [:foo]}
      assert MyConstruct.my_construct?(ast)
    end

    test "returns false for other nodes" do
      ast = {:def, [line: 1], [:foo, [do: nil]]}
      refute MyConstruct.my_construct?(ast)
    end
  end

  describe "extract/2" do
    test "extracts construct with name and options" do
      ast = {:my_construct, [line: 5], [:foo, [opt: :value]]}
      context = %{file_path: "test.ex"}

      assert {:ok, result} = MyConstruct.extract(ast, context)
      assert result.type == :my_construct
      assert result.name == :foo
      assert result.options == [opt: :value]
    end
  end
end
```

## Implementing a Builder

### Step 1: Create the Builder Module

Create `lib/elixir_ontologies/builders/my_construct_builder.ex`:

```elixir
defmodule ElixirOntologies.Builders.MyConstructBuilder do
  @moduledoc """
  Builds RDF triples for my custom construct.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias NS.{Core, Structure}

  @doc """
  Builds RDF triples for my construct.
  """
  @spec build(ElixirOntologies.Extractors.MyConstruct.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%ElixirOntologies.Extractors.MyConstruct{} = data, context) do
    # Generate IRI for this construct
    construct_iri = generate_iri(data, context)

    # Build all triples
    triples =
      [
        # Type assertion
        Helpers.type_triple(construct_iri, Structure.MyConstruct),
        # Name property
        Helpers.datatype_property(
          construct_iri,
          Structure.myProperty(),
          Atom.to_string(data.name),
          RDF.XSD.String
        )
      ] ++
        build_option_triples(construct_iri, data.options) ++
        build_location_triple(construct_iri, data, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {construct_iri, triples}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp generate_iri(data, context) do
    # Use consistent IRI pattern
    RDF.iri("#{context.base_iri}my_construct/#{data.name}")
  end

  defp build_option_triples(_subject, []), do: []

  defp build_option_triples(subject, options) do
    Enum.map(options, fn {key, value} ->
      Helpers.datatype_property(
        subject,
        RDF.iri("https://w3id.org/elixir-code/structure##{key}"),
        inspect(value),
        RDF.XSD.String
      )
    end)
  end

  defp build_location_triple(_subject, %{location: nil}, _context), do: []
  defp build_location_triple(_subject, _data, %Context{file_path: nil}), do: []

  defp build_location_triple(subject, data, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    location_iri = IRI.for_source_location(
      file_iri,
      data.location.start_line,
      data.location.end_line || data.location.start_line
    )

    [Helpers.object_property(subject, Core.hasSourceLocation(), location_iri)]
  end
end
```

### Step 2: Register in Orchestrator

Update `lib/elixir_ontologies/builders/orchestrator.ex`:

```elixir
defmodule ElixirOntologies.Builders.Orchestrator do
  alias ElixirOntologies.Builders.MyConstructBuilder

  # In build/2 function, add:
  my_construct_triples =
    Enum.flat_map(my_constructs, fn data ->
      {_, triples} = MyConstructBuilder.build(data, context)
      triples
    end)

  # Concat with other triples
  all_triples = my_construct_triples ++ other_triples
end
```

### Step 3: Write Tests

Create `test/elixir_ontologies/builders/my_construct_builder_test.exs`:

```elixir
defmodule ElixirOntologies.Builders.MyConstructBuilderTest do
  use ExUnit.Case
  alias ElixirOntologies.Builders.{MyConstructBuilder, Context}
  alias ElixirOntologies.Extractors.MyConstruct

  describe "build/2" do
    test "builds triples for my construct" do
      data = %MyConstruct{
        type: :my_construct,
        name: :foo,
        options: [opt: :value],
        location: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} = MyConstructBuilder.build(data, context)

      # Verify IRI
      assert to_string(iri) == "https://example.org/code#my_construct/foo"

      # Verify type triple
      assert {^iri, RDF.type(), _} = Enum.find(triples, fn {s, p, _} ->
        s == iri and p == RDF.type()
      end)

      # Verify name triple
      assert {^iri, _, RDF.literal("foo")} = Enum.find(triples, fn {s, _, o} ->
        s == iri and o == RDF.literal("foo")
      end)
    end
  end
end
```

## Adding Validation Rules

### Step 1: Define SHACL Shape

Add to `priv/ontologies/elixir-shapes.ttl`:

```turtle
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix struct: <https://w3id.org/elixir-code/structure#> .

:MyConstructShape a sh:NodeShape ;
    sh:targetClass struct:MyConstruct ;
    sh:property [
        sh:path struct:myProperty ;
        sh:datatype xsd:string ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:pattern "^[a-z][a-zA-Z0-9_]*$"
    ] .
```

### Step 2: Test Validation

```bash
# Generate test data
mix elixir_ontologies.analyze lib/test.ex --output test.ttl

# Validate against shapes
mix elixir_ontologies.kg validate test.ttl
```

### Step 3: Custom Validator (Optional)

For complex validation, create a SPARQL constraint:

```turtle
:MyConstructShape sh:sparql """
    PREFIX struct: <https://w3id.org/elixir-code/structure#>

    SELECT $this ($name AS ?fail)
    WHERE {
        $this struct:myProperty $name .
        FILTER (!REGEX($name, "^[a-z]"))
    }
""" .
```

## Testing Your Changes

### Unit Tests

```elixir
# Test extractor
mix test test/elixir_ontologies/extractors/my_construct_test.exs

# Test builder
mix test test/elixir_ontologies/builders/my_construct_builder_test.exs

# Test all
mix test
```

### Integration Tests

Create `test/elixir_ontologies/my_construct_integration_test.exs`:

```elixir
defmodule ElixirOntologies.MyConstructIntegrationTest do
  use ExUnit.Case
  alias ElixirOntologies.{Pipeline, Config}

  @test_code """
  my_construct :foo do
    :ok
  end
  """

  test "full pipeline extracts and builds my construct" do
    # Parse and analyze
    {:ok, result} = Pipeline.analyze_string(@test_code)

    # Verify extraction
    assert Enum.any?(result.modules, fn m ->
      Enum.any?(m.my_constructs, &(&1.name == :foo))
    end)

    # Verify RDF generation
    assert RDF.Graph.triple_count(result.graph) > 0

    # Verify validation
    {:ok, report} = SHACL.Validator.run(result.graph, shapes_graph())
    assert report.conforms?
  end

  defp shapes_graph do
    {:ok, graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")
    graph
  end
end
```

### Manual Testing

```bash
# Analyze a test file
mix elixir_ontologies.analyze test/fixtures/my_construct.ex

# Output and inspect
mix elixir_ontologies.analyze test/fixtures/my_construct.ex --output /tmp/test.ttl
cat /tmp/test.ttl
```

## Integration Workflow

### 1. Development Checklist

- [ ] Add class/properties to ontology `.ttl` file
- [ ] Add IRI constants to `NS` module
- [ ] Implement extractor with tests
- [ ] Register in `Matchers` module
- [ ] Implement builder with tests
- [ ] Register in `Orchestrator` module
- [ ] Add SHACL validation rules (optional)
- [ ] Add integration tests
- [ ] Update documentation

### 2. Code Review Considerations

- Does the extractor handle edge cases?
- Are IRI patterns consistent with existing code?
- Is the RDF output valid per ontology?
- Do tests cover success and failure cases?
- Is documentation clear and complete?

### 3. Performance Considerations

- Extractors should be O(n) where n is AST size
- Builders should not modify their input
- Use parallel execution where possible (Orchestrator)
- Minimize memory allocation in hot paths

## Common Patterns

### Handling Optional Data

```elixir
# In extractor
def extract({:my_construct, meta, args}, context) do
  # Extract optional field
  optional_field = extract_optional(args, :field)

  %__MODULE__{
    # ...
    optional_field: optional_field  # nil if not present
  }
end

# In builder
defp build_optional_triple(_subject, nil), do: []
defp build_optional_triple(subject, value) do
  [Helpers.datatype_property(subject, predicate, value, datatype)]
end
```

### Handling Lists

```elixir
# In extractor
def extract({:my_construct, meta, items}, context) do
  %__MODULE__{
    items: parse_items(items)  # Returns list
  }
end

# In builder - use RDF list
defp build_items_triple(subject, items) do
  {list_head, list_triples} =
    Enum.map(items, fn item ->
      item_iri = generate_item_iri(item)
      {item_iri, build_item_triples(item_iri, item)}
    end)
    |> Helpers.build_rdf_list()

  link_triple = Helpers.object_property(subject, hasItem(), list_head)
  [link_triple | list_triples]
end
```

### Handling Nested Structures

```elixir
# In extractor - recursive extraction
def extract({:my_construct, meta, [children]}, context) do
  {child_extractions, _} =
    Enum.map_reduce(children, context, fn child, ctx ->
      {:ok, child_data} = ChildExtractor.extract(child, ctx)
      {child_data, ctx}
    end)

  %__MODULE__{
    children: child_extractions
  }
end

# In builder - delegate to child builder
defp build_children_triples(subject, children, context) do
  Enum.flat_map(children, fn child ->
    {child_iri, child_triples} = ChildBuilder.build(child, context)
    link = Helpers.object_property(subject, hasChild(), child_iri)
    [link | child_triples]
  end)
end
```

## Debugging Tips

### Inspect AST

```elixir
# In IEx
iex> ast = Code.string_to_quoted!("my_construct :foo do :ok end")
iex> Macro.to_string(ast)
iex> ast  # Inspect raw AST structure
```

### Trace Pipeline

```elixir
# Add debug logging
def extract(ast, context) do
  IO.inspect(ast, label: "Input AST")
  result = do_extract(ast, context)
  IO.inspect(result, label: "Extracted")
  result
end
```

### Validate RDF

```bash
# Use RDF validator online
# https://www.w3.org/RDF/validator/

# Or use riot (RDF Inference and Validation Tool)
riot test.ttl
```

## Related Documentation

- **[Architecture Overview](architecture.md)** - System architecture
- **[Extractors Component](components/extractors.md)** - Extractor patterns
- **[Builders Component](components/builders.md)** - Builder patterns
- **[Validators Component](components/validators.md)** - Validation patterns
- **[SHACL Component](components/shacl.md)** - SHACL model

## Getting Help

- Review existing extractors and builders as examples
- Check test files for usage patterns
- Consult SHACL specification for validation rules
- Review OWL constructs for ontology modeling

## References

- [Elixir AST Documentation](https://hexdocs.pm/elixir/Main.html#module-code)
- [SHACL Specification](https://www.w3.org/TR/shacl/)
- [OWL 2 Specification](https://www.w3.org/TR/owl2-overview/)
- [RDF 1.1 Primer](https://www.w3.org/TR/rdf11-primer/)
