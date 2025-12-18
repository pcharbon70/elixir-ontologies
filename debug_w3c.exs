# Debug W3C test parsing and validation

alias ElixirOntologies.SHACL
alias ElixirOntologies.SHACL.W3CTestRunner

# Test a simple case
test_file = "test/fixtures/w3c/core/property-datatype-001.ttl"

IO.puts "=== Parsing test file: #{test_file} ==="
{:ok, test_case} = W3CTestRunner.parse_test_file(test_file)

IO.puts "Test label: #{test_case.label}"
IO.puts "Expected conforms: #{test_case.expected_conforms}"
IO.puts "Expected result count: #{test_case.expected_result_count}"
IO.puts ""

IO.puts "=== Data graph triples (first 20) ==="
test_case.data_graph
|> RDF.Graph.triples()
|> Enum.take(20)
|> Enum.each(fn {s, p, o} ->
  IO.puts "  #{inspect(s)} #{inspect(p)} #{inspect(o)}"
end)

IO.puts ""
IO.puts "=== Looking for NodeShapes ==="
test_case.shapes_graph
|> RDF.Graph.triples()
|> Enum.filter(fn {_s, p, o} ->
  p == RDF.type() && o == RDF.iri("http://www.w3.org/ns/shacl#NodeShape")
end)
|> Enum.each(fn {s, _p, _o} ->
  IO.puts "  Found NodeShape: #{inspect(s)}"
end)

IO.puts ""
IO.puts "=== Running validation ==="
{:ok, report} = SHACL.validate(test_case.data_graph, test_case.shapes_graph)

IO.puts "Conforms: #{report.conforms?}"
IO.puts "Results count: #{length(report.results)}"
IO.puts ""

if length(report.results) > 0 do
  IO.puts "=== Validation Results ==="
  Enum.each(report.results, fn result ->
    IO.puts "  Focus: #{inspect(result.focus_node)}"
    IO.puts "  Path: #{inspect(result.path)}"
    IO.puts "  Message: #{result.message}"
    IO.puts ""
  end)
end
