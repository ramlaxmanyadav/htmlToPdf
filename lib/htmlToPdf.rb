require "securerandom"
require "htmlToPdf/version"
require "htmlToPdf/configuration"

module HtmlToPdf

  def html_to_pdf()
    pdf_options = params[:pdf_options] ? params[:pdf_options] : {}
    if request.format == 'application/pdf'
      initialize_downloads(pdf_options)
      _tmp_dir = HtmlToPdf.configuration.tmp_dir || File.join(Rails.root, 'tmp')
      FileUtils.mkdir_p(_tmp_dir)
      _unique_id = "#{Time.now.to_i}_#{SecureRandom.hex(8)}"
      _source_file = File.join(_tmp_dir, "#{_unique_id}.html")
      _destination_file = File.join(_tmp_dir, "#{_unique_id}.pdf")
      _controller = ("#{controller_name}Controller").camelize.constantize.new
      _controller.request = request
      _controller.response = response
      _controller.params = params
      _controller.method(action_name).call

      _controller.instance_variables.each do |var|
        instance_variable_set(var, _controller.instance_variable_get(var))
      end

      _html = render_to_string(template: "#{controller_name}/#{action_name}", :layout => @layout, locals: { url: Rails.application.routes.url_helpers })
      file_content = _html.gsub(/\\&quot;/, "")


      File.open(_source_file, "w+") do |f|
        f.write(file_content)
      end
      system(HtmlToPdf.configuration.wkhtmltopdf_path, *wkhtmltopdf_args, _source_file, _destination_file)
      File.delete(_source_file) if File.exist?(_source_file)
      send_data File.open(_destination_file, "rb") { |f| f.read }, :disposition => 'attachment', :filename => "#{sanitized_pdf_name}.pdf"
      File.delete(_destination_file)
    end
  end

  def initialize_downloads(pdf_options = {})
    pdf_options ||= {}
    @name = pdf_options[:title].nil? ? "#{Time.now.to_i.to_s}" : pdf_options[:title]
    @layout = pdf_options[:layout].nil? ? HtmlToPdf.configuration.default_layout : pdf_options[:layout]
    @wkhtmltopdf_options = build_wkhtmltopdf_options(pdf_options)
  end

  def sanitized_pdf_name
    @name.to_s.gsub(/[^a-zA-Z0-9_\- ]/, '').strip.presence || Time.now.to_i.to_s
  end

  # Merges, in increasing precedence: HtmlToPdf.configuration.default_options,
  # pdf_options[:padding] (shorthand applied to all four margins), then
  # pdf_options[:wkhtmltopdf_options] (any wkhtmltopdf flag, e.g. orientation:
  # 'Landscape', page_size: 'A4', grayscale: true). Keys are dasherized so
  # either underscore or dash form works.
  def build_wkhtmltopdf_options(pdf_options)
    options = dasherize_keys(HtmlToPdf.configuration.default_options)

    if pdf_options[:padding].present?
      padding = pdf_options[:padding].to_s
      %w[margin-top margin-bottom margin-left margin-right].each { |flag| options[flag] = padding }
    end

    options.merge!(dasherize_keys(pdf_options[:wkhtmltopdf_options] || {}))
    options
  end

  def dasherize_keys(hash)
    hash.each_with_object({}) { |(key, value), acc| acc[key.to_s.tr('_', '-')] = value }
  end

  # Query-string values arrive as strings (e.g. grayscale: true serializes to
  # "true" in a link_to href and comes back as that literal string), so plain
  # booleans aren't enough to detect a falsy/truthy flag.
  FALSEY_VALUES = [nil, false, '', '0', 'false', 'off'].freeze
  TRUTHY_FLAG_VALUES = [true, 'true'].freeze

  def wkhtmltopdf_args
    (@wkhtmltopdf_options || {}).each_with_object([]) do |(flag, value), args|
      normalized = value.is_a?(String) ? value.downcase : value
      next if FALSEY_VALUES.include?(normalized)

      args << "--#{flag}"
      args << value.to_s unless TRUTHY_FLAG_VALUES.include?(normalized)
    end
  end

end

ActionController::Base.send(:include, HtmlToPdf)
