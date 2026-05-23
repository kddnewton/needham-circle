# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :sync do
  def run_sync
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "logger"
    require "needham_circle"

    secrets = NeedhamCircle::Env.secrets
    calendar = NeedhamCircle::GoogleCalendar.new(secrets.fetch("SERVICE_ACCOUNT_KEY"))
    sync =
      yield.new(
        calendar: calendar,
        calendar_id: secrets.fetch("EVENTS_CALENDAR_ID"),
        logger: Logger.new($stdout)
      )

    exit(sync.call ? 0 : 1)
  end

  desc "Sync LWV-Needham events into the public Google Calendar"
  task(:lwv) { run_sync { NeedhamCircle::Sync::Lwv } }

  desc "Sync Let's Bike Needham events into the public Google Calendar"
  task(:lets_bike) { run_sync { NeedhamCircle::Sync::LetsBike } }

  desc "Sync Town of Needham (needhamma.gov) events into the public Google Calendar"
  task(:needham_gov) { run_sync { NeedhamCircle::Sync::NeedhamGov } }

  desc "Sync Needham Rotary Club events into the public Google Calendar"
  task(:needham_rotary) { run_sync { NeedhamCircle::Sync::NeedhamRotary } }
end
