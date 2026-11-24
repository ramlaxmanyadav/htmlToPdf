require "spec_helper"

RSpec.describe HtmlToPdf::ConcurrencyLimiter do
  after { described_class.reset! }

  describe ".around" do
    it "yields directly, with no limiting, when max_concurrent_renders is unset (default)" do
      expect(HtmlToPdf.configuration.max_concurrent_renders).to be_nil

      result = described_class.around { :done }

      expect(result).to eq(:done)
    end

    it "lets up to max_concurrent_renders callers run at once" do
      HtmlToPdf.configure { |c| c.max_concurrent_renders = 2 }
      started = Queue.new
      release = Queue.new

      threads = Array.new(2) do
        Thread.new do
          described_class.around do
            started << :started
            release.pop
          end
        end
      end

      2.times { started.pop }
      expect(threads.all?(&:alive?)).to be true
    ensure
      2.times { release << :go }
      threads&.each(&:join)
    end

    it "blocks a caller beyond the limit until a permit is released" do
      HtmlToPdf.configure { |c| c.max_concurrent_renders = 1 }
      holding = Queue.new
      release = Queue.new
      second_call_started = false

      first = Thread.new do
        described_class.around do
          holding << :holding
          release.pop
        end
      end
      holding.pop

      second = Thread.new do
        described_class.around { second_call_started = true }
      end

      sleep 0.05
      expect(second_call_started).to be false

      release << :go
      first.join
      second.join

      expect(second_call_started).to be true
    end

    it "releases the permit even if the block raises" do
      HtmlToPdf.configure { |c| c.max_concurrent_renders = 1 }

      expect { described_class.around { raise "boom" } }.to raise_error("boom")

      # If the permit weren't released, this would hang — RSpec's own
      # default timeout would fail the example rather than wedge the suite.
      expect(described_class.around { :ok }).to eq(:ok)
    end

    it "resizes the semaphore when max_concurrent_renders changes" do
      HtmlToPdf.configure { |c| c.max_concurrent_renders = 1 }
      described_class.around { nil }

      HtmlToPdf.configure { |c| c.max_concurrent_renders = 5 }

      expect(described_class.semaphore_for(5).available_permits).to eq(5)
    end
  end
end
