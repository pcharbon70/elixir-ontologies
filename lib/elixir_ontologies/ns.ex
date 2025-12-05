defmodule ElixirOntologies.NS do
  @moduledoc """
  RDF namespace definitions for the Elixir Ontologies.

  This module provides vocabulary namespaces for building RDF statements using RDF.ex.
  Each namespace corresponds to one of the ontology layers:

  - `Core` - Base AST primitives (https://w3id.org/elixir-code/core#)
  - `Structure` - Elixir-specific constructs (https://w3id.org/elixir-code/structure#)
  - `OTP` - OTP runtime patterns (https://w3id.org/elixir-code/otp#)
  - `Evolution` - Temporal/provenance (https://w3id.org/elixir-code/evolution#)

  ## Usage

      alias ElixirOntologies.NS.{Core, Structure, OTP, Evolution}

      # Build RDF triples using namespace terms
      RDF.Graph.new()
      |> RDF.Graph.add({my_module_iri, RDF.type(), Structure.Module})
      |> RDF.Graph.add({my_module_iri, Structure.moduleName(), "MyApp.Users"})

  ## Standard Namespaces

  Common RDF namespaces are re-exported for convenience:

  - `RDF` - RDF vocabulary
  - `RDFS` - RDF Schema
  - `OWL` - Web Ontology Language
  - `XSD` - XML Schema datatypes
  - `SKOS` - Simple Knowledge Organization System
  - `PROV` - W3C Provenance Ontology

  ## Prefix Map

  Use `prefix_map/0` to get a complete mapping of prefixes for serialization:

      graph
      |> RDF.Turtle.write_string!(prefixes: ElixirOntologies.NS.prefix_map())
  """

  use RDF.Vocabulary.Namespace

  # ============================================================================
  # Elixir Ontology Namespaces
  # ============================================================================

  # Core ontology namespace for AST primitives.
  # Base IRI: https://w3id.org/elixir-code/core#
  #
  # Provides classes for:
  # - Code elements (CodeElement, SourceLocation, SourceFile, Repository, CommitRef)
  # - AST nodes (ASTNode, Expression, Statement, Declaration)
  # - Literal types (AtomLiteral, IntegerLiteral, StringLiteral, etc.)
  # - Operators (PipeOperator, MatchOperator, etc.)
  # - Control flow (IfExpression, CaseExpression, WithExpression, etc.)
  # - Pattern matching (Pattern, Guard, GuardClause)
  # - Blocks and scopes (Block, DoBlock, Scope, Closure)
  defvocab(Core,
    base_iri: "https://w3id.org/elixir-code/core#",
    file: "priv/ontologies/elixir-core.ttl",
    case_violations: :ignore
  )

  # Structure ontology namespace for Elixir-specific constructs.
  # Base IRI: https://w3id.org/elixir-code/structure#
  #
  # Provides classes for:
  # - Modules (Module, NestedModule, ModuleAlias, Import, Require, Use)
  # - Module attributes (ModuleAttribute, DocAttribute, TypeSpec)
  # - Functions (Function, PublicFunction, PrivateFunction, FunctionClause, Parameter)
  # - Protocols (Protocol, ProtocolImplementation)
  # - Behaviours (Behaviour, CallbackFunction)
  # - Structs and exceptions (Struct, StructField, Exception)
  # - Macros (Macro, QuotedExpression, UnquoteExpression)
  # - Type system (TypeExpression, UnionType, FunctionType)
  defvocab(Structure,
    base_iri: "https://w3id.org/elixir-code/structure#",
    file: "priv/ontologies/elixir-structure.ttl",
    case_violations: :ignore
  )

  # OTP ontology namespace for runtime patterns.
  # Base IRI: https://w3id.org/elixir-code/otp#
  #
  # Provides classes for:
  # - Processes (Process, ProcessIdentity, PID, ProcessMailbox)
  # - OTP behaviours (GenServer, Supervisor, Agent, Task)
  # - Supervision (SupervisionTree, ChildSpec, SupervisionStrategy)
  # - GenServer callbacks and messages (GenServerCallback, Call, Cast, Info)
  # - Distributed Erlang (Node, Cluster)
  # - ETS/DETS (ETSTable, DETSTable)
  # - Telemetry (TelemetryEvent, TelemetryHandler)
  defvocab(OTP,
    base_iri: "https://w3id.org/elixir-code/otp#",
    file: "priv/ontologies/elixir-otp.ttl",
    case_violations: :ignore
  )

  # Evolution ontology namespace for temporal provenance.
  # Base IRI: https://w3id.org/elixir-code/evolution#
  #
  # Provides classes for:
  # - Code versions (CodeVersion, ModuleVersion, FunctionVersion, CodebaseSnapshot)
  # - Development activities (DevelopmentActivity, Commit, Refactoring, BugFix)
  # - Agents (Developer, Team, Bot, LLMAgent)
  # - Change tracking (ChangeSet, Addition, Modification, Removal)
  # - Version control (Repository, Branch, Tag, PullRequest)
  # - Semantic versioning (SemanticVersion, BreakingChange)
  # - Temporal modeling (TemporalExtent, ValidTime, TransactionTime)
  defvocab(Evolution,
    base_iri: "https://w3id.org/elixir-code/evolution#",
    file: "priv/ontologies/elixir-evolution.ttl",
    case_violations: :ignore
  )

  # ============================================================================
  # Additional Standard Namespaces
  # ============================================================================

  # W3C PROV-O namespace for provenance.
  # Base IRI: http://www.w3.org/ns/prov#
  defvocab(PROV,
    base_iri: "http://www.w3.org/ns/prov#",
    terms: ~w[
      Entity Activity Agent
      wasGeneratedBy used wasAttributedTo wasAssociatedWith
      wasInformedBy wasDerivedFrom wasRevisionOf wasQuotedFrom
      wasInvalidatedBy
      actedOnBehalfOf hadRole
      qualifiedAssociation qualifiedAttribution qualifiedDerivation
      startedAtTime endedAtTime generatedAtTime invalidatedAtTime
      atLocation
      Role
    ]a
  )

  # Basic Formal Ontology (BFO) namespace.
  # Base IRI: http://purl.obolibrary.org/obo/
  defvocab(BFO,
    base_iri: "http://purl.obolibrary.org/obo/",
    terms: ~w[
      BFO_0000001 BFO_0000002 BFO_0000003 BFO_0000004
      BFO_0000006 BFO_0000015 BFO_0000016 BFO_0000017
      BFO_0000019 BFO_0000020 BFO_0000023 BFO_0000024
      BFO_0000027 BFO_0000029 BFO_0000030 BFO_0000031
      BFO_0000034 BFO_0000035 BFO_0000038 BFO_0000040
    ]a
  )

  # Information Artifact Ontology (IAO) namespace.
  # Base IRI: http://purl.obolibrary.org/obo/IAO_
  # Note: IAO uses numeric identifiers which aren't valid Elixir identifiers,
  # so we use aliases with descriptive names.
  defvocab(IAO,
    base_iri: "http://purl.obolibrary.org/obo/IAO_",
    terms: [],
    alias: [
      information_content_entity: "0000030",
      textual_entity: "0000078",
      data_item: "0000104",
      definition: "0000115",
      editor_note: "0000116",
      term_editor: "0000117",
      editor_preferred_term: "0000118",
      definition_source: "0000119",
      metadata_complete: "0000120",
      metadata_incomplete: "0000121",
      ready_for_release: "0000122",
      curation_status: "0000129",
      ontology_module: "0000136",
      centrally_registered_identifier: "0000219",
      centrally_registered_identifier_symbol: "0000220",
      obsolescence_reason: "0000225",
      document: "0000310",
      image: "0000311",
      software: "0000400",
      denotator_type: "0000409",
      mass_measurement_datum: "0000414",
      documentation: "0000572",
      centrally_registered_identifier_scheme: "0000578",
      has_time_stamp: "0000582"
    ],
    strict: false
  )

  # Dublin Core Elements namespace.
  # Base IRI: http://purl.org/dc/elements/1.1/
  defvocab(DC,
    base_iri: "http://purl.org/dc/elements/1.1/",
    terms: ~w[
      title creator subject description publisher contributor
      date type format identifier source language relation
      coverage rights
    ]a
  )

  # Dublin Core Terms namespace.
  # Base IRI: http://purl.org/dc/terms/
  defvocab(DCTerms,
    base_iri: "http://purl.org/dc/terms/",
    terms: ~w[
      abstract accessRights accrualMethod accrualPeriodicity
      alternative audience available bibliographicCitation
      conformsTo contributor coverage created creator date
      dateAccepted dateCopyrighted dateSubmitted description
      educationLevel extent format hasFormat hasPart hasVersion
      identifier instructionalMethod isFormatOf isPartOf
      isReferencedBy isReplacedBy isRequiredBy issued isVersionOf
      language license mediator medium modified provenance
      publisher references relation replaces requires rights
      rightsHolder source spatial subject tableOfContents temporal
      title type valid
    ]a
  )

  # ============================================================================
  # Prefix Map
  # ============================================================================

  @doc """
  Returns a complete prefix map for RDF serialization.

  This map includes all Elixir ontology namespaces and commonly used
  standard namespaces. Use with RDF.ex serializers:

      graph
      |> RDF.Turtle.write_string!(prefixes: ElixirOntologies.NS.prefix_map())

  ## Included Prefixes

  Elixir Ontologies:
  - `core:` - Core AST primitives
  - `struct:` - Elixir-specific constructs
  - `otp:` - OTP runtime patterns
  - `evo:` - Evolution/provenance

  Standard:
  - `rdf:`, `rdfs:`, `owl:`, `xsd:`
  - `skos:`, `prov:`
  - `bfo:`, `iao:`
  - `dc:`, `dcterms:`

  ## Returns

  A keyword list suitable for passing to serializer options.
  """
  @spec prefix_map() :: keyword()
  def prefix_map do
    [
      # Elixir ontology namespaces
      core: Core.__base_iri__(),
      struct: Structure.__base_iri__(),
      otp: OTP.__base_iri__(),
      evo: Evolution.__base_iri__(),

      # Standard namespaces
      rdf: RDF.NS.RDF.__base_iri__(),
      rdfs: RDF.NS.RDFS.__base_iri__(),
      owl: RDF.NS.OWL.__base_iri__(),
      xsd: RDF.NS.XSD.__base_iri__(),
      skos: RDF.NS.SKOS.__base_iri__(),
      prov: PROV.__base_iri__(),

      # BFO/IAO
      bfo: BFO.__base_iri__(),
      iao: IAO.__base_iri__(),

      # Dublin Core
      dc: DC.__base_iri__(),
      dcterms: DCTerms.__base_iri__()
    ]
  end

  @doc """
  Returns the base IRI for a given prefix atom.

  ## Examples

      iex> ElixirOntologies.NS.base_iri(:core)
      "https://w3id.org/elixir-code/core#"

      iex> ElixirOntologies.NS.base_iri(:struct)
      "https://w3id.org/elixir-code/structure#"
  """
  @spec base_iri(atom()) :: String.t() | nil
  def base_iri(prefix) do
    Keyword.get(prefix_map(), prefix)
  end
end
