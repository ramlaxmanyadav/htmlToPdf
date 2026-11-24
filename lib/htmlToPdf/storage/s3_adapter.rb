module HtmlToPdf
  module Storage
    # Direct S3 upload via the AWS SDK, for apps that don't use ActiveStorage
    # at all and just want a plain bucket/key/URL back. htmlToPdf does not
    # depend on aws-sdk-s3 — add `gem "aws-sdk-s3"` to your own Gemfile to
    # use this adapter.
    #
    # bucket/client_options fall back to HtmlToPdf.configuration.s3_bucket/
    # s3_client_options if not given per call. Prefer leaving credentials out
    # of client_options and letting the AWS SDK's default credential chain
    # (an EC2/ECS instance role) resolve them; only pass explicit credentials
    # if an instance role genuinely isn't an option (e.g. a cross-account
    # bucket).
    class S3Adapter
      def initialize(key:, bucket: nil, content_type: "application/pdf", client_options: nil)
        @key = key
        @bucket = bucket || HtmlToPdf.configuration.s3_bucket
        @content_type = content_type
        @client_options = client_options || HtmlToPdf.configuration.s3_client_options || {}

        return if @bucket

        raise ArgumentError,
              "HtmlToPdf::Storage::S3Adapter needs a bucket — pass bucket: or set " \
              "HtmlToPdf.configuration.s3_bucket."
      end

      def store(bytes)
        require_aws_sdk!

        client = Aws::S3::Client.new(**@client_options)
        client.put_object(bucket: @bucket, key: @key, body: bytes, content_type: @content_type)
        url = Aws::S3::Object.new(bucket_name: @bucket, key: @key, client: client).public_url

        { adapter: :s3, bucket: @bucket, key: @key, url: url }
      end

      private

      def require_aws_sdk!
        require "aws-sdk-s3"
      rescue LoadError
        raise LoadError, 'aws-sdk-s3 isn\'t available — add `gem "aws-sdk-s3"` to your Gemfile ' \
                          "to use HtmlToPdf::Storage::S3Adapter."
      end
    end
  end
end
