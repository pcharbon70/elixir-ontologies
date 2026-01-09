defmodule ElixirOntologies.Config do
  @moduledoc """
  Configuration for ElixirOntologies analysis and graph generation.

  This module provides a centralized configuration struct and functions
  for managing analyzer settings including base IRI, output options,
  and feature flags.

  ## Configuration Options

  - `base_iri` - Base IRI for generating resource URIs (default: `"https://example.org/code#"`)
  - `include_source_text` - Include source code text in triples (default: `false`)
  - `include_git_info` - Include git provenance information (default: `true`)
  - `output_format` - Output format: `:turtle`, `:ntriples`, or `:jsonld` (default: `:turtle`)
  - `include_expressions` - Include full expression ASTs in triples (default: `false`)

  ## Expression Extraction

  When `include_expressions` is `true`, the extractor will capture full expression
  trees for guards, conditions, function bodies, and other code constructs. This
  provides complete AST representation but significantly increases storage requirements.

  **Storage Impact:**
  - Light mode (default): ~500 KB per 100 functions
  - Full mode: ~5-20 MB per 100 functions

  **Project vs Dependencies:**
  Expression extraction only applies to project code, not dependencies. Files in
  the `/deps/` directory are always extracted in light mode regardless of the
  `include_expressions` setting. This design keeps storage manageable when analyzing
  projects with many dependencies.

  ## Example

      config = ElixirOntologies.Config.default()
      #=> %ElixirOntologies.Config{base_iri: "https://example.org/code#", ...}

      custom = ElixirOntologies.Config.merge(config, base_iri: "https://myproject.org/")
      #=> %ElixirOntologies.Config{base_iri: "https://myproject.org/", ...}

      full_mode = ElixirOntologies.Config.merge(config, include_expressions: true)
      #=> %ElixirOntologies.Config{include_expressions: true, ...}

  """

  @default_base_iri "https://example.org/code#"
  @valid_output_formats [:turtle, :ntriples, :jsonld]

  defstruct base_iri: @default_base_iri,
            include_source_text: false,
            include_git_info: true,
            output_format: :turtle,
            include_expressions: false

  @type t :: %__MODULE__{
          base_iri: String.t(),
          include_source_text: boolean(),
          include_git_info: boolean(),
          output_format: :turtle | :ntriples | :jsonld,
          include_expressions: boolean()
        }

  @doc """
  Returns a configuration with sensible default values.

  ## Defaults

  - `base_iri` - `"https://example.org/code#"` (should be customized)
  - `include_source_text` - `false` (opt-in to avoid large graphs)
  - `include_git_info` - `true` (useful for provenance)
  - `output_format` - `:turtle` (human-readable)
  - `include_expressions` - `false` (opt-in for full AST extraction)

  ## Example

      iex> config = ElixirOntologies.Config.default()
      iex> config.base_iri
      "https://example.org/code#"
      iex> config.include_source_text
      false
      iex> config.include_expressions
      false

  """
  @spec default() :: t()
  def default do
    %__MODULE__{}
  end

  @doc """
  Merges user options with a configuration, returning a new configuration.

  Options provided will override the corresponding fields in the base config.
  Unknown options are ignored.

  ## Parameters

  - `config` - The base configuration (typically from `default/0`)
  - `opts` - Keyword list of options to override

  ## Example

      iex> config = ElixirOntologies.Config.default()
      iex> merged = ElixirOntologies.Config.merge(config, base_iri: "https://myapp.org/")
      iex> merged.base_iri
      "https://myapp.org/"
      iex> merged.include_git_info
      true

  """
  @spec merge(t(), keyword()) :: t()
  def merge(%__MODULE__{} = config, opts) when is_list(opts) do
    valid_keys = [:base_iri, :include_source_text, :include_git_info, :output_format, :include_expressions]

    filtered_opts =
      opts
      |> Enum.filter(fn {key, _} -> key in valid_keys end)

    struct(config, filtered_opts)
  end

  @doc """
  Validates a configuration, returning `{:ok, config}` or `{:error, reasons}`.

  Checks:
  - `base_iri` must be a non-empty string
  - `include_source_text` must be a boolean
  - `include_git_info` must be a boolean
  - `output_format` must be one of `:turtle`, `:ntriples`, or `:jsonld`
  - `include_expressions` must be a boolean

  ## Example

      iex> config = ElixirOntologies.Config.default()
      iex> ElixirOntologies.Config.validate(config)
      {:ok, config}

      iex> invalid = %ElixirOntologies.Config{base_iri: "", output_format: :invalid}
      iex> {:error, reasons} = ElixirOntologies.Config.validate(invalid)
      iex> "base_iri must be a non-empty string" in reasons
      true

  """
  @spec validate(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(%__MODULE__{} = config) do
    errors =
      []
      |> validate_base_iri(config.base_iri)
      |> validate_boolean(:include_source_text, config.include_source_text)
      |> validate_boolean(:include_git_info, config.include_git_info)
      |> validate_boolean(:include_expressions, config.include_expressions)
      |> validate_output_format(config.output_format)

    case errors do
      [] -> {:ok, config}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates a configuration, raising on error.

  Same as `validate/1` but raises `ArgumentError` if validation fails.

  ## Example

      iex> config = ElixirOntologies.Config.default()
      iex> ElixirOntologies.Config.validate!(config)
      %ElixirOntologies.Config{}

  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    case validate(config) do
      {:ok, config} -> config
      {:error, reasons} -> raise ArgumentError, "Invalid config: #{Enum.join(reasons, "; ")}"
    end
  end

  @doc """
  Creates a new configuration from options, using defaults for unspecified fields.

  This is a convenience function combining `default/0`, `merge/2`, and `validate!/1`.

  ## Example

      iex> config = ElixirOntologies.Config.new(base_iri: "https://myapp.org/")
      iex> config.base_iri
      "https://myapp.org/"

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    default()
    |> merge(opts)
    |> validate!()
  end

  # Private validation helpers

  defp validate_base_iri(errors, base_iri) when is_binary(base_iri) and byte_size(base_iri) > 0 do
    errors
  end

  defp validate_base_iri(errors, _base_iri) do
    ["base_iri must be a non-empty string" | errors]
  end

  defp validate_boolean(errors, _field, value) when is_boolean(value) do
    errors
  end

  defp validate_boolean(errors, field, _value) do
    ["#{field} must be a boolean" | errors]
  end

  defp validate_output_format(errors, format) when format in @valid_output_formats do
    errors
  end

  defp validate_output_format(errors, _format) do
    ["output_format must be one of: #{inspect(@valid_output_formats)}" | errors]
  end

  # ===========================================================================
  # Project File Detection (Expression Extraction)
  # ===========================================================================

  @doc """
  Determines if a file path belongs to the project code (not a dependency).

  Returns `true` if the path does not contain `/deps/`, indicating it's part of
  the project source code. Returns `false` if the path contains `/deps/`, indicating
  it's a dependency that should always use light mode.

  This distinction is important for expression extraction: we want full expression
  details for project code but only structural metadata for dependencies to keep
  storage manageable.

  ## Parameters

  - `file_path` - The file path to check (can be `nil`)

  ## Returns

  - `true` if the path is project code (not in `/deps/`)
  - `false` if the path is in `/deps/` or is `nil`

  ## Examples

      iex> ElixirOntologies.Config.project_file?("lib/my_app/users.ex")
      true

      iex> ElixirOntologies.Config.project_file?("src/my_app/users.ex")
      true

      iex> ElixirOntologies.Config.project_file?("deps/decimal/lib/decimal.ex")
      false

      iex> ElixirOntologies.Config.project_file?("/path/to/project/deps/nimble_parsec/lib/parsec.ex")
      false

      iex> ElixirOntologies.Config.project_file?(nil)
      false

  """
  @spec project_file?(String.t() | nil) :: boolean()
  def project_file?(nil), do: false

  def project_file?(file_path) when is_binary(file_path) do
    # Check if file is in a dependencies directory
    # Handle both "deps/" at start and "/deps/" or "deps/" in middle of path
    not deps_path?(file_path)
  end

  # Checks if a path is within a dependencies directory
  defp deps_path?(path) do
    # Check for "deps/" as a path component anywhere in the path
    String.contains?(path, "/deps/") or
      String.contains?(path, "\\deps\\") or
      String.starts_with?(path, "deps/") or
      String.starts_with?(path, "deps\\")
  end

  @doc """
  Determines if full expression extraction should be enabled for a given file.

  Full expression extraction is enabled only when BOTH:
  1. `config.include_expressions` is `true`
  2. The file is project code (not in `/deps/`)

  This ensures that dependencies are always extracted in light mode regardless of
  the `include_expressions` setting, keeping storage manageable for projects with
  many dependencies.

  ## Parameters

  - `file_path` - The file path to check
  - `config` - The configuration struct

  ## Returns

  - `true` if full expression extraction should be used
  - `false` if light mode should be used

  ## Examples

      iex> config = ElixirOntologies.Config.new(include_expressions: true)
      iex> ElixirOntologies.Config.should_extract_full?("lib/my_app/users.ex", config)
      true

      iex> config = ElixirOntologies.Config.new(include_expressions: true)
      iex> ElixirOntologies.Config.should_extract_full?("deps/decimal/lib/decimal.ex", config)
      false

      iex> config = ElixirOntologies.Config.new(include_expressions: false)
      iex> ElixirOntologies.Config.should_extract_full?("lib/my_app/users.ex", config)
      false

  """
  @spec should_extract_full?(String.t() | nil, t()) :: boolean()
  def should_extract_full?(file_path, %__MODULE__{} = config) do
    config.include_expressions and project_file?(file_path)
  end
end
