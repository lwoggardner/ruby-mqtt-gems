# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

# Unit tests for QoS 2 session store methods
describe 'QoS 2 Session Store Methods' do
  let(:memory_store) { MQTT::Core::Client.memory_store }
  let(:filesystem_store) { MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'test_client', expiry_interval: 3600) }

  describe 'MemorySessionStore' do
    it 'max_qos returns 2' do
      _(memory_store.max_qos).must_equal(2)
    end

    it 'qos2_recover returns empty array' do
      _(memory_store.qos2_recover).must_equal([])
    end

    it 'qos2_pending is a no-op' do
      _(memory_store.qos2_pending(123)).must_be_nil
    end

    it 'qos2_release is a no-op' do
      _(memory_store.qos2_release(123)).must_be_nil
    end
  end

  describe 'FilesystemSessionStore' do
    after do
      FileUtils.rm_rf(filesystem_store.instance_variable_get(:@base_dir))
    end

    it 'max_qos returns 2' do
      _(filesystem_store.max_qos).must_equal(2)
    end

    it 'qos2_recover returns empty array for new session' do
      filesystem_store.connected!
      _(filesystem_store.qos2_recover).must_equal([])
    end

    it 'qos2_pending persists and qos2_recover restores' do
      filesystem_store.connected!
      filesystem_store.qos2_pending(0x0A)
      filesystem_store.qos2_pending(0x0B)

      recovered = filesystem_store.qos2_recover
      _(recovered.sort).must_equal([0x0A, 0x0B])
    end

    it 'qos2_release removes pending file' do
      filesystem_store.connected!
      filesystem_store.qos2_pending(0x0C)
      filesystem_store.qos2_release(0x0C)

      _(filesystem_store.qos2_recover).must_equal([])
    end

    it 'qos2_release is safe for non-existent id' do
      filesystem_store.connected!
      filesystem_store.qos2_release(999) # should not raise
    end

    it 'survives simulated restart: pending ids recovered by new store instance' do
      filesystem_store.connected!
      filesystem_store.qos2_pending(0x10)
      filesystem_store.qos2_pending(0x20)
      filesystem_store.qos2_release(0x10)

      # Simulate restart: new store instance pointing at same directory
      restarted = filesystem_store.restart_clone
      restarted.connected!
      recovered = restarted.qos2_recover
      _(recovered).must_equal([0x20])
    end
  end

  describe 'Qos0SessionStore' do
    let(:qos0_store) { MQTT::Core::Client.qos0_store }

    it 'max_qos returns 0' do
      _(qos0_store.max_qos).must_equal(0)
    end

    it 'does not have QoS 2 methods' do
      _(qos0_store).wont_respond_to(:qos2_recover)
      _(qos0_store).wont_respond_to(:qos2_pending)
      _(qos0_store).wont_respond_to(:qos2_release)
    end
  end
end
