defmodule ElixirOntologies.Builders.Evolution.VersionBuilder do
  @moduledoc """
  Builds RDF triples for code version relationships.

  This module transforms `ElixirOntologies.Extractors.Evolution.EntityVersion`
  results (ModuleVersion, FunctionVersion) into RDF triples following the
  elixir-evolution.ttl ontology. It handles:

  - Version type classification (ModuleVersion, FunctionVersion)
  - Version string representation
  - Version chain relationships (hasPreviousVersion)
  - PROV-O entity alignment

  ## Usage

      alias ElixirOntologies.Builders.Evolution.VersionBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.Evolution.EntityVersion

      {:ok, versions} = EntityVersion.track_module_versions(
        ".",
        "MyApp.UserController",
        limit: 10
      )

      context = Context.new(base_iri: "https://example.org/code#")

      {version_iri, triples} = VersionBuilder.build(hd(versions), context)

  ## RDF Output

  For a module version:

      version:MyApp.UserController@abc123d a evo:ModuleVersion, prov:Entity ;
          evo:versionString "MyApp.UserController@abc123d" ;
          evo:hasPreviousVersion version:MyApp.UserController@def456e .

  For a function version:

      version:MyApp.UserController.create%2F1@abc123d a evo:FunctionVersion, prov:Entity ;
          evo:versionString "MyApp.UserController.create/1@abc123d" ;
          evo:hasPreviousVersion version:MyApp.UserController.create%2F1@def456e .

  ## Version Type Mapping

  | Struct | Ontology Class |
  |--------|----------------|
  | `ModuleVersion` | `evolution:ModuleVersion` |
  | `FunctionVersion` | `evolution:FunctionVersion` |

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion.ModuleVersion
      iex> version = %ModuleVersion{
      ...>   module_name: "MyApp.User",
      ...>   version_id: "MyApp.User@abc123d",
      ...>   commit_sha: "abc123def456789012345678901234567890abcd",
      ...>   short_sha: "abc123d",
      ...>   file_path: "lib/my_app/user.ex",
      ...>   content_hash: "sha256:abc123",
      ...>   previous_version: nil
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {version_iri, triples} = VersionBuilder.build(version, context)
      iex> to_string(version_iri) |> String.contains?("abc123d")
      true
      iex> length(triples) >= 2
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.Evolution.EntityVersion.{ModuleVersion, FunctionVersion}
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a version (ModuleVersion or FunctionVersion).

  Takes a version struct and builder context, returns the version IRI
  and a list of RDF triples representing the version in the ontology.

  ## Parameters

  - `version` - ModuleVersion or FunctionVersion struct
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{version_iri, triples}` where:
  - `version_iri` - The IRI of the version
  - `triples` - List of RDF triples describing the version

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion.ModuleVersion
      iex> version = %ModuleVersion{
      ...>   module_name: "MyApp.User",
      ...>   version_id: "MyApp.User@def456e",
      ...>   commit_sha: "def456e789012345678901234567890abcdef01",
      ...>   short_sha: "def456e",
      ...>   file_path: "lib/my_app/user.ex",
      ...>   content_hash: "sha256:def456"
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {version_iri, triples} = VersionBuilder.build(version, context)
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(ModuleVersion.t() | FunctionVersion.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%ModuleVersion{} = version, %Context{} = context) do
    build_version(version, :module, context)
  end

  def build(%FunctionVersion{} = version, %Context{} = context) do
    build_version(version, :function, context)
  end

  @doc """
  Builds RDF triples for multiple versions.

  ## Parameters

  - `versions` - List of ModuleVersion or FunctionVersion structs
  - `context` - Builder context

  ## Returns

  A list of `{version_iri, triples}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> results = VersionBuilder.build_all([], context)
      iex> results
      []
  """
  @spec build_all([ModuleVersion.t() | FunctionVersion.t()], Context.t()) ::
          [{RDF.IRI.t(), [RDF.Triple.t()]}]
  def build_all(versions, context) when is_list(versions) do
    Enum.map(versions, &build(&1, context))
  end

  @doc """
  Builds RDF triples for multiple versions and collects all triples.

  Returns a flat list of all triples from all versions.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = VersionBuilder.build_all_triples([], context)
      iex> triples
      []
  """
  @spec build_all_triples([ModuleVersion.t() | FunctionVersion.t()], Context.t()) ::
          [RDF.Triple.t()]
  def build_all_triples(versions, context) when is_list(versions) do
    versions
    |> build_all(context)
    |> Enum.flat_map(fn {_iri, triples} -> triples end)
  end

  # ===========================================================================
  # Private Implementation
  # ===========================================================================

  defp build_version(version, type, context) do
    # Generate version IRI
    version_iri = generate_version_iri(version, context)

    # Build all triples using list of lists pattern
    triples =
      [
        build_type_triples(version_iri, type),
        build_version_string_triple(version_iri, version),
        build_previous_version_triple(version_iri, version, context),
        build_timestamp_triple(version_iri, version)
      ]
      |> Helpers.finalize_triples()

    {version_iri, triples}
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  defp generate_version_iri(version, context) do
    base = to_string(context.base_iri)

    # Version IDs are in format "ModuleName@sha" or "ModuleName.func/arity@sha"
    # We URL-encode the version_id for safe IRI generation
    encoded_id = URI.encode(version.version_id, &URI.char_unreserved?/1)

    RDF.iri("#{base}version/#{encoded_id}")
  end

  defp generate_previous_version_iri(previous_version_id, context) do
    base = to_string(context.base_iri)
    encoded_id = URI.encode(previous_version_id, &URI.char_unreserved?/1)
    RDF.iri("#{base}version/#{encoded_id}")
  end

  # ===========================================================================
  # Type Triple Generation
  # ===========================================================================

  defp build_type_triples(version_iri, type) do
    # Dual-typing: prov:Entity + specific evolution class
    evolution_class = version_type_to_class(type)
    Helpers.dual_type_triples(version_iri, PROV.Entity, evolution_class)
  end

  @doc """
  Maps a version type atom to its corresponding ontology class.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> VersionBuilder.version_type_to_class(:module) == Evolution.ModuleVersion
      true

      iex> alias ElixirOntologies.Builders.Evolution.VersionBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> VersionBuilder.version_type_to_class(:function) == Evolution.FunctionVersion
      true
  """
  @spec version_type_to_class(atom()) :: RDF.IRI.t()
  def version_type_to_class(:module), do: Evolution.ModuleVersion |> RDF.iri()
  def version_type_to_class(:function), do: Evolution.FunctionVersion |> RDF.iri()
  def version_type_to_class(:type), do: Evolution.TypeVersion |> RDF.iri()
  # Catch-all with guard for unknown atom types
  def version_type_to_class(type) when is_atom(type), do: Evolution.CodeVersion |> RDF.iri()

  # ===========================================================================
  # Version String Triple Generation
  # ===========================================================================

  defp build_version_string_triple(version_iri, version) do
    [
      Helpers.datatype_property(
        version_iri,
        Evolution.versionString(),
        version.version_id,
        RDF.XSD.String
      )
    ]
  end

  # ===========================================================================
  # Previous Version Triple Generation
  # ===========================================================================

  defp build_previous_version_triple(_version_iri, %{previous_version: nil}, _context), do: []

  defp build_previous_version_triple(version_iri, version, context) do
    previous_iri = generate_previous_version_iri(version.previous_version, context)

    [
      Helpers.object_property(version_iri, Evolution.hasPreviousVersion(), previous_iri)
    ]
  end

  # ===========================================================================
  # Timestamp Triple Generation
  # ===========================================================================

  defp build_timestamp_triple(version_iri, %{timestamp: timestamp}) do
    # Use optional_datetime_property which handles nil values
    [Helpers.optional_datetime_property(version_iri, PROV.generatedAtTime(), timestamp)]
  end

  # Handle structs that don't have timestamp field
  defp build_timestamp_triple(_version_iri, _version), do: []
end
