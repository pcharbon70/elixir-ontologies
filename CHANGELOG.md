# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added contextual `FileAnalyzer.analyze_string/3` and `analyze_string!/3` APIs for
  caller-classified project and dependency source.
- Added `Pipeline.build_graph_for_modules_result/3` for strict graph construction.

### Changed

- Full project expression resources now use stable, source-scoped structural identities;
  multi-clause functions retain deterministic clause order.

### Fixed

- Activated full expression builders for contextual string analysis and made clause body,
  guard, collection, map, tuple, and range expression resources distinct and reachable.
- Preserved control-flow roles, source spans, parameter patterns, keyword/map keys, and
  map-update structure in rooted full-expression graphs.

### Compatibility

- Legacy `analyze_string/1` and `/2` and dependency analysis remain lightweight.

### Safety

- Contextual full-mode analysis returns no partial graph on builder failure and enforces
  100,000-resource, depth-100, and 500,000-triple limits.

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
