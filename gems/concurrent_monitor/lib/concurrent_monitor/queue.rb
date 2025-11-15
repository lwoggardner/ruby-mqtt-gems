# frozen_string_literal: true

module ConcurrentMonitor
  # A simple queue with timeout suitable for use with a Monitor
  class Queue
    # @param [ConcurrentMonitor] monitor for this queue
    def initialize(monitor:)
      @items = []
      @monitor = monitor
      @condition = monitor.new_condition
    end

    def push(*items)
      with_items(__method__, *items, signal: true)
    end
    alias enqueue push

    def <<(item)
      with_items(__method__, item, signal: true)
    end

    def unshift(*items)
      with_items(__method__, *items, signal: true)
    end

    def pop(timeout = nil, **wait_opts)
      when_not_empty(__method__, timeout, **wait_opts)
    end

    def shift(timeout = nil, **wait_opts)
      when_not_empty(__method__, timeout, **wait_opts)
    end
    alias dequeue shift

    # For inspection, not synchronised
    def items
      @items.dup
    end

    # For inspection not synchronized!
    def size
      @items.size
    end

    def respond_to_missing?(method_name, include_private = false)
      @items.respond_to?(method_name, false) || super
    end

    # Operates on the underlying Array synchronized by this Queue's monitor
    # @note Accepts a :signal keyword argument to control whether waiters are signaled
    def method_missing(...)
      with_items(...)
    end

    private

    attr_reader :monitor, :condition

    def with_items(method, *, signal: method.end_with?('!'), &)
      monitor.synchronize { @items.public_send(method, *, &).tap { condition.broadcast if signal } }
    end

    def when_not_empty(method, timeout = nil, **wait_opts)
      monitor.synchronize do
        condition.wait_while(timeout, **wait_opts) { @items.empty? } if @items.empty?
        @items.public_send(method)
      end
    end
  end
end
