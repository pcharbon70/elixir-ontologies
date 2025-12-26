# Evolution Tracking Guide

This guide explains how to track code evolution using Git integration and PROV-O semantics.

## Overview

The evolution tracking system provides:

- **Commit extraction** - Full commit metadata and history
- **Activity classification** - Categorize commits (feature, bugfix, refactor)
- **Agent tracking** - Track developers, bots, and CI systems
- **Version chains** - Link code versions over time
- **Blame information** - Line-level authorship
- **Release tracking** - Git tags and releases

## PROV-O Alignment

The system uses W3C PROV-O (Provenance Ontology) concepts:

| PROV-O Concept | Implementation | Description |
|----------------|----------------|-------------|
| `prov:Entity` | Code versions | Versioned snapshots of modules/functions |
| `prov:Activity` | Commits | Development activities that change code |
| `prov:Agent` | Developers | People and systems that perform activities |
| `prov:wasGeneratedBy` | Version creation | Links code versions to commits |
| `prov:wasAttributedTo` | Authorship | Links code to its authors |
| `prov:actedOnBehalfOf` | Delegation | Code ownership chains |

## Extracting Commit Information

### Single Commit

```elixir
alias ElixirOntologies.Extractors.Evolution.Commit

# Extract HEAD commit
{:ok, commit} = Commit.extract_commit(".", "HEAD")

IO.puts("SHA: #{commit.sha}")
IO.puts("Author: #{commit.author_name} <#{commit.author_email}>")
IO.puts("Subject: #{commit.subject}")
IO.puts("Merge: #{commit.is_merge}")
```

### Commit History

```elixir
# Extract last 10 commits
{:ok, commits} = Commit.extract_commits(".", limit: 10)

Enum.each(commits, fn commit ->
  IO.puts("#{commit.short_sha} #{commit.subject}")
end)
```

### Commits for a File

```elixir
# Get commits that modified a specific file
{:ok, commits} = Commit.extract_commits(".",
  file_path: "lib/my_module.ex",
  limit: 20
)
```

## Activity Classification

Commits are automatically classified based on their messages:

```elixir
alias ElixirOntologies.Extractors.Evolution.Activity

{:ok, commit} = Commit.extract_commit(".", "HEAD")
{:ok, activity} = Activity.classify_commit(".", commit)

IO.puts("Type: #{activity.type}")        # :feature, :bugfix, :refactor, etc.
IO.puts("Confidence: #{activity.confidence}")  # :high, :medium, :low
```

### Activity Types

| Type | Description | Detected By |
|------|-------------|-------------|
| `:feature` | New functionality | "feat:", "add", "implement" |
| `:bugfix` | Bug fixes | "fix:", "bug", "patch" |
| `:refactor` | Code restructuring | "refactor:", restructure patterns |
| `:docs` | Documentation | "docs:", ".md" files only |
| `:test` | Test changes | "test:", test file patterns |
| `:chore` | Maintenance | "chore:", config changes |
| `:deprecation` | Deprecations | `@deprecated` additions |
| `:deletion` | Code removal | Pure deletions |

### Conventional Commits

