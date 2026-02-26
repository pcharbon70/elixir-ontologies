# Phase 22: Literal Expression Extraction

This phase implements extraction for all literal types defined in the elixir-core.ttl ontology. Literals are the leaves of the AST tree and form the foundation for all expression extraction. We'll handle atoms, integers, floats, strings, charlists, binaries, lists, tuples, maps, keyword lists, sigils, and ranges.

## 22.1 Atom Literals

This section implements extraction for atom literals including `true`, `false`, `nil`, and named atoms like `:ok`, `:error`.

### 22.1.1 Atom Literal Detection
- [ ] 22.1.1.1 Implement `build_atom_literal/3` in ExpressionBuilder
- [ ] 22.1.1.2 Match boolean atoms: `true`, `false` → `BooleanLiteral` (subclasses AtomLiteral)
- [ ] 22.1.1.3 Match `nil` → `NilLiteral` (subclass of AtomLiteral)
- [ ] 22.1.1.4 Match other atoms → generic `AtomLiteral`
- [ ] 22.1.1.5 Handle quoted atoms `{:{}, _, [atom_name]}` pattern

### 22.1.2 Atom Value Extraction
- [ ] 22.1.2.1 Extract atom name using `Atom.to_string/1`
- [ ] 22.1.2.2 Create `atomValue` triple with XSD string datatype
- [ ] 22.1.2.3 Handle colon-prefixed atoms in AST (Elixir represents `:foo` as atom `:foo`)
- [ ] 22.1.2.4 Handle boolean atoms as both `AtomLiteral` and boolean literals
- [ ] 22.1.2.5 Create type triple: `expr_iri a Core.AtomLiteral`

**Section 22.1 Unit Tests:**
- [ ] Test atom literal extraction for `true` (boolean)
- [ ] Test atom literal extraction for `false` (boolean)
- [ ] Test atom literal extraction for `nil`
- [ ] Test atom literal extraction for named atoms (`:ok`, `:error`)
- [ ] Test atom literal extraction for atoms with special characters
- [ ] Test atom value is correctly escaped in RDF
- [ ] Test atom literal IRI is deterministic

## 22.2 Numeric Literals

This section implements extraction for integer and float literals, including support for different number bases and formats.

### 22.2.1 Integer Literals
- [ ] 22.2.1.1 Implement `build_integer_literal/3` for integer AST nodes
- [ ] 22.2.1.2 Match plain integers: `42`, `-42`, `+42`
- [ ] 22.2.1.3 Match hexadecimal: `0x1A`, `0x1a`
- [ ] 22.2.1.4 Match octal: `0o755` (if present in AST)
- [ ] 22.2.1.5 Match binary: `0b1010` (if present in AST)
- [ ] 22.2.1.6 Create type triple: `expr_iri a Core.IntegerLiteral`
- [ ] 22.2.1.7 Create `integerValue` triple with XSD integer datatype
- [ ] 22.2.1.8 Optionally store base information in metadata

### 22.2.2 Float Literals
- [ ] 22.2.2.1 Implement `build_float_literal/3` for float AST nodes
- [ ] 22.2.2.2 Match decimal floats: `3.14`, `-0.5`, `1.0e10`
- [ ] 22.2.2.3 Match scientific notation: `1.5e-3`, `2.0E10`
- [ ] 22.2.2.4 Create type triple: `expr_iri a Core.FloatLiteral`
- [ ] 22.2.2.5 Create `floatValue` triple with XSD double datatype
- [ ] 22.2.2.6 Handle Elixir float precision in RDF conversion

**Section 22.2 Unit Tests:**
- [ ] Test integer literal extraction for positive integers
- [ ] Test integer literal extraction for negative integers
- [ ] Test integer literal extraction for zero
- [ ] Test integer literal extraction for hexadecimal (if in AST)
- [ ] Test integer literal extraction for octal (if in AST)
- [ ] Test integer literal extraction for binary (if in AST)
- [ ] Test float literal extraction for decimal floats
- [ ] Test float literal extraction for scientific notation
- [ ] Test float literal extraction handles precision correctly
- [ ] Test numeric literals preserve value in round-trip

## 22.3 String Literals

This section implements extraction for string (binary) literals and their interpolation/special character handling.

