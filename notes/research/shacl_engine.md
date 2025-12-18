You've set this up really nicely already: you've got Elixir ontologies, a SHACL shapes file, and RDF tooling; what's missing is the SHACL engine in the middle.

Below is a concrete design + implementation plan for a **pure Elixir SHACL reader / validator / writer** that fits your elixir-ontologies repo and builds on RDF.ex / SPARQL.ex.

I'll anchor it to your actual shapes file (elixir-shapes.ttl) so this stays practical, not abstract. [GitHub+1](https://github.com/pcharbon70/elixir-ontologies/raw/main/elixir-shapes.ttl)

**1\. Grounding: what you actually need to support**

From elixir-shapes.ttl, we can enumerate the SHACL features you _actually_ use:

**Node shapes:**

- sh:NodeShape
- sh:targetClass (e.g. struct:Module, struct:Function, otp:Supervisor, evo:Commit, etc.)

**Property constraints:**

- Cardinality: sh:minCount, sh:maxCount
- Type constraints: sh:datatype, sh:class
- String constraints: sh:pattern, sh:minLength
- Value constraints:
  - sh:in (lists of IRIs, e.g. allowed OTP strategies, restart types)
  - sh:hasValue
- Qualified constraints:
  - sh:qualifiedValueShape \[ sh:class … \]
  - sh:qualifiedMinCount

**Advanced constraints:**

