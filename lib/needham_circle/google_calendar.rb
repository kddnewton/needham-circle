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

    class SourceEventView
      attr_reader :id #: String
      attr_reader :source_id #: String?

      #: (Google::Apis::CalendarV3::Event event) -> void
      def initialize(event)
        @id = event.id
        @source_id = event.extended_properties&.private&.[]("source_id")
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

    #: (String calendar_id, String source) -> Result[Array[SourceEventView]]
    def list_events_by_source(calendar_id, source)
      Result.wrap do
        @service
          .list_events(
            calendar_id,
            private_extended_property: ["source=#{source}"],
            single_events: true,
            show_deleted: false,
            max_results: 2500
          )
          .items
          .map { |google_event| SourceEventView.new(google_event) }
      end
    end

    #: (String calendar_id, String source, String? existing_event_id, Sync::Event event) -> Result[void]
    def upsert_source_event(calendar_id, source, existing_event_id, event)
      Result.wrap do
        google_event = build_source_event(source, event)
        if existing_event_id
          @service.update_event(calendar_id, existing_event_id, google_event)
        else
          @service.insert_event(calendar_id, google_event)
        end
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

    #: (String source, Sync::Event event) -> Google::Apis::CalendarV3::Event
    def build_source_event(source, event)
      Google::Apis::CalendarV3::Event.new(
        summary: event.title,
        description: event.description,
        location: event.location,
        start: source_date_time(event.start_at, event.timezone),
        end: source_date_time(event.end_at, event.timezone),
        source: Google::Apis::CalendarV3::Event::Source.new(
          title: source,
          url: event.url
        ),
        extended_properties:
          Google::Apis::CalendarV3::Event::ExtendedProperties.new(
            private: { "source" => source, "source_id" => event.source_id }
          )
      )
    end

    #: (String iso, String timezone) -> Google::Apis::CalendarV3::EventDateTime
    def source_date_time(iso, timezone)
      Google::Apis::CalendarV3::EventDateTime.new(
        date_time: iso,
        time_zone: timezone
      )
    end
  end
end
