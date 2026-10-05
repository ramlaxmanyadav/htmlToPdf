# HtmlToPdf in Rails

[← Back to README](../README.md)

## Wiring it up

```ruby
class ApplicationController < ActionController::Base
  include HtmlToPdf
  around_action :html_to_pdf
end
```

It has to be `include` + `around_action`, not just a `before_action` — see
[Architecture](architecture.md#request-lifecycle) for exactly why, and
[The DoubleRenderError trap](https://ramlaxmanyadav.github.io/htmlToPdf/rails-double-render-pdf.html)
for the bug this replaced. `HtmlToPdf` is a plain `ActiveSupport::Concern` with no `included do`
block, so including it only defines the method — nothing runs for any controller until you also
declare the `around_action` yourself, scoped however you like:

```ruby
# Only the actions that actually support a PDF export, not every action on the controller.
around_action :html_to_pdf, only: [:index, :show]
```

## Callback ordering

Because this is a real `around_action`, every other callback runs in its normal, declared
position — a `before_action` declared *after* `html_to_pdf` still runs before the view is
captured, same as it would for an ordinary HTML request:

```ruby
class InvoicesController < ApplicationController
  around_action :html_to_pdf, only: [:show]
  before_action :set_invoice, only: [:show]   # runs normally; @invoice is set before capture

  def show
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end
end
```

`rescue_from` works the same way — an exception raised inside the action during the `yield`
propagates normally and is handled by whatever `rescue_from` the controller has configured, exactly
as it would outside a PDF request.

## Custom layout and filename per request

```erb
<%= link_to "Download PDF", invoice_path(@invoice, format: :pdf, pdf_options: {
  title: "invoice-#{@invoice.number}",
  layout: "pdf"
}) %>
```

`pdf_options[:layout]` overrides `config.default_layout` for just this render — handy for a
print-specific layout with no navigation chrome, as opposed to your app's normal layout. See the
[README](../README.md#usage) for the full `pdf_options`/`print_options` reference.

## Production deployment: Chrome in Docker

The most common point of friction isn't the gem, it's "Chrome isn't in my container image."
Ferrum needs a real Chrome/Chromium binary on the machine actually rendering PDFs. For a
Debian/Ubuntu-based image:

```dockerfile
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      chromium \
    && rm -rf /var/lib/apt/lists/*
```

If your container runs as root (common for a minimal/CI image, uncommon for a real production
image — prefer a non-root user there if you can), Chrome refuses to start without its sandbox
disabled:

```ruby
# config/initializers/html_to_pdf.rb
HtmlToPdf.configure do |config|
  config.browser_options = { browser_options: { "no-sandbox" => nil } } if ENV["CHROME_NO_SANDBOX"]
end
```

Don't set `no-sandbox` unconditionally on a machine where you don't control what else runs — it's
specifically a root-in-a-throwaway-container accommodation, not a default.

## The asset_host gotcha

`HtmlToPdf` writes the rendered view to a temporary `.html` file and points Chrome at it via a
`file://` URL (so relative paths still have a real base URI to resolve against — see
[Architecture](architecture.md#request-lifecycle)). A stylesheet tag that emits a root-relative URL
(`/assets/application-abcd1234.css`, Rails' normal default) resolves against that `file://` origin
to `file:///assets/application-abcd1234.css` — which doesn't exist — and the CSS silently fails to
load. The PDF comes out completely unstyled, with no error anywhere.

The fix is `config.asset_host`, set to something that actually resolves over real HTTP. Hardcoding
a host only works until someone runs the app on a different port, so derive it from the request
instead:

```ruby
# config/environments/development.rb
config.asset_host = Proc.new { |_source, request| request ? "#{request.scheme}://#{request.host_with_port}" : nil }
```

Production usually already has a real `asset_host` pointed at a CDN for unrelated reasons — if
yours doesn't yet, this is exactly the same fix, just pointed at your own domain instead of
`localhost`.
