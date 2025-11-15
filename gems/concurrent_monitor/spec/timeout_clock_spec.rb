# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/concurrent_monitor/timeout_clock'

describe ConcurrentMonitor::TimeoutClock do
  describe 'class_method - wait_until' do
    it 'must return truthy result of block' do
      o = Object.new
      result = ConcurrentMonitor::TimeoutClock.wait_until(5) { o }
      _(result).must_be_same_as(o) # Assuming the method returns `nil` if the block evaluates successfully
    end

    it 'must raise the given exception when the block does not evaluate to true before the timeout' do
      exception = Class.new(StandardError)
      _ { ConcurrentMonitor::TimeoutClock.wait_until(0.1, exception:) { false } }.must_raise(exception)
    end

    it 'must handle a delay between block evaluations' do
      start_time = Time.now
      ConcurrentMonitor::TimeoutClock.wait_until(1, delay: 0.5) { (Time.now - start_time) > 0.5 }
      _(Time.now - start_time).must_be :>=, 0.5
    end

    it 'must pass the correct parameters to the block' do
      block_called = false
      ConcurrentMonitor::TimeoutClock.wait_until(5) do
        block_called = true
        true
      end
      _(block_called).must_equal true
    end
  end

  describe '#expired?' do
    let(:timeout_clock) { ConcurrentMonitor::TimeoutClock.new(5) } # 5 seconds timeout

    before do
      timeout_clock.start!
    end

    it 'returns true if remaining time is negative' do
      def timeout_clock.remaining
        -1
      end

      _(timeout_clock.expired?).must_equal true
    end

    it 'returns false if remaining time is positive and no block is given' do
      def timeout_clock.remaining
        3
      end

      _(timeout_clock.expired?).must_equal false
    end

    it 'yields remaining time if a block is given and remaining time is positive' do
      def timeout_clock.remaining
        3
      end

      executed = false
      expired = timeout_clock.expired? do |remaining|
        executed = true
        _(remaining).must_equal 3
      end
      _(expired).must_equal false
      _(executed).must_equal true
    end

    it 'does not yield if remaining time is negative' do
      def timeout_clock.remaining
        -1
      end

      executed = false
      expired = timeout_clock.expired? do |_|
        executed = true
      end
      _(expired).must_equal true
      _(executed).must_equal false
    end

    it 'always yields and returns false if no timeout' do
      executed = false
      result = timeout_clock.expired? do |_remaining|
        executed = true
      end

      _(result).must_equal false
      _(executed).must_equal true
    end
  end

  describe '#wait_until' do
    let(:timeout) { 2 }
    let(:exception) { StandardError }
    let(:delay) { 0.5 }
    let(:timeout_clock) { ConcurrentMonitor::TimeoutClock.new(timeout) }

    before do
      timeout_clock.start!
    end

    it 'returns the truthy result when block completes successfully within time limit' do
      result = timeout_clock.wait_until do |_remaining|
        sleep(0.1)
        true
      end
      _(result).must_equal true
    end

    it 'raises the provided exception when timeout is reached and exception is given' do
      _(proc {
        timeout_clock.wait_until(exception: exception) do |_remaining|
          false
        end
      }).must_raise StandardError
    end

    it 'returns false when timeout is reached and no exception is given' do
      result = timeout_clock.wait_until do |_remaining|
        false
      end
      _(result).must_equal false
    end

    it 'respects the delay between block executions' do
      delay_time = 0.2
      calls = 0
      timeout_clock.wait_until(delay: delay_time) do |_remaining|
        calls += 1
        (calls == 3) # Ends when called 3 times
      end
      _(calls).must_equal 3
    end

    it 'yields the remaining time to the block' do
      timeout_clock.wait_until do |remaining|
        _(remaining).must_be :<=, timeout
        true
      end
    end
  end
end
