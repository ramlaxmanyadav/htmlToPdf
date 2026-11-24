module HtmlToPdf
  class JobStatus
    # Default HtmlToPdf.configuration.job_status_store. Persists each job's
    # state under a namespaced Rails.cache key, so a web process can read
    # what a Sidekiq/Solid Queue worker process wrote.
    #
    # Rails.cache is zero-setup (every Rails app has one — :memory_store in
    # development), but that's also its caveat: :memory_store and
    # :file_store are per-process, so a web process will never see a status
    # a *different* worker process wrote with either of those. Production
    # needs a shared store (Redis, Solid Cache, Memcached) for job status to
    # actually be visible across processes — see docs/background-jobs.md.
    class CacheStore
      KEY_PREFIX = "htmlToPdf:job_status:".freeze

      def read(job_id)
        Rails.cache.read(key_for(job_id))
      end

      def write(job_id, attrs)
        Rails.cache.write(key_for(job_id), attrs, expires_in: HtmlToPdf.configuration.job_status_ttl)
      end

      private

      def key_for(job_id)
        "#{KEY_PREFIX}#{job_id}"
      end
    end
  end
end
