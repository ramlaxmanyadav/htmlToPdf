require "spec_helper"

# These exercise the controller hook (include HtmlToPdf + around_action)
# against a real Rails dispatch, not a stub. An earlier version of this gem
# hooked in as a before_action that quietly rebuilt the controller and
# re-ran the action on the copy; Rails' own `response=` setter is documented
# to mark the response as already rendered the moment it's assigned, and
# copying the throwaway controller's instance variables back onto the real
# one carried that flag along, so `send_data` raised DoubleRenderError on
# every single PDF request once run against a real app rather than a stub.
# It also meant a before_action declared after html_to_pdf never got to run
# before the view was captured. These specs pin both down so they can't
# silently come back.
RSpec.describe "HtmlToPdf controller integration", type: :request do
  around do |example|
    HtmlToPdf.configure { |c| c.default_options = { print_background: true } }
    example.run
  ensure
    HtmlToPdf::BrowserPool.reset!
  end

  it "does not raise DoubleRenderError and returns a real PDF" do
    get "/widgets/42", params: { format: :pdf }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body.byteslice(0, 4)).to eq("%PDF")
  end

  it "runs a before_action declared after the around_action before capturing the view" do
    get "/widgets/42", params: { format: :pdf }

    pdf_text = extract_text(response.body)
    expect(pdf_text).to include("Widget #42")
  end

  it "runs the action body exactly once" do
    WidgetsController.show_invocations = 0

    get "/widgets/7", params: { format: :pdf }

    expect(WidgetsController.show_invocations).to eq(1)
  end

  it "leaves ordinary HTML requests completely unaffected" do
    get "/widgets/42"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("Widget #42")
  end

  it "honors a custom layout passed via pdf_options" do
    get "/widgets/5", params: { format: :pdf, pdf_options: { layout: "pdf" } }

    expect(extract_text(response.body)).to include("PDF LAYOUT")
  end

  it "still runs rescue_from for an exception raised inside the action" do
    get "/booms/1", params: { format: :pdf }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to eq("handled")
  end

  def extract_text(pdf_bytes)
    require "tempfile"
    file = Tempfile.new(["spec", ".pdf"], binmode: true)
    file.write(pdf_bytes)
    file.flush
    `pdftotext #{file.path} -`
  ensure
    file&.close!
  end
end
