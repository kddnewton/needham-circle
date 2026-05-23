# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # Normalized shape produced by every source-specific syncer. Times are
    # strings in "YYYY-MM-DDTHH:MM:SS" form, paired with an IANA timezone, so
    # Google Calendar receives wall-clock times in the source's zone rather
    # than having us round-trip through Ruby Time and risk a TZ shift.
    Event =
      Struct.new(
        :source_id,
        :title,
        :description,
        :location,
        :url,
        :start_at,
        :end_at,
        :timezone,
        keyword_init: true
      )
  end
end
