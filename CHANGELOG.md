# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [4.0.0] - 2026-11-24

The headline change: PDFs no longer have to be generated inline, in the request that asked for
them. `HtmlToPdf.generate_later` renders in the background via ActiveJob, tracks the job's status,
and can hand the finished PDF off to S3 or ActiveStorage instead of streaming it back — a big
enough expansion of what this gem does that it gets a major version bump, even though every
existing synchronous `include HtmlToPdf` / `around_action :html_to_pdf` integration keeps working
completely unchanged. **Nothing from 3.x needs to change to upgrade** — see "Upgrading from 3.x"
below.

### Added: background rendering (`HtmlToPdf.generate_later`)

```ruby
job = HtmlToPdf.generate_later(
  controller: InvoicesController,
  action: :show,
  assigns: { invoice: invoice },
  pdf_options: { title: "invoice", print_options: { format: "A4" } },
  store: { adapter: :active_storage, record: invoice, attachment: :pdf },
  metadata: { invoice_id: invoice.id }
)

HtmlToPdf::JobStatus.find(job.job_id) # => state/result/error/metadata
```

- **`HtmlToPdf::GenerateJob`**, a plain `ActiveJob::Base` subclass built entirely on ActiveJob's own
  public API (`retry_on`/`discard_on`/`queue_as`) — no Sidekiq- or Solid-Queue-specific code
  anywhere, so it runs under whichever queue adapter the host app configures. Automatic retries on
  the same transient Chrome errors `BrowserPool` already retries once internally; failed/discarded
  jobs invoke the new `config.on_job_failure` callback. Required eagerly (guarded on
  `ActiveJob::Base` already being defined) rather than lazily on first `generate_later` call —
  found by actually running a background job against a real, separate Solid Queue worker process:
  a worker that never itself calls `generate_later` still needs the job class defined in *its own*
  process to perform a job the web process enqueued, and a lazy `require` inside `generate_later`
  never runs there at all.
- **`HtmlToPdf::Renderer`**, the piece `generate_later` is built on — renders a controller action to
  PDF bytes outside of a request, via `ActionController::Renderer` (the same mechanism ActionMailer
  uses). Requires the new `config.default_url_options`, since there's no real request for it to
  infer a host from — raises a clear `ArgumentError` if that's unset rather than silently rendering
  broken asset/route URLs.
- **`HtmlToPdf::JobStatus`**, tracking a background job's `queued` → `processing` →
  `completed`/`failed` lifecycle in `config.job_status_store` (default: a `Rails.cache`-backed
  `CacheStore`, swappable for a custom store), so a different process than the one running the job
  — e.g. the web process a user is polling from — can read it.
- **`HtmlToPdf::Storage`**, pluggable PDF storage with two adapters shipped:
  - `:active_storage` — attaches to any ActiveRecord `has_one_attached`/`has_many_attached`, via
    whatever service `config/storage.yml` already points at (disk, S3, GCS, ...).
  - `:s3` — direct upload via `aws-sdk-s3`, for apps that don't use ActiveStorage and just want a
    plain bucket/key/URL back. **A true optional dependency — this gem does not depend on
    `aws-sdk-s3`**; add it to your own Gemfile to use `:s3`.
  - Register your own with `HtmlToPdf::Storage.register(:name, AdapterClass)`.
- **`config.max_concurrent_renders`** (default `nil`, unbounded — unchanged behavior) — caps how
  many conversions may run against the shared `BrowserPool` browser at once, via the new
  `HtmlToPdf::ConcurrencyLimiter`. Applies to the synchronous controller path too, not just jobs,
  since both funnel through the same one Chrome process per Ruby process.
- New config: `config.job_status_store`, `config.job_status_ttl`, `config.job_queue_name`,
  `config.on_job_success`, `config.on_job_failure`, `config.default_url_options`,
  `config.s3_bucket`, `config.s3_client_options`.

### Changed (internal, non-breaking)

- Extracted the "write HTML to a temp file, convert via `BrowserPool`, clean up" logic (previously
  inlined in `html_to_pdf`) into `HtmlToPdf::Converter`, shared by both the synchronous controller
  path and `HtmlToPdf::Renderer` — no behavior change to the synchronous path, just one copy of the
  logic instead of two.

### Upgrading from 3.x

Nothing to do. Every new piece is additive, defaults to today's exact behavior (unbounded
concurrency, no background store, etc.), and the synchronous path's code, options, and security
model (see [Security](docs/security.md)) are untouched. Adopt `HtmlToPdf.generate_later` wherever
and whenever it's useful — the two paths compose freely in the same app.

See [Background PDF generation](docs/background-jobs.md) for the full write-up, including why
retry `attempts`/`wait` are fixed rather than a `HtmlToPdf.configure` option (a class-definition-
time-vs-initializer-load-order hazard, explained there), the cross-process cache-visibility caveat
for job status in production, and a detailed look at each storage adapter.

## [3.0.1] - 2026-11-24

