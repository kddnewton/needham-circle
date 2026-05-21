# frozen_string_literal: true

require "sinatra"
require "google/apis/calendar_v3"

$secrets =
  if File.exist?((filepath = File.expand_path(".env", __dir__)))
    File.foreach(filepath).to_h { |line| line.chomp.split("=", 2) }
  else
    ENV
  end

def list_events
  service = Google::Apis::CalendarV3::CalendarService.new
  service.key = $secrets.fetch("GOOGLE_API_KEY")

  begin
    service
      .list_events(
        $secrets.fetch("EVENTS_CALENDAR_ID"),
        single_events: true,
        order_by: "startTime",
        time_min: Time.now.iso8601,
        max_results: 50
      )
      .items
  rescue => error
    logger.error("Failed to load events: #{error.class}: #{error.message}")
    nil
  end
end

get "/" do
  @events = list_events
  erb :index
end
