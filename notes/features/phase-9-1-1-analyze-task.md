# Feature: Phase 9.1.1 - Analyze Mix Task

## Problem Statement

Implement a Mix task (`mix elixir_ontologies.analyze`) that provides a command-line interface for analyzing Elixir projects and files, generating RDF knowledge graphs in Turtle format. This task serves as the primary user-facing tool for the ElixirOntologies library.

The task must:
- Provide a clean, intuitive CLI interface following Mix conventions
- Support both project-wide and single-file analysis
- Accept command-line options for configuration (--output, --base-iri, etc.)
- Output Turtle-formatted RDF to stdout or file
- Display progress during analysis
- Handle errors gracefully with clear, actionable messages
- Integrate seamlessly with existing ProjectAnalyzer and FileAnalyzer
- Support all configuration options from Config module

## Solution Overview

Create `lib/mix/tasks/elixir_ontologies.analyze.ex` that:

1. **Task Definition**: Use Mix.Task behavior with proper @shortdoc and @moduledoc
2. **Argument Parsing**: Parse command-line arguments using OptionParser
3. **Analysis Mode Detection**: Determine if analyzing a file or project
4. **Configuration Building**: Construct Config from command-line options
5. **Analysis Execution**: Call ProjectAnalyzer or FileAnalyzer as appropriate
6. **Progress Reporting**: Display progress using Mix.shell().info/1
7. **Graph Serialization**: Convert result graph to Turtle format
8. **Output Handling**: Write to stdout or file based on --output option
9. **Error Handling**: Catch errors and display user-friendly messages

## Technical Details

### File Structure

```
lib/mix/tasks/
└── elixir_ontologies.analyze.ex     # New file (main implementation)

test/mix/tasks/
└── elixir_ontologies.analyze_test.exs   # New file (comprehensive tests)
```

### Task Definition

```elixir
defmodule Mix.Tasks.ElixirOntologies.Analyze do
  use Mix.Task

  @shortdoc "Analyze Elixir code and generate RDF knowledge graph"
  @requirements ["compile"]

  @moduledoc """
  Analyzes Elixir source code and generates an RDF knowledge graph.

  ## Usage

      # Analyze current project
      mix elixir_ontologies.analyze

      # Analyze specific project
      mix elixir_ontologies.analyze /path/to/project

      # Analyze single file
      mix elixir_ontologies.analyze lib/my_module.ex

      # Save to file
      mix elixir_ontologies.analyze --output output.ttl

      # Customize base IRI
      mix elixir_ontologies.analyze --base-iri https://myapp.org/code#

  ## Options

    * `--output`, `-o` - Output file path (default: stdout)
    * `--base-iri`, `-b` - Base IRI for generated resources (default: https://example.org/code#)
    * `--include-source` - Include source code text in graph (default: false)
    * `--include-git` - Include git provenance information (default: true)
    * `--exclude-tests` - Exclude test files from project analysis (default: true)
    * `--quiet`, `-q` - Suppress progress output (default: false)

  ## Examples

      # Analyze project and save to file
      mix elixir_ontologies.analyze --output my_project.ttl

      # Analyze with custom base IRI and source text
      mix elixir_ontologies.analyze --base-iri https://myapp.org/ --include-source

      # Analyze single file to stdout
      mix elixir_ontologies.analyze lib/my_module.ex

      # Analyze without git info (faster)
      mix elixir_ontologies.analyze --no-include-git
  """

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args)
end
```

### Command-Line Options

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--output` | `-o` | string | nil | Output file (nil = stdout) |
| `--base-iri` | `-b` | string | `"https://example.org/code#"` | Base IRI for resources |
| `--include-source` | - | boolean | false | Include source text in graph |
| `--include-git` | - | boolean | true | Include git provenance |
| `--exclude-tests` | - | boolean | true | Exclude test/ directories |
| `--quiet` | `-q` | boolean | false | Suppress progress output |

### Analysis Mode Detection

```elixir
defp determine_analysis_mode(args) do
  case args do
    [] ->
      {:project, "."}

    [path] ->
      cond do
        File.regular?(path) -> {:file, path}
        File.dir?(path) -> {:project, path}
        true -> {:error, "Path not found: #{path}"}
      end

    _ ->
      {:error, "Expected 0 or 1 argument, got #{length(args)}"}
  end
