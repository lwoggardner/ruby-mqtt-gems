# frozen_string_literal: true

require_relative 'monitor_helper'

module ConcurrentMonitor
  module ConditionVariableTests
    def self.included(spec)
      spec.class_eval do
        describe 'ConditionVariableSpec' do
          let(:condition) { new_condition }
          describe 'basic signaling' do
            it 'receives signals' do
              sync do
                result = nil

                t1 = async('waiter') do
                  result = synchronize do
                    condition.wait
                    Object.new
                  end
                end

                t2 = async('signaler') do
                  sleep 0.1
                  synchronize { condition.signal }
                end

                [t1, t2].each(&:value)

                expect(result).wont_be_nil
              end
            end

            it 'times out when not signaled' do
              result = nil

              sync do
                async('waiter') do
                  result = synchronize do
                    condition.wait(0.1)
                    'x'
                  end
                end.value
              end

              expect(result).must_equal('x')
            end

            it 'broadcasts to all waiters' do
              results = Array.new(5, false)

              sync do
                tasks =
                  5.times.map do |i|
                    async("waiter-#{i}") do
                      synchronize { condition.wait }
                      results[i] = true
                    end
                  end

                async('broadcaster') do
                  sleep 0.5
                  synchronize { condition.broadcast }
                end

                tasks.each(&:value)
              end

              expect(results.all?).must_equal true
            end
          end

          describe 'ConditionVariable with WaitTimeout' do
            it 'handles spurious wakeups with wait_until' do
              sync do
                keep_waiting = false
                wait_complete = false

                t1 = async('signaler') do
                  # Signal the condition multiple times before the value becomes true
                  sleep 0.05
                  synchronize { condition.signal } # First signal - value is still false

                  sleep 0.05
                  synchronize { condition.signal } # Second signal - value still false

                  sleep 0.05
                  keep_waiting = true
                  synchronize { condition.signal } # Third signal - now value is true
                end

                t2 = async('waiter') do
                  # This should wait until value is true, ignoring signals when it's false
                  synchronize { condition.wait_until(1) { keep_waiting } }
                  wait_complete = true if keep_waiting
                end

                [t1, t2].each(&:value)
                expect(keep_waiting).must_equal true
                expect(wait_complete).must_equal true
              end
            end

            it 'handles spurious wakeups with wait_while' do
              sync do
                cond = new_condition
                keep_waiting = true
                wait_complete = false

                t1 = async('signaler') do
                  # Signal multiple times before the condition is met
                  sleep 0.1
                  synchronize { cond.signal } # Signal when we should still wait

                  sleep 0.1
                  keep_waiting = false
                  synchronize { cond.signal } # Signal when we should stop waiting
                end

                t2 = async('waiter') do
                  synchronize do
                    cond.wait_while(1) { keep_waiting }
                  end
                  wait_complete = true unless keep_waiting
                end

                [t1, t2].each(&:value)

                expect(keep_waiting).must_equal false
                expect(wait_complete).must_equal true
              end
            end

            it 'times out properly when condition is never met' do
              sync do
                cond = new_condition
                value = false
                timed_out = false
                start_time = Time.now

                t1 = async('signaler') do
                  # Signal but never set value to true
                  sleep 0.05
                  synchronize { cond.signal }
                  sleep 0.05
                  synchronize { cond.signal }
                end

                t2 = async('waiter') do
                  synchronize do
                    result = cond.wait_until(0.2) { value }
                    timed_out = result.nil? || result == false
                  end
                end

                [t1, t2].each(&:value)

                elapsed = Time.now - start_time
                expect(timed_out).must_equal true
                expect(elapsed).must_be :>=, 0.2
                expect(elapsed).must_be :<, 0.3 # Some leeway for test execution
                expect(value).must_equal false
              end
            end

            it 'handles broadcast with multiple waiters' do
              sync do
                cond = new_condition
                value = false
                counter = 0

                tasks = []

                # Create multiple waiters
                3.times do
                  tasks << async('waiter') do
                    synchronize do
                      cond.wait_until { value }
                      counter += 1
                    end
                  end
                end

                tasks << async('broadcaster') do
                  value = true
                  synchronize { cond.broadcast }
                end

                tasks.each(&:value)

                expect(counter).must_equal 3
                expect(value).must_equal true
              end
            end

            it 'preserves condition when wait_until is interrupted' do
              sync do
                cond = new_condition
                value = false
                wait_count = 0

                t1 = async('interrupter') do
                  # Signal condition before it's true
                  sleep 0.05
                  synchronize { cond.signal }

                  # Then later make it true
                  sleep 0.1
                  value = true
                  synchronize { cond.signal }
                end

                t2 = async('waiter') do
                  synchronize do
                    # The lambda should be called multiple times
                    # First when it's signaled but value is false
                    # Then again when value becomes true
                    cond.wait_until(0.5) do
                      wait_count += 1
                      value
                    end
                  end
                end

                [t1, t2].each(&:value)

                expect(wait_count).must_be :>, 1
                expect(value).must_equal true
              end
            end
          end

          describe 'multiple condition variables' do
            it 'handles multiple condition variables independently' do
              sync do
                cv1 = new_condition
                cv2 = new_condition
                result1 = nil
                result2 = nil

                t1 = async('waiter1') do
                  result1 = synchronize do
                              cv1.wait
                                          :task1
                  end
                end

                t2 = async('waiter2') do
                  result2 = synchronize do
                              cv2.wait
                                          :task2
                  end
                end

                t3 = async('signaler') do
                  sleep 0.1
                  synchronize { cv1.signal }
                  sleep 0.1
                  synchronize { cv2.signal }
                end

                [t1, t2, t3].each(&:value)

                expect(result1).must_equal :task1
                expect(result2).must_equal :task2
              end
            end
          end
        end
      end
    end
  end
end

test_with_monitors(ConcurrentMonitor::ConditionVariableTests)