The classifier recognizes [Conventional Commits](https://conventionalcommits.org/):

```
feat: add user authentication
fix(auth): resolve token expiration bug
refactor!: restructure database layer

BREAKING CHANGE: API changed
```

## Agent Tracking

Track developers and automated systems:

```elixir
alias ElixirOntologies.Extractors.Evolution.Agent

{:ok, commit} = Commit.extract_commit(".", "HEAD")
{:ok, agents} = Agent.extract_agents(".", commit)

Enum.each(agents, fn agent ->
  IO.puts("#{agent.name} (#{agent.agent_type})")
end)
```

### Agent Types

| Type | Description | Detection |
|------|-------------|-----------|
| `:developer` | Human developer | Default |
| `:bot` | Dependency bots | dependabot, renovate, greenkeeper |
| `:ci` | CI/CD systems | GitHub Actions, GitLab CI |
| `:llm` | AI assistants | copilot, claude, cursor |

### Agent Deduplication

Agents are deduplicated by email across commits:

```elixir
{:ok, commits} = Commit.extract_commits(".", limit: 100)
{:ok, all_agents} = Agent.extract_all_agents(".", commits)

# Unique agents with activity counts
Enum.each(all_agents, fn agent ->
  IO.puts("#{agent.name}: #{length(agent.associated_activities)} activities")
end)
```

## Version Tracking

Track how code entities evolve:

```elixir
alias ElixirOntologies.Extractors.Evolution.EntityVersion

# Track module versions
{:ok, versions} = EntityVersion.track_module_versions(
  ".",
  "MyApp.Users",
  limit: 10
)

Enum.each(versions, fn version ->
  IO.puts("#{version.version_id} - #{version.content_hash}")
end)
```

### Content Hashing

Versions use content hashes to detect actual changes:

```elixir
# Two commits may touch the file but not change content
# Content hash identifies truly different versions
version.content_hash  # => "a1b2c3d4e5f6g7h8"
```

### Derivation Chains

Build version history chains:

```elixir
{:ok, versions} = EntityVersion.track_module_versions(".", "MyApp.Users")
chain = EntityVersion.build_derivation_chain(versions)

# Each version links to its predecessor
Enum.each(chain, fn {current, previous} ->
  IO.puts("#{current.version_id} derived from #{previous.version_id}")
end)
```

## Blame Information

Get line-level authorship:

```elixir
alias ElixirOntologies.Extractors.Evolution.Blame

{:ok, blame} = Blame.extract_blame(".", "lib/my_module.ex")

IO.puts("File: #{blame.path}")
IO.puts("Lines: #{blame.line_count}")

# Each line has authorship info
Enum.each(blame.lines, fn line ->
  IO.puts("L#{line.line_number}: #{line.author} - #{line.sha}")
end)
```

## File History

Track file changes over time:

```elixir
alias ElixirOntologies.Extractors.Evolution.FileHistory

{:ok, history} = FileHistory.extract_history(".", "lib/my_module.ex")

Enum.each(history.changes, fn change ->
  IO.puts("#{change.sha}: +#{change.additions}/-#{change.deletions}")
end)
```

## Release Tracking

Track Git tags and releases:

```elixir
alias ElixirOntologies.Extractors.Evolution.Release

# Get all releases
{:ok, releases} = Release.extract_releases(".")

Enum.each(releases, fn release ->
  IO.puts("#{release.tag}: #{release.name}")
end)

# Get latest release
{:ok, latest} = Release.extract_latest_release(".")
```

## Snapshot Extraction

Capture repository state at a point in time:

```elixir
alias ElixirOntologies.Extractors.Evolution.Snapshot

# Current state
{:ok, snapshot} = Snapshot.extract_snapshot(".")

IO.puts("Commit: #{snapshot.commit_sha}")
IO.puts("Files: #{length(snapshot.files)}")
IO.puts("Taken at: #{snapshot.timestamp}")
```

## Building RDF Graphs

### Commit Triples

```elixir
alias ElixirOntologies.Builders.Evolution.CommitBuilder
alias ElixirOntologies.Builders.Context

{:ok, commit} = Commit.extract_commit(".", "HEAD")
context = Context.new(base_iri: "https://example.org/code#")

{commit_iri, triples} = CommitBuilder.build(commit, context)

# triples contains:
# - Type assertion (evo:Commit or evo:MergeCommit)
# - Hash properties
# - Timestamps (prov:startedAtTime, prov:endedAtTime)
# - Parent relationships
```

### Activity Triples

```elixir
alias ElixirOntologies.Builders.Evolution.ActivityBuilder
alias ElixirOntologies.Extractors.Evolution.ActivityModel

{:ok, commit} = Commit.extract_commit(".", "HEAD")
{:ok, activity} = ActivityModel.extract_activity(".", commit)

{activity_iri, triples} = ActivityBuilder.build(activity, context)

# Includes PROV-O relationships:
# - prov:Activity type
# - prov:wasAssociatedWith (agents)
# - prov:used (input entities)
# - prov:wasGeneratedBy (output entities)
```

### Agent Triples

```elixir
alias ElixirOntologies.Builders.Evolution.AgentBuilder

{:ok, agents} = Agent.extract_agents(".", commit)
agent = List.first(agents)

{agent_iri, triples} = AgentBuilder.build(agent, context)

# Includes:
# - prov:Agent type
# - Agent type classification
# - Name and identity
```

## Privacy Considerations

### Email Anonymization

For privacy (GDPR compliance), emails can be anonymized:

```elixir
alias ElixirOntologies.Extractors.Evolution.GitUtils

# Anonymize email
hash = GitUtils.anonymize_email("user@example.com")
# => "a1b2c3..." (SHA256 hash)

# Use in extraction
{:ok, commit} = Commit.extract_commit(".", "HEAD", anonymize_emails: true)
```

### Agent IDs

Agent IDs are hash-based for privacy:

```elixir
Agent.build_agent_id("user@example.com")
# => "agent:a1b2c3d4e5f6"
```

## Complete Example

```elixir
alias ElixirOntologies.Extractors.Evolution.{Commit, Activity, Agent}
alias ElixirOntologies.Builders.Evolution.{CommitBuilder, ActivityBuilder, AgentBuilder}
alias ElixirOntologies.Builders.Context
alias ElixirOntologies.Graph

# Setup
context = Context.new(base_iri: "https://myapp.org/code#")
graph = Graph.new()

# Extract and build for recent commits
{:ok, commits} = Commit.extract_commits(".", limit: 10)

graph = Enum.reduce(commits, graph, fn commit, acc ->
  # Build commit triples
  {_iri, commit_triples} = CommitBuilder.build(commit, context)

  # Build activity triples
  {:ok, activity} = Activity.classify_commit(".", commit)
  {_iri, activity_triples} = ActivityBuilder.build(activity, context)

  # Build agent triples
  {:ok, agents} = Agent.extract_agents(".", commit)
  agent_triples = Enum.flat_map(agents, fn agent ->
    {_iri, triples} = AgentBuilder.build(agent, context)
    triples
  end)

  # Add all to graph
  acc
  |> Graph.add(commit_triples)
  |> Graph.add(activity_triples)
  |> Graph.add(agent_triples)
end)

# Output
IO.puts(Graph.to_turtle(graph))
```

## Next Steps

- [SHACL Validation](./shacl-validation.md) - Validate evolution graphs
- [Querying the Graph](./querying.md) - Query provenance data
