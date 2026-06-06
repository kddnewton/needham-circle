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
      #: (Google::Apis::CalendarV3::Event event, (EventDateTimeFormatter | EventDateFormatter) formatter) -> void
      def initialize(event, formatter)
        @event = event
        @formatter = formatter
      end

      #: () -> String
      def title
        @event.summary
      end

      #: () -> String?
      def url
        if (candidate = @event.source&.url)&.match?(%r{\Ahttps?://})
          candidate
        end
      end

      #: () -> String
      def iso8601
        @formatter.iso8601(@event)
      end

      #: () -> String
      def formatted_starts_at
        @formatter.formatted_starts_at(@event)
      end

      #: () -> String
      def formatted_month
        @formatter.formatted_month(@event)
      end
    end

    class EventDateTimeFormatter
      #: (Google::Apis::CalendarV3::Event event) -> String
      def iso8601(event)
        event.start.date_time.iso8601
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_starts_at(event)
        event.start.date_time.strftime("%A, %B %-d at %-l:%M %p")
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_month(event)
        event.start.date_time.strftime("%B %Y")
      end
    end

    class EventDateFormatter
      #: (Google::Apis::CalendarV3::Event event) -> String
      def iso8601(event)
        event.start.date.iso8601
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_starts_at(event)
        event.start.date.strftime("%A, %B %-d")
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_month(event)
        event.start.date.strftime("%B %Y")
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
          .map do |google_event|
            EventView.new(
              google_event,
              if google_event.start.date_time
                EventDateTimeFormatter.new
              elsif google_event.start_date
                EventDateFormatter.new
              else
                raise
              end
            )
          end
      end
    end

    #: (String calendar_id, EventForm event_form) -> Result[void]
    def create_event(calendar_id, event_form)
      Result.wrap do
        google_event =
          Google::Apis::CalendarV3::Event.new(
            summary: event_form.coerced_for(:title),
            description: event_form.coerced_for(:description),
            location: event_form.coerced_for(:location),
            start: event_date_time(event_form.coerced_for(:start_time)),
            end: event_date_time(event_form.coerced_for(:end_time))
          )

        # Google rejects Event::Source with a blank url. Only attach the source
        # block when we actually have one to link to.
        if (url = event_form.coerced_for(:url)) && !url.empty?
          google_event.source =
            Google::Apis::CalendarV3::Event::Source.new(
              title: "Event website",
              url: url
            )
        end

        @service.insert_event(calendar_id, google_event)
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
      google_event =
        Google::Apis::CalendarV3::Event.new(
          summary: event.title,
          description: event.description,
          location: event.location,
          start: source_date_time(event.start_at, event.timezone),
          end: source_date_time(event.end_at, event.timezone),
          extended_properties:
            Google::Apis::CalendarV3::Event::ExtendedProperties.new(
              private: { "source" => source, "source_id" => event.source_id }
            )
        )

      # Google rejects Event::Source with a blank url. Only attach the source
      # block when we actually have one to link to.
      if event.url && !event.url.empty?
        google_event.source =
          Google::Apis::CalendarV3::Event::Source.new(
            title: source,
            url: event.url
          )
      end

      google_event
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
