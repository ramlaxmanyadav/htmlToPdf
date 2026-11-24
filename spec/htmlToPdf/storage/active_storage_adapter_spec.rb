require "spec_helper"

RSpec.describe HtmlToPdf::Storage::ActiveStorageAdapter do
  it "attaches the PDF bytes to the given record/attachment and returns blob metadata" do
    document = Document.create!

    result = described_class.new(record: document, attachment: :pdf, filename: "invoice.pdf")
      .store("%PDF-1.4 fake bytes")

    document.reload
    expect(document.pdf).to be_attached
    expect(document.pdf.blob.filename.to_s).to eq("invoice.pdf")
    expect(document.pdf.blob.content_type).to eq("application/pdf")
    expect(result).to eq(
      adapter: :active_storage,
      blob_id: document.pdf.blob.id,
      key: document.pdf.blob.key,
      filename: "invoice.pdf",
      byte_size: "%PDF-1.4 fake bytes".bytesize
    )
  end

  it "dispatches through HtmlToPdf::Storage.store(adapter: :active_storage, ...)" do
    document = Document.create!

    HtmlToPdf::Storage.store("%PDF-bytes", adapter: :active_storage, record: document, attachment: :pdf)

    expect(document.reload.pdf).to be_attached
  end

  it "raises a clear LoadError if ActiveStorage isn't defined" do
    hide_const("ActiveStorage")

    expect { described_class.new(record: Document.new, attachment: :pdf).store("x") }
      .to raise_error(LoadError, /ActiveStorage isn't loaded/)
  end
end
