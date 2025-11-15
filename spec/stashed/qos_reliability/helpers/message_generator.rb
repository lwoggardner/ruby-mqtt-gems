# frozen_string_literal: true

require 'securerandom'

module MQTT
  module QoSReliability
    # Message Generator - Publishes messages to test incoming flows
    class MessageGenerator
      attr_reader :client, :published_messages

      def initialize(client)
        @client = client
        @published_messages = {}
      end

      # Publishes QoS 1 message to trigger incoming flow test
      # Returns the message ID and the publish packet
      def generate_qos1_flow(topic, payload)
        pub, ack = client.publish(topic, payload, qos: 1)
        message_id = pub.packet_identifier
        @published_messages[message_id] = {
          topic: topic,
          payload: payload,
          qos: 1,
          pub: pub,
          ack: ack
        }
        [message_id, pub]
      end

      # Publishes QoS 2 message to trigger incoming flow test
      # Returns the message ID and the publish packet
      def generate_qos2_flow(topic, payload)
        pub, ack = client.publish(topic, payload, qos: 2)
        message_id = pub.packet_identifier
        @published_messages[message_id] = {
          topic: topic,
          payload: payload,
          qos: 2,
          pub: pub,
          ack: ack
        }
        [message_id, pub]
      end

      # Generates multiple messages for stress testing
      # Returns an array of message IDs
      def generate_burst(topic, count, qos: 1)
        message_ids = []
        count.times do |i|
          payload = "burst-#{i}-#{SecureRandom.hex(4)}"
          if qos == 0
            client.publish(topic, payload, qos: 0)
            message_ids << nil
          elsif qos == 1
            message_id, = generate_qos1_flow(topic, payload)
            message_ids << message_id
          elsif qos == 2
            message_id, = generate_qos2_flow(topic, payload)
            message_ids << message_id
          end
        end
        message_ids
      end

      # Generates messages with controlled timing
      # messages is an array of [payload, qos] pairs
      # Returns an array of message IDs
      def generate_with_timing(topic, messages, interval: 0.5)
        message_ids = []
        messages.each do |payload, qos|
          if qos == 0
            client.publish(topic, payload, qos: 0)
            message_ids << nil
          elsif qos == 1
            message_id, = generate_qos1_flow(topic, payload)
            message_ids << message_id
          elsif qos == 2
            message_id, = generate_qos2_flow(topic, payload)
            message_ids << message_id
          end
          sleep interval if interval > 0
        end
        message_ids
      end
    end
  end
end