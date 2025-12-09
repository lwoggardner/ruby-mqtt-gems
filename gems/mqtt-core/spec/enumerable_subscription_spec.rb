# frozen_string_literal: true

require_relative '../../../spec/spec_helper'
require 'mqtt/core/packet/publish'
require 'mqtt/core/client/enumerable_subscription'

describe 'MQTT::Core::Client::EnumerableSubscription' do
  let(:queue) do
    Class.new do
      def initialize
        @items = []
      end
      def push(item)
        @items << item
      end
      alias enqueue push
      def dequeue
        @items.shift
      end
    end.new
  end

  let(:mock_client) do
    Class.new do
      attr_reader :handled_calls, :deleted_subs
      def initialize
        @handled_calls = []
        @deleted_subs = []
      end
      def handled!(packet)
        @handled_calls << packet if packet&.qos&.positive?
      end
      def delete_subscription(sub, **opts)
        @deleted_subs << [sub, opts]
      end
      def async(name)
        self
      end
    end.new
  end

  let(:mock_publish) do
    Class.new do
      attr_reader :topic, :payload, :qos
      def initialize(topic:, payload:, qos: 0)
        @topic = @topic_name = topic
        @payload = payload
        @qos = qos
      end
      def to_h
        { topic: @topic, payload: @payload, qos: @qos }
      end
      include MQTT::Core::Packet::Publish
    end
  end

  let(:mock_sub_packet) do
    Struct.new(:x) do
      def unsubscribe_params(ack)
        {}
      end
    end.new(1)
  end

  let(:subscription) do
    MQTT::Core::Client::EnumerableSubscription.new(
      sub_packet: mock_sub_packet,
      ack_packet: nil,
      handler: queue,
      client: mock_client
    )
  end

  describe '#get_packet' do
    it 'gets one packet' do
      pub = mock_publish.new(topic: 'test', payload: 'hello')
      queue.push(pub)
      _(subscription.get_packet).must_equal(pub)
    end

    it 'returns nil when closed' do
      queue.push(nil)
      _(subscription.get_packet).must_be_nil
    end
  end

  describe '#get' do
    it 'gets one message' do
      pub = mock_publish.new(topic: 'test/a', payload: 'world')
      queue.push(pub)
      topic, payload, attrs = subscription.get
      _(topic).must_equal('test/a')
      _(payload).must_equal('world')
      _(attrs[:qos]).must_equal(0)
    end

    it 'returns nil when closed' do
      queue.push(nil)
      result = subscription.get_packet
      _(result).must_be_nil
    end
  end

  describe '#read_packet' do
    it 'reads one packet' do
      pub = mock_publish.new(topic: 'test', payload: 'data')
      queue.push(pub)
      _(subscription.read_packet).must_equal(pub)
    end

    it 'raises StopIteration on nil' do
      queue.push(nil)
      _ { subscription.read_packet }.must_raise(StopIteration)
    end
  end

  describe '#read' do
    it 'reads one message' do
      pub = mock_publish.new(topic: 'test/b', payload: 'content')
      queue.push(pub)
      topic, payload, _attrs = subscription.read
      _(topic).must_equal('test/b')
      _(payload).must_equal('content')
    end

    it 'raises StopIteration on nil' do
      queue.push(nil)
      _ { subscription.read }.must_raise(StopIteration)
    end
  end

  describe '#each_packet' do
    it 'enumerates packets' do
      3.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      queue.push(nil)

      results = []
      subscription.each_packet { |p| break unless p; results << p }
      _(results.size).must_equal(3)
      _(results.first).must_be_kind_of(mock_publish)
    end

    it 'returns regular enumerator without block' do
      _(subscription.each_packet).must_be_kind_of(Enumerator)
      _(subscription.each_packet).wont_be_kind_of(Enumerator::Lazy)
    end
  end

  describe '#each' do
    it 'enumerates messages' do
      3.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      queue.push(nil)

      results = []
      subscription.each { |t, p| break unless t; results << [t, p] }
      _(results.size).must_equal(3)
      _(results.first[0]).must_equal('t0')
      _(results.first[1]).must_equal('p0')
    end

    it 'returns regular enumerator without block' do
      _(subscription.each).must_be_kind_of(Enumerator)
      _(subscription.each).wont_be_kind_of(Enumerator::Lazy)
    end
  end

  describe 'Enumerable methods' do
    it 'takes limited messages' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      results = subscription.take(3)
      _(results.size).must_equal(3)
      _(results).must_be_kind_of(Array)
    end

    it 'gets first message' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      result = subscription.first
      _(result[0]).must_equal('t0')
      _(result).must_be_kind_of(Array)
    end

    it 'maps messages' do
      3.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      queue.push(nil)

      results = []
      subscription.map { |_t, p| p.to_i }.each { |n| break unless n; results << n }
      _(results).must_equal([0, 1, 2])
    end
  end

  describe '#lazy' do
    it 'returns lazy enumerator' do
      _(subscription.lazy).must_be_kind_of(Enumerator::Lazy)
    end

    it 'supports lazy chaining' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      results = subscription.lazy.select { |_t, p| p.to_i.even? }.map { |_t, p| p.to_i }.take(2)
      _(results).must_be_kind_of(Enumerator::Lazy)
      _(results.to_a).must_equal([0, 2])
    end
  end

  describe '#lazy!' do
    it 'returns lazy enumerator with auto-unsubscribe' do
      _(subscription.lazy!).must_be_kind_of(Enumerator::Lazy)
    end

    it 'unsubscribes after lazy chain completes' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      results = subscription.lazy!.select { |_t, p| p.to_i.even? }.take(2).to_a
      _(results.size).must_equal(2)
      _(mock_client.deleted_subs.size).must_equal(1)
    end
  end

  describe '#lazy_packets' do
    it 'returns lazy enumerator' do
      _(subscription.lazy_packets).must_be_kind_of(Enumerator::Lazy)
    end

    it 'supports lazy chaining on packets' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      results = subscription.lazy_packets.select { |p| p.payload.to_i.even? }.take(2)
      _(results).must_be_kind_of(Enumerator::Lazy)
      _(results.to_a.size).must_equal(2)
    end
  end

  describe '#lazy_packets!' do
    it 'returns lazy enumerator with auto-unsubscribe' do
      _(subscription.lazy_packets!).must_be_kind_of(Enumerator::Lazy)
    end

    it 'unsubscribes after lazy chain completes' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      results = subscription.lazy_packets!.select { |p| p.payload.to_i.even? }.take(2).to_a
      _(results.size).must_equal(2)
      _(mock_client.deleted_subs.size).must_equal(1)
    end
  end

  describe 'aliases' do
    it 'lazy_messages aliases lazy' do
      _(subscription.method(:lazy_messages)).must_equal(subscription.method(:lazy))
    end

    it 'lazy_messages! aliases lazy!' do
      _(subscription.method(:lazy_messages!)).must_equal(subscription.method(:lazy!))
    end
  end

  describe 'bang methods' do
    it 'unsubscribes with each! and block' do
      2.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      queue.push(nil)

      subscription.each! { |t, _| break unless t }
      _(mock_client.deleted_subs.size).must_equal(1)
    end

    it 'unsubscribes with tap!' do
      result = nil
      subscription.tap! { |s| result = s }
      _(result).must_equal(subscription)
      _(mock_client.deleted_subs.size).must_equal(1)
    end

    it 'unsubscribes with with!' do
      result = nil
      subscription.with! { |s| result = s }
      _(result).must_equal(subscription)
      _(mock_client.deleted_subs.size).must_equal(1)
    end

    it 'unsubscribes with first!' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      result = subscription.first!
      _(result[0]).must_equal('t0')
      _(mock_client.deleted_subs.size).must_equal(1)
    end

    it 'unsubscribes with take!' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "p#{i}")) }
      results = subscription.take!(3)
      _(results.size).must_equal(3)
      _(mock_client.deleted_subs.size).must_equal(1)
    end

    it 'unsubscribes with select!' do
      5.times { |i| queue.push(mock_publish.new(topic: "t#{i}", payload: "#{i}")) }
      queue.push(nil)
      results = subscription.select! { |t, p| break [] unless t; p.to_i.even? }
      _(results.size).must_equal(3)
      _(mock_client.deleted_subs.size).must_equal(1)
    end
  end

  describe 'QoS handling' do
    it 'marks qos1 packets as handled' do
      pub = mock_publish.new(topic: 'test', payload: 'data', qos: 1)
      queue.push(pub)
      subscription.get
      _(mock_client.handled_calls).must_include(pub)
    end

    it 'marks qos2 packets as handled' do
      pub = mock_publish.new(topic: 'test', payload: 'data', qos: 2)
      queue.push(pub)
      subscription.get
      _(mock_client.handled_calls).must_include(pub)
    end

    it 'does not mark qos0 packets as handled' do
      pub = mock_publish.new(topic: 'test', payload: 'data', qos: 0)
      queue.push(pub)
      subscription.get
      _(mock_client.handled_calls).wont_include(pub)
    end
  end

  describe '#method_missing' do
    it 'responds to enumerable methods with bang' do
      _(subscription.respond_to?(:take!)).must_equal(true)
      _(subscription.respond_to?(:first!)).must_equal(true)
      _(subscription.respond_to?(:select!)).must_equal(true)
    end

    it 'does not respond to non-enumerable methods with bang' do
      _(subscription.respond_to?(:foobar!)).must_equal(false)
    end
  end

  describe 'concurrent put(nil)' do
    it 'stops iteration in another thread' do
      require 'concurrent_monitor'
      
      stub_client = Object.new
      stub_client.extend(ConcurrentMonitor)
      stub_client.monitor = ConcurrentMonitor.thread_monitor.new
      
      def stub_client.handled!(packet); end
      def stub_client.delete_subscription(sub, **opts); end
      
      real_queue = stub_client.new_queue
      real_sub = MQTT::Core::Client::EnumerableSubscription.new(
        sub_packet: nil,
        ack_packet: nil,
        handler: real_queue,
        client: stub_client
      )

      results = []
      thread = Thread.new do
        real_sub.each { |t, p| results << [t, p] }
      end

      sleep 0.1 # ensure thread is blocked on dequeue
      real_sub.put(mock_publish.new(topic: 'test/1', payload: 'msg1'))
      real_sub.put(nil)
      
      thread.join(1)
      _(thread.alive?).must_equal(false)
      _(results.size).must_equal(1)
    end

    it 'stops iteration in async fiber' do
      require 'concurrent_monitor'
      require 'async'
      
      stub_client = Object.new
      stub_client.extend(ConcurrentMonitor)
      stub_client.monitor = ConcurrentMonitor.async_monitor.new
      
      def stub_client.handled!(packet); end
      def stub_client.delete_subscription(sub, **opts); end
      
      real_queue = stub_client.new_queue
      real_sub = MQTT::Core::Client::EnumerableSubscription.new(
        sub_packet: nil,
        ack_packet: nil,
        handler: real_queue,
        client: stub_client
      )

      results = []
      Async do
        task = stub_client.async do
          real_sub.each { |t, p| results << [t, p] }
        end

        sleep 0.1
        real_sub.put(mock_publish.new(topic: 'test/1', payload: 'msg1'))
        real_sub.put(nil)
        
        task.wait
        _(results.size).must_equal(1)
      end
    end

    it 'stops async_packets with put(nil)' do
      require 'concurrent_monitor'
      require 'async'
      
      stub_client = Object.new
      stub_client.extend(ConcurrentMonitor)
      stub_client.monitor = ConcurrentMonitor.async_monitor.new
      
      def stub_client.handled!(packet); end
      def stub_client.delete_subscription(sub, **opts); end
      
      real_queue = stub_client.new_queue
      real_sub = MQTT::Core::Client::EnumerableSubscription.new(
        sub_packet: nil,
        ack_packet: nil,
        handler: real_queue,
        client: stub_client
      )

      results = []
      Async do
        _sub, task = real_sub.async_packets { |pkt| results << pkt }

        sleep 0.1
        real_sub.put(mock_publish.new(topic: 'test/1', payload: 'msg1'))
        real_sub.put(nil)
        
        task.wait
        _(results.size).must_equal(1)
      end
    end
  end
end
