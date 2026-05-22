# frozen_string_literal: true

module NeedhamCircle
  class RateLimit
    MAX_TRACKED = 10_000

    def initialize(app, limit:, period:, path:)
      raise ArgumentError, "limit must be positive" unless limit.positive?
      raise ArgumentError, "period must be positive" unless period.positive?

      @app = app

      @limit = limit
      @period = period
      @path = path

      @hits = {}
      @last_sweep = monotonic_now
      @mutex = Mutex.new

      @too_many = [
        429,
        { "content-type" => "text/plain", "retry-after" => "#{period}" }.freeze,
        ["Too many submissions. Please try again later.\n"].freeze
      ].freeze
    end

    def call(env)
      if env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == @path
        return @too_many if rate_limited?(Rack::Request.new(env).ip)
      end

      @app.call(env)
    end

    private

    def rate_limited?(ip)
      now = monotonic_now
      cutoff = now - @period

      @mutex.synchronize do
        if now - @last_sweep >= @period
          @hits.delete_if { |_, hits| (hits.last || 0) <= cutoff }
          @last_sweep = now
        end

        hits = @hits.delete(ip) || []
        hits.shift while hits.first && hits.first <= cutoff

        limited = hits.size >= @limit
        hits << now unless limited

        @hits[ip] = hits
        @hits.shift while @hits.size > MAX_TRACKED

        limited
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
    end
  end
end
