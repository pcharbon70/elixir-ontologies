# Phase 19.4.3: Supervision Tree Builder

## Overview

Implement functions in SupervisorBuilder to generate RDF triples for supervision tree relationships, including supervisor-child links, ordering, and root supervisor detection.

## Task Requirements (from phase-19.md)

- [ ] 19.4.3.1 Implement `build_supervision_tree/3` generating tree relationships
- [ ] 19.4.3.2 Generate `otp:supervises` linking supervisor to children
- [ ] 19.4.3.3 Generate `otp:supervisedBy` inverse relationship
- [ ] 19.4.3.4 Generate `otp:childPosition` with ordering
- [ ] 19.4.3.5 Generate `otp:isRootSupervisor` for application supervisors
- [ ] 19.4.3.6 Add supervision tree builder tests

## Ontology Analysis

From `elixir-otp.ttl`:

### Classes
- `otp:SupervisionTree` - Hierarchical structure of supervisors and workers
- `otp:Supervisor` - Supervisor process
- `otp:Process` - Base process class

### Object Properties
- `otp:supervises` - Links Supervisor to Process (domain: Supervisor, range: Process)
- `otp:supervisedBy` - Inverse of supervises, links Process to Supervisor (domain: Process, range: Supervisor, functional)
- `otp:hasChildren` - Ordered list of child specs (domain: Supervisor, range: rdf:List)
- `otp:rootSupervisor` - Links SupervisionTree to its root Supervisor (domain: SupervisionTree, range: Supervisor)
- `otp:partOfTree` - Links Process to SupervisionTree (domain: Process, range: SupervisionTree)

### Note on childPosition
The ontology doesn't have a `childPosition` property. Options:
1. Use `hasChildren` with rdf:List for ordering (ontology-compliant)
2. Add custom property for direct position tracking

**Decision:** Generate ordering using existing `hasChildren` rdf:List for ontology compliance, and add a position annotation if needed for direct querying.

## Implementation Plan

### Step 1: Implement build_ordered_children/3

Generate ordered children list using rdf:List:
```elixir
@spec build_ordered_children([ChildOrder.t()], RDF.IRI.t(), Context.t()) ::
        {RDF.IRI.t() | nil, [RDF.Triple.t()]}
def build_ordered_children(ordered_children, supervisor_iri, context)
```

Generates:
- `{supervisor_iri, otp:hasChildren, list_head}` - Link to ordered list
- rdf:List structure for children ordering

### Step 2: Implement build_supervision_relationships/3

Generate direct supervisor-child relationships:
```elixir
@spec build_supervision_relationships([ChildSpec.t()], RDF.IRI.t(), Context.t()) ::
        [RDF.Triple.t()]
def build_supervision_relationships(child_specs, supervisor_iri, context)
```

Generates for each child:
- `{supervisor_iri, otp:supervises, child_module_iri}` - Supervisor supervises child
- `{child_module_iri, otp:supervisedBy, supervisor_iri}` - Inverse relationship

### Step 3: Implement build_supervision_tree/4

Main function combining all tree relationships:
```elixir
@spec build_supervision_tree(
  [ChildOrder.t()],
  RDF.IRI.t(),
  Context.t(),
  keyword()
) :: {RDF.IRI.t() | nil, [RDF.Triple.t()]}
def build_supervision_tree(ordered_children, supervisor_iri, context, opts \\ [])
```

Options:
- `:is_root` - Mark as root supervisor
- `:tree_iri` - SupervisionTree IRI if part of larger tree

### Step 4: Implement build_root_supervisor/3

Generate root supervisor triples:
```elixir
@spec build_root_supervisor(RDF.IRI.t(), RDF.IRI.t(), Context.t()) ::
        [RDF.Triple.t()]
def build_root_supervisor(supervisor_iri, tree_iri, context)
```

Generates:
- `{tree_iri, rdf:type, otp:SupervisionTree}` - Tree type
- `{tree_iri, otp:rootSupervisor, supervisor_iri}` - Root link
- `{supervisor_iri, otp:partOfTree, tree_iri}` - Process to tree link

### Step 5: Add IRI Generation

Add to IRI module:
- `for_supervision_tree/2` - Generate tree IRI from base and app name

## Files to Modify

1. `lib/elixir_ontologies/iri.ex`
   - Add `for_supervision_tree/2`

2. `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
   - Add `build_ordered_children/3`
   - Add `build_supervision_relationships/3`
   - Add `build_supervision_tree/4`
   - Add `build_root_supervisor/3`

3. `test/elixir_ontologies/builders/otp/supervisor_builder_test.exs`
   - Add supervision tree builder tests

## Success Criteria

1. All existing tests continue to pass
2. Supervision relationships (supervises/supervisedBy) generated correctly
3. Ordered children list using rdf:List
4. Root supervisor marking works
5. Code compiles without warnings

## Progress

- [x] Step 1: Implement build_ordered_children/3 (rdf:List structure)
- [x] Step 2: Implement build_supervision_relationships/3 (supervises/supervisedBy)
- [x] Step 3: Implement build_supervision_tree/4 (main entry point)
- [x] Step 4: Implement build_root_supervisor/3 (tree type, rootSupervisor, partOfTree)
- [x] Step 5: Add IRI generation for supervision tree (for_supervision_tree/2)
- [x] Step 6: Add comprehensive tests (17 tests)
- [x] Quality checks pass (69 tests total, no warnings)
