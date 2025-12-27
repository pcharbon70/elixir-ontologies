# Load test support modules
Code.require_file("support/evolution_fixtures.ex", __DIR__)

ExUnit.start(exclude: [:pending])
