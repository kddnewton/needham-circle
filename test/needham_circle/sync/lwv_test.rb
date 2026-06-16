# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class LwvTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
      end

      def test_inserts_when_no_existing_events
        sync =
          build_sync(
            pages: [
              {
                "events" => [event_payload(id: 1, title: "First"), event_payload(id: 2, title: "Second")],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal 2, @calendar.upserts.size
        assert_nil @calendar.upserts[0][0]
        assert_equal "First", @calendar.upserts[0][1].title
        assert_nil @calendar.upserts[1][0]
        assert_equal "Second", @calendar.upserts[1][1].title
      end

      def test_updates_when_source_id_matches_existing
        @calendar.existing = { "1" => "google-evt-7" }
        sync =
          build_sync(
            pages: [
              {
                "events" => [event_payload(id: 1, title: "Updated"), event_payload(id: 2, title: "New")],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "google-evt-7", @calendar.upserts[0][0]
        assert_equal "Updated", @calendar.upserts[0][1].title
        assert_nil @calendar.upserts[1][0]
        assert_equal "New", @calendar.upserts[1][1].title
      end

      def test_paginates_across_multiple_pages
        sync =
          build_sync(
            pages: [
              { "events" => [event_payload(id: 1)], "total_pages" => 2 },
              { "events" => [event_payload(id: 2)], "total_pages" => 2 }
            ]
          )

        assert sync.call
        assert_equal %w[1 2], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_returns_false_and_skips_upserts_on_list_error
        @calendar.list_error = Google::Apis::ServerError.new("boom")
        sync =
          build_sync(
            pages: [{ "events" => [event_payload(id: 1)], "total_pages" => 1 }]
          )

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_sync(pages: [nil])
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_any_upsert_fails
        @calendar.upsert_error = Google::Apis::ServerError.new("nope")
        sync =
          build_sync(
            pages: [{ "events" => [event_payload(id: 1)], "total_pages" => 1 }]
          )

        refute sync.call
        assert_equal 1, @calendar.upserts.size
      end

      def test_strips_html_from_description
        sync =
          build_sync(
            pages: [
              {
                "events" => [
                  event_payload(
                    id: 1,
                    description: "<p>Hello <strong>world</strong></p>\n<p>More</p>"
                  )
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "Hello world\nMore", @calendar.upserts[0][1].description
      end

      def test_formats_venue_address
        sync =
          build_sync(
            pages: [
              {
                "events" => [
                  event_payload(
                    id: 1,
                    venue: {
                      "venue" => "Center at the Heights",
                      "address" => "300 Hillside Ave",
                      "city" => "Needham",
                      "state" => "MA",
                      "zip" => "02494"
                    }
                  )
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "Center at the Heights, 300 Hillside Ave, Needham, MA, 02494",
                     @calendar.upserts[0][1].location
      end

      def test_skips_blank_venue_parts
        sync =
          build_sync(
            pages: [
              {
                "events" => [
                  event_payload(id: 1, venue: { "venue" => "Hall", "address" => "", "city" => "Needham" })
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "Hall, Needham", @calendar.upserts[0][1].location
      end

      def test_converts_tribe_date_format_to_iso
        sync =
          build_sync(
            pages: [
              {
                "events" => [
                  event_payload(
                    id: 1,
                    start_date: "2026-05-28 18:00:00",
                    end_date: "2026-05-28 20:30:00"
                  )
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "2026-05-28T18:00:00", event.start_at
        assert_equal "2026-05-28T20:30:00", event.end_at
      end

      def test_overrides_tribe_timezone_with_iana_zone
        # Tribe returns fixed offsets like "UTC-5" that ignore DST, so we
        # must replace them with an IANA zone before handing to Google.
        sync =
          build_sync(
            pages: [
              { "events" => [event_payload(id: 1, timezone: "UTC-5")], "total_pages" => 1 }
            ]
          )

        assert sync.call
        assert_equal "America/New_York", @calendar.upserts[0][1].timezone
      end

      private

      def build_sync(pages:)
        queue = pages.dup
        Runner.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetcher: Lwv.new(fetch_page: ->(_page) { queue.shift })
        )
      end

      def event_payload(id:, **overrides)
        {
          "id" => id,
          "title" => "Event #{id}",
          "description" => "",
          "url" => "https://example.com/#{id}",
          "start_date" => "2026-05-28 18:00:00",
          "end_date" => "2026-05-28 20:00:00",
          "timezone" => "America/New_York",
          "venue" => {}
        }.merge(overrides.transform_keys(&:to_s))
      end
    end
  end
end
