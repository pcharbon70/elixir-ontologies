defmodule ElixirOntologies.SHACL.Model.SPARQLConstraintTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.SPARQLConstraint

  describe "struct creation" do
    test "creates SPARQL constraint with all fields" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Test constraint failed",
        select_query: "SELECT $this WHERE { $this ?p ?o }",
        prefixes_graph: nil
      }

      assert constraint.source_shape_id == ~I<http://example.org/Shape1>
      assert constraint.message == "Test constraint failed"
      assert constraint.select_query == "SELECT $this WHERE { $this ?p ?o }"
      assert constraint.prefixes_graph == nil
    end

    test "creates SPARQL constraint without prefixes_graph" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Violation",
        select_query: "SELECT $this WHERE { }",
        prefixes_graph: nil
      }

      assert constraint.prefixes_graph == nil
    end

    test "creates SPARQL constraint with prefixes_graph" do
      prefixes_graph = RDF.Graph.new()

      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Violation",
        select_query: "SELECT $this WHERE { }",
        prefixes_graph: prefixes_graph
      }

      assert constraint.prefixes_graph == prefixes_graph
    end
  end

  describe "$this placeholder" do
    test "query contains $this placeholder" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Violation",
        select_query: """
        SELECT $this
        WHERE {
          $this <http://example.org/prop> ?value .
        }
        """,
        prefixes_graph: nil
      }

      assert String.contains?(constraint.select_query, "$this")
    end

    test "query can have multiple $this occurrences" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<http://example.org/Shape1>,
        message: "Violation",
        select_query: """
        SELECT $this
        WHERE {
          $this <http://example.org/start> ?start ;
                <http://example.org/end> ?end .
          FILTER (?end < ?start)
        }
        """,
        prefixes_graph: nil
      }

      count = constraint.select_query |> String.split("$this") |> length() |> Kernel.-(1)
      assert count == 2
    end
  end

  describe "real-world usage from elixir-shapes.ttl" do
    test "creates SourceLocationShape SPARQL constraint" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#SourceLocationShape>,
        message: "Source location endLine must be >= startLine",
        select_query: """
        PREFIX core: <https://w3id.org/elixir-code/core#>
        SELECT $this
        WHERE {
          $this core:startLine ?start ;
                core:endLine ?end .
          FILTER (?end < ?start)
        }
        """,
        prefixes_graph: nil
      }

      assert constraint.source_shape_id ==
               ~I<https://w3id.org/elixir-code/shapes#SourceLocationShape>

      assert String.contains?(constraint.select_query, "$this")
      assert String.contains?(constraint.select_query, "FILTER")
    end

    test "creates FunctionArityMatchShape SPARQL constraint" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
        message: "Function arity must equal the number of parameters",
        select_query: """
        PREFIX struct: <https://w3id.org/elixir-code/structure#>
        SELECT $this ?arity (COUNT(?param) AS ?paramCount)
        WHERE {
          $this struct:arity ?arity ;
                struct:hasParameter ?param .
        }
        GROUP BY $this ?arity
        HAVING (?arity != COUNT(?param))
        """,
        prefixes_graph: nil
      }

      assert constraint.message == "Function arity must equal the number of parameters"
      assert String.contains?(constraint.select_query, "GROUP BY")
      assert String.contains?(constraint.select_query, "HAVING")
    end

    test "creates ProtocolComplianceShape SPARQL constraint" do
      constraint = %SPARQLConstraint{
        source_shape_id: ~I<https://w3id.org/elixir-code/shapes#ProtocolComplianceShape>,
        message: "Protocol implementation must implement all protocol functions",
        select_query: """
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
        """,
        prefixes_graph: nil
      }

      assert String.contains?(constraint.select_query, "FILTER NOT EXISTS")
      assert String.contains?(constraint.select_query, "implementsProtocol")
    end
  end
end
