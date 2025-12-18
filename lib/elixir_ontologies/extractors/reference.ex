defmodule ElixirOntologies.Extractors.Reference do
  @moduledoc """
  Extracts variable and reference expressions from AST nodes.

  This module analyzes Elixir AST nodes representing variables, module references,
  function captures, and function calls. Supports all reference types defined in
  the elixir-core.ttl ontology:

  - Variable: `x`, `my_var` - Simple variable references
  - Module Reference: `MyModule`, `MyApp.Users` - Module aliases
  - Function Capture: `&func/1`, `&Mod.func/2` - Captured functions
  - Remote Call: `Module.function(args)` - Calls to module functions
  - Local Call: `function(args)` - Calls to local functions
  - Binding: `x = value` - Variable assignments
  - Pin: `^x` - Pinned variable references

  ## Usage

      iex> alias ElixirOntologies.Extractors.Reference
      iex> {:ok, result} = Reference.extract({:x, [], Elixir})
      iex> result.type
      :variable
      iex> result.name
      :x

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ast = {:__aliases__, [], [:String]}
      iex> {:ok, result} = Reference.extract(ast)
      iex> result.type
      :module
      iex> result.name
      [:String]
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of reference extraction.

  - `:type` - The reference type classification
  - `:name` - Name of the variable, function, or module parts
  - `:module` - Module path for remote calls/captures (list of atoms)
  - `:function` - Function name for calls/captures
  - `:arity` - Arity for function captures
  - `:arguments` - Arguments for function calls
  - `:value` - Right-hand side for bindings
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: reference_type(),
          name: atom() | [atom()] | nil,
          module: [atom()] | atom() | nil,
          function: atom() | nil,
          arity: non_neg_integer() | nil,
          arguments: [Macro.t()] | nil,
          value: Macro.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type reference_type ::
          :variable | :module | :function_capture | :remote_call | :local_call | :binding | :pin

  defstruct [
    :type,
    :name,
    :module,
    :function,
    :arity,
    :arguments,
    :value,
    :location,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a variable.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.variable?({:x, [], Elixir})
      true

      iex> ElixirOntologies.Extractors.Reference.variable?({:my_var, [], nil})
      true

      iex> ElixirOntologies.Extractors.Reference.variable?({:def, [], nil})
      false

      iex> ElixirOntologies.Extractors.Reference.variable?(:atom)
      false

      # By default, underscore-prefixed variables are excluded
      iex> ElixirOntologies.Extractors.Reference.variable?({:_reason, [], nil})
      false

      # Use include_underscored: true to include them
      iex> ElixirOntologies.Extractors.Reference.variable?({:_reason, [], nil}, include_underscored: true)
      true

      # The single underscore wildcard is always excluded
      iex> ElixirOntologies.Extractors.Reference.variable?({:_, [], nil}, include_underscored: true)
      false
  """
  @spec variable?(Macro.t(), keyword()) :: boolean()
  def variable?(node, opts \\ [])

  def variable?({name, _meta, context}, opts) when is_atom(name) and is_atom(context) do
    include_underscored = Keyword.get(opts, :include_underscored, false)
    name_str = Atom.to_string(name)

    cond do
      Helpers.special_form?(name) -> false
      # Single underscore is always excluded (true wildcard)
      name == :_ -> false
      # Other underscore-prefixed variables depend on option
      String.starts_with?(name_str, "_") -> include_underscored
      true -> true
    end
  end

  def variable?(_, _opts), do: false

  @doc """
  Checks if an AST node represents a module reference.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.module_reference?({:__aliases__, [], [:MyModule]})
      true

      iex> ElixirOntologies.Extractors.Reference.module_reference?({:__aliases__, [], [:MyApp, :Users]})
      true

      iex> ElixirOntologies.Extractors.Reference.module_reference?({:x, [], nil})
      false
  """
  @spec module_reference?(Macro.t()) :: boolean()
  def module_reference?({:__aliases__, _meta, parts}) when is_list(parts), do: true
  def module_reference?(_), do: false

  @doc """
  Checks if an AST node represents a function capture.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.function_capture?({:&, [], [{:/, [], [{:func, [], nil}, 1]}]})
      true

      iex> ElixirOntologies.Extractors.Reference.function_capture?({:&, [], [1]})
      true

      iex> ElixirOntologies.Extractors.Reference.function_capture?({:x, [], nil})
      false
  """
  @spec function_capture?(Macro.t()) :: boolean()
  def function_capture?({:&, _meta, [_expr]}), do: true
  def function_capture?(_), do: false

  @doc """
  Checks if an AST node represents a remote call (Module.function(args)).

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.remote_call?({{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hi"]})
      true

      iex> ElixirOntologies.Extractors.Reference.remote_call?({{:., [], [:erlang, :now]}, [], []})
      true

      iex> ElixirOntologies.Extractors.Reference.remote_call?({:my_func, [], [1]})
      false
  """
  @spec remote_call?(Macro.t()) :: boolean()
  def remote_call?({{:., _meta1, [_module, _function]}, _meta2, args}) when is_list(args),
    do: true

  def remote_call?(_), do: false

  @doc """
  Checks if an AST node represents a local call (function(args)).

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.local_call?({:my_func, [], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Reference.local_call?({:puts, [], ["hello"]})
      true

      iex> ElixirOntologies.Extractors.Reference.local_call?({:x, [], Elixir})
      false
  """
  @spec local_call?(Macro.t()) :: boolean()
  def local_call?({name, _meta, args}) when is_atom(name) and is_list(args) do
    not Helpers.special_form?(name)
  end

  def local_call?(_), do: false

  @doc """
  Checks if an AST node represents a variable binding.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.binding?({:=, [], [{:x, [], nil}, 1]})
      true

      iex> ElixirOntologies.Extractors.Reference.binding?({:x, [], nil})
      false
  """
  @spec binding?(Macro.t()) :: boolean()
  def binding?({:=, _meta, [_pattern, _value]}), do: true
  def binding?(_), do: false

  @doc """
  Checks if an AST node represents a pin operator.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.pin?({:^, [], [{:x, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Reference.pin?({:x, [], nil})
      false
  """
  @spec pin?(Macro.t()) :: boolean()
  def pin?({:^, _meta, [{_name, _var_meta, _context}]}), do: true
  def pin?(_), do: false

  @doc """
  Returns the reference type of an AST node, or `nil` if not a reference.

  ## Options

  - `:include_underscored` - If true, treat `_`-prefixed variables (except `_`) as variables.
    Defaults to `false`.

  ## Examples

      iex> ElixirOntologies.Extractors.Reference.reference_type({:x, [], Elixir})
      :variable

      iex> ElixirOntologies.Extractors.Reference.reference_type({:__aliases__, [], [:MyModule]})
      :module

      iex> ElixirOntologies.Extractors.Reference.reference_type({:=, [], [{:x, [], nil}, 1]})
      :binding

      iex> ElixirOntologies.Extractors.Reference.reference_type(123)
      nil

      iex> ElixirOntologies.Extractors.Reference.reference_type({:_reason, [], nil})
      nil

      iex> ElixirOntologies.Extractors.Reference.reference_type({:_reason, [], nil}, include_underscored: true)
      :variable
  """
  @spec reference_type(Macro.t(), keyword()) :: reference_type() | nil
  def reference_type(node, opts \\ []) do
    cond do
      pin?(node) -> :pin
      binding?(node) -> :binding
      function_capture?(node) -> :function_capture
      remote_call?(node) -> :remote_call
      module_reference?(node) -> :module
      local_call?(node) -> :local_call
      variable?(node, opts) -> :variable
      true -> nil
    end
  end

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a reference from an AST node.

  Returns `{:ok, %Reference{}}` on success, or `{:error, reason}` if the node
  is not a recognized reference type.

  ## Options

  - `:include_underscored` - If true, treat `_`-prefixed variables (except `_`) as variables.
    Defaults to `false`.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.Reference.extract({:x, [], Elixir})
      iex> result.type
      :variable
      iex> result.name
      :x

      iex> {:ok, result} = ElixirOntologies.Extractors.Reference.extract({:__aliases__, [], [:String]})
      iex> result.type
      :module
      iex> result.name
      [:String]

      iex> {:error, _} = ElixirOntologies.Extractors.Reference.extract(123)

      # Underscore-prefixed variables with option
      iex> {:ok, result} = ElixirOntologies.Extractors.Reference.extract({:_reason, [], nil}, include_underscored: true)
      iex> result.type
      :variable
      iex> result.name
      :_reason
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ []) do
    case reference_type(node, opts) do
      nil -> {:error, Helpers.format_error("Not a reference", node)}
      :variable -> {:ok, extract_variable(node)}
      :module -> {:ok, extract_module(node)}
      :function_capture -> {:ok, extract_function_capture(node)}
      :remote_call -> {:ok, extract_remote_call(node)}
      :local_call -> {:ok, extract_local_call(node)}
      :binding -> {:ok, extract_binding(node)}
      :pin -> {:ok, extract_pin(node)}
    end
  end

  @doc """
  Extracts a reference, raising on error.

  ## Options

  - `:include_underscored` - If true, treat `_`-prefixed variables (except `_`) as variables.
    Defaults to `false`.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract!({:x, [], Elixir})
      iex> result.type
      :variable
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Type-Specific Extractors
  # ===========================================================================

  @doc """
  Extracts a variable reference.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract_variable({:my_var, [], Elixir})
      iex> result.name
      :my_var
      iex> result.type
      :variable
  """
  @spec extract_variable(Macro.t()) :: t()
  def extract_variable({name, _meta, context} = node) when is_atom(name) and is_atom(context) do
    %__MODULE__{
      type: :variable,
      name: name,
      location: Helpers.extract_location(node),
      metadata: %{
        context: context
      }
    }
  end

  @doc """
  Extracts a module reference.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract_module({:__aliases__, [], [:MyApp, :Users]})
      iex> result.name
      [:MyApp, :Users]
      iex> result.metadata.full_name
      "MyApp.Users"
  """
  @spec extract_module(Macro.t()) :: t()
  def extract_module({:__aliases__, _meta, parts} = node) when is_list(parts) do
    %__MODULE__{
      type: :module,
      name: parts,
      module: parts,
      location: Helpers.extract_location(node),
      metadata: %{
        full_name: Enum.join(parts, "."),
        depth: length(parts)
      }
    }
  end

  @doc """
  Extracts a function capture.

  ## Examples

      iex> ast = {:&, [], [{:/, [], [{:func, [], nil}, 2]}]}
      iex> result = ElixirOntologies.Extractors.Reference.extract_function_capture(ast)
      iex> result.type
      :function_capture
      iex> result.function
      :func
      iex> result.arity
      2
      iex> result.metadata.capture_type
      :local
  """
  @spec extract_function_capture(Macro.t()) :: t()
  def extract_function_capture({:&, _meta, [expr]} = node) do
    capture_info = analyze_capture(expr)

    %__MODULE__{
      type: :function_capture,
      name: capture_info.function,
      module: capture_info.module,
      function: capture_info.function,
      arity: capture_info.arity,
      location: Helpers.extract_location(node),
      metadata: %{
        capture_type: capture_info.capture_type,
        is_remote: capture_info.module != nil
      }
    }
  end

  @doc """
  Extracts a remote call.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> result = ElixirOntologies.Extractors.Reference.extract_remote_call(ast)
      iex> result.type
      :remote_call
      iex> result.module
      [:String]
      iex> result.function
      :upcase
      iex> result.arguments
      ["hello"]
  """
  @spec extract_remote_call(Macro.t()) :: t()
  def extract_remote_call({{:., _dot_meta, [module_ast, function]}, _meta, args} = node)
      when is_atom(function) and is_list(args) do
    module = extract_module_from_ast(module_ast)

    %__MODULE__{
      type: :remote_call,
      name: function,
      module: module,
      function: function,
      arity: length(args),
      arguments: args,
      location: Helpers.extract_location(node),
      metadata: %{
        is_erlang: is_atom(module_ast),
        full_call: format_call(module, function, length(args))
      }
    }
  end

  @doc """
  Extracts a local call.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract_local_call({:my_func, [], [1, 2, 3]})
      iex> result.type
      :local_call
      iex> result.function
      :my_func
      iex> result.arity
      3
  """
  @spec extract_local_call(Macro.t()) :: t()
  def extract_local_call({name, _meta, args} = node) when is_atom(name) and is_list(args) do
    %__MODULE__{
      type: :local_call,
      name: name,
      function: name,
      arity: length(args),
      arguments: args,
      location: Helpers.extract_location(node),
      metadata: %{
        full_call: "#{name}/#{length(args)}"
      }
    }
  end

  @doc """
  Extracts a variable binding.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract_binding({:=, [], [{:x, [], nil}, 42]})
      iex> result.type
      :binding
      iex> result.name
      :x
      iex> result.value
      42
  """
  @spec extract_binding(Macro.t()) :: t()
  def extract_binding({:=, _meta, [pattern, value]} = node) do
    bound_name = extract_bound_name(pattern)

    %__MODULE__{
      type: :binding,
      name: bound_name,
      value: value,
      location: Helpers.extract_location(node),
      metadata: %{
        pattern: pattern,
        # Would require scope analysis
        is_rebinding: false
      }
    }
  end

  @doc """
  Extracts a pin operator.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Reference.extract_pin({:^, [], [{:x, [], nil}]})
      iex> result.type
      :pin
      iex> result.name
      :x
  """
  @spec extract_pin(Macro.t()) :: t()
  def extract_pin({:^, _meta, [{name, _var_meta, _context}]} = node) when is_atom(name) do
    %__MODULE__{
      type: :pin,
      name: name,
      location: Helpers.extract_location(node),
      metadata: %{
        pinned_variable: name
      }
    }
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns true if the reference is a remote call or remote capture.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :remote_call, module: [:String]}
      iex> Reference.remote?(ref)
      true

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :local_call}
      iex> Reference.remote?(ref)
      false
  """
  @spec remote?(t()) :: boolean()
  def remote?(%__MODULE__{type: :remote_call}), do: true
  def remote?(%__MODULE__{type: :function_capture, module: mod}) when mod != nil, do: true
  def remote?(_), do: false

  @doc """
  Returns true if the reference is a function call (local or remote).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :local_call}
      iex> Reference.call?(ref)
      true

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :variable}
      iex> Reference.call?(ref)
      false
  """
  @spec call?(t()) :: boolean()
  def call?(%__MODULE__{type: type}) when type in [:local_call, :remote_call], do: true
  def call?(_), do: false

  @doc """
  Returns the full module path as a string.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :module, module: [:MyApp, :Users, :Account]}
      iex> Reference.module_string(ref)
      "MyApp.Users.Account"

      iex> alias ElixirOntologies.Extractors.Reference
      iex> ref = %Reference{type: :remote_call, module: :erlang}
      iex> Reference.module_string(ref)
      ":erlang"
  """
  @spec module_string(t()) :: String.t() | nil
  def module_string(%__MODULE__{module: module}) when is_list(module) do
    Enum.join(module, ".")
  end

  def module_string(%__MODULE__{module: module}) when is_atom(module) and module != nil do
    inspect(module)
  end

  def module_string(_), do: nil

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Analyze a capture expression to extract function info
  defp analyze_capture({:/, _meta, [func_ref, arity]}) when is_integer(arity) do
    case func_ref do
      # Remote capture: &Mod.func/n
      {{:., _, [module_ast, function]}, _, _} ->
        %{
          capture_type: :remote,
          module: extract_module_from_ast(module_ast),
          function: function,
          arity: arity
        }

      # Local capture: &func/n
      {name, _, _} when is_atom(name) ->
        %{
          capture_type: :local,
          module: nil,
          function: name,
          arity: arity
        }

      _ ->
        %{capture_type: :unknown, module: nil, function: nil, arity: arity}
    end
  end

  # Anonymous capture: &(&1 + &2)
  defp analyze_capture(_expr) do
    %{
      capture_type: :anonymous,
      module: nil,
      function: nil,
      arity: nil
    }
  end

  # Extract module from AST (handles both Elixir and Erlang modules)
  defp extract_module_from_ast({:__aliases__, _meta, parts}), do: parts
  defp extract_module_from_ast(atom) when is_atom(atom), do: atom
  defp extract_module_from_ast(_), do: nil

  @max_recursion_depth 100

  # Extract the bound variable name from a pattern (with depth limit)
  defp extract_bound_name(pattern), do: extract_bound_name(pattern, 0)

  defp extract_bound_name(_pattern, depth) when depth > @max_recursion_depth, do: nil

  defp extract_bound_name({name, _meta, context}, _depth)
       when is_atom(name) and is_atom(context) do
    name
  end

  defp extract_bound_name({:=, _meta, [left, _right]}, depth) do
    # For nested matches like `{:ok, x} = result`, get innermost binding
    extract_bound_name(left, depth + 1)
  end

  defp extract_bound_name(tuple, _depth) when is_tuple(tuple) do
    # For tuple patterns, return nil (complex pattern)
    nil
  end

  defp extract_bound_name(_, _depth), do: nil

  # Format a full call string
  defp format_call(module, function, arity) when is_list(module) do
    "#{Enum.join(module, ".")}.#{function}/#{arity}"
  end

  defp format_call(module, function, arity) when is_atom(module) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  defp format_call(nil, function, arity), do: "#{function}/#{arity}"
end
