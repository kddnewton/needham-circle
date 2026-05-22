# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "needham_circle"
require "minitest/autorun"
require "rack/test"

NeedhamCircle::App.set :service_account_key, "fake-key"
NeedhamCircle::App.set :events_calendar_id, "events-cal-id"
NeedhamCircle::App.set :submissions_calendar_id, "submissions-cal-id"
NeedhamCircle::App.set :session_secret, "x" * 64

# Empty permitted_hosts disables HostAuthorization; rack-test's default
# Host of example.org would not match the production allowlist otherwise.
NeedhamCircle::App.set :host_authorization, permitted_hosts: []
