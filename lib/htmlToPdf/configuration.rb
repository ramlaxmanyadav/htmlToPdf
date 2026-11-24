require "htmlToPdf/job_status"

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

    # Caps how many conversions (HtmlToPdf::BrowserPool#with_page calls) may
    # run against the shared browser at once, via a Concurrent::Semaphore —
    # see HtmlToPdf::ConcurrencyLimiter. nil (default) means unbounded, i.e.
    # today's exact behavior. Applies to both the synchronous controller path
    # and background jobs, since both funnel through the same one Chrome
    # process per Ruby process (see docs/architecture.md's scaling note).
    attr_accessor :max_concurrent_renders

    # Where HtmlToPdf::JobStatus persists a background job's state so it's
    # readable from a different process than the one running the job (e.g.
    # your web process checking on a Sidekiq worker). Defaults to a
    # Rails.cache-backed store (HtmlToPdf::JobStatus::CacheStore) — swap in
    # your own by assigning any object responding to #read(job_id)/
    # #write(job_id, attrs). See docs/background-jobs.md for the
    # cross-process-visibility caveat with memory_store/file_store.
    attr_accessor :job_status_store

    # How long a HtmlToPdf::JobStatus entry is kept in job_status_store
    # before it's eligible for eviction. Defaults to 24 hours.
    attr_accessor :job_status_ttl

    # The ActiveJob queue HtmlToPdf::GenerateJob enqueues onto. Defaults to
    # :default. Read dynamically per-enqueue (via queue_as's block form), so
    # this is safe to change at runtime, unlike job_retry settings — see
    # docs/background-jobs.md.
    attr_accessor :job_queue_name

    # Optional Procs invoked after a background job completes/fails for
    # good, i.e. after retries are exhausted for on_job_failure. Each is
    # called with the HtmlToPdf::JobStatus record (on_job_failure also gets
    # the exception as a second argument). Never invoked for the synchronous
    # controller path.
    attr_accessor :on_job_success, :on_job_failure

    # Hash of options (e.g. { host: "app.example.com", protocol: "https" })
    # used to build the ActionController::Renderer HtmlToPdf::Renderer calls
    # from a background job, where (unlike a real request) there's no
    # request to infer a host from at all. Required to use
    # HtmlToPdf.generate_later / HtmlToPdf::Renderer — see
    # docs/background-jobs.md.
    attr_accessor :default_url_options

    # Defaults consumed by HtmlToPdf::Storage::S3Adapter so callers don't
    # have to repeat them on every call. s3_client_options is passed straight
    # to Aws::S3::Client.new (e.g. { region: "us-east-1" }) — leave
    # credentials out of it and let the AWS SDK's default credential chain
    # (an instance/task IAM role) resolve them; only set explicit credentials
    # there if an instance role genuinely isn't an option.
    attr_accessor :s3_bucket, :s3_client_options

    def initialize
      @browser_options          = {}
      @default_layout           = 'application'
      @default_options          = { print_background: true }
      @tmp_dir                  = nil
      @allow_request_templates  = false
      @max_javascript_delay_ms  = 10_000
      @max_concurrent_renders   = nil
      @job_status_store         = HtmlToPdf::JobStatus::CacheStore.new
      @job_status_ttl           = 24 * 60 * 60
      @job_queue_name           = :default
      @on_job_success           = nil
      @on_job_failure           = nil
      @default_url_options      = nil
      @s3_bucket                = nil
      @s3_client_options        = {}
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
