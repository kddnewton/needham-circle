# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # Syncs one source's events into the calendar. The source-specific work —
    # which Source, and fetching/parsing its feed — is delegated to `fetcher`,
    # an object responding to #source and #fetch_events.
    class Runner
      #: (calendar: GoogleCalendar, calendar_id: String, fetcher: untyped, ?logger: Logger?) -> void
      def initialize(calendar:, calendar_id:, fetcher:, logger: nil)
        @calendar = calendar
        @calendar_id = calendar_id
        @fetcher = fetcher
        @logger = logger
      end

      #: () -> bool
      def call
        source = @fetcher.source
        result = @calendar.source_ids(@calendar_id, source.value)
        if (error = result.error)
          log(source, "source_ids failed: #{error.class}: #{error.message}")
          return false
        end
        existing_ids = result.value

        events = @fetcher.fetch_events
        return false if events.nil?

        ok = true
        events.each do |event|
          result =
            @calendar.upsert_source_event(@calendar_id, source.value, existing_ids[event.source_id], event)
          if (error = result.error)
            ok = false
            log(source, "upsert failed for #{event.source_id}: #{error.class}: #{error.message}")
          end
        end
        ok
      end

      private

      #: (Source source, String message) -> void
      def log(source, message)
        @logger&.error("Sync[#{source.slug}] #{message}")
      end
    end
  end
end
