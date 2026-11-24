require "spec_helper"

RSpec.describe HtmlToPdf::Converter do
  let(:fake_browser) { instance_double(Ferrum::Browser, quit: nil) }
  let(:fake_page) { instance_double(Ferrum::Page, go_to: nil, pdf: "%PDF-fake-bytes") }
  let(:written_path) { [] }

  before do
    allow(Ferrum::Browser).to receive(:new).and_return(fake_browser)
    allow(fake_browser).to receive(:create_page) do |&block|
      block.call(fake_page)
    end
    allow(fake_page).to receive(:go_to) { |url| written_path << url.delete_prefix("file://") }
  end

  after { HtmlToPdf::BrowserPool.reset! }

  describe ".convert" do
    it "writes the HTML to a temp file under config.tmp_dir, converts it, then deletes the temp file" do
      Dir.mktmpdir do |dir|
        HtmlToPdf.configure { |c| c.tmp_dir = dir }

        result = described_class.convert("<h1>hi</h1>", print_options: {}, javascript_delay: nil)

        expect(result).to eq("%PDF-fake-bytes")
        expect(written_path.first).to start_with(dir)
        expect(File.exist?(written_path.first)).to be false
      end
    end

    it "strips the \\&quot; artifact the same way the synchronous path always has" do
      allow(File).to receive(:write).and_call_original

      described_class.convert('<p>say \\&quot;hi\\&quot;</p>', print_options: {}, javascript_delay: nil)

      expect(File).to have_received(:write).with(anything, "<p>say hi</p>")
    end

    it "deletes the temp file even if the conversion raises" do
      allow(fake_browser).to receive(:create_page).and_raise(ArgumentError, "boom")
      written = []
      allow(File).to receive(:write).and_wrap_original { |m, path, content| written << path; m.call(path, content) }

      expect { described_class.convert("<p>x</p>", print_options: {}, javascript_delay: nil) }
        .to raise_error(ArgumentError)
      expect(File.exist?(written.first)).to be false
    end
  end

  describe ".render_pdf" do
    it "sleeps for javascript_delay/1000 seconds before capturing, when positive" do
      allow(described_class).to receive(:sleep)

      Tempfile.create(["x", ".html"]) do |f|
        described_class.render_pdf(f.path, print_options: {}, javascript_delay: 500)
      end

      expect(described_class).to have_received(:sleep).with(0.5)
    end

    it "does not sleep when javascript_delay is nil or zero" do
      allow(described_class).to receive(:sleep)

      Tempfile.create(["x", ".html"]) do |f|
        described_class.render_pdf(f.path, print_options: {}, javascript_delay: nil)
      end

      expect(described_class).not_to have_received(:sleep)
    end
  end
end
