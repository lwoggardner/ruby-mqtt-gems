# frozen_string_literal: true

require 'async'
require_relative '../concurrent_monitor'

Fiber.attr_accessor :concurrent_monitor_task

module Async
  # Implements the ConcurrentMonitor interface using Async::Tasks
  class Monitor
    # Common task interface over Async::Task
    class Task < ConcurrentMonitor::Task
      def initialize(name_arg = nil, name: name_arg, report_on_exception: true, &block)
        super()
        Async(annotation: name, finished: report_on_exception ? nil : false) do |task|
          @task = task
          Fiber.current.concurrent_monitor_task = self
          block.call(self)
        end
      end

      def alive? = @task.alive?

      def current? = @task.current?

      def value = @task.wait

      def stop
        raise Async::Stop if current?

        # defer stop (need to call value before stopped?) and don't stop if we are already stopped
        # (since this will change the status to :stopped)
        @task.stop(true) unless @task.finished?
        self
      end

      def stopped?
        @task.stopped?
      end

      def to_s = @task.to_s

      def inspect = @task.inspect
    end

    # Functions
    module Functions
      # @return Async::Task
      def async(...)
        Task.new(...)
      end

      # Execute a block, wrapped in a Reactor if this fiber is not already in one
      def sync(name = nil, &)
        Sync(annotation: name, &)
      end

      def current_task
        Fiber.current.concurrent_monitor_task
      end

      def new_monitor
        SINGLETON # there is only one
      end

      # No-op yield.  This is only really a critical section as long as the fiber is not yielded
      def synchronize
        yield
      end

      def task_dump(io = $stderr)
        io.puts "=== Async Task Dump at #{Time.now} ==="
        if Async::Task.current?
          reactor = Async::Task.current.reactor
          reactor.print_hierarchy($stderr)
        else
          io.puts 'No current Async task context'
        end
      end
    end

    # Condition with timeout support
    class ConditionVariable < Async::Condition
      include ConcurrentMonitor::ConditionVariable

      def wait(timeout = nil)
        return super() unless timeout

        # return values match MonitorMixin::ConditionVariable
        Async::Task.current.with_timeout(timeout) do
          super()
        rescue Async::TimeoutError
          nil
        end
      end

      # Note signal is broadcast anyway, so all the waiting fibers are resumed.
      alias broadcast signal
    end

    private_constant :ConditionVariable

    include Functions
    extend Functions

    def new_condition
      ConditionVariable.new
    end

    # @!visibility private
    SINGLETON = new
  end
end
