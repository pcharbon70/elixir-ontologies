defmodule ElixirOntologies.Builders.CallGraphBuilder do
  @moduledoc """
  Builds RDF triples for function calls.

  This module transforms `ElixirOntologies.Extractors.Call.FunctionCall` results into RDF
  triples following the elixir-core.ttl and elixir-structure.ttl ontologies. It handles:

  - Call type classification (LocalCall, RemoteCall, DynamicCall)
  - Call target properties (name, arity, module)
  - Caller/callee relationships via structure:callsFunction
  - Source location information

  ## Usage

      alias ElixirOntologies.Builders.{CallGraphBuilder, Context}
      alias ElixirOntologies.Extractors.Call.FunctionCall

      call = %FunctionCall{
        type: :remote,
        name: :upcase,
        arity: 1,
        module: [:String],
        arguments: [{:x, [], nil}],
        metadata: %{caller_function: "MyApp/process/1"}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {call_iri, triples} = CallGraphBuilder.build(call, context)

  ## IRI Pattern

  Call IRIs follow the pattern: `{base}call/{caller_iri_fragment}/{index}`

  For example:
  - `https://example.org/code#call/MyApp/process/1/0` (first call in process/1)
  - `https://example.org/code#call/MyApp/process/1/1` (second call in process/1)

  ## Examples

      iex> alias ElixirOntologies.Builders.{CallGraphBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Call.FunctionCall
      iex> call = %FunctionCall{type: :local, name: :helper, arity: 0, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {call_iri, _triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)
      iex> to_string(call_iri)
      "https://example.org/code#call/MyApp/test/0/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Call.FunctionCall
  alias NS.{Core, Structure}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a function call.

  Takes a function call extraction result and builder context, returns the call IRI
  and a list of RDF triples representing the call in the ontology.

  ## Parameters

  - `call` - Function call extraction result from `Extractors.Call`
  - `context` - Builder context with base IRI and configuration
  - `opts` - Options:
    - `:caller_function` - IRI fragment of the calling function (e.g., "MyApp/process/1")
    - `:index` - Call index within the calling function (default: 0)

  ## Returns

  A tuple `{call_iri, triples}` where:
  - `call_iri` - The IRI of the function call
  - `triples` - List of RDF triples describing the call

  ## Examples

      iex> alias ElixirOntologies.Builders.{CallGraphBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Call.FunctionCall
      iex> call = %FunctionCall{type: :remote, name: :get, arity: 2, module: [:Map], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)
      iex> Enum.any?(triples, fn {_, p, _} -> p == RDF.type() end)
      true
  """
  @spec build(FunctionCall.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%FunctionCall{} = call, %Context{} = context, opts \\ []) do
    caller_function = Keyword.get(opts, :caller_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    call_iri = call_iri(context.base_iri, caller_function, index)

    triples =
      []
      |> add_type_triple(call_iri, call.type)
      |> add_name_triple(call_iri, call.name)
      |> add_arity_triple(call_iri, call.arity)
      |> add_module_triple(call_iri, call.module)
      |> add_caller_triple(call_iri, context.base_iri, caller_function)
      |> add_target_triple(call_iri, context, call)
      |> add_location_triples(call_iri, call.location)

    {call_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple function calls.

  Assigns unique indices to each call within the same calling function.

  ## Parameters

  - `calls` - List of function call extraction results
  - `context` - Builder context
  - `opts` - Options:
    - `:caller_function` - IRI fragment of the calling function

  ## Returns

  A tuple `{call_iris, all_triples}` where:
  - `call_iris` - List of IRIs for each call
  - `all_triples` - Combined list of all triples

  ## Examples

      iex> alias ElixirOntologies.Builders.{CallGraphBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Call.FunctionCall
      iex> calls = [
      ...>   %FunctionCall{type: :local, name: :foo, arity: 0, metadata: %{}},
      ...>   %FunctionCall{type: :local, name: :bar, arity: 1, metadata: %{}}
      ...> ]
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iris, _triples} = CallGraphBuilder.build_all(calls, context, caller_function: "MyApp/test/0")
      iex> length(iris)
      2
  """
  @spec build_all([FunctionCall.t()], Context.t(), keyword()) ::
          {[RDF.IRI.t()], [RDF.Triple.t()]}
  def build_all(calls, %Context{} = context, opts \\ []) when is_list(calls) do
    caller_function = Keyword.get(opts, :caller_function, "unknown/0")

    {iris, triples_list} =
      calls
      |> Enum.with_index()
      |> Enum.map(fn {call, index} ->
        build(call, context, caller_function: caller_function, index: index)
      end)
      |> Enum.unzip()

    {iris, List.flatten(triples_list)}
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  @doc """
  Generates an IRI for a function call.

  ## Parameters

  - `base_iri` - Base IRI for the codebase
  - `caller_function` - IRI fragment of the calling function (e.g., "MyApp/process/1")
  - `index` - Index of this call within the function

  ## Examples

      iex> ElixirOntologies.Builders.CallGraphBuilder.call_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#call/MyApp/foo/1/0>

      iex> ElixirOntologies.Builders.CallGraphBuilder.call_iri("https://example.org/code#", "MyApp/bar/2", 5)
      ~I<https://example.org/code#call/MyApp/bar/2/5>
  """
  @spec call_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def call_iri(base_iri, caller_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}call/#{caller_function}/#{index}")
  end

  def call_iri(%RDF.IRI{value: base}, caller_function, index) do
    call_iri(base, caller_function, index)
  end

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  # Add type triple based on call type
  defp add_type_triple(triples, call_iri, :local) do
    [Helpers.type_triple(call_iri, Core.LocalCall) | triples]
  end

  defp add_type_triple(triples, call_iri, :remote) do
    [Helpers.type_triple(call_iri, Core.RemoteCall) | triples]
  end

  defp add_type_triple(triples, call_iri, :dynamic) do
    # Use LocalCall for dynamic as fallback since DynamicCall may not exist
    # In a complete ontology, we'd have a DynamicCall class
    [Helpers.type_triple(call_iri, Core.LocalCall) | triples]
  end

  defp add_type_triple(triples, _call_iri, _type), do: triples

  # Add call name triple (reuse structure:functionName for the called function name)
  defp add_name_triple(triples, call_iri, name) when is_atom(name) do
    triple = Helpers.datatype_property(call_iri, Structure.functionName(), Atom.to_string(name))
    [triple | triples]
  end

  defp add_name_triple(triples, _call_iri, _name), do: triples

  # Add call arity triple (reuse structure:arity for the called function arity)
  defp add_arity_triple(triples, call_iri, arity) when is_integer(arity) do
    triple =
      Helpers.datatype_property(call_iri, Structure.arity(), arity, RDF.XSD.NonNegativeInteger)

    [triple | triples]
  end

  defp add_arity_triple(triples, _call_iri, _arity), do: triples

  # Add target module triple for remote calls (reuse structure:moduleName)
  defp add_module_triple(triples, call_iri, module) when is_list(module) and module != [] do
    module_name = Enum.map_join(module, ".", &Atom.to_string/1)
    triple = Helpers.datatype_property(call_iri, Structure.moduleName(), module_name)
    [triple | triples]
  end

  defp add_module_triple(triples, call_iri, module) when is_atom(module) and not is_nil(module) do
    triple = Helpers.datatype_property(call_iri, Structure.moduleName(), Atom.to_string(module))
    [triple | triples]
  end

  defp add_module_triple(triples, _call_iri, _module), do: triples

  # Add caller function triple (link to the function containing this call)
  defp add_caller_triple(triples, call_iri, base_iri, caller_function)
       when caller_function != "unknown/0" do
    caller_iri = RDF.iri("#{base_iri}#{caller_function}")
    # Use belongsTo to link call to containing function (call belongsTo function)
    triple = Helpers.object_property(call_iri, Structure.belongsTo(), caller_iri)
    [triple | triples]
  end

  defp add_caller_triple(triples, _call_iri, _base_iri, _caller_function), do: triples

  # Add target function triple (for calls to known functions)
  defp add_target_triple(triples, call_iri, context, %FunctionCall{type: :remote} = call) do
    # For remote calls, generate target function IRI
    if call.module && call.name do
      module_name = format_module_name(call.module)
      function_name = Atom.to_string(call.name)
      target_iri = IRI.for_function(context.base_iri, module_name, function_name, call.arity)
      triple = Helpers.object_property(call_iri, Structure.callsFunction(), target_iri)
      [triple | triples]
    else
      triples
    end
  end

  defp add_target_triple(triples, call_iri, context, %FunctionCall{type: :local} = call) do
    # For local calls, we need the module from context metadata or caller_function
    if call.name do
      # Extract module from context metadata if available
      module_name = get_module_from_context(context)

      if module_name do
        function_name = Atom.to_string(call.name)
        target_iri = IRI.for_function(context.base_iri, module_name, function_name, call.arity)
        triple = Helpers.object_property(call_iri, Structure.callsFunction(), target_iri)
        [triple | triples]
      else
        triples
      end
    else
      triples
    end
  end

  defp add_target_triple(triples, _call_iri, _context, _call), do: triples

  # Add location triples if present (using core:startLine)
  defp add_location_triples(triples, call_iri, %{line: line} = _location) when is_integer(line) do
    triple = Helpers.datatype_property(call_iri, Core.startLine(), line, RDF.XSD.PositiveInteger)
    [triple | triples]
  end

  defp add_location_triples(triples, _call_iri, _location), do: triples

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp format_module_name(module) when is_list(module) do
    Enum.map_join(module, ".", &Atom.to_string/1)
  end

  defp format_module_name(module) when is_atom(module) do
    Atom.to_string(module)
  end

  defp get_module_from_context(%Context{metadata: %{module: module}}) when not is_nil(module) do
    format_module_name(module)
  end

  defp get_module_from_context(_context), do: nil
end
