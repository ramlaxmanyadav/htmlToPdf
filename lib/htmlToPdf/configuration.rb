module HtmlToPdf
  class Configuration
    # Hash of keyword options passed straight to Ferrum::Browser.new, e.g.
    # { browser_path: '/usr/bin/chromium', timeout: 20, process_timeout: 30,
    #   browser_options: { 'no-sandbox' => nil } } (the last is for running as
    # root in Docker). Leave empty to let Ferrum auto-detect a local Chrome/
    # Chromium install.
    attr_accessor :browser_options

    attr_accessor :default_layout, :default_options, :tmp_dir

    def initialize
      @browser_options  = {}
      @default_layout   = 'application'
      @default_options  = { print_background: true }
      @tmp_dir          = nil
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
