require "spec_helper"

RSpec.describe HtmlToPdf::PrintOptions do
  def build(pdf_options)
    described_class.build(pdf_options)
  end

  describe "precedence" do
    it "lets a per-request :padding override a gem-wide default margin" do
      HtmlToPdf.configure { |c| c.default_options = { margin_top: "1in" } }

      options, = build(padding: "20mm")

      expect(options[:margin_top]).to be_within(0.0001).of(20 / 25.4)
    end

    it "lets an explicit print_options margin win over :padding" do
      options, = build(padding: "20mm", print_options: { margin_top: "5mm" })

      expect(options[:margin_top]).to be_within(0.0001).of(5 / 25.4)
      expect(options[:margin_bottom]).to be_within(0.0001).of(20 / 25.4)
    end

    it "lets explicit paper_width/paper_height override a gem-wide default :format" do
      HtmlToPdf.configure { |c| c.default_options = { format: "A4" } }

      options, = build(print_options: { paper_width: 5, paper_height: 5 })

      expect(options[:paper_width]).to eq(5.0)
      expect(options[:paper_height]).to eq(5.0)
    end

    it "resolves a per-request :format, overriding the default" do
      HtmlToPdf.configure { |c| c.default_options = { format: "A4" } }

      options, = build(print_options: { format: "Letter" })

      expect(options[:paper_width]).to eq(8.50)
      expect(options[:paper_height]).to eq(11.00)
    end

    it "falls back to the resolved default format when nothing is passed" do
      HtmlToPdf.configure { |c| c.default_options = { format: "A4" } }

      options, = build({})

      expect(options[:paper_width]).to eq(8.27)
      expect(options[:paper_height]).to eq(11.70)
    end
  end

  describe "unit conversion" do
    %w[mm cm in px].each do |unit|
      it "accepts #{unit} units on size keys" do
        options, = build(print_options: { margin_top: "10#{unit}" })

        expect(options[:margin_top]).to be_a(Float)
      end
    end

    it "treats a bare number as inches" do
      options, = build(print_options: { margin_top: 2 })

      expect(options[:margin_top]).to eq(2.0)
    end

    it "raises on an unrecognized size value" do
      expect { build(print_options: { margin_top: "lots" }) }.to raise_error(ArgumentError)
    end
  end

  describe "paper format" do
    it "raises on an unknown format name" do
      expect { build(print_options: { format: "Poster" }) }.to raise_error(ArgumentError)
    end

    it "is case-insensitive" do
      options, = build(print_options: { format: "a4" })

      expect(options[:paper_width]).to eq(8.27)
    end
  end

  describe "header_template / footer_template" do
    it "strips them from request-supplied print_options by default" do
      options, = build(print_options: { header_template: "<script>evil()</script>" })

      expect(options).not_to have_key(:header_template)
    end

    it "still honors them from config.default_options, which is trusted app code" do
      HtmlToPdf.configure { |c| c.default_options = { header_template: "<span>trusted</span>" } }

      options, = build({})

      expect(options[:header_template]).to eq("<span>trusted</span>")
    end

    it "honors a request-supplied template only when explicitly opted in" do
      HtmlToPdf.configure { |c| c.allow_request_templates = true }

      options, = build(print_options: { footer_template: "<span>ok</span>" })

      expect(options[:footer_template]).to eq("<span>ok</span>")
    end
  end

  describe "javascript_delay" do
    it "is extracted out of the CDP options hash" do
      options, delay = build(print_options: { javascript_delay: 250 })

      expect(options).not_to have_key(:javascript_delay)
      expect(delay).to eq(250)
    end

    it "is clamped to config.max_javascript_delay_ms" do
      HtmlToPdf.configure { |c| c.max_javascript_delay_ms = 1_000 }

      _, delay = build(print_options: { javascript_delay: 999_999 })

      expect(delay).to eq(1_000)
    end

    it "never goes negative" do
      _, delay = build(print_options: { javascript_delay: -500 })

      expect(delay).to eq(0)
    end

    it "is nil when not given" do
      _, delay = build({})

      expect(delay).to be_nil
    end
  end

  describe "legacy flag names" do
    it "no longer recognizes wkhtmltopdf-style orientation/page_size" do
      options, = build(print_options: { orientation: "Landscape", page_size: "A4" })

      expect(options[:landscape]).to be_nil
      expect(options[:orientation]).to eq("Landscape")
      expect(options[:paper_width]).to be_nil
    end
  end

  describe "key formatting" do
    it "accepts dasherized keys the same as underscored ones" do
      options, = build(print_options: { "margin-top" => "10mm" })

      expect(options[:margin_top]).to be_within(0.0001).of(10 / 25.4)
    end
  end
end
