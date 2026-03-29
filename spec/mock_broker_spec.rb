# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'
require 'mqtt/v3'
require 'socket'

# A mock broker that runs its protocol script in a background thread.
module MockBroker
  # Quacks like a SocketFactory for Client.open
  class SocketFactory
    attr_reader :uri

    def initialize(io)
      @io = io
      @uri = URI.parse('mqtt://mock-broker')
    end

    def new_io = @io
    def query_params = {}
  end

  def self.start(&script)
    client_io, broker_io = UNIXSocket.pair
    thread = Thread.new do
      script.call(broker_io)
    rescue IOError, Errno::EPIPE
      nil
    ensure
      broker_io.close unless broker_io.closed?
    end
    [SocketFactory.new(client_io), thread]
  end

  def self.accept_connect(io, pkt_mod, session_present: false)
    pkt_mod.deserialize(io)
    pkt_mod.build_packet(:connack, session_present:).serialize(io)
  end

  def self.read_packet(io, pkt_mod) = pkt_mod.deserialize(io)

  def self.send_puback(io, pkt_mod, packet_identifier:)
    pkt_mod.build_packet(:puback, packet_identifier:).serialize(io)
  end

  def self.send_suback(io, pkt_mod, packet_identifier:, return_codes:)
    # V3 uses return_codes, V5 uses reason_codes
    key = pkt_mod == MQTT::V5::Packet ? :reason_codes : :return_codes
    pkt_mod.build_packet(:suback, packet_identifier:, key => return_codes).serialize(io)
  end

  def self.send_publish(io, pkt_mod, **opts)
    pkt_mod.build_packet(:publish, **opts).serialize(io)
  end
end

module MQTT
  module OutboundRetrySpec
    def self.included(spec)
      spec.class_eval do
        describe 'QoS 1 outbound retry across restart' do
          it 'resends unacked publish with dup flag after restart' do
            store = session_store
            pkt_mod = client_class.packet_module
            topic = 'test/retry'
            payload = 'hello'
            captured_pub = nil

            # Connection 1: establish session
            sf, bt = MockBroker.start { |io| MockBroker.accept_connect(io, pkt_mod) }
            client_class.open(sf, session_store: store) { |c| c.connect }
            bt.join(5)

            # Connection 2: publish QoS 1, broker closes without PUBACK
            sf, bt = MockBroker.start do |io|
              MockBroker.accept_connect(io, pkt_mod, session_present: true)
              captured_pub = MockBroker.read_packet(io, pkt_mod)
            end

            begin
              client_class.open(sf, session_store: store) do |c|
                c.connect
                c.publish(topic, payload, qos: 1)
              end
            rescue StandardError
              # expected — broker closed before PUBACK
            end
            bt.join(5)

            _(captured_pub&.packet_name).must_equal :publish
            _(captured_pub.dup).must_equal false

            # Connection 3: reconnect with cloned store — should resend with dup
            retried_pub = nil
            sf, bt = MockBroker.start do |io|
              MockBroker.accept_connect(io, pkt_mod, session_present: true)
              loop do
                pkt = MockBroker.read_packet(io, pkt_mod)
                break unless pkt
                next unless pkt.packet_name == :publish

                retried_pub = pkt
                MockBroker.send_puback(io, pkt_mod, packet_identifier: pkt.packet_identifier)
                break
              end
            end

            client_class.open(sf, session_store: store.restart_clone) do |c|
              c.connect
              wait_until { retried_pub }
            end
            bt.join(5)

            _(retried_pub&.packet_name).must_equal :publish
            _(retried_pub.dup).must_equal true
            _(retried_pub.topic_name).must_equal topic
          end
        end
      end
    end
  end

  module BirthBufferSpec
    def self.included(spec)
      spec.class_eval do
        describe 'birth-phase buffering across restart' do
          it 'delivers messages arriving during on_birth to subscriptions' do
            store = session_store
            pkt_mod = client_class.packet_module

            # Connection 1: establish session
            sf, bt = MockBroker.start { |io| MockBroker.accept_connect(io, pkt_mod) }
            client_class.open(sf, session_store: store) { |c| c.connect }
            bt.join(5)

            # Connection 2: reconnect — broker sends queued message after SUBACK
            received = []
            sf, bt = MockBroker.start do |io|
              MockBroker.accept_connect(io, pkt_mod, session_present: true)
              sub = MockBroker.read_packet(io, pkt_mod)
              MockBroker.send_suback(io, pkt_mod,
                                     packet_identifier: sub.packet_identifier,
                                     return_codes: sub.topic_filters.map { 0 })
              MockBroker.send_publish(io, pkt_mod,
                                      topic_name: 'test/queued', payload: 'buffered', qos: 0)
              MockBroker.read_packet(io, pkt_mod) rescue nil
            end

            client_class.open(sf, session_store: store.restart_clone) do |c|
              c.on_birth do
                c.subscribe('test/#').async { |topic, payload| received << [topic, payload] }
              end
              c.connect
              wait_until { received.size >= 1 }
            end
            bt.join(5)

            _(received.first).must_equal ['test/queued', 'buffered']
          end
        end
      end
    end
  end
end

# FileStore only × all client classes (V3/V5 × threaded/async)
describe 'Mock broker tests' do
  extend MQTT::SpecHelper::ClassMethods

  persistent_dir = Pathname.new(Dir.mktmpdir)
  Minitest.after_run { persistent_dir.rmtree }

  let(:session_store) do
    MQTT::Core::Client.file_store(base_dir: persistent_dir, expiry_interval: nil,
                                  client_id: MQTT::Core::Client.generate_client_id)
  end

  with_client_classes do
    include MQTT::OutboundRetrySpec
    include MQTT::BirthBufferSpec
  end
end
