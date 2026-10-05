# HtmlToPdf

This gem will generate pdf of the action's html requested as pdf.

Supports Rails 7.x and Rails 8.x (latest).

Renders through a pooled headless Chrome instance (via the [ferrum](https://github.com/rubycdp/ferrum) gem), so you get modern CSS (flexbox, grid, custom fonts) and only need a Chrome/Chromium install — no separate renderer binary to install or package.

## Installation

#### Make sure Chrome or Chromium is installed on the machine that will render PDFs.

Ferrum auto-detects a local Google Chrome / Chromium install (including on macOS, Linux and in most CI images). If it's installed somewhere non-standard, or you're running as root in Docker, see [Configuration](#configuration) below.

Add this line to your application's Gemfile:

    gem 'htmlToPdf'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install htmlToPdf

## Usage

Opt in on the controller(s) that should support PDF export — typically `ApplicationController`:

    class ApplicationController < ActionController::Base
      include HtmlToPdf
      around_action :html_to_pdf
    end

It must be an `around_action`, not a `before_action`: the rest of the callback chain and the action itself run normally via `yield`, so any other `before_action`s (e.g. one that loads `@record`) still run in their usual order and their instance variables are available to the view. Nothing happens for ordinary requests — `html_to_pdf` only takes over when the request's format is `pdf`.

in views:

    <%= link_to 'download', your_action_path(:format => 'pdf') %>

customizing pdf downloads:

you can customize pdf like you can give the name and layout for the pdf.to customize pdf use this following example:

    <%= link_to 'download', your_action_path(:format => 'pdf',:pdf_options => {title: 'pdf_name', layout: 'layout_name'}) %>

 this will generate the pdf of your_action named `pdf_name.pdf` with layout `layout_name`.

 one can call any action as pdf and he get the pdf file of that action's html.

customizing page padding and print options:

    <%= link_to 'download', your_action_path(:format => 'pdf', :pdf_options => {
      title: 'pdf_name',
      layout: 'layout_name',
      padding: '10mm',
      print_options: {
        landscape: true,
        format: 'A4',
        margin_top: '15mm',
        scale: 0.9,
        print_background: true,
        display_header_footer: true,
        header_template: '<span></span>',
        footer_template: '<div style="font-size:10px; width:100%; text-align:center;"><span class="pageNumber"></span> / <span class="totalPages"></span></div>',
        javascript_delay: 500
      }
    }) %>

`padding` is a shorthand that sets all four margins at once. `print_options` accepts the options Chrome's print-to-PDF engine supports:

| Option | Type | Notes |
|---|---|---|
| `landscape` | boolean | |
| `format` | string | `'A4'`, `'Letter'`, `'Legal'`, `'Tabloid'`, `'Ledger'`, `'A0'`–`'A6'` (case-insensitive) |
| `paper_width`, `paper_height` | number or string | used instead of `format`; accepts a plain number (inches) or a string with a unit, e.g. `'210mm'` |
| `margin_top`, `margin_bottom`, `margin_left`, `margin_right` | number or string | same units as above |
| `scale` | number | 0.1–2 |
| `print_background` | boolean | defaults to `true` (configurable, see below) |
| `display_header_footer`, `header_template`, `footer_template` | boolean / string | templates are HTML; Chrome supports `<span class="pageNumber">`, `<span class="totalPages">`, `<span class="date">`, `<span class="title">`, `<span class="url">` inside them |
| `page_ranges` | string | e.g. `'1-3'` |
| `prefer_css_page_size` | boolean | honor `@page` CSS size over `format`/`paper_width`/`paper_height` |
| `javascript_delay` | integer (ms) | pause between page load and capture, for content that renders asynchronously |

 ##### Security note: `pdf_options` is read from the request's query params. `print_options` is a fixed, narrow set of PDF layout flags (margins, paper size, headers/footers, etc.) rather than arbitrary CLI arguments forwarded to a subprocess, so it can't be used to inject arbitrary binary flags. Still, only expose the pdf format on actions where letting a caller tweak layout/margins is acceptable, or filter `pdf_options` yourself before it reaches `html_to_pdf` (e.g. in a `before_action` that runs earlier).

## Configuration

Set gem-wide defaults in an initializer (e.g. `config/initializers/html_to_pdf.rb`):

    HtmlToPdf.configure do |config|
      # Keyword options passed straight to Ferrum::Browser.new. Leave empty to
      # let Ferrum auto-detect a local Chrome/Chromium install. Useful for a
      # custom binary path, longer timeouts, or Chrome flags such as
      # no-sandbox when running as root in Docker:
      config.browser_options = {
        # browser_path: '/usr/bin/chromium',
        # timeout: 20,
        # process_timeout: 30,
        # browser_options: { 'no-sandbox' => nil, 'disable-gpu' => nil }
      }

      # Layout used when pdf_options[:layout] isn't given. Defaults to "application".
      config.default_layout = "pdf"

      # Print options (see the table above) applied to every PDF, merged
      # under any per-request padding/print_options. Defaults to
      # { print_background: true }.
      config.default_options = { print_background: true, format: 'A4' }

      # Directory the rendered HTML is temporarily written to before Chrome
      # loads it (via a file:// URL, so relative asset paths resolve).
      # Defaults to Rails.root/tmp.
      config.tmp_dir = Rails.root.join("tmp", "pdfs")
    end

A single headless Chrome process is started lazily and reused across requests in the same Ruby process (each conversion gets its own isolated browser context), since launching Chrome per-request is comparatively expensive. It's restarted automatically if Chrome crashes or stops responding.

 ##### Make sure you have configured your `asset_host` in application's Rails environment, otherwise assets might not be loaded properly.

`config.action_controller.asset_host = "YOUR_ASSETS_HOST"`
