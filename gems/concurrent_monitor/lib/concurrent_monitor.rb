# frozen_string_literal: true

require_relative 'concurrent_monitor/timeout_clock'
require_relative 'concurrent_monitor/task'
require_relative 'concurrent_monitor/condition_variable'
require_relative 'concurrent_monitor/queue'
require_relative 'concurrent_monitor/barrier'
require_relative 'concurrent_monitor/future'
require_relative 'concurrent_monitor/timeout_watcher'
require 'forwardable'

# A unified abstraction layer for synchronization and concurrency primitives that works
# consistently across both Thread and Fiber-based concurrency models.
# @example Class usage
#   require 'concurrent_monitor'
#   class MyConcurrentResource
#     include ConcurrentMonitor
#
#     def initialize(monitor:)
#       self.monitor = monitor.new_monitor
#     end
#   end
# @example Async (Fiber-based) usage
#   require 'async/monitor'
#   resource = MyConcurrentResource.new(monitor: ConcurrentMonitor.async_monitor)
# @example Threaded usage
#   require 'thread/monitor'
#   resource = MyConcurrentResource.new(monitor: ConcurrentMonitor.thread_monitor)
module ConcurrentMonitor
  class << self
    def async_monitor
      require 'async/monitor'
      Async::Monitor
    end

    def thread_monitor
      require 'thread/monitor'
      Thread::Monitor
    end
  end

  # Include general wait_until, wait_while
  include TimeoutClock::Mixin

  extend Forwardable

  # @!attribute [rw] monitor
  #   @return [Async::Monitor,Thread::Monitor] should be set to an instance of Async::Monitor or Thread::Monitor
  def_delegators :@monitor, :sync, :async, :current_task, :synchronize, :new_condition, :new_monitor, :task_dump

  # @!method new_monitor
  #   @return [Async::Monitor|Thread::Monitor] a new monitor of the same kind as the current one

  # @!method async(name = nil, report_on_exception: true, &block)
  # Run a task asynchronously
  # @return [Task]

  # @!method sync(name = nil, &block)
  # Run a task immediately, starting a reactor if necessary
  # @return [Object] the result of the block

  # @!method current_task
  # @return [Task] The current task which can be compared against other tasks

  # @!method task_dump(io=$stderr)
  # Dumps a list of running tasks, with backtrace, to the supplied IO
  # @return [void]

  # @!method synchronize(&block)
  # Execute block as a (potentially re-entrant) critical section within this monitor
  #
  # Synchronisation principles:
  #   1. Critical sections should be kept brief and focused on manipulating shared state.
  #   2. Only yield control using monitor based primitives such as ConditionVariable / Queue
  #   2. Always recheck state when resuming after potentially yielding control
  #
  # @note Async::Monitor#synchronize does not provide true mutual exclusion. However,
  #       Code proven to be thread-safe under Thread::Monitor will also be safe for use with Async::Monitor.

  # @!method new_condition
  # @return [ConditionVariable]

  # Run a task with a timeout
  # @param [Numeric|TimeoutClock] timeout
  # @param [Class|StandardError|nil] exception if set the error to raise on timeout
  # @return [Object] task result, nil if timed out without exception
  def with_timeout(timeout_arg, timeout: timeout_arg, exception: nil, condition: new_condition, **kw_async, &block)
    done = false
    task = async(**kw_async) do |t|
      block.call(t)
    ensure
      synchronize do
        done = true
        condition.broadcast
      end
    end

    begin
      synchronize { condition.wait_until(timeout:, exception:) { done } }
    ensure
      task.stop
    end

    task.value
  end

  # @return [Queue] a new queue synchronized on this monitor
  def new_queue(monitor: self)
    Queue.new(monitor:)
  end

  # Creates a new task barrier
  # @return [Barrier]
  def new_barrier(monitor: self)
    Barrier.new(monitor:)
  end

  # @see Barrier#wait!
  def with_barrier(monitor: self, &)
    Barrier.wait!(monitor:, &)
  end

  def new_future(monitor: self)
    Future.new(monitor:)
  end

  def new_semaphore(limit:, monitor: self)
    Semaphore.new(monitor:, limit:)
  end

  # Creates a new timeout watcher
  # @return [TimeoutWatcher]
  def new_timeout_watcher(monitor: self)
    TimeoutWatcher.new(monitor:)
  end

  # @!attribute [rw] monitor
  #   @return [Thread::Monitor|Async::Monitor]
  attr_accessor :monitor
end
