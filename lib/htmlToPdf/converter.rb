require "securerandom"
require "fileutils"

module HtmlToPdf
  # Turns an already-rendered HTML string into PDF bytes via the pooled
  # headless Chrome (BrowserPool). Shared by both the synchronous controller
  # path (lib/htmlToPdf.rb#html_to_pdf, which gets its HTML from a real
  # request's render_to_string) and HtmlToPdf::Renderer (which gets its HTML
  # from ActionController::Renderer, outside of a request) — the "write to a
  # temp file, point Chrome's file:// at it, clean up" steps are identical
  # either way.
  module Converter
    module_function

    def convert(html, print_options:, javascript_delay:)
      # Chrome loads this over file://, not a Rails-served response, so a
      # relative asset URL only resolves if config.action_controller.asset_host
      # is set — see docs/rails-integration.md#the-asset_host-gotcha.
      file_content = html.gsub(/\\&quot;/, "")

      tmp_dir = HtmlToPdf.configuration.tmp_dir || File.join(Rails.root, "tmp")
      FileUtils.mkdir_p(tmp_dir)
      source_file = File.join(tmp_dir, "#{Time.now.to_i}_#{SecureRandom.hex(8)}.html")
      File.write(source_file, file_content)

      begin
        render_pdf(source_file, print_options: print_options, javascript_delay: javascript_delay)
      ensure
        File.delete(source_file) if File.exist?(source_file)
      end
    end

    def render_pdf(source_file, print_options:, javascript_delay:)
      HtmlToPdf::BrowserPool.with_page do |page|
        page.go_to("file://#{source_file}")
        sleep(javascript_delay / 1000.0) if javascript_delay.to_i.positive?
        page.pdf(encoding: :binary, **(print_options || {}))
      end
    end
  end
end
