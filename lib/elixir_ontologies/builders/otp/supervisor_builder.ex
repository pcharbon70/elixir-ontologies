defmodule ElixirOntologies.Builders.OTP.SupervisorBuilder do
  @moduledoc """
  Builds RDF triples for OTP Supervisor implementations.

  This module transforms `ElixirOntologies.Extractors.OTP.Supervisor` results into RDF
  triples following the elixir-otp.ttl ontology. It handles:

  - Supervisor implementations (use Supervisor vs @behaviour Supervisor)
  - DynamicSupervisor implementations
  - Supervision strategies (one_for_one, one_for_all, rest_for_one)
  - Child specifications
  - Restart and shutdown strategies

  ## Supervision Patterns

  **Supervisor**: Static process supervision with predefined children
  **DynamicSupervisor**: Dynamic supervision for runtime child management

  **Supervision Strategies**:
  - :one_for_one - Restart only the failed child
  - :one_for_all - Restart all children if one fails
  - :rest_for_one - Restart failed child and all started after it

  ## Usage

      alias ElixirOntologies.Builders.OTP.{SupervisorBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.Supervisor

      # Build Supervisor implementation
      supervisor_info = %Supervisor{
        supervisor_type: :supervisor,
        detection_method: :use,
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#MySupervisor>
      context = Context.new(base_iri: "https://example.org/code#")
      {supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor
      iex> supervisor_info = %Supervisor{
      ...>   supervisor_type: :supervisor,
      ...>   detection_method: :use,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {supervisor_iri, _triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
      iex> to_string(supervisor_iri)
      "https://example.org/code#MySup"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.Supervisor
  alias NS.{OTP, Core}

  # OTP default values for supervision strategies
  # See: https://hexdocs.pm/elixir/Supervisor.html#module-options
  @otp_default_max_restarts 3
  @otp_default_max_seconds 5

  # ===========================================================================
  # Public API - Supervisor Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a Supervisor implementation.

  ## Parameters

  - `supervisor_info` - Supervisor extraction result
  - `module_iri` - The IRI of the module implementing Supervisor
  - `context` - Builder context

  ## Returns

  A tuple `{supervisor_iri, triples}` where:
  - `supervisor_iri` - The IRI of the Supervisor (same as module_iri)
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor
      iex> supervisor_info = %Supervisor{
      ...>   supervisor_type: :supervisor,
      ...>   detection_method: :use,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^supervisor_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_supervisor(Supervisor.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_supervisor(supervisor_info, module_iri, context) do
    # Supervisor IRI is the same as module IRI
    supervisor_iri = module_iri

    # Build all triples
    triples =
      [
        # Core Supervisor triples
        build_type_triple(supervisor_iri, supervisor_info.supervisor_type),
        build_implements_otp_behaviour_triple(supervisor_iri, supervisor_info.supervisor_type)
      ] ++
        build_location_triple(supervisor_iri, supervisor_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {supervisor_iri, triples}
  end

  # ===========================================================================
  # Public API - Supervision Strategy Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a supervision strategy.

  ## Parameters

  - `strategy_info` - Strategy extraction result
  - `supervisor_iri` - The IRI of the supervisor
  - `_context` - Builder context (unused currently)

  ## Returns

  A tuple `{strategy_iri, triples}` where:
  - `strategy_iri` - The IRI of the strategy (predefined individual)
  - `triples` - List of RDF triples
  """
  @spec build_strategy(Supervisor.Strategy.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_strategy(strategy_info, supervisor_iri, _context) do
    # Strategy IRI is a predefined individual
    strategy_iri = determine_strategy_iri(strategy_info.type)

    # Build triples
    triples = [
      # Link supervisor to strategy
      Helpers.object_property(supervisor_iri, OTP.hasStrategy(), strategy_iri)
    ]

    {strategy_iri, triples}
  end

  @doc """
  Builds RDF triples for a complete supervision strategy including restart intensity.

  This function generates:
  - `otp:hasStrategy` linking supervisor to the strategy individual (OneForOne, etc.)
  - `otp:maxRestarts` with the restart limit (on supervisor)
  - `otp:maxSeconds` with the time window (on supervisor)

  ## Parameters

  - `strategy_info` - Strategy extraction result with type and restart intensity
  - `supervisor_iri` - The IRI of the supervisor
  - `_context` - Builder context (unused currently)

  ## Returns

  A tuple `{strategy_iri, triples}` where:
  - `strategy_iri` - The IRI of the strategy individual
  - `triples` - List of RDF triples including restart intensity

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
      iex> strategy = %Strategy{type: :one_for_one, max_restarts: 5, max_seconds: 10}
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {strategy_iri, triples} = SupervisorBuilder.build_supervision_strategy(strategy, supervisor_iri, context)
      iex> to_string(strategy_iri) =~ "OneForOne"
      true
      iex> length(triples) >= 3
      true
  """
  @spec build_supervision_strategy(Supervisor.Strategy.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_supervision_strategy(strategy_info, supervisor_iri, _context) do
    # Strategy IRI is a predefined individual
    strategy_iri = determine_strategy_iri(strategy_info.type)

    # Calculate effective values (use OTP defaults if not explicitly set)
    max_restarts = effective_max_restarts(strategy_info)
    max_seconds = effective_max_seconds(strategy_info)

    # Build triples
    triples = [
      # Link supervisor to strategy individual
      Helpers.object_property(supervisor_iri, OTP.hasStrategy(), strategy_iri),

      # Restart intensity on supervisor (per ontology: domain is Supervisor)
      Helpers.datatype_property(supervisor_iri, OTP.maxRestarts(), max_restarts),
      Helpers.datatype_property(supervisor_iri, OTP.maxSeconds(), max_seconds)
    ]

    {strategy_iri, triples}
  end

  # Calculate effective max_restarts using OTP default
  defp effective_max_restarts(%{max_restarts: nil}), do: @otp_default_max_restarts
  defp effective_max_restarts(%{max_restarts: value}), do: value

  # Calculate effective max_seconds using OTP default
  defp effective_max_seconds(%{max_seconds: nil}), do: @otp_default_max_seconds
  defp effective_max_seconds(%{max_seconds: value}), do: value

  # ===========================================================================
  # Supervisor Implementation Triple Generation
  # ===========================================================================

  # Build rdf:type triple for Supervisor or DynamicSupervisor
  defp build_type_triple(supervisor_iri, :supervisor) do
    Helpers.type_triple(supervisor_iri, OTP.Supervisor)
  end

  defp build_type_triple(supervisor_iri, :dynamic_supervisor) do
    Helpers.type_triple(supervisor_iri, OTP.DynamicSupervisor)
  end

  # Build otp:implementsOTPBehaviour triple
  defp build_implements_otp_behaviour_triple(supervisor_iri, :supervisor) do
    Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour)
  end

  defp build_implements_otp_behaviour_triple(supervisor_iri, :dynamic_supervisor) do
    Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour)
  end

  # Build location triple if present
  defp build_location_triple(_supervisor_iri, nil, _context), do: []
  defp build_location_triple(_supervisor_iri, _location, %Context{file_path: nil}), do: []

  defp build_location_triple(supervisor_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(supervisor_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # Strategy Triple Generation
  # ===========================================================================

  # Determine strategy IRI (predefined individuals from ontology)
  defp determine_strategy_iri(:one_for_one), do: OTP.OneForOne
  defp determine_strategy_iri(:one_for_all), do: OTP.OneForAll
  defp determine_strategy_iri(:rest_for_one), do: OTP.RestForOne

  # ===========================================================================
  # Public API - Child Spec Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a child specification.

  ## Parameters

  - `child_spec` - ChildSpec extraction result
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context
  - `index` - Position in children list (default: 0)

  ## Returns

  A tuple `{child_spec_iri, triples}` where:
  - `child_spec_iri` - The IRI of the child spec
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> child_spec = %ChildSpec{
      ...>   id: :worker1,
      ...>   module: MyWorker,
      ...>   restart: :permanent,
      ...>   type: :worker
      ...> }
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {child_spec_iri, triples} = SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)
      iex> to_string(child_spec_iri) =~ "MySup/child/worker1/0"
      true
      iex> Enum.any?(triples, fn {_, pred, _} -> pred == RDF.type() end)
      true
  """
  @spec build_child_spec(Supervisor.ChildSpec.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_child_spec(child_spec, supervisor_iri, _context, index \\ 0) do
    # Generate child spec IRI
    child_id = child_spec.id || child_spec.module || :unknown
    child_spec_iri = IRI.for_child_spec(supervisor_iri, child_id, index)

    # Build all triples
    triples =
      [
        # Type triple
        Helpers.type_triple(child_spec_iri, OTP.ChildSpec),

        # Link supervisor to child spec
        Helpers.object_property(supervisor_iri, OTP.hasChildSpec(), child_spec_iri),

        # Child ID
        build_child_id_triple(child_spec_iri, child_id),

        # Start function
        build_start_module_triple(child_spec_iri, child_spec),
        build_start_function_triple(child_spec_iri, child_spec),

        # Restart strategy
        build_restart_strategy_triple(child_spec_iri, child_spec.restart),

        # Child type
        build_child_type_triple(child_spec_iri, child_spec.type)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {child_spec_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple child specifications.

  Iterates through a list of ChildSpec structs and builds triples for each,
  using the list position as the index.

  ## Parameters

  - `child_specs` - List of ChildSpec extraction results
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context

  ## Returns

  A tuple `{child_spec_iris, all_triples}` where:
  - `child_spec_iris` - List of IRIs for all child specs
  - `all_triples` - Combined list of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> specs = [
      ...>   %ChildSpec{id: :worker1, module: Worker1, restart: :permanent, type: :worker},
      ...>   %ChildSpec{id: :worker2, module: Worker2, restart: :temporary, type: :worker}
      ...> ]
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iris, triples} = SupervisorBuilder.build_child_specs(specs, supervisor_iri, context)
      iex> length(iris)
      2
      iex> length(triples) > 0
      true
  """
  @spec build_child_specs([Supervisor.ChildSpec.t()], RDF.IRI.t(), Context.t()) ::
          {[RDF.IRI.t()], [RDF.Triple.t()]}
  def build_child_specs(child_specs, supervisor_iri, context) when is_list(child_specs) do
    {iris, triples_list} =
      child_specs
      |> Enum.with_index()
      |> Enum.map(fn {spec, index} ->
        build_child_spec(spec, supervisor_iri, context, index)
      end)
      |> Enum.unzip()

    {iris, List.flatten(triples_list)}
  end

  # ===========================================================================
  # Child Spec Triple Generation
  # ===========================================================================

  # Build child ID triple
  defp build_child_id_triple(child_spec_iri, child_id) do
    id_string = format_id_for_literal(child_id)
    Helpers.datatype_property(child_spec_iri, OTP.childId(), id_string)
  end

  # Build start module triple
  defp build_start_module_triple(_child_spec_iri, %{start: nil}), do: nil
  defp build_start_module_triple(_child_spec_iri, %{module: nil, start: %{module: nil}}), do: nil

  defp build_start_module_triple(child_spec_iri, %{start: %{module: module}}) when not is_nil(module) do
    module_string = format_id_for_literal(module)
    Helpers.datatype_property(child_spec_iri, OTP.startModule(), module_string)
  end

  defp build_start_module_triple(child_spec_iri, %{module: module}) when not is_nil(module) do
    module_string = format_id_for_literal(module)
    Helpers.datatype_property(child_spec_iri, OTP.startModule(), module_string)
  end

  defp build_start_module_triple(_, _), do: nil

  # Build start function triple
  defp build_start_function_triple(_child_spec_iri, %{start: nil}), do: nil
  defp build_start_function_triple(_child_spec_iri, %{start: %{function: nil}}), do: nil

  defp build_start_function_triple(child_spec_iri, %{start: %{function: function}}) when not is_nil(function) do
    function_string = Atom.to_string(function)
    Helpers.datatype_property(child_spec_iri, OTP.startFunction(), function_string)
  end

  defp build_start_function_triple(_, _), do: nil

  # Build restart strategy triple
  defp build_restart_strategy_triple(child_spec_iri, restart_type) do
    restart_iri = determine_restart_strategy_iri(restart_type)
    Helpers.object_property(child_spec_iri, OTP.hasRestartStrategy(), restart_iri)
  end

  # Build child type triple
  defp build_child_type_triple(child_spec_iri, child_type) do
    type_iri = determine_child_type_iri(child_type)
    Helpers.object_property(child_spec_iri, OTP.hasChildType(), type_iri)
  end

  # Determine restart strategy IRI (predefined individuals from ontology)
  defp determine_restart_strategy_iri(:permanent), do: OTP.Permanent
  defp determine_restart_strategy_iri(:temporary), do: OTP.Temporary
  defp determine_restart_strategy_iri(:transient), do: OTP.Transient
  defp determine_restart_strategy_iri(_), do: OTP.Permanent

  # Determine child type IRI (predefined individuals from ontology)
  defp determine_child_type_iri(:worker), do: OTP.WorkerType
  defp determine_child_type_iri(:supervisor), do: OTP.SupervisorType
  defp determine_child_type_iri(_), do: OTP.WorkerType

  # Format ID for RDF literal (atom, module, or other term)
  defp format_id_for_literal(id) when is_atom(id) do
    id |> Atom.to_string() |> String.replace("Elixir.", "")
  end

  defp format_id_for_literal(id), do: inspect(id)

  # ===========================================================================
  # Public API - Supervision Tree Building
  # ===========================================================================

  @doc """
  Builds RDF triples for supervision relationships.

  Generates `otp:supervises` and `otp:supervisedBy` triples linking the supervisor
  to its child modules.

  ## Parameters

  - `child_specs` - List of ChildSpec structs
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context

  ## Returns

  A list of RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> specs = [%ChildSpec{id: :worker1, module: MyWorker}]
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = SupervisorBuilder.build_supervision_relationships(specs, supervisor_iri, context)
      iex> length(triples) > 0
      true
  """
  @spec build_supervision_relationships([Supervisor.ChildSpec.t()], RDF.IRI.t(), Context.t()) ::
          [RDF.Triple.t()]
  def build_supervision_relationships(child_specs, supervisor_iri, context) when is_list(child_specs) do
    child_specs
    |> Enum.flat_map(fn child_spec ->
      build_child_supervision_triples(child_spec, supervisor_iri, context)
    end)
  end

  # Build supervision triples for a single child
  defp build_child_supervision_triples(child_spec, supervisor_iri, context) do
    module = child_spec.module

    if module do
      child_module_iri = IRI.for_module(context.base_iri, format_module_name(module))

      [
        # Supervisor supervises child module
        Helpers.object_property(supervisor_iri, OTP.supervises(), child_module_iri),
        # Child module is supervised by supervisor (inverse)
        Helpers.object_property(child_module_iri, OTP.supervisedBy(), supervisor_iri)
      ]
    else
      []
    end
  end

  # Format module name for IRI generation
  defp format_module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace("Elixir.", "")
  end

  defp format_module_name(module), do: inspect(module)

  @doc """
  Builds RDF triples for ordered children using rdf:List.

  Generates an ordered list of child spec IRIs that preserves the
  child ordering from the supervisor's init/1 callback.

  ## Parameters

  - `ordered_children` - List of ChildOrder structs
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context

  ## Returns

  A tuple `{list_iri, triples}` where:
  - `list_iri` - The IRI of the list head (or nil if empty)
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}
      iex> children = [
      ...>   %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1},
      ...>   %ChildOrder{position: 1, child_spec: %ChildSpec{id: :w2, module: W2}, id: :w2}
      ...> ]
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_list_iri, triples} = SupervisorBuilder.build_ordered_children(children, supervisor_iri, context)
      iex> length(triples) > 0
      true
  """
  @spec build_ordered_children([Supervisor.ChildOrder.t()], RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t() | nil, [RDF.Triple.t()]}
  def build_ordered_children([], _supervisor_iri, _context), do: {nil, []}

  def build_ordered_children(ordered_children, supervisor_iri, _context) do
    # Build child spec IRIs for each ordered child
    child_spec_iris =
      ordered_children
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn %{position: pos, id: id} ->
        IRI.for_child_spec(supervisor_iri, id || :unknown, pos)
      end)

    # Build rdf:List structure
    {list_iri, list_triples} = build_rdf_list(child_spec_iris)

    # Link supervisor to list
    link_triple =
      if list_iri do
        [Helpers.object_property(supervisor_iri, OTP.hasChildren(), list_iri)]
      else
        []
      end

    {list_iri, link_triple ++ list_triples}
  end

  # Build rdf:List from a list of IRIs
  defp build_rdf_list([]), do: {RDF.nil(), []}

  defp build_rdf_list(iris) do
    # Generate blank nodes for list structure
    {list_head, triples} = build_list_nodes(iris, 0, [])
    {list_head, triples}
  end

  # Recursively build list nodes
  defp build_list_nodes([], _index, acc), do: {RDF.nil(), Enum.reverse(acc)}

  defp build_list_nodes([iri | rest], index, acc) do
    # Create a blank node for this list element
    list_node = RDF.bnode("list_#{index}")

    # Build triples for this node
    first_triple = {list_node, RDF.first(), iri}

    if rest == [] do
      # Last element, rest is rdf:nil
      rest_triple = {list_node, RDF.rest(), RDF.nil()}
      {list_node, Enum.reverse([rest_triple, first_triple | acc])}
    else
      # More elements, recurse
      {next_node, remaining_triples} = build_list_nodes(rest, index + 1, [])
      rest_triple = {list_node, RDF.rest(), next_node}

      triples = [rest_triple, first_triple | acc]
      {list_node, Enum.reverse(triples) ++ remaining_triples}
    end
  end

  @doc """
  Builds RDF triples for a supervision tree.

  This is the main entry point for building supervision tree relationships.
  It combines supervision relationships, ordered children, and optionally
  marks the supervisor as a root supervisor.

  ## Parameters

  - `ordered_children` - List of ChildOrder structs
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context
  - `opts` - Options:
    - `:is_root` - Mark as root supervisor (default: false)
    - `:tree_iri` - SupervisionTree IRI (required if is_root: true)
    - `:app_name` - Application name for generating tree IRI

  ## Returns

  A tuple `{tree_iri, triples}` where:
  - `tree_iri` - The IRI of the supervision tree (or nil)
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.{ChildOrder, ChildSpec}
      iex> children = [
      ...>   %ChildOrder{position: 0, child_spec: %ChildSpec{id: :w1, module: W1}, id: :w1}
      ...> ]
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_tree_iri, triples} = SupervisorBuilder.build_supervision_tree(children, supervisor_iri, context)
      iex> length(triples) > 0
      true
  """
  @spec build_supervision_tree(
          [Supervisor.ChildOrder.t()],
          RDF.IRI.t(),
          Context.t(),
          keyword()
        ) :: {RDF.IRI.t() | nil, [RDF.Triple.t()]}
  def build_supervision_tree(ordered_children, supervisor_iri, context, opts \\ []) do
    is_root = Keyword.get(opts, :is_root, false)
    tree_iri = Keyword.get(opts, :tree_iri)
    app_name = Keyword.get(opts, :app_name)

    # Extract child specs for supervision relationships
    child_specs =
      ordered_children
      |> Enum.map(& &1.child_spec)
      |> Enum.reject(&is_nil/1)

    # Build supervision relationships (supervises/supervisedBy)
    supervision_triples = build_supervision_relationships(child_specs, supervisor_iri, context)

    # Build ordered children list
    {_list_iri, children_triples} = build_ordered_children(ordered_children, supervisor_iri, context)

    # Build root supervisor triples if applicable
    {final_tree_iri, root_triples} =
      if is_root do
        effective_tree_iri =
          tree_iri || (app_name && IRI.for_supervision_tree(context.base_iri, app_name))

        if effective_tree_iri do
          {effective_tree_iri, build_root_supervisor(supervisor_iri, effective_tree_iri, context)}
        else
          {nil, []}
        end
      else
        {nil, []}
      end

    # Combine all triples
    all_triples = supervision_triples ++ children_triples ++ root_triples

    {final_tree_iri, all_triples}
  end

  @doc """
  Builds RDF triples for a root supervisor.

  Generates triples marking a supervisor as the root of a supervision tree.

  ## Parameters

  - `supervisor_iri` - The IRI of the root supervisor
  - `tree_iri` - The IRI of the supervision tree
  - `_context` - Builder context (unused currently)

  ## Returns

  A list of RDF triples.

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> tree_iri = RDF.iri("https://example.org/code#tree/my_app")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = SupervisorBuilder.build_root_supervisor(supervisor_iri, tree_iri, context)
      iex> length(triples) == 3
      true
  """
  @spec build_root_supervisor(RDF.IRI.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_root_supervisor(supervisor_iri, tree_iri, _context) do
    [
      # Tree type
      Helpers.type_triple(tree_iri, OTP.SupervisionTree),
      # Root supervisor link
      Helpers.object_property(tree_iri, OTP.rootSupervisor(), supervisor_iri),
      # Supervisor is part of tree
      Helpers.object_property(supervisor_iri, OTP.partOfTree(), tree_iri)
    ]
  end
end
