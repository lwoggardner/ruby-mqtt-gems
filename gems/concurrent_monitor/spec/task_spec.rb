# frozen_string_literal: true

require_relative 'monitor_helper'

module ConcurrentMonitor
  module MonitorSpec
    def self.included(_spec)
      describe ConcurrentMonitor::Task do
        describe '#value' do
          it 'returns the result of immediate task' do
            sync do
              _(async { 1 }.value).must_equal 1
            end
          end

          it 'returns the result of a delayed task' do
            sync { _(async { sleep(0.1) && 'x' }.value).must_equal 'x' }
          end

          it 'raises the exception of immediate task' do
            sync do
              task = async(report_on_exception: false) { raise 'oops' }

              _(-> { task.value }).must_raise('oops')
            end
          end

          it 'raises the exception of delayed task' do
            sync do
              task = async(report_on_exception: false) do
                sleep(0.1)
                raise 'oops'
              end

              _(-> { task.value }).must_raise('oops')
            end
          end
        end

        %i[wait join].each do |method|
          describe "##{method}" do
            it 'waits and returns self' do
              sync do
                result = nil
                task = async(:join_test) do |task|
                  result = :started
                  _(task.current?).must_equal(true)
                  sleep(0.2)
                  _(current_task).must_equal(task)
                  result = :done
                end
                sleep(0.05)
                _(result).must_equal :started
                _(task.public_send(method)).must_equal task
                _(result).must_equal :done
              end
            end

            it 'raises exception of the task' do
              sync do
                task = async(report_on_exception: false) do
                  sleep(0.1)
                  raise 'oops'
                end

                _(-> { task.public_send(method) }).must_raise('oops')
              end
            end
          end
        end

        describe '#stop' do
          it 'stops the task' do
            sync do
              result = nil
              task = async do
                result = :started
                sleep 10
                result = :done
              end
              sleep(0.05)
              task.stop
              _(task.value).must_be_nil
              _(task.stopped?).must_equal(true)
              _(result).must_equal(:started)
              task.stop
            end
          end

          it 'can stop the current task' do
            sync do
              task = async do |task|
                sleep(0.05)
                task.stop
              end
              _(task.stopped?).must_equal(false) # not stopped? until value called
              _(task.value).must_be_nil
              _(task.join).must_equal(task)
              _(task.stopped?).must_equal(true)
            end
          end

          it 'does not fail if task is already complete' do
            sync do
              task = async do
                sleep(0.05)
                :done
              end
              sleep(0.2)
              _(task.value).must_equal :done
              task.stop
              _(task.value).must_equal :done
              task.stop # again...
              _(task.stopped?).must_equal(false)
            end
          end

          it 'does not fail if task raised exception' do
            sync do
              task = async(report_on_exception: false) do
                sleep(0.05)
                raise 'oops'
              end
              _(-> { task.join }).must_raise('oops')
              task.stop
              _(-> { task.join }).must_raise('oops')
              task.stop # again...
              _(task.stopped?).must_equal(false)
            end
          end
        end
      end
    end
  end
end

test_with_monitors(ConcurrentMonitor::MonitorSpec)
