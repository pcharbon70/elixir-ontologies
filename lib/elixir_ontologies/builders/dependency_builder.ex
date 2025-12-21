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
  - **Requires** - `require Logger` creates `struct:Require`
  - **Uses** - `use GenServer, restart: :temporary` creates `struct:Use`

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
  alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
  alias ElixirOntologies.Extractors.Directive.Use.{UseDirective, UseOption}
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
  # Public API - Require Dependencies
  # ===========================================================================

  @doc """
  Builds RDF triples for a single require directive.

  Creates a Require resource with:
  - `rdf:type struct:Require` - type classification
  - `struct:requireModule` - link to the required module
  - `struct:requireAlias` - optional alias name (if `as:` is specified)
  - Link from containing module via `struct:hasRequire`

  ## Parameters

  - `require_info` - RequireDirective struct from extraction
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI
  - `index` - Zero-based index of the require within the module

  ## Returns

  A tuple `{require_iri, triples}` where:
  - `require_iri` - The IRI of the require resource
  - `triples` - List of RDF triples describing the require

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
      iex> require_info = %RequireDirective{module: [:Logger]}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)
      iex> to_string(require_iri)
      "https://example.org/code#MyApp/require/0"
      iex> length(triples)
      3

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
      iex> require_info = %RequireDirective{module: [:Logger], as: :L}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)
      iex> length(triples)
      4
  """
  @spec build_require_dependency(RequireDirective.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_require_dependency(require_info, module_iri, context, index) do
    # Generate require IRI
    require_iri = IRI.for_require(module_iri, index)

    # Get required module IRI
    required_module_name = module_name_string(require_info.module)
    required_module_iri = IRI.for_module(context.base_iri, required_module_name)

    # Build base triples
    base_triples = [
      # Type triple
      Helpers.type_triple(require_iri, Structure.Require),
      # Link to required module
      Helpers.object_property(require_iri, Structure.requireModule(), required_module_iri),
      # Link from containing module
      Helpers.object_property(module_iri, Structure.hasRequire(), require_iri)
    ]

    # Add alias triple if present
    alias_triples = build_require_alias_triple(require_iri, require_info.as)

    triples = base_triples ++ alias_triples

    {require_iri, triples}
  end

  @doc """
  Builds RDF triples for all require directives in a module.

  Calls `build_require_dependency/4` for each require and aggregates the results.

  ## Parameters

  - `requires` - List of RequireDirective structs
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI

  ## Returns

  A list of all generated RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
      iex> requires = [
      ...>   %RequireDirective{module: [:Logger]},
      ...>   %RequireDirective{module: [:Ecto, :Query], as: :Q}
      ...> ]
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = DependencyBuilder.build_require_dependencies(requires, module_iri, context)
      iex> length(triples)
      7
  """
  @spec build_require_dependencies([RequireDirective.t()], RDF.IRI.t(), Context.t()) ::
          [RDF.Triple.t()]
  def build_require_dependencies(requires, module_iri, context) do
    requires
    |> Enum.with_index()
    |> Enum.flat_map(fn {require_info, index} ->
      {_require_iri, triples} = build_require_dependency(require_info, module_iri, context, index)
      triples
    end)
  end

  # ===========================================================================
  # Public API - Use Dependencies
  # ===========================================================================

  @doc """
  Builds RDF triples for a single use directive.

  Creates a Use resource with:
  - `rdf:type struct:Use` - type classification
  - `struct:useModule` - link to the used module
  - `struct:hasUseOption` - links to option resources (if options present)
  - Link from containing module via `struct:hasUse`

  ## Parameters

  - `use_info` - UseDirective struct from extraction
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI
  - `index` - Zero-based index of the use within the module

  ## Returns

  A tuple `{use_iri, triples}` where:
  - `use_iri` - The IRI of the use resource
  - `triples` - List of RDF triples describing the use

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Use.UseDirective
      iex> use_info = %UseDirective{module: [:GenServer]}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)
      iex> to_string(use_iri)
      "https://example.org/code#MyApp/use/0"
      iex> length(triples)
      3

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Use.UseDirective
      iex> use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)
      iex> length(triples)
      9
  """
  @spec build_use_dependency(UseDirective.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_use_dependency(use_info, module_iri, context, index) do
    # Generate use IRI
    use_iri = IRI.for_use(module_iri, index)

    # Get used module IRI
    used_module_name = module_name_string(use_info.module)
    used_module_iri = IRI.for_module(context.base_iri, used_module_name)

    # Build base triples
    base_triples = [
      # Type triple
      Helpers.type_triple(use_iri, Structure.Use),
      # Link to used module
      Helpers.object_property(use_iri, Structure.useModule(), used_module_iri),
      # Link from containing module
      Helpers.object_property(module_iri, Structure.hasUse(), use_iri)
    ]

    # Build option triples if present
    option_triples = build_use_option_triples(use_iri, use_info.options)

    triples = base_triples ++ option_triples

    {use_iri, triples}
  end

  @doc """
  Builds RDF triples for all use directives in a module.

  Calls `build_use_dependency/4` for each use and aggregates the results.

  ## Parameters

  - `uses` - List of UseDirective structs
  - `module_iri` - IRI of the containing module
  - `context` - Builder context with base IRI

  ## Returns

  A list of all generated RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.{DependencyBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Directive.Use.UseDirective
      iex> uses = [
      ...>   %UseDirective{module: [:GenServer]},
      ...>   %UseDirective{module: [:Supervisor], options: [strategy: :one_for_one]}
      ...> ]
      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = DependencyBuilder.build_use_dependencies(uses, module_iri, context)
      iex> length(triples)
      12
  """
  @spec build_use_dependencies([UseDirective.t()], RDF.IRI.t(), Context.t()) ::
          [RDF.Triple.t()]
  def build_use_dependencies(uses, module_iri, context) do
    uses
    |> Enum.with_index()
    |> Enum.flat_map(fn {use_info, index} ->
      {_use_iri, triples} = build_use_dependency(use_info, module_iri, context, index)
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

  # ===========================================================================
  # Private Helpers - Require
  # ===========================================================================

  # Build require alias triple if as: is present
  defp build_require_alias_triple(require_iri, as_name) when is_atom(as_name) and not is_nil(as_name) do
    alias_string = Atom.to_string(as_name)
    [Helpers.datatype_property(require_iri, Structure.requireAlias(), alias_string, RDF.XSD.String)]
  end

  defp build_require_alias_triple(_require_iri, _as_name), do: []

  # ===========================================================================
  # Private Helpers - Use
  # ===========================================================================

  # Build option triples for use directive options
  defp build_use_option_triples(use_iri, [_ | _] = options) do
    options
    |> Enum.with_index()
    |> Enum.flat_map(fn {option, index} ->
      build_single_use_option_triples(use_iri, option, index)
    end)
  end

  defp build_use_option_triples(_use_iri, _options), do: []

  # Build triples for a single use option
  defp build_single_use_option_triples(use_iri, {key, value}, index) when is_atom(key) do
    option_iri = IRI.for_use_option(use_iri, index)

    # Determine value type and string representation
    {value_type, value_string, is_dynamic} = analyze_option_value(value)

    [
      # Type triple
      Helpers.type_triple(option_iri, Structure.UseOption),
      # Link from use directive
      Helpers.object_property(use_iri, Structure.hasUseOption(), option_iri),
      # Option key
      Helpers.datatype_property(option_iri, Structure.optionKey(), Atom.to_string(key), RDF.XSD.String),
      # Option value
      Helpers.datatype_property(option_iri, Structure.optionValue(), value_string, RDF.XSD.String),
      # Value type
      Helpers.datatype_property(option_iri, Structure.optionValueType(), value_type, RDF.XSD.String),
      # Dynamic flag
      Helpers.datatype_property(option_iri, Structure.isDynamicOption(), is_dynamic, RDF.XSD.Boolean)
    ]
  end

  # Handle UseOption struct (from analyze_options)
  defp build_single_use_option_triples(use_iri, %UseOption{} = opt, index) do
    option_iri = IRI.for_use_option(use_iri, index)

    key_string = if opt.key, do: Atom.to_string(opt.key), else: ""
    value_string = format_option_value(opt.value)
    value_type = Atom.to_string(opt.value_type)

    [
      # Type triple
      Helpers.type_triple(option_iri, Structure.UseOption),
      # Link from use directive
      Helpers.object_property(use_iri, Structure.hasUseOption(), option_iri),
      # Option key
      Helpers.datatype_property(option_iri, Structure.optionKey(), key_string, RDF.XSD.String),
      # Option value
      Helpers.datatype_property(option_iri, Structure.optionValue(), value_string, RDF.XSD.String),
      # Value type
      Helpers.datatype_property(option_iri, Structure.optionValueType(), value_type, RDF.XSD.String),
      # Dynamic flag
      Helpers.datatype_property(option_iri, Structure.isDynamicOption(), opt.dynamic, RDF.XSD.Boolean)
    ]
  end

  # Handle positional (non-keyword) options like `use MyApp.Web, :controller`
  defp build_single_use_option_triples(use_iri, value, index) do
    option_iri = IRI.for_use_option(use_iri, index)

    {value_type, value_string, is_dynamic} = analyze_option_value(value)

    [
      # Type triple
      Helpers.type_triple(option_iri, Structure.UseOption),
      # Link from use directive
      Helpers.object_property(use_iri, Structure.hasUseOption(), option_iri),
      # Option key (empty for positional)
      Helpers.datatype_property(option_iri, Structure.optionKey(), "", RDF.XSD.String),
      # Option value
      Helpers.datatype_property(option_iri, Structure.optionValue(), value_string, RDF.XSD.String),
      # Value type
      Helpers.datatype_property(option_iri, Structure.optionValueType(), value_type, RDF.XSD.String),
      # Dynamic flag
      Helpers.datatype_property(option_iri, Structure.isDynamicOption(), is_dynamic, RDF.XSD.Boolean)
    ]
  end

  # Analyze an option value and return {type_string, value_string, is_dynamic}
  # Note: boolean check must come before atom since is_atom(true) returns true
  defp analyze_option_value(value) when is_boolean(value) do
    {"boolean", Atom.to_string(value), false}
  end

  defp analyze_option_value(nil) do
    {"nil", "nil", false}
  end

  defp analyze_option_value(value) when is_atom(value) do
    {"atom", Atom.to_string(value), false}
  end

  defp analyze_option_value(value) when is_binary(value) do
    {"string", value, false}
  end

  defp analyze_option_value(value) when is_integer(value) do
    {"integer", Integer.to_string(value), false}
  end

  defp analyze_option_value(value) when is_float(value) do
    {"float", Float.to_string(value), false}
  end

  defp analyze_option_value(value) when is_list(value) do
    {"list", inspect(value), false}
  end

  defp analyze_option_value(value) when is_tuple(value) do
    {"tuple", inspect(value), false}
  end

  defp analyze_option_value(_value) do
    {"dynamic", "<dynamic>", true}
  end

  # Format an option value as a string
  defp format_option_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_option_value(value) when is_binary(value), do: value
  defp format_option_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_option_value(value) when is_float(value), do: Float.to_string(value)
  defp format_option_value(value) when is_boolean(value), do: Atom.to_string(value)
  defp format_option_value(nil), do: "nil"
  defp format_option_value(value), do: inspect(value)
end
