# frozen_string_literal: true

module NeedhamCircle
  class App < Sinatra::Base
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
        local && Time.strptime(local, "%Y-%m-%dT%H:%M")
      rescue ArgumentError
      end
    end

    set :root, File.expand_path("../..", __dir__)
    set :erb, escape_html: true

    enable :sessions
    use RateLimit, limit: 5, period: 60, path: "/submit"
    use Rack::Protection::AuthenticityToken

    helpers do
      def google_calendar
        Thread.current[:google_calendar] ||=
          GoogleCalendar.new(settings.service_account_key)
      end
    end

    get "/" do
      result = google_calendar.list_events(settings.events_calendar_id)
      if (error = result.error)
        logger.error("Failed to load events: #{error.class}: #{error.message}")
      else
        @events = result.value
      end

      erb :index
    end

    get "/submit" do
      @event = EventForm.new

      erb :submit
    end

    post "/submit" do
      @event =
        EventForm.new(
          title: params["title"],
          description: params["description"],
          location: params["location"],
          starts_at: params["start"],
          ends_at: params["end"]
        )

      if @event.valid?
        result = google_calendar.create_event(settings.submissions_calendar_id, @event)
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
  end
end
