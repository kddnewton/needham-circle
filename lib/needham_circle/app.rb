# frozen_string_literal: true

module NeedhamCircle
  class App < Sinatra::Base
    class EventForm < Form
      string_field :title, "Title", required: true, max_length: 200
      string_field :description, "Description", max_length: 2000
      string_field :location, "Location", max_length: 200
      time_field :start_time, "Start time", required: true, future_only: true
      time_field :end_time, "End time", required: true, future_only: true

      validate do |form|
        start_time = form.coerced_for(:start_time)
        end_time = form.coerced_for(:end_time)

        if start_time && end_time && end_time <= start_time
          form.errors[:end_time] << "End time must be after start time."
        end
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

      def event_datetime(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      end

      def format_event_time(value)
        case value
        when DateTime, Time
          value.strftime("%A, %B %-d at %-l:%M %p")
        when String
          begin
            Date.parse(value).strftime("%A, %B %-d")
          rescue ArgumentError
            value
          end
        else
          value.to_s
        end
      end
    end

    get "/" do
      @page_title = "Needham Circle"
      @page_description = "Upcoming community events in Needham Circle. Browse what's happening, and submit your own events."

      result = google_calendar.list_events(settings.events_calendar_id)
      if (error = result.error)
        logger.error("Failed to load events: #{error.class}: #{error.message}")
      else
        @events = result.value
      end

      erb :index
    end

    get "/submit" do
      @page_title = "Needham Circle — Submit an Event"
      @page_description = "Submit a community event to the Needham Circle calendar."
      @event = EventForm.new

      erb :submit
    end

    post "/submit" do
      @page_title = "Needham Circle — Submit an Event"
      @page_description = "Submit a community event to the Needham Circle calendar."
      @event = EventForm.new(params)

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
