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
  end

  describe 'birth phase buffering' do
    let(:packet1) { MQTT::V5::Packet::Publish.new(topic_name: 'test/a', payload: 'a', qos: 1, packet_identifier: 100) }
    let(:packet2) { MQTT::V5::Packet::Publish.new(topic_name: 'test/b', payload: 'b', qos: 2, packet_identifier: 200) }

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
  end
end
