require "concurrent/atomic/semaphore"

module HtmlToPdf
  # Bounds how many conversions may run against the shared BrowserPool
  # browser at once. Configured via HtmlToPdf.configuration.max_concurrent_renders
  # (nil, the default, means unbounded — today's exact behavior, no overhead).
  #
  # Exists because BrowserPool is one Chrome process per Ruby process (see
  # docs/architecture.md's scaling note): a web app under normal load rarely
  # needs this, but a Sidekiq/Solid Queue pool with many worker threads all
  # calling HtmlToPdf::GenerateJob at once can otherwise pile an unbounded
  # number of concurrent Page.printToPDF calls onto that one process.
  module ConcurrencyLimiter
    MUTEX = Mutex.new

    module_function

    def around
      limit = HtmlToPdf.configuration.max_concurrent_renders
      return yield unless limit

      semaphore_for(limit).acquire { yield }
    end

    def semaphore_for(limit)
      MUTEX.synchronize do
        @semaphore = Concurrent::Semaphore.new(limit) if @semaphore.nil? || @limit != limit
        @limit = limit
        @semaphore
      end
    end

    def reset!
      MUTEX.synchronize do
        @semaphore = nil
        @limit = nil
      end
    end
  end
end
