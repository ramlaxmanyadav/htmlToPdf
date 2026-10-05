# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
