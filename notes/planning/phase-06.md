# Phase 6: OTP Extractors (elixir-otp.ttl)

This phase implements extractors for OTP patterns: GenServer, Supervisor, Agent, Task, ETS.

## 6.1 GenServer Extractor

This section detects and extracts GenServer implementations.

### 6.1.1 GenServer Detection
- [x] **Task 6.1.1 Complete**

Detect modules implementing GenServer behaviour.

- [x] 6.1.1.1 Create `lib/elixir_ontologies/extractors/otp/genserver.ex`
- [x] 6.1.1.2 Detect `use GenServer` or `@behaviour GenServer`
- [x] 6.1.1.3 Create `GenServerImplementation` instance
- [x] 6.1.1.4 Link via `implementsOTPBehaviour`
- [x] 6.1.1.5 Write GenServer detection tests (success: 39 tests)

### 6.1.2 GenServer Callback Extraction
- [x] **Task 6.1.2 Complete**

Extract GenServer callbacks.

- [x] 6.1.2.1 Detect `init/1` as `InitCallback`
- [x] 6.1.2.2 Detect `handle_call/3` as `HandleCallCallback`
- [x] 6.1.2.3 Detect `handle_cast/2` as `HandleCastCallback`
- [x] 6.1.2.4 Detect `handle_info/2` as `HandleInfoCallback`
- [x] 6.1.2.5 Detect `handle_continue/2` as `HandleContinueCallback`
- [x] 6.1.2.6 Detect `terminate/2` as `TerminateCallback`
- [x] 6.1.2.7 Link via `hasGenServerCallback`
- [x] 6.1.2.8 Write callback extraction tests (success: 30 tests)

**Section 6.1 Unit Tests:**
- [x] Test GenServer detection via use
- [x] Test GenServer detection via @behaviour
- [x] Test init/1 extraction
- [x] Test handle_call/3 extraction
- [x] Test handle_cast/2 extraction
- [x] Test handle_info/2 extraction

## 6.2 Supervisor Extractor

This section extracts Supervisor definitions and child specs.

### 6.2.1 Supervisor Detection
- [ ] **Task 6.2.1 Complete**

Detect Supervisor implementations.

- [ ] 6.2.1.1 Create `lib/elixir_ontologies/extractors/otp/supervisor.ex`
- [ ] 6.2.1.2 Detect `use Supervisor` or `@behaviour Supervisor`
- [ ] 6.2.1.3 Create `Supervisor` instance
- [ ] 6.2.1.4 Detect `DynamicSupervisor` usage
- [ ] 6.2.1.5 Write supervisor detection tests (success: 6 tests)

### 6.2.2 Supervision Strategy Extraction
- [ ] **Task 6.2.2 Complete**

Extract supervision strategies and child specs.

- [ ] 6.2.2.1 Parse `init/1` return value for strategy
- [ ] 6.2.2.2 Detect `:one_for_one` as `OneForOne`
- [ ] 6.2.2.3 Detect `:one_for_all` as `OneForAll`
- [ ] 6.2.2.4 Detect `:rest_for_one` as `RestForOne`
- [ ] 6.2.2.5 Link via `hasStrategy`
- [ ] 6.2.2.6 Extract child specs as `ChildSpec` instances
- [ ] 6.2.2.7 Extract restart strategy (`:permanent`, `:temporary`, `:transient`)
- [ ] 6.2.2.8 Extract shutdown strategy
- [ ] 6.2.2.9 Write strategy extraction tests (success: 12 tests)

**Section 6.2 Unit Tests:**
- [ ] Test Supervisor detection
- [ ] Test DynamicSupervisor detection
- [ ] Test :one_for_one extraction
- [ ] Test :one_for_all extraction
- [ ] Test child spec extraction
- [ ] Test restart strategy extraction

## 6.3 Agent and Task Extractors

This section extracts Agent and Task usage patterns.

### 6.3.1 Agent/Task Extractor
- [ ] **Task 6.3.1 Complete**

Detect Agent and Task usage.

- [ ] 6.3.1.1 Create `lib/elixir_ontologies/extractors/otp/agent_task.ex`
- [ ] 6.3.1.2 Detect `use Agent` as `Agent`
- [ ] 6.3.1.3 Detect `Task.async`, `Task.start` calls
- [ ] 6.3.1.4 Detect `Task.Supervisor` usage
- [ ] 6.3.1.5 Write agent/task tests (success: 8 tests)

**Section 6.3 Unit Tests:**
- [ ] Test Agent module detection
- [ ] Test Task.async detection
- [ ] Test Task.Supervisor detection

## 6.4 ETS Extractor

This section extracts ETS table definitions and usage.

### 6.4.1 ETS Table Extractor
- [ ] **Task 6.4.1 Complete**

Detect ETS table creation and configuration.

- [ ] 6.4.1.1 Create `lib/elixir_ontologies/extractors/otp/ets.ex`
- [ ] 6.4.1.2 Detect `:ets.new/2` calls
- [ ] 6.4.1.3 Create `ETSTable` instance
- [ ] 6.4.1.4 Extract table name via `tableName`
- [ ] 6.4.1.5 Detect table type (`:set`, `:ordered_set`, `:bag`, `:duplicate_bag`)
- [ ] 6.4.1.6 Classify as `SetTable`, `OrderedSetTable`, `BagTable`, `DuplicateBagTable`
- [ ] 6.4.1.7 Detect access type (`:public`, `:protected`, `:private`)
- [ ] 6.4.1.8 Classify as `PublicTable`, `ProtectedTable`, `PrivateTable`
- [ ] 6.4.1.9 Extract `:read_concurrency`, `:write_concurrency` options
- [ ] 6.4.1.10 Link owner via `ownedByProcess`
- [ ] 6.4.1.11 Write ETS extraction tests (success: 12 tests)

**Section 6.4 Unit Tests:**
- [ ] Test ETS table detection
- [ ] Test table type classification
- [ ] Test access type classification
- [ ] Test concurrency options extraction
- [ ] Test named table detection

## Phase 6 Integration Tests

- [ ] Test GenServer module with all callbacks
- [ ] Test Supervisor with child specs
- [ ] Test module using Agent pattern
- [ ] Test module creating ETS tables
- [ ] Test Application module with supervision tree
