# frozen_string_literal: true

require_relative 'monitor_helper'

module ConcurrentMonitor
  module QueueTest
    def self.included(spec)
      spec.class_eval do
        describe Queue do
          let(:queue) { new_queue }
          describe 'basic operations' do
            it 'handles producer-consumer pattern' do
              sync do
                results = []

                t1 = async do
                  5.times do |i|
                    queue << "item-#{i}"
                    sleep(rand * 0.05)
                  end
                end

                t2 = async do
                  5.times do
                    item = queue.pop(1.0)
                    results << item if item
                  end
                end

                [t1, t2].each(&:value)

                expect(results.size).must_equal 5
                expect(results).must_equal((0..4).map { |i| "item-#{i}" })
              end
            end

            it 'times out when queue is empty' do
              sync do
                result = queue.pop(0.1)
                expect(result).must_be_nil
              end
            end

            it 'handles multiple producers and consumers' do
              sync do
                results = []
                producer_tasks = []
                consumer_tasks = [] # Multiple producers
                3.times do |producer_id|
                  producer_tasks << async do
                    3.times do |i|
                      queue << "item-#{producer_id}-#{i}"
                      sleep(rand * 0.02)
                    end
                  end
                end

                # Multiple consumers
                3.times do |_consumer_id|
                  consumer_tasks << async do
                    3.times do
                      item = queue.pop(1.0)
                      results << item if item
                    end
                  end
                end

                [producer_tasks, consumer_tasks].flatten.each(&:value)

                expect(results.size).must_equal 9 # 3 producers * 3 items

                # All items should be consumed
                3.times do |producer_id|
                  3.times do |i|
                    expect(results).must_include "item-#{producer_id}-#{i}"
                  end
                end
              end
            end

            it 'supports clear operation' do
              sync do
                5.times { |i| queue << "item-#{i}" }

                expect(queue.size).must_equal 5

                queue.clear

                expect(queue.size).must_equal 0
                expect(queue.empty?).must_equal true
              end
            end
          end
        end
      end
    end
  end
end

test_with_monitors(ConcurrentMonitor::QueueTest)
