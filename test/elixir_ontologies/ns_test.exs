defmodule ElixirOntologies.NSTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.NS
  alias ElixirOntologies.NS.{Core, Structure, OTP, Evolution, PROV, BFO, IAO, DC, DCTerms}

  # Note: RDF.ex vocabulary namespaces create two types of terms:
  # - Uppercase terms (like CodeElement) are module aliases that implement RDF protocols
  # - Lowercase terms (like hasSourceLocation) are functions that return RDF.IRI structs
  #
  # Both can be used in RDF graph operations, but they're accessed differently:
  # - Core.CodeElement (no parentheses - module reference)
  # - Core.hasSourceLocation() (with parentheses - function call)

  describe "Core namespace" do
    test "has correct base IRI" do
      assert to_string(Core.__base_iri__()) == "https://w3id.org/elixir-code/core#"
    end

    test "defines CodeElement class" do
      # Uppercase terms are module aliases that work as IRIs via protocol dispatch
      assert RDF.IRI.valid?(Core.CodeElement)

      assert RDF.iri(Core.CodeElement) |> to_string() ==
               "https://w3id.org/elixir-code/core#CodeElement"
    end

    test "defines SourceLocation class" do
      assert RDF.IRI.valid?(Core.SourceLocation)

      assert RDF.iri(Core.SourceLocation) |> to_string() ==
               "https://w3id.org/elixir-code/core#SourceLocation"
    end

    test "defines ASTNode class" do
      assert RDF.IRI.valid?(Core.ASTNode)
    end

    test "defines Expression class" do
      assert RDF.IRI.valid?(Core.Expression)
    end

    test "defines hasSourceLocation property" do
      # Lowercase terms are functions that return RDF.IRI
      iri = Core.hasSourceLocation()
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://w3id.org/elixir-code/core#hasSourceLocation"
    end

    test "defines startLine property" do
      assert %RDF.IRI{} = Core.startLine()
    end

    test "defines literal types" do
      assert RDF.IRI.valid?(Core.AtomLiteral)
      assert RDF.IRI.valid?(Core.IntegerLiteral)
      assert RDF.IRI.valid?(Core.StringLiteral)
    end

    test "defines operator classes" do
      assert RDF.IRI.valid?(Core.PipeOperator)
      assert RDF.IRI.valid?(Core.MatchOperator)
    end

    test "defines control flow classes" do
      assert RDF.IRI.valid?(Core.CaseExpression)
      assert RDF.IRI.valid?(Core.IfExpression)
      assert RDF.IRI.valid?(Core.WithExpression)
    end
  end

  describe "Structure namespace" do
    test "has correct base IRI" do
      assert to_string(Structure.__base_iri__()) == "https://w3id.org/elixir-code/structure#"
    end

    test "defines Module class" do
      assert RDF.IRI.valid?(Structure.Module)

      assert RDF.iri(Structure.Module) |> to_string() ==
               "https://w3id.org/elixir-code/structure#Module"
    end

    test "defines Function class" do
      assert RDF.IRI.valid?(Structure.Function)
    end

    test "defines function identity properties" do
      assert %RDF.IRI{} = Structure.functionName()
      assert %RDF.IRI{} = Structure.arity()
      assert %RDF.IRI{} = Structure.belongsTo()
    end

    test "defines FunctionClause class" do
      assert RDF.IRI.valid?(Structure.FunctionClause)
    end

    test "defines Parameter class" do
      assert RDF.IRI.valid?(Structure.Parameter)
    end

    test "defines Protocol and Behaviour classes" do
      assert RDF.IRI.valid?(Structure.Protocol)
      assert RDF.IRI.valid?(Structure.Behaviour)
    end

    test "defines Struct class" do
      assert RDF.IRI.valid?(Structure.Struct)
    end

    test "defines Macro class" do
      assert RDF.IRI.valid?(Structure.Macro)
    end

    test "defines TypeSpec class" do
      assert RDF.IRI.valid?(Structure.TypeSpec)
    end
  end

  describe "OTP namespace" do
    test "has correct base IRI" do
      assert to_string(OTP.__base_iri__()) == "https://w3id.org/elixir-code/otp#"
    end

    test "defines Process class" do
      assert RDF.IRI.valid?(OTP.Process)
      assert RDF.iri(OTP.Process) |> to_string() == "https://w3id.org/elixir-code/otp#Process"
    end

    test "defines GenServer class" do
      assert RDF.IRI.valid?(OTP.GenServer)
    end

    test "defines Supervisor class" do
      assert RDF.IRI.valid?(OTP.Supervisor)
    end

    test "defines Agent and Task classes" do
      assert RDF.IRI.valid?(OTP.Agent)
      assert RDF.IRI.valid?(OTP.Task)
    end

    test "defines supervision strategy individuals" do
      assert RDF.IRI.valid?(OTP.OneForOne)
      assert RDF.IRI.valid?(OTP.OneForAll)
      assert RDF.IRI.valid?(OTP.RestForOne)
    end

    test "defines ETSTable class" do
      assert RDF.IRI.valid?(OTP.ETSTable)
    end

    test "defines Node class" do
      assert RDF.IRI.valid?(OTP.Node)
    end
  end

  describe "Evolution namespace" do
    test "has correct base IRI" do
      assert to_string(Evolution.__base_iri__()) == "https://w3id.org/elixir-code/evolution#"
    end

    test "defines CodeVersion class" do
      assert RDF.IRI.valid?(Evolution.CodeVersion)

      assert RDF.iri(Evolution.CodeVersion) |> to_string() ==
               "https://w3id.org/elixir-code/evolution#CodeVersion"
    end

    test "defines Commit class" do
      assert RDF.IRI.valid?(Evolution.Commit)
    end

    test "defines Developer class" do
      assert RDF.IRI.valid?(Evolution.Developer)
    end

    test "defines ChangeSet class" do
      assert RDF.IRI.valid?(Evolution.ChangeSet)
    end

    test "defines Repository class" do
      assert RDF.IRI.valid?(Evolution.Repository)
    end

    test "defines Branch and Tag classes" do
      assert RDF.IRI.valid?(Evolution.Branch)
      assert RDF.IRI.valid?(Evolution.Tag)
    end

    test "defines development activity classes" do
      assert RDF.IRI.valid?(Evolution.DevelopmentActivity)
      assert RDF.IRI.valid?(Evolution.Refactoring)
      assert RDF.IRI.valid?(Evolution.BugFix)
    end
  end

  describe "PROV namespace" do
    test "has correct base IRI" do
      assert to_string(PROV.__base_iri__()) == "http://www.w3.org/ns/prov#"
    end

    test "defines Entity class" do
      assert RDF.IRI.valid?(PROV.Entity)
    end

    test "defines Activity class" do
      assert RDF.IRI.valid?(PROV.Activity)
    end

    test "defines Agent class" do
      assert RDF.IRI.valid?(PROV.Agent)
    end

    test "defines provenance properties" do
      assert %RDF.IRI{} = PROV.wasGeneratedBy()
      assert %RDF.IRI{} = PROV.wasAttributedTo()
      assert %RDF.IRI{} = PROV.used()
    end
  end

  describe "BFO namespace" do
    test "has correct base IRI" do
      assert to_string(BFO.__base_iri__()) == "http://purl.obolibrary.org/obo/"
    end

    test "defines BFO terms" do
      # BFO_0000031 is Generically Dependent Continuant
      assert RDF.IRI.valid?(BFO.BFO_0000031)

      assert RDF.iri(BFO.BFO_0000031) |> to_string() ==
               "http://purl.obolibrary.org/obo/BFO_0000031"
    end
  end

  describe "IAO namespace" do
    test "has correct base IRI" do
      assert to_string(IAO.__base_iri__()) == "http://purl.obolibrary.org/obo/IAO_"
    end

    test "defines aliased IAO terms" do
      # information_content_entity is IAO_0000030
      iri = IAO.information_content_entity()
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "http://purl.obolibrary.org/obo/IAO_0000030"
    end

    test "defines definition term" do
      # definition is IAO_0000115
      iri = IAO.definition()
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "http://purl.obolibrary.org/obo/IAO_0000115"
    end
  end

  describe "DC namespace" do
    test "has correct base IRI" do
      assert to_string(DC.__base_iri__()) == "http://purl.org/dc/elements/1.1/"
    end

    test "defines common DC terms" do
      assert %RDF.IRI{} = DC.title()
      assert %RDF.IRI{} = DC.creator()
      assert %RDF.IRI{} = DC.description()
    end
  end

  describe "DCTerms namespace" do
    test "has correct base IRI" do
      assert to_string(DCTerms.__base_iri__()) == "http://purl.org/dc/terms/"
    end

    test "defines common DCTerms properties" do
      assert %RDF.IRI{} = DCTerms.created()
      assert %RDF.IRI{} = DCTerms.modified()
      assert %RDF.IRI{} = DCTerms.license()
    end
  end

  describe "prefix_map/0" do
    test "returns a keyword list" do
      prefix_map = NS.prefix_map()
      assert is_list(prefix_map)
      assert Keyword.keyword?(prefix_map)
    end

    test "includes all Elixir ontology prefixes" do
      prefix_map = NS.prefix_map()
      assert Keyword.has_key?(prefix_map, :core)
      assert Keyword.has_key?(prefix_map, :struct)
      assert Keyword.has_key?(prefix_map, :otp)
      assert Keyword.has_key?(prefix_map, :evo)
    end

    test "includes standard namespace prefixes" do
      prefix_map = NS.prefix_map()
      assert Keyword.has_key?(prefix_map, :rdf)
      assert Keyword.has_key?(prefix_map, :rdfs)
      assert Keyword.has_key?(prefix_map, :owl)
      assert Keyword.has_key?(prefix_map, :xsd)
      assert Keyword.has_key?(prefix_map, :skos)
      assert Keyword.has_key?(prefix_map, :prov)
    end

    test "includes BFO and IAO prefixes" do
      prefix_map = NS.prefix_map()
      assert Keyword.has_key?(prefix_map, :bfo)
      assert Keyword.has_key?(prefix_map, :iao)
    end

    test "includes Dublin Core prefixes" do
      prefix_map = NS.prefix_map()
      assert Keyword.has_key?(prefix_map, :dc)
      assert Keyword.has_key?(prefix_map, :dcterms)
    end

    test "prefix values are strings representing IRIs" do
      prefix_map = NS.prefix_map()
      # __base_iri__() returns strings, not RDF.IRI structs
      assert is_binary(prefix_map[:core])
      assert prefix_map[:core] == "https://w3id.org/elixir-code/core#"
      assert is_binary(prefix_map[:rdf])
    end
  end

  describe "base_iri/1" do
    test "returns correct IRI string for known prefixes" do
      assert is_binary(NS.base_iri(:core))
      assert NS.base_iri(:core) == "https://w3id.org/elixir-code/core#"
      assert NS.base_iri(:struct) == "https://w3id.org/elixir-code/structure#"
      assert NS.base_iri(:otp) == "https://w3id.org/elixir-code/otp#"
      assert NS.base_iri(:evo) == "https://w3id.org/elixir-code/evolution#"
    end

    test "returns nil for unknown prefixes" do
      assert NS.base_iri(:unknown) == nil
      assert NS.base_iri(:foo) == nil
    end
  end

  describe "RDF graph construction" do
    test "can build a simple graph using namespaces" do
      module_iri = RDF.iri("https://example.org/code#MyApp.Users")

      graph =
        RDF.Graph.new()
        |> RDF.Graph.add({module_iri, RDF.type(), Structure.Module})
        |> RDF.Graph.add({module_iri, Structure.moduleName(), "MyApp.Users"})

      assert RDF.Graph.include?(graph, {module_iri, RDF.type(), Structure.Module})
      assert RDF.Graph.triple_count(graph) == 2
    end

    test "can serialize graph with prefix_map" do
      module_iri = RDF.iri("https://example.org/code#MyApp.Users")

      graph =
        RDF.Graph.new()
        |> RDF.Graph.add({module_iri, RDF.type(), Structure.Module})

      {:ok, turtle} = RDF.Turtle.write_string(graph, prefixes: NS.prefix_map())

      assert is_binary(turtle)
      assert turtle =~ "struct:Module"
    end
  end
end
