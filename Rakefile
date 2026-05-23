# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :sync do
  desc "Sync LWV-Needham events into the public Google Calendar"
  task :lwv do
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "logger"
    require "needham_circle"

    secrets = NeedhamCircle::Env.secrets
    calendar = NeedhamCircle::GoogleCalendar.new(secrets.fetch("SERVICE_ACCOUNT_KEY"))
    sync =
      NeedhamCircle::Sync::Lwv.new(
        calendar: calendar,
        calendar_id: secrets.fetch("EVENTS_CALENDAR_ID"),
        logger: Logger.new($stdout)
      )

    exit(sync.call ? 0 : 1)
  end
end
