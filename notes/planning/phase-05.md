# Phase 5: Advanced Structure Extractors

This phase implements extractors for protocols, behaviours, and structs.

## 5.1 Protocol Extractor

This section extracts protocol definitions and implementations.

### 5.1.1 Protocol Definition Extractor
- [x] **Task 5.1.1 Complete**

Extract defprotocol definitions.

- [x] 5.1.1.1 Create `lib/elixir_ontologies/extractors/protocol.ex`
- [x] 5.1.1.2 Detect `defprotocol` AST pattern
- [x] 5.1.1.3 Extract `protocolName`
- [x] 5.1.1.4 Extract protocol functions as `ProtocolFunction`
- [x] 5.1.1.5 Link via `definesProtocolFunction`
- [x] 5.1.1.6 Detect `@fallback_to_any` as `fallbackToAny`
- [x] 5.1.1.7 Write protocol definition tests (success: 23 doctests + 18 unit tests)

### 5.1.2 Protocol Implementation Extractor
- [x] **Task 5.1.2 Complete**

Extract defimpl definitions.

- [x] 5.1.2.1 Detect `defimpl` AST pattern
- [x] 5.1.2.2 Create `ProtocolImplementation` instance
- [x] 5.1.2.3 Link protocol via `implementsProtocol`
- [x] 5.1.2.4 Extract target type via `forDataType`
- [x] 5.1.2.5 Detect `@derive` as `DerivedImplementation`
- [x] 5.1.2.6 Detect `for: Any` as `AnyImplementation`
- [x] 5.1.2.7 Link struct derivations via `derivesProtocol`
- [x] 5.1.2.8 Write implementation tests (success: 23 doctests + 42 unit tests)

**Section 5.1 Unit Tests:**
- [x] Test defprotocol extraction
- [x] Test protocol function extraction
- [x] Test defimpl extraction
- [x] Test forDataType linking
- [x] Test @derive detection
- [x] Test Any implementation detection

## 5.2 Behaviour Extractor

This section extracts behaviour definitions and implementations.

### 5.2.1 Behaviour Definition Extractor
- [x] **Task 5.2.1 Complete**

Extract modules that define behaviours via @callback.

- [x] 5.2.1.1 Create `lib/elixir_ontologies/extractors/behaviour.ex`
- [x] 5.2.1.2 Detect modules with `@callback` as `Behaviour`
- [x] 5.2.1.3 Extract `@callback` as `RequiredCallback`
- [x] 5.2.1.4 Extract `@optional_callbacks` items as `OptionalCallback`
- [x] 5.2.1.5 Extract `@macrocallback` as `MacroCallback`
- [x] 5.2.1.6 Link via `definesCallback`
- [x] 5.2.1.7 Create `CallbackSpec` for callback type signatures
- [x] 5.2.1.8 Write behaviour definition tests (success: 20 doctests + 38 unit tests)

### 5.2.2 Behaviour Implementation Extractor
- [x] **Task 5.2.2 Complete**

Extract @behaviour declarations and callback implementations.

- [x] 5.2.2.1 Detect `@behaviour ModuleName` in module
- [x] 5.2.2.2 Create `BehaviourImplementation` relationship
- [x] 5.2.2.3 Link via `implementsBehaviour`
- [x] 5.2.2.4 Match implemented functions to callbacks via `implementsCallback`
- [x] 5.2.2.5 Detect `defoverridable` for default implementations
- [x] 5.2.2.6 Link overrides via `overridesDefault`
- [x] 5.2.2.7 Write implementation tests (success: 40 doctests + 71 unit tests)

**Section 5.2 Unit Tests:**
- [x] Test behaviour definition extraction
- [x] Test @callback extraction
- [x] Test @optional_callbacks handling
- [x] Test @behaviour declaration extraction
- [x] Test callback implementation matching
- [x] Test defoverridable detection

## 5.3 Struct Extractor

This section extracts struct and exception definitions.

### 5.3.1 Struct Definition Extractor
- [ ] **Task 5.3.1 Complete**

Extract defstruct definitions.

- [ ] 5.3.1.1 Create `lib/elixir_ontologies/extractors/struct.ex`
- [ ] 5.3.1.2 Detect `defstruct` AST pattern
- [ ] 5.3.1.3 Create `Struct` linked to containing module
- [ ] 5.3.1.4 Extract fields as `StructField` instances
- [ ] 5.3.1.5 Set `fieldName` for each field
- [ ] 5.3.1.6 Detect fields with defaults (`hasDefaultFieldValue: true`)
- [ ] 5.3.1.7 Extract `@enforce_keys` as `EnforcedKey` subclass
- [ ] 5.3.1.8 Link via `hasField` and `hasEnforcedKey`
- [ ] 5.3.1.9 Extract `@derive` protocols via `derivesProtocol`
- [ ] 5.3.1.10 Write struct tests (success: 12 tests)

### 5.3.2 Exception Extractor
- [ ] **Task 5.3.2 Complete**

Extract defexception definitions.

- [ ] 5.3.2.1 Detect `defexception` AST pattern
- [ ] 5.3.2.2 Create `Exception` (subclass of Struct)
- [ ] 5.3.2.3 Extract exception message field
- [ ] 5.3.2.4 Extract custom `message/1` implementation if present
- [ ] 5.3.2.5 Write exception tests (success: 6 tests)

**Section 5.3 Unit Tests:**
- [ ] Test defstruct extraction
- [ ] Test struct field extraction
- [ ] Test default value detection
- [ ] Test @enforce_keys extraction
- [ ] Test @derive extraction
- [ ] Test defexception extraction

## Phase 5 Integration Tests

- [ ] Test protocol with multiple implementations
- [ ] Test behaviour with implementing module
- [ ] Test struct with enforced keys and derived protocols
- [ ] Test exception with custom message
