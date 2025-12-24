defmodule ElixirOntologies.Builders.OTP.TaskBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.OTP.TaskBuilder

  alias ElixirOntologies.Builders.OTP.TaskBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.OTP.Task
  alias ElixirOntologies.NS.OTP

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "TestWorker")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_task(opts \\ []) do
    %Task{
      type: Keyword.get(opts, :type, :task),
      detection_method: Keyword.get(opts, :detection_method, :function_call),
      function_calls: Keyword.get(opts, :function_calls, []),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Task Implementation Building Tests
  # ===========================================================================

  describe "build_task/3 - basic building" do
    test "builds minimal Task with function_call detection" do
      task_info = build_test_task(type: :task, detection_method: :function_call)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify IRI (same as module IRI)
      assert task_iri == module_iri
      assert to_string(task_iri) == "https://example.org/code#TestWorker"

      # Verify type triple
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end

    test "builds TaskSupervisor with use detection" do
      task_info = build_test_task(type: :task_supervisor, detection_method: :use)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify type triple
      assert {task_iri, RDF.type(), OTP.TaskSupervisor} in triples
    end

    test "builds Task with nil detection_method" do
      task_info = build_test_task(detection_method: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify Task implementation exists
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end
  end

  describe "build_task/3 - IRI patterns" do
    test "Task IRI is same as module IRI" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "Workers")

      {task_iri, _triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      assert task_iri == module_iri
      assert to_string(task_iri) == "https://example.org/code#Workers"
    end

    test "handles nested module names" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Workers.Async")

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      assert task_iri == module_iri
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "no duplicate triples in Task implementation" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "Task has type triple" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Count type triples
      has_type =
        Enum.any?(triples, fn
          {^task_iri, pred, OTP.Task} -> pred == RDF.type()
          _ -> false
        end)

      assert has_type
    end

    test "TaskSupervisor has correct type" do
      task_info = build_test_task(type: :task_supervisor)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify TaskSupervisor type
      has_type =
        Enum.any?(triples, fn
          {^task_iri, pred, OTP.TaskSupervisor} -> pred == RDF.type()
          _ -> false
        end)

      assert has_type
    end

    test "all expected triples for basic Task" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Should have at least 1 triple (type)
      assert length(triples) >= 1

      # Verify all triples have the task IRI as subject
      assert Enum.all?(triples, fn {subj, _, _} -> subj == task_iri end)
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "Task in nested module" do
      task_info = build_test_task()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Services.AsyncWorker")

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify implementation
      assert {task_iri, RDF.type(), OTP.Task} in triples
      assert to_string(task_iri) == "https://example.org/code#MyApp.Services.AsyncWorker"
    end

    test "TaskSupervisor in nested module" do
      task_info = build_test_task(type: :task_supervisor)
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Supervisors.TaskSup")

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify implementation
      assert {task_iri, RDF.type(), OTP.TaskSupervisor} in triples
      assert to_string(task_iri) == "https://example.org/code#MyApp.Supervisors.TaskSup"
    end

    test "multiple detection methods produce consistent structure" do
      context = build_test_context()
      module_iri = build_test_module_iri()

      task_use = build_test_task(detection_method: :use)
      task_function = build_test_task(detection_method: :function_call)
      task_nil = build_test_task(detection_method: nil)

      {_, triples_use} = TaskBuilder.build_task(task_use, module_iri, context)
      {_, triples_function} = TaskBuilder.build_task(task_function, module_iri, context)
      {_, triples_nil} = TaskBuilder.build_task(task_nil, module_iri, context)

      # All should have same core triples (type)
      assert length(triples_use) == length(triples_function)
      assert length(triples_function) == length(triples_nil)
    end

    test "Task with different base IRIs" do
      task_info = build_test_task()
      context1 = build_test_context(base_iri: "https://example.org/code#")
      context2 = build_test_context(base_iri: "https://different.org/app#")

      module_iri1 = build_test_module_iri(base_iri: "https://example.org/code#")
      module_iri2 = build_test_module_iri(base_iri: "https://different.org/app#")

      {task_iri1, triples1} = TaskBuilder.build_task(task_info, module_iri1, context1)
      {task_iri2, triples2} = TaskBuilder.build_task(task_info, module_iri2, context2)

      # Different IRIs but same structure
      assert task_iri1 != task_iri2
      assert length(triples1) == length(triples2)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "Task with nil location" do
      task_info = build_test_task(location: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Should still work, just no location triple
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end

    test "Task with context that has no file_path" do
      task_info =
        build_test_task(
          location: %ElixirOntologies.Analyzer.Location.SourceLocation{
            start_line: 10,
            start_column: 1
          }
        )

      context = build_test_context(file_path: nil)
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Should still work, just no location triple
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end

    test "Task with metadata" do
      task_info =
        build_test_task(
          metadata: %{
            custom_key: "custom_value",
            call_count: 5
          }
        )

      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Metadata doesn't affect triples, but implementation should still work
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end

    test "Task with empty function_calls list" do
      task_info = build_test_task(function_calls: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Should still work
      assert {task_iri, RDF.type(), OTP.Task} in triples
    end

    test "TaskSupervisor with function_call detection" do
      task_info = build_test_task(type: :task_supervisor, detection_method: :function_call)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {task_iri, triples} =
        TaskBuilder.build_task(task_info, module_iri, context)

      # Verify TaskSupervisor type
      assert {task_iri, RDF.type(), OTP.TaskSupervisor} in triples
    end
  end
end
