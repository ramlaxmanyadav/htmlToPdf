require "spec_helper"
require "aws-sdk-s3"

RSpec.describe HtmlToPdf::Storage::S3Adapter do
  # Aws::S3::Client's own built-in test mode — no real network calls, no
  # WebMock needed.
  let(:client_options) { { stub_responses: true, region: "us-east-1" } }

  it "uploads the PDF bytes to the given bucket/key and returns where it landed" do
    captured_client = nil
    allow(Aws::S3::Client).to receive(:new).and_wrap_original { |original, *args| captured_client = original.call(*args) }

    result = described_class.new(key: "invoices/1.pdf", bucket: "my-bucket", client_options: client_options)
      .store("%PDF-fake-bytes")

    put_object_call = captured_client.api_requests.find { |r| r[:operation_name] == :put_object }
    expect(put_object_call[:params]).to include(
      bucket: "my-bucket", key: "invoices/1.pdf", body: "%PDF-fake-bytes", content_type: "application/pdf"
    )
    expect(result).to include(adapter: :s3, bucket: "my-bucket", key: "invoices/1.pdf")
    expect(result[:url]).to include("my-bucket").and include("invoices/1.pdf")
  end

  it "falls back to config.s3_bucket/s3_client_options when not given per call" do
    HtmlToPdf.configure do |c|
      c.s3_bucket = "configured-bucket"
      c.s3_client_options = client_options
    end

    result = described_class.new(key: "x.pdf").store("bytes")

    expect(result[:bucket]).to eq("configured-bucket")
  end

  it "raises ArgumentError when no bucket is given or configured" do
    expect { described_class.new(key: "x.pdf") }.to raise_error(ArgumentError, /bucket/)
  end

  it "raises a clear LoadError if aws-sdk-s3 can't be required" do
    adapter = described_class.new(key: "x.pdf", bucket: "b", client_options: client_options)
    allow(adapter).to receive(:require).with("aws-sdk-s3").and_raise(LoadError)

    expect { adapter.store("bytes") }.to raise_error(LoadError, /add `gem "aws-sdk-s3"`/)
  end
end
