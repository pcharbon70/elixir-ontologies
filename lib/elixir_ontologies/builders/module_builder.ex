defmodule ElixirOntologies.Builders.ModuleBuilder do
  @moduledoc """
  Builds RDF triples for Elixir modules.

  This module transforms `ElixirOntologies.Extractors.Module` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Module and NestedModule classification
  - Module names and documentation
  - Nested module relationships (parent/child)
  - Module directives (alias, import, require, use)
  - Containment relationships (functions, macros, types)
  - Source location information

  ## Usage

      alias ElixirOntologies.Builders.{ModuleBuilder, Context}
      alias ElixirOntologies.Extractors.Module

      module_info = %Module{
        type: :module,
        name: [:MyApp, :Users],
        docstring: "User management",
        # ... other fields
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # module_iri => ~I<https://example.org/code#MyApp.Users>
      # triples => [
      #   {module_iri, RDF.type(), Structure.Module},
      #   {module_iri, Structure.moduleName(), "MyApp.Users"},
      #   ...
      # ]

  ## Examples

      iex> alias ElixirOntologies.Builders.{ModuleBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Module
      iex> module_info = %Module{
      ...>   type: :module,
      ...>   name: [:MyApp],
      ...>   docstring: nil,
      ...>   aliases: [],
      ...>   imports: [],
      ...>   requires: [],
      ...>   uses: [],
      ...>   functions: [],
      ...>   macros: [],
      ...>   types: [],
      ...>   location: nil,
      ...>   metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {module_iri, _triples} = ModuleBuilder.build(module_info, context)
      iex> to_string(module_iri)
      "https://example.org/code#MyApp"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Module, as: ModuleExtractor
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a module.

  Takes a module extraction result and builder context, returns the module IRI
  and a list of RDF triples representing the module in the ontology.

  ## Parameters

  - `module_info` - Module extraction result from `Extractors.Module.extract/1`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{module_iri, triples}` where:
  - `module_iri` - The IRI of the module
  - `triples` - List of RDF triples describing the module

  ## Examples

      iex> alias ElixirOntologies.Builders.{ModuleBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Module
      iex> module_info = %Module{
      ...>   type: :module,
      ...>   name: [:Simple],
      ...>   docstring: "A simple module",
      ...>   aliases: [],
      ...>   imports: [],
      ...>   requires: [],
      ...>   uses: [],
      ...>   functions: [],
      ...>   macros: [],
      ...>   types: [],
      ...>   location: nil,
      ...>   metadata: %{parent_module: nil, has_moduledoc: true, nested_modules: []}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {module_iri, triples} = ModuleBuilder.build(module_info, context)
      iex> type_pred = RDF.type()
      iex> type_triple = Enum.find(triples, fn {_s, p, _o} -> p == type_pred end)
      iex> {^module_iri, ^type_pred, _class} = type_triple
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(ModuleExtractor.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(module_info, context) do
    # Generate module IRI
    module_iri = generate_module_iri(module_info, context)

    # Build all triples
    triples =
      [
        # Core module triples
        build_type_triple(module_iri, module_info),
        build_name_triple(module_iri, module_info)
      ] ++
        build_docstring_triple(module_iri, module_info) ++
        build_parent_triple(module_iri, module_info, context) ++
        build_directive_triples(module_iri, module_info, context) ++
        build_containment_triples(module_iri, module_info, context) ++
        build_location_triple(module_iri, module_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {module_iri, triples}
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Generate module IRI from module name
  defp generate_module_iri(module_info, context) do
    module_name = module_name_string(module_info.name)
    IRI.for_module(context.base_iri, module_name)
  end

  # Build rdf:type triple (Module or NestedModule)
  defp build_type_triple(module_iri, module_info) do
    class =
      case module_info.type do
        :module -> Structure.Module
        :nested_module -> Structure.NestedModule
      end

    Helpers.type_triple(module_iri, class)
  end

  # Build struct:moduleName datatype property
  defp build_name_triple(module_iri, module_info) do
    module_name = module_name_string(module_info.name)
    Helpers.datatype_property(module_iri, Structure.moduleName(), module_name, RDF.XSD.String)
  end

  # Build struct:docstring datatype property (if present)
  defp build_docstring_triple(module_iri, module_info) do
    case module_info.docstring do
      nil ->
        []

      false ->
        # @moduledoc false - intentionally hidden
        []

      doc when is_binary(doc) ->
        [Helpers.datatype_property(module_iri, Structure.docstring(), doc, RDF.XSD.String)]
    end
  end

  # ===========================================================================
  # Nested Module Support
  # ===========================================================================

  # Build parent module relationships for nested modules
  defp build_parent_triple(module_iri, module_info, context) do
    case module_info.metadata.parent_module do
      nil ->
        []

      parent_name_list ->
        parent_name = module_name_string(parent_name_list)
        parent_iri = IRI.for_module(context.base_iri, parent_name)

        [
          # nested -> parent relationship
          Helpers.object_property(module_iri, Structure.parentModule(), parent_iri),
          # parent -> nested relationship (inverse)
          Helpers.object_property(parent_iri, Structure.hasNestedModule(), module_iri)
        ]
    end
  end

  # ===========================================================================
  # Module Directives
  # ===========================================================================

  # Aggregator for all directive triples
  defp build_directive_triples(module_iri, module_info, context) do
    build_alias_triples(module_iri, module_info.aliases, context) ++
      build_import_triples(module_iri, module_info.imports, context) ++
      build_require_triples(module_iri, module_info.requires, context) ++
      build_use_triples(module_iri, module_info.uses, context)
  end

  # Build struct:aliasesModule triples
  defp build_alias_triples(module_iri, aliases, context) do
    Enum.flat_map(aliases, fn alias_info ->
      aliased_module = module_name_string(alias_info.module)
      aliased_iri = IRI.for_module(context.base_iri, aliased_module)

      [Helpers.object_property(module_iri, Structure.aliasesModule(), aliased_iri)]
    end)
  end

  # Build struct:importsFrom triples
  defp build_import_triples(module_iri, imports, context) do
    Enum.flat_map(imports, fn import_info ->
      imported_module = normalize_module_name(import_info.module)
      imported_iri = IRI.for_module(context.base_iri, imported_module)

      [Helpers.object_property(module_iri, Structure.importsFrom(), imported_iri)]
    end)
  end

  # Build struct:requiresModule triples
  defp build_require_triples(module_iri, requires, context) do
    Enum.flat_map(requires, fn require_info ->
      required_module = normalize_module_name(require_info.module)
      required_iri = IRI.for_module(context.base_iri, required_module)

      [Helpers.object_property(module_iri, Structure.requiresModule(), required_iri)]
    end)
  end

  # Build struct:usesModule triples
  defp build_use_triples(module_iri, uses, context) do
    Enum.flat_map(uses, fn use_info ->
      used_module = normalize_module_name(use_info.module)
      used_iri = IRI.for_module(context.base_iri, used_module)

      [Helpers.object_property(module_iri, Structure.usesModule(), used_iri)]
    end)
  end

  # ===========================================================================
  # Containment Relationships
  # ===========================================================================

  # Build all containment triples (functions, macros, types)
  defp build_containment_triples(module_iri, module_info, context) do
    module_name = extract_module_name_from_iri(module_iri)

    function_triples =
      build_function_containment(module_iri, module_name, module_info.functions, context)

    macro_triples = build_macro_containment(module_iri, module_name, module_info.macros, context)
    type_triples = build_type_containment(module_iri, module_name, module_info.types, context)

    function_triples ++ macro_triples ++ type_triples
  end

  # Build struct:containsFunction triples
  defp build_function_containment(module_iri, module_name, functions, context) do
    Enum.flat_map(functions, fn func_info ->
      func_iri =
        IRI.for_function(
          context.base_iri,
          module_name,
          func_info.name,
          func_info.arity
        )

      [Helpers.object_property(module_iri, Structure.containsFunction(), func_iri)]
    end)
  end

  # Build struct:containsMacro triples
  defp build_macro_containment(module_iri, module_name, macros, context) do
    Enum.flat_map(macros, fn macro_info ->
      # Macros use the same IRI pattern as functions but different type
      macro_iri =
        IRI.for_function(
          context.base_iri,
          module_name,
          macro_info.name,
          macro_info.arity
        )

      [Helpers.object_property(module_iri, Structure.containsMacro(), macro_iri)]
    end)
  end

  # Build struct:containsType triples
  defp build_type_containment(module_iri, module_name, types, context) do
    Enum.flat_map(types, fn type_info ->
      # Types also use function-like IRI pattern
      type_iri =
        IRI.for_function(
          context.base_iri,
          module_name,
          type_info.name,
          type_info.arity
        )

      [Helpers.object_property(module_iri, Structure.containsType(), type_iri)]
    end)
  end

  # ===========================================================================
  # Source Location
  # ===========================================================================

  # Build core:hasSourceLocation triple if location information available
  defp build_location_triple(module_iri, module_info, context) do
    case {module_info.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        # Location exists but no file path - skip location triple
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)

        # Need end line - use start line if end not available
        end_line = location.end_line || location.start_line

        location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

        [Helpers.object_property(module_iri, Core.hasSourceLocation(), location_iri)]
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Convert module name list to string
  defp module_name_string(name) when is_list(name) do
    name
    |> Enum.map(&module_part_to_string/1)
    |> Enum.join(".")
  end

  # Convert individual module name parts to strings
  # Handles atoms, strings, and AST tuples like {:__MODULE__, _, _}
  defp module_part_to_string(part) when is_atom(part), do: to_string(part)
  defp module_part_to_string(part) when is_binary(part), do: part

  # Handle __MODULE__ AST tuple
  defp module_part_to_string({:__MODULE__, _meta, _context}), do: "__MODULE__"

  # Handle other macro expressions (unquote, etc.)
  defp module_part_to_string({macro_name, _meta, _args}) when is_atom(macro_name) do
    to_string(macro_name)
  end

  # Fallback for unexpected structures
  defp module_part_to_string(other), do: inspect(other)

  # Handle both atom and list module names in directives
  defp normalize_module_name(module) when is_list(module), do: module_name_string(module)
  defp normalize_module_name(module) when is_atom(module), do: to_string(module)

  # Extract module name from module IRI
  defp extract_module_name_from_iri(module_iri) do
    case IRI.module_from_iri(module_iri) do
      {:ok, module_name} -> module_name
      {:error, _} -> raise "Invalid module IRI: #{inspect(module_iri)}"
    end
  end
end
