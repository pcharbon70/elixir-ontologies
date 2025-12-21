defmodule ElixirOntologies.Builders.DependencyBuilder do
  @moduledoc """
  Builds RDF triples for module dependency directives.

  This module transforms extracted directive information into detailed RDF
  representations following the elixir-structure.ttl ontology. It creates
  first-class RDF resources for each directive with proper type classification
  and property values.

  ## Supported Directives

  - **Aliases** - `alias MyApp.Users, as: U` creates `struct:ModuleAlias`
  - (Future) **Imports** - creates `struct:Import`
  - (Future) **Requires** - creates `struct:Require`
  - (Future) **Uses** - creates `struct:Use`

  ## Usage

      alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective

      alias_directive = %AliasDirective{
        source: [:MyApp, :Users],
        as: :U
      }

      module_iri = RDF.iri("https://example.org/code#MyApp")
      context = Context.new(base_iri: "https://example.org/code#")

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(
        alias_directive, module_iri, context, 0
      )

  ## Generated Triples

  For an alias directive `alias MyApp.Users, as: U`:

  ```turtle
  ex:MyApp/alias/0 a struct:ModuleAlias ;
      struct:aliasName "U" ;
      struct:aliasedModule ex:MyApp.Users .

  ex:MyApp struct:hasAlias ex:MyApp/alias/0 .
  ```

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
      iex> alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {alias_iri, _triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)
      iex> to_string(alias_iri)
      "https://example.org/code#MyApp/alias/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
  alias NS.Structure

  # ===========================================================================
  # Public API - Alias Dependencies
  # ===========================================================================

  @doc """
  Builds RDF triples for a single alias directive.

  Creates a ModuleAlias resource with:
  - `rdf:type struct:ModuleAlias` - type classification
  - `struct:aliasName` - the short name used for the alias
  - `struct:aliasedModule` - link to the target module
  - Link from containing module via `struct:hasAlias`

  ## Parameters

  - `alias_info` - AliasDirective struct from extraction
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI
  - `index` - Zero-based index of the alias within the module

  ## Returns

  A tuple `{alias_iri, triples}` where:
  - `alias_iri` - The IRI of the alias resource
  - `triples` - List of RDF triples describing the alias

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
      iex> alias_info = %AliasDirective{source: [:Enum], as: :E}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)
      iex> to_string(alias_iri)
      "https://example.org/code#MyApp/alias/0"
      iex> length(triples)
      4
  """
  @spec build_alias_dependency(AliasDirective.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_alias_dependency(alias_info, module_iri, context, index) do
    # Generate alias IRI
    alias_iri = IRI.for_alias(module_iri, index)

    # Get aliased module IRI - AliasDirective uses :source field
    aliased_module_name = module_name_string(alias_info.source)
    aliased_module_iri = IRI.for_module(context.base_iri, aliased_module_name)

    # Get alias short name
    alias_name = get_alias_name(alias_info)

    # Build triples
    triples = [
      # Type triple
      Helpers.type_triple(alias_iri, Structure.ModuleAlias),
      # Alias name
      Helpers.datatype_property(alias_iri, Structure.aliasName(), alias_name, RDF.XSD.String),
      # Link to aliased module
      Helpers.object_property(alias_iri, Structure.aliasedModule(), aliased_module_iri),
      # Link from containing module
      Helpers.object_property(module_iri, Structure.hasAlias(), alias_iri)
    ]

    {alias_iri, triples}
  end

  @doc """
  Builds RDF triples for all alias directives in a module.

  Calls `build_alias_dependency/4` for each alias and aggregates the results.

  ## Parameters

  - `aliases` - List of AliasDirective structs
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI

  ## Returns

  A list of all generated RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
      iex> aliases = [
      ...>   %AliasDirective{source: [:Enum], as: :E},
      ...>   %AliasDirective{source: [:String], as: nil}
      ...> ]
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = DependencyBuilder.build_alias_dependencies(aliases, module_iri, context)
      iex> length(triples)
      8
  """
  @spec build_alias_dependencies([AliasDirective.t()], RDF.IRI.t(), Context.t()) ::
          [RDF.Triple.t()]
  def build_alias_dependencies(aliases, module_iri, context) do
    aliases
    |> Enum.with_index()
    |> Enum.flat_map(fn {alias_info, index} ->
      {_alias_iri, triples} = build_alias_dependency(alias_info, module_iri, context, index)
      triples
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Convert module atom list to string representation
  defp module_name_string(module) when is_list(module) do
    Enum.map_join(module, ".", &Atom.to_string/1)
  end

  defp module_name_string(module) when is_atom(module) do
    Atom.to_string(module)
  end

  # Get the alias short name - either explicit :as or last part of source module
  defp get_alias_name(%AliasDirective{as: as_name, source: source}) do
    case as_name do
      nil ->
        # Use last part of source module name
        source
        |> List.last()
        |> Atom.to_string()

      name when is_atom(name) ->
        Atom.to_string(name)
    end
  end
end
