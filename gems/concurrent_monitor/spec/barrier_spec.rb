# frozen_string_literal: true

require_relative 'monitor_helper'

module ConcurrentMonitor
  module BarrierSpec
    def self.included(spec)
      spec.class_eval do
        describe Barrier do
          let(:barrier) { new_barrier }

          describe '#async #wait!' do
            it 'succeeds with no tasks' do
              sync do
                _(barrier).must_be(:empty?)
                barrier.wait
                _(barrier).must_be(:empty?)
              ensure
                barrier.stop
              end
            end

            it 'handles tasks that complete immediately' do
              result = []
              sync do
                barrier.async do
                  result << :task_1
                end

                barrier.async do
                  result << :task_2
                end

                barrier.wait
              ensure
                barrier.stop
              end

              _(result).must_equal %i[task_1 task_2]
              _(barrier.empty?).must_equal true
            end

            it 'handles tasks that complete asynchronously' do
              result = []
              sync do
                barrier.async do
                  sleep 0.1
                  result << :task_1
                end

                barrier.async do
                  sleep 0.2
                  result << :task_2
                end

                barrier.wait!
              end

              _(result).must_equal %i[task_1 task_2]
            end

            it 'fails fast on error and stops unfinished tasks' do
              result = []

              sync do
                sleeper = barrier.async { sleep 10 }
                barrier.async { sleep(0.1) && raise('Task error') }
                barrier.async { result << :task1 }
                _(barrier.size).must_equal(3)
                _(-> { barrier.wait! }).must_raise(RuntimeError, 'Task error')
                _(result).must_equal %i[task1]
                _(sleeper.value).must_be_nil
                _(sleeper.stopped?).must_equal true
                _(barrier.empty?).must_equal false # the stopped task is pending
                barrier.wait # should not raise Stopped
                _(barrier.empty?).must_equal true
              end
            end
          end

          describe '#wait' do
            it 'does not stop tasks by default'
          end

          describe '#each_task' do
            it 'yields each task as it completes' do
              sync do |_task|
                result = []
                task2_done = false
                task2_task = barrier.async do
                  sleep(0.2)
                  task2_done = true
                  :task2
                end
                barrier.async { :task3 }
                barrier.async do
                  sleep(0.1)
                  :task1
                end

                barrier.each_task do |t|
                  result << t.value if !task2_done || t.eql?(task2_task)
                end

                _(result).must_equal %i[task3 task1 task2]
              end
            end

            it 'returns an Enumerator::Lazy when no block given' do
              results = []
              sync do |_task|
                with_timeout(5, exception: RuntimeError) do
                  sleeper = barrier.async do
                    sleep(100)
                    :task2
                  end
                  barrier.async { :task3 }
                  barrier.async do
                    sleep(0.1)
                    :task1
                  end

                  _(barrier).wont_be(:empty?)
                  e = barrier.each_task.filter_map { |t| t.value.tap { results << t.value } }
                  _(e).must_be_kind_of Enumerator::Lazy
                  _(e.first(2)).must_equal %i[task3 task1]
                  # pulled the first two values through filter map without waiting for the third
                  _(results).must_equal %i[task3 task1]
                  # sleeper is still running
                  _(sleeper.alive?).must_equal(true)
                  barrier.stop
                  _(sleeper.value || sleeper.stopped?).must_equal(true)
                end
              end
            end

            it 'enumerates all tasks even when new ones are added during enumeration' do
              # Test dynamic task addition during enumeration
              sync do |_task|
                result = []

                # Start initial tasks
                barrier.async { sleep(0.2) && :task2 }
                barrier.async { sleep(0.1) && :task1 }

                # Start enumerating. New tasks will be dynamically added during this process
                barrier.each_task do |t|
                  result << t.value

                  # Dynamically add more tasks during enumeration
                  if result.size == 1
                    barrier.async { :task3 }
                    barrier.async { sleep(0.05) && :task4 }
                  end
                end

                _(result.sort).must_equal %i[task1 task2 task3 task4]
              end
            end

            # Test error propagation
            it 'handles errors within enumerated tasks'
          end

          describe '#each' do
            # Test basic result yielding
            it 'yields the result of each completed task'

            # Test enumerator return
            it 'returns a lazy enumerator when no block given'
          end

          describe 'enumerable' do
            def with_tasks
              sync do |_task|
                sleeper = barrier.async do
                  sleep(0.5)
                  :task2
                end
                barrier.async { :task3 }
                barrier.async do
                  sleep(0.1)
                  :task1
                end

                next if yield barrier

                barrier.stop
                _(sleeper.value).must_be_nil
                _(sleeper.stopped?).must_equal(true)
              end
            end

            it 'returns the first n tasks' do
              with_tasks do |barrier|
                _(barrier.first(2)).must_equal %i[task3 task1]
                false
              end
            end

            it 'returns all the tasks' do
              with_tasks do |barrier|
                _(barrier.to_a).must_equal %i[task3 task1 task2]
                true
              end
            end

            it 'maps the tasks' do
              with_tasks do |barrier|
                _(barrier.map(&:to_s)).must_equal %w[task3 task1 task2]
              end
            end
          end

          describe 'Error handling' do
            # Test exception behavior during each/each_task
            it 'propagates exceptions from tasks during enumeration'

            # Test exception behavior during wait
            it 'propagates exceptions during wait'

            # Test resource cleanup on errors
            it 'cleans up properly when exceptions occur'

            # Test stop behavior on exception
            it 'stops all tasks when an exception occurs and ensure_stop is true'
          end

          describe 'basic operations' do
            it 'synchronizes multiple tasks' do
              sync do
                counter = 0
                with_barrier do |barrier|
                  5.times do |i|
                    barrier.async("worker-#{i}") do
                      sleep(rand * 0.1)
                      counter += 1
                    end
                  end
                end
                expect(counter).must_equal 5
              end
            end

            it 'handles exceptions in tasks' do
              success_count = 0
              error_count = 0
              sync do
                with_barrier do |barrier|
                  barrier.async('successful') do
                    success_count += 1
                  end

                  barrier.async('failing') do
                    raise 'Simulated error'
                  end

                  barrier.async('also-successful') do
                    success_count += 1
                  end
                end
              rescue StandardError
                error_count += 1
              end

              expect(success_count).must_equal 2
              expect(error_count).must_equal 1
            end

            it 'handles nested barriers' do
              outer_count = 0
              inner_count = 0

              sync do
                with_barrier do |outer|
                  outer.async('outer-task') do
                    outer_count += 1

                    with_barrier do |inner|
                      inner.async('inner-task-1') do
                        inner_count += 1
                      end

                      inner.async('inner-task-2') do
                        inner_count += 1
                      end
                    end
                  end
                end
              end
              expect(outer_count).must_equal 1
              expect(inner_count).must_equal 2
            end
          end

          describe 'synchronization' do
            it 'ensures atomic updates' do
              skip 'FiberMonitor does not really do mutual exclusion' if monitor_class == Async::Monitor
              shared_value = 0
              sync do
                with_barrier do |barrier|
                  10.times do
                    barrier.async('incrementer') do
                      100.times do
                        synchronize do
                          temp = shared_value
                          # Simulate some work that could cause race conditions
                          sleep 0.0001
                          shared_value = temp + 1
                        end
                      end
                    end
                  end
                end
              end
              expect(shared_value).must_equal 1000
            end
          end
        end
      end
    end
  end
end

test_with_monitors(ConcurrentMonitor::BarrierSpec)
