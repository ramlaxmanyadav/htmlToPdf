require "combustion"
Combustion.initialize! :action_controller, :action_view, :active_record, :active_job, :active_storage

require "rspec/rails"
require "active_job/test_helper"
require "htmlToPdf"

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include ActiveJob::TestHelper

  config.before do
    HtmlToPdf.reset_configuration!
    HtmlToPdf::ConcurrencyLimiter.reset!
  end

  # Specs tagged :chrome exercise a real headless Chrome/Chromium process.
  # Skip them with a clear reason rather than a confusing Ferrum crash when
  # no browser is installed, so running the suite stays contributor-friendly
  # on a machine that just doesn't have Chrome.
  chrome_available =
    begin
      browser = Ferrum::Browser.new
      true
    rescue Ferrum::BinaryNotFoundError
      false
    ensure
      browser&.quit
    end

  config.filter_run_excluding(chrome: true) unless chrome_available
end
