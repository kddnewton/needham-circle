require "sinatra"
require "google/apis/calendar_v3"
require "googleauth"
require "base64"
require "time"

module NeedhamCircle
  class EventForm
    attr_reader :title, :description, :location, :starts_at, :ends_at #: String?
    attr_reader :starts_at_time, :ends_at_time #: Time?

    #: (String? title, String? description, String? location, String? starts_at, String? ends_at) -> void
    def initialize(title: nil, description: nil, location: nil, starts_at: nil, ends_at: nil)
      @title = title
      @description = description
      @location = location
      @starts_at = starts_at
      @ends_at = ends_at
      @starts_at_time = parse_time(starts_at)
      @ends_at_time = parse_time(ends_at)
    end

    #: () -> bool
    def valid?
      !@title.to_s.strip.empty? && !@starts_at_time.nil? && !@ends_at_time.nil?
    end

    private

    def parse_time(local)
      Time.strptime(local, "%Y-%m-%dT%H:%M")
    rescue ArgumentError
    end
  end

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
            summary: event_form.title,
            description: event_form.description,
            location: event_form.location,
            start: event_date_time(event_form.starts_at_time),
            end: event_date_time(event_form.ends_at_time)
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

#——————————————————————————————————————————————————————————————————————————————#

$secrets =
  if File.exist?((filepath = File.expand_path(".env", __dir__)))
    File.foreach(filepath).to_h { |line| line.chomp.split("=", 2) }
  else
    ENV
  end

get "/" do
  result =
    NeedhamCircle::GoogleCalendar
      .new($secrets.fetch("SERVICE_ACCOUNT_KEY"))
      .list_events($secrets.fetch("EVENTS_CALENDAR_ID"))

  @events =
    if (error = result.error)
      logger.error("Failed to load events: #{error.class}: #{error.message}")
      nil
    else
      result.value
    end

  erb :index
end

get "/submit" do
  @event = NeedhamCircle::EventForm.new

  erb :submit
end

post "/submit" do
  @event =
    NeedhamCircle::EventForm.new(
      title: params["title"],
      description: params["description"],
      location: params["location"],
      starts_at: params["start"],
      ends_at: params["end"]
    )

  if @event.valid?
    result =
      NeedhamCircle::GoogleCalendar
        .new($secrets.fetch("SERVICE_ACCOUNT_KEY"))
        .create_event($secrets.fetch("SUBMISSIONS_CALENDAR_ID"), @event)

    if (error = result.error)
      logger.error("Failed to create submission: #{error.class}: #{error.message}")
      @form_error = true
    else
      @submitted = true
    end
  else
    @form_error = true
  end

  erb :submit
end