end
```

### Progress Reporting Strategy

Display progress at key stages:
- Starting analysis
- Discovering files (for project mode)
- Analyzing individual files (with count)
- Building unified graph
- Serializing to Turtle
- Writing output

Example output:
```
==> Analyzing project at /path/to/project
==> Discovered 23 source files (excluding tests)
==> Analyzing files... (1/23) lib/my_app.ex
==> Analyzing files... (23/23) lib/utils/helper.ex
==> Building unified graph (547 triples)
==> Serializing to Turtle format
==> Writing output to my_project.ttl
==> Analysis complete!
```

### Error Handling Strategy

**User Errors** (exit code 1):
- Invalid arguments (wrong number of arguments)
- Path not found
- Invalid file type (not .ex or .exs)
- No Mix project found
- Invalid option values

**Analysis Errors** (exit code 2):
- Parse errors in source files
- Failed to read files
- Failed to detect project

**System Errors** (exit code 3):
- Failed to write output file
- Permission denied
- Disk full

**Error Message Format**:
```
==> Error: <clear description>
    <optional context/details>
    <optional suggestion for fix>

Example:
==> Error: Mix project not found at /path/to/dir
    No mix.exs file found in /path/to/dir or parent directories.
    Try running from a Mix project directory or specify a valid project path.
```

## Implementation Plan

### Step 1: Create Task Module and Structure
- [ ] Create `lib/mix/tasks/` directory
- [ ] Create `lib/mix/tasks/elixir_ontologies.analyze.ex`
- [ ] Define module with `use Mix.Task`
- [ ] Add @shortdoc and @moduledoc
- [ ] Add @requirements ["compile"]
- [ ] Implement stub run/1 function

### Step 2: Implement Option Parsing
- [ ] Define option parser schema with OptionParser.parse/2
- [ ] Map options to Config struct fields
- [ ] Handle boolean flags (--include-source, --include-git, --exclude-tests)
- [ ] Handle negated flags (--no-include-git)
- [ ] Extract positional arguments (file/project path)
- [ ] Implement parse_options/1 helper
- [ ] Validate parsed options

### Step 3: Implement Configuration Building
- [ ] Create build_config/1 function
- [ ] Start with Config.default()
- [ ] Merge command-line options
- [ ] Validate base_iri format
- [ ] Handle edge cases (empty strings, invalid URIs)
- [ ] Return {:ok, config} or {:error, reason}

### Step 4: Implement Analysis Mode Detection
- [ ] Create determine_analysis_mode/1 function
- [ ] Check if argument is file or directory
- [ ] Return {:project, path} or {:file, path}
- [ ] Handle missing paths
- [ ] Handle invalid paths
- [ ] Validate file extensions (.ex, .exs)

### Step 5: Implement Project Analysis
- [ ] Create analyze_project/3 function (path, config, opts)
- [ ] Call ProjectAnalyzer.analyze/2
- [ ] Handle ProjectAnalyzer errors
- [ ] Extract graph from result
- [ ] Return {:ok, graph, metadata} or {:error, reason}

### Step 6: Implement File Analysis
- [ ] Create analyze_file/3 function (path, config, opts)
- [ ] Call FileAnalyzer.analyze/2
- [ ] Handle FileAnalyzer errors
- [ ] Extract graph from result
- [ ] Return {:ok, graph, metadata} or {:error, reason}

### Step 7: Implement Progress Reporting
- [ ] Create progress reporter module/functions
- [ ] Check opts.quiet flag before displaying
- [ ] Use Mix.shell().info/1 for output
- [ ] Display file count for projects
- [ ] Display current file being analyzed
- [ ] Display graph statistics (triple count)
- [ ] Display completion message

### Step 8: Implement Graph Serialization
- [ ] Create serialize_graph/1 function
- [ ] Call Graph.to_turtle!/1
- [ ] Handle serialization errors
- [ ] Return turtle string

### Step 9: Implement Output Writing
- [ ] Create write_output/2 function (content, opts)
- [ ] Check if --output specified
- [ ] Write to stdout if no output file
- [ ] Write to file if output specified
- [ ] Create parent directories if needed
- [ ] Handle write errors (permissions, disk space)
- [ ] Display success message with file path

### Step 10: Implement Main run/1 Function
- [ ] Parse command-line arguments
- [ ] Build configuration
- [ ] Determine analysis mode
- [ ] Execute appropriate analysis (project or file)
- [ ] Report progress at each stage
- [ ] Serialize graph to Turtle
- [ ] Write output
- [ ] Handle errors at each stage
- [ ] Return :ok on success

### Step 11: Implement Error Handling
- [ ] Catch option parsing errors
- [ ] Catch analysis errors (project/file)
- [ ] Catch serialization errors
- [ ] Catch output writing errors
- [ ] Display user-friendly error messages
- [ ] Exit with appropriate exit codes
- [ ] Create display_error/1 helper

### Step 12: Write Comprehensive Tests
- [ ] Test basic project analysis (stdout)
- [ ] Test basic file analysis (stdout)
- [ ] Test with --output option (file writing)
- [ ] Test with --base-iri option
- [ ] Test with --include-source option
- [ ] Test with --no-include-git option
- [ ] Test with --exclude-tests option
- [ ] Test with --quiet option
- [ ] Test error: invalid path
- [ ] Test error: no Mix project
- [ ] Test error: invalid option values
- [ ] Test error: file write failure

### Step 13: Documentation and Polish
- [ ] Add detailed @moduledoc with examples
- [ ] Add function documentation
- [ ] Add inline comments for complex logic
- [ ] Add usage examples to README (if applicable)
- [ ] Test with real projects
- [ ] Verify output formatting

## Testing Strategy

**Test Categories** (minimum 10 tests):

1. **Basic Analysis** (2 tests)
   - Analyze current project (no args)
   - Analyze file with path argument

2. **Option Parsing** (3 tests)
   - Parse --output option
   - Parse --base-iri option
   - Parse boolean flags (--include-source, --no-include-git)

3. **Configuration Building** (2 tests)
   - Build config from options
   - Validate invalid options

4. **Analysis Mode Detection** (2 tests)
   - Detect project mode (directory path)
   - Detect file mode (file path)

5. **Output Writing** (2 tests)
   - Write to stdout (no --output)
   - Write to file (with --output)

6. **Progress Reporting** (1 test)
   - Suppress output with --quiet

7. **Error Handling** (3 tests)
   - Handle invalid path
   - Handle no Mix project found
   - Handle file write errors

8. **Integration** (2 tests)
   - End-to-end project analysis
   - End-to-end file analysis

### Testing Approach

Since Mix tasks are difficult to test directly (they perform side effects), use these strategies:

1. **Extract Logic**: Move core logic to testable helper functions
2. **Capture Output**: Use `ExUnit.CaptureIO` to test output
3. **Temporary Files**: Use `System.tmp_dir!/0` for output file tests
4. **Mock Shell**: Consider creating a test shell for progress reporting
5. **Integration Tests**: Test with real small Elixir files/projects

### Test Fixtures

Create test fixtures in `test/fixtures/`:
- `simple_module.ex` - Single module with functions
- `tiny_project/` - Minimal Mix project with 2-3 files
- `invalid.ex` - File with syntax errors

## Integration Points

Integrates with:
1. **ProjectAnalyzer** - Project-wide analysis
2. **FileAnalyzer** - Single-file analysis
3. **Config** - Configuration management
4. **Graph** - RDF graph serialization (to_turtle!/1)
5. **Mix.Task** - Mix task behavior
6. **Mix.Shell** - Progress output
7. **OptionParser** - Command-line argument parsing

## Command-Line Examples

```bash
# Basic usage - analyze current project
$ mix elixir_ontologies.analyze

