# frozen_string_literal: true

require "cgi/escape"
require "json"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    class NeedhamObserver
      ENDPOINT = "https://needhamobserver.com/wp-json/tribe/events/v1/events"
      PER_PAGE = 50

      # Tribe's `timezone` field is a fixed offset abbreviation that doesn't
      # track DST. All Needham Observer events are local to Needham, so we hand
      # Google an IANA zone and let it apply DST correctly.
      TIMEZONE = "America/New_York"

      # Needham Observer authors events in the block editor, so the REST
      # `description` wraps the actual prose in Tribe's own rendered blocks: a
      # leading schedule widget, then (after the prose) an "Add to calendar"
      # subscribe dropdown, an event-meta section, and a venue block. Strip the
      # schedule block and everything from the subscribe block onward, leaving
      # just the prose for html_to_text.
      SCHEDULE_BLOCK = %r{<div\b[^>]*tribe-events-schedule\b.*?</div>}mi
      TRAILING_BLOCKS = %r{<div\b[^>]*tribe-block__events-link\b.*\z}mi

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(fetch_page: nil, logger: nil)
        @fetch_page = fetch_page || method(:fetch_page_from_api)
        @logger = logger
      end

      #: () -> Source
      def source
        Source::NO
      end

      #: () -> Array[Event]?
      def fetch_events
        events = []
        page = 1
        loop do
          payload = @fetch_page.call(page)
          return nil if payload.nil?

          (payload["events"] || []).each do |raw|
            events << build_event(raw)
          end

          total_pages = payload["total_pages"] || 1
          break if page >= total_pages
          page += 1
        end
        events
      end

      private

      #: (Integer page) -> Hash[String, untyped]?
      def fetch_page_from_api(page)
        uri = URI(ENDPOINT)
        uri.query =
          URI.encode_www_form(per_page: PER_PAGE, page: page, status: "publish")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.get(uri.request_uri, { "User-Agent" => USER_AGENT })
        unless response.is_a?(Net::HTTPSuccess)
          log("fetch page=#{page} returned status #{response.code}")
          return nil
        end

        JSON.parse(response.body)
      rescue StandardError => error
        log("fetch page=#{page} raised: #{error.class}: #{error.message}")
        nil
      end

      #: (Hash[String, untyped] raw) -> Event
      def build_event(raw)
        Event.new(
          source_id: raw.fetch("id").to_s,
          title: CGI.unescapeHTML(raw["title"].to_s),
          description: clean_description(raw["description"]),
          location: format_location(raw["venue"]),
          url: raw["url"].to_s,
          start_at: format_time(raw["start_date"]),
          end_at: format_time(raw["end_date"]),
          timezone: TIMEZONE
        )
      end

      #: (String? html) -> String
      def clean_description(html)
        return "" if html.nil? || html.empty?

        stripped = html.gsub(SCHEDULE_BLOCK, " ").sub(TRAILING_BLOCKS, "")
        Sync.html_to_text(stripped)
      end

      #: (Hash[String, untyped]? venue) -> String
      def format_location(venue)
        return "" if venue.nil? || venue.empty?

        [
          venue["venue"],
          venue["address"],
          venue["city"],
          venue["state"],
          venue["zip"]
        ].compact.reject { |part| part.to_s.strip.empty? }.join(", ")
      end

      # Tribe returns "2026-05-28 18:00:00" — Google wants ISO-ish with a "T".
      #: (String? string) -> String?
      def format_time(string)
        return nil if string.nil? || string.empty?
        string.sub(" ", "T")
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::NeedhamObserver #{message}")
      end
    end
  end
end
