require "spec_helper"

RSpec.describe HtmlToPdf::Configuration do
  describe "defaults" do
    subject(:config) { described_class.new }

    it "has no browser_options, letting Ferrum auto-detect Chrome" do
      expect(config.browser_options).to eq({})
    end

    it "defaults to the application layout" do
      expect(config.default_layout).to eq("application")
    end

    it "prints backgrounds by default" do
      expect(config.default_options).to eq(print_background: true)
    end

    it "does not honor request-supplied header/footer templates by default" do
      expect(config.allow_request_templates).to eq(false)
    end

    it "caps javascript_delay at 10 seconds by default" do
      expect(config.max_javascript_delay_ms).to eq(10_000)
    end
  end

  describe "HtmlToPdf.configure" do
    after { HtmlToPdf.reset_configuration! }

    it "yields the shared configuration for mutation" do
      HtmlToPdf.configure { |c| c.default_layout = "pdf" }

      expect(HtmlToPdf.configuration.default_layout).to eq("pdf")
    end

    it "memoizes the same configuration instance across calls" do
      expect(HtmlToPdf.configuration).to equal(HtmlToPdf.configuration)
    end
  end

  describe ".reset_configuration!" do
    it "replaces the configuration with fresh defaults" do
      HtmlToPdf.configure { |c| c.default_layout = "pdf" }

      HtmlToPdf.reset_configuration!

      expect(HtmlToPdf.configuration.default_layout).to eq("application")
    end
  end
end