### 22.3.1 String Literal Extraction
- [ ] 22.3.1.1 Implement `build_string_literal/3` for string AST nodes
- [ ] 22.3.1.2 Match double-quoted strings: `"hello"`
- [ ] 22.3.1.3 Match heredocs: `"""multi\nline"""`
- [ ] 22.3.1.4 Match sigil strings: `~s(no interpolation)`
- [ ] 22.3.1.5 Match interpolated strings: `"hello #{name}"` (as StringLiteral with interpolated expressions)
- [ ] 22.3.1.6 Create type triple: `expr_iri a Core.StringLiteral`
- [ ] 22.3.1.7 Create `stringValue` triple with XSD string datatype
- [ ] 22.3.1.8 Handle escape sequences in string values

### 22.3.2 String Interpolation (Future Extension)
- [ ] 22.3.2.1 Detect interpolation: `{:<<>>, _, [parts]}` with `{}`
- [ ] 22.3.2.2 Create `InterpolatedString` or use `StringConcatOperator`
- [ ] 22.3.2.3 Extract literal parts as `StringLiteral`
- [ ] 22.3.2.4 Extract interpolated expressions as child expressions
- [ ] 22.3.2.5 Link via `hasExpression` for each interpolated part
- [ ] 22.3.2.6 Note: Defer detailed interpolation to phase 29 (complex expressions)

**Section 22.3 Unit Tests:**
- [ ] Test string literal extraction for simple strings
- [ ] Test string literal extraction for empty strings
- [ ] Test string literal extraction for multi-line strings
- [ ] Test string literal extraction for strings with escape sequences
- [ ] Test string literal extraction for strings with special characters
- [ ] Test string literal extraction for heredocs
- [ ] Test string literal preserves exact value in RDF
- [ ] Test interpolated strings are detected (details deferred)

## 22.4 Charlist Literals

This section implements extraction for charlist literals (single-quoted lists of characters).

### 22.4.1 Charlist Literal Extraction
- [ ] 22.4.1.1 Implement `build_charlist_literal/3` for charlist AST nodes
- [ ] 22.4.1.2 Match single-quoted strings: `'hello'`
- [ ] 22.4.1.3 Match charlists with escape sequences: `'\n'`, `'\t'`
- [ ] 22.4.1.4 Match charlist question mark: `'?'`
- [ ] 22.4.1.5 Create type triple: `expr_iri a Core.CharlistLiteral`
- [ ] 22.4.1.6 Store charlist content as string (converted from list of integers)
- [ ] 22.4.1.7 Create appropriate value property triple

**Section 22.4 Unit Tests:**
- [ ] Test charlist literal extraction for simple charlists
- [ ] Test charlist literal extraction for empty charlists
- [ ] Test charlist literal extraction for escape sequences
- [ ] Test charlist literal is distinguished from string literal
- [ ] Test charlist content is correctly converted

## 22.5 Binary Literals

This section implements extraction for binary/bitstring literals with their modifiers and segment specifications.

### 22.5.1 Binary Literal Extraction
- [ ] 22.5.1.1 Implement `build_binary_literal/3` for binary AST nodes
- [ ] 22.5.1.2 Match `<<>>` double angle brackets pattern
- [ ] 22.5.1.3 Match empty binary: `<<>>`
- [ ] 22.5.1.4 Match binary with content: `<<"hello">>`
- [ ] 22.5.1.5 Match binary with segments: `<<x::8, y::binary>>`
- [ ] 22.5.1.6 Create type triple: `expr_iri a Core.BinaryLiteral`
- [ ] 22.5.1.7 Store binary content using base64 encoding or hex
- [ ] 22.5.1.8 Create `binaryValue` triple with XSD base64Binary datatype

### 22.5.2 Binary Segment Extraction (Future Extension)
- [ ] 22.5.2.1 Note: Full binary segment extraction deferred to pattern phase
- [ ] 22.5.2.2 Binary segments will use `BinaryPattern` from ontology
- [ ] 22.5.2.3 Size, type, and unit modifiers handled in pattern phase
- [ ] 22.5.2.4 For literals, just store the concatenated binary value

**Section 22.5 Unit Tests:**
- [ ] Test binary literal extraction for empty binary
- [ ] Test binary literal extraction for string binary
- [ ] Test binary literal extraction for binary with segments
- [ ] Test binary literal is correctly base64 encoded
- [ ] Test binary literal round-trip preserves value

## 22.6 List Literals

