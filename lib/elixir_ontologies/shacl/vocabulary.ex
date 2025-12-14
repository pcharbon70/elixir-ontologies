defmodule ElixirOntologies.SHACL.Vocabulary do
  @moduledoc """
  SHACL vocabulary constants following W3C SHACL Recommendation.

  This module provides centralized definitions of SHACL and RDF IRIs used across
  the SHACL implementation (Reader, Writer, ReportParser, and tests).

  ## Usage

      alias ElixirOntologies.SHACL.Vocabulary, as: SHACL

      # Access SHACL vocabulary terms
      SHACL.node_shape()        # => ~I<http://www.w3.org/ns/shacl#NodeShape>
      SHACL.validation_report() # => ~I<http://www.w3.org/ns/shacl#ValidationReport>

  ## Vocabulary Coverage

  This module includes all SHACL terms used in elixir-ontologies:
  - Core shape classes (NodeShape, ValidationReport, ValidationResult)
  - Targeting (targetClass)
  - Property constraints (path, minCount, maxCount, datatype, class, etc.)
  - Validation report predicates (conforms, result, focusNode, etc.)
  - Severity levels (Violation, Warning, Info)
  - RDF vocabulary terms commonly used with SHACL

  ## Reference

  - W3C SHACL Recommendation: https://www.w3.org/TR/shacl/
  - SHACL namespace: http://www.w3.org/ns/shacl#
  """

  # SHACL Core Classes
  @sh_node_shape RDF.iri("http://www.w3.org/ns/shacl#NodeShape")
  @sh_validation_report RDF.iri("http://www.w3.org/ns/shacl#ValidationReport")
  @sh_validation_result RDF.iri("http://www.w3.org/ns/shacl#ValidationResult")

  # Targeting
  @sh_target_class RDF.iri("http://www.w3.org/ns/shacl#targetClass")
  @sh_target_node RDF.iri("http://www.w3.org/ns/shacl#targetNode")

  # Property Shapes
  @sh_property RDF.iri("http://www.w3.org/ns/shacl#property")
  @sh_path RDF.iri("http://www.w3.org/ns/shacl#path")

  # Property Constraints - Cardinality
  @sh_min_count RDF.iri("http://www.w3.org/ns/shacl#minCount")
  @sh_max_count RDF.iri("http://www.w3.org/ns/shacl#maxCount")

  # Property Constraints - Type
  @sh_datatype RDF.iri("http://www.w3.org/ns/shacl#datatype")
  @sh_class RDF.iri("http://www.w3.org/ns/shacl#class")

  # Property Constraints - String
  @sh_pattern RDF.iri("http://www.w3.org/ns/shacl#pattern")
  @sh_min_length RDF.iri("http://www.w3.org/ns/shacl#minLength")

  # Property Constraints - Numeric
  @sh_min_inclusive RDF.iri("http://www.w3.org/ns/shacl#minInclusive")
  @sh_max_inclusive RDF.iri("http://www.w3.org/ns/shacl#maxInclusive")
  @sh_min_exclusive RDF.iri("http://www.w3.org/ns/shacl#minExclusive")
  @sh_max_exclusive RDF.iri("http://www.w3.org/ns/shacl#maxExclusive")
  @sh_max_length RDF.iri("http://www.w3.org/ns/shacl#maxLength")

  # Property Constraints - Value
  @sh_in RDF.iri("http://www.w3.org/ns/shacl#in")
  @sh_node_kind RDF.iri("http://www.w3.org/ns/shacl#nodeKind")
  @sh_language_in RDF.iri("http://www.w3.org/ns/shacl#languageIn")
  @sh_has_value RDF.iri("http://www.w3.org/ns/shacl#hasValue")

  # Property Constraints - Qualified
  @sh_qualified_value_shape RDF.iri("http://www.w3.org/ns/shacl#qualifiedValueShape")
  @sh_qualified_min_count RDF.iri("http://www.w3.org/ns/shacl#qualifiedMinCount")

  # SPARQL Constraints
  @sh_sparql RDF.iri("http://www.w3.org/ns/shacl#sparql")
  @sh_select RDF.iri("http://www.w3.org/ns/shacl#select")

  # Logical Operators
  @sh_and RDF.iri("http://www.w3.org/ns/shacl#and")
  @sh_or RDF.iri("http://www.w3.org/ns/shacl#or")
  @sh_xone RDF.iri("http://www.w3.org/ns/shacl#xone")
  @sh_not RDF.iri("http://www.w3.org/ns/shacl#not")

  # Constraint Components (for violation reporting)
  @sh_and_constraint_component RDF.iri("http://www.w3.org/ns/shacl#AndConstraintComponent")
  @sh_or_constraint_component RDF.iri("http://www.w3.org/ns/shacl#OrConstraintComponent")
  @sh_xone_constraint_component RDF.iri("http://www.w3.org/ns/shacl#XoneConstraintComponent")
  @sh_not_constraint_component RDF.iri("http://www.w3.org/ns/shacl#NotConstraintComponent")

  # Validation Report Predicates
  @sh_conforms RDF.iri("http://www.w3.org/ns/shacl#conforms")
  @sh_result RDF.iri("http://www.w3.org/ns/shacl#result")
  @sh_focus_node RDF.iri("http://www.w3.org/ns/shacl#focusNode")
  @sh_result_path RDF.iri("http://www.w3.org/ns/shacl#resultPath")
  @sh_source_shape RDF.iri("http://www.w3.org/ns/shacl#sourceShape")
  @sh_result_severity RDF.iri("http://www.w3.org/ns/shacl#resultSeverity")
  @sh_result_message RDF.iri("http://www.w3.org/ns/shacl#resultMessage")
  @sh_value RDF.iri("http://www.w3.org/ns/shacl#value")
  @sh_source_constraint_component RDF.iri("http://www.w3.org/ns/shacl#sourceConstraintComponent")
  @sh_message RDF.iri("http://www.w3.org/ns/shacl#message")

  # Severity Levels
  @sh_violation RDF.iri("http://www.w3.org/ns/shacl#Violation")
  @sh_warning RDF.iri("http://www.w3.org/ns/shacl#Warning")
  @sh_info RDF.iri("http://www.w3.org/ns/shacl#Info")

  # RDF Vocabulary (commonly used with SHACL)
  @rdf_type RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  @rdf_first RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#first")
  @rdf_rest RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest")
  @rdf_nil RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")

  # Core Classes
  @doc "SHACL NodeShape class IRI"
  def node_shape, do: @sh_node_shape

  @doc "SHACL ValidationReport class IRI"
  def validation_report, do: @sh_validation_report

  @doc "SHACL ValidationResult class IRI"
  def validation_result, do: @sh_validation_result

  # Targeting
  @doc "SHACL targetClass predicate IRI"
  def target_class, do: @sh_target_class

  @doc "SHACL targetNode predicate IRI"
  def target_node, do: @sh_target_node

  # Property Shapes
  @doc "SHACL property predicate IRI"
  def property, do: @sh_property

  @doc "SHACL path predicate IRI"
  def path, do: @sh_path

  # Cardinality Constraints
  @doc "SHACL minCount constraint IRI"
  def min_count, do: @sh_min_count

  @doc "SHACL maxCount constraint IRI"
  def max_count, do: @sh_max_count

  # Type Constraints
  @doc "SHACL datatype constraint IRI"
  def datatype, do: @sh_datatype

  @doc "SHACL class constraint IRI"
  def class, do: @sh_class

  # String Constraints
  @doc "SHACL pattern constraint IRI"
  def pattern, do: @sh_pattern

  @doc "SHACL minLength constraint IRI"
  def min_length, do: @sh_min_length

  # Numeric Constraints
  @doc "SHACL minInclusive constraint IRI"
  def min_inclusive, do: @sh_min_inclusive

  @doc "SHACL maxInclusive constraint IRI"
  def max_inclusive, do: @sh_max_inclusive

  @doc "SHACL minExclusive constraint IRI"
  def min_exclusive, do: @sh_min_exclusive

  @doc "SHACL maxExclusive constraint IRI"
  def max_exclusive, do: @sh_max_exclusive

  @doc "SHACL maxLength constraint IRI"
  def max_length, do: @sh_max_length

  # Node Kind Constraints
  @doc "SHACL nodeKind constraint IRI"
  def node_kind, do: @sh_node_kind

  @doc "SHACL languageIn constraint IRI (allowed language tags)"
  def language_in, do: @sh_language_in

  # Value Constraints
  @doc "SHACL in constraint IRI (value enumeration)"
  def in_values, do: @sh_in

  @doc "SHACL hasValue constraint IRI"
  def has_value, do: @sh_has_value

  # Qualified Constraints
  @doc "SHACL qualifiedValueShape constraint IRI"
  def qualified_value_shape, do: @sh_qualified_value_shape

  @doc "SHACL qualifiedMinCount constraint IRI"
  def qualified_min_count, do: @sh_qualified_min_count

  # SPARQL Constraints
  @doc "SHACL sparql constraint IRI"
  def sparql, do: @sh_sparql

  @doc "SHACL select query predicate IRI"
  def select, do: @sh_select

  # Logical Operators
  @doc "SHACL and logical operator IRI (all shapes must conform)"
  def and_operator, do: @sh_and

  @doc "SHACL or logical operator IRI (at least one shape must conform)"
  def or_operator, do: @sh_or

  @doc "SHACL xone logical operator IRI (exactly one shape must conform)"
  def xone_operator, do: @sh_xone

  @doc "SHACL not logical operator IRI (shape must NOT conform)"
  def not_operator, do: @sh_not

  # Constraint Components
  @doc "SHACL AndConstraintComponent IRI"
  def and_constraint_component, do: @sh_and_constraint_component

  @doc "SHACL OrConstraintComponent IRI"
  def or_constraint_component, do: @sh_or_constraint_component

  @doc "SHACL XoneConstraintComponent IRI"
  def xone_constraint_component, do: @sh_xone_constraint_component

  @doc "SHACL NotConstraintComponent IRI"
  def not_constraint_component, do: @sh_not_constraint_component

  # Validation Report Predicates
  @doc "SHACL conforms predicate IRI"
  def conforms, do: @sh_conforms

  @doc "SHACL result predicate IRI"
  def result, do: @sh_result

  @doc "SHACL focusNode predicate IRI"
  def focus_node, do: @sh_focus_node

  @doc "SHACL resultPath predicate IRI"
  def result_path, do: @sh_result_path

  @doc "SHACL sourceShape predicate IRI"
  def source_shape, do: @sh_source_shape

  @doc "SHACL resultSeverity predicate IRI"
  def result_severity, do: @sh_result_severity

  @doc "SHACL resultMessage predicate IRI"
  def result_message, do: @sh_result_message

  @doc "SHACL value predicate IRI"
  def value, do: @sh_value

  @doc "SHACL sourceConstraintComponent predicate IRI"
  def source_constraint_component, do: @sh_source_constraint_component

  @doc "SHACL message predicate IRI"
  def message, do: @sh_message

  # Severity Levels
  @doc "SHACL Violation severity IRI"
  def violation, do: @sh_violation

  @doc "SHACL Warning severity IRI"
  def warning, do: @sh_warning

  @doc "SHACL Info severity IRI"
  def info, do: @sh_info

  # RDF Vocabulary
  @doc "RDF type predicate IRI"
  def rdf_type, do: @rdf_type

  @doc "RDF first predicate IRI (for RDF lists)"
  def rdf_first, do: @rdf_first

  @doc "RDF rest predicate IRI (for RDF lists)"
  def rdf_rest, do: @rdf_rest

  @doc "RDF nil IRI (empty list terminator)"
  def rdf_nil, do: @rdf_nil

  @doc """
  Returns standard SHACL prefix map for Turtle serialization.

  ## Example

      iex> ElixirOntologies.SHACL.Vocabulary.prefix_map()
      %{
        sh: "http://www.w3.org/ns/shacl#",
        rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        xsd: "http://www.w3.org/2001/XMLSchema#"
      }

  """
  @spec prefix_map() :: %{atom() => String.t()}
  def prefix_map do
    %{
      sh: "http://www.w3.org/ns/shacl#",
      rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
      xsd: "http://www.w3.org/2001/XMLSchema#"
    }
  end
end
