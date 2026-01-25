# frozen_string_literal: true
require_relative 'spec_helper'
require 'mqtt/v5'

# Unit tests for QoS 2 session store methods
describe 'QoS 2 Session Store Methods' do
  let(:memory_store) { MQTT::Core::Client.memory_store }
  let(:filesystem_store) { MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'test_client', expiry_interval: 3600) }
  
  describe 'MemorySessionStore QoS 2 methods' do
    it 'qos2_recover returns empty array for new session' do
      result = memory_store.qos2_recover
      _(result).must_be_kind_of(Array)
      _(result).must_be_empty
    end

    it 'qos2_release handles packet ID release' do
      packet_id = 123
      result = memory_store.qos2_release(packet_id)
      _(result).must_be_nil  # Memory store returns nil
    end

    it 'qos_handled processes packet completion' do
      packet = MQTT::V5::Packet::Publish.new(topic_name: 'test', payload: 'data', qos: 2, packet_identifier: 456)
      unique_id = 'test_unique_id'
      
      # Should not raise an error
      memory_store.qos_handled(packet, unique_id)
    end

    it 'store_qos_received stores received QoS packets' do
      packet = MQTT::V5::Packet::Publish.new(topic_name: 'test', payload: 'data', qos: 2, packet_identifier: 789)
      unique_id = 'received_unique_id'
      
      # Should not raise an error
      memory_store.store_qos_received(packet, unique_id)
    end

    it 'max_qos returns 2 for QoS 2 capable store' do
      _(memory_store.max_qos).must_equal(2)
    end
  end

  describe 'FilesystemSessionStore QoS 2 methods' do
    after do
      # Cleanup temp directory
      FileUtils.rm_rf(filesystem_store.instance_variable_get(:@base_dir))
    end

    it 'qos2_recover returns empty array for new session' do
      filesystem_store.connected! # Initialize directories
      result = filesystem_store.qos2_recover
      _(result).must_be_kind_of(Array)
      _(result).must_be_empty
    end

    it 'qos2_release handles packet ID release' do
      filesystem_store.connected! # Initialize directories
      packet_id = 123
      result = filesystem_store.qos2_release(packet_id)
      # Filesystem store returns true when attempting to release (even if packet not found)
      _(result).must_equal(true)
    end

    it 'qos_handled processes packet completion' do
      filesystem_store.connected! # Initialize directories
      packet = MQTT::V5::Packet::Publish.new(topic_name: 'test', payload: 'data', qos: 2, packet_identifier: 456)
      unique_id = 'test_unique_id'
      
      # Should not raise an error
      filesystem_store.qos_handled(packet, unique_id)
    end

    it 'store_qos_received stores received QoS packets' do
      filesystem_store.connected! # Initialize directories
      packet = MQTT::V5::Packet::Publish.new(topic_name: 'test', payload: 'data', qos: 2, packet_identifier: 789)
      unique_id = 'received_unique_id'
      
      # Should not raise an error
      filesystem_store.store_qos_received(packet, unique_id)
    end

    it 'max_qos returns 2 for QoS 2 capable store' do
      _(filesystem_store.max_qos).must_equal(2)
    end
  end

  describe 'QoS0SessionStore limitations' do
    let(:qos0_store) { MQTT::Core::Client.qos0_store }

    it 'max_qos returns 0' do
      _(qos0_store.max_qos).must_equal(0)
    end

    it 'only supports basic packet storage' do
      # QoS0SessionStore doesn't have QoS 2 specific methods
      _(qos0_store).wont_respond_to(:store_qos_received)
      _(qos0_store).wont_respond_to(:qos2_recover)
    end
  end
end
