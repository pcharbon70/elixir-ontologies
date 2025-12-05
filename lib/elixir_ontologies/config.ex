defmodule ElixirOntologies.Config do
  @moduledoc """
  Configuration for ElixirOntologies analysis and graph generation.

  This module provides a centralized configuration struct and functions
  for managing analyzer settings including base IRI, output options,
  and feature flags.

  ## Example

      config = ElixirOntologies.Config.default()
      #=> %ElixirOntologies.Config{base_iri: "https://example.org/code#", ...}

      custom = ElixirOntologies.Config.merge(config, base_iri: "https://myproject.org/")
      #=> %ElixirOntologies.Config{base_iri: "https://myproject.org/", ...}

  """

  @default_base_iri "https://example.org/code#"
  @valid_output_formats [:turtle, :ntriples, :jsonld]

  defstruct base_iri: @default_base_iri,
            include_source_text: false,
            include_git_info: true,
            output_format: :turtle

  @type t :: %__MODULE__{
          base_iri: String.t(),
          include_source_text: boolean(),
          include_git_info: boolean(),
          output_format: :turtle | :ntriples | :jsonld
        }

  @doc """
  Returns a configuration with sensible default values.

  ## Defaults

  - `base_iri` - `"https://example.org/code#"` (should be customized)
  - `include_source_text` - `false` (opt-in to avoid large graphs)
  - `include_git_info` - `true` (useful for provenance)
  - `output_format` - `:turtle` (human-readable)

  ## Example

      iex> config = ElixirOntologies.Config.default()
      iex> config.base_iri
      "https://example.org/code#"
      iex> config.include_source_text
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
    valid_keys = [:base_iri, :include_source_text, :include_git_info, :output_format]

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
end
