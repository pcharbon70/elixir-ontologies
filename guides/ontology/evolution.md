# Elixir Evolution Ontology Guide

**File**: `ontology/elixir-evolution.ttl`
**Namespace**: `https://w3id.org/elixir-code/evolution#`
**Prefix**: `evo:`

## Overview

The evolution ontology tracks code changes over time with full provenance. It answers questions like:

- Who changed this function and when?
- What was the previous version of this module?
- Which commit introduced this bug?
- How has this codebase evolved?

Built on W3C PROV-O, it provides rigorous provenance semantics while supporting RDF-star for fine-grained statement-level annotations.

## Dependencies

```turtle
owl:imports <https://w3id.org/elixir-code/structure> ,
            <http://www.w3.org/ns/prov-o#>
```

Imports:
- Structure ontology for code elements (Module, Function, etc.)
- PROV-O for standardized provenance vocabulary

## PROV-O Foundation

The ontology extends three PROV-O core classes:

### Entities (What)

Things that exist and can be versioned:

```
prov:Entity
└── CodeVersion
    ├── ModuleVersion
    ├── FunctionVersion
    ├── TypeVersion
    └── CodebaseSnapshot
└── ReleaseArtifact
    └── BeamFile
└── ChangeSet
```

### Activities (How)

Things that happen:

```
prov:Activity
├── DevelopmentActivity
│   ├── Commit
│   │   └── MergeCommit
│   ├── Refactoring
│   │   ├── FunctionExtraction
│   │   ├── ModuleExtraction
│   │   ├── Rename
│   │   └── InlineRefactoring
│   ├── CodeReview
│   ├── BugFix
│   ├── FeatureAddition
│   ├── Deprecation
│   ├── Deletion
│   └── PullRequest
├── Compilation
├── Release
└── Deployment
    └── HotCodeUpgrade
```

### Agents (Who)

Who or what performs activities:

```
prov:Agent
└── DevelopmentAgent
    ├── Developer
    ├── Team
    └── Bot
        ├── LLMAgent
        └── CISystem
```

## Versioned Entities

### CodeVersion

Base class for versioned code:

```turtle
evo:CodeVersion a owl:Class ;
    rdfs:subClassOf prov:Entity .
```

Properties:
- `versionString` - Version identifier
- `wasRevisionOf` - Previous version (PROV-O)
- `hasPreviousVersion` / `hasNextVersion` - Direct navigation
- `wasGeneratedBy` - Activity that created it
- `wasAttributedTo` - Agent responsible

### Specialized Versions

```turtle
evo:ModuleVersion a owl:Class ;
    rdfs:subClassOf evo:CodeVersion .

evo:FunctionVersion a owl:Class ;
    rdfs:subClassOf evo:CodeVersion .

evo:TypeVersion a owl:Class ;
    rdfs:subClassOf evo:CodeVersion .

evo:CodebaseSnapshot a owl:Class ;
    rdfs:subClassOf evo:CodeVersion .
```

### Release Artifacts

```turtle
evo:ReleaseArtifact a owl:Class ;
    rdfs:subClassOf prov:Entity .

evo:BeamFile a owl:Class ;
    rdfs:subClassOf evo:ReleaseArtifact .
```

BEAM files are compiled `.beam` bytecode—the output of compilation.

## Development Activities

### Commits

```turtle
evo:Commit a owl:Class ;
    rdfs:subClassOf evo:DevelopmentActivity .
```

Properties:
- `commitHash` - Full 40-character SHA
- `shortHash` - Abbreviated hash
- `commitMessage` - Full message
- `commitSubject` - First line
- `commitBody` - Remaining lines
- `authoredAt` - When written
- `committedAt` - When committed
- `isSigned` - GPG signature present
- `filesChanged` - Number of files
- `parentCommit` - Previous commit(s)
- `containsChange` - Changes in this commit

### Merge Commits

```turtle
evo:MergeCommit a owl:Class ;
    rdfs:subClassOf evo:Commit .
```

Additional properties:
- `mergedFrom` - Source branch
- `mergesPR` - Associated pull request

### Refactoring Types

```turtle
evo:Refactoring a owl:Class ;
    rdfs:subClassOf evo:DevelopmentActivity .
```

