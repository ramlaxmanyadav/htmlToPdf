require "securerandom"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "htmlToPdf/version"
require "htmlToPdf/configuration"
require "htmlToPdf/browser_pool"
require "htmlToPdf/print_options"
require "htmlToPdf/converter"
require "htmlToPdf/renderer"
require "htmlToPdf/storage"
require "htmlToPdf/job_status"

# Defined eagerly (not lazily inside HtmlToPdf.generate_later) specifically
# so a separate worker process (a Sidekiq/Solid Queue process that never
# itself calls generate_later, only performs jobs the web process enqueued)
# has the class available too — ActiveJob resolves a job by class *name* at
# perform time, in whatever process that happens to be, and that process's
# own boot never otherwise touches this gem's generate_later method. Guarded
# on ActiveJob::Base being defined already (true for any ordinary Rails app
# by the time Bundler.require reaches this gem) so an app generated with
# --skip-active-job still boots — HtmlToPdf.generate_later itself raises a
# clear error in that case instead.
require "htmlToPdf/generate_job" if defined?(ActiveJob::Base)

module HtmlToPdf
  extend ActiveSupport::Concern

  class << self
    # Enqueues HtmlToPdf::GenerateJob — the background-rendering counterpart
    # to the synchronous `include HtmlToPdf` / around_action path, for PDFs
    # slow enough that a caller shouldn't hold a connection open for them, or
    # that should end up in storage (S3/ActiveStorage) rather than streamed
    # back directly. See docs/background-jobs.md.
    #
    # controller: a controller Class (or its String name). action: Symbol/
    # String. assigns: ivars the view needs (AR objects pass through fine —
    # ActiveJob serializes them via GlobalID). pdf_options: same shape as the
    # synchronous path's pdf_options. store: optional, e.g.
    # { adapter: :active_storage, record:, attachment: } or
    # { adapter: :s3, key: } — see HtmlToPdf::Storage. metadata: optional,
    # arbitrary serializable data surfaced on the JobStatus record and handed
    # to config.on_job_success/on_job_failure.
    #
    # Returns the enqueued HtmlToPdf::GenerateJob (ActiveJob::Base#job_id,
    # etc.). Immediately writes a "queued" HtmlToPdf::JobStatus for that
    # job_id, readable via HtmlToPdf::JobStatus.find.
    def generate_later(controller:, action:, assigns: {}, pdf_options: {}, store: nil, metadata: {})
      unless defined?(ActiveJob::Base)
        raise LoadError,
              "ActiveJob isn't loaded — HtmlToPdf.generate_later needs it. If this app was " \
              "generated with --skip-active-job, either undo that or call " \
              "HtmlToPdf::Renderer.render + HtmlToPdf::Storage.store directly instead (the " \
              "synchronous building blocks generate_later is built from)."
      end

      require "htmlToPdf/generate_job"

      # Built via .new + #enqueue (what .perform_later does internally)
      # rather than .perform_later directly, so the "queued" status below is
      # written *before* the job can possibly run — some queue adapters
      # (:inline, or the :test adapter under perform_enqueued_jobs) execute
      # the job synchronously as part of enqueuing it, and writing "queued"
      # afterwards would then clobber a "completed"/"failed" status that
      # already landed.
      job = GenerateJob.new(
        controller: controller, action: action, assigns: assigns,
        pdf_options: pdf_options, store: store, metadata: metadata
      )
      JobStatus.new(job.job_id, metadata: metadata).queued!
      job.enqueue
      job
    end
  end

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
    pdf_bytes = HtmlToPdf::Converter.convert(html, print_options: @print_options, javascript_delay: @javascript_delay)

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
    HtmlToPdf::Converter.render_pdf(source_file, print_options: @print_options, javascript_delay: @javascript_delay)
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
