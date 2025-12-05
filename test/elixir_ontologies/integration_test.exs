defmodule ElixirOntologies.IntegrationTest do
  @moduledoc """
  Integration tests for Phase 1 of ElixirOntologies.

  These tests verify that all Phase 1 components work together correctly:
  - Config: Configuration management
  - NS: RDF namespace definitions
  - IRI: IRI generation
  - Graph: Graph CRUD operations
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.{Config, Graph, IRI, NS}
  alias ElixirOntologies.NS.{Core, Structure, OTP, Evolution}

  @moduletag :integration

  # ============================================================================
  # Complete Workflow Tests
  # ============================================================================

  describe "complete workflow: create → add → save → load → verify" do
    @tag :tmp_dir
    test "round-trip preserves graph content", %{tmp_dir: tmp_dir} do
      # 1. Create a new graph with a base IRI (use trailing / for proper round-trip)
      base_iri = "https://example.org/test/"
      graph = Graph.new(base_iri: base_iri)

      # 2. Generate IRIs for code elements
      module_iri = IRI.for_module(base_iri, "MyApp.Users")
      function_iri = IRI.for_function(base_iri, "MyApp.Users", "get_user", 1)
      clause_iri = IRI.for_clause(function_iri, 0)

      # 3. Add triples using namespace terms
      graph =
        graph
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Structure.moduleName(), "MyApp.Users"})
        |> Graph.add({function_iri, RDF.type(), Structure.Function})
        |> Graph.add({function_iri, Structure.functionName(), "get_user"})
        |> Graph.add({function_iri, Structure.arity(), 1})
        |> Graph.add({function_iri, Structure.belongsTo(), module_iri})
        |> Graph.add({clause_iri, RDF.type(), Structure.FunctionClause})
        |> Graph.add({function_iri, Structure.hasClause(), clause_iri})

      # 4. Save to file
      file_path = Path.join(tmp_dir, "test_graph.ttl")
      :ok = Graph.save(graph, file_path)

      # 5. Load from file
      {:ok, loaded_graph} = Graph.load(file_path)

      # 6. Verify content is preserved
      assert Graph.statement_count(loaded_graph) == Graph.statement_count(graph)

      # Verify specific triples
      loaded_subjects = Graph.subjects(loaded_graph)
      assert MapSet.member?(loaded_subjects, module_iri)
      assert MapSet.member?(loaded_subjects, function_iri)
      assert MapSet.member?(loaded_subjects, clause_iri)

      # Verify module description
      module_desc = Graph.describe(loaded_graph, module_iri)
      assert RDF.Description.include?(module_desc, {RDF.type(), Structure.Module})
      assert RDF.Description.include?(module_desc, {Structure.moduleName(), "MyApp.Users"})

      # Verify function description
      func_desc = Graph.describe(loaded_graph, function_iri)
      assert RDF.Description.include?(func_desc, {RDF.type(), Structure.Function})
      assert RDF.Description.include?(func_desc, {Structure.functionName(), "get_user"})
      assert RDF.Description.include?(func_desc, {Structure.arity(), 1})
    end

    @tag :tmp_dir
    test "multiple save/load cycles preserve content", %{tmp_dir: tmp_dir} do
      base_iri = "https://example.org/multi#"
      module_iri = IRI.for_module(base_iri, "TestModule")

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Structure.moduleName(), "TestModule"})

      original_count = Graph.statement_count(graph)

      # Save and load 3 times
      result_graph =
        Enum.reduce(1..3, graph, fn i, g ->
          path = Path.join(tmp_dir, "cycle_#{i}.ttl")
          :ok = Graph.save(g, path)
          {:ok, loaded} = Graph.load(path)
          loaded
        end)

      assert Graph.statement_count(result_graph) == original_count
    end

    @tag :tmp_dir
    test "complex graph with all ontology layers", %{tmp_dir: tmp_dir} do
      base_iri = "https://example.org/full/"
      graph = Graph.new(base_iri: base_iri)

      # Core layer - source file
      file_iri = IRI.for_source_file(base_iri, "lib/app.ex")
      location_iri = IRI.for_source_location(file_iri, 1, 50)

      # Structure layer - module and function
      module_iri = IRI.for_module(base_iri, "App")
      function_iri = IRI.for_function(base_iri, "App", "start", 2)

      # OTP layer - GenServer
      genserver_iri = IRI.for_module(base_iri, "App.Server")

      # Evolution layer - repository
      repo_iri = IRI.for_repository(base_iri, "https://github.com/user/app")
      commit_iri = IRI.for_commit(repo_iri, "abc123")

      graph =
        graph
        # Core triples
        |> Graph.add({file_iri, RDF.type(), Core.SourceFile})
        |> Graph.add({location_iri, RDF.type(), Core.SourceLocation})
        |> Graph.add({location_iri, Core.inSourceFile(), file_iri})
        # Structure triples
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({function_iri, RDF.type(), Structure.Function})
        |> Graph.add({function_iri, Structure.belongsTo(), module_iri})
        |> Graph.add({function_iri, Core.hasSourceLocation(), location_iri})
        # OTP triples
        |> Graph.add({genserver_iri, RDF.type(), OTP.GenServer})
        # Evolution triples
        |> Graph.add({repo_iri, RDF.type(), Evolution.Repository})
        |> Graph.add({commit_iri, RDF.type(), Evolution.Commit})
        |> Graph.add({commit_iri, Evolution.inRepository(), repo_iri})

      # Save and reload
      file_path = Path.join(tmp_dir, "full_graph.ttl")
      :ok = Graph.save(graph, file_path)
      {:ok, loaded} = Graph.load(file_path)

      # Verify all layers present
      subjects = Graph.subjects(loaded)
      assert MapSet.member?(subjects, file_iri)
      assert MapSet.member?(subjects, module_iri)
      assert MapSet.member?(subjects, genserver_iri)
      assert MapSet.member?(subjects, repo_iri)
    end
  end

  # ============================================================================
  # Namespace Resolution Tests
  # ============================================================================

  describe "namespace resolution in serialized output" do
    test "prefix_map includes all ontology namespaces" do
      prefixes = NS.prefix_map()

      # Verify Elixir ontology prefixes
      assert Keyword.has_key?(prefixes, :core)
      assert Keyword.has_key?(prefixes, :struct)
      assert Keyword.has_key?(prefixes, :otp)
      assert Keyword.has_key?(prefixes, :evo)

      # Verify standard prefixes
      assert Keyword.has_key?(prefixes, :rdf)
      assert Keyword.has_key?(prefixes, :rdfs)
      assert Keyword.has_key?(prefixes, :owl)
      assert Keyword.has_key?(prefixes, :xsd)
    end

    test "serialized turtle contains prefix declarations" do
      base_iri = "https://example.org/ns#"
      module_iri = IRI.for_module(base_iri, "TestMod")

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})

      {:ok, turtle} = Graph.to_turtle(graph)

      # Should contain struct prefix (for Structure.Module)
      assert turtle =~ ~r/@prefix\s+struct:/

      # Should contain the type declaration
      assert turtle =~ "struct:Module"
    end

    test "all namespace terms resolve to valid IRIs" do
      # Test that namespace terms create valid RDF resources
      assert RDF.IRI.valid?(Structure.Module)
      assert RDF.IRI.valid?(Structure.Function)
      assert RDF.IRI.valid?(Core.SourceFile)
      assert RDF.IRI.valid?(OTP.GenServer)
      assert RDF.IRI.valid?(Evolution.Commit)

      # Verify they resolve to the expected base IRIs (need RDF.iri to convert)
      assert RDF.iri(Structure.Module) |> to_string() |> String.starts_with?("https://w3id.org/elixir-code/structure#")
      assert RDF.iri(Core.SourceFile) |> to_string() |> String.starts_with?("https://w3id.org/elixir-code/core#")
      assert RDF.iri(OTP.GenServer) |> to_string() |> String.starts_with?("https://w3id.org/elixir-code/otp#")
      assert RDF.iri(Evolution.Commit) |> to_string() |> String.starts_with?("https://w3id.org/elixir-code/evolution#")
    end

    test "properties resolve correctly in triples" do
      base_iri = "https://example.org/prop#"
      module_iri = IRI.for_module(base_iri, "PropTest")
      function_iri = IRI.for_function(base_iri, "PropTest", "test_fn", 0)

      graph =
        Graph.new()
        |> Graph.add({function_iri, Structure.belongsTo(), module_iri})
        |> Graph.add({function_iri, Structure.arity(), 0})
        |> Graph.add({function_iri, Structure.functionName(), "test_fn"})

      {:ok, turtle} = Graph.to_turtle(graph)

      # Properties should be serialized with prefix
      assert turtle =~ "struct:belongsTo"
      assert turtle =~ "struct:arity"
      assert turtle =~ "struct:functionName"
    end
  end

  # ============================================================================
  # IRI Integration Tests
  # ============================================================================

  describe "IRI generation integrates with graph operations" do
    test "generated module IRI works in graph queries" do
      base_iri = "https://example.org/iri#"
      module_iri = IRI.for_module(base_iri, "MyApp.Query")

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Structure.moduleName(), "MyApp.Query"})

      # Should be findable as a subject
      assert MapSet.member?(Graph.subjects(graph), module_iri)

      # Should be describable
      desc = Graph.describe(graph, module_iri)
      refute RDF.Description.empty?(desc)
    end

    test "generated function IRI with special characters works" do
      base_iri = "https://example.org/special#"
      function_iri = IRI.for_function(base_iri, "MyApp", "valid?", 1)

      graph =
        Graph.new()
        |> Graph.add({function_iri, RDF.type(), Structure.Function})
        |> Graph.add({function_iri, Structure.functionName(), "valid?"})

      # IRI should be valid and work in graph
      assert RDF.IRI.valid?(function_iri)
      assert MapSet.member?(Graph.subjects(graph), function_iri)

      # Should round-trip through parse
      {:ok, parsed} = IRI.function_from_iri(function_iri)
      assert parsed == {"MyApp", "valid?", 1}
    end

    test "nested IRI hierarchy works correctly" do
      base_iri = "https://example.org/nested#"

      # Build hierarchy: module → function → clause → parameter
      module_iri = IRI.for_module(base_iri, "Nested.Test")
      function_iri = IRI.for_function(base_iri, "Nested.Test", "process", 2)
      clause_iri = IRI.for_clause(function_iri, 0)
      param_iri = IRI.for_parameter(clause_iri, 0)

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({function_iri, RDF.type(), Structure.Function})
        |> Graph.add({function_iri, Structure.belongsTo(), module_iri})
        |> Graph.add({clause_iri, RDF.type(), Structure.FunctionClause})
        |> Graph.add({function_iri, Structure.hasClause(), clause_iri})
        |> Graph.add({param_iri, RDF.type(), Structure.Parameter})

      # All should be present (module, function, clause, param)
      subjects = Graph.subjects(graph)
      assert MapSet.size(subjects) == 4

      # Verify relationships via describe
      func_desc = Graph.describe(graph, function_iri)
      assert RDF.Description.include?(func_desc, {Structure.belongsTo(), module_iri})
      assert RDF.Description.include?(func_desc, {Structure.hasClause(), clause_iri})
    end

    test "file and location IRIs work in graph" do
      base_iri = "https://example.org/file#"
      file_iri = IRI.for_source_file(base_iri, "lib/my_app/users.ex")
      location_iri = IRI.for_source_location(file_iri, 10, 25)

      graph =
        Graph.new()
        |> Graph.add({file_iri, RDF.type(), Core.SourceFile})
        |> Graph.add({file_iri, Core.filePath(), "lib/my_app/users.ex"})
        |> Graph.add({location_iri, RDF.type(), Core.SourceLocation})
        |> Graph.add({location_iri, Core.inSourceFile(), file_iri})
        |> Graph.add({location_iri, Core.startLine(), 10})
        |> Graph.add({location_iri, Core.endLine(), 25})

      # Verify file
      file_desc = Graph.describe(graph, file_iri)
      assert RDF.Description.include?(file_desc, {RDF.type(), Core.SourceFile})

      # Verify location references file
      loc_desc = Graph.describe(graph, location_iri)
      assert RDF.Description.include?(loc_desc, {Core.inSourceFile(), file_iri})
    end

    test "repository and commit IRIs maintain stable hashes" do
      base_iri = "https://example.org/repo#"
      repo_url = "https://github.com/elixir-lang/elixir"

      # Generate twice - should be identical
      repo_iri_1 = IRI.for_repository(base_iri, repo_url)
      repo_iri_2 = IRI.for_repository(base_iri, repo_url)

      assert repo_iri_1 == repo_iri_2

      # Commit IRIs from same repo should share prefix
      commit_1 = IRI.for_commit(repo_iri_1, "abc123")
      commit_2 = IRI.for_commit(repo_iri_1, "def456")

      assert to_string(commit_1) |> String.contains?(to_string(repo_iri_1))
      assert to_string(commit_2) |> String.contains?(to_string(repo_iri_1))

      # Use in graph
      graph =
        Graph.new()
        |> Graph.add({repo_iri_1, RDF.type(), Evolution.Repository})
        |> Graph.add({commit_1, RDF.type(), Evolution.Commit})
        |> Graph.add({commit_1, Evolution.inRepository(), repo_iri_1})

      subjects = Graph.subjects(graph)
      assert MapSet.member?(subjects, repo_iri_1)
      assert MapSet.member?(subjects, commit_1)
    end
  end

  # ============================================================================
  # Configuration Flow Tests
  # ============================================================================

  describe "configuration flows through all components" do
    test "Config.new creates valid configuration for graph operations" do
      config = Config.new(base_iri: "https://myproject.org/code#")

      # Use config base_iri for IRI generation
      module_iri = IRI.for_module(config.base_iri, "MyProject.Main")

      # Create graph with same base
      graph =
        Graph.new(base_iri: config.base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})

      # IRI should match graph base
      assert to_string(module_iri) |> String.starts_with?(config.base_iri)

      # Verify graph contains the module
      assert MapSet.member?(Graph.subjects(graph), module_iri)
    end

    test "Config defaults work with all modules" do
      config = Config.default()

      # Default base_iri should work
      module_iri = IRI.for_module(config.base_iri, "DefaultModule")
      assert RDF.IRI.valid?(module_iri)

      # Should work in graph
      graph = Graph.new(base_iri: config.base_iri)
      graph = Graph.add(graph, {module_iri, RDF.type(), Structure.Module})

      refute Graph.empty?(graph)
    end

    test "Config merge preserves base_iri through workflow" do
      base_config = Config.default()
      custom_config = Config.merge(base_config, base_iri: "https://custom.org/")

      assert custom_config.base_iri == "https://custom.org/"

      # Generate IRIs with custom base
      module_iri = IRI.for_module(custom_config.base_iri, "Custom.Module")
      assert to_string(module_iri) |> String.starts_with?("https://custom.org/")

      # Use in graph
      graph = Graph.new(base_iri: custom_config.base_iri)
      graph = Graph.add(graph, {module_iri, RDF.type(), Structure.Module})

      {:ok, turtle} = Graph.to_turtle(graph)
      assert turtle =~ "https://custom.org/"
    end

    test "Config validation catches invalid configurations early" do
      # Empty base_iri should fail validation
      invalid_config = %Config{base_iri: "", output_format: :turtle}
      {:error, reasons} = Config.validate(invalid_config)

      assert "base_iri must be a non-empty string" in reasons
    end

    @tag :tmp_dir
    test "output_format config affects serialization", %{tmp_dir: tmp_dir} do
      config = Config.new(base_iri: "https://format.test/", output_format: :turtle)

      module_iri = IRI.for_module(config.base_iri, "FormatTest")

      graph =
        Graph.new(base_iri: config.base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})

      # Save with format from config
      file_path = Path.join(tmp_dir, "format_test.ttl")
      :ok = Graph.save(graph, file_path, format: config.output_format)

      # Verify file was created and is valid Turtle
      assert File.exists?(file_path)
      {:ok, loaded} = Graph.load(file_path)
      assert Graph.statement_count(loaded) == Graph.statement_count(graph)
    end
  end

  # ============================================================================
  # Graph Merge Integration Tests
  # ============================================================================

  describe "graph merge operations" do
    test "merging graphs from different modules preserves all data" do
      base_iri = "https://example.org/merge#"

      # Graph 1: Module definitions
      module_iri = IRI.for_module(base_iri, "Merge.Test")

      graph1 =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Structure.moduleName(), "Merge.Test"})

      # Graph 2: Function definitions
      function_iri = IRI.for_function(base_iri, "Merge.Test", "run", 0)

      graph2 =
        Graph.new(base_iri: base_iri)
        |> Graph.add({function_iri, RDF.type(), Structure.Function})
        |> Graph.add({function_iri, Structure.belongsTo(), module_iri})

      # Merge
      merged = Graph.merge(graph1, graph2)

      # Both module and function should be present
      subjects = Graph.subjects(merged)
      assert MapSet.member?(subjects, module_iri)
      assert MapSet.member?(subjects, function_iri)

      # Relationship should be intact
      func_desc = Graph.describe(merged, function_iri)
      assert RDF.Description.include?(func_desc, {Structure.belongsTo(), module_iri})
    end

    @tag :tmp_dir
    test "merged graph round-trips correctly", %{tmp_dir: tmp_dir} do
      base_iri = "https://example.org/merge-rt/"

      # Create two separate graphs
      mod1_iri = IRI.for_module(base_iri, "Module1")
      mod2_iri = IRI.for_module(base_iri, "Module2")

      graph1 =
        Graph.new(base_iri: base_iri)
        |> Graph.add({mod1_iri, RDF.type(), Structure.Module})

      graph2 =
        Graph.new(base_iri: base_iri)
        |> Graph.add({mod2_iri, RDF.type(), Structure.Module})

      # Merge and save
      merged = Graph.merge(graph1, graph2)
      file_path = Path.join(tmp_dir, "merged.ttl")
      :ok = Graph.save(merged, file_path)

      # Load and verify
      {:ok, loaded} = Graph.load(file_path)

      subjects = Graph.subjects(loaded)
      assert MapSet.member?(subjects, mod1_iri)
      assert MapSet.member?(subjects, mod2_iri)
    end
  end

  # ============================================================================
  # SPARQL Integration Tests (when available)
  # ============================================================================

  describe "SPARQL query integration" do
    test "query with namespace prefixes returns results" do
      base_iri = "https://example.org/sparql#"
      module_iri = IRI.for_module(base_iri, "SparqlTest")

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Structure.moduleName(), "SparqlTest"})

      # Query using struct prefix (should be injected automatically)
      query = """
      SELECT ?module ?name
      WHERE {
        ?module a struct:Module .
        ?module struct:moduleName ?name .
      }
      """

      {:ok, result} = Graph.query(graph, query)

      # Should find our module
      assert length(result.results) == 1
      [row] = result.results
      assert row["module"] == module_iri
      assert to_string(row["name"]) == "SparqlTest"
    end

    test "query across multiple ontology layers" do
      base_iri = "https://example.org/multi-sparql#"

      module_iri = IRI.for_module(base_iri, "MultiQuery")
      file_iri = IRI.for_source_file(base_iri, "lib/multi.ex")
      location_iri = IRI.for_source_location(file_iri, 1, 10)

      graph =
        Graph.new(base_iri: base_iri)
        |> Graph.add({module_iri, RDF.type(), Structure.Module})
        |> Graph.add({module_iri, Core.hasSourceLocation(), location_iri})
        |> Graph.add({location_iri, RDF.type(), Core.SourceLocation})
        |> Graph.add({location_iri, Core.inSourceFile(), file_iri})
        |> Graph.add({file_iri, RDF.type(), Core.SourceFile})

      # Query combining struct and core namespaces
      query = """
      SELECT ?module ?file
      WHERE {
        ?module a struct:Module .
        ?module core:hasSourceLocation ?loc .
        ?loc core:inSourceFile ?file .
      }
      """

      {:ok, result} = Graph.query(graph, query)

      assert length(result.results) == 1
      [row] = result.results
      assert row["module"] == module_iri
      assert row["file"] == file_iri
    end
  end
end