Subtypes:
- `FunctionExtraction` - Extract code into new function
- `ModuleExtraction` - Extract code into new module
- `Rename` - Rename any code element
- `InlineRefactoring` - Inline function/variable

### Other Activities

| Class | Description |
|-------|-------------|
| `CodeReview` | PR/changeset review |
| `BugFix` | Defect correction |
| `FeatureAddition` | New functionality |
| `Deprecation` | Mark as deprecated |
| `Deletion` | Remove code |
| `Compilation` | Source to BEAM |
| `Release` | Build release artifact |
| `Deployment` | Deploy to environment |
| `HotCodeUpgrade` | Live code replacement |

## Change Tracking

### ChangeSet

```turtle
evo:ChangeSet a owl:Class ;
    rdfs:subClassOf prov:Entity .
```

Properties:
- `changedElement` - What was changed
- `fromVersion` - Previous state
- `toVersion` - New state
- `linesAdded`, `linesRemoved` - Statistics

### Change Types

```
ChangeSet
├── Addition      # New code added
├── Modification  # Existing code changed
│   ├── SignatureChange    # Parameters/return type
│   ├── BodyChange         # Implementation
│   └── DocumentationChange # Docs only
├── Removal       # Code deleted
└── DependencyChange
    ├── DependencyAddition
    ├── DependencyRemoval
    └── DependencyUpdate
```

### Semantic Versioning

```turtle
evo:SemanticVersion a owl:Class .

evo:BreakingChange a owl:Class ;
    rdfs:subClassOf evo:ChangeSet .

evo:MinorChange a owl:Class ;
    rdfs:subClassOf evo:ChangeSet .

evo:PatchChange a owl:Class ;
    rdfs:subClassOf evo:ChangeSet .
```

Properties:
- `majorVersion`, `minorVersion`, `patchVersion`
- `prereleaseLabel` (e.g., "alpha.1")
- `buildMetadata` (e.g., "build.123")

## Agents

### Developer

```turtle
evo:Developer a owl:Class ;
    rdfs:subClassOf evo:DevelopmentAgent .
```

Properties:
- `developerName` - Display name
- `developerEmail` - Email address
- `githubUsername` - GitHub handle
- `memberOf` - Team membership

### Team

```turtle
evo:Team a owl:Class ;
    rdfs:subClassOf evo:DevelopmentAgent .
```

Properties:
- `teamName` - Team identifier

### Bots

```turtle
evo:Bot a owl:Class ;
    rdfs:subClassOf evo:DevelopmentAgent .

evo:LLMAgent a owl:Class ;
    rdfs:subClassOf evo:Bot .

evo:CISystem a owl:Class ;
    rdfs:subClassOf evo:Bot .
```

Properties:
- `botName` - Bot identifier
- `llmModel` - For LLMAgent, which model

### Roles

```turtle
evo:Author a evo:DevelopmentRole .
evo:Committer a evo:DevelopmentRole .
evo:Reviewer a evo:DevelopmentRole .
evo:Approver a evo:DevelopmentRole .
evo:Maintainer a evo:DevelopmentRole .
```

Used with PROV-O qualified associations:

```turtle
ex:commit1 prov:qualifiedAssociation [
    prov:agent ex:alice ;
    prov:hadRole evo:Author
] .
```

## Version Control Integration

### Repository

```turtle
evo:Repository a owl:Class .
```

Properties:
- `repositoryUrl` - Git remote URL
- `repositoryName` - Short name
- `hasBranch` - Branches in repo
- `hasTag` - Tags in repo
- `defaultBranch` - Main branch

### Branch

```turtle
evo:Branch a owl:Class .
```

Properties:
- `branchName` - Branch identifier (e.g., "main", "feature/login")

### Tag

```turtle
evo:Tag a owl:Class .
```

Properties:
- `tagName` - Tag identifier (e.g., "v1.2.3")
- `tagAnnotation` - Annotation message
- `taggedCommit` - Commit being tagged

### Pull Request

```turtle
evo:PullRequest a owl:Class ;
    rdfs:subClassOf evo:DevelopmentActivity .
```

