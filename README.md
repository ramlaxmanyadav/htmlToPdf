# HtmlToPdf

This gem will generate pdf of the action's html requested as pdf. 

Supports Rails 7.x and Rails 8.x (latest).

## Installation
#### Install and setup `wkhtmltopdf`. Please refer https://wkhtmltopdf.org for more details. 

Add this line to your application's Gemfile:

    gem 'htmlToPdf'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install htmlToPdf

## Usage

write following code inside Application Controller

    before_action :html_to_pdf

in views:

    <%= link_to 'download', your_action_path(:format => 'pdf') %>

customizing pdf downloads:

you can customize pdf like you can give the name and layout for the pdf.to customize pdf use this following example:

    <%= link_to 'download', your_action_path(:format => 'pdf',:pdf_options => {title: 'pdf_name', layout: 'layout_name'}) %>

 this will generate the pdf of your_action named `pdf_name.pdf` with layout `layout_name`.

 one can call any action as pdf and he get the pdf file of that action's html.

customizing page padding and wkhtmltopdf options:

    <%= link_to 'download', your_action_path(:format => 'pdf', :pdf_options => {
      title: 'pdf_name',
      layout: 'layout_name',
      padding: '10mm',
      wkhtmltopdf_options: {
        orientation: 'Landscape',
        page_size: 'A4',
        margin_top: '15mm',
        grayscale: true
      }
    }) %>

 `padding` is a shorthand that sets all four margins at once. `wkhtmltopdf_options` accepts **any** option the `wkhtmltopdf` CLI supports (underscores or dashes both work, e.g. `margin_top`, `page_size`, `orientation`, `dpi`, `zoom`, `encoding`, `javascript_delay`, `disable_smart_shrinking`, ...) — see https://wkhtmltopdf.org for the full list. Boolean-style flags (e.g. `grayscale: true`) are passed as bare flags; anything else is passed as `--flag value`.

 ##### Security note: `pdf_options` is read from the request's query params and forwarded verbatim as CLI flags to `wkhtmltopdf`. If `your_action_path` is publicly reachable, anyone can pass arbitrary `wkhtmltopdf` flags to it. Only expose the pdf format on actions where that's acceptable, or filter `pdf_options` yourself before it reaches `html_to_pdf` (e.g. in a `before_action` that runs earlier).

## Configuration

Set gem-wide defaults in an initializer (e.g. `config/initializers/html_to_pdf.rb`):

    HtmlToPdf.configure do |config|
      # Path to the wkhtmltopdf binary. Defaults to "wkhtmltopdf" (resolved via $PATH).
      # Useful when it's installed via the wkhtmltopdf-binary gem or a custom location.
      config.wkhtmltopdf_path = Wkhtmltopdf.path # or an absolute path string

      # Layout used when pdf_options[:layout] isn't given. Defaults to "application".
      config.default_layout = "pdf"

      # wkhtmltopdf options applied to every PDF, merged under any per-request
      # padding/wkhtmltopdf_options. Defaults to {}.
      config.default_options = { dpi: 300, margin_top: "10mm" }

      # Directory temporary .html/.pdf files are written to. Defaults to Rails.root/tmp.
      config.tmp_dir = Rails.root.join("tmp", "pdfs")
    end

 ##### Make sure you have configured your `asset_host` in application's Rails environment, otherwise assets might not be loaded properly.

`config.action_controller.asset_host = "YOUR_ASSETS_HOST"`

