defmodule ElixirOntologies.Builders.DependencyBuilder do
  @moduledoc """
  Builds RDF triples for module dependency directives.

  This module transforms extracted directive information into detailed RDF
  representations following the elixir-structure.ttl ontology. It creates
  first-class RDF resources for each directive with proper type classification
  and property values.

  ## Supported Directives

  - **Aliases** - `alias MyApp.Users, as: U` creates `struct:ModuleAlias`
  - **Imports** - `import Enum, only: [map: 2]` creates `struct:Import`
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
  alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
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
  # Public API - Import Dependencies
  # ===========================================================================

  @doc """
  Builds RDF triples for a single import directive.

  Creates an Import resource with:
  - `rdf:type struct:Import` - type classification
  - `struct:importsModule` - link to the imported module
  - `struct:isFullImport` - whether this is a full import (no only/except)
  - `struct:importType` - for type-based imports (:functions, :macros, :sigils)
  - `struct:importsFunction` - for each explicitly imported function
  - `struct:excludesFunction` - for each explicitly excluded function
  - Link from containing module via `struct:hasImport`

  ## Parameters

  - `import_info` - ImportDirective struct from extraction
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI
  - `index` - Zero-based index of the import within the module

  ## Returns

  A tuple `{import_iri, triples}` where:
  - `import_iri` - The IRI of the import resource
  - `triples` - List of RDF triples describing the import

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
      iex> import_info = %ImportDirective{module: [:Enum]}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)
      iex> to_string(import_iri)
      "https://example.org/code#MyApp/import/0"
      iex> length(triples)
      4

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
      iex> import_info = %ImportDirective{module: [:Enum], only: [map: 2, filter: 2]}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)
      iex> length(triples)
      6
  """
  @spec build_import_dependency(ImportDirective.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_import_dependency(import_info, module_iri, context, index) do
    # Generate import IRI
    import_iri = IRI.for_import(module_iri, index)

    # Get imported module IRI
    imported_module_name = module_name_string(import_info.module)
    imported_module_iri = IRI.for_module(context.base_iri, imported_module_name)

    # Determine if this is a full import
    is_full_import = import_info.only == nil and import_info.except == nil

    # Build base triples
    base_triples = [
      # Type triple
      Helpers.type_triple(import_iri, Structure.Import),
      # Link to imported module
      Helpers.object_property(import_iri, Structure.importsModule(), imported_module_iri),
      # Full import flag
      Helpers.datatype_property(import_iri, Structure.isFullImport(), is_full_import, RDF.XSD.Boolean),
      # Link from containing module
      Helpers.object_property(module_iri, Structure.hasImport(), import_iri)
    ]

    # Add type-based import triple if applicable
    type_triples = build_import_type_triples(import_iri, import_info.only)

    # Add function import triples if applicable
    function_triples =
      build_imported_function_triples(import_iri, import_info.only, imported_module_name, context)

    # Add excluded function triples if applicable
    excluded_triples =
      build_excluded_function_triples(import_iri, import_info.except, imported_module_name, context)

    triples = base_triples ++ type_triples ++ function_triples ++ excluded_triples

    {import_iri, triples}
  end

  @doc """
  Builds RDF triples for all import directives in a module.

  Calls `build_import_dependency/4` for each import and aggregates the results.

  ## Parameters

  - `imports` - List of ImportDirective structs
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI

  ## Returns

  A list of all generated RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
      iex> imports = [
      ...>   %ImportDirective{module: [:Enum]},
      ...>   %ImportDirective{module: [:String], only: [upcase: 1]}
      ...> ]
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = DependencyBuilder.build_import_dependencies(imports, module_iri, context)
      iex> length(triples)
      9
  """
  @spec build_import_dependencies([ImportDirective.t()], RDF.IRI.t(), Context.t()) ::
          [RDF.Triple.t()]
  def build_import_dependencies(imports, module_iri, context) do
    imports
    |> Enum.with_index()
    |> Enum.flat_map(fn {import_info, index} ->
      {_import_iri, triples} = build_import_dependency(import_info, module_iri, context, index)
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

  # ===========================================================================
  # Private Helpers - Import
  # ===========================================================================

  # Build import type triple for type-based imports (:functions, :macros, :sigils)
  defp build_import_type_triples(import_iri, only) when only in [:functions, :macros, :sigils] do
    type_string = Atom.to_string(only)
    [Helpers.datatype_property(import_iri, Structure.importType(), type_string, RDF.XSD.String)]
  end

  defp build_import_type_triples(_import_iri, _only), do: []

  # Build triples for explicitly imported functions (only: [func: arity, ...])
  defp build_imported_function_triples(import_iri, only, imported_module, context)
       when is_list(only) do
    Enum.map(only, fn {func_name, arity} ->
      func_iri = IRI.for_function(context.base_iri, imported_module, func_name, arity)
      Helpers.object_property(import_iri, Structure.importsFunction(), func_iri)
    end)
  end

  defp build_imported_function_triples(_import_iri, _only, _imported_module, _context), do: []

  # Build triples for excluded functions (except: [func: arity, ...])
  defp build_excluded_function_triples(import_iri, except, imported_module, context)
       when is_list(except) do
    Enum.map(except, fn {func_name, arity} ->
      func_iri = IRI.for_function(context.base_iri, imported_module, func_name, arity)
      Helpers.object_property(import_iri, Structure.excludesFunction(), func_iri)
    end)
  end

  defp build_excluded_function_triples(_import_iri, _except, _imported_module, _context), do: []
end