- **Security: patched a batch of transitive dependency CVEs** flagged by GitHub's dependency
  graph, none of which are in code this gem's own runtime path touches directly — all pulled in
  through the `rails`/`rspec-rails`/`combustion` dev-dependency chain used to build and test the
  gem itself. Still bumped because a published gem's `Gemfile.lock` is what `bundle lock
  --add-platform`/CI resolve against, and a stale lock keeps flagging downstream apps that `bundle
  install --deployment` against it. Notably `activestorage` 8.1.4 → 8.1.4.1 (CVE-2026-122006,
  critical) and `actionpack` 8.1.4 → 8.1.4.1 (CVE-2026-126083/126081, high); also `rack` ~> 3.2.9,
  `nokogiri` ~> 1.19.7, `loofah` ~> 2.25.3, `rails-html-sanitizer` ~> 1.7.2, `addressable` ~> 2.10,
  and the rest of Rails 8.1 (`actionview`, `actionmailbox`, `activesupport`) to 8.1.4.1.
- **Security: patched `crass` 1.0.7 → 1.0.8** (CVE-2026-116695, a CSS-sanitizer-bypass via
  tokenization of malformed URLs) — a `loofah` sub-dependency GitHub's digest didn't surface;
  caught by adding `bundler-audit` below.
- Added `bundler-audit` as a dev dependency and a dedicated CI job that runs
  `bundle exec bundler-audit check --update` against the committed `Gemfile.lock` on every
  push/PR, plus a weekly Monday-morning cron run so newly-disclosed CVEs against already-locked
  versions get caught even when nothing in the repo changes.

## [3.0.0] - 2026-10-05

- **Breaking: replaced the wkhtmltopdf binary dependency with a pooled headless Chrome instance**,
  driven over the DevTools protocol via the [ferrum](https://github.com/rubycdp/ferrum) gem.
  wkhtmltopdf is an unmaintained, years-out-of-date WebKit build with no flexbox/Grid support;
  headless Chrome is the same engine your users already browse the app with. One `Ferrum::Browser`
  process is kept alive per Ruby process instead of spawning a binary per request — see
  [Architecture](docs/architecture.md#browserpool). `config.wkhtmltopdf_path` is gone, replaced by
  `config.browser_options` (passed straight to `Ferrum::Browser.new`).
- **Breaking: `pdf_options[:wkhtmltopdf_options]` is gone, replaced by `pdf_options[:print_options]`**
  — Chrome's print-to-PDF parameters (`landscape`, `format`, `margin_*`, `scale`,
  `display_header_footer`/`header_template`/`footer_template`, `page_ranges`,
  `prefer_css_page_size`, plus `javascript_delay` as the gem's own convenience) instead of literal
  wkhtmltopdf CLI flags. The old `orientation`/`page_size` flag names are no longer recognized —
  use `landscape`/`format`. See the README's options table.
- **Breaking: wire-up changed from `before_action :html_to_pdf` to `include HtmlToPdf` +
  `around_action :html_to_pdf`**, and the gem no longer auto-includes itself into every
  `ActionController::Base` subclass in the host app. This fixes two real bugs found while testing
  the previous design against an actual Rails app rather than a stub: every PDF request raised
  `AbstractController::DoubleRenderError` (Rails' `response=` setter is documented to mark the
  response as already-rendered the instant it's assigned; the old shadow-controller design copied
  that flag onto the real controller), and any `before_action` declared after `html_to_pdf` never
  ran before the view was captured. See
  [The DoubleRenderError trap](https://ramlaxmanyadav.github.io/htmlToPdf/rails-double-render-pdf.html)
  for the full story and [Rails integration](docs/rails-integration.md) for the new wiring.
- **Security: `header_template`/`footer_template` are now filtered out of request-supplied
  `print_options` by default** — unlike every other print option, they're raw HTML Chrome renders
  as-is, which made them an SSRF vector (`<img src="http://internal-host/...">`) on any action that
  forwards `pdf_options` from request params. Only honored from `config.default_options` unless
  `config.allow_request_templates = true` is set explicitly. See [Security](docs/security.md).
- **Security: `javascript_delay` is now capped** at `config.max_javascript_delay_ms` (default 10
  seconds) — previously an uncapped value let one caller stall the shared browser pool for every
  other in-flight PDF render in the same process.
- Fixed: a per-request browser context leaked on every single render (the context Chrome creates
  for isolation was never disposed unless `create_page` was called with its own block).
- Fixed: a gem-wide default `:format`/margin in `config.default_options` could silently clobber an
  explicit per-request `paper_width`/`paper_height`/`:padding` instead of being overridden by it.
- Added: an automated test suite (RSpec + [combustion](https://github.com/pat/combustion) for a
  real-Rails-dispatch integration spec) and CI across Ruby 3.1–3.4 on every push/PR.

## [2.0.0] and earlier

Rendered via the wkhtmltopdf binary; see git history prior to 3.0.0 for details.
