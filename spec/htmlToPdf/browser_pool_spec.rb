require "spec_helper"

RSpec.describe HtmlToPdf::BrowserPool do
  after { described_class.reset! }

  describe "pooling (stubbed Ferrum, no real Chrome)" do
    let(:fake_browser) { instance_double(Ferrum::Browser, quit: nil) }

    before do
      allow(Ferrum::Browser).to receive(:new).and_return(fake_browser)
    end

    it "memoizes one browser across multiple with_page calls" do
      allow(fake_browser).to receive(:create_page).and_yield(double("page")).twice

      described_class.with_page { |_page| nil }
      described_class.with_page { |_page| nil }

      expect(Ferrum::Browser).to have_received(:new).once
    end

    it "quits and drops the memoized browser on reset!" do
      described_class.browser

      described_class.reset!

      expect(fake_browser).to have_received(:quit)
      allow(Ferrum::Browser).to receive(:new).and_return(fake_browser)
      described_class.browser
      expect(Ferrum::Browser).to have_received(:new).twice
    end

    it "retries once after a recoverable error, then succeeds on the new browser" do
      call_count = 0
      allow(fake_browser).to receive(:create_page) do |&block|
        call_count += 1
        raise Ferrum::DeadBrowserError if call_count == 1

        block.call(double("page"))
      end

      result = described_class.with_page { |_page| :ok }

      expect(result).to eq(:ok)
      expect(call_count).to eq(2)
    end

    it "gives up and raises after the retry also fails" do
      allow(fake_browser).to receive(:create_page).and_raise(Ferrum::DeadBrowserError)

      expect { described_class.with_page { |_page| nil } }.to raise_error(Ferrum::DeadBrowserError)
    end

    it "does not retry a non-recoverable error" do
      allow(fake_browser).to receive(:create_page).and_raise(ArgumentError, "boom")

      expect { described_class.with_page { |_page| nil } }.to raise_error(ArgumentError)
      expect(fake_browser).to have_received(:create_page).once
    end

    it "passes configuration.browser_options straight to Ferrum::Browser.new" do
      HtmlToPdf.configure { |c| c.browser_options = { timeout: 42 } }
      allow(fake_browser).to receive(:create_page).and_yield(double("page"))

      described_class.with_page { |_page| nil }

      expect(Ferrum::Browser).to have_received(:new).with(timeout: 42)
    end
  end

  describe "against a real Chrome process", :chrome do
    it "reuses the same browser process across renders" do
      pids = Array.new(3) do
        described_class.with_page do |page|
          page.go_to("about:blank")
          described_class.browser.process.pid
        end
      end

      expect(pids.uniq.size).to eq(1)
    end

    it "does not leak a browser context per render (block form disposes it)" do
      5.times { described_class.with_page { |page| page.go_to("about:blank") } }

      expect(described_class.browser.contexts.size).to eq(0)
    end
  end
end
