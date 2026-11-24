# Background PDF generation

[← Back to README](../README.md)

`HtmlToPdf.generate_later` is the async counterpart to the synchronous `include HtmlToPdf` /
`around_action :html_to_pdf` path: instead of streaming the PDF back in the response, it enqueues
an ActiveJob job that renders the view, converts it, optionally stores it (S3/ActiveStorage), and
tracks its own status so a different process (e.g. your web process, checking on a Sidekiq/Solid
Queue worker) can poll it.

## Quick start

```ruby
job = HtmlToPdf.generate_later(
  controller: InvoicesController,
  action: :show,
  assigns: { invoice: invoice },                 # ivars the view needs
  pdf_options: { title: "invoice", print_options: { format: "A4" } },
  store: { adapter: :active_storage, record: invoice, attachment: :pdf },
  metadata: { invoice_id: invoice.id }
)

job.job_id # => a String you can hang onto (e.g. render it to the client to poll with)

HtmlToPdf::JobStatus.find(job.job_id)
# => #<HtmlToPdf::JobStatus state: "completed", result: {...}, metadata: {invoice_id: 1}, ...>
```

Required one-time setup, in an initializer:

```ruby
HtmlToPdf.configure do |config|
  # There's no real request in a background job for HtmlToPdf::Renderer to
  # infer a host from — this is required, and HtmlToPdf.generate_later
  # raises a clear ArgumentError if it's missing. Note these are
  # ActionController::Renderer's env keys (http_host/https), not
  # config.action_mailer.default_url_options's (host/protocol).
  config.default_url_options = { http_host: "app.example.com", https: true }
end
```

## How it renders without a request

