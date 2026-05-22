# frozen_string_literal: true

module NeedhamCircle
  class GoogleCalendar
    class Result
      attr_reader :value #: T
      attr_reader :error #: Google::Apis::Error?

      #: (T? value, Google::Apis::Error? error) -> void
      def initialize(value, error)
        @value = value
        @error = error
      end

      #: () { () -> T } -> Result[T]
      def self.wrap
        value = yield
        new(value, nil)
      rescue Google::Apis::Error => error
        new(nil, error)
      end
    end

    class EventView
      #: (Google::Apis::CalendarV3::Event event) -> void
      def initialize(event)
        @event = event
      end

      #: () -> String
      def title
        @event.summary || "(no title)"
      end

      #: () -> String
      def starts_at
        @event.start.date_time || @event.start.date
      end
    end

    #: (String key) -> void
    def initialize(key)
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.authorization =
        Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(Base64.decode64(key)),
          scope: ["https://www.googleapis.com/auth/calendar.events"]
        )
    end

    #: (String calendar_id) -> Result[Array[EventView]]
    def list_events(calendar_id)
      Result.wrap do
        @service
          .list_events(
            calendar_id,
            single_events: true,
            order_by: "startTime",
            time_min: Time.now.iso8601,
            max_results: 50
          )
          .items
          .map { |google_event| EventView.new(google_event) }
      end
    end

    #: (String calendar_id, EventForm event_form) -> Result[void]
    def create_event(calendar_id, event_form)
      Result.wrap do
        @service.insert_event(
          calendar_id,
          Google::Apis::CalendarV3::Event.new(
            summary: event_form.coerced_for(:title),
            description: event_form.coerced_for(:description),
            location: event_form.coerced_for(:location),
            start: event_date_time(event_form.coerced_for(:start_time)),
            end: event_date_time(event_form.coerced_for(:end_time))
          )
        )
      end
    end

    private

    #: (Time time) -> Google::Apis::CalendarV3::EventDateTime
    def event_date_time(time)
      Google::Apis::CalendarV3::EventDateTime.new(
        date_time: time.strftime("%Y-%m-%dT%H:%M:%S"),
        time_zone: "America/New_York"
      )
    end
  end
end
