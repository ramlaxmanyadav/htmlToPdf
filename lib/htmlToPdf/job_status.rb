require "htmlToPdf/job_status/cache_store"

module HtmlToPdf
  # Tracks one HtmlToPdf::GenerateJob's lifecycle (queued -> processing ->
  # completed/failed) in config.job_status_store, so it's readable from a
  # different process than the one running the job — e.g. a web request
  # polling on a PDF a Sidekiq/Solid Queue worker is generating.
  #
  # Not used by the synchronous controller path at all; that path has
  # nothing to poll for, since it returns the PDF directly in the response.
  class JobStatus
    attr_reader :job_id, :state, :result, :error, :metadata, :queued_at, :started_at, :finished_at

    def self.find(job_id)
      new(job_id).tap(&:reload)
    end

    def initialize(job_id, metadata: {})
      @job_id = job_id
      @metadata = metadata
    end

    def reload
      stored = HtmlToPdf.configuration.job_status_store.read(job_id)
      assign(stored) if stored
      self
    end

    %i[queued processing completed failed].each do |s|
      define_method("#{s}?") { state == s.to_s }
    end

    def queued!
      persist!(state: "queued", queued_at: Time.now.utc)
    end

    def processing!
      persist!(state: "processing", started_at: Time.now.utc)
    end

    def completed!(result:)
      persist!(state: "completed", result: result, finished_at: Time.now.utc)
    end

    def failed!(exception)
      persist!(
        state: "failed",
        error: { class: exception.class.name, message: exception.message },
        finished_at: Time.now.utc
      )
    end

    private

    def persist!(changes)
      assign(changes)
      HtmlToPdf.configuration.job_status_store.write(job_id, to_h)
      self
    end

    def assign(attrs)
      @state       = attrs[:state]       if attrs.key?(:state)
      @result      = attrs[:result]      if attrs.key?(:result)
      @error       = attrs[:error]       if attrs.key?(:error)
      @metadata    = attrs[:metadata]     if attrs.key?(:metadata)
      @queued_at   = attrs[:queued_at]    if attrs.key?(:queued_at)
      @started_at  = attrs[:started_at]  if attrs.key?(:started_at)
      @finished_at = attrs[:finished_at] if attrs.key?(:finished_at)
    end

    def to_h
      {
        state: state, result: result, error: error, metadata: metadata,
        queued_at: queued_at, started_at: started_at, finished_at: finished_at
      }
    end
  end
end
