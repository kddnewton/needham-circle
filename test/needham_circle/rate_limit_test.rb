# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class RateLimitTest < Minitest::Test
    INNER_APP = ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }

    def build_limiter(limit: 5, period: 60, path: "/submit", monotonic: RateLimit::Monotonic.new)
      RateLimit.new(INNER_APP, limit: limit, period: period, path: path, monotonic: monotonic)
    end

    def post_env(path, ip)
      Rack::MockRequest.env_for(path, method: "POST", "REMOTE_ADDR" => ip)
    end

    def get_env(path, ip)
      Rack::MockRequest.env_for(path, method: "GET", "REMOTE_ADDR" => ip)
    end

    def test_initialize_raises_on_zero_limit
      assert_raises(ArgumentError) { build_limiter(limit: 0) }
    end

    def test_initialize_raises_on_negative_period
      assert_raises(ArgumentError) { build_limiter(period: -1) }
    end

    def test_allows_requests_below_limit
      limiter = build_limiter(limit: 3, period: 60)
      3.times do
        assert_equal 200, limiter.call(post_env("/submit", "1.1.1.1"))[0]
      end
    end

    def test_rejects_requests_above_limit
      limiter = build_limiter(limit: 2, period: 60)
      2.times { limiter.call(post_env("/submit", "2.2.2.2")) }
      status, headers, body = limiter.call(post_env("/submit", "2.2.2.2"))
      assert_equal 429, status
      assert_equal "60", headers["retry-after"]
      assert_equal "text/plain", headers["content-type"]
      assert_includes body.first, "Too many submissions"
    end

    def test_per_ip_isolation
      limiter = build_limiter(limit: 1, period: 60)
      assert_equal 200, limiter.call(post_env("/submit", "3.3.3.3"))[0]
      assert_equal 200, limiter.call(post_env("/submit", "4.4.4.4"))[0]
      assert_equal 429, limiter.call(post_env("/submit", "3.3.3.3"))[0]
      assert_equal 429, limiter.call(post_env("/submit", "4.4.4.4"))[0]
    end

    def test_path_gate_only_limits_configured_path
      limiter = build_limiter(limit: 1, period: 60)
      assert_equal 200, limiter.call(post_env("/submit", "5.5.5.5"))[0]
      assert_equal 429, limiter.call(post_env("/submit", "5.5.5.5"))[0]
      assert_equal 200, limiter.call(post_env("/other", "5.5.5.5"))[0]
      assert_equal 200, limiter.call(post_env("/other", "5.5.5.5"))[0]
    end

    def test_method_gate_only_limits_post
      limiter = build_limiter(limit: 1, period: 60)
      assert_equal 200, limiter.call(post_env("/submit", "6.6.6.6"))[0]
      assert_equal 429, limiter.call(post_env("/submit", "6.6.6.6"))[0]
      assert_equal 200, limiter.call(get_env("/submit", "6.6.6.6"))[0]
      assert_equal 200, limiter.call(get_env("/submit", "6.6.6.6"))[0]
    end

    def test_resets_after_period_expires
      clock = 0
      limiter = build_limiter(limit: 1, period: 60, monotonic: -> { clock })

      clock = 10
      assert_equal 200, limiter.call(post_env("/submit", "7.7.7.7"))[0]
      assert_equal 429, limiter.call(post_env("/submit", "7.7.7.7"))[0]

      clock = 200
      assert_equal 200, limiter.call(post_env("/submit", "7.7.7.7"))[0]
    end
  end
end
