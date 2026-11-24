module HtmlToPdf
  # Dispatches HtmlToPdf::Storage.store(bytes, adapter: ..., **opts) to a
  # registered storage adapter. Ships with :active_storage and :s3 (see
  # storage/active_storage_adapter.rb and storage/s3_adapter.rb); register
  # your own with HtmlToPdf::Storage.register(:my_adapter, MyAdapterClass).
  #
  # An adapter is any class whose #initialize takes the **opts passed to
  # .store (minus :adapter itself) and whose #store(pdf_bytes) returns a
  # plain, ActiveJob-serializable Hash describing where the PDF ended up —
  # that return value becomes HtmlToPdf::JobStatus#result for a background
  # job, so avoid returning live objects (an ActiveStorage::Blob, an
  # Aws::S3::Object) that may not survive round-tripping through the job
  # status store.
  module Storage
    class UnknownAdapterError < StandardError; end

    ADAPTERS = {}

    module_function

    def register(name, klass)
      ADAPTERS[name.to_sym] = klass
    end

    def store(bytes, adapter:, **options)
      klass = ADAPTERS.fetch(adapter.to_sym) do
        raise UnknownAdapterError,
              "Unknown HtmlToPdf storage adapter: #{adapter.inspect} " \
              "(registered: #{ADAPTERS.keys.join(', ')})"
      end

      klass.new(**options).store(bytes)
    end
  end
end

require "htmlToPdf/storage/active_storage_adapter"
require "htmlToPdf/storage/s3_adapter"

HtmlToPdf::Storage.register(:active_storage, HtmlToPdf::Storage::ActiveStorageAdapter)
HtmlToPdf::Storage.register(:s3, HtmlToPdf::Storage::S3Adapter)
