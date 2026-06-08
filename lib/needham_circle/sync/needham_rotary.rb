# frozen_string_literal: true

require "icalendar"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    class NeedhamRotary
      ENDPOINT = "https://needhamrotaryclub.org/calendar-feed"

      # ClubRunner emits times as UTC with a trailing `Z` and no TZID. We
      # re-emit them as UTC ISO with the same `Z` suffix; Google reads the
      # absolute instant and applies America/New_York for display.
      TIMEZONE = "America/New_York"

      #: (?fetch: ^() -> String?, ?now: Time?, ?logger: Logger?) -> void
      def initialize(fetch: nil, now: nil, logger: nil)
        @fetch = fetch || method(:fetch_from_api)
        @now = now
        @logger = logger
      end

      #: () -> Source
      def source
        Source::RC
      end

      #: () -> Array[Event]?
      def fetch_events
        body = @fetch.call
        return nil if body.nil?

        calendar = Icalendar::Calendar.parse(body).first
        if calendar.nil?
          log("parse produced no VCALENDAR block")
          return nil
        end

        now = (@now || Time.now).to_time
        calendar.events.filter_map do |ics_event|
          next if ics_event.dtend && ics_event.dtend.to_time < now
          build_event(ics_event)
        end
      rescue StandardError => error
        log("parse failed: #{error.class}: #{error.message}")
        nil
      end

      private

      #: () -> String?
      def fetch_from_api
        uri = URI(ENDPOINT)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.get(uri.request_uri, { "User-Agent" => USER_AGENT })
        unless response.is_a?(Net::HTTPSuccess)
          log("fetch returned status #{response.code}")
          return nil
        end

        response.body
      rescue StandardError => error
        log("fetch raised: #{error.class}: #{error.message}")
        nil
      end

      #: (Icalendar::Event ics_event) -> Event
      def build_event(ics_event)
        Event.new(
          source_id: ics_event.uid.to_s,
          title: ics_event.summary.to_s,
          description: ics_event.description.to_s.strip,
          location: ics_event.location.to_s,
          url: "",
          start_at: format_time(ics_event.dtstart),
          end_at: format_time(ics_event.dtend),
          timezone: TIMEZONE
        )
      end

      # ClubRunner DTSTART/DTEND are UTC ("…T160000Z"). Emit ISO with `Z`
      # suffix so Google reads the absolute instant directly.
      #: (Icalendar::Values::DateTime? dt) -> String?
      def format_time(dt)
        return nil if dt.nil?
        dt.to_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::NeedhamRotary #{message}")
      end
    end
  end
end
