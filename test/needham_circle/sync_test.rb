# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class HtmlToTextTest < Minitest::Test
      def test_returns_empty_for_nil_or_blank
        assert_equal "", Sync.html_to_text(nil)
        assert_equal "", Sync.html_to_text("")
      end

      def test_strips_tags_and_collapses_whitespace
        assert_equal "Hello world\nMore", Sync.html_to_text("<p>Hello <strong>world</strong></p>\n<p>More</p>")
      end

      def test_breaks_blocks_onto_separate_lines
        assert_equal "One\nTwo", Sync.html_to_text("<p>One</p><p>Two</p>")
      end

      def test_converts_br_to_newline
        assert_equal "One\nTwo", Sync.html_to_text("One<br>Two")
      end

      def test_collapses_newline_runs_to_single_break
        assert_equal "One\nTwo", Sync.html_to_text("<p>One</p>\n\n<div></div><p>Two</p>")
      end

      def test_drops_style_and_script_block_contents
        html = %q{<p>Ride with us</p><style>.btn{color:#fff}</style><script>track();</script>}
        assert_equal "Ride with us", Sync.html_to_text(html)
      end

      def test_decodes_entities_including_nbsp
        assert_equal "Bikes & gear It’s fun", Sync.html_to_text("Bikes&nbsp;&amp; gear It&#8217;s fun")
      end
    end
  end
end
