# Phase Hex.6: Mix Task

This phase implements the Mix task providing CLI interface for the batch analyzer with comprehensive options for controlling the analysis process.

## Hex.6.1 Mix Task Implementation

Create the Mix task for running batch analysis from the command line.

### Hex.6.1.1 Create Mix Task Module

Create `lib/mix/tasks/elixir_ontologies.hex_batch.ex` for CLI interface.

- [ ] Hex.6.1.1.1 Create `lib/mix/tasks/elixir_ontologies.hex_batch.ex` module
- [ ] Hex.6.1.1.2 Use `Mix.Task` behaviour
- [ ] Hex.6.1.1.3 Define `@shortdoc` as "Analyze all Elixir packages from hex.pm"
- [ ] Hex.6.1.1.4 Define comprehensive `@moduledoc` with usage examples

### Hex.6.1.2 Define CLI Options

Define command-line option parsing.

- [ ] Hex.6.1.2.1 Define `@switches` keyword list for OptionParser
- [ ] Hex.6.1.2.2 Add `--output-dir` (string) - output directory path
- [ ] Hex.6.1.2.3 Add `--progress-file` (string) - progress file path
- [ ] Hex.6.1.2.4 Add `--resume` (boolean) - resume from progress file
- [ ] Hex.6.1.2.5 Add `--limit` (integer) - max packages to process
- [ ] Hex.6.1.2.6 Add `--start-page` (integer) - starting API page
- [ ] Hex.6.1.2.7 Add `--delay` (integer) - inter-package delay in ms
- [ ] Hex.6.1.2.8 Add `--timeout` (integer) - per-package timeout in minutes
- [ ] Hex.6.1.2.9 Add `--package` (string) - analyze single package
- [ ] Hex.6.1.2.10 Add `--dry-run` (boolean) - list packages only
- [ ] Hex.6.1.2.11 Add `--quiet` (boolean) - minimal output
- [ ] Hex.6.1.2.12 Add `--verbose` (boolean) - detailed output
- [ ] Hex.6.1.2.13 Define `@aliases` for short options (`-o`, `-r`, `-l`, `-v`, `-q`)

### Hex.6.1.3 Implement Run Function

Implement main task execution.

- [ ] Hex.6.1.3.1 Implement `run/1` accepting args list
- [ ] Hex.6.1.3.2 Parse args with `OptionParser.parse!/2`
- [ ] Hex.6.1.3.3 Extract positional arg as output_dir (required)
- [ ] Hex.6.1.3.4 Validate output_dir is provided
- [ ] Hex.6.1.3.5 Ensure required applications started (`:req`, `:jason`)
- [ ] Hex.6.1.3.6 Build `%Config{}` from parsed options
- [ ] Hex.6.1.3.7 Handle `--package` for single package mode
- [ ] Hex.6.1.3.8 Handle `--dry-run` for listing mode
- [ ] Hex.6.1.3.9 Call `BatchProcessor.run/1` for full batch
- [ ] Hex.6.1.3.10 Display final summary on completion
- [ ] Hex.6.1.3.11 Exit with appropriate code (0 success, 1 error)

### Hex.6.1.4 Implement Single Package Mode

Implement single package analysis for testing.

- [ ] Hex.6.1.4.1 Implement `run_single_package/2` accepting name and config
- [ ] Hex.6.1.4.2 Fetch package metadata with `Api.get_package/2`
- [ ] Hex.6.1.4.3 Select version with `Api.latest_stable_version/1`
- [ ] Hex.6.1.4.4 Process single package with `BatchProcessor.process_package/2`
- [ ] Hex.6.1.4.5 Display result
- [ ] Hex.6.1.4.6 Return success/failure status

### Hex.6.1.5 Implement Dry Run Mode

Implement package listing without processing.

- [ ] Hex.6.1.5.1 Implement `run_dry_run/1` accepting config
- [ ] Hex.6.1.5.2 Stream packages from API
- [ ] Hex.6.1.5.3 Filter to Elixir packages
- [ ] Hex.6.1.5.4 Apply limit if configured
- [ ] Hex.6.1.5.5 Print each package name and version
- [ ] Hex.6.1.5.6 Print total count at end
- [ ] Hex.6.1.5.7 Do not download or analyze

### Hex.6.1.6 Implement Help Output

Implement help message display.

- [ ] Hex.6.1.6.1 Define usage examples in `@moduledoc`
- [ ] Hex.6.1.6.2 Show examples for common use cases
- [ ] Hex.6.1.6.3 Document all options with descriptions
- [ ] Hex.6.1.6.4 Show default values for each option

