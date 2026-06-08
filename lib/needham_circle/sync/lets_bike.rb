# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    class LetsBike
      BASE_URL = "https://www.letsbikeneedham.com"
      ENDPOINT = "#{BASE_URL}/events?format=json"

      # Squarespace serves absolute UTC instants (epoch ms), so we send an
      # offset-bearing dateTime to Google and use TIMEZONE only as the
      # display zone — DST is handled by Google.
      TIMEZONE = "America/New_York"

      #: (?fetch: ^() -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(fetch: nil, logger: nil)
        @fetch = fetch || method(:fetch_from_api)
        @logger = logger
      end

      #: () -> Source
      def source
        Source::LBN
      end

      #: () -> Array[Event]?
      def fetch_events
        payload = @fetch.call
        return nil if payload.nil?
        (payload["upcoming"] || []).map { |raw| build_event(raw) }
      end

      private

      #: () -> Hash[String, untyped]?
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

        JSON.parse(response.body)
      rescue StandardError => error
        log("fetch raised: #{error.class}: #{error.message}")
        nil
      end

      #: (Hash[String, untyped] raw) -> Event
      def build_event(raw)
        Event.new(
          source_id: raw.fetch("id").to_s,
          title: raw["title"].to_s,
          description: clean_description(raw["body"]),
          location: format_location(raw["location"]),
          url: full_url(raw["fullUrl"]),
          start_at: ms_to_iso(raw["startDate"]),
          end_at: ms_to_iso(raw["endDate"]),
          timezone: TIMEZONE
        )
      end

      #: (Integer? ms) -> String?
      def ms_to_iso(ms)
        return nil if ms.nil?
        Time.at(ms / 1000.0).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      #: (String? html) -> String
      def clean_description(html)
        return "" if html.nil? || html.empty?
        html.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip
      end

      #: (Hash[String, untyped]? location) -> String
      def format_location(location)
        return "" if location.nil? || location.empty?

        [
          location["addressTitle"],
          location["addressLine1"],
          location["addressLine2"],
          location["addressCity"],
          location["addressRegion"],
          location["addressPostalCode"]
        ].compact.reject { |part| part.to_s.strip.empty? }.join(", ")
      end

      #: (String? path) -> String
      def full_url(path)
        return "" if path.nil? || path.empty?
        return path if path.start_with?("http")
        "#{BASE_URL}#{path.start_with?("/") ? path : "/#{path}"}"
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::LetsBike #{message}")
      end
    end
  end
end
