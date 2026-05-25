# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class GoogleCalendarTest < Minitest::Test
    FakeApiStart = Struct.new(:date_time, :date)
    FakeApiSource = Struct.new(:url)
    FakeApiEvent = Struct.new(:summary, :start, :source)

    def test_result_wrap_returns_value_on_success
      result = GoogleCalendar::Result.wrap { "hello" }
      assert_equal "hello", result.value
      assert_nil result.error
    end

    def test_result_wrap_captures_google_apis_error
      error = Google::Apis::ServerError.new("boom")
      result = GoogleCalendar::Result.wrap { raise error }
      assert_nil result.value
      assert_equal error, result.error
    end

    def test_result_wrap_does_not_rescue_other_errors
      assert_raises(RuntimeError) do
        GoogleCalendar::Result.wrap { raise "not an api error" }
      end
    end

    def test_event_view_title_uses_summary
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Picnic", FakeApiStart.new(nil, nil))
      )
      assert_equal "Picnic", view.title
    end

    def test_event_view_title_falls_back_when_summary_nil
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new(nil, FakeApiStart.new(nil, nil))
      )
      assert_equal "(no title)", view.title
    end

    def test_event_view_starts_at_prefers_date_time
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new("2099-01-01T10:00:00Z", "2099-01-01"))
      )
      assert_equal "2099-01-01T10:00:00Z", view.starts_at
    end

    def test_event_view_starts_at_falls_back_to_date
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new(nil, "2099-01-02"))
      )
      assert_equal "2099-01-02", view.starts_at
    end

    def test_event_view_url_returns_source_url
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new(nil, nil), FakeApiSource.new("https://example.com/e/1"))
      )
      assert_equal "https://example.com/e/1", view.url
    end

    def test_event_view_url_nil_when_no_source
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new(nil, nil), nil)
      )
      assert_nil view.url
    end

    def test_event_view_url_rejects_javascript_scheme
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new(nil, nil), FakeApiSource.new("javascript:alert(1)"))
      )
      assert_nil view.url
    end

    def test_event_view_url_rejects_empty_string
      view = GoogleCalendar::EventView.new(
        FakeApiEvent.new("Ok", FakeApiStart.new(nil, nil), FakeApiSource.new(""))
      )
      assert_nil view.url
    end
  end
end
