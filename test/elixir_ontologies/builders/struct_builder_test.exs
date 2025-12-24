defmodule ElixirOntologies.Builders.StructBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.StructBuilder

  alias ElixirOntologies.Builders.{StructBuilder, Context}
  alias ElixirOntologies.Extractors.Struct
  alias ElixirOntologies.NS.Structure

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
    module_name = Keyword.get(opts, :module_name, "TestStruct")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_struct(opts \\ []) do
    %Struct{
      fields: Keyword.get(opts, :fields, []),
      enforce_keys: Keyword.get(opts, :enforce_keys, []),
      derives: Keyword.get(opts, :derives, []),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_field(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, :test_field),
      has_default: Keyword.get(opts, :has_default, false),
      default_value: Keyword.get(opts, :default_value, nil),
      location: Keyword.get(opts, :location, nil)
    }
  end

  defp build_test_exception(opts \\ []) do
    %Struct.Exception{
      fields: Keyword.get(opts, :fields, []),
      enforce_keys: Keyword.get(opts, :enforce_keys, []),
      derives: Keyword.get(opts, :derives, []),
      has_custom_message: Keyword.get(opts, :has_custom_message, false),
      default_message: Keyword.get(opts, :default_message, nil),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Basic Struct Building Tests
  # ===========================================================================

  describe "build_struct/3 - basic building" do
    test "builds minimal struct with no fields" do
      struct_info = build_test_struct()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify IRI
      assert struct_iri == module_iri
      assert to_string(struct_iri) == "https://example.org/code#TestStruct"

      # Verify type triple
      assert {struct_iri, RDF.type(), Structure.Struct} in triples

      # Verify containsStruct triple
      assert {struct_iri, Structure.containsStruct(), struct_iri} in triples
    end

    test "builds struct with single field" do
      field = build_test_field(name: :name, has_default: false)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify field IRI
      field_iri = RDF.iri("#{struct_iri}/field/name")

      # Verify field type
      assert {field_iri, RDF.type(), Structure.StructField} in triples

      # Verify field properties
      assert {field_iri, Structure.fieldName(), RDF.XSD.String.new("name")} in triples

      # Verify hasField relationship
      assert {struct_iri, Structure.hasField(), field_iri} in triples
    end

    test "builds struct with multiple fields" do
      fields = [
        build_test_field(name: :name),
        build_test_field(name: :email),
        build_test_field(name: :age)
      ]

      struct_info = build_test_struct(fields: fields)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify all fields present
      name_iri = RDF.iri("#{struct_iri}/field/name")
      email_iri = RDF.iri("#{struct_iri}/field/email")
      age_iri = RDF.iri("#{struct_iri}/field/age")

      assert {name_iri, RDF.type(), Structure.StructField} in triples
      assert {email_iri, RDF.type(), Structure.StructField} in triples
      assert {age_iri, RDF.type(), Structure.StructField} in triples
    end
  end

  # ===========================================================================
  # Field Default Value Tests
  # ===========================================================================

  describe "build_struct/3 - field defaults" do
    test "builds field without default value" do
      field = build_test_field(name: :name, has_default: false)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/name")

      # Verify no hasDefaultFieldValue triple
      default_pred = Structure.hasDefaultFieldValue()

      refute Enum.any?(triples, fn
               {^field_iri, ^default_pred, _} -> true
               _ -> false
             end)
    end

    test "builds field with default value (integer)" do
      field = build_test_field(name: :age, has_default: true, default_value: 0)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/age")

      # Verify hasDefaultFieldValue triple
      assert {field_iri, Structure.hasDefaultFieldValue(), RDF.XSD.String.new("0")} in triples
    end

    test "builds field with default value (string)" do
      field = build_test_field(name: :status, has_default: true, default_value: "active")
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/status")

      # Verify hasDefaultFieldValue triple (inspected value includes quotes)
      assert {field_iri, Structure.hasDefaultFieldValue(), RDF.XSD.String.new("\"active\"")} in triples
    end

    test "builds field with default value (list)" do
      field = build_test_field(name: :tags, has_default: true, default_value: [])
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/tags")

      # Verify hasDefaultFieldValue triple
      assert {field_iri, Structure.hasDefaultFieldValue(), RDF.XSD.String.new("[]")} in triples
    end
  end

  # ===========================================================================
  # Enforced Keys Tests
  # ===========================================================================

  describe "build_struct/3 - enforced keys" do
    test "builds struct with no enforced keys" do
      field = build_test_field(name: :name)
      struct_info = build_test_struct(fields: [field], enforce_keys: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify no hasEnforcedKey triples
      enforced_pred = Structure.hasEnforcedKey()

      refute Enum.any?(triples, fn
               {^struct_iri, ^enforced_pred, _} -> true
               _ -> false
             end)
    end

    test "builds struct with single enforced key" do
      field = build_test_field(name: :name)
      struct_info = build_test_struct(fields: [field], enforce_keys: [:name])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/name")

      # Verify hasEnforcedKey triple
      assert {struct_iri, Structure.hasEnforcedKey(), field_iri} in triples
    end

    test "builds struct with multiple enforced keys" do
      fields = [
        build_test_field(name: :name),
        build_test_field(name: :email),
        build_test_field(name: :age)
      ]

      struct_info = build_test_struct(fields: fields, enforce_keys: [:name, :email])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      name_iri = RDF.iri("#{struct_iri}/field/name")
      email_iri = RDF.iri("#{struct_iri}/field/email")
      age_iri = RDF.iri("#{struct_iri}/field/age")

      # Verify enforced keys
      assert {struct_iri, Structure.hasEnforcedKey(), name_iri} in triples
      assert {struct_iri, Structure.hasEnforcedKey(), email_iri} in triples

      # Verify age is NOT enforced
      refute {struct_iri, Structure.hasEnforcedKey(), age_iri} in triples
    end
  end

  # ===========================================================================
  # Protocol Derivation Tests
  # ===========================================================================

  describe "build_struct/3 - protocol derivation" do
    test "builds struct with no derived protocols" do
      field = build_test_field(name: :name)
      struct_info = build_test_struct(fields: [field], derives: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify no derivesProtocol triples
      derives_pred = Structure.derivesProtocol()

      refute Enum.any?(triples, fn
               {^struct_iri, ^derives_pred, _} -> true
               _ -> false
             end)
    end

    test "builds struct with single derived protocol (list format)" do
      derive_info = %ElixirOntologies.Extractors.Helpers.DeriveInfo{
        protocols: [%{protocol: [:Inspect], options: nil}],
        location: nil
      }

      struct_info = build_test_struct(derives: [derive_info])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      protocol_iri = RDF.iri("https://example.org/code#Inspect")

      # Verify derivesProtocol triple
      assert {struct_iri, Structure.derivesProtocol(), protocol_iri} in triples
    end

    test "builds struct with single derived protocol (atom format)" do
      derive_info = %ElixirOntologies.Extractors.Helpers.DeriveInfo{
        protocols: [%{protocol: :Inspect, options: nil}],
        location: nil
      }

      struct_info = build_test_struct(derives: [derive_info])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      protocol_iri = RDF.iri("https://example.org/code#Inspect")

      # Verify derivesProtocol triple
      assert {struct_iri, Structure.derivesProtocol(), protocol_iri} in triples
    end

    test "builds struct with multiple derived protocols" do
      derive_info = %ElixirOntologies.Extractors.Helpers.DeriveInfo{
        protocols: [
          %{protocol: [:Inspect], options: nil},
          %{protocol: [:Enumerable], options: nil}
        ],
        location: nil
      }

      struct_info = build_test_struct(derives: [derive_info])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      inspect_iri = RDF.iri("https://example.org/code#Inspect")
      enumerable_iri = RDF.iri("https://example.org/code#Enumerable")

      # Verify both derivesProtocol triples
      assert {struct_iri, Structure.derivesProtocol(), inspect_iri} in triples
      assert {struct_iri, Structure.derivesProtocol(), enumerable_iri} in triples
    end
  end

  # ===========================================================================
  # Exception Building Tests
  # ===========================================================================

  describe "build_exception/3 - basic building" do
    test "builds minimal exception with no fields" do
      exception_info = build_test_exception()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Verify IRI
      assert exception_iri == module_iri

      # Verify type triple (Exception, not Struct)
      assert {exception_iri, RDF.type(), Structure.Exception} in triples

      # Verify containsStruct triple
      assert {exception_iri, Structure.containsStruct(), exception_iri} in triples
    end

    test "builds exception with message field and default" do
      field = build_test_field(name: :message, has_default: true, default_value: "error")

      exception_info =
        build_test_exception(
          fields: [field],
          default_message: "error"
        )

      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Verify exceptionMessage triple
      assert {exception_iri, Structure.exceptionMessage(), RDF.XSD.String.new("error")} in triples

      # Verify message field exists
      message_iri = RDF.iri("#{exception_iri}/field/message")
      assert {message_iri, RDF.type(), Structure.StructField} in triples
    end

    test "builds exception with custom message" do
      exception_info =
        build_test_exception(has_custom_message: true, default_message: "custom error")

      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Verify exceptionMessage triple
      assert {exception_iri, Structure.exceptionMessage(), RDF.XSD.String.new("custom error")} in triples
    end

    test "builds exception without default message" do
      exception_info = build_test_exception(default_message: nil)
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Verify no exceptionMessage triple
      exception_msg_pred = Structure.exceptionMessage()

      refute Enum.any?(triples, fn
               {^exception_iri, ^exception_msg_pred, _} -> true
               _ -> false
             end)
    end

    test "builds exception with enforced keys" do
      field = build_test_field(name: :code)

      exception_info =
        build_test_exception(
          fields: [field],
          enforce_keys: [:code]
        )

      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      code_iri = RDF.iri("#{exception_iri}/field/code")

      # Verify enforced key
      assert {exception_iri, Structure.hasEnforcedKey(), code_iri} in triples
    end
  end

  # ===========================================================================
  # IRI Generation Tests
  # ===========================================================================

  describe "IRI generation" do
    test "generates struct IRI using module pattern" do
      struct_info = build_test_struct()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.UserStruct")

      {struct_iri, _triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      assert to_string(struct_iri) == "https://example.org/code#MyApp.UserStruct"
    end

    test "generates field IRI with struct/field/name pattern" do
      field = build_test_field(name: :email)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/email")
      assert {field_iri, RDF.type(), Structure.StructField} in triples
    end

    test "generates different IRIs for different fields" do
      fields = [
        build_test_field(name: :name),
        build_test_field(name: :email)
      ]

      struct_info = build_test_struct(fields: fields)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      name_iri = RDF.iri("#{struct_iri}/field/name")
      email_iri = RDF.iri("#{struct_iri}/field/email")

      assert {name_iri, RDF.type(), Structure.StructField} in triples
      assert {email_iri, RDF.type(), Structure.StructField} in triples
      assert name_iri != email_iri
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "generates all expected triples for struct with fields" do
      field = build_test_field(name: :name, has_default: true, default_value: "unknown")
      struct_info = build_test_struct(fields: [field], enforce_keys: [:name])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Count expected triples:
      # 1. Struct type
      # 2. containsStruct
      # 3. Field type
      # 4. fieldName
      # 5. hasField
      # 6. hasDefaultFieldValue
      # 7. EnforcedKey type
      # 8. hasEnforcedKey
      # = 8 triples minimum

      assert length(triples) >= 8
    end

    test "does not generate duplicate triples" do
      field = build_test_field(name: :name)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Verify deduplication worked
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "generates all expected triples for exception" do
      field = build_test_field(name: :message, has_default: true, default_value: "error")

      exception_info =
        build_test_exception(
          fields: [field],
          has_custom_message: true,
          default_message: "error"
        )

      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {_exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Count expected triples:
      # 1. Exception type
      # 2. containsStruct
      # 3. Field type
      # 4. fieldName
      # 5. hasField
      # 6. hasDefaultFieldValue
      # 7. exceptionMessage
      # = 7 triples minimum

      assert length(triples) >= 7
    end
  end

  # ===========================================================================
  # Edge Cases Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles struct with field that has nil default" do
      field = build_test_field(name: :optional, has_default: true, default_value: nil)
      struct_info = build_test_struct(fields: [field])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      field_iri = RDF.iri("#{struct_iri}/field/optional")

      # Verify hasDefaultFieldValue triple with "nil"
      assert {field_iri, Structure.hasDefaultFieldValue(), RDF.XSD.String.new("nil")} in triples
    end

    test "handles exception with only standard fields" do
      # No custom fields, just the standard :message and :__exception__
      exception_info = build_test_exception(fields: [])
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyError")

      {exception_iri, triples} =
        StructBuilder.build_exception(exception_info, module_iri, context)

      # Should still have type and containsStruct
      assert {exception_iri, RDF.type(), Structure.Exception} in triples
      assert {exception_iri, Structure.containsStruct(), exception_iri} in triples
    end

    test "handles struct with enforced key not in fields list" do
      # This shouldn't happen in practice, but test graceful handling
      field = build_test_field(name: :name)
      struct_info = build_test_struct(fields: [field], enforce_keys: [:name, :email])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {struct_iri, triples} = StructBuilder.build_struct(struct_info, module_iri, context)

      # Should still generate enforced key triples (field IRI exists conceptually)
      name_iri = RDF.iri("#{struct_iri}/field/name")
      email_iri = RDF.iri("#{struct_iri}/field/email")

      assert {struct_iri, Structure.hasEnforcedKey(), name_iri} in triples
      assert {struct_iri, Structure.hasEnforcedKey(), email_iri} in triples
    end
  end
end
