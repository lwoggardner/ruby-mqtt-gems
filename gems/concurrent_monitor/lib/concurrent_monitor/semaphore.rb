# frozen_string_literal: true

module ConcurrentMonitor
  # Limits the number of concurrently running tasks started with this Semaphore
  # @example with Barrier, with early exit
  # Barrier.wait!(monitor) do |barrier
  #   # Start a task to feed 100 tasks into the barrier 5 at a time
  #   Semaphore.new(barrier, 5).async_tasks do |semaphore|
  #     100.times { |i| semaphore.async { start_job(i) } }
  #   end
  #   # Wait! here for the all the tasks, including the feeder, to finish.
  #   #  but if any one of them fails, all currently running tasks AND the feeder will be stopped
  # end
  class Semaphore
    # Create a semaphore, load it up with tasks, and then wait for those tasks to finish
    def self.wait(monitor:, limit:, &)
      new(monitor:, limit:).wait(&)
    end

    # @param [Mixin|Barrier] monitor the monitor for starting async tasks.
    def initialize(monitor:, limit:)
      @monitor = monitor
      @limit = limit
      @condition = monitor.new_condition
      @task_count = 0
    end

    # Run an async task, to feed other tasks - eg into a barrier
    #
    # @return [Task] a task executing block (which is expected to call #{async} to feed tasks )
    # @note this task counts against the semaphore limit
    def async_tasks(&block)
      async do |task|
        block.call(self)
        task.stop
      end
    end

    # Start a task, blocking until the semaphore can be acquired
    def async(name_arg = nil, name: name_arg, report_on_exception: true, &)
      synchronize do
        @condition.wait_while { @task_count >= @limit }
        @task_count += 1
      end

      monitor.async(name, report_on_exception:) { |t| run_task(t, &) }
    end

    # Wait until all tasks are finished (without understanding anything about their results)
    #
    # If a block is given it is sent to {#async_tasks} before waiting
    # @return [self]
    # @see Barrier
    def wait(timeout = nil, **wait_opts, &block)
      async_tasks(&block) if block
      synchronize { @condition.wait_while(timeout, **wait_opts) { @task_count.positive? } }
      self
    end

    def synchronize(&)
      monitor.synchronize(&)
    end

    attr_reader :task_count, :limit

    private

    attr_reader :monitor, :condition

    def run_task(task, &block)
      block.call(task)
    ensure
      synchronize do
        @task_count -= 1
        @condition.signal
      end
    end
  end
end
