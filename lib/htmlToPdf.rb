require "securerandom"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "htmlToPdf/version"
require "htmlToPdf/configuration"
require "htmlToPdf/browser_pool"
require "htmlToPdf/print_options"

module HtmlToPdf
  extend ActiveSupport::Concern

  # Wire up with `include HtmlToPdf` then `around_action :html_to_pdf` (not
  # `before_action`) in the controller(s) that should support it — typically
  # ApplicationController. An around_action is required: it lets the rest of
  # the callback chain and the action itself run normally via `yield` (so
  # other before_actions' instance variables are available), rather than
  # re-invoking the action out-of-band the way earlier versions of this gem
  # did.
  def html_to_pdf
    unless pdf_request?
      yield
      return
    end

    pdf_options = params[:pdf_options] ? params[:pdf_options] : {}
    initialize_downloads(pdf_options)

    # Run the real callback chain/action with the format forced to :html, so
    # Rails' own implicit rendering resolves the normal HTML template instead
    # of raising UnknownFormat for a nonexistent .pdf template. That render's
    # output is discarded — render_to_string below (not response.body) is
    # what actually gets converted — this only needs to happen so the action
    # itself runs in its ordinary place in the chain.
    original_format = request.format
    request.format = :html
    begin
      yield
    ensure
      request.format = original_format
    end

    html = render_to_string(template: "#{controller_name}/#{action_name}", layout: @layout, locals: { url: Rails.application.routes.url_helpers })
    file_content = html.gsub(/\\&quot;/, "")

    tmp_dir = HtmlToPdf.configuration.tmp_dir || File.join(Rails.root, 'tmp')
    FileUtils.mkdir_p(tmp_dir)
    source_file = File.join(tmp_dir, "#{Time.now.to_i}_#{SecureRandom.hex(8)}.html")
    File.write(source_file, file_content)

    begin
      pdf_bytes = render_pdf(source_file)
    ensure
      File.delete(source_file) if File.exist?(source_file)
    end

    deliver_pdf(pdf_bytes)
  end

  def initialize_downloads(pdf_options = {})
    pdf_options ||= {}
    @name = pdf_options[:title].nil? ? "#{Time.now.to_i.to_s}" : pdf_options[:title]
    @layout = pdf_options[:layout].nil? ? HtmlToPdf.configuration.default_layout : pdf_options[:layout]
    @print_options, @javascript_delay = HtmlToPdf::PrintOptions.build(pdf_options)
  end

  def sanitized_pdf_name
    @name.to_s.gsub(/[^a-zA-Z0-9_\- ]/, '').strip.presence || Time.now.to_i.to_s
  end

  # Renders the given HTML file to PDF bytes via a pooled headless Chrome
  # instance. Navigating to a file:// URL (rather than feeding Chrome the
  # markup directly) gives relative asset paths a real base URI to resolve
  # against, matching how a browser would load the page.
  def render_pdf(source_file)
    HtmlToPdf::BrowserPool.with_page do |page|
      page.go_to("file://#{source_file}")
      sleep(@javascript_delay / 1000.0) if @javascript_delay.to_i.positive?
      page.pdf(encoding: :binary, **(@print_options || {}))
    end
  end

  private

  def pdf_request?
    request.format == 'application/pdf'
  end

  # Equivalent to send_data, but assigns response_body directly instead of
  # going through #render. #render refuses a second render in the same
  # action (AbstractController::DoubleRenderError) — and by this point one
  # already happened, deliberately, via the forced-:html yield above.
  def deliver_pdf(pdf_bytes)
    send_file_headers!(disposition: 'attachment', filename: "#{sanitized_pdf_name}.pdf")
    self.status = 200
    self.response_body = pdf_bytes
  end
end
