# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

describe 'Session expiry and SessionNotPresent' do
  let(:monitor) { ConcurrentMonitor.thread_monitor }

  def make_session(store)
    MQTT::Core::Client::Session.new(client: nil, monitor:, session_store: store)
  end

  MockConnack = Struct.new(:session_present, keyword_init: true) do
    alias_method :session_present?, :session_present
  end

  describe 'SessionExpired' do
    it 'raises when FileStore session has expired' do
      store = MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'expiry_test', expiry_interval: 1)
      session = make_session(store)

      # Establish then disconnect
      store.connected!
      store.disconnected!

      sleep 1.5

      assert_raises(MQTT::SessionExpired) { session.expired! }
    ensure
      FileUtils.rm_rf(store.base_dir)
    end

    it 'does not raise when session has not expired' do
      store = MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'no_expiry_test', expiry_interval: 3600)
      session = make_session(store)

      store.connected!
      store.disconnected!

      session.expired! # should not raise
      pass
    ensure
      FileUtils.rm_rf(store.base_dir)
    end

    it 'does not raise for clean session even if expired' do
      store = MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'clean_expiry', expiry_interval: 1)
      session = make_session(store)

      # Never connected — store is clean
      session.expired! # should not raise
      pass
    ensure
      FileUtils.rm_rf(store.base_dir)
    end
  end

  describe 'SessionNotPresent' do
    it 'raises when broker has no session but client expected one' do
      store = MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'snp_test', expiry_interval: 3600)
      session = make_session(store)

      # First connection establishes session
      store.connected!
      store.disconnected!

      # Reconnect — store is not clean, but broker says no session
      assert_raises(MQTT::SessionNotPresent) do
        session.connected!(nil, MockConnack.new(session_present: false))
      end
    ensure
      FileUtils.rm_rf(store.base_dir)
    end

    it 'does not raise when broker confirms session present' do
      store = MQTT::Core::Client.file_store(base_dir: Dir.mktmpdir, client_id: 'sp_test', expiry_interval: 3600)
      session = make_session(store)

      store.connected!
      store.disconnected!

      session.connected!(nil, MockConnack.new(session_present: true)) # should not raise
      pass
    ensure
      FileUtils.rm_rf(store.base_dir)
    end

    it 'does not raise for clean session even if broker has no session' do
      store = MQTT::Core::Client.memory_store
      session = make_session(store)

      # MemoryStore is clean on first connect
      session.connected!(nil, MockConnack.new(session_present: false)) # should not raise
      pass
    end
  end
end
