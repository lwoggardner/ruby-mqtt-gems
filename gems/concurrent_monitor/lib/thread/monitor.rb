# frozen_string_literal: true

require 'monitor'
require_relative '../concurrent_monitor'

class Thread
  # A concurrent Monitor based for Threads based on MonitorMixin
  # This is the standalone monitor class.
  # @see Monitor::Mixin
  class Monitor
    # rubocop:disable Lint/InheritException

    # Raised from stop when a task is stopped
    class Stop < Exception; end

    # rubocop:enable Lint/InheritException

    # @!visibility private
    class ConditionVariable < MonitorMixin::ConditionVariable
      include ConcurrentMonitor::ConditionVariable
    end

    # @!visibility private
    # Common task interface over Thread
    class Task < ConcurrentMonitor::Task
      def initialize(name_arg = nil, name: name_arg, report_on_exception: true, &block)
        super()
        @stopped = nil

        @thread =
          if block_given?
            Thread.new(self, name, report_on_exception, block) do |t, n, e, b|
              run_thread(t, n, e, &b)
            rescue Stop
              @stopped = true
              nil
            ensure
              @stopped ||= false
            end
          else
            # this is the main thread
            Thread.current.tap { |t| t.thread_variable_set(:concurrent_monitor_task, self) }
          end
      end

      def alive? = @thread.alive?

      def current? = @thread == Thread.current

      def value
        result = @thread.value
        raise ConcurrentMonitor::TaskStopped, 'Task was stopped' if @stopped

        result
      rescue Stop
        @stopped = true
        raise ConcurrentMonitor::TaskStopped, 'Task was stopped'
      end

      def stop
        raise Stop if current?

        @thread.raise(Stop) if @thread.alive?
        self
      rescue ThreadError
        self # race with alive?
      end

      # must call wait before @stopped will be true
      def stopped?
        !!@stopped
      end

      def to_s = @thread.to_s

      def inspect = @thread.inspect

      private

      def run_thread(task, name, report_on_exception)
        Thread.current.tap do |c|
          c.report_on_exception = report_on_exception
          c.name = name.to_s if name
          c.thread_variable_set(:concurrent_monitor_task, task)
        end
        yield task
      end
    end

    # @!visibility private
    # Module functions
    module Functions
      def new_monitor
        Monitor.new
      end

      # @return [Task]
      def async(...)
        start_thread_group
        Task.new(...)
      end

      # Just invokes the block
      def sync(_name = nil, &block)
        start_thread_group
        block.call
      end

      def current_task
        Thread.current.thread_variable_get(:concurrent_monitor_task) || Task.new
      end

      def task_dump(io = $stderr)
        io.puts "=== Thread Dump at #{Time.now} ==="
        # Get the current thread group
        group = Thread.current.group

        if group == ThreadGroup::Default
          io.puts 'Not in a Thread::Monitor group'
        else
          io.puts "Total Threads in #{group}: #{group.list.count}"
          group.list.each do |thread|
            io.puts "\n#{thread}"
            io.puts "→ #{thread.backtrace.join("\n  ")}" if thread.backtrace
          end
        end
      end

      private

      def start_thread_group
        ThreadGroup.new.add(Thread.current) if Thread.current.group == ThreadGroup::Default
      end
    end

    def new_condition
      # We're using the underlying @mon_data variable but giving ourselves
      # the enhanced condition variable, which just saves one level of wrapping
      ConditionVariable.new(@mon_data)
    end

    include MonitorMixin

    include Functions
    extend Functions
  end
end
