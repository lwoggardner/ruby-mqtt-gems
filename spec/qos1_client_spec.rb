# frozen_string_literal: true
require_relative 'spec_helper'

# QoS 1 specific tests - only run with session stores that support QoS 1+
module MQTT
  module Qos1ClientSpec
    def self.included(spec)
      spec.class_eval do

        describe 'QoS 1 functionality' do
          it 'qos1 publish' do
            with_client do |client|
              pub = ack = nil
              client.on_publish { |p, a| pub = p; ack = a }
              client.connect
              client.publish('ruby_mqtt5/test', 'hello', qos: 1)
              expect(client.max_qos).wont_equal(0)
              expect(pub.packet_name).must_equal(:publish)
              expect(pub.packet_identifier).must_be :>, 0
              expect(pub.qos).must_equal(1)
              expect(ack.packet_name).must_equal(:puback)
              expect(ack.packet_identifier).must_equal(pub.packet_identifier)
            end
          end

          it 'qos1 subscribe' do
            topic = 'ruby_mqtt5/qos1_test'
            payload = 'qos1_message'
            
            with_client do |subscriber|
              subscriber.connect
              sub = subscriber.subscribe(topic, max_qos: 1)
              
              with_client(session_store: client_class.memory_store) do |publisher|
                publisher.publish(topic, payload, qos: 1)
              end
              
              # Receive and verify message
              received_topic, received_payload, attrs = sub.first
              _(attrs[:qos]).must_equal(1)
              _(received_topic).must_equal(topic)
              _(received_payload).must_equal(payload)
              
              sub.unsubscribe
            end
          end

        end

      end
    end
  end
end

# Only run these tests with session stores that support QoS 1+
MQTT::SpecHelper.client_spec(MQTT::Qos1ClientSpec, min_qos: 1)
