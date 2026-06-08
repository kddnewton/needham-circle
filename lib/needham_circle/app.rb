# frozen_string_literal: true

module NeedhamCircle
  class App < Sinatra::Base
    class EventForm < Form
      string_field :title, "Title", required: true, max_length: 200
      string_field :description, "Description", max_length: 2000
      string_field :location, "Location", max_length: 200
      time_field :start_time, "Start time", required: true, future_only: true
      time_field :end_time, "End time", required: true, future_only: true
      url_field :url, "URL", max_length: 500

      validate do |form|
        start_time = form.coerced_for(:start_time)
        end_time = form.coerced_for(:end_time)

        if start_time && end_time && end_time <= start_time
          form.errors[:end_time] << "End time must be after start time."
        end
      end
    end

    class FilterForm < Form
      string_field :q, "Search", nullify: true
      multi_select_field :source, "Source", values: Source::ALL.map(&:slug)

      #: () -> Array[Source]
      def sources
        Source::ALL
      end

      #: () -> String?
      def query
        coerced_for(:q)
      end

      #: () -> Array[String]
      def selected_sources
        coerced_for(:source)
      end

      #: (String slug) -> bool
      def selected?(slug)
        selected_sources.include?(slug)
      end

      #: () -> Array[String?]
      def selected_values
        Source::ALL.select { |source| selected?(source.slug) }.map(&:value)
      end

      #: (String slug) -> String
      def toggle_url(slug)
        slugs = selected_sources
        slugs = slugs.include?(slug) ? slugs - [slug] : slugs + [slug]

        query_params = {}
        query_params["source"] = slugs.join(",") unless slugs.empty?

        if (q = query)
          query_params["q"] = q
        end

        query_params.empty? ? "/" : "/?#{URI.encode_www_form(query_params)}"
      end
    end

    set :root, File.expand_path("../..", __dir__)
    set :erb, escape_html: true

    enable :sessions
    use RateLimit, limit: 5, period: 60, path: "/submit"
    use Rack::Protection::AuthenticityToken

    helpers do
      def google_calendar
        Thread.current[:google_calendar] ||= GoogleCalendar.new(settings.service_account_key)
      end

      #: (EventForm event) -> GoogleCalendar::Result[void]
      def create_event(event)
        result = google_calendar.create_event(settings.submissions_calendar_id, event)
        if (error = result.error)
          logger.error("Failed to create submission: #{error.class}: #{error.message}")
        end
        result
      end

      #: (FilterForm filter) -> Array[GoogleCalendar::EventView]?
      def list_events(filter)
        result = google_calendar.list_events(settings.events_calendar_id, query: filter.query)
        if (error = result.error)
          logger.error("Failed to load events: #{error.class}: #{error.message}")
          return nil
        end

        values = filter.selected_values
        return result.value if values.empty?

        result.value.select do |event|
          source = event.source
          source = nil if source && source.empty?
          values.include?(source)
        end
      end
    end

    get "/" do
      @page_title = "Needham Circle"
      @page_description = "Upcoming community events in Needham Circle. Browse what's happening, and submit your own events."
      @events = list_events(@filter = FilterForm.new(params))
      erb :index
    end

    get "/events" do
      @events = list_events(@filter = FilterForm.new(params))
      erb :events_list, layout: false
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
        if (error = create_event(@event).error)
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
