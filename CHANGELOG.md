# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-01

### Added

- Initial release of Elixir Ontologies
- Core ontology (`elixir-core.ttl`): Language-agnostic AST primitives with BFO/IAO alignment
- Structure ontology (`elixir-structure.ttl`): Elixir modules, functions, protocols, behaviours, macros
- OTP ontology (`elixir-otp.ttl`): OTP runtime patterns, supervision trees, GenServer, ETS
- Evolution ontology (`elixir-evolution.ttl`): PROV-O provenance, versioning, change tracking
- Shapes (`elixir-shapes.ttl`): SHACL validation constraints
- Comprehensive guides for each ontology module
- Helper functions for accessing ontology files and namespaces
