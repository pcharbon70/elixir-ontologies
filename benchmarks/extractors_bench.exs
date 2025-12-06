# Benchmarks for Phase 3 Extractors
#
# Run with: mix run benchmarks/extractors_bench.exs
#
# This establishes baseline performance metrics for all extractors.

alias ElixirOntologies.Extractors.{
  Literal,
  Operator,
  Pattern,
  ControlFlow,
  Comprehension,
  Block,
  Reference
}

# ============================================================================
# Sample AST Nodes
# ============================================================================

# Literals
atom_literal = :ok
integer_literal = 42
float_literal = 3.14159
string_literal = "hello world"
list_literal = [1, 2, 3, 4, 5]
map_literal = {:%{}, [], [a: 1, b: 2, c: 3]}
keyword_list = [name: "John", age: 30]
tuple_literal = {:ok, :value}

# Operators
binary_op = {:+, [], [1, 2]}
comparison_op = {:==, [], [{:x, [], nil}, 0]}
pipe_op = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}
match_op = {:=, [], [{:x, [], nil}, 42]}
unary_op = {:not, [], [true]}

# Patterns
variable_pattern = {:x, [], Elixir}
wildcard_pattern = {:_, [], Elixir}
pin_pattern = {:^, [], [{:x, [], Elixir}]}
tuple_pattern = {:ok, {:value, [], Elixir}}
list_pattern = [{:head, [], nil}, {:|, [], [{:h, [], nil}, {:t, [], nil}]}]
map_pattern = {:%{}, [], [key: {:v, [], nil}]}
struct_pattern = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:n, [], nil}]}]}

# Control Flow
if_expr = {:if, [], [{:>, [], [{:x, [], nil}, 0]}, [do: :positive, else: :negative]]}
case_expr = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:ok], :success]}, {:->, [], [[{:_, [], nil}], :fallback]}]]]}
cond_expr = {:cond, [], [[do: [{:->, [], [[{:>, [], [{:x, [], nil}, 0]}], :positive]}, {:->, [], [[true], :zero_or_negative]}]]]}
with_expr = {:with, [], [{:<-, [], [{:ok, {:x, [], nil}}, {:fetch, [], []}]}, [do: {:x, [], nil}]]}

# Comprehensions
simple_for = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:x, [], nil}]]}
for_with_filter = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, {:>, [], [{:x, [], nil}, 1]}, [do: {:x, [], nil}]]}
nested_for = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2]]}, {:<-, [], [{:y, [], nil}, [3, 4]]}, [do: {:*, [], [{:x, [], nil}, {:y, [], nil}]}]]}

# Blocks
simple_block = {:__block__, [], [1, 2, 3]}
multi_expr_block = {:__block__, [], [{:=, [], [{:x, [], nil}, 1]}, {:=, [], [{:y, [], nil}, 2]}, {:+, [], [{:x, [], nil}, {:y, [], nil}]}]}
fn_expr = {:fn, [], [{:->, [], [[{:x, [], nil}], {:*, [], [{:x, [], nil}, 2]}]}]}
multi_clause_fn = {:fn, [], [{:->, [], [[0], :zero]}, {:->, [], [[{:n, [], nil}], {:n, [], nil}]}]}

# References
variable_ref = {:x, [], Elixir}
module_ref = {:__aliases__, [], [:String]}
nested_module_ref = {:__aliases__, [], [:MyApp, :Users, :Account]}
local_call = {:foo, [], [1, 2, 3]}
remote_call = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
function_capture = {:&, [], [{:/, [], [{:length, [], nil}, 1]}]}
binding = {:=, [], [{:x, [], nil}, 42]}

# ============================================================================
# Run Benchmarks
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Phase 3 Extractors Benchmark Suite")
IO.puts(String.duplicate("=", 60) <> "\n")

Benchee.run(
  %{
    # Literal Extractors
    "Literal.extract (atom)" => fn -> Literal.extract(atom_literal) end,
    "Literal.extract (integer)" => fn -> Literal.extract(integer_literal) end,
    "Literal.extract (float)" => fn -> Literal.extract(float_literal) end,
    "Literal.extract (string)" => fn -> Literal.extract(string_literal) end,
    "Literal.extract (list)" => fn -> Literal.extract(list_literal) end,
    "Literal.extract (map)" => fn -> Literal.extract(map_literal) end,
    "Literal.extract (keyword)" => fn -> Literal.extract(keyword_list) end,
    "Literal.extract (tuple)" => fn -> Literal.extract(tuple_literal) end,

    # Operator Extractors
    "Operator.extract (binary)" => fn -> Operator.extract(binary_op) end,
    "Operator.extract (comparison)" => fn -> Operator.extract(comparison_op) end,
    "Operator.extract (pipe)" => fn -> Operator.extract(pipe_op) end,
    "Operator.extract (match)" => fn -> Operator.extract(match_op) end,
    "Operator.extract (unary)" => fn -> Operator.extract(unary_op) end,

    # Pattern Extractors
    "Pattern.extract (variable)" => fn -> Pattern.extract(variable_pattern) end,
    "Pattern.extract (wildcard)" => fn -> Pattern.extract(wildcard_pattern) end,
    "Pattern.extract (pin)" => fn -> Pattern.extract(pin_pattern) end,
    "Pattern.extract (tuple)" => fn -> Pattern.extract(tuple_pattern) end,
    "Pattern.extract (list)" => fn -> Pattern.extract(list_pattern) end,
    "Pattern.extract (map)" => fn -> Pattern.extract(map_pattern) end,
    "Pattern.extract (struct)" => fn -> Pattern.extract(struct_pattern) end,

    # Control Flow Extractors
    "ControlFlow.extract (if)" => fn -> ControlFlow.extract(if_expr) end,
    "ControlFlow.extract (case)" => fn -> ControlFlow.extract(case_expr) end,
    "ControlFlow.extract (cond)" => fn -> ControlFlow.extract(cond_expr) end,
    "ControlFlow.extract (with)" => fn -> ControlFlow.extract(with_expr) end,

    # Comprehension Extractors
    "Comprehension.extract (simple)" => fn -> Comprehension.extract(simple_for) end,
    "Comprehension.extract (filter)" => fn -> Comprehension.extract(for_with_filter) end,
    "Comprehension.extract (nested)" => fn -> Comprehension.extract(nested_for) end,

    # Block Extractors
    "Block.extract (simple)" => fn -> Block.extract(simple_block) end,
    "Block.extract (multi-expr)" => fn -> Block.extract(multi_expr_block) end,
    "Block.extract (fn)" => fn -> Block.extract(fn_expr) end,
    "Block.extract (multi-clause fn)" => fn -> Block.extract(multi_clause_fn) end,

    # Reference Extractors
    "Reference.extract (variable)" => fn -> Reference.extract(variable_ref) end,
    "Reference.extract (module)" => fn -> Reference.extract(module_ref) end,
    "Reference.extract (nested module)" => fn -> Reference.extract(nested_module_ref) end,
    "Reference.extract (local call)" => fn -> Reference.extract(local_call) end,
    "Reference.extract (remote call)" => fn -> Reference.extract(remote_call) end,
    "Reference.extract (capture)" => fn -> Reference.extract(function_capture) end,
    "Reference.extract (binding)" => fn -> Reference.extract(binding) end
  },
  warmup: 1,
  time: 3,
  print: [
    benchmarking: true,
    fast_warning: false,
    configuration: true
  ],
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Benchmark Complete")
IO.puts(String.duplicate("=", 60) <> "\n")
