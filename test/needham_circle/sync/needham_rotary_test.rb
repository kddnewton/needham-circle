# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class NeedhamRotaryTest < Minitest::Test
      SourceView = Struct.new(:id, :source_id)

      class FakeCalendar
        attr_accessor :existing, :list_error, :upsert_error
        attr_reader :upserts

        def initialize
          @existing = []
          @list_error = nil
          @upsert_error = nil
          @upserts = []
        end

        def list_events_by_source(_calendar_id, _source)
          GoogleCalendar::Result.new(@list_error ? nil : @existing, @list_error)
        end

        def upsert_source_event(_calendar_id, _source, existing_event_id, event)
          @upserts << [existing_event_id, event]
          GoogleCalendar::Result.new(@upsert_error ? nil : true, @upsert_error)
        end
      end

      UUID_A = "bf52954d-f0d3-4887-b7f8-b42f7bed496b"
      UUID_B = "78767a9f-c7a8-45ff-806a-e24718113ea3"

      def setup
        @calendar = FakeCalendar.new
        @now = Time.utc(2026, 5, 22, 12, 0, 0)
      end

      def test_inserts_when_no_existing_events
        sync = build_sync(events: [vevent(uid: UUID_A), vevent(uid: UUID_B, summary: "Mental Health")])

        assert sync.call
        assert_equal 2, @calendar.upserts.size
        assert_nil @calendar.upserts[0][0]
        assert_equal UUID_A, @calendar.upserts[0][1].source_id
        assert_equal "Mental Health", @calendar.upserts[1][1].title
      end

      def test_updates_when_uuid_matches_existing
        @calendar.existing = [SourceView.new("google-evt-1", UUID_A)]
        sync = build_sync(events: [vevent(uid: UUID_A, summary: "Updated"), vevent(uid: UUID_B)])

        assert sync.call
        assert_equal "google-evt-1", @calendar.upserts[0][0]
        assert_equal "Updated", @calendar.upserts[0][1].title
        assert_nil @calendar.upserts[1][0]
      end

      def test_filters_past_events_using_dtend
        sync =
          build_sync(
            events: [
              vevent(uid: UUID_A, dtstart: "20250506T160000Z", dtend: "20250506T170000Z"),
              vevent(uid: UUID_B, dtstart: "20260601T160000Z", dtend: "20260601T170000Z")
            ]
          )

        assert sync.call
        assert_equal [UUID_B], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_returns_false_and_skips_upserts_on_list_error
        @calendar.list_error = Google::Apis::ServerError.new("boom")
        sync = build_sync(events: [vevent(uid: UUID_A)])

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = NeedhamRotary.new(calendar: @calendar, calendar_id: "events-cal-id", fetch: -> { nil }, now: @now)
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_parse_yields_no_vcalendar
        sync = NeedhamRotary.new(calendar: @calendar, calendar_id: "events-cal-id", fetch: -> { "not ics" }, now: @now)
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_any_upsert_fails
        @calendar.upsert_error = Google::Apis::ServerError.new("nope")
        sync = build_sync(events: [vevent(uid: UUID_A)])

        refute sync.call
        assert_equal 1, @calendar.upserts.size
      end

      def test_emits_utc_iso_with_z_suffix
        sync =
          build_sync(
            events: [vevent(uid: UUID_A, dtstart: "20260601T160000Z", dtend: "20260601T170000Z")]
          )

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "2026-06-01T16:00:00Z", event.start_at
        assert_equal "2026-06-01T17:00:00Z", event.end_at
        assert_equal "America/New_York", event.timezone
      end

      def test_leaves_url_blank
        sync = build_sync(events: [vevent(uid: UUID_A)])

        assert sync.call
        assert_equal "", @calendar.upserts[0][1].url
      end

      def test_empty_location_passes_through
        sync = build_sync(events: [vevent(uid: UUID_A, location: "")])

        assert sync.call
        assert_equal "", @calendar.upserts[0][1].location
      end

      private

      def build_sync(events:)
        ics = build_ics(events)
        NeedhamRotary.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetch: -> { ics },
          now: @now
        )
      end

      def vevent(uid:, summary: "Event", description: "Update on all things library",
                 location: "", dtstart: "20260601T160000Z", dtend: "20260601T170000Z")
        { uid: uid, summary: summary, description: description, location: location,
          dtstart: dtstart, dtend: dtend }
      end

      def build_ics(events)
        body = events.map { |e| <<~VEVENT.chomp }.join("\n")
          BEGIN:VEVENT
          UID:#{e[:uid]}
          SUMMARY:#{e[:summary]}
          DESCRIPTION:#{e[:description]}
          LOCATION:#{e[:location]}
          DTSTART:#{e[:dtstart]}
          DTEND:#{e[:dtend]}
          END:VEVENT
        VEVENT

        <<~ICS
          BEGIN:VCALENDAR
          PRODID:test
          VERSION:2.0
          #{body}
          END:VCALENDAR
        ICS
      end
    end
  end
end
