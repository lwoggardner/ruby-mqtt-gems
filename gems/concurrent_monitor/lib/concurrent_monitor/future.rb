# frozen_string_literal: true

module ConcurrentMonitor
  # A passive future value
  class Future
    def initialize(monitor:, condition: monitor.new_condition)
      @monitor = monitor
      @condition = condition
      @completed = false
      @value = nil
      @error = nil
    end

    # Blocks until the future is completed or the timeout expires
    # @return [Object] The value with which the future was fulfilled
    # @raise [StandardError] If the future was rejected
    def value
      wait
      raise @error if @error

      @value
    end

    def wait(timeout = nil, **wait_opts)
      synchronize { condition.wait_until(timeout, **wait_opts) { @completed } }
    end

    # Resolve the future with a block
    def resolve
      complete! do
        @value = yield
      rescue StandardError => e
        @error = e
      end
    end

    # Fulfills this future with the given value
    # @param value [Object] The value to fulfill this future with
    # @return [Boolean] true if the future was fulfilled, false if already completed
    def fulfill(value)
      complete! { @value = value }
    end

    # Rejects this future with the given error
    # @param error [Exception] The error to reject this future with
    # @return [Boolean] true if the future was rejected, false if already completed
    def reject(error)
      error = error.new('rejected') if error.is_a?(Class)
      complete! { @error = error }
    end

    # @return [Boolean] true if this future has been completed
    def completed?
      synchronize { @completed }
    end

    # @return [Boolean] true if this future has not yet been completed
    def pending?
      !completed?
    end

    private

    attr_reader :monitor, :condition

    def complete!
      synchronize do
        return false if @completed

        yield
      ensure
        @completed = true
        @condition.broadcast
      end
    end

    def synchronize(&)
      monitor.synchronize(&)
    end
  end
end
