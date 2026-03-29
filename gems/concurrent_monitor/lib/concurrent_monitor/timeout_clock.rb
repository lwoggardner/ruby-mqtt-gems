# frozen_string_literal: true

module ConcurrentMonitor
  # The timeout clock tracks monotonic time for the completion of an event
  #
  # Inspired by Async::Clock
  class TimeoutClock
    # A module for creating and waiting with TimeoutClock
    module Mixin
      # @return [Numeric] current monotonic time
      def now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end

      # Create and start a new TimeoutClock
      def timeout(timeout)
        return NIL_TIMEOUT_CLOCK unless timeout
        return timeout if timeout.is_a?(TimeoutClock)

        TimeoutClock.new(timeout).tap(&:start!)
      end

      # Create a TimeoutClock and wait until block is true. See {#wait_until}
      # @example
      #   TimeoutClock.wait_until(60) { closed? || (sleep(1) && false)}
      def wait_until(timeout_arg = nil, timeout: timeout_arg, delay: nil, exception: nil, &)
        timeout(timeout).wait_until(exception:, delay:, &)
      end

      # Create a TimeoutClock and wait while block is true. See {#wait_while}
      def wait_while(timeout_arg = nil, timeout: timeout_arg, delay: nil, exception: nil, &)
        timeout(timeout).wait_while(exception:, delay:, &)
      end
    end

    extend Mixin

    # @param [Numeric] duration the duration in seconds before timeout.
    def initialize(duration)
      @timeout = duration
    end

    # Start the timeout
    def start!
      @start = TimeoutClock.now if @timeout
    end

    # @return [Numeric] remaining duration before timeout
    def remaining
      return nil unless @timeout

      @timeout - duration
    end

    # @return [Boolean] true if the timeout has expired
    # @yield(remaining)
    #   if block provided and not yet expired
    # @yieldparam [Numeric] remaining
    # @yieldreturn [void]
    def expired?
      return true if (rem = remaining)&.negative?

      yield rem if block_given?
      false
    end

    # @return [Numeric] time in seconds since {#start!}
    def duration
      @start ? TimeoutClock.now - @start : 0
    end

    # Repeatedly call block, passing remaining duration, until it returns truthy or the timeout is expired
    # @param [Class] exception to raise on timeout
    # @param [Numeric] delay duration in seconds to sleep between calls to block
    # @yield[remaining]
    # @yieldparam [Numeric] remaining the remaining time in the timeout
    # @yieldreturn [Boolean] something truthy to indicate the wait is over
    # @return [Object]
    #   the truthy value of the block, or false if the timeout was expired and no exception class was provided
    # @raise [StandardError]
    #    an instance of the exception class if the timeout expires before the block returns a truthy value
    def wait_until(exception: nil, delay: nil)
      loop do
        next unless expired? do |remaining|
          if (result = yield remaining)
            return result
          end

          sleep([delay, self.remaining || delay].min) if delay
        end

        raise exception, 'timed out' if exception

        return false
      end
    end

    # Wait while block is truthy
    # @param [StandardError] exception
    # @yield(remaining)
    # @yieldparam [Numeric] remaining the remaining time in the timeout
    # @yieldreturn [Boolean] true if waiting should continue
    # @return [void]
    # @raise [StandardError]
    def wait_while(delay: nil, exception: nil)
      wait_until(exception:, delay:) { |remaining| !yield remaining }
    end
  end

  NIL_TIMEOUT_CLOCK = TimeoutClock.new(nil)
end