# Analyze specific project
$ mix elixir_ontologies.analyze ~/projects/my_app

# Analyze single file
$ mix elixir_ontologies.analyze lib/my_module.ex

# Save to file
$ mix elixir_ontologies.analyze --output my_project.ttl

# Custom base IRI
$ mix elixir_ontologies.analyze --base-iri https://myapp.org/code#

# Include source text
$ mix elixir_ontologies.analyze --include-source

# Exclude git information (faster)
$ mix elixir_ontologies.analyze --no-include-git

# Include test files
$ mix elixir_ontologies.analyze --no-exclude-tests

# Quiet mode (no progress output)
$ mix elixir_ontologies.analyze --quiet --output out.ttl

# Analyze and pipe to file
$ mix elixir_ontologies.analyze > output.ttl

# Combine multiple options
$ mix elixir_ontologies.analyze \
    --base-iri https://myapp.org/ \
    --output analysis.ttl \
    --include-source \
    --no-exclude-tests
```

## Success Criteria

- [ ] All 10+ tests pass
- [ ] Task appears in `mix help` output
- [ ] Can analyze real Mix projects (including this one)
- [ ] Generates valid Turtle output
- [ ] All command-line options work correctly
- [ ] Progress output is clear and informative
- [ ] Error messages are helpful and actionable
- [ ] Performance: Analyzes typical project (<100 files) in reasonable time
- [ ] Output can be piped to other commands
- [ ] File output creates directories if needed
- [ ] Handles edge cases gracefully
- [ ] Credo clean
- [ ] Documentation complete with examples

## Current Status

🔲 **NOT STARTED** - Ready for implementation

- **Prerequisites:**
  - ✅ ProjectAnalyzer (Phase 8.2.1) complete
  - ✅ FileAnalyzer (Phase 8.2.2) complete
  - ✅ Graph serialization (Graph.to_turtle!/1) available
  - ✅ Config module available

- **Next steps:**
  1. Create lib/mix/tasks/ directory structure
  2. Implement basic task skeleton
  3. Add option parsing
  4. Implement analysis logic
  5. Add progress reporting
  6. Write comprehensive tests

## Implementation Notes

### Design Considerations

1. **Mix Task Conventions**:
   - Follow Mix naming convention (namespace.action)
   - Use @requirements ["compile"] to ensure code is compiled
   - Use @shortdoc for brief help text
   - Provide detailed @moduledoc with examples

2. **Output Flexibility**:
   - Default to stdout for Unix pipeline compatibility
   - Support file output for convenience
   - Use Mix.shell() for progress (goes to stderr)
   - This allows: `mix analyze > output.ttl` to work

3. **Progress vs Output**:
   - Progress messages go to Mix.shell() (stderr)
   - Graph output goes to stdout or file
   - This separation allows piping without progress noise
   - --quiet suppresses progress but not output

4. **Error Recovery**:
   - ProjectAnalyzer already handles file failures gracefully
   - Task should only fail on fatal errors
   - Collect and report non-fatal errors
   - Exit with appropriate codes for scripting

5. **Performance Considerations**:
   - For large projects, consider batch processing
   - Display progress to show task is working
   - Consider adding --parallel option (future enhancement)
   - Git operations can be slow; allow --no-include-git

### Future Enhancements

These features are out of scope for Phase 9.1.1 but could be added later:

1. **Format Options**:
   - Support --format [turtle|ntriples|jsonld]
   - Default to turtle for human readability

2. **Filtering Options**:
   - --include-pattern "lib/**/*.ex"
   - --exclude-pattern "lib/generated/**"
   - More granular control over file selection

3. **Parallel Processing**:
   - --parallel flag to use parallel analysis
   - Significant speedup for large projects

4. **Incremental Analysis**:
   - --incremental flag to only analyze changed files
   - Requires change tracking (Phase 8.3.1)

5. **Statistics Report**:
   - --stats flag to display analysis statistics
   - Module count, function count, triple count, etc.

6. **Validation**:
   - --validate flag to run SHACL validation
   - Report constraint violations

7. **Interactive Mode**:
   - Interactive selection of files/modules to analyze
   - Useful for large projects

### Testing Challenges

Mix tasks are inherently side-effectful, making testing challenging:

1. **Solution**: Extract pure logic to helper functions
   - parse_options/1 - testable
   - build_config/1 - testable
   - determine_analysis_mode/1 - testable
   - Only run/1 performs side effects

2. **Solution**: Use ExUnit.CaptureIO
   - Capture stdout and stderr
   - Verify progress messages
   - Verify error messages

3. **Solution**: Use temporary files
   - Create temp output files
   - Verify file contents
   - Clean up after tests

4. **Solution**: Integration tests
   - Use small, real Elixir files
   - Verify end-to-end behavior
   - May be slower but catch real issues

## Dependencies

### Internal Dependencies
- `ElixirOntologies.Analyzer.ProjectAnalyzer`
- `ElixirOntologies.Analyzer.FileAnalyzer`
- `ElixirOntologies.Config`
- `ElixirOntologies.Graph`

### External Dependencies
- `Mix.Task` (Elixir standard library)
- `Mix.Shell` (Elixir standard library)
- `OptionParser` (Elixir standard library)
- `File` (Elixir standard library)
- `Path` (Elixir standard library)

### Test Dependencies
- `ExUnit.CaptureIO` (for testing output)
- Test fixtures (small Elixir files/projects)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Mix task testing complexity | High | Medium | Extract logic to testable helpers |
| Option parsing edge cases | Medium | Low | Comprehensive option tests |
| File write permissions | Low | Medium | Check permissions before analysis |
| Large project performance | Medium | High | Display progress, consider --quiet |
| Invalid Turtle output | Low | High | Test serialization thoroughly |
| Unclear error messages | Medium | Medium | User test with real errors |

## Validation Checklist

Before marking this phase complete:

- [ ] `mix help` shows the task with correct @shortdoc
- [ ] `mix elixir_ontologies.analyze` (no args) analyzes current project
- [ ] Can analyze this project (elixir-ontologies) successfully
- [ ] All command-line options work as documented
- [ ] Error messages are clear and helpful
- [ ] Progress output shows meaningful information
- [ ] Output is valid Turtle (test with RDF tool)
- [ ] Can pipe output to file: `mix analyze > out.ttl`
- [ ] --quiet suppresses progress but not output
- [ ] File output creates directories if needed
- [ ] All tests pass (minimum 10 tests)
- [ ] Credo clean (no warnings)
- [ ] Documentation complete with examples
- [ ] Handles Ctrl-C gracefully (can interrupt)

## Related Phases

- **Phase 8.2.1** - ProjectAnalyzer (prerequisite)
- **Phase 8.2.2** - FileAnalyzer (prerequisite)
- **Phase 9.1.2** - Update Mix Task (related)
- **Phase 9.2** - CLI Improvements (future enhancements)
- **Phase 10** - Validation (SHACL integration)

## References

- [Mix.Task documentation](https://hexdocs.pm/mix/Mix.Task.html)
- [OptionParser documentation](https://hexdocs.pm/elixir/OptionParser.html)
- [Mix shell documentation](https://hexdocs.pm/mix/Mix.Shell.html)
- [Phase 8.2.1 - Project Analyzer](phase-8-2-1-project-analyzer.md)
- [Phase 8.2.2 - File Analyzer](phase-8-2-2-file-analyzer.md)
