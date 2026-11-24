require "spec_helper"

# Loaded eagerly by lib/htmlToPdf.rb itself (guarded on ActiveJob::Base
# already being defined, true here) — required explicitly anyway so this
# file doesn't depend on load order against other specs.
require "htmlToPdf/generate_job"

RSpec.describe HtmlToPdf::GenerateJob do
  let(:fake_browser) { instance_double(Ferrum::Browser, quit: nil) }
  let(:fake_page) { instance_double(Ferrum::Page, go_to: nil, pdf: "%PDF-fake-bytes") }

  it "is defined as soon as the gem loads, not only after HtmlToPdf.generate_later is first called — a separate Sidekiq/Solid Queue worker process that never calls generate_later itself still needs the class available to perform a job the web process enqueued" do
    expect(defined?(HtmlToPdf::GenerateJob)).to be_truthy
  end

  before do
    HtmlToPdf.configure { |c| c.default_url_options = { http_host: "example.test" } }
    allow(Ferrum::Browser).to receive(:new).and_return(fake_browser)
    allow(fake_browser).to receive(:create_page).and_yield(fake_page)
  end

  after { HtmlToPdf::BrowserPool.reset! }

  describe "HtmlToPdf.generate_later" do
    it "enqueues a GenerateJob and immediately writes a queued JobStatus" do
      job = nil
      expect do
        job = HtmlToPdf.generate_later(
          controller: WidgetsController, action: :show, assigns: { widget: "Widget #1" }
        )
      end.to have_enqueued_job(described_class)

      expect(HtmlToPdf::JobStatus.find(job.job_id).state).to eq("queued")
    end
  end

  describe "#perform" do
    it "renders the PDF, stores it, and marks the status completed, calling on_job_success" do
      on_success = nil
      HtmlToPdf.configure { |c| c.on_job_success = ->(status) { on_success = status } }

      perform_enqueued_jobs do
        HtmlToPdf.generate_later(controller: WidgetsController, action: :show, assigns: { widget: "W" })
      end

      status = on_success
      expect(status.state).to eq("completed")
      expect(status.result).to be_nil # no `store:` was given
    end

    it "stores the PDF via the given adapter when store: is passed" do
      document = Document.create!
      perform_enqueued_jobs do
        HtmlToPdf.generate_later(
          controller: WidgetsController, action: :show, assigns: { widget: "W" },
          store: { adapter: :active_storage, record: document, attachment: :pdf }
        )
      end

      document.reload
      expect(document.pdf).to be_attached
    end

    it "retries on a recoverable Ferrum error, then succeeds" do
      call_count = 0
      allow(fake_browser).to receive(:create_page) do |&block|
        call_count += 1
        raise Ferrum::DeadBrowserError if call_count == 1

        block.call(fake_page)
      end

      perform_enqueued_jobs do
        HtmlToPdf.generate_later(controller: WidgetsController, action: :show, assigns: { widget: "W" })
      end

      expect(call_count).to eq(2)
    end

    it "marks the status failed and calls on_job_failure once retries are exhausted" do
      allow(fake_browser).to receive(:create_page).and_raise(Ferrum::DeadBrowserError)
      on_failure_args = nil
      HtmlToPdf.configure { |c| c.on_job_failure = ->(status, error) { on_failure_args = [status, error] } }

      job = nil
      perform_enqueued_jobs do
        job = HtmlToPdf.generate_later(controller: WidgetsController, action: :show, assigns: { widget: "W" })
      end

      status, error = on_failure_args
      expect(error).to be_a(Ferrum::DeadBrowserError)
      expect(status.job_id).to eq(job.job_id)
      expect(HtmlToPdf::JobStatus.find(job.job_id).state).to eq("failed")
    end

    it "discards (no retry) on ArgumentError — a bad print_options can't be fixed by retrying" do
      on_failure_args = nil
      HtmlToPdf.configure { |c| c.on_job_failure = ->(status, error) { on_failure_args = [status, error] } }

      perform_enqueued_jobs do
        HtmlToPdf.generate_later(
          controller: WidgetsController, action: :show,
          pdf_options: { print_options: { format: "not-a-real-format" } }
        )
      end

      expect(fake_browser).not_to have_received(:create_page)
      expect(on_failure_args.last).to be_a(ArgumentError)
    end
  end
end