Properties:
- `prNumber` - PR number
- `prTitle` - Title
- `prDescription` - Body
- `prState` - "open", "closed", "merged"
- `associatedPR` - Links commits to PRs

## Temporal Modeling

### Bitemporal Support

The ontology supports bitemporal modeling—tracking both:

1. **Valid time**: When facts were true in the real world
2. **Transaction time**: When facts were recorded in the knowledge base

```turtle
evo:TemporalExtent a owl:Class .

evo:ValidTime a owl:Class ;
    rdfs:subClassOf evo:TemporalExtent .

evo:TransactionTime a owl:Class ;
    rdfs:subClassOf evo:TemporalExtent .
```

Properties:
- `validFrom` - When fact became true
- `validTo` - When fact ceased to be true
- `recordedAt` - When recorded
- `supersededAt` - When superseded by new record

### RDF-star Annotations

The ontology is designed for RDF-star, enabling statement-level provenance:

```turtle
# Who added this return type and when?
<<ex:myFunction struct:hasReturnType ex:StringType>>
    evo:validFrom "2024-01-15"^^xsd:date ;
    prov:wasGeneratedBy ex:commit_abc123 ;
    prov:wasAttributedTo ex:alice .
```

This avoids the overhead of full RDF reification (4+ triples per annotation).

### Supersession

```turtle
evo:supersedes a owl:ObjectProperty .
evo:supersededBy a owl:ObjectProperty ;
    owl:inverseOf evo:supersedes .
```

For tracking when statements are replaced by new information.

## Compilation and Deployment

### Compilation

```turtle
evo:Compilation a owl:Class ;
    rdfs:subClassOf prov:Activity .
```

Properties:
- `buildNumber` - CI build number
- `mixEnv` - "dev", "test", "prod"
- `compilesTo` - Produced BEAM files

### Release

```turtle
evo:Release a owl:Class ;
    rdfs:subClassOf prov:Activity .
```

Properties:
- `releasedVersion` - CodebaseSnapshot being released
- `includesArtifact` - Release artifacts

### Deployment

```turtle
evo:Deployment a owl:Class ;
    rdfs:subClassOf prov:Activity .

evo:HotCodeUpgrade a owl:Class ;
    rdfs:subClassOf evo:Deployment .
```

Properties:
- `targetEnvironment` - "staging", "production"
- `deployedArtifact` - What was deployed

## PROV-O Relationships

### Entity Relationships

```turtle
evo:wasRevisionOf a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasRevisionOf ;
    a owl:TransitiveProperty .  # For version chains

evo:wasQuotedFrom a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasQuotedFrom .  # Code copied from
```

### Activity Relationships

```turtle
evo:wasGeneratedBy a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasGeneratedBy .

evo:used a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:used .

evo:wasInvalidatedBy a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasInvalidatedBy .

evo:wasInformedBy a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasInformedBy .  # Activity dependencies
```

### Agent Relationships

```turtle
evo:wasAttributedTo a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasAttributedTo .

evo:wasAssociatedWith a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:wasAssociatedWith .

evo:actedOnBehalfOf a owl:ObjectProperty ;
    rdfs:subPropertyOf prov:actedOnBehalfOf .  # Delegation
```

## OWL Axioms

### Disjoint Classes

```turtle
# Activities are disjoint
[] a owl:AllDisjointClasses ;
    owl:members (
        evo:Commit
        evo:Refactoring
        evo:CodeReview
        evo:BugFix
        evo:FeatureAddition
        evo:Deprecation
        evo:Deletion
        evo:Compilation
        evo:Release
        evo:Deployment
    ) .

# Change types are disjoint
[] a owl:AllDisjointClasses ;
    owl:members (
        evo:Addition
        evo:Modification
        evo:Removal
    ) .
```

### Required Properties

```turtle
# Every commit has exactly one hash
evo:Commit rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty evo:commitHash ;
    owl:cardinality 1
] .

# Every commit has at least one change
evo:Commit rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty evo:containsChange ;
    owl:minCardinality 1
] .
```

### Transitivity

```turtle
evo:wasRevisionOf a owl:TransitiveProperty .
```

Enables querying for all ancestors of a version.

