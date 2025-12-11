defmodule ElixirOntologies.Validator.ShaclEngine do
  @moduledoc """
  Wrapper for pySHACL validation engine.

  This module provides integration with the pySHACL Python library for SHACL validation.
  It handles:
  - Detection of pySHACL availability
  - Execution of pySHACL command-line tool
  - Temporary file management for RDF serialization
  - Parsing of pySHACL exit codes

  ## pySHACL Exit Codes

  - 0: Validation succeeded (graph conforms)
  - 1: Validation failed (graph does not conform)
  - 2: Error occurred during validation

  ## Installation

  pySHACL can be installed via pip:

      pip install pyshacl

  """

  require Logger

  @pyshacl_command "pyshacl"
  @shapes_file "priv/ontologies/elixir-shapes.ttl"

  @typedoc "Result of SHACL validation"
  @type validation_result ::
          {:ok, :conforms}
          | {:ok, :non_conformant, String.t()}
          | {:error, term()}

  @doc """
  Checks if pySHACL is available on the system.

  ## Examples

      iex> ElixirOntologies.Validator.ShaclEngine.available?()
      true

  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd("which", [@pyshacl_command], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Returns installation instructions for pySHACL.

  ## Examples

      iex> instructions = ElixirOntologies.Validator.ShaclEngine.installation_instructions()
      iex> String.contains?(instructions, "pip install pyshacl")
      true

  """
  @spec installation_instructions() :: String.t()
  def installation_instructions do
    """
    pySHACL is not installed or not available on your system PATH.

    To install pySHACL:

    1. Using pip:
       pip install pyshacl

    2. Using pip3:
       pip3 install pyshacl

    3. Using conda:
       conda install -c conda-forge pyshacl

    For more information, visit: https://github.com/RDFLib/pySHACL

    Requirements:
    - Python 3.9 or higher
    - pip or conda package manager
    """
  end

  @doc """
  Validates an RDF graph against SHACL shapes using pySHACL.

  ## Parameters

  - `data_graph_turtle`: The RDF data graph in Turtle format (string)
  - `opts`: Optional keyword list with:
    - `:shapes_file` - Path to SHACL shapes file (default: priv/ontologies/elixir-shapes.ttl)
    - `:timeout` - Validation timeout in milliseconds (default: 30000)

  ## Returns

  - `{:ok, :conforms}` - Graph conforms to shapes
  - `{:ok, :non_conformant, report_turtle}` - Graph does not conform, includes validation report
  - `{:error, :pyshacl_not_available}` - pySHACL not installed
  - `{:error, {:validation_error, message}}` - Error during validation

  ## Examples

      iex> turtle = "@prefix ex: <http://example.org/> . ex:MyModule a ex:Module ."
      iex> ElixirOntologies.Validator.ShaclEngine.validate(turtle)
      {:ok, :conforms}

  """
  @spec validate(String.t(), keyword()) :: validation_result()
  def validate(data_graph_turtle, opts \\ []) do
    unless available?() do
      {:error, :pyshacl_not_available}
    else
      shapes_file = Keyword.get(opts, :shapes_file, @shapes_file)
      timeout = Keyword.get(opts, :timeout, 30_000)

      with {:ok, data_file} <- write_temp_file(data_graph_turtle, "data.ttl"),
           {:ok, result} <- run_pyshacl(data_file, shapes_file, timeout) do
        File.rm(data_file)
        result
      else
        {:error, reason} = error ->
          Logger.error("SHACL validation error: #{inspect(reason)}")
          error
      end
    end
  end

  # Writes content to a temporary file
  @spec write_temp_file(String.t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  defp write_temp_file(content, filename) do
    temp_dir = System.tmp_dir!()
    temp_file = Path.join(temp_dir, "elixir_ontologies_#{:rand.uniform(999_999)}_#{filename}")

    case File.write(temp_file, content) do
      :ok -> {:ok, temp_file}
      {:error, reason} -> {:error, {:file_write_error, reason}}
    end
  end

  # Executes pySHACL command
  @spec run_pyshacl(Path.t(), Path.t(), non_neg_integer()) :: validation_result()
  defp run_pyshacl(data_file, shapes_file, timeout) do
    # pyshacl -s shapes.ttl -df turtle -sf turtle -f turtle data.ttl
    args = [
      "-s",
      shapes_file,
      "-df",
      "turtle",
      "-sf",
      "turtle",
      "-f",
      "turtle",
      data_file
    ]

    case System.cmd(@pyshacl_command, args, stderr_to_stdout: true, timeout: timeout) do
      {_output, 0} ->
        # Exit code 0: Conformant
        {:ok, :conforms}

      {output, 1} ->
        # Exit code 1: Non-conformant, output contains validation report
        {:ok, :non_conformant, output}

      {output, 2} ->
        # Exit code 2: Error during validation
        {:error, {:validation_error, extract_error_message(output)}}

      {output, exit_code} ->
        # Unexpected exit code
        {:error, {:unexpected_exit_code, exit_code, output}}
    end
  rescue
    error ->
      {:error, {:pyshacl_exception, error}}
  end

  # Extracts error message from pySHACL output
  @spec extract_error_message(String.t()) :: String.t()
  defp extract_error_message(output) do
    # pySHACL typically outputs error messages to stdout
    # Extract the first meaningful line
    output
    |> String.split("\n")
    |> Enum.find(&(String.trim(&1) != ""), fn -> "Unknown validation error" end)
    |> String.trim()
  end
end