This section implements extraction for list literals including proper lists and improper lists.

### 22.6.1 List Literal Extraction
- [ ] 22.6.1.1 Implement `build_list_literal/3` for list AST nodes
- [ ] 22.6.1.2 Match empty list: `[]`
- [ ] 22.6.1.3 Match proper list: `[1, 2, 3]`
- [ ] 22.6.1.4 Match nested lists: `[[1, 2], [3, 4]]`
- [ ] 22.6.1.5 Create type triple: `expr_iri a Core.ListLiteral`
- [ ] 22.6.1.6 Extract each element as a child expression recursively
- [ ] 22.6.1.7 Link elements via `hasElement` property (ordered)
- [ ] 22.6.1.8 Optionally create RDF list for preserving order

### 22.6.2 Improper List and Cons Pattern
- [ ] 22.6.2.1 Match cons pattern: `[head | tail]`
- [ ] 22.6.2.2 Create type triple: `expr_iri a Core.ListLiteral`
- [ ] 22.6.2.3 Extract `head` expression and link via `hasHead`
- [ ] 22.6.2.4 Extract `tail` expression and link via `hasTail`
- [ ] 22.6.2.5 Note: Improper lists use `ConsOperator` or special list handling

**Section 22.6 Unit Tests:**
- [ ] Test list literal extraction for empty list
- [ ] Test list literal extraction for flat list
- [ ] Test list literal extraction for nested list
- [ ] Test list literal extraction for heterogeneous list
- [ ] Test list literal extraction preserves element order
- [ ] Test cons pattern extraction for `[head | tail]`
- [ ] Test cons pattern links head and tail expressions

## 22.7 Tuple Literals

This section implements extraction for tuple literals of any arity.

### 22.7.1 Tuple Literal Extraction
- [ ] 22.7.1.1 Implement `build_tuple_literal/3` for tuple AST nodes
- [ ] 22.7.1.2 Match 2-tuple special form: `{left, right}` (when left is not atom)
- [ ] 22.7.1.3 Match n-tuple: `{{}, _, elements}`
- [ ] 22.7.1.4 Match empty tuple: `{}`
- [ ] 22.7.1.5 Match nested tuples: `{{1, 2}, {3, 4}}`
- [ ] 22.7.1.6 Create type triple: `expr_iri a Core.TupleLiteral`
- [ ] 22.7.1.7 Extract each element as a child expression
- [ ] 22.7.1.8 Link elements via `hasElement` property with position

**Section 22.7 Unit Tests:**
- [ ] Test tuple literal extraction for empty tuple
- [ ] Test tuple literal extraction for 2-tuple
- [ ] Test tuple literal extraction for n-tuple
- [ ] Test tuple literal extraction for nested tuple
- [ ] Test tuple literal extraction preserves element order
- [ ] Test tuple literal distinguishes from tagged tuple

## 22.8 Map and Keyword List Literals

This section implements extraction for map literals, struct literals, and keyword list literals.

### 22.8.1 Map Literal Extraction
- [ ] 22.8.1.1 Implement `build_map_literal/3` for map AST nodes
- [ ] 22.8.1.2 Match empty map: `%{}`
- [ ] 22.8.1.3 Match map with pairs: `%{a: 1, b: 2}`
- [ ] 22.8.1.4 Match map with string keys: `%{"a" => 1}`
- [ ] 22.8.1.5 Match map with mixed keys: `%{a: 1, "b" => 2}`
- [ ] 22.8.1.6 Create type triple: `expr_iri a Core.MapLiteral`
- [ ] 22.8.1.7 Extract each key-value pair as a `MapEntry`
- [ ] 22.8.1.8 Link entries via `hasEntry` property

### 22.8.2 Struct Literal Extraction
- [ ] 22.8.2.1 Match struct literal: `%StructName{key: value}`
- [ ] 22.8.2.2 Create type triple: `expr_iri a Core.StructLiteral`
- [ ] 22.8.2.3 Extract struct name and link via `hasStructType`
- [ ] 22.8.2.4 Extract struct fields as map entries
- [ ] 22.8.2.5 Create `refersToModule` property for struct type

