# frozen_string_literal: true
require_relative 'spec_helper'
require 'mqtt/v5'

# Unit tests for QoSTracker behavior with FileStore
describe 'QoSTracker with FileStore' do
  let(:session_store) { MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'qos_tracker_test', expiry_interval: 3600) }
  let(:tracker_class) do
    Class.new do
      include MQTT::Core::Client::QosTracker
      
      attr_reader :session_store
      
      def initialize(store)
        @session_store = store
        @session_store.connected!
        qos_initialize
      end
      
      def synchronize(&block)
        block.call
      end
      
      def log
        @log ||= Logger.new(nil)
      end
      
      def deserialize(io)
        MQTT::V5::Packet.deserialize(io)
      end
    end
  end
  let(:tracker) { tracker_class.new(session_store) }

  after do
    # Cleanup temp directory
    FileUtils.rm_rf(session_store.instance_variable_get(:@base_dir))
  end

  describe 'QoS 2 duplicate detection' do
    it 'detects first occurrence of packet ID' do
      _(tracker.qos2_published?(123)).must_equal(false)
    end

    it 'detects duplicate packet ID' do
      tracker.qos2_published?(123)
      _(tracker.qos2_published?(123)).must_equal(true)
    end

    it 'handles multiple different packet IDs' do
      _(tracker.qos2_published?(100)).must_equal(false)
      _(tracker.qos2_published?(200)).must_equal(false)
      _(tracker.qos2_published?(100)).must_equal(true)
      _(tracker.qos2_published?(200)).must_equal(true)
    end
  end

  describe 'packet lifecycle management' do
    let(:packet) { MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', payload: 'data', qos: 2, packet_identifier: 456) }

    it 'stores received packet with subscription count' do
      tracker.qos_received(packet, 1)
      
      # Packet should be tracked internally
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets).must_include(packet)
      _(qos_packets[packet][:counter]).must_equal(1)
    end

    it 'decrements counter when handled' do
      tracker.qos_received(packet, 2)
      tracker.birth_complete!
      
      tracker.handled!(packet)
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets[packet][:counter]).must_equal(1)
      
      tracker.handled!(packet)
      _(qos_packets).wont_include(packet)
    end

    it 'calls session store qos_handled when counter reaches zero' do
      tracker.qos_received(packet, 1)
      tracker.birth_complete!
      
      # Mock to verify qos_handled is called
      called_with = nil
      session_store.define_singleton_method(:qos_handled) do |pkt, uid|
        called_with = [pkt, uid]
      end
      
      tracker.handled!(packet)
      _(called_with[0]).must_equal(packet)
      _(called_with[1]).must_be_kind_of(String)
    end
  end

  describe 'QoS 2 release' do
    it 'releases packet ID and returns true if previously seen' do
      tracker.qos2_published?(789)
      result = tracker.qos2_release(789)
      _(result).must_equal(true)
    end

    it 'returns false for unseen packet ID' do
      result = tracker.qos2_release(999)
      _(result).must_equal(false)
    end

    it 'removes packet ID from pending set' do
      tracker.qos2_published?(555)
      tracker.qos2_release(555)
      
      # Should be able to see it as "first occurrence" again
      _(tracker.qos2_published?(555)).must_equal(false)
    end
  end

  describe 'birth phase management' do
    let(:packet1) { MQTT::V5::Packet::Publish.new(topic_name: 'test/topic1', payload: 'data1', qos: 2, packet_identifier: 100) }
    let(:packet2) { MQTT::V5::Packet::Publish.new(topic_name: 'test/topic2', payload: 'data2', qos: 2, packet_identifier: 200) }

    it 'caches packets during birth phase' do
      tracker.qos_received(packet1, 0)  # No subscriptions yet
      tracker.qos_received(packet2, 1)  # One subscription
      
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets.size).must_equal(2)
      _(tracker.birth_complete?).must_equal(false)
    end

    it 'matches cached packets to new subscriptions' do
      tracker.qos_received(packet1, 0)
      
      matched = tracker.qos_subscribed { |pkt| pkt.topic_name == 'test/topic1' }
      _(matched).must_include(packet1)
      
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets[packet1][:counter]).must_equal(1)
      _(qos_packets[packet1][:subscribed]).must_equal(true)
    end

    it 'removes unsubscribed packets during birth phase' do
      tracker.qos_received(packet1, 0)  # No subscriptions (subscribed: false)
      tracker.qos_received(packet2, 1)  # Has subscription (subscribed: true)
      
      # Remove unsubscribed packets matching the filter
      tracker.qos_unsubscribed { |pkt| pkt.topic_name == 'test/topic1' }
      
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets).wont_include(packet1)  # Should be removed (was unsubscribed)
      _(qos_packets).must_include(packet2)   # Should remain (was subscribed)
    end

    it 'ignores unsubscribe after birth complete' do
      tracker.qos_received(packet1, 1)
      tracker.birth_complete!
      
      # Should not affect packets after birth complete
      tracker.qos_unsubscribed { |pkt| pkt.topic_name == 'test/topic1' }
      
      qos_packets = tracker.send(:qos_packets)
      _(qos_packets).must_include(packet1)
    end

    it 'processes zero-counter packets on birth complete' do
      tracker.qos_received(packet1, 0)  # No subscriptions
      
      # Mock qos_handled to verify it's called
      handled_packets = []
      session_store.define_singleton_method(:qos_handled) do |pkt, uid|
        handled_packets << pkt
      end
      
      tracker.birth_complete!
      _(handled_packets).must_include(packet1)
      _(tracker.birth_complete?).must_equal(true)
    end
  end
end