`HtmlToPdf::Renderer` uses [`ActionController::Renderer`](https://api.rubyonrails.org/classes/ActionController/Renderer.html)
— the same mechanism ActionMailer itself uses to render views outside of a request — rather than
a real controller instance's `render_to_string`. The actual HTML-to-PDF conversion
(`HtmlToPdf::Converter`) is the exact same code the synchronous path uses: write to a temp file,
point headless Chrome at it via `file://`, convert, clean up. `print_options`/`header_template`
filtering goes through the same `HtmlToPdf::PrintOptions` as the synchronous path too — see
[Security](security.md) for what that means for a job's `pdf_options`.

**The `asset_host` gotcha is worse here than in a real request** (see
[Rails integration](rails-integration.md#the-asset_host-gotcha)): there's no `request` object at
all for a `Proc`-based `config.action_controller.asset_host` to close over. If your views load any
asset (CSS, images), `asset_host` needs to be a plain string/host, not the request-derived `Proc`
form, when rendering from a job.

`assigns:` — not `params:` — is the actual mechanism for feeding a view data here (`params:` isn't
a thing `ActionController::Renderer#render` accepts; it just forwards straight to
`render_to_string`). ActiveRecord objects pass through `assigns:` fine, since ActiveJob serializes
them via GlobalID.

## Sidekiq / Solid Queue "compatibility"

`HtmlToPdf::GenerateJob` is a plain `ActiveJob::Base` subclass using only `retry_on`/`discard_on`/
`queue_as` — ActiveJob's own public API, nothing Sidekiq- or Solid-Queue-specific anywhere. It runs
under whichever adapter your app configures via `config.active_job.queue_adapter`. "Compatible with
Sidekiq and Solid Queue" is true by construction here, not something this gem's own CI spins up
both backends to verify (its specs run against ActiveJob's built-in `:test` adapter).

### Setting up Solid Queue

Rails 8's default. `config/environments/production.rb` (or any environment you want it in):

```ruby
config.active_job.queue_adapter = :solid_queue
```

Run a worker as its own process alongside your web server:

```
bin/jobs
```

**The web process and the worker process are separate Ruby processes with separate memory** — see
"Job status tracking" below for why that means `config.cache_store` needs to be something other
than `:memory_store` for `HtmlToPdf::JobStatus` to actually be readable from the web side.

### Setting up Sidekiq

Add it to your Gemfile (this gem does not depend on it — same "bring your own adapter" stance as
`aws-sdk-s3`):

```ruby
gem "sidekiq"
```

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server { |c| c.redis = { url: ENV.fetch("REDIS_URL") } }
Sidekiq.configure_client { |c| c.redis = { url: ENV.fetch("REDIS_URL") } }
```

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :sidekiq
```

Run a worker:

```
bundle exec sidekiq
```

Same caveat as Solid Queue: the worker is a separate process from your web server, so
`config.cache_store` needs to be Redis (or another shared store) — not `:memory_store` — for job
status to be visible from the web side. If you're already running Redis for Sidekiq, pointing
`config.cache_store` at the same Redis instance (`:redis_cache_store`) is the path of least
resistance.

### Any other ActiveJob adapter

The same applies to anything else ActiveJob supports (`good_job`, `que`, `delayed_job`, ...) —
there's nothing in this gem to configure beyond `config.active_job.queue_adapter` itself and,
again, a cache store that isn't tied to one process.

## Retries and failures

`GenerateJob` retries the same errors `BrowserPool` itself retries once internally (a crashed/
unresponsive Chrome — `Ferrum::DeadBrowserError`, `ProcessTimeoutError`, `TimeoutError`,
`NoSuchPageError`), up to 3 job-level attempts, with `wait: :polynomially_longer`. A bad
`print_options` value (`ArgumentError`) is discarded immediately instead — retrying a validation
error can't fix it.

**Retry `attempts`/`wait` are fixed, not a `HtmlToPdf.configure` option — on purpose.** `retry_on`
is a class-level macro evaluated once when this gem is `require`d, which happens at
`Bundler.require` time — *before* your own `config/initializers/html_to_pdf.rb` has run. A config
value read at that point would always see this gem's default, never your override, which would be
a confusing, silent footgun. If you want different retry/discard/queue semantics, define your own
tiny `ActiveJob::Base` subclass on the same primitives `GenerateJob` itself is built from:

```ruby
class MyPdfJob < ActiveJob::Base
  retry_on Ferrum::DeadBrowserError, wait: 10.seconds, attempts: 10

  def perform(...)
    pdf_bytes = HtmlToPdf::Renderer.render(...)
    HtmlToPdf::Storage.store(pdf_bytes, adapter: :s3, key: ...)
  end
end
```

(`config.job_queue_name` *is* a safe runtime option — `queue_as { HtmlToPdf.configuration.job_queue_name }`
uses ActiveJob's block form, which is evaluated per-enqueue, not at class-definition time.)

`config.on_job_success` / `config.on_job_failure` are optional Procs called with the
`HtmlToPdf::JobStatus` (and the exception, for `on_job_failure`) once a job finishes — for good, in
the failure case, i.e. after retries are exhausted or the job was discarded.

## Job status tracking

`HtmlToPdf::JobStatus` persists each job's `queued` → `processing` → `completed`/`failed`
transitions to `config.job_status_store`, which defaults to `HtmlToPdf::JobStatus::CacheStore` — a
thin wrapper over `Rails.cache`, namespaced under `htmlToPdf:job_status:<job_id>`, with
`config.job_status_ttl` (default 24 hours) as the expiry.

**This needs a shared cache store in production to actually be visible across processes.**
`Rails.cache`'s `:memory_store`/`:file_store` are per-process — a web process will never see a
status a *different* Sidekiq/Solid Queue worker process wrote with either of those. Configure
Redis, Solid Cache, or Memcached for `config.cache_store` if you're polling job status from a
different process than the one running the job (the normal case).

Swap the store entirely with any object responding to `#read(job_id)` / `#write(job_id, attrs)`:

```ruby
config.job_status_store = MyActiveRecordBackedStore.new
```

## Storage adapters

`HtmlToPdf::Storage.store(pdf_bytes, adapter:, **options)` dispatches to a registered adapter.
Two ship with the gem:

- **`:active_storage`** (`HtmlToPdf::Storage::ActiveStorageAdapter`) — attaches the PDF to an
  ActiveRecord record via `has_one_attached`/`has_many_attached`, using whatever service
  `config/storage.yml` already points your app at (disk, S3, GCS, ...).
  `{ adapter: :active_storage, record:, attachment:, filename: "document.pdf" }`.
- **`:s3`** (`HtmlToPdf::Storage::S3Adapter`) — direct upload via `aws-sdk-s3`, for apps that don't
  use ActiveStorage and just want a plain bucket/key/URL back, no blob/attachment bookkeeping.
  `{ adapter: :s3, key:, bucket: (or config.s3_bucket) }`. **htmlToPdf does not depend on
  `aws-sdk-s3`** — add it to your own Gemfile to use this adapter. Prefer leaving credentials out
  of `config.s3_client_options` and letting the AWS SDK's default credential chain (an EC2/ECS
  instance role) resolve them; only pass explicit credentials if an instance role genuinely isn't
  an option (e.g. a cross-account bucket).

Register your own with `HtmlToPdf::Storage.register(:my_adapter, MyAdapterClass)` — any class
whose `#initialize` takes the call's `**options` and whose `#store(pdf_bytes)` returns a plain,
cache-serializable Hash (that return value becomes `JobStatus#result`).

## Troubleshooting

- **A job sits in `"queued"` forever.** No worker process is running against that queue, or
  `config.job_queue_name` doesn't match what the worker is listening to (Solid Queue's
  `config/queue.yml` `queues: "*"` listens to everything by default; Sidekiq needs the queue name
  in its own `-q`/`:queues` config). Confirm a worker process (`bin/jobs`, `bundle exec sidekiq`,
  ...) is actually running, separately from the web server.
- **`HtmlToPdf::JobStatus.find` returns a status with a `nil` state even though the job clearly
  ran** (you can see it in the worker's log). `config.cache_store` is `:memory_store` or
  `:file_store` in the process you're reading from, and the write happened in a *different*
  process — see "Job status tracking" above. This is the single most common setup mistake.
- **`HtmlToPdf::Storage::ActiveStorageAdapter` raises `LoadError: ActiveStorage isn't loaded`.**
  The app was generated with `--skip-active-storage` (or `Rails.application.config.active_storage`
  was never configured). Either undo that, or use `:s3` instead.
- **`HtmlToPdf::Storage::S3Adapter` raises `ArgumentError: ... needs a bucket`.** Pass `bucket:` on
  the call, or set `config.s3_bucket` — one of the two is required, there's no implicit default.
- **A job fails immediately with `ActiveJob::DeserializationError` mentioning a controller or
  record.** Something passed to `assigns:`/`store:` (via GlobalID) was deleted before the job ran.
  This is the same failure mode any ActiveJob job has when it's handed a record that disappears
  before it executes — not specific to this gem.

## Concurrency

`config.max_concurrent_renders` (default `nil`, unbounded — today's exact behavior) caps how many
conversions may run against the shared `BrowserPool` browser at once, via
`HtmlToPdf::ConcurrencyLimiter`. Applies to the synchronous controller path too, not just jobs,
since both funnel through the same one Chrome process per Ruby process — see
[Architecture](architecture.md#browserpool)'s scaling note. A web app under normal load rarely
needs this; a Sidekiq/Solid Queue pool with many worker threads all calling
`HtmlToPdf.generate_later` at once is the case it exists for.
