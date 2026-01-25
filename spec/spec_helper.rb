# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/mock'

Minitest.load_plugins

ENV['MINITEST_REPORTER'] ||= 'DefaultReporter'
Minitest::Reporters.use! unless ENV.include?('RM_INFO') || Minitest::Reporters.reporters&.any?

require 'mqtt/core'
MQTT::Logger.log.public_send(ENV['DEBUG'] ? :debug! : :fatal!)

# keyword each for test generation
module Enumerable
  def kw_each(&block)
    each do |opts|
      block.call(**opts)
    end
  end
end

module MQTT
  module SpecHelper
    module ClassMethods
      def require_spec(name)
        require_relative "shared/#{name}"
      end

      def with_client_classes(protocol_version: nil, &block)
        clients = [
          { protocol: 5, async: false, class_name: 'MQTT::V5::Client', skip: false },
          { protocol: 5, async: true, class_name: 'MQTT::V5::Async::Client', skip: false },
          { protocol: 3, async: false, class_name: 'MQTT::V3::Client', skip: false },
          { protocol: 3, async: true, class_name: 'MQTT::V3::Async::Client', skip: false }
        ]
        
        clients = clients.select { |c| c[:protocol] == protocol_version } if protocol_version
        
        clients.reject { |opts| opts[:skip] }
               .kw_each do |class_name:, protocol:, async:, **|
          require "mqtt/v#{protocol}"
          require "mqtt/v#{protocol}/async/client" if async
          describe class_name do
            let(:client_class) { Object.const_get(class_name) }
            let(:monitor_class) { Object.const_get("#{async ? 'Async' : 'Thread'}::Monitor") }
            let(:retry_strategy) { false }
            let(:client_class_opts) { { protocol_version: protocol, async:, session_store:, retry_strategy: } }
            instance_eval(&block)
          end
        end
      end

      def file_store(klass, persistent_dir)
        klass.file_store(base_dir: persistent_dir, expiry_interval: nil, client_id: klass.generate_client_id)
      end

      def with_session_stores(min_qos: 0, &block)
        persistent_dir = Pathname.new(Dir.mktmpdir)
        Minitest.after_run { persistent_dir.rmtree }

        stores = [
          { ss: 'MemoryStore', ss_proc: ->(klass) { klass.memory_store }, max_qos: 2 },
          { ss: 'QoS0Store', ss_proc: ->(klass) { klass.qos0_store }, max_qos: 0 },
          { ss: 'FileStore', ss_proc: ->(klass) { file_store(klass, persistent_dir) }, max_qos: 2 }
        ]
        
        stores.select { |store| store[:max_qos] >= min_qos }
              .kw_each do |ss:, ss_proc:, **|
          describe "with #{ss}" do
            let(:session_store) { ss_proc.call(MQTT::Core::Client) }
            instance_eval(&block)
          end
        end
      end

      def with_brokers(&block)
        unix_socket = File.expand_path('fixture/mosquitto/mqtt.sock', __dir__)
        [
          { uri: 'mqtt://broker.hivemq.com', sys_topic: nil, skip: true },
          { uri: 'mqtt://localhost', sys_topic: '$SYS/broker/version', skip: false },
          { uri: "unix://#{unix_socket}", sys_topic: '$SYS/broker/version', skip: !File.exist?(unix_socket) },
          { uri: 'mqtt://test.mosquitto.org', sys_topic: '$SYS/broker/version', skip: true }
        ].reject { |opts| opts[:skip] }
          .kw_each do |uri:, sys_topic:, **|
          # Rubymine is confused by '.' characters
          describe "for #{uri.tr('.', "\u00b7")}" do
            let(:uri) { uri }
            let(:sys_topic) { sys_topic }
            instance_eval(&block)
          end
        end
      end

      def client_spec(*specs, min_qos: 0, protocol_version: nil)
        this = self
        with_brokers do
          parallelize_me! unless MQTT::Logger.log.debug?
          this.with_session_stores(min_qos: min_qos) do
            this.with_client_classes(protocol_version: protocol_version) do
              include(*specs)
            end
          end
        end
      end

      def protocol_version_spec(*specs)
        [
          { protocol: 3, subscribe_class: 'MQTT::V3::Packet::Subscribe', publish_class: 'MQTT::V3::Packet::Publish' },
          { protocol: 5, subscribe_class: 'MQTT::V5::Packet::Subscribe', publish_class: 'MQTT::V5::Packet::Publish' }
        ].kw_each do |protocol:, subscribe_class:, publish_class:|
          describe "MQTT v#{protocol}" do
            let(:subscribe_class) { Object.const_get(subscribe_class) }
            let(:publish_class) { Object.const_get(publish_class) }
            include(*specs)
          end
        end
      end
    end
    extend ClassMethods
  end
end

def with_client(**opts, &)
  MQTT.open(uri, **client_class_opts, **opts, &)
rescue MQTT::ConnectionError => e
  if e.cause
    puts "Rescued: #{e.class.name}: #{e.message}. Raising cause"
    raise e.cause
  end

  raise
end

def wait_until(timeout = 5, delay: 0.2, &block)
  ConcurrentMonitor::TimeoutClock.wait_until(timeout, delay:, &block)
end