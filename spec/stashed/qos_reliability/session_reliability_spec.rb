# frozen_string_literal: true

require 'securerandom'
require_relative '../spec_helper'
require_relative 'helpers'

module MQTT
  module QoSReliability
    module SessionReliabilitySpec
      def self.included(spec)
        spec.class_eval do
          include MQTT::QoSReliability::TestHelpers
          let(:retry_strategy) { nil }
          let(:network_controller) { QoSReliability::NetworkController.new }
          let(:witness_tracker) { QoSReliability::PacketWitness.new }
          let(:client_tracker) { QoSReliability::PacketWitness.new }

          def with_witness_client(&block)
            witness_client_id = "witness_client_#{SecureRandom.hex(4)}"
            MQTT.open(uri, client_id: witness_client_id, connect_timeout: connect_timeout) do |witness_client|
              witness_client.configure_retry(nil)
              witness_client.on_receive { |packet| witness_tracker.call(:receive, packet) }
              block.call(witness_client)
            end
          end

          def create_test_topic(prefix = 'ruby_mqtt_qos_test')
            "#{prefix}/#{SecureRandom.hex(8)}"
          end

          it 'resends unacknowledged SUBSCRIBE messages after auto reconnect'
          it 'resends unacknowledged UNSUBSCRIBE messages after auto reconnect'

          if self.name =~ /QoS0Store/
            it 'establishes a clean session, cancels subscriptions and calls #birth event after auto reconnect'
          else
            it 'retains the session, and does not call #birth event after auto reconnect'
          end

          it 'disconnects with cause of #birth event failure'

          # TODO: SUBSCRIBE / UNSUBSCRIBE / QOS 1, QOS 2 network failure at random points
          it 'handles bursts of messages reliably' do
            test_topic = create_test_topic

            with_witness_client do |witness_client|
              # Set up witness to verify message delivery
              witness = MQTT::QoSReliability::PacketWitness.new(witness_client)
              witness.subscribe_to(test_topic, qos: 1)

              with_client do |client|
                # Create message generator
                generator = MQTT::QoSReliability::MessageGenerator.new(client)

                # Generate a burst of 10 QoS 1 messages
                message_count = 10
                message_ids = generator.generate_burst(test_topic, message_count, qos: 1)

                # Verify all messages were received
                received = witness.wait_for_message_count(test_topic, message_count, timeout: 10)
                _(received).must_equal true

                # Verify the message count
                count = witness.message_count_for_topic(test_topic)
                _(count).must_equal message_count
              end
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::QoSReliability::SessionReliabilitySpec)