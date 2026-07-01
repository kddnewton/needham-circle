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
      email_field :email, "Email", required: true, max_length: 200

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

      #: () -> Array[Source]
      def selected_sources
        coerced = coerced_for(:source)
        Source::ALL.select { |source| coerced.include?(source.slug) }
      end

      #: () -> Integer
      def selected_sources_size
        coerced_for(:source).size
      end

      #: (String slug) -> String
      def toggle_url(slug)
        slugs = coerced_for(:source)
        slugs = slugs.include?(slug) ? slugs - [slug] : slugs + [slug]
        filter_url(slugs)
      end

      #: () -> String
      def select_all_url
        filter_url(Source::ALL.map(&:slug))
      end

      #: () -> String
      def clear_sources_url
        filter_url([])
      end

      private

      # Builds a "/" URL for the given source selection, preserving the current
      # search query. The source param is comma-joined (see MultiSelectField).
      #: (Array[String] slugs) -> String
      def filter_url(slugs)
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

        values = filter.selected_sources.map(&:value)
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

    get "/about" do
      @page_title = "Needham Circle — About"
      @page_description = "About Needham Circle."
      erb :about
    end

    get "/resources" do
      @page_title = "Needham Circle — Resources"
      @page_description = "Community resources for Needham: town offices, affinity groups, nonprofits, and parks."
      @sections = Resources::SECTIONS
      @wide = true
      erb :resources
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
