module HtmlToPdf
  # Normalizes the Hash passed as pdf_options[:print_options] (plus the
  # default_options configured globally and the :padding shorthand) into the
  # keyword arguments Ferrum::Page#pdf / Chrome's Page.printToPDF expect.
  #
  # Chrome's print options are a fixed, narrow set of layout flags (margins,
  # paper size, scale, headers/footers) rather than arbitrary CLI arguments,
  # so this can't be used to inject arbitrary binary flags even when
  # pdf_options comes from params.
  module PrintOptions
    SIZE_KEYS = %i[paper_width paper_height margin_top margin_bottom margin_left margin_right].freeze

    # Matches Chrome's own predefined paper sizes (inches).
    PAPER_SIZES = {
      'letter'  => [8.50, 11.00],
      'legal'   => [8.50, 14.00],
      'tabloid' => [11.00, 17.00],
      'ledger'  => [17.00, 11.00],
      'a0'      => [33.10, 46.80],
      'a1'      => [23.40, 33.10],
      'a2'      => [16.54, 23.40],
      'a3'      => [11.70, 16.54],
      'a4'      => [8.27, 11.70],
      'a5'      => [5.83, 8.27],
      'a6'      => [4.13, 5.83]
    }.freeze

    UNIT_TO_INCHES = { 'in' => 1.0, 'cm' => 1 / 2.54, 'mm' => 1 / 25.4, 'px' => 1 / 96.0 }.freeze

    module_function

    # Returns [cdp_options, javascript_delay_in_ms]. javascript_delay isn't a
    # Chrome print flag (Page.printToPDF has no such parameter and rejects
    # unknown ones) — it's our own convenience, applied as a pause between
    # page load and capture, for pages that render content asynchronously.
    #
    # Precedence, highest first: pdf_options[:print_options], then
    # pdf_options[:padding], then config.default_options. default_options and
    # print_options are each resolved (legacy aliases/format) independently
    # before merging, so e.g. a gem-wide default :format can't clobber an
    # explicit per-request :paper_width/:paper_height, and a gem-wide default
    # margin doesn't block a per-request :padding from overriding it.
    def build(pdf_options)
      defaults = resolve_source(HtmlToPdf.configuration.default_options)
      request_options = resolve_source(pdf_options[:print_options] || {})
      apply_padding!(request_options, pdf_options[:padding])

      options = defaults.merge(request_options)
      convert_sizes!(options)
      javascript_delay = options.delete(:javascript_delay)
      [options, javascript_delay]
    end

    def resolve_source(hash)
      options = underscore_keys(hash)
      apply_format!(options)
      options
    end

    def underscore_keys(hash)
      hash.each_with_object({}) { |(key, value), acc| acc[key.to_s.tr('-', '_').to_sym] = value }
    end

    def apply_padding!(options, padding)
      return if padding.blank?

      %i[margin_top margin_bottom margin_left margin_right].each do |key|
        options[key] = padding unless options.key?(key)
      end
    end

    def apply_format!(options)
      format = options.delete(:format)
      return unless format

      dimensions = PAPER_SIZES[format.to_s.downcase]
      raise ArgumentError, "Unknown paper format: #{format.inspect}" unless dimensions

      options[:paper_width], options[:paper_height] = dimensions
    end

    def convert_sizes!(options)
      SIZE_KEYS.each do |key|
        next unless options.key?(key)

        options[key] = to_inches(options[key])
      end
    end

    def to_inches(value)
      return value.to_f if value.is_a?(Numeric)

      match = value.to_s.strip.match(/\A(-?[\d.]+)\s*(in|cm|mm|px)?\z/i)
      raise ArgumentError, "Unrecognized size value: #{value.inspect}" unless match

      number, unit = match.captures
      number.to_f * UNIT_TO_INCHES.fetch(unit&.downcase || 'in')
    end
  end
end
