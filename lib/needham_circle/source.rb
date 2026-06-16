# frozen_string_literal: true

module NeedhamCircle
  # An event source.
  class Source
    attr_reader :slug, :label #: String
    attr_reader :value #: String?

    def initialize(slug, label, value)
      @slug = slug
      @label = label
      @value = value
      freeze
    end

    ALL = [
      NIL = Source.new("community", "Community Submissions", nil),
      LWV = Source.new("lwv", "League of Women Voters", "lwv-needham"),
      LBN = Source.new("lets-bike", "Let's Bike Needham", "lets-bike-needham"),
      NO = Source.new("observer", "Needham Observer", "needham-observer"),
      RC = Source.new("rotary", "Rotary Club", "needham-rotary"),
      TN = Source.new("town", "Town of Needham", "needham-gov")
    ].freeze
  end
end
