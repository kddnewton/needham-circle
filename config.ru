$:.unshift File.expand_path("lib", __dir__)
require "needham_circle"

secrets = NeedhamCircle::Env.secrets

NeedhamCircle::App.set :service_account_key, secrets.fetch("SERVICE_ACCOUNT_KEY")
NeedhamCircle::App.set :events_calendar_id, secrets.fetch("EVENTS_CALENDAR_ID")
NeedhamCircle::App.set :submissions_calendar_id, secrets.fetch("SUBMISSIONS_CALENDAR_ID")
NeedhamCircle::App.set :session_secret, secrets.fetch("SESSION_SECRET")
NeedhamCircle::App.set :smtp_account, "needhamcircle@gmail.com"
NeedhamCircle::App.set :smtp_password, secrets.fetch("SMTP_PASSWORD")

run NeedhamCircle::App
