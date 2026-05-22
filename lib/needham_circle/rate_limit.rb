# frozen_string_literal: true

module NeedhamCircle
  class RateLimit
    class Monotonic
      def call
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
      end
    end

    MAX_TRACKED = 10_000

    def initialize(app, limit:, period:, path:, monotonic: Monotonic.new)
      raise ArgumentError, "limit must be positive" unless limit.positive?
      raise ArgumentError, "period must be positive" unless period.positive?

      @app = app

      @limit = limit
      @period = period
      @path = path

      @monotonic = monotonic
      @last_sweep = monotonic.call

      @hits = {}
      @mutex = Mutex.new

      @retry_after = period.to_s
      @too_many_body = ["Too many submissions. Please try again later.\n"].freeze
    end

    def call(env)
      if env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == @path
        if rate_limited?(Rack::Request.new(env).ip)
          return [
            429,
            { "content-type" => "text/plain", "retry-after" => @retry_after },
            @too_many_body
          ]
        end
      end

      @app.call(env)
    end

    private

    def rate_limited?(ip)
      now = @monotonic.call
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
  end
end
