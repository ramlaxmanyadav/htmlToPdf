module HtmlToPdf
  class Configuration
    attr_accessor :wkhtmltopdf_path, :default_layout, :default_options, :tmp_dir

    def initialize
      @wkhtmltopdf_path = 'wkhtmltopdf'
      @default_layout   = 'application'
      @default_options  = {}
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
