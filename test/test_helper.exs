# Load test support modules
Code.require_file("support/evolution_fixtures.ex", __DIR__)
Code.require_file("elixir_ontologies/builders/expression_test_helpers.ex", __DIR__)

ExUnit.start(exclude: [:pending, :integration])
