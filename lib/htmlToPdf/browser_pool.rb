require "ferrum"

module HtmlToPdf
  # Keeps a single headless Chrome process alive per Ruby process (starting
  # Chrome per-request costs several hundred ms) and hands out a fresh,
  # isolated browser context per conversion so pages never share cookies or
  # state. Automatically restarts the browser once if Chrome has crashed or
  # stopped responding.
  module BrowserPool
    MUTEX = Mutex.new

    RECOVERABLE_ERRORS = [
      Ferrum::DeadBrowserError,
      Ferrum::ProcessTimeoutError,
      Ferrum::TimeoutError,
      Ferrum::NoSuchPageError
    ].freeze

    module_function

    def with_page
      attempts = 0
      begin
        attempts += 1
        # The block form is required: it's the only way Ferrum disposes the
        # browser context afterward. Closing just the page (as a bare
        # `create_page(new_context: true)` + `page.close` would) leaks a
        # context per call, which adds up fast in a long-lived pooled browser.
        browser.create_page(new_context: true) { |page| yield page }
      rescue *RECOVERABLE_ERRORS
        reset!
        retry if attempts < 2
        raise
      end
    end

    def browser
      MUTEX.synchronize do
        @browser ||= Ferrum::Browser.new(**HtmlToPdf.configuration.browser_options)
      end
    end

    def reset!
      MUTEX.synchronize do
        @browser&.quit
        @browser = nil
      end
    end
  end
end
