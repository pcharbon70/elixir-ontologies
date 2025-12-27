defmodule ElixirOntologies.Builders.Context do
  @moduledoc """
  Context struct for RDF builder operations.

  The `BuilderContext` maintains state during RDF graph construction, providing:
  - Base IRI for generating resource URIs
  - Current file path being analyzed
  - Parent module IRI for nested modules
  - Configuration options
  - Additional metadata

  ## Usage

      alias ElixirOntologies.Builders.Context

      context = Context.new(
        base_iri: "https://example.org/code#",
        file_path: "lib/my_app/users.ex"
      )

      # Thread context through builders
      {module_iri, triples} = ModuleBuilder.build(module_info, context)

      # Create child context for nested modules
      child_context = Context.with_parent_module(context, module_iri)

  ## Fields

  - `:base_iri` - Base IRI for resource generation (required)
  - `:file_path` - Current file being analyzed (optional)
  - `:parent_module` - Parent module IRI for nested modules (optional)
  - `:config` - Configuration options (optional)
  - `:metadata` - Additional context metadata (optional)
  - `:known_modules` - Set of module names in analysis scope for cross-module linking (optional)
  """

  @enforce_keys [:base_iri]
  defstruct [
    :base_iri,
    :file_path,
    :parent_module,
    config: %{},
    metadata: %{},
    known_modules: nil
  ]

  @type t :: %__MODULE__{
          base_iri: String.t() | RDF.IRI.t(),
          file_path: String.t() | nil,
          parent_module: RDF.IRI.t() | nil,
          config: map(),
          metadata: map(),
          known_modules: MapSet.t(String.t()) | nil
        }

  # ===========================================================================
  # Constructor
  # ===========================================================================

  @doc """
  Creates a new builder context.

  ## Parameters

  - `opts` - Keyword list of context options

  ## Options

  - `:base_iri` - Base IRI for resource generation (required)
  - `:file_path` - Current file being analyzed
  - `:parent_module` - Parent module IRI for nested modules
  - `:config` - Configuration map
  - `:metadata` - Additional metadata map
  - `:known_modules` - MapSet of module names in analysis scope

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> context.base_iri
      "https://example.org/code#"

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   file_path: "lib/my_app.ex"
      ...> )
      iex> context.file_path
      "lib/my_app.ex"

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   config: %{include_private: false}
      ...> )
      iex> context.config.include_private
      false
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    base_iri = Keyword.fetch!(opts, :base_iri)
    file_path = Keyword.get(opts, :file_path)
    parent_module = Keyword.get(opts, :parent_module)
    config = Keyword.get(opts, :config, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    known_modules = Keyword.get(opts, :known_modules)

    %__MODULE__{
      base_iri: base_iri,
      file_path: file_path,
      parent_module: parent_module,
      config: config,
      metadata: metadata,
      known_modules: known_modules
    }
  end

  # ===========================================================================
  # Context Transformations
  # ===========================================================================

  @doc """
  Creates a new context with a parent module IRI.

  Used when building nested modules to maintain the parent-child relationship.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> parent_iri = ~I<https://example.org/code#MyApp>
      iex> child_context = ElixirOntologies.Builders.Context.with_parent_module(context, parent_iri)
      iex> child_context.parent_module
      ~I<https://example.org/code#MyApp>
      iex> child_context.base_iri
      "https://example.org/code#"
  """
  @spec with_parent_module(t(), RDF.IRI.t()) :: t()
  def with_parent_module(%__MODULE__{} = context, parent_module_iri) do
    %{context | parent_module: parent_module_iri}
  end

  @doc """
  Creates a new context with updated metadata.

  Merges the provided metadata map with the existing metadata.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   metadata: %{version: "1.0.0"}
      ...> )
      iex> updated = ElixirOntologies.Builders.Context.with_metadata(context, %{author: "dev"})
      iex> updated.metadata
      %{version: "1.0.0", author: "dev"}
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = context, new_metadata) when is_map(new_metadata) do
    %{context | metadata: Map.merge(context.metadata, new_metadata)}
  end

  @doc """
  Creates a new context with updated configuration.

  Merges the provided config map with the existing configuration.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   config: %{include_private: true}
      ...> )
      iex> updated = ElixirOntologies.Builders.Context.with_config(context, %{include_docs: false})
      iex> updated.config
      %{include_private: true, include_docs: false}
  """
  @spec with_config(t(), map()) :: t()
  def with_config(%__MODULE__{} = context, new_config) when is_map(new_config) do
    %{context | config: Map.merge(context.config, new_config)}
  end

  @doc """
  Creates a new context with a different file path.

  Used when processing multiple files in a project.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   file_path: "lib/users.ex"
      ...> )
      iex> new_context = ElixirOntologies.Builders.Context.with_file_path(context, "lib/accounts.ex")
      iex> new_context.file_path
      "lib/accounts.ex"
  """
  @spec with_file_path(t(), String.t()) :: t()
  def with_file_path(%__MODULE__{} = context, file_path) when is_binary(file_path) do
    %{context | file_path: file_path}
  end

  # ===========================================================================
  # Config Helpers
  # ===========================================================================

  @doc """
  Gets a configuration value from the context.

  Returns the value if present, otherwise returns the provided default.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   config: %{include_private: false}
      ...> )
      iex> ElixirOntologies.Builders.Context.get_config(context, :include_private, true)
      false
      iex> ElixirOntologies.Builders.Context.get_config(context, :include_docs, true)
      true
  """
  @spec get_config(t(), atom(), term()) :: term()
  def get_config(%__MODULE__{config: config}, key, default \\ nil) do
    Map.get(config, key, default)
  end

  @doc """
  Gets a metadata value from the context.

  Returns the value if present, otherwise returns the provided default.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   metadata: %{version: "1.0.0"}
      ...> )
      iex> ElixirOntologies.Builders.Context.get_metadata(context, :version)
      "1.0.0"
      iex> ElixirOntologies.Builders.Context.get_metadata(context, :author, "unknown")
      "unknown"
  """
  @spec get_metadata(t(), atom(), term()) :: term()
  def get_metadata(%__MODULE__{metadata: metadata}, key, default \\ nil) do
    Map.get(metadata, key, default)
  end

  # ===========================================================================
  # Validation
  # ===========================================================================

  @doc """
  Validates that a context is properly configured for building.

  Returns `:ok` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> ElixirOntologies.Builders.Context.validate(context)
      :ok

      iex> context = %ElixirOntologies.Builders.Context{base_iri: nil}
      iex> ElixirOntologies.Builders.Context.validate(context)
      {:error, :missing_base_iri}
  """
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{base_iri: nil}), do: {:error, :missing_base_iri}

  def validate(%__MODULE__{base_iri: base_iri})
      when is_binary(base_iri) or is_struct(base_iri, RDF.IRI),
      do: :ok

  def validate(_), do: {:error, :invalid_context}

  # ===========================================================================
  # Known Modules (Cross-Module Linking)
  # ===========================================================================

  @doc """
  Creates a new context with known modules for cross-module linking.

  Known modules are modules that exist within the analysis scope (e.g., your
  project's modules). When building dependency triples, directives referencing
  known modules will have `isExternalModule = false`, while references to
  unknown modules (e.g., Elixir stdlib, third-party libraries) will have
  `isExternalModule = true`.

  ## Parameters

  - `context` - The context to update
  - `modules` - Either a MapSet of module names or a list of module names

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> known = MapSet.new(["MyApp.Users", "MyApp.Accounts"])
      iex> updated = ElixirOntologies.Builders.Context.with_known_modules(context, known)
      iex> MapSet.member?(updated.known_modules, "MyApp.Users")
      true

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> updated = ElixirOntologies.Builders.Context.with_known_modules(context, ["MyApp.Users", "MyApp.Accounts"])
      iex> MapSet.member?(updated.known_modules, "MyApp.Users")
      true
  """
  @spec with_known_modules(t(), MapSet.t(String.t()) | [String.t()]) :: t()
  def with_known_modules(%__MODULE__{} = context, %MapSet{} = modules) do
    %{context | known_modules: modules}
  end

  def with_known_modules(%__MODULE__{} = context, modules) when is_list(modules) do
    %{context | known_modules: MapSet.new(modules)}
  end

  @doc """
  Checks if a module is known (exists within the analysis scope).

  Returns `true` if the module is in the known_modules set, `false` otherwise.
  If no known_modules set is configured, returns `nil` to indicate that
  cross-module linking is not enabled.

  ## Parameters

  - `context` - The context to check
  - `module_name` - The module name as a string

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> known = MapSet.new(["MyApp.Users", "MyApp.Accounts"])
      iex> context = ElixirOntologies.Builders.Context.with_known_modules(context, known)
      iex> ElixirOntologies.Builders.Context.module_known?(context, "MyApp.Users")
      true
      iex> ElixirOntologies.Builders.Context.module_known?(context, "Enum")
      false

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> ElixirOntologies.Builders.Context.module_known?(context, "MyApp.Users")
      nil
  """
  @spec module_known?(t(), String.t()) :: boolean() | nil
  def module_known?(%__MODULE__{known_modules: nil}, _module_name), do: nil

  def module_known?(%__MODULE__{known_modules: known}, module_name) do
    MapSet.member?(known, module_name)
  end

  @doc """
  Checks if cross-module linking is enabled in the context.

  Cross-module linking is enabled when a `known_modules` set is configured.

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> ElixirOntologies.Builders.Context.cross_module_linking_enabled?(context)
      false

      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/code#")
      iex> context = ElixirOntologies.Builders.Context.with_known_modules(context, ["MyApp"])
      iex> ElixirOntologies.Builders.Context.cross_module_linking_enabled?(context)
      true
  """
  @spec cross_module_linking_enabled?(t()) :: boolean()
  def cross_module_linking_enabled?(%__MODULE__{known_modules: nil}), do: false
  def cross_module_linking_enabled?(%__MODULE__{known_modules: _}), do: true

  # ===========================================================================
  # Context IRI Resolution
  # ===========================================================================

  @doc """
  Gets the context IRI based on available context information.

  The resolution order is:
  1. Module from metadata (if present)
  2. Parent module IRI (if present)
  3. File path (if present)
  4. Fallback namespace appended to base_iri

  This function consolidates the duplicated `get_context_iri/1` pattern
  used across builders.

  ## Parameters

  - `context` - The builder context
  - `fallback_namespace` - Namespace to use when no other context is available
    (e.g., "anonymous", "captures", "closures")

  ## Examples

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#",
      ...>   metadata: %{module: ["MyApp", "Users"]}
      ...> )
      iex> ElixirOntologies.Builders.Context.get_context_iri(context, "anonymous")
      # Returns IRI for MyApp.Users module

      iex> context = ElixirOntologies.Builders.Context.new(
      ...>   base_iri: "https://example.org/code#"
      ...> )
      iex> ElixirOntologies.Builders.Context.get_context_iri(context, "anonymous")
      ~I<https://example.org/code#anonymous>
  """
  @spec get_context_iri(t(), String.t()) :: RDF.IRI.t()
  def get_context_iri(%__MODULE__{metadata: %{module: module}} = context, _fallback)
      when is_list(module) and module != [] do
    module_name = Enum.join(module, ".")
    ElixirOntologies.IRI.for_module(context.base_iri, module_name)
  end

  def get_context_iri(%__MODULE__{parent_module: parent_module}, _fallback)
      when not is_nil(parent_module) do
    parent_module
  end

  def get_context_iri(%__MODULE__{file_path: file_path} = context, _fallback)
      when is_binary(file_path) and file_path != "" do
    ElixirOntologies.IRI.for_source_file(context.base_iri, file_path)
  end

  def get_context_iri(%__MODULE__{} = context, fallback_namespace) do
    RDF.iri("#{context.base_iri}#{fallback_namespace}")
  end
end
