# frozen_string_literal: true

require_relative 'wait_timeout'

module ConcurrentMonitor
  # @abstract
  # Common interface to underlying tasks
  class Task
    # @!method value
    #  Wait for task to complete and return its value
    #  @return [Object]
    #  @raise [StandardError]

    # Wait for task to complete
    # @return [self]
    def wait
      value
      self
    end

    alias join wait

    # @!method stop
    #  @return [self] after stopping
    #  @raise [Exception] if called from the current task

    # @!method stopped?
    #  @return [Boolean] true if the task has completed via stop.

    # @!method alive?
    #  @return [Boolean] true if the task has not reached completion (as seen by the calling task)

    # @!method current?
    #  @return [Boolean] true if this task is the current thread/fiber
  end
end
