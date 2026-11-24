require "spec_helper"

RSpec.describe HtmlToPdf::JobStatus do
  describe "lifecycle" do
    it "moves through queued -> processing -> completed, persisted via config.job_status_store" do
      status = described_class.new("job-1", metadata: { invoice_id: 42 })

      status.queued!
      expect(status.state).to eq("queued")
      expect(status.queued_at).to be_a(Time)

      status.processing!
      expect(status.state).to eq("processing")
      expect(status.started_at).to be_a(Time)

      status.completed!(result: { adapter: :s3, key: "invoices/42.pdf" })
      expect(status.state).to eq("completed")
      expect(status.result).to eq(adapter: :s3, key: "invoices/42.pdf")
      expect(status.finished_at).to be_a(Time)
      expect(status.metadata).to eq(invoice_id: 42)
    end

    it "records an exception's class and message on failed!, not the raw exception" do
      status = described_class.new("job-2")

      status.failed!(ArgumentError.new("bad print_options"))

      expect(status.state).to eq("failed")
      expect(status.error).to eq(class: "ArgumentError", message: "bad print_options")
    end

    it "#queued?/#processing?/#completed?/#failed? reflect the current state" do
      status = described_class.new("job-4")
      status.queued!
      expect(status.queued?).to be true
      expect(status.processing?).to be false

      status.processing!
      expect(status.processing?).to be true
      expect(status.queued?).to be false

      status.completed!(result: nil)
      expect(status.completed?).to be true
    end
  end

  describe ".find" do
    it "reads back a status written by a different instance (e.g. a worker process)" do
      described_class.new("job-5", metadata: { a: 1 }).processing!

      found = described_class.find("job-5")

      expect(found.state).to eq("processing")
      expect(found.metadata).to eq(a: 1)
    end

    it "returns a status with a nil state for a job_id nothing has written yet" do
      found = described_class.find("never-seen")

      expect(found.state).to be_nil
    end
  end

  describe "the default store (CacheStore)" do
    it "is namespaced under htmlToPdf:job_status: so it can't collide with the host app's own cache keys" do
      described_class.new("job-6").queued!

      expect(Rails.cache.read("htmlToPdf:job_status:job-6")).to include(state: "queued")
    end

    it "honors config.job_status_ttl as the cache expiry" do
      HtmlToPdf.configure { |c| c.job_status_ttl = 60 }
      expect(Rails.cache).to receive(:write).with(anything, anything, hash_including(expires_in: 60))

      described_class.new("job-7").queued!
    end
  end
end
