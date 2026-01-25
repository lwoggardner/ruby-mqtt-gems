# frozen_string_literal: true
require_relative 'spec_helper'

# QoS 2 specific tests - only run with session stores that support QoS 2
# PUBLISH → PUBREC → PUBREL → PUBCOMP
module MQTT
  module Qos2ClientSpec
    def self.included(spec)
      spec.class_eval do

        describe 'QoS 2 subscription receive flow' do
          it 'qos2 publish' do
            with_client do |client|
              pub = ack = nil
              sent_packets = []
              client.on_publish { |p, a| pub = p; ack = a }
              client.on_send { |pkt| sent_packets << pkt if pkt }
              client.connect
              client.publish('ruby_mqtt5/test', 'hello', qos: 2)
              expect(client.max_qos).must_equal(2)
              expect(pub.packet_name).must_equal(:publish)
              expect(pub.packet_identifier).must_be :>, 0
              expect(pub.qos).must_equal(2)
              expect(ack.packet_name).must_equal(:pubcomp)
              expect(ack.packet_identifier).must_equal(pub.packet_identifier)
              
              # Verify QoS 2 publish flow packets were sent
              pubrel_packets = sent_packets.select { |p| p.packet_name == :pubrel }
              expect(pubrel_packets.size).must_be :>=, 1
            end
          end

          it 'tracks QoS 2 packet flow with event handlers' do
            topic = 'ruby_mqtt5/qos2_flow_test'
            payload = 'qos2_flow_message'
            
            sent_packets = []
            
            with_client do |subscriber|
              subscriber.on_send { |pkt| sent_packets << pkt if pkt }
              subscriber.connect
              sub = subscriber.subscribe(topic, max_qos: 2)
              
              with_client(session_store: client_class.memory_store) do |publisher|
                publisher.publish(topic, payload, qos: 2)
              end
              
              # Receive the message
              received_topic, received_payload, attrs = sub.first
              _(attrs[:qos]).must_equal(2)
              _(received_topic).must_equal(topic)
              _(received_payload).must_equal(payload)
              
              sub.unsubscribe
            end
            
            # Verify QoS 2 receive flow packets were sent (after client cleanup)
            pubrec_packets = sent_packets.select { |p| p.packet_name == :pubrec }
            pubcomp_packets = sent_packets.select { |p| p.packet_name == :pubcomp }
            
            _(pubrec_packets.size).must_be :>=, 1
            _(pubcomp_packets.size).must_be :>=, 1
          end

        end

      end
    end
  end
end

# Only run these tests with session stores that support QoS 2
MQTT::SpecHelper.client_spec(MQTT::Qos2ClientSpec, min_qos: 2)
