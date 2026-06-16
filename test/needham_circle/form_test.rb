# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class FormTest < Minitest::Test
    class TestForm < Form
      string_field :name, "Name", required: true, max_length: 5
      string_field :note, "Note"
      time_field :starts_at, "Start", required: true, future_only: true
    end

    def test_string_field_strips_whitespace
      field = Form::StringField.new(:x, "X")
      assert_equal "hi", field.coerce("  hi  ")
    end

    def test_string_field_coerces_nil_to_empty_string
      field = Form::StringField.new(:x, "X")
      assert_equal "", field.coerce(nil)
    end

    def test_string_field_required_rejects_empty
      field = Form::StringField.new(:x, "X", required: true)
      assert_equal "X is required.", field.validate("")
      assert_nil field.validate("ok")
    end

    def test_string_field_enforces_max_length
      field = Form::StringField.new(:x, "X", max_length: 3)
      assert_nil field.validate("abc")
      assert_equal "X must be at most 3 characters.", field.validate("abcd")
    end

    def test_time_field_parses_datetime_local
      field = Form::TimeField.new(:t, "T")
      result = field.coerce("2099-01-02T15:30")
      assert_instance_of Time, result
      assert_equal 2099, result.year
      assert_equal 15, result.hour
      assert_equal 30, result.min
    end

    def test_time_field_returns_nil_for_garbage
      field = Form::TimeField.new(:t, "T")
      assert_nil field.coerce("not-a-time")
      assert_nil field.coerce(nil)
      assert_nil field.coerce("")
    end

    def test_time_field_required_rejects_nil
      field = Form::TimeField.new(:t, "T", required: true)
      assert_equal "T is required to be a valid time.", field.validate(nil)
      assert_nil field.validate(Time.now + 60)
    end

    def test_time_field_future_only_rejects_past
      field = Form::TimeField.new(:t, "T", future_only: true)
      assert_equal "T must be in the future.", field.validate(Time.now - 3600)
      assert_nil field.validate(Time.now + 3600)
    end

    def test_email_field_strips_whitespace
      field = Form::EmailField.new(:e, "Email")
      assert_equal "a@b.com", field.coerce("  a@b.com  ")
    end

    def test_email_field_required_rejects_empty
      field = Form::EmailField.new(:e, "Email", required: true)
      assert_equal "Email is required.", field.validate("")
      assert_nil field.validate("a@b.com")
    end

    def test_email_field_rejects_malformed_address
      field = Form::EmailField.new(:e, "Email")
      assert_equal "Email must be a valid email address.", field.validate("not-an-email")
      assert_equal "Email must be a valid email address.", field.validate("missing-domain@")
      assert_nil field.validate("a@b.com")
    end

    def test_email_field_allows_blank_when_not_required
      field = Form::EmailField.new(:e, "Email")
      assert_nil field.validate("")
    end

    def test_email_field_enforces_max_length
      field = Form::EmailField.new(:e, "Email", max_length: 7)
      assert_equal "Email must be at most 7 characters.", field.validate("a@b.com1")
    end

    def test_form_skips_validation_when_constructed_without_params
      form = TestForm.new
      assert form.valid?
      assert_empty form.errors_for(:name)
      assert_empty form.errors_for(:starts_at)
      assert_equal "", form.value_for(:name)
    end

    def test_form_validates_when_params_are_passed_even_if_empty
      form = TestForm.new({})
      refute form.valid?
      assert_includes form.errors_for(:name), "Name is required."
      assert_includes form.errors_for(:starts_at), "Start is required to be a valid time."
    end

    def test_form_value_for_returns_raw_input
      form = TestForm.new("name" => "  Bob  ")
      assert_equal "  Bob  ", form.value_for(:name)
    end

    def test_form_coerced_for_returns_coerced_value
      form = TestForm.new("name" => "  Bob  ")
      assert_equal "Bob", form.coerced_for(:name)
    end

    def test_form_runs_cross_field_validation
      klass = Class.new(Form) do
        string_field :a, "A"
        string_field :b, "B"
        validate do |form|
          if form.coerced_for(:a) != form.coerced_for(:b)
            form.errors[:b] << "must match A"
          end
        end
      end

      refute klass.new("a" => "x", "b" => "y").valid?
      assert klass.new("a" => "x", "b" => "x").valid?
    end
  end
end
