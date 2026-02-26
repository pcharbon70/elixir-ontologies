# Mix Tasks Cheat Sheet (`develop`)

This is a quick reference for the custom Mix tasks in this branch.

## `mix elixir_ontologies.analyze [path]`

Analyze a project or file and output RDF Turtle.

### Mode

- No positional arg: analyze current project (`.`)
- One file path: analyze that file
- One directory path: analyze that project

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--output` | `-o` | string | stdout | Output file path |
| `--base-iri` | `-b` | string | `https://example.org/code#` | Base IRI |
| `--include-source` |  | boolean | `false` | Include source text in graph |
| `--include-git` |  | boolean | `true` | Include git provenance |
| `--exclude-tests` |  | boolean | `true` | Exclude `test/` files for project mode |
| `--validate` | `-v` | boolean | `false` | Validate against SHACL shapes |
| `--quiet` | `-q` | boolean | `false` | Suppress progress output |

Examples:

```bash
mix elixir_ontologies.analyze
mix elixir_ontologies.analyze lib/my_module.ex
mix elixir_ontologies.analyze --output output.ttl --base-iri https://myapp.org/code#
mix elixir_ontologies.analyze --no-include-git
```

---

## `mix elixir_ontologies.update --input graph.ttl [project_path]`

Update an existing graph. Uses incremental mode when state is available.

### Behavior

- `--input` is required.
- If `project_path` is omitted, uses `.`.
- If `INPUT_FILE.state` exists and is valid, incremental update is attempted.
- If state is missing/invalid, it falls back to full analysis.
- `--force-full` always forces full analysis.

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--input` | `-i` | string | required | Input graph file |
| `--output` | `-o` | string | input path | Output graph file |
| `--force-full` |  | boolean | `false` | Skip incremental update |
| `--base-iri` | `-b` | string | `https://example.org/code#` | Base IRI |
| `--include-source` |  | boolean | `false` | Include source text |
| `--include-git` |  | boolean | `true` | Include git provenance |
| `--exclude-tests` |  | boolean | `true` | Exclude `test/` files |
| `--quiet` | `-q` | boolean | `false` | Suppress progress output |

Examples:

```bash
mix elixir_ontologies.update --input my_project.ttl
mix elixir_ontologies.update -i old.ttl -o new.ttl
mix elixir_ontologies.update -i graph.ttl --force-full
mix elixir_ontologies.update -i graph.ttl /path/to/project
```

---

## `mix elixir_ontologies.kg <command> ...`

Knowledge graph commands (requires `triple_store`).

### Commands

- `load`
- `query`
- `stats`
- `export`

### `load`

| Option | Alias | Type | Default |
|---|---|---|---|
| `--db` | `-d` | string | required |
| `--batch-size` | `-b` | integer | `1000` |

Example:

```bash
mix elixir_ontologies.kg load --db ./kg "ontology/**/*.ttl"
```

### `query`

| Option | Alias | Type | Default |
|---|---|---|---|
| `--db` | `-d` | string | required |
| `--file` | `-f` | string | none |
| `--format` | `-o` | string | `table` (`table|json|csv`) |
| `--timeout` | `-t` | integer | `30000` ms |

Examples:

```bash
mix elixir_ontologies.kg query --db ./kg "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10"
mix elixir_ontologies.kg query --db ./kg --file query.sparql --format json
```

### `stats`

| Option | Alias | Type | Default |
|---|---|---|---|
| `--db` | `-d` | string | required |

Example:

```bash
mix elixir_ontologies.kg stats --db ./kg
```

### `export`

| Option | Alias | Type | Default |
|---|---|---|---|
| `--db` | `-d` | string | required |
| output path (positional) |  | string | required |

Example:

```bash
mix elixir_ontologies.kg export --db ./kg backup.ttl
```

---

## `mix elixir_ontologies.hex_batch [output_dir]`

Batch-analyze Hex packages and write `.ttl` files.

### Mode selection (priority order)

1. `--package NAME` -> analyze one package
2. `--dry-run` -> list packages only
3. `--build-list` -> build list/progress files only
4. default -> full batch processing

### Options

| Option | Alias | Type | Default | Notes |
|---|---|---|---|---|
| `--output-dir` | `-o` | string | `.ttl` | Output directory (or positional arg) |
| `--progress-file` |  | string | `OUTPUT_DIR/progress.json` | Progress file |
| `--resume` | `-r` | boolean | `true` | Resume prior run |
| `--limit` | `-l` | integer | unlimited | Max packages |
| `--start-page` |  | integer | `1` | Starting API page |
| `--delay` |  | integer | `100` | Delay between packages (ms) |
| `--timeout` |  | integer | `5` | Per-package timeout (minutes) |
| `--sort-by` | `-s` | string | `popularity` | `popularity`, `alphabetical`, `alpha` |
| `--package` | `-p` | string | none | Single package mode |
| `--dry-run` |  | boolean | `false` | List only |
| `--build-list` |  | boolean | `false` | Build list only |
| `--halt-on-warning` |  | boolean | `false` | Stop batch when a warning is detected |
| `--include-expressions` |  | boolean | `false` | Enable full expression AST extraction (larger output) |
| `--quiet` | `-q` | boolean | `false` | Minimal output |
| `--verbose` | `-v` | boolean | `false` | Detailed output |

Examples:

```bash
mix elixir_ontologies.hex_batch
mix elixir_ontologies.hex_batch ./hex_output --limit 100
mix elixir_ontologies.hex_batch --package phoenix
mix elixir_ontologies.hex_batch --dry-run --limit 50
mix elixir_ontologies.hex_batch --halt-on-warning --include-expressions
```

### Important

- `--include-source` is not a valid `hex_batch` option.
- Use `--include-expressions` for deeper extraction in this branch.

---

## Notes

- Boolean options generally support `--no-...` forms (for example `--no-include-git`, `--no-resume`).
- Source files:
  - `lib/mix/tasks/elixir_ontologies.analyze.ex`
  - `lib/mix/tasks/elixir_ontologies.update.ex`
  - `lib/mix/tasks/elixir_ontologies.kg.ex`
  - `lib/mix/tasks/elixir_ontologies.hex_batch.ex`
