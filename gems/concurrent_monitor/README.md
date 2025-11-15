Concurrent Monitor
-------------------

A unified abstraction layer for synchronization and concurrency primitives that works
consistently across both Thread and Fiber-based concurrency models.

Libraries can program against this common interface, allowing users to choose
their preferred concurrency model (Threads or Fibers) at runtime without code changes.

### Features

* {ConcurrentMonitor::Task} - asynchronous execution
* {ConcurrentMonitor::#synchronize} - synchronization of critical sections
* {ConcurrentMonitor::ConditionVariable} - synchronization point (wait & signal)
* {ConcurrentMonitor::Future} - passively fulfilled future value (or error)
* {ConcurrentMonitor::Queue} - thread safe list
* {ConcurrentMonitor::Barrier} - task co-ordination
* {ConcurrentMonitor::Semaphore} - limit concurrent tasks
* {ConcurrentMonitor::TimeoutClock} - timeout utilities (eg wait_until/wait_while)

Concrete implementations

* {Thread::Monitor} runs tasks in a ruby `Thread`, based on standard library gem 'monitor'
* {Async::Monitor} runs tasks in a ruby `Fiber` via  `Async::Task` from gem `async'

### Usage

```ruby
require 'concurrent_monitor'

class MyApp
  include ConcurrentMonitor
  
  def initialize(monitor:)
    self.monitor = monitor.new_monitor
    @queue = new_queue
    @condition = new_condition
  end
  
  def run_jobs(jobs)
    job_results = with_barrier do |barrier| 
      jobs.each { |j| barrier.async { start_job(j) }}
      b.to_a # collect results of jobs
    end
  end
end

# async usage
app = MyApp.new(monitor: ConcurrentMonitor.async_monitor)

# thread based usage
app = MyApp.new(monitor: ConcurrentMoniotr.thread_monitor)
```