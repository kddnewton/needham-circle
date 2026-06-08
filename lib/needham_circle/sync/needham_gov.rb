# frozen_string_literal: true

require "icalendar"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    class NeedhamGov
      CATEGORY_ID = 84 # Community Events
      BASE_URL = "https://www.needhamma.gov"
      ENDPOINT = "#{BASE_URL}/common/modules/iCalendar/iCalendar.aspx?catID=#{CATEGORY_ID}&feed=calendar"

      # The feed uses `TZID=America/New_York` consistently. We pass the
      # wall-clock components straight through and let Google apply DST.
      TIMEZONE = "America/New_York"

      # CivicPlus appends a link to the human-readable event page at the end
      # of every description (e.g. "...prose. \n https://...EID=27083"). We
      # strip it because we already build a clean URL from the UID.
      DESCRIPTION_URL_SUFFIX = %r{\s*https://www\.needhamma\.gov/calendar\.aspx\?EID=\d+\s*\z}

      #: (?fetch: ^() -> String?, ?now: DateTime?, ?logger: Logger?) -> void
      def initialize(fetch: nil, now: nil, logger: nil)
        @fetch = fetch || method(:fetch_from_api)
        @now = now
        @logger = logger
      end

      #: () -> Source
      def source
        Source::TN
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

        # Icalendar::Values::DateTime is a SimpleDelegator over Time, so a
        # direct `<` against a plain DateTime hits Time#< and fails. Coerce
        # both sides to Time — also handles Date-valued all-day events.
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
        uid = ics_event.uid.to_s
        Event.new(
          source_id: uid,
          title: ics_event.summary.to_s,
          description: clean_description(ics_event.description),
          location: ics_event.location.to_s,
          url: "#{BASE_URL}/calendar.aspx?EID=#{uid}",
          start_at: format_time(ics_event.dtstart),
          end_at: format_time(ics_event.dtend),
          timezone: TIMEZONE
        )
      end

      #: (Icalendar::Values::DateTime? dt) -> String?
      def format_time(dt)
        return nil if dt.nil?
        dt.strftime("%Y-%m-%dT%H:%M:%S")
      end

      #: (String? text) -> String
      def clean_description(text)
        return "" if text.nil?
        text.to_s.sub(DESCRIPTION_URL_SUFFIX, "").strip
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::NeedhamGov #{message}")
      end
    end
  end
end
