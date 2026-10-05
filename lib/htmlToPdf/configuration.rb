module HtmlToPdf
  class Configuration
    # Hash of keyword options passed straight to Ferrum::Browser.new, e.g.
    # { browser_path: '/usr/bin/chromium', timeout: 20, process_timeout: 30,
    #   browser_options: { 'no-sandbox' => nil } } (the last is for running as
    # root in Docker). Leave empty to let Ferrum auto-detect a local Chrome/
    # Chromium install.
    attr_accessor :browser_options

    attr_accessor :default_layout, :default_options, :tmp_dir

    # header_template/footer_template are raw HTML that Chrome renders
    # as-is — unlike every other print option, they're not a validated
    # number/enum/boolean, so letting a request control them lets a caller
    # embed arbitrary markup (e.g. <img src="http://internal-host/...">,
    # an SSRF vector against your network from the Chrome process). They're
    # only honored from config.default_options (trusted application code)
    # unless this is explicitly enabled. Only set this if pdf_options never
    # flows from unfiltered request params in your app.
    attr_accessor :allow_request_templates

    # Upper bound (ms) on pdf_options[:print_options][:javascript_delay].
    # render_pdf sleeps for this long while holding the pooled browser's
    # page/context open, so an uncapped caller-supplied value would let one
    # request stall every other PDF render sharing that browser.
    attr_accessor :max_javascript_delay_ms

    def initialize
      @browser_options          = {}
      @default_layout           = 'application'
      @default_options          = { print_background: true }
      @tmp_dir                  = nil
      @allow_request_templates  = false
      @max_javascript_delay_ms  = 10_000
    end
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
