# frozen_string_literal: true

require 'securerandom'
require_relative '../spec_helper'
require_relative 'helpers'

module MQTT
  module QoSReliabilitySpec
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

        def wait_until(timeout = 5, delay: 0.2, &block)
          ConcurrentMonitor::TimeoutClock.wait_until(timeout, delay: delay, &block)
        end

        def create_test_topic(prefix = 'ruby_mqtt_qos_test')
          "#{prefix}/#{SecureRandom.hex(8)}"
        end

        if self.name =~ /QoS0Store/
          it 'rejects QOS1 publish and subscribe'
          next
        end

        failure_points = [[:receive, :puback],[:send, :publish]]
        it 'resends QoS 1 messages after hard restart if not acknowledged' do
          # Generate a unique topic and payload
          test_topic = create_test_topic
          payload = "qos1-resend-#{SecureRandom.hex(4)}"
          # First client will disconnect on receiving PUBACK
          network_controller.raise_on_receive(:puback)

          with_client(network_controller, client_tracker) do |client|
            expect(proc { client.publish(test_topic, payload, qos: 1) }).must_raise(ConnectionError)
          end

          # Connect a new client with a clone o the session store (simulating reconnection and packet completion)
          # TODO: We should also test with a more complex client
          #   resubscribing,  starting to republish,  test order (republish should be sent before next publish)

          with_client(client_tracker, session_store: session_store.restart_clone) { |client| } # do nothing but clean disconnect

          # We never sent the original, only sent the dup
          client_tracker.matches(:publish, dup: false).size.must_equal 0
          client_tracker.matches(:publish, dup: true, topic: test_topic, payload:).size.must_equal 1
        end

        it 'resends QoS 1 messages after auto retry if not acknowledged' do
          # Generate a unique topic and payload
          test_topic = create_test_topic
          payload = "qos1-resend-#{SecureRandom.hex(4)}"
          network_controller.raise_on_receive(:puback)
          network_controller.retry_error(count: 2)
          with_client(network_controller, client_tracker) do |client|
            client.publish(test_topic, payload, qos: 1)
          end
          # We never sent the original, only sent the dup
          client_tracker.matches(:publish, dup: false).size.must_equal 0
          client_tracker.matches(:publish, dup: true, topic: test_topic, payload:).size.must_equal 1
        end


        it 'handles burst of QoS 1 messages reliably' do
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

MQTT::SpecHelper.client_spec(MQTT::QoSReliabilitySpec)