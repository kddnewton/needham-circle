# frozen_string_literal: true

module NeedhamCircle
  module Env
    ROOT = File.expand_path("../..", __dir__)

    # Returns a hash-like object (Hash or ENV) supporting `.fetch`. In local
    # development this reads from a `.env` file at the project root; in CI
    # and production we fall back to the process environment.
    #: () -> _Fetchable
    def self.secrets
      filepath = File.expand_path(".env", ROOT)
      if File.exist?(filepath)
        File.foreach(filepath).to_h { |line| line.chomp.split("=", 2) }
      else
        ENV
      end
    end
  end
end
