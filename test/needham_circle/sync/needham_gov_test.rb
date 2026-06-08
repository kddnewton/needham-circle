# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class NeedhamGovTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
        @now = DateTime.new(2026, 5, 22, 12, 0, 0, "-04:00")
      end

      def test_inserts_when_no_existing_events
        sync = build_sync(events: [vevent(uid: "27083"), vevent(uid: "27397", summary: "Group Ride")])

        assert sync.call
        assert_equal 2, @calendar.upserts.size
        assert_nil @calendar.upserts[0][0]
        assert_equal "27083", @calendar.upserts[0][1].source_id
        assert_equal "Group Ride", @calendar.upserts[1][1].title
      end

      def test_updates_when_uid_matches_existing
        @calendar.existing = { "27083" => "google-evt-1" }
        sync = build_sync(events: [vevent(uid: "27083", summary: "Updated"), vevent(uid: "27397")])

        assert sync.call
        assert_equal "google-evt-1", @calendar.upserts[0][0]
        assert_equal "Updated", @calendar.upserts[0][1].title
        assert_nil @calendar.upserts[1][0]
      end

      def test_filters_past_events_using_dtend
        sync =
          build_sync(
            events: [
              vevent(uid: "past", dtstart: "20260501T100000", dtend: "20260501T110000"),
              vevent(uid: "future", dtstart: "20260601T100000", dtend: "20260601T110000")
            ]
          )

        assert sync.call
        assert_equal ["future"], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_returns_true_with_no_upserts_when_feed_has_no_events
        sync = build_sync(events: [])
        assert sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_and_skips_upserts_on_list_error
        @calendar.list_error = Google::Apis::ServerError.new("boom")
        sync = build_sync(events: [vevent(uid: "27083")])

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_runner(NeedhamGov.new(fetch: -> { nil }, now: @now))
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_parse_fails
        sync = build_runner(NeedhamGov.new(fetch: -> { "not ics" }, now: @now))
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_any_upsert_fails
        @calendar.upsert_error = Google::Apis::ServerError.new("nope")
        sync = build_sync(events: [vevent(uid: "27083")])

        refute sync.call
        assert_equal 1, @calendar.upserts.size
      end

      def test_strips_trailing_civicplus_url_from_description
        description = "Prose here. https://www.needhamma.gov/calendar.aspx?EID=27083"
        sync = build_sync(events: [vevent(uid: "27083", description: description)])

        assert sync.call
        assert_equal "Prose here.", @calendar.upserts[0][1].description
      end

      def test_description_with_only_civicplus_url_becomes_empty
        sync =
          build_sync(
            events: [vevent(uid: "27388", description: "https://www.needhamma.gov/calendar.aspx?EID=27388")]
          )

        assert sync.call
        assert_equal "", @calendar.upserts[0][1].description
      end

      def test_url_is_built_from_uid_not_from_ical_url_field
        sync = build_sync(events: [vevent(uid: "27083")])

        assert sync.call
        assert_equal "https://www.needhamma.gov/calendar.aspx?EID=27083",
                     @calendar.upserts[0][1].url
      end

      def test_wall_clock_time_preserved_from_tzid
        sync =
          build_sync(
            events: [vevent(uid: "1", dtstart: "20260615T140000", dtend: "20260615T153000")]
          )

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "2026-06-15T14:00:00", event.start_at
        assert_equal "2026-06-15T15:30:00", event.end_at
        assert_equal "America/New_York", event.timezone
      end

      private

      def build_sync(events:)
        ics = build_ics(events)
        build_runner(NeedhamGov.new(fetch: -> { ics }, now: @now))
      end

      def build_runner(fetcher)
        Runner.new(calendar: @calendar, calendar_id: "events-cal-id", fetcher: fetcher)
      end

      def vevent(uid:, summary: "Event #{uid}", description: "", location: "Town Hall",
                 dtstart: "20260615T140000", dtend: "20260615T150000")
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
          DTSTART;TZID=America/New_York:#{e[:dtstart]}
          DTEND;TZID=America/New_York:#{e[:dtend]}
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
