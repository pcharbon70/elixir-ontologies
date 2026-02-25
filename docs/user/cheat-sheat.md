# Mix Tasks Cheat Sheat

Quick reference for custom Mix tasks in this project.

## 1) `mix elixir_ontologies.analyze [path]`

Analyze a file or project and generate RDF Turtle output.

### Behavior

| Input | Mode |
|---|---|
| No positional arg | Analyze current project (`.`) |
| One positional arg to file | Analyze single file |
| One positional arg to directory | Analyze project directory |

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--output` | `-o` | string | stdout | Output `.ttl` file path |
| `--base-iri` | `-b` | string | `https://example.org/code#` | Base IRI for generated resources |
| `--include-source` |  | boolean | `false` | Include source text in graph |
| `--include-git` |  | boolean | `true` | Include Git provenance |
| `--exclude-tests` |  | boolean | `true` | Exclude `test/` files in project mode |
| `--validate` | `-v` | boolean | `false` | Validate graph against SHACL |
| `--quiet` | `-q` | boolean | `false` | Suppress progress output |

Examples:

```bash
mix elixir_ontologies.analyze
mix elixir_ontologies.analyze lib/my_module.ex
mix elixir_ontologies.analyze --output output.ttl
mix elixir_ontologies.analyze --base-iri https://myapp.org/code#
mix elixir_ontologies.analyze --no-include-git
```

---

## 2) `mix elixir_ontologies.update --input graph.ttl [project_path]`

Update an existing graph using incremental analysis when state is available.

### Behavior

| Input | Behavior |
|---|---|
| `--input` required | Reads existing graph |
| `project_path` omitted | Uses current directory (`.`) |
| State file present (`INPUT.state`) | Tries incremental update |
| State file missing/invalid | Falls back to full analysis |
| `--force-full` | Always full re-analysis |

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--input` | `-i` | string | required | Existing graph path |
| `--output` | `-o` | string | same as input | Output graph path |
| `--force-full` |  | boolean | `false` | Force full analysis |
| `--base-iri` | `-b` | string | `https://example.org/code#` | Base IRI override |
| `--include-source` |  | boolean | `false` | Include source text |
| `--include-git` |  | boolean | `true` | Include Git provenance |
| `--exclude-tests` |  | boolean | `true` | Exclude test files |
| `--quiet` | `-q` | boolean | `false` | Suppress progress output |

Examples:

```bash
mix elixir_ontologies.update --input my_project.ttl
mix elixir_ontologies.update -i old.ttl -o new.ttl
mix elixir_ontologies.update -i graph.ttl --force-full
mix elixir_ontologies.update -i graph.ttl /path/to/project
```

---

## 3) `mix elixir_ontologies.kg <command> ...`

Persistent knowledge graph management (requires optional `triple_store` dependency).

### Commands

| Command | Purpose |
|---|---|
| `load` | Load RDF files into KG |
| `query` | Run SPARQL query |
| `stats` | Show triple count |
| `export` | Export KG to file |

### `load` options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--db` | `-d` | string | required | DB path |
| `--batch-size` | `-b` | integer | `1000` | Triples per batch |

Examples:

```bash
mix elixir_ontologies.kg load --db ./kg file1.ttl file2.ttl
mix elixir_ontologies.kg load --db ./kg "ontology/**/*.ttl"
```

### `query` options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--db` | `-d` | string | required | DB path |
| `--file` | `-f` | string | none | Read query from file |
| `--format` | `-o` | string | `table` | `table`, `json`, `csv` |
| `--timeout` | `-t` | integer | `30000` | Milliseconds |

Examples:

```bash
mix elixir_ontologies.kg query --db ./kg "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10"
mix elixir_ontologies.kg query --db ./kg --file query.sparql --format json
```

### `stats` options

| Option | Alias | Type | Default |
|---|---|---|---|
| `--db` | `-d` | string | required |

Example:

```bash
mix elixir_ontologies.kg stats --db ./kg
```

### `export` options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--db` | `-d` | string | required | DB path |
| positional output path |  | string | required | Export file |

Example:

```bash
mix elixir_ontologies.kg export --db ./kg backup.ttl
```

---

## 4) `mix elixir_ontologies.hex_batch [output_dir]`

Batch-analyze Hex packages and write `.ttl` outputs.

### Behavior

| Input | Behavior |
|---|---|
| No positional output dir | Uses `.ttl` |
| Positional output dir provided | Uses that directory |
| `--package NAME` | Single package mode |
| `--dry-run` | List packages only |
| `--build-list` | Build pending list files only |

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--output-dir` | `-o` | string | `.ttl` | Output directory |
| `--progress-file` |  | string | `OUTPUT_DIR/progress.json` | Progress store |
| `--resume` | `-r` | boolean | `true` | Resume processing |
| `--limit` | `-l` | integer | unlimited | Max packages |
| `--start-page` |  | integer | `1` | API page start |
| `--delay` |  | integer | `100` | Delay between packages (ms) |
| `--timeout` |  | integer | `5` | Per-package timeout (minutes) |
| `--sort-by` | `-s` | string | `popularity` | `popularity`, `alphabetical`, `alpha` |
| `--package` | `-p` | string | none | Analyze one package |
| `--dry-run` |  | boolean | `false` | List only |
| `--build-list` |  | boolean | `false` | Build list only |
| `--quiet` | `-q` | boolean | `false` | Minimal output |
| `--verbose` | `-v` | boolean | `false` | Detailed logs |

Examples:

```bash
mix elixir_ontologies.hex_batch
mix elixir_ontologies.hex_batch --limit 100
mix elixir_ontologies.hex_batch --package phoenix
mix elixir_ontologies.hex_batch --dry-run --limit 50
mix elixir_ontologies.hex_batch --sort-by alphabetical
```

---

## Notes

- Boolean options support `--no-...` forms in Mix/OptionParser (for example: `--no-include-git`, `--no-resume`).
- Task definitions live in:
  - `lib/mix/tasks/elixir_ontologies.analyze.ex`
  - `lib/mix/tasks/elixir_ontologies.update.ex`
  - `lib/mix/tasks/elixir_ontologies.kg.ex`
  - `lib/mix/tasks/elixir_ontologies.hex_batch.ex`