- sh:sparql constraints with sh:select:
  - SourceLocationShape: endLine >= startLine
  - FunctionArityMatchShape: arity = parameter count
  - ProtocolComplianceShape: implementation covers all protocol functions [GitHub](https://github.com/pcharbon70/elixir-ontologies/raw/main/elixir-shapes.ttl)

So a first-pass SHACL engine needs:

- **Core SHACL** constraints used here (SHACL Core / 1.0 & 1.2 overlap). [W3C+1](https://www.w3.org/TR/shacl/?utm_source=chatgpt.com)
- Optional **SHACL-SPARQL** support for the sh:sparql bits (advanced features). [W3C](https://w3c.github.io/data-shapes/shacl-af/?utm_source=chatgpt.com)

You _don't_ currently use more exotic stuff (e.g. sh:or, sh:and, sh:not, sh:node, sh:propertyShape reuse, etc.) - that lets you aggressively scope v1.

**2\. Building blocks in the Elixir ecosystem**

You can lean heavily on the existing RDF stack:

- **RDF.ex** for RDF graphs, IRIs, literals, and Turtle serialization. [GitHub+2Hexdocs+2](https://github.com/rdf-elixir/rdf-ex?utm_source=chatgpt.com)
- **RDF.Turtle** to read/write your .ttl files (already gives you in-memory graphs). [Hexdocs](https://hexdocs.pm/rdf/RDF.Turtle.html)
- **SPARQL.ex** for evaluating the sh:sparql constraints in-memory once you're ready for that. [Medium+1](https://medium.com/%40tonyhammond/querying-rdf-with-elixir-2378b39d65cc?utm_source=chatgpt.com)
- **ShEx.ex** as a _design reference_ for how to structure a constraint engine in Elixir (similar problem domain, different spec). It already does parallel validation over RDF graphs. [GitHub](https://github.com/rdf-elixir/shex-ex)

There is **no SHACL implementation** listed in the RDF-on-Elixir ecosystem yet (only ShEx.ex, JSON-LD.ex, etc.), so this would be filling a genuine gap. [RDF on Elixir](https://rdf-elixir.dev/links.html)

For semantics, the source of truth is:

- **SHACL 1.2 Core spec** (November 2025) [W3C](https://www.w3.org/TR/shacl12-core/?utm_source=chatgpt.com)
- **SHACL test suite + implementation report** for interoperability tests [W3C](https://w3c.github.io/data-shapes/data-shapes-test-suite/?utm_source=chatgpt.com)
- Existing fully-featured validators:
  - **pySHACL** (pure Python) [PyPI+2Anaconda+2](https://pypi.org/project/pyshacl/?utm_source=chatgpt.com)
  - **TopBraid SHACL API** for Jena (Java) [GitHub](https://github.com/TopQuadrant/shacl?utm_source=chatgpt.com)

Those two are good references for nuanced edge cases.

**3\. Overall architecture for your SHACL engine**

I'd treat this as a small, generic library living _inside_ elixir-ontologies at first, but designed to be extractable as shacl_ex later.

**High-level modules**

Something along these lines:

\# Top-level API

defmodule ElixirOntologies.SHACL do

alias ElixirOntologies.SHACL.{Reader, Validator, Writer}

alias RDF.Graph

@spec validate(Graph.t(), Graph.t(), keyword()) ::

{:ok, %Validator.Report{}} | {:error, term()}

def validate(data_graph, shapes_graph, opts \\\\ \[\]) do

with {:ok, shapes} <- Reader.parse_shapes(shapes_graph, opts),

{:ok, report} <- Validator.run(data_graph, shapes, opts) do

{:ok, report}

end

end

end

Submodules:

- SHACL.Reader - turn the shapes graph (RDF) into internal structs.
- SHACL.Model - structs for node shapes, property shapes, constraints.
- SHACL.Validator - run validation, return report struct.
- SHACL.Writer - emit a SHACL validation report as RDF/Turtle or maps.

**4\. Data model (internal structs)**

Keep it close to the spec but trimmed to what you actually use.

defmodule ElixirOntologies.SHACL.NodeShape do

@enforce_keys \[:id\]

defstruct \[

:id,

target_classes: \[\], # \[RDF.IRI.t\]

property_shapes: \[\], # \[%PropertyShape{}\]

sparql_constraints: \[\] # \[%SPARQLConstraint{}\]

\]

end

defmodule ElixirOntologies.SHACL.PropertyShape do

@enforce_keys \[:id, :path\]

defstruct \[

:id,

:path, # RDF.IRI.t

:message, # string | nil

\# Cardinality

min_count: nil, # non_neg_integer | nil

max_count: nil, # non_neg_integer | nil

\# Datatype / class

datatype: nil, # RDF.IRI.t | nil

class: nil, # RDF.IRI.t | nil

\# String constraints

pattern: nil, # Regex.t | nil

min_length: nil, # non_neg_integer | nil

\# Value constraints

in: \[\], # \[RDF.term\]

has_value: nil, # RDF.term | nil

\# Qualified

qualified_class: nil, # RDF.IRI.t | nil (simplified for your shapes)

qualified_min_count: nil # non_neg_integer | nil

\]

end

defmodule ElixirOntologies.SHACL.SPARQLConstraint do

defstruct \[

:source_shape_id,

:message,

:select_query, # raw SPARQL with \$this placeholder

:prefixes_graph # optional RDF.Graph of prefixes

\]

end

defmodule ElixirOntologies.SHACL.ValidationResult do

defstruct \[

:focus_node, # RDF.term

:path, # RDF.IRI.t | nil

:source_shape, # RDF.IRI.t

:severity, # :violation | :warning | :info

:message, # string

:details # map() for additional info

\]

end

defmodule ElixirOntologies.SHACL.ValidationReport do

defstruct \[

conforms?: true,

results: \[\] # \[%ValidationResult{}\]

\]

end

You can keep severity simple (default everything to sh:Violation unless you later start using custom severities).

**5\. Reader: parsing elixir-shapes.ttl into structs**

You already have the shapes TTL; reading it is trivial with RDF.ex:

{:ok, shapes_graph} = RDF.Turtle.read_file("elixir-shapes.ttl")

Reader.parse_shapes/2 would:

- **Find all node shapes**
  - Every subject ?shape with triple ?shape rdf:type sh:NodeShape.
  - Collect sh:targetClass values.
  - Collect sh:property blank nodes and parse them as property shapes.
  - Collect sh:sparql blank nodes and parse as SPARQLConstraint.
- **Parse property shapes**

For each property blank node ?ps:

- - sh:path → path (assume only simple IRIs, no complex paths v1).
    - sh:minCount, sh:maxCount → min_count, max_count.
    - sh:datatype → datatype.
    - sh:class → class.
    - sh:pattern → compile to Elixir Regex (you can store the original string too).
    - sh:minLength → min_length.
    - sh:in list → in (extract RDF list into list of terms).
    - sh:hasValue → has_value.
    - sh:qualifiedValueShape \[ sh:class X \] + sh:qualifiedMinCount N  
        → qualified_class = X, qualified_min_count = N.

Using RDF.ex, you can pivot around descriptions:

desc = RDF.Graph.description(shapes_graph, ps_node)

path = desc\[SH.path\] |> only_object()

min_count = desc\[SH.minCount\] |> int_or_nil()

\# etc…

- **Parse SPARQL constraints (SHACL-SPARQL)**

For each sh:sparql blank node:

- - sh:message → message.
    - sh:select → SPARQL SELECT string (with \$this).
    - sh:prefixes → optional graph or prefix declarations (you can initially ignore and use the prefixes from the shapes graph).

You'll store those in %SPARQLConstraint{} on the node shape.

Because elixir-shapes.ttl is relatively small and flat, a straightforward graph-walking implementation will be fine.

**6\. Validator: core algorithm**

The validator workflow (SHACL Core) is:

- For each **node shape** S
- Determine its **target nodes** in the data graph
  - For each C in sh:targetClass, select all nodes having rdf:type C.
- For each **focus node** n in those targets:
  - Apply each **property shape** P in S.
  - Apply each **SPARQL constraint** in S (if enabled).
- Aggregate all ValidationResults into a ValidationReport.

In Elixir-ish pseudocode:

defmodule ElixirOntologies.SHACL.Validator do

alias ElixirOntologies.SHACL.{ValidationReport, ValidationResult}

def run(data_graph, node_shapes, opts \\\\ \[\]) do

results =

node_shapes

|> Task.async_stream(fn shape ->

validate_node_shape(data_graph, shape, opts)

end, timeout: :infinity)

|> Enum.flat_map(fn {:ok, res} -> res end)

{:ok, %ValidationReport{

conforms?: results == \[\],

results: results

}}

end

defp validate_node_shape(data_graph, shape, opts) do

targets = target_nodes(data_graph, shape)

targets

|> Task.async_stream(fn node ->

validate_focus_node(data_graph, shape, node, opts)

end, timeout: :infinity)

|> Enum.flat_map(fn {:ok, res} -> res end)

end

end

Parallelism follows the pattern used by ShEx.ex for "larger amounts of nodes". [GitHub](https://github.com/rdf-elixir/shex-ex)

**6.1 Evaluating property shapes**

For each property shape P and focus node n:

Let values = set of o such that (n, P.path, o) is in data_graph.

Then:

- **minCount / maxCount**
- count = Enum.count(values)
- if p.min_count && count < p.min_count do
- violation("Too few values for path …")
- end
- if p.max_count && count > p.max_count do
- violation("Too many values for path …")
- end
- **datatype**

For each literal v in values, check v.datatype against p.datatype.

With RDF.ex, you can match on RDF.Literal and look at datatype.

- **class**

For each resource v in values, ensure (v, rdf:type, p.class) exists in the data graph (you can decide whether to use raw explicit types only or add reasoning later).

- **pattern**

Applicable only to literals; get the lexical string (RDF.Literal.value/1) and run Regex.match?(p.pattern, value).

- **minLength**

Similar: String.length(value) >= min_length.

- **in**

Check that each v is equal (as RDF term) to one of the allowed terms in p.in.

- **hasValue**

Ensure the specific term is present in values.

- **qualifiedValueShape (simplified)**

In your shapes, sh:qualifiedValueShape always just constrains sh:class of the values (e.g. otp:InitCallback). So:

qualified_values =

values

|> Enum.filter(&has_type?(data_graph, &1, p.qualified_class))

if p.qualified_min_count && length(qualified_values) < p.qualified_min_count do

violation("Expected at least #{p.qualified_min_count} values of class #{…}")

end

That covers all property-level constraints actually used in elixir-shapes.ttl.

**6.2 SPARQL constraints (phase 2)**

For each SPARQLConstraint and focus node n:

- Replace \$this in the sh:select query with the Turtle of the focus node (e.g. &lt;IRI&gt; or \_:b123).
- Run the resulting SELECT query against data_graph using SPARQL.ex.
- If the result set is non-empty, generate a ValidationResult per row (or one aggregated result).

Pseudo:

defp eval_sparql_constraint(data_graph, %SPARQLConstraint{} = c, focus_node) do

query =

c.select_query

|> String.replace("\$this", to_sparql_term(focus_node))

case SPARQL.execute_query(data_graph, query) do

{:ok, %SPARQL.Result{results: \[\]}} ->

\[\]

{:ok, %SPARQL.Result{results: rows}} ->

\[%ValidationResult{

focus_node: focus_node,

path: nil,

source_shape: c.source_shape_id,

severity: :violation,

message: c.message,

details: %{rows: rows}

}\]

{:error, reason} ->

\# You might want to raise or treat this as a separate error

raise "SPARQL constraint execution failed: #{inspect(reason)}"

end

end

You can _ship v1 without SPARQL_, mark those as "not evaluated yet", then enable SPARQL once the core is solid.

**7\. Writer: SHACL Validation Report in RDF/Turtle**

The spec defines a sh:ValidationReport graph with sh:result entries, each a sh:ValidationResult node containing:

- sh:focusNode
- sh:resultPath
- sh:sourceShape
- sh:resultSeverity
- sh:resultMessage
- sh:detail / custom things [W3C+1](https://www.w3.org/TR/shacl/?utm_source=chatgpt.com)

You can map %ValidationReport{} to an RDF.Graph:

defmodule ElixirOntologies.SHACL.Writer do

alias ElixirOntologies.SHACL.ValidationReport

alias RDF.{Graph, Description, IRI, Literal}

@sh "<http://www.w3.org/ns/shacl#>"

def to_graph(%ValidationReport{conforms?: conforms, results: results}) do

report_iri = IRI.new("\_:report") # or generate a proper blank node

base_graph =

Graph.new()

|> Graph.add({report_iri, IRI.new(@sh <> "conforms"), Literal.new(conforms)})

Enum.reduce(results, base_graph, fn res, g ->

add_result(g, report_iri, res)

end)

end

def to_turtle(report) do

report

|> to_graph()

|> RDF.Turtle.write_string!()

end

end

In add_result/3 you create a blank node per result and attach SHACL properties.

That gives you:

- mix function to return %ValidationReport{}
- Optional --report-ttl CLI mode (CI-friendly) to dump the full SHACL report as Turtle.

**8\. Testing strategy**

You want to be _very_ conservative here - SHACL is subtle.

**8.1 Unit tests for each constraint type**

For each constraint type (minCount, datatype, pattern, sh:in, etc.):

- Minimal shapes graph with one NodeShape, one PropertyShape.
- Small data graphs that:
  - Conform
  - Fail for exactly one reason

Each test asserts both conforms? and the shape/ path / message in the ValidationResult.

**8.2 W3C SHACL test suite (subset)**

The W3C SHACL test suite defines a standard format for validating implementations and provides many cases. [W3C](https://w3c.github.io/data-shapes/data-shapes-test-suite/?utm_source=chatgpt.com)

You can:

- Import a subset of **core** tests matching the features you implement.
- Have a small script that:
  - Loads the data graph and shapes graph.
  - Runs ElixirOntologies.SHACL.validate/3.
  - Compares your conforms? against the expected result in the manifest.

This is how pySHACL & others prove compliance. [PyPI+1](https://pypi.org/project/pyshacl/?utm_source=chatgpt.com)

**8.3 Domain-specific tests**

Check your actual use-cases, e.g.:

- A small Elixir code sample (module + function + macro) → extracted TTL → validation should pass.
- Intentionally broken examples:
  - Function with arity mismatch vs parameter count.
  - OTP supervisor with invalid strategy.
  - Commit with malformed SHA.

These exercise your elixir-shapes.ttl specifically. [GitHub+1](https://github.com/pcharbon70/elixir-ontologies/raw/main/elixir-shapes.ttl)

**9\. Integration into your "read codebase → TTL → validate" pipeline**

Given elixir-ontologies already defines the ontologies and shapes and you have / will have a _code extractor_ that emits individuals as Turtle, a typical flow could be:

{:ok, data_graph} = RDF.Turtle.read_file("codebase.ttl")

{:ok, shapes_graph} = RDF.Turtle.read_file("elixir-shapes.ttl")

{:ok, report} = ElixirOntologies.SHACL.validate(data_graph, shapes_graph)

if report.conforms? do

IO.puts("✅ Elixir ontology graph is SHACL-conformant.")

else

IO.puts("❌ SHACL validation failed.")

IO.puts(ElixirOntologies.SHACL.Writer.to_turtle(report))

System.halt(1)

end

You can then:

- Wrap that in a mix task, e.g. mix elixir_ontologies.validate ttl_path.
- Wire it into CI to reject PRs that produce invalid individuals.

**10\. Suggested implementation phases**

To keep it manageable:

**Phase 0 - Skeleton & plumbing**

- Add ElixirOntologies.SHACL namespace and module skeletons.
- Implement reading TTL graphs with RDF.Turtle.
- Implement empty validator that just returns conforms?: true.

**Phase 1 - Core property constraints**

Implement and unit-test, in this order:

- sh:targetClass → targeting
- sh:minCount / sh:maxCount
- sh:datatype
- sh:class
- sh:pattern / sh:minLength
- sh:in, sh:hasValue
- sh:qualifiedValueShape + sh:qualifiedMinCount (class-only version)

At the end of Phase 1, almost all constraints in elixir-shapes.ttl are covered except the SPARQL ones.

**Phase 2 - SHACL Validation Report writer**

- Implement %ValidationReport{} → SHACL sh:ValidationReport graph + Turtle serialization.

**Phase 3 - SPARQL constraints**

- Integrate SPARQL.ex.
- Implement sh:sparql execution for:
  - SourceLocation endLine >= startLine
  - Function arity vs parameter count
  - Protocol implementation coverage

**Phase 4 - W3C test suite + hardening**

- Wire a subset of W3C SHACL tests.
- Add regression tests based on real Elixir projects.
