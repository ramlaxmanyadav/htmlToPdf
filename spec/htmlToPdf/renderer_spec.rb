require "spec_helper"

RSpec.describe HtmlToPdf::Renderer do
  before do
    HtmlToPdf.configure { |c| c.default_url_options = { http_host: "example.test" } }
  end

  describe "without config.default_url_options set" do
    it "raises a clear ArgumentError instead of silently rendering broken asset/route URLs" do
      HtmlToPdf.configure { |c| c.default_url_options = nil }

      expect { described_class.render(controller: WidgetsController, action: :show) }
        .to raise_error(ArgumentError, /default_url_options/)
    end
  end

  describe "rendering outside of a request (stubbed Ferrum, no real Chrome)" do
    let(:fake_browser) { instance_double(Ferrum::Browser, quit: nil) }
    let(:fake_page) { instance_double(Ferrum::Page, go_to: nil, pdf: "%PDF-fake-bytes") }

    before do
      allow(Ferrum::Browser).to receive(:new).and_return(fake_browser)
      allow(fake_browser).to receive(:create_page).and_yield(fake_page)
    end

    after { HtmlToPdf::BrowserPool.reset! }

    it "renders the given controller/action via ActionController::Renderer and converts it" do
      result = described_class.render(
        controller: WidgetsController,
        action: :show,
        assigns: { widget: "Widget #1" }
      )

      expect(result).to eq("%PDF-fake-bytes")
      expect(fake_page).to have_received(:pdf).with(hash_including(encoding: :binary))
    end

    it "accepts the controller as a String, matching the synchronous path's flexibility" do
      result = described_class.render(controller: "WidgetsController", action: :show)

      expect(result).to eq("%PDF-fake-bytes")
    end

    it "resolves print_options/layout through the same HtmlToPdf::PrintOptions as the synchronous path" do
      described_class.render(
        controller: WidgetsController,
        action: :show,
        pdf_options: { print_options: { landscape: true, format: "A4" } }
      )

      expect(fake_page).to have_received(:pdf).with(hash_including(landscape: true, paper_width: 8.27))
    end

    it "strips header_template/footer_template from pdf_options by default, same as the synchronous path" do
      described_class.render(
        controller: WidgetsController,
        action: :show,
        pdf_options: { print_options: { header_template: "<script>evil</script>" } }
      )

      expect(fake_page).to have_received(:pdf) do |**opts|
        expect(opts).not_to have_key(:header_template)
      end
    end
  end
end
