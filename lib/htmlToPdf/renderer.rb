require "htmlToPdf/converter"
require "htmlToPdf/print_options"

module HtmlToPdf
  # Renders a controller action to PDF bytes *outside* of a request —
  # there's no controller instance mid-dispatch to call render_to_string on,
  # the way the synchronous `include HtmlToPdf` / around_action path does.
  # Used by HtmlToPdf::GenerateJob (and anything else running in a
  # background job), via ActionController::Renderer — the same Rails API
  # ActionMailer itself uses to render views outside a request.
  module Renderer
    module_function

    # controller: a controller Class (or its String name). action: Symbol/
    # String. assigns: a Hash of the ivars the view needs — this is the
    # actual mechanism (not `params`) for feeding a renderer-rendered
    # template data; ActiveRecord objects pass through fine since ActiveJob
    # serializes them via GlobalID. pdf_options: same shape taken by the
    # synchronous path (:title is unused here — callers get the PDF bytes
    # back directly, not a filename).
    def render(controller:, action:, assigns: {}, pdf_options: {})
      env = default_url_options!
      controller_class = resolve_controller(controller)
      layout = pdf_options[:layout] || HtmlToPdf.configuration.default_layout
      print_options, javascript_delay = HtmlToPdf::PrintOptions.build(pdf_options)

      html = controller_class.renderer.new(env).render(
        template: "#{controller_class.controller_path}/#{action}",
        assigns: assigns,
        layout: layout
      )

      HtmlToPdf::Converter.convert(html, print_options: print_options, javascript_delay: javascript_delay)
    end

    def resolve_controller(controller)
      controller.is_a?(String) ? controller.constantize : controller
    end

    def default_url_options!
      env = HtmlToPdf.configuration.default_url_options
      return env if env

      raise ArgumentError,
            "HtmlToPdf.configuration.default_url_options must be set to render a PDF outside " \
            "of a request (there's no request here for HtmlToPdf::Renderer to infer a host " \
            "from, unlike the synchronous controller path). Set it in your initializer, e.g. " \
            'config.default_url_options = { http_host: "app.example.com", https: true } — ' \
            "note these are ActionController::Renderer's env keys (http_host/https), not " \
            "config.action_mailer.default_url_options's (host/protocol). See " \
            "docs/background-jobs.md."
    end
  end
end
