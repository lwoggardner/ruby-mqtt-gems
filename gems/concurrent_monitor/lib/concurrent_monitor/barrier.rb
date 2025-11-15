# frozen_string_literal: true

module ConcurrentMonitor
  # A Barrier/Waiter for joining and/or enumerating a group of tasks
  #
  #  * The iterator methods return lazy enumerators so that results can be processed as tasks complete
  #  * Methods ending in `!` ensure remaining tasks are stopped if enumeration finishes early, e.g. when an exception is
  #    raised.
  class Barrier
    include Enumerable

    # Create a Barrier, yield it to the supplied block then wait for tasks to complete, ensuring
    # remaining tasks are stopped.
    #
    # @return [Object] the result of the block
    # @example just start and wait for tasks
    #   Barrier.wait!(monitor) do |barrier|
    #      jobs.each { |j| barrier.async { j.run } }
    #   end
    # @example enumerate results
    #   Barrier.wait!(monitor) do |barrier|
    #      jobs.each { |j| barrier.async { j.run } }
    #      barrier.to_a
    #   end
    # @example short circuit enumeration with each!
    #  Barrier.wait!(monitor) do |barrier|
    #     jobs.each { |j| barrier.async { j.run } }
    #     # using the each! enumerator ensures the remaining tasks are stopped after the first two results are found
    #     barrier.each!.first(2)
    #  end
    def self.wait!(monitor:, &)
      new(monitor:).wait!(&)
    end

    # @param [Mixin] monitor
    def initialize(monitor:)
      @monitor = monitor
      @queue = monitor.new_queue
      @tasks = Set.new
    end

    # Start a task within the barrier
    # @param [:to_s] name
    # @param [Boolean] report_on_exception
    # @return [Task]
    def async(name = nil, report_on_exception: false, &)
      synchronize { monitor.async(name, report_on_exception:) { |t| run_task(t, &) }.tap { |t| tasks << t } }
    end

    # Yield each task as it completes
    # @return [Enumerator::Lazy] if no block is given?
    # @return [void]
    def each_task
      return enum_for(:each_task).lazy unless block_given?

      while (t = dequeue)
        yield t
      end
    end

    # {#each_task}, ensuring {#stop}
    # @return [Enumerator::Lazy] if no block is given?
    # @return [void]
    def each_task!(&)
      return enum_for(:each_task!).lazy unless block_given?

      ensure_stop { each_task(&) }
    end

    # Yield the value of each task as it completes
    # @return [Enumerator::Lazy] if no block is given
    # @return [void]
    def each
      return enum_for(:each).lazy unless block_given?

      each_task do |t|
        v = t.value
        yield v unless t.stopped?
      end
    end

    # {#each}, ensuring {#stop}
    # @return [Enumerator::Lazy] if no block is given
    # @return [void]
    def each!
      return enum_for(:each!).lazy unless block_given?

      ensure_stop { each(&block) }
    end

    # Optionally yield then wait for tasks
    # @yield[self]
    # @return [Object] result of yield if block is given
    # @return [self] if no block is given
    def wait
      (block_given? ? yield(self) : self).tap { each(&:itself) }
    end

    # {#wait}, ensuring {#stop}
    def wait!(&) = ensure_stop { wait(&) }

    def stop
      current, stopping = synchronize { tasks.partition(&:current?) }
      stopping.each(&:stop)
      current.first&.stop
      self
    end

    def empty?
      synchronize { tasks.empty? && queue.empty? }
    end

    def size
      tasks.size
    end

    def ready
      queue.size
    end

    def synchronize(&) = monitor.synchronize(&)
    def new_condition = monitor.new_condition

    private

    attr_reader :monitor, :queue, :tasks

    def ensure_stop(method = nil)
      yield if block_given?
      send(method) if method
    ensure
      stop
    end

    def run_task(task)
      yield(task)
    ensure
      queue.push(task)
    end

    def dequeue
      synchronize do
        return nil if empty?

        queue.dequeue.tap { |t| tasks.delete(t) if t }
      end
    end
  end
end
