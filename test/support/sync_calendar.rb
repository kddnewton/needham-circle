# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # Shared in-memory calendar for sync tests. `existing` maps source_id =>
    # google_event_id (the shape source_ids returns); `upserts` records each
    # [existing_event_id, event] passed to upsert_source_event.
    class FakeCalendar
      attr_accessor :existing, :list_error, :upsert_error
      attr_reader :upserts

      def initialize
        @existing = {}
        @list_error = nil
        @upsert_error = nil
        @upserts = []
      end

      def source_ids(_calendar_id, _source)
        GoogleCalendar::Result.new(@list_error ? nil : @existing, @list_error)
      end

      def upsert_source_event(_calendar_id, _source, existing_event_id, event)
        @upserts << [existing_event_id, event]
        GoogleCalendar::Result.new(@upsert_error ? nil : true, @upsert_error)
      end
    end
  end
end
