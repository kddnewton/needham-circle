$:.unshift File.expand_path("lib", __dir__)
require "needham_circle"

secrets =
  if File.exist?((filepath = File.expand_path(".env", __dir__)))
    File.foreach(filepath).to_h { |line| line.chomp.split("=", 2) }
  else
    ENV
  end

NeedhamCircle::App.set :service_account_key, secrets.fetch("SERVICE_ACCOUNT_KEY")
NeedhamCircle::App.set :events_calendar_id, secrets.fetch("EVENTS_CALENDAR_ID")
NeedhamCircle::App.set :submissions_calendar_id, secrets.fetch("SUBMISSIONS_CALENDAR_ID")

run NeedhamCircle::App
