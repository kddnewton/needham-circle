# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class NeedhamObserverTest < Minitest::Test
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

      def test_decodes_html_entities_in_title
        sync =
          build_sync(
            pages: [
              {
                "events" => [event_payload(id: 1, title: "The Council&#8217;s Memory Cafe")],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "The Council’s Memory Cafe", @calendar.upserts[0][1].title
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

      def test_strips_tribe_boilerplate_blocks_from_description
        # The REST description wraps prose in Tribe's rendered blocks: a leading
        # schedule widget and, after the prose, a subscribe dropdown / event
        # meta / venue block. Only the prose should survive.
        description = <<~HTML
          <div class="tribe-events-schedule tribe-clearfix"><p>@</p></div>
          Join us for the real event details.
          <div class="tribe-block tribe-block__events-link"><div>Add to calendar</div>
          <div>Google Calendar</div></div>
          <div class="tribe-events-event-meta"><h3>Details</h3></div>
        HTML

        sync =
          build_sync(
            pages: [
              { "events" => [event_payload(id: 1, description: description)], "total_pages" => 1 }
            ]
          )

        assert sync.call
        assert_equal "Join us for the real event details.", @calendar.upserts[0][1].description
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
                      "venue" => "new art center",
                      "address" => "61 Washington Park",
                      "city" => "Newton",
                      "state" => "MA",
                      "zip" => "02460"
                    }
                  )
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "new art center, 61 Washington Park, Newton, MA, 02460",
                     @calendar.upserts[0][1].location
      end

      def test_skips_blank_and_nil_venue_parts
        sync =
          build_sync(
            pages: [
              {
                "events" => [
                  event_payload(
                    id: 1,
                    venue: { "venue" => "Needham Public Library", "address" => "", "city" => "Needham", "state" => nil }
                  )
                ],
                "total_pages" => 1
              }
            ]
          )

        assert sync.call
        assert_equal "Needham Public Library, Needham", @calendar.upserts[0][1].location
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
          fetcher: NeedhamObserver.new(fetch_page: ->(_page) { queue.shift })
        )
      end

      def event_payload(id:, **overrides)
        {
          "id" => id,
          "title" => "Event #{id}",
          "description" => "",
          "url" => "https://needhamobserver.com/event/#{id}/",
          "start_date" => "2026-05-28 18:00:00",
          "end_date" => "2026-05-28 20:00:00",
          "timezone" => "America/New_York",
          "venue" => {}
        }.merge(overrides.transform_keys(&:to_s))
      end
    end
  end
end
