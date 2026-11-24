require "htmlToPdf/renderer"
require "htmlToPdf/storage"
require "htmlToPdf/job_status"
require "htmlToPdf/browser_pool"

module HtmlToPdf
  # The batteries-included background job behind HtmlToPdf.generate_later.
  # Built entirely on ActiveJob's own public API (retry_on/discard_on/
  # queue_as) — no Sidekiq- or Solid-Queue-specific code anywhere — so it
  # runs under whichever queue adapter the host app configures
  # (config.active_job.queue_adapter).
  #
  # Anyone who wants different retry/discard/queue semantics than the ones
  # below should define their own ActiveJob class built on the same
  # HtmlToPdf::Renderer / HtmlToPdf::Storage primitives this job itself
  # calls, rather than trying to reconfigure this one — see
  # docs/background-jobs.md for why retry attempts specifically aren't a
  # HtmlToPdf.configure knob (retry_on is evaluated once, at class-definition
  # time, before a host app's initializer has had a chance to run).
  class GenerateJob < ActiveJob::Base
    queue_as { HtmlToPdf.configuration.job_queue_name }

    retry_on(*HtmlToPdf::BrowserPool::RECOVERABLE_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
      status = HtmlToPdf::JobStatus.new(job.job_id).failed!(error)
      HtmlToPdf.configuration.on_job_failure&.call(status, error)
    end

    discard_on ArgumentError do |job, error|
      status = HtmlToPdf::JobStatus.new(job.job_id).failed!(error)
      HtmlToPdf.configuration.on_job_failure&.call(status, error)
    end

    def perform(controller:, action:, assigns: {}, pdf_options: {}, store: nil, metadata: {})
      status = HtmlToPdf::JobStatus.new(job_id, metadata: metadata)
      status.processing!

      pdf_bytes = HtmlToPdf::Renderer.render(controller: controller, action: action, assigns: assigns, pdf_options: pdf_options)
      result = store ? HtmlToPdf::Storage.store(pdf_bytes, **store) : nil

      status.completed!(result: result)
      HtmlToPdf.configuration.on_job_success&.call(status)
    end
  end
end