## Relationship to Other Modules

### Imports

- `elixir-structure.ttl` - Code elements being versioned
- `PROV-O` - W3C provenance standard

### Usage with Other Modules

Evolution wraps structure entities:

```turtle
ex:userModuleV2 a evo:ModuleVersion ;
    evo:versionString "2.0.0" ;
    evo:wasRevisionOf ex:userModuleV1 ;
    evo:wasGeneratedBy ex:commit123 ;
    # Links to the actual module
    prov:specializationOf ex:userModule .
```

## Usage Examples

### Modeling a Commit

```turtle
ex:commit_abc123 a evo:Commit ;
    evo:commitHash "abc123def456..." ;
    evo:shortHash "abc123" ;
    evo:commitMessage "Fix user authentication bug" ;
    evo:commitSubject "Fix user authentication bug" ;
    evo:authoredAt "2024-03-15T10:30:00Z"^^xsd:dateTime ;
    evo:committedAt "2024-03-15T10:30:00Z"^^xsd:dateTime ;
    evo:filesChanged 3 ;
    evo:wasAssociatedWith ex:alice ;
    evo:containsChange ex:authFix ;
    evo:onBranch ex:mainBranch ;
    evo:inRepository ex:myAppRepo ;
    evo:parentCommit ex:commit_previous .

ex:authFix a evo:BugFix, evo:Modification ;
    evo:changedElement ex:authenticateFunction ;
    evo:linesAdded 5 ;
    evo:linesRemoved 3 .
```

### Modeling Version History

```turtle
ex:userModuleV1 a evo:ModuleVersion ;
    evo:versionString "1.0.0" ;
    evo:wasGeneratedBy ex:initialCommit ;
    evo:wasAttributedTo ex:bob .

ex:userModuleV2 a evo:ModuleVersion ;
    evo:versionString "2.0.0" ;
    evo:wasRevisionOf ex:userModuleV1 ;
    evo:wasGeneratedBy ex:refactorCommit ;
    evo:wasAttributedTo ex:alice .

ex:userModuleV3 a evo:ModuleVersion ;
    evo:versionString "2.1.0" ;
    evo:wasRevisionOf ex:userModuleV2 ;
    evo:wasGeneratedBy ex:featureCommit .
```

### Using RDF-star for Fine-Grained Provenance

```turtle
# Track when a function's return type was added
<<ex:getUserById struct:hasReturnType ex:UserType>>
    evo:validFrom "2024-03-01"^^xsd:date ;
    prov:wasGeneratedBy ex:commit_def456 ;
    prov:wasAttributedTo ex:alice .

# Track when it was changed
<<ex:getUserById struct:hasReturnType ex:OptionalUserType>>
    evo:validFrom "2024-06-01"^^xsd:date ;
    evo:supersedes <<ex:getUserById struct:hasReturnType ex:UserType>> ;
    prov:wasGeneratedBy ex:commit_ghi789 .
```

### Modeling a Release

```turtle
ex:release_v1_0_0 a evo:Release ;
    evo:releasedVersion ex:codebaseV1 ;
    prov:startedAtTime "2024-04-01T12:00:00Z"^^xsd:dateTime ;
    prov:endedAtTime "2024-04-01T12:15:00Z"^^xsd:dateTime ;
    evo:includesArtifact ex:releaseArtifact .

ex:codebaseV1 a evo:CodebaseSnapshot ;
    evo:versionString "1.0.0" ;
    evo:majorVersion 1 ;
    evo:minorVersion 0 ;
    evo:patchVersion 0 .

ex:deployment_prod a evo:Deployment ;
    evo:targetEnvironment "production" ;
    evo:deployedArtifact ex:releaseArtifact ;
    prov:wasInformedBy ex:release_v1_0_0 .
```

## Design Rationale

1. **PROV-O alignment**: Standard provenance vocabulary enables interoperability
2. **RDF-star ready**: Fine-grained annotations without reification overhead
3. **Bitemporal support**: Track both real-world time and recording time
4. **Git-centric**: First-class support for Git workflows
5. **Semantic versioning**: Built-in support for semver classification
6. **Agent diversity**: Humans, teams, bots, and LLMs as first-class agents