### 22.8.3 Keyword List Literal Extraction
- [ ] 22.8.3.1 Match keyword list: `[key: value, key2: value2]`
- [ ] 22.8.3.2 Detect keyword list using `Keyword.keyword?/1`
- [ ] 22.8.3.3 Create type triple: `expr_iri a Core.KeywordListLiteral`
- [ ] 22.8.3.4 Extract each key-value pair
- [ ] 22.8.3.5 Store keys as atoms, values as expressions
- [ ] 22.8.3.6 Link via `hasEntry` or similar property

**Section 22.8 Unit Tests:**
- [ ] Test map literal extraction for empty map
- [ ] Test map literal extraction for atom key map
- [ ] Test map literal extraction for string key map
- [ ] Test map literal extraction for mixed key map
- [ ] Test struct literal extraction includes struct name
- [ ] Test struct literal extraction includes fields
- [ ] Test keyword list extraction is distinguished from list
- [ ] Test keyword list extraction preserves key atom types
- [ ] Test keyword list extraction handles duplicate keys

## 22.9 Sigil Literals

This section implements extraction for sigil literals including their modifiers and content.

### 22.9.1 Sigil Literal Extraction
- [ ] 22.9.1.1 Implement `build_sigil_literal/3` for sigil AST nodes
- [ ] 22.9.1.2 Match sigil pattern: `{:sigil_i, _, [content, modifiers]}`
- [ ] 22.9.1.3 Match word sigil: `~w(foo bar baz)`
- [ ] 22.9.1.4 Match regex sigil: `~r/pattern/opts`
- [ ] 22.9.1.5 Match string sigil: `~s(string)`
- [ ] 22.9.1.6 Match custom sigils: `~x(content)`
- [ ] 22.9.1.7 Create type triple: `expr_iri a Core.SigilLiteral`
- [ ] 22.9.1.8 Extract sigil character (`sigilChar` property)
- [ ] 22.9.1.9 Extract sigil content (`sigilContent` property)
- [ ] 22.9.1.10 Extract sigil modifiers as list (`sigilModifiers` property)

**Section 22.9 Unit Tests:**
- [ ] Test sigil literal extraction for word sigil
- [ ] Test sigil literal extraction for regex sigil
- [ ] Test sigil literal extraction for string sigil
- [ ] Test sigil literal extraction for custom sigil
- [ ] Test sigil literal extraction captures sigil character
- [ ] Test sigil literal extraction captures modifiers
- [ ] Test sigil literal extraction handles empty content

## 22.10 Range Literals

This section implements extraction for range literals including step ranges.

### 22.10.1 Range Literal Extraction
- [ ] 22.10.1.1 Implement `build_range_literal/3` for range AST nodes
- [ ] 22.10.1.2 Match simple range: `1..10` (AST: `{:.., _, [first, last]}`)
- [ ] 22.10.1.3 Match step range: `1..10//2` (AST: `{:"..//", _, [first, last, step]}`)
- [ ] 22.10.1.4 Match inclusive ranges
- [ ] 22.10.1.5 Create type triple: `expr_iri a Core.RangeLiteral`
- [ ] 22.10.1.6 Extract first value: `rangeStart` property
- [ ] 22.10.1.7 Extract last value: `rangeEnd` property
- [ ] 22.10.1.8 Extract step value: `rangeStep` property (if present)
- [ ] 22.10.1.9 Handle negative ranges: `10..1`
- [ ] 22.10.1.10 Handle infinite ranges (if representable)

**Section 22.10 Unit Tests:**
- [ ] Test range literal extraction for simple range
- [ ] Test range literal extraction for step range
- [ ] Test range literal extraction captures start
- [ ] Test range literal extraction captures end
- [ ] Test range literal extraction captures step
- [ ] Test range literal extraction for negative ranges
- [ ] Test range literal extraction for single-element ranges

## Phase 22 Integration Tests

- [ ] Test complete literal extraction: atoms, integers, floats, strings
- [ ] Test literal extraction preserves value fidelity in round-trip
- [ ] Test literal extraction handles all literal types in complex expressions
- [ ] Test nested literals (list of tuples, map of lists, etc.)
- [ ] Test light mode skips literal extraction (backward compat)
- [ ] Test full mode includes all literal triples
- [ ] Test SPARQL queries find literals by type
- [ ] Test SPARQL queries find literals by value
- [ ] Test literal IRI generation is deterministic
- [ ] Test all 12 literal types from ontology are extractable

**Integration Test Summary:**
- 10 integration tests covering all literal types
- Tests verify value preservation and RDF generation
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/literal_builder_test.exs`
