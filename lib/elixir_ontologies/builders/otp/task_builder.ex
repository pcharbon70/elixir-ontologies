defmodule ElixirOntologies.Builders.OTP.TaskBuilder do
  @moduledoc """
  Builds RDF triples for OTP Task implementations.

  This module transforms `ElixirOntologies.Extractors.OTP.Task` results into RDF
  triples following the elixir-otp.ttl ontology. It handles:

  - Task usage via function calls
  - Task.Supervisor usage
  - Task function call tracking
  - Detection methods (use, function_call)

  ## Task Patterns

  **Task**: Abstraction for async/await pattern
  - Lightweight concurrent operations
  - async/await operations
  - Process designed for single computations

  **TaskSupervisor**: Dynamic task supervision
  - Supervisor specialized for Task children
  - Supports async_nolink for fire-and-forget tasks

  ## Usage

      alias ElixirOntologies.Builders.OTP.{TaskBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.Task

      # Build Task usage
      task_info = %Task{
        type: :task,
        detection_method: :function_call,
        function_calls: [],
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#Workers>
      context = Context.new(base_iri: "https://example.org/code#")
      {task_iri, triples} = TaskBuilder.build_task(task_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.TaskBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Task
      iex> task_info = %Task{
      ...>   type: :task,
      ...>   detection_method: :function_call,
      ...>   function_calls: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestWorker")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {task_iri, _triples} = TaskBuilder.build_task(task_info, module_iri, context)
      iex> to_string(task_iri)
      "https://example.org/code#TestWorker"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.Task
  alias NS.{OTP, Core}

  # ===========================================================================
  # Public API - Task Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a Task implementation.

  Takes a Task extraction result and builder context, returns the Task IRI
  and a list of RDF triples representing the Task usage.

  ## Parameters

  - `task_info` - Task extraction result from `Extractors.OTP.Task.extract/1`
  - `module_iri` - The IRI of the module using Task
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{task_iri, triples}` where:
  - `task_iri` - The IRI of the Task (same as module_iri)
  - `triples` - List of RDF triples describing the Task

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.TaskBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Task
      iex> task_info = %Task{
      ...>   type: :task,
      ...>   detection_method: :function_call,
      ...>   function_calls: [],
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#TestWorker")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {task_iri, triples} = TaskBuilder.build_task(task_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^task_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_task(Task.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_task(task_info, module_iri, context) do
    # Task IRI is the same as module IRI
    task_iri = module_iri

    # Build all triples
    triples =
      [
        # Core Task triples
        build_type_triple(task_iri, task_info.type)
      ] ++
        build_location_triple(task_iri, task_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {task_iri, triples}
  end

  # ===========================================================================
  # Task Implementation Triple Generation
  # ===========================================================================

  # Build rdf:type otp:Task triple
  defp build_type_triple(task_iri, :task) do
    Helpers.type_triple(task_iri, OTP.Task)
  end

  # Build rdf:type otp:TaskSupervisor triple
  defp build_type_triple(task_iri, :task_supervisor) do
    Helpers.type_triple(task_iri, OTP.TaskSupervisor)
  end

  # Build location triple if present
  defp build_location_triple(_task_iri, nil, _context), do: []
  defp build_location_triple(_task_iri, _location, %Context{file_path: nil}), do: []

  defp build_location_triple(task_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(task_iri, Core.hasSourceLocation(), location_iri)]
  end
end
