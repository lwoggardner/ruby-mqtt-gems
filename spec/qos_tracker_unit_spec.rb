# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

# Unit tests for QoSTracker: birth buffering + QoS2 protocol dedup
describe 'QoSTracker' do
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

      def synchronize(&) = yield

      def log
        @log ||= Logger.new(nil)
      end
    end
  end
  let(:tracker) { tracker_class.new(session_store) }

  after do
    FileUtils.rm_rf(session_store.instance_variable_get(:@base_dir))
  end

  describe 'QoS2 duplicate detection' do
    it 'detects first occurrence' do
      _(tracker.qos2_published?(123)).must_equal(false)
    end

    it 'detects duplicate' do
      tracker.qos2_published?(123)
      _(tracker.qos2_published?(123)).must_equal(true)
    end

    it 'handles multiple packet IDs' do
      _(tracker.qos2_published?(100)).must_equal(false)
      _(tracker.qos2_published?(200)).must_equal(false)
      _(tracker.qos2_published?(100)).must_equal(true)
      _(tracker.qos2_published?(200)).must_equal(true)
    end
  end

  describe 'QoS2 release' do
    it 'releases and returns true if previously seen' do
      tracker.qos2_published?(789)
      _(tracker.qos2_release(789)).must_equal(true)
    end

    it 'returns false for unseen packet ID' do
      _(tracker.qos2_release(999)).must_equal(false)
    end

    it 'allows re-use of released packet ID' do
      tracker.qos2_published?(555)
      tracker.qos2_release(555)
      _(tracker.qos2_published?(555)).must_equal(false)
    end

    it 'recovers pending ids across restart and still deduplicates' do
      tracker.qos2_published?(0x0A)
      tracker.qos2_published?(0x0B)
      tracker.qos2_release(0x0A)

      # Simulate restart with same store directory
      restarted_store = session_store.restart_clone
      restarted_store.connected!
      restarted = tracker_class.new(restarted_store)

      # 0x0B was pending (not released), should be recovered as duplicate
      _(restarted.qos2_published?(0x0B)).must_equal(true)
      # 0x0A was released, should be seen as new
      _(restarted.qos2_published?(0x0A)).must_equal(false)
    end
  end

  describe 'birth phase buffering' do
    let(:packet1) { MQTT::V5::Packet::Publish.new(topic_name: 'test/a', payload: 'a', qos: 1, packet_identifier: 100) }
    let(:packet2) { MQTT::V5::Packet::Publish.new(topic_name: 'test/b', payload: 'b', qos: 2, packet_identifier: 200) }
    let(:packet3) { MQTT::V5::Packet::Publish.new(topic_name: 'other/c', payload: 'c', qos: 0) }

    it 'buffers packets before birth complete' do
      tracker.birth_buffer(packet1)
      tracker.birth_buffer(packet2)

      replayed = []
      tracker.qos_subscribed { |p| replayed << p }
      _(replayed).must_equal([packet1, packet2])
    end

    it 'does not buffer after birth complete' do
      tracker.birth_complete!
      tracker.birth_buffer(packet1)

      replayed = []
      tracker.qos_subscribed { |p| replayed << p }
      _(replayed).must_be_empty
    end

    it 'clears buffer on birth complete' do
      tracker.birth_buffer(packet1)
      tracker.birth_complete!

      replayed = []
      tracker.qos_subscribed { |p| replayed << p }
      _(replayed).must_be_empty
    end

    it 'reports birth_complete? correctly' do
      _(tracker.birth_complete?).must_equal(false)
      tracker.birth_complete!
      _(tracker.birth_complete?).must_equal(true)
    end

    it 'replays only matching packets to subscription via topic filter' do
      tracker.birth_buffer(packet1)  # test/a
      tracker.birth_buffer(packet2)  # test/b
      tracker.birth_buffer(packet3)  # other/c

      # Simulate what Client#qos_subscription does: filter by topic match
      replayed = []
      filters = ['test/#']
      tracker.qos_subscribed do |p|
        replayed << p if MQTT::Core::Client::Subscription::Filters.match_topic?(p.topic_name, filters)
      end

      _(replayed).must_equal([packet1, packet2])
    end

    it 'replays same packet to multiple subscriptions with different filters' do
      tracker.birth_buffer(packet1)  # test/a

      replayed_broad = []
      replayed_exact = []

      tracker.qos_subscribed do |p|
        replayed_broad << p if MQTT::Core::Client::Subscription::Filters.match_topic?(p.topic_name, ['#'])
      end
      tracker.qos_subscribed do |p|
        replayed_exact << p if MQTT::Core::Client::Subscription::Filters.match_topic?(p.topic_name, ['test/a'])
      end

      _(replayed_broad).must_equal([packet1])
      _(replayed_exact).must_equal([packet1])
    end

    it 'buffers QoS 0 packets during birth phase' do
      tracker.birth_buffer(packet3)  # qos: 0

      replayed = []
      tracker.qos_subscribed { |p| replayed << p }
      _(replayed).must_equal([packet3])
    end
  end
end
