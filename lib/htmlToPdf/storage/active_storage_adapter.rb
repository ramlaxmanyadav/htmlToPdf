require "stringio"

module HtmlToPdf
  module Storage
    # Attaches the rendered PDF to an ActiveRecord record via ActiveStorage
    # — `record.public_send(attachment)` must be a has_one_attached/
    # has_many_attached association. Uses whatever service config/storage.yml
    # already points the app at (disk, S3, GCS, ...); for direct S3 upload
    # without ActiveStorage's blob/attachment bookkeeping, see S3Adapter.
    class ActiveStorageAdapter
      def initialize(record:, attachment:, filename: "document.pdf", content_type: "application/pdf")
        @record = record
        @attachment = attachment
        @filename = filename
        @content_type = content_type
      end

      def store(bytes)
        unless defined?(ActiveStorage)
          raise LoadError,
                "ActiveStorage isn't loaded. If this app was generated with " \
                "--skip-active-storage, either undo that or use " \
                "HtmlToPdf::Storage::S3Adapter (adapter: :s3) instead."
        end

        attachable = @record.public_send(@attachment)
        attachable.attach(io: StringIO.new(bytes), filename: @filename, content_type: @content_type)
        blob = attachable.blob

        { adapter: :active_storage, blob_id: blob.id, key: blob.key,
          filename: blob.filename.to_s, byte_size: blob.byte_size }
      end
    end
  end
end
