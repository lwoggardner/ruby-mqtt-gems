# frozen_string_literal: true

require_relative 'wait_timeout'

module ConcurrentMonitor
  # Raised when calling #value on a stopped task
  class TaskStopped < StandardError; end

  # @abstract
  # Common interface to underlying tasks
  class Task
    # @!method value
    #  Wait for task to complete and return its value, or raise its error
    #  @return [Object]
    #  @raise [TaskStopped] if the task was explicitly {#stop stopped} (Thread API)
    #  @raise [StandardError]

    # Wait for task to complete and return its value, or raise its error
    # @return [Object]
    # @return [nil] if the task was explicitly {#stop stopped} (Async::Task API)
    # @raise [StandardError] if task raised an exception
    # @see stopped?
    def wait
      value
    rescue TaskStopped
      nil
    end

    # Wait for task to complete and return self (Thread API)
    # @return [self]
    # @raise [TaskStopped] if task was stopped
    # @raise [StandardError] if task raised an exception
    def join
      value
      self
    end

    # @!method stop
    #  @return [self] after stopping
    #  @raise [Exception] if called from the current task

    # @!method stopped?
    #  Check if task was stopped.
    #
    #  A false result is ambiguous unless the calling task has called {#wait} (or rescued {TaskStopped} from a call to
    #  {#value}/{#join})
    #  @return [Boolean] true if the task has completed via stop.

    # @!method alive?
    #  A true result is ambiguous unless the calling task has called {#wait} (or rescued {TaskStopped} from a call to
    #  {#value}/{#join})
    #  @return [Boolean] true if the task has not reached completion

    # @!method current?
    #  @return [Boolean] true if this task is the current thread/fiber
  end
end
