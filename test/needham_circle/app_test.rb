# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class AppTest < Minitest::Test
    include Rack::Test::Methods

    FakeEventView = Struct.new(:title, :starts_at, :url)

    class FakeCalendar
      attr_accessor :events_to_return, :list_error, :create_error
      attr_reader :created

      def initialize
        @events_to_return = []
        @list_error = nil
        @create_error = nil
        @created = []
      end

      def list_events(_calendar_id)
        GoogleCalendar::Result.new(
          @list_error ? nil : @events_to_return,
          @list_error
        )
      end

      def create_event(calendar_id, event_form)
        @created << [calendar_id, event_form]
        GoogleCalendar::Result.new(
          @create_error ? nil : true,
          @create_error
        )
      end
    end

    # Each test gets a unique synthetic IP. The RateLimit middleware lives on the
    # shared App and persists @hits across tests; without distinct
    # IPs, the test order would determine whether limits trip.
    @@ip_counter = 0

    def app
      App
    end

    def setup
      @@ip_counter += 1
      @test_ip = "10.99.#{@@ip_counter / 256 % 256}.#{@@ip_counter % 256}"
      @fake_calendar = FakeCalendar.new
      Thread.current[:google_calendar] = @fake_calendar
    end

    def teardown
      Thread.current[:google_calendar] = nil
    end

    def get(path, params = {}, rack_env = {})
      super(path, params, rack_env.merge("REMOTE_ADDR" => @test_ip))
    end

    def post(path, params = {}, rack_env = {})
      super(path, params, rack_env.merge("REMOTE_ADDR" => @test_ip))
    end

    def test_index_renders_events_from_calendar
      @fake_calendar.events_to_return = [
        FakeEventView.new("Summer Picnic", "2099-07-04T12:00"),
        FakeEventView.new("Book Club", "2099-08-01T18:00")
      ]
      get "/"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Summer Picnic"
      assert_includes last_response.body, "Book Club"
    end

    def test_index_renders_friendly_error_on_calendar_failure
      @fake_calendar.list_error = Google::Apis::ServerError.new("boom")
      get "/"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "trouble loading events"
    end

    def test_index_wraps_title_in_link_when_event_has_url
      @fake_calendar.events_to_return = [
        FakeEventView.new("Summer Picnic", "2099-07-04T12:00", "https://example.com/picnic")
      ]
      get "/"
      assert_match %r{<a href="https://example\.com/picnic"[^>]*>Summer Picnic</a>}, last_response.body
    end

    def test_index_renders_plain_title_when_event_has_no_url
      @fake_calendar.events_to_return = [
        FakeEventView.new("Bake Sale", "2099-09-04T12:00", nil)
      ]
      get "/"
      assert_includes last_response.body, "Bake Sale"
      refute_match %r{<a [^>]*>Bake Sale</a>}, last_response.body
    end

    def test_submit_page_renders_form_with_csrf_token
      get "/submit"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Submit an Event"
      assert_match(/name="authenticity_token" value="[^"]+"/, last_response.body)
    end

    def test_post_without_csrf_token_is_rejected
      post "/submit", "title" => "Hi"
      assert_equal 403, last_response.status
      assert_empty @fake_calendar.created
    end

    def test_valid_submission_creates_event_and_renders_thanks
      submit(
        "title" => "Town Meeting",
        "description" => "Discuss things",
        "location" => "Town Hall",
        "start_time" => future_local(1),
        "end_time" => future_local(3)
      )

      assert_equal 200, last_response.status
      assert_includes last_response.body, "Thanks!"
      assert_equal 1, @fake_calendar.created.size
      calendar_id, form = @fake_calendar.created.first
      assert_equal "submissions-cal-id", calendar_id
      assert_equal "Town Meeting", form.coerced_for(:title)
    end

    def test_invalid_submission_shows_field_errors_and_does_not_create
      submit(
        "title" => "",
        "start_time" => "garbage",
        "end_time" => ""
      )

      assert_includes last_response.body, "Title is required."
      assert_includes last_response.body, "Start time is required to be a valid time."
      assert_empty @fake_calendar.created
    end

    def test_end_before_start_is_rejected
      submit(
        "title" => "Inverted",
        "start_time" => future_local(3),
        "end_time" => future_local(1)
      )

      assert_includes last_response.body, "End time must be after start time."
      assert_empty @fake_calendar.created
    end

    def test_past_start_time_is_rejected
      submit(
        "title" => "Yesterday",
        "start_time" => (Time.now - 3600).strftime("%Y-%m-%dT%H:%M"),
        "end_time" => future_local(1)
      )

      assert_includes last_response.body, "Start time must be in the future."
      assert_empty @fake_calendar.created
    end

    def test_xss_payload_in_form_is_escaped_on_rerender
      submit(
        "title" => '"><script>alert(1)</script>',
        "start_time" => "",
        "end_time" => ""
      )

      refute_includes last_response.body, "<script>alert(1)"
      assert_includes last_response.body, "&lt;script&gt;"
    end

    def test_calendar_create_failure_shows_generic_error
      @fake_calendar.create_error = Google::Apis::ServerError.new("nope")
      submit(
        "title" => "Picnic",
        "start_time" => future_local(1),
        "end_time" => future_local(3)
      )

      refute_includes last_response.body, "Thanks!"
      assert_includes last_response.body, "problem with your submission"
    end

    def test_rate_limit_kicks_in_after_five_posts
      @test_ip = "192.168.99.99"
      5.times do |i|
        submit("title" => "ok #{i}", "start_time" => "", "end_time" => "")
        refute_equal 429, last_response.status, "request #{i + 1} should not be rate limited"
      end

      submit("title" => "ok 6", "start_time" => "", "end_time" => "")
      assert_equal 429, last_response.status
    end

    private

    def submit(params)
      get "/submit"
      match = last_response.body.match(/name="authenticity_token" value="([^"]+)"/)
      flunk "no CSRF token in /submit response (status=#{last_response.status})" unless match
      post "/submit", params.merge("authenticity_token" => match[1])
    end

    def future_local(hours_ahead)
      (Time.now + hours_ahead * 3600).strftime("%Y-%m-%dT%H:%M")
    end
  end
end
