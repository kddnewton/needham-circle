# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class LetsBikeTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
      end

      def test_inserts_when_no_existing_events
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(id: "a"),
                event_payload(id: "b", title: "Group Ride")
              ]
            }
          )

        assert sync.call
        assert_equal 2, @calendar.upserts.size
        assert_nil @calendar.upserts[0][0]
        assert_equal "a", @calendar.upserts[0][1].source_id
        assert_equal "Group Ride", @calendar.upserts[1][1].title
      end

      def test_updates_when_source_id_matches_existing
        @calendar.existing = { "a" => "google-evt-1" }
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(id: "a", title: "Updated"),
                event_payload(id: "b", title: "New")
              ]
            }
          )

        assert sync.call
        assert_equal "google-evt-1", @calendar.upserts[0][0]
        assert_equal "Updated", @calendar.upserts[0][1].title
        assert_nil @calendar.upserts[1][0]
      end

      def test_returns_true_with_no_upserts_when_upcoming_empty
        sync = build_sync(payload: { "upcoming" => [] })
        assert sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_and_skips_upserts_on_list_error
        @calendar.list_error = Google::Apis::ServerError.new("boom")
        sync = build_sync(payload: { "upcoming" => [event_payload(id: "a")] })

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_sync(payload: nil)
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_any_upsert_fails
        @calendar.upsert_error = Google::Apis::ServerError.new("nope")
        sync = build_sync(payload: { "upcoming" => [event_payload(id: "a")] })

        refute sync.call
        assert_equal 1, @calendar.upserts.size
      end

      def test_strips_html_from_body
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(
                  id: "a",
                  body: "<div><p>Hello <strong>world</strong></p>\n<p>More</p></div>"
                )
              ]
            }
          )

        assert sync.call
        assert_equal "Hello world\nMore", @calendar.upserts[0][1].description
      end

      def test_formats_text_address_location
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(
                  id: "a",
                  location: {
                    "addressTitle" => "Town Hall",
                    "addressLine1" => "1471 Highland Ave",
                    "addressCity" => "Needham",
                    "addressRegion" => "MA",
                    "addressPostalCode" => "02492"
                  }
                )
              ]
            }
          )

        assert sync.call
        assert_equal "Town Hall, 1471 Highland Ave, Needham, MA, 02492",
                     @calendar.upserts[0][1].location
      end

      def test_skips_blank_address_parts_and_lat_lng
        # Squarespace returns lat/lng-only locations with empty address strings.
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(
                  id: "a",
                  location: {
                    "mapLat" => 42.28,
                    "mapLng" => -71.24,
                    "addressTitle" => "",
                    "addressLine1" => ""
                  }
                )
              ]
            }
          )

        assert sync.call
        assert_equal "", @calendar.upserts[0][1].location
      end

      def test_converts_unix_ms_to_utc_iso_with_z_suffix
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(id: "a", startDate: 1779835500078, endDate: 1779840000078)
              ]
            }
          )

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "2026-05-26T22:45:00Z", event.start_at
        assert_equal "2026-05-27T00:00:00Z", event.end_at
      end

      def test_prepends_base_url_to_relative_full_url
        sync =
          build_sync(
            payload: {
              "upcoming" => [event_payload(id: "a", fullUrl: "/events/needham-bike-moms-1")]
            }
          )

        assert sync.call
        assert_equal "https://www.letsbikeneedham.com/events/needham-bike-moms-1",
                     @calendar.upserts[0][1].url
      end

      def test_leaves_absolute_full_url_alone
        sync =
          build_sync(
            payload: {
              "upcoming" => [
                event_payload(id: "a", fullUrl: "https://example.com/x")
              ]
            }
          )

        assert sync.call
        assert_equal "https://example.com/x", @calendar.upserts[0][1].url
      end

      def test_timezone_is_always_iana
        sync = build_sync(payload: { "upcoming" => [event_payload(id: "a")] })

        assert sync.call
        assert_equal "America/New_York", @calendar.upserts[0][1].timezone
      end

      private

      def build_sync(payload:)
        Runner.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetcher: LetsBike.new(fetch: -> { payload })
        )
      end

      def event_payload(id:, **overrides)
        {
          "id" => id,
          "title" => "Event #{id}",
          "body" => "",
          "fullUrl" => "/events/#{id}",
          "startDate" => 1779835500078,
          "endDate" => 1779840000078,
          "location" => {}
        }.merge(overrides.transform_keys(&:to_s))
      end
    end
  end
end
