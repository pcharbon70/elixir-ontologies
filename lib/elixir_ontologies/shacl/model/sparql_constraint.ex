defmodule ElixirOntologies.SHACL.Model.SPARQLConstraint do
  @moduledoc """
  Represents a SHACL-SPARQL constraint (sh:sparql).

  SPARQL constraints allow complex validation logic that cannot be expressed
  with standard property constraints. The constraint is defined as a SPARQL
  SELECT query that uses the special `$this` placeholder for the focus node.

  ## SPARQL Constraints in elixir-shapes.ttl

  The Elixir ontology shapes file uses three SPARQL constraints:

  1. **SourceLocationShape** - Validates that endLine >= startLine for source locations
  2. **FunctionArityMatchShape** - Validates that function arity matches parameter count
  3. **ProtocolComplianceShape** - Validates that protocol implementations cover all functions

  ## Query Execution Model

  During validation:
  1. Replace `$this` with the actual focus node IRI or blank node
  2. Execute the SELECT query against the data graph
  3. If the query returns results, a violation occurred
  4. Each result row represents one violation

  ## Fields

  - `source_shape_id` - The IRI of the node shape containing this constraint
  - `message` - Error message template for violations
  - `select_query` - SPARQL SELECT query string with `$this` placeholder
  - `prefixes_graph` - Optional RDF graph containing prefix declarations

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.SPARQLConstraint
      iex> # Source location constraint
      iex> %SPARQLConstraint{
      ...>   source_shape_id: ~I<https://w3id.org/elixir-code/shapes#SourceLocationShape>,
      ...>   message: "Source location endLine must be >= startLine",
      ...>   select_query: \"\"\"
      ...>     SELECT $this
      ...>     WHERE {
      ...>       $this core:startLine ?start ;
      ...>             core:endLine ?end .
      ...>       FILTER (?end < ?start)
      ...>     }
      ...>   \"\"\",
      ...>   prefixes_graph: nil
      ...> }
      %ElixirOntologies.SHACL.Model.SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#SourceLocationShape>,
        message: "Source location endLine must be >= startLine",
        select_query: "SELECT $this\\nWHERE {\\n  $this core:startLine ?start ;\\n ...",
        prefixes_graph: nil
      }

  ## Real-World Usage

  From elixir-shapes.ttl:

      # Function arity must match parameter count
      %SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
        message: "Function arity must equal the number of parameters",
        select_query: \"\"\"
          PREFIX struct: <https://w3id.org/elixir-code/structure#>
          SELECT $this ?arity (COUNT(?param) AS ?paramCount)
          WHERE {
            $this struct:arity ?arity ;
                  struct:hasParameter ?param .
          }
          GROUP BY $this ?arity
          HAVING (?arity != COUNT(?param))
        \"\"\",
        prefixes_graph: nil
      }

      # Protocol implementation must cover all protocol functions
      %SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#ProtocolComplianceShape>,
        message: "Protocol implementation must implement all protocol functions",
        select_query: \"\"\"
          PREFIX struct: <https://w3id.org/elixir-code/structure#>
          SELECT $this ?protocol ?missing
          WHERE {
            $this struct:implementsProtocol ?protocol .
            ?protocol struct:hasFunction ?missing .
            FILTER NOT EXISTS {
              $this struct:hasFunction ?impl .
              ?impl struct:functionName ?name .
              ?missing struct:functionName ?name .
            }
          }
        \"\"\",
        prefixes_graph: nil
      }

  ## The `$this` Placeholder

  The `$this` placeholder is replaced during validation with the focus node's IRI
  or blank node identifier. For example, if validating a function:

      # Before substitution
      SELECT $this WHERE { $this struct:arity ?a }

      # After substitution (IRI)
      SELECT <http://example.org/MyModule#foo/2>
      WHERE { <http://example.org/MyModule#foo/2> struct:arity ?a }

      # After substitution (blank node)
      SELECT _:b42 WHERE { _:b42 struct:arity ?a }

  ## Prefixes

  The `prefixes_graph` field can optionally store prefix declarations from the
  shapes graph. In practice, prefixes are usually inherited from the shapes
  file's context, so this field is often `nil`.
  """

  defstruct [
    # RDF.IRI.t()
    :source_shape_id,
    # String.t()
    :message,
    # String.t() - raw SPARQL with $this
    :select_query,
    # RDF.Graph.t() | nil
    :prefixes_graph
  ]

  @type t :: %__MODULE__{
          source_shape_id: RDF.IRI.t(),
          message: String.t(),
          select_query: String.t(),
          prefixes_graph: RDF.Graph.t() | nil
        }
end
