# frozen_string_literal: true

module ConcurrentMonitor
  # Shared timeout watcher that manages timeouts for multiple tasks efficiently.
  # Caller is responsible for starting the watcher task.
  class TimeoutWatcher
    attr_reader :monitor

    include ConcurrentMonitor

    # @param monitor [ConcurrentMonitor::Mixin] the monitor for synchronization
    def initialize(monitor:)
      @monitor = monitor
      @timeouts = {}
      @condition = monitor.new_condition
    end

    # Wrap a block with timeout. Spawns the block in a new task, registers it for timeout,
    # and ensures timeout is cancelled on completion.
    # @param timeout [Numeric] seconds until timeout
    # @yield block to execute
    # @return [Task] the spawned task
    def with_timeout(timeout_arg = nil, timeout: timeout_arg, **, &block)
      async(**async) do |t|
        watch(t, timeout: timeout) if timeout
        block.call(t)
      ensure
        cancel_timeout(t) if timeout
      end
    end

    # Cancel timeout for task
    def cancel_timeout(task = current_task)
      synchronize { @timeouts.delete(task) }
    end

    # Run the watcher loop. Caller should spawn this in a task.
    # @example
    #   watcher = TimeoutWatcher.new(monitor: self)
    #   watcher_task = async(name: 'timeout_watcher') { watcher.run }
    def run
      until @stopped
        synchronize do
          @timeouts.delete_if { |task, clock| clock.expired?.tap { |expired| task.stop if expired } }
          @condition.wait(@timeouts.values.map(&:remaining).compact.min)
        end
      end
    end

    def stop
      synchronize do
        @stopped = true
        @condition.broadcast
      end
    end

    private

    # Register task to be stopped after timeout
    def watch(task, timeout:)
      clock = self.timeout(timeout)

      synchronize do
        @timeouts[task] = clock
        @condition.broadcast
      end
    end
  end
end