### Hex.6.1.7 Implement Signal Handling

Handle Ctrl+C and termination signals.

- [ ] Hex.6.1.7.1 Trap exit signals in `run/1`
- [ ] Hex.6.1.7.2 Register cleanup handler
- [ ] Hex.6.1.7.3 On signal: save progress immediately
- [ ] Hex.6.1.7.4 On signal: display interruption message
- [ ] Hex.6.1.7.5 On signal: exit gracefully
- [ ] Hex.6.1.7.6 Allow graceful shutdown window (5 seconds)

- [ ] **Task Hex.6.1 Complete**

## Hex.6.2 Progress Display

Implement console progress reporting for user feedback.

### Hex.6.2.1 Create Progress Display Module

Create `lib/elixir_ontologies/hex/progress_display.ex` for UI output.

- [ ] Hex.6.2.1.1 Create `lib/elixir_ontologies/hex/progress_display.ex` module
- [ ] Hex.6.2.1.2 Define `@moduledoc` describing progress display

### Hex.6.2.2 Implement Status Line

Implement single-line status display.

- [ ] Hex.6.2.2.1 Implement `status_line/1` accepting progress state
- [ ] Hex.6.2.2.2 Format: `[123/15000] phoenix v1.7.10 - 45% complete`
- [ ] Hex.6.2.2.3 Include current package name and version
- [ ] Hex.6.2.2.4 Include processed/total count
- [ ] Hex.6.2.2.5 Include percentage if total known
- [ ] Hex.6.2.2.6 Use ANSI escape codes for overwrite (carriage return)

### Hex.6.2.3 Implement ETA Calculation

Calculate and display estimated time remaining.

- [ ] Hex.6.2.3.1 Implement `calculate_eta/1` accepting progress
- [ ] Hex.6.2.3.2 Calculate average duration per package
- [ ] Hex.6.2.3.3 Multiply by remaining packages
- [ ] Hex.6.2.3.4 Return seconds remaining
- [ ] Hex.6.2.3.5 Implement `format_eta/1` for human-readable output
- [ ] Hex.6.2.3.6 Format as "Xh Ym" or "Ym Zs"

### Hex.6.2.4 Implement Statistics Display

Display processing statistics.

- [ ] Hex.6.2.4.1 Implement `stats_line/1` accepting progress
- [ ] Hex.6.2.4.2 Show success/fail/skip counts
- [ ] Hex.6.2.4.3 Format: `✓ 100 ✗ 5 ⊘ 10`
- [ ] Hex.6.2.4.4 Use colors if terminal supports (green/red/yellow)
- [ ] Hex.6.2.4.5 Implement `supports_color?/0` checking terminal

### Hex.6.2.5 Implement Verbose Logging

Implement detailed logging for verbose mode.

- [ ] Hex.6.2.5.1 Implement `log_start/2` logging package start
- [ ] Hex.6.2.5.2 Implement `log_complete/2` logging success
- [ ] Hex.6.2.5.3 Implement `log_error/3` logging failure with reason
- [ ] Hex.6.2.5.4 Implement `log_skip/2` logging skipped package
- [ ] Hex.6.2.5.5 Include timestamps in verbose mode
- [ ] Hex.6.2.5.6 Include duration in complete log

### Hex.6.2.6 Implement Summary Display

Display final summary after completion.

- [ ] Hex.6.2.6.1 Implement `display_summary/1` accepting final progress
- [ ] Hex.6.2.6.2 Show total packages processed
- [ ] Hex.6.2.6.3 Show success/fail/skip breakdown
- [ ] Hex.6.2.6.4 Show total duration
- [ ] Hex.6.2.6.5 Show average duration per package
- [ ] Hex.6.2.6.6 Show output directory path
- [ ] Hex.6.2.6.7 Show progress file path for resume
- [ ] Hex.6.2.6.8 Suggest retry command for failures

- [ ] **Task Hex.6.2 Complete**

**Section Hex.6 Unit Tests:**

- [ ] Test CLI option parsing
- [ ] Test --output-dir is required
- [ ] Test --resume flag handling
- [ ] Test --limit restricts count
- [ ] Test --package single mode
- [ ] Test --dry-run lists only
- [ ] Test --quiet suppresses output
- [ ] Test --verbose enables logging
- [ ] Test Config building from options
- [ ] Test single package processing
- [ ] Test dry run output format
- [ ] Test signal handling saves progress
- [ ] Test status_line formatting
- [ ] Test ETA calculation accuracy
- [ ] Test format_eta output
- [ ] Test stats_line formatting

**Target: 16 unit tests**
