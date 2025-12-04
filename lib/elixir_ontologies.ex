defmodule ElixirOntologies do
  @moduledoc """
  OWL ontologies for modeling Elixir code structure, OTP runtime patterns,
  and code evolution.

  ## Ontology Modules

  This package provides five interconnected ontology modules:

  | Module | File | Description |
  |--------|------|-------------|
  | Core | `elixir-core.ttl` | Language-agnostic AST primitives, BFO/IAO alignment |
  | Structure | `elixir-structure.ttl` | Elixir modules, functions, protocols, behaviours, macros |
  | OTP | `elixir-otp.ttl` | OTP runtime patterns, supervision, GenServer, ETS |
  | Evolution | `elixir-evolution.ttl` | PROV-O provenance, versioning, change tracking |
  | Shapes | `elixir-shapes.ttl` | SHACL validation constraints |

  ## Accessing Ontology Files

  Use `ontology_path/1` to get the path to any ontology file:

      ElixirOntologies.ontology_path("elixir-core.ttl")
      # => "/path/to/priv/ontologies/elixir-core.ttl"

  Or list all available ontologies:

      ElixirOntologies.list_ontologies()
      # => ["elixir-core.ttl", "elixir-evolution.ttl", ...]

  ## Namespaces

  | Prefix | IRI |
  |--------|-----|
  | `core:` | `https://w3id.org/elixir-code/core#` |
  | `struct:` | `https://w3id.org/elixir-code/structure#` |
  | `otp:` | `https://w3id.org/elixir-code/otp#` |
  | `evo:` | `https://w3id.org/elixir-code/evolution#` |
  | `shapes:` | `https://w3id.org/elixir-code/shapes#` |

  ## Usage with RDF Libraries

  These ontologies can be loaded with any RDF library. For example, with `rdf_ex`:

      {:ok, graph} = RDF.Turtle.read_file(ElixirOntologies.ontology_path("elixir-core.ttl"))

  Or with `grax` for mapping to Elixir structs.

  ## Learn More

  See the guides for detailed documentation on each ontology module:

  - [Core Ontology Guide](core.html)
  - [Structure Ontology Guide](structure.html)
  - [OTP Ontology Guide](otp.html)
  - [Evolution Ontology Guide](evolution.html)
  - [Shapes Guide](shapes.html)
  """

  @ontologies_dir "priv/ontologies"

  @doc """
  Returns the absolute path to the ontologies directory.

  ## Example

      ElixirOntologies.ontologies_dir()
      # => "/path/to/elixir_ontologies/priv/ontologies"
  """
  @spec ontologies_dir() :: String.t()
  def ontologies_dir do
    Application.app_dir(:elixir_ontologies, @ontologies_dir)
  end

  @doc """
  Returns the absolute path to a specific ontology file.

  ## Parameters

  - `filename` - The ontology filename (e.g., `"elixir-core.ttl"`)

  ## Example

      ElixirOntologies.ontology_path("elixir-core.ttl")
      # => "/path/to/elixir_ontologies/priv/ontologies/elixir-core.ttl"

  ## Available Ontologies

  - `elixir-core.ttl` - Core AST primitives
  - `elixir-structure.ttl` - Elixir code structure
  - `elixir-otp.ttl` - OTP runtime patterns
  - `elixir-evolution.ttl` - Code evolution and provenance
  - `elixir-shapes.ttl` - SHACL validation shapes
  """
  @spec ontology_path(String.t()) :: String.t()
  def ontology_path(filename) when is_binary(filename) do
    Path.join(ontologies_dir(), filename)
  end

  @doc """
  Lists all available ontology files.

  ## Example

      ElixirOntologies.list_ontologies()
      # => ["elixir-core.ttl", "elixir-evolution.ttl", "elixir-otp.ttl",
      #     "elixir-shapes.ttl", "elixir-structure.ttl"]
  """
  @spec list_ontologies() :: [String.t()]
  def list_ontologies do
    ontologies_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ttl"))
    |> Enum.sort()
  end

  @doc """
  Reads and returns the content of an ontology file.

  ## Parameters

  - `filename` - The ontology filename (e.g., `"elixir-core.ttl"`)

  ## Example

      {:ok, content} = ElixirOntologies.read_ontology("elixir-core.ttl")
  """
  @spec read_ontology(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def read_ontology(filename) when is_binary(filename) do
    filename
    |> ontology_path()
    |> File.read()
  end

  @doc """
  Returns a map of namespace prefixes to their IRIs.

  ## Example

      ElixirOntologies.namespaces()
      # => %{
      #   core: "https://w3id.org/elixir-code/core#",
      #   struct: "https://w3id.org/elixir-code/structure#",
      #   ...
      # }
  """
  @spec namespaces() :: %{atom() => String.t()}
  def namespaces do
    %{
      core: "https://w3id.org/elixir-code/core#",
      struct: "https://w3id.org/elixir-code/structure#",
      otp: "https://w3id.org/elixir-code/otp#",
      evo: "https://w3id.org/elixir-code/evolution#",
      shapes: "https://w3id.org/elixir-code/shapes#"
    }
  end

  @doc """
  Returns the IRI for a specific namespace prefix.

  ## Parameters

  - `prefix` - The namespace prefix atom (e.g., `:core`, `:struct`)

  ## Example

      ElixirOntologies.namespace(:core)
      # => "https://w3id.org/elixir-code/core#"
  """
  @spec namespace(atom()) :: String.t() | nil
  def namespace(prefix) when is_atom(prefix) do
    Map.get(namespaces(), prefix)
  end
end
