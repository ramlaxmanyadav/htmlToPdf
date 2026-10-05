# Security model

[← Back to README](../README.md)

`pdf_options` is typically read straight from request params (`params[:pdf_options]`) — the README
example passes it through a `link_to` query string. That means anything accepted under
`pdf_options[:print_options]` is, by default, something an unauthenticated caller can set on any
action that exposes the `pdf` format. The design goal is that the worst a caller can do with that
is make an ugly PDF, never run arbitrary code or reach another host.

## What's safe by construction

Every `print_options` key except two (below) is a validated number, boolean, or enum:

- `format` is checked against a fixed table of named paper sizes (`PrintOptions::PAPER_SIZES`) and
  raises `ArgumentError` on anything else — it can't be used to inject arbitrary strings into
  Chrome's protocol layer.
- `margin_*`/`paper_width`/`paper_height` go through `PrintOptions.to_inches`, which only accepts a
  number or a `number + unit` string (`mm`/`cm`/`in`/`px`) — again, `ArgumentError` on anything else.
- `landscape`, `print_background`, `display_header_footer`, `prefer_css_page_size` are passed
  straight through to Chrome's `Page.printToPDF`, which itself only accepts booleans for these.

This is a meaningfully narrower surface than the gem's wkhtmltopdf-based predecessor, which
forwarded `wkhtmltopdf_options` as literal CLI flags to a subprocess — any key a caller supplied
became an actual argv entry to a binary. `print_options` is a fixed hash of typed values sent over
the Chrome DevTools Protocol; there's no argv for a caller to inject into.

## The one exception: header_template / footer_template

These two are raw HTML — Chrome renders them as-is inside the printed header/footer. Unlike every
other key, there's no validation that could make an arbitrary string safe here: a caller who
controls `header_template` can embed anything, including
`<img src="http://169.254.169.254/latest/meta-data/...">` or any other internal-network URL,
and the Chrome process (which has real network access) will fetch it — a server-side request
forgery vector, not merely an HTML-injection one.

Because of that, `header_template`/`footer_template` are **stripped from request-supplied
`print_options` by default**. They're only honored from `config.default_options` — Ruby code you
wrote, not request input:

```ruby
# config/initializers/html_to_pdf.rb — this is fine, it's your own code
HtmlToPdf.configure do |config|
  config.default_options = {
    header_template: "<span></span>",
    footer_template: "<div style='font-size:10px;text-align:center;'><span class=\"pageNumber\"></span></div>"
  }
end
```

If you genuinely need a caller to control the header/footer HTML — and have your own separate
sanitization in place before `pdf_options` ever reaches `html_to_pdf` — that's what
`config.allow_request_templates` is for:

```ruby
# Only do this if pdf_options never flows from unfiltered request params in your app.
HtmlToPdf.configure { |config| config.allow_request_templates = true }
```

Default is `false`. Leave it there unless you've specifically reviewed what feeds `pdf_options` in
your app.

## javascript_delay has a ceiling

`render_pdf` sleeps for `javascript_delay` milliseconds between page load and capture, while
holding the pooled browser's page/context open (see [Architecture](architecture.md#browserpool)).
Without a cap, one caller passing an enormous value would stall every other PDF render sharing that
browser for however long they chose — a single-request denial of service against a resource every
thread in the process shares. `config.max_javascript_delay_ms` (default `10_000`, i.e. 10 seconds)
clamps it; raise it only if you trust whatever can set `javascript_delay` in your app.

## The baseline that doesn't change

None of the above touches the actual page content itself: `html_to_pdf` renders your view's own
HTML, exactly as your app would render it for a normal request. If that view embeds
caller-controlled content unescaped, or makes requests to caller-controlled URLs, that's the same
risk any server-rendered HTML page has — PDF conversion doesn't add to it, but it doesn't take it
away either. The guidance already in the README stands: don't expose the `pdf` format on an action
where you wouldn't be comfortable letting a caller influence layout, and don't pass
request-controlled values into `pdf_options` on a publicly reachable action without thinking about
what in there is actually safe to expose.
