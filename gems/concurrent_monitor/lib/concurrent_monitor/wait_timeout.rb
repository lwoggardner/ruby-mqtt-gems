# frozen_string_literal: true

require_relative 'timeout_clock'

module ConcurrentMonitor
  # Extends anything with a 'wait(timeout=nil)' method with wait_while and wait_until
  module WaitTimeout
    # Repeatedly call wait(timeout) until the condition is true or the timeout duration is expired
    # @param [TimeoutClock|Integer|nil] timeout
    #   duration in seconds to wait on the condition before timeout or nil to wait forever
    # @param [Exception|nil] exception an exception to raise on timeout
    # @return [Object] the truthy return value of the block
    # @return [nil] if a timeout occurs
    def wait_until(timeout = nil, exception: nil)
      TimeoutClock.wait_until(timeout, exception:) { |remaining| yield || (wait(remaining) && false) }
    end

    # @return [void] - always falsey
    # @see wait_until
    def wait_while(*, **)
      wait_until(*, **) { !yield }
    end
  end
end
