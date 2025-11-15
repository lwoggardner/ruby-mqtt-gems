# frozen_string_literal: true

require_relative 'wait_timeout'

module ConcurrentMonitor
  # Concurrency primitive for waiting on signals with optional timeout
  # @abstract
  # @see ConcurrentMonitor::new_condition
  module ConditionVariable
    include ConcurrentMonitor::WaitTimeout

    # @!method wait(timeout = nil)
    #   Wait for {#broadcast}
    #   @param [Numeric] timeout in seconds
    #   @return [void] always true
    # @note must be called within the {ConcurrentMonitor::Mixin#synchronize} method of this condition's monitor.
    # @note A condition return from at any time, regardless of broadcast or timeout. See {#wait_until}, #{wait_while}

    # @!method broadcast
    #   Signal all waiters
    # @note must be called within the {ConcurrentMonitor::Mixin#synchronize} method of this condition's monitor.

    # @!parse
    #   alias signal broadcast
  end
end
