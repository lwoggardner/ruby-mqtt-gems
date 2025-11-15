# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'securerandom'
require_relative '../spec_helper'
require_relative 'helpers'

module MQTT
  module QoSReliability
    describe 'QoS 2 Reliability Tests' do
      include TestHelpers

      # Use test.mosquitto.org as the broker for tests
      let(:broker_uri) { 'mqtt://test.mosquitto.org' }
      
      before do
        @client_setup = TripleClientSetup.new(broker_uri)
      end
      
      after do
        @client_setup.cleanup_all
      end
      
      describe 'Basic QoS 2 Message Delivery' do
        it 'delivers QoS 2 messages exactly once' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Generate a unique payload
          payload = "qos2-basic-#{SecureRandom.hex(4)}"
          
          # Publish a QoS 2 message
          pub, ack = test_client.publish(test_topic, payload, qos: 2)
          
          # Verify the publish and ack packets
          _(pub.packet_name).must_equal :publish
          _(pub.qos).must_equal 2
          _(ack.packet_name).must_equal :pubcomp
          _(ack.packet_identifier).must_equal pub.packet_identifier
          
          # Verify the message was received by the witness
          received = witness.verify_received(payload, timeout: 5)
          _(received).must_equal true
          
          # Verify the message was received exactly once (no duplicates)
          count = witness.message_count_for_payload(payload)
          _(count).must_equal 1
        end
        
        it 'completes the full QoS 2 flow (PUBLISH -> PUBREC -> PUBREL -> PUBCOMP)' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Set up flow verifier
          flow_verifier = QoSFlowVerifier.new
          
          # Track packet flow
          received_packets = []
          
          test_client.on_send do |packet|
            received_packets << packet if packet
          end
          
          test_client.on_receive do |packet|
            received_packets << packet if packet
          end
          
          # Generate a unique payload
          payload = "qos2-flow-#{SecureRandom.hex(4)}"
          
          # Publish a QoS 2 message
          pub, ack = test_client.publish(test_topic, payload, qos: 2)
          
          # Verify the packet flow
          publish_packets = received_packets.select { |p| p.packet_name == :publish && p.qos == 2 }
          pubrec_packets = received_packets.select { |p| p.packet_name == :pubrec }
          pubrel_packets = received_packets.select { |p| p.packet_name == :pubrel }
          pubcomp_packets = received_packets.select { |p| p.packet_name == :pubcomp }
          
          _(publish_packets.size).must_equal 1
          _(pubrec_packets.size).must_equal 1
          _(pubrel_packets.size).must_equal 1
          _(pubcomp_packets.size).must_equal 1
          
          # Verify packet IDs match
          message_id = publish_packets.first.packet_identifier
          _(pubrec_packets.first.packet_identifier).must_equal message_id
          _(pubrel_packets.first.packet_identifier).must_equal message_id
          _(pubcomp_packets.first.packet_identifier).must_equal message_id
        end
      end
      
      describe 'QoS 2 with Network Failures' do
        it 'handles network disconnection after PUBLISH' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "qos2-disconnect-after-publish-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after sending PUBLISH
          network_controller.disconnect_at_stage(test_client, :before_pubrec)
          
          # Publish a QoS 2 message (this will disconnect after sending)
          begin
            test_client.publish(test_topic, payload, qos: 2)
          rescue => e
            # Expect a disconnect error
            _(e.message).must_match(/disconnect|connection|closed/i)
          end
          
          # Reconnect the client
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Verify the message was received by the witness
          received = witness.verify_received(payload, timeout: 10)
          _(received).must_equal true
          
          # Verify the message was received exactly once (no duplicates)
          count = witness.message_count_for_payload(payload)
          _(count).must_equal 1
        end
        
        it 'handles network disconnection after PUBREC' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "qos2-disconnect-after-pubrec-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after receiving PUBREC
          network_controller.disconnect_at_stage(test_client, :before_pubrel)
          
          # Publish a QoS 2 message (this will disconnect after receiving PUBREC)
          begin
            test_client.publish(test_topic, payload, qos: 2)
          rescue => e
            # Expect a disconnect error
            _(e.message).must_match(/disconnect|connection|closed/i)
          end
          
          # Reconnect the client
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Verify the message was received by the witness
          received = witness.verify_received(payload, timeout: 10)
          _(received).must_equal true
          
          # Verify the message was received exactly once (no duplicates)
          count = witness.message_count_for_payload(payload)
          _(count).must_equal 1
        end
        
        it 'handles network disconnection after PUBREL' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "qos2-disconnect-after-pubrel-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after sending PUBREL
          network_controller.disconnect_at_stage(test_client, :before_pubcomp)
          
          # Publish a QoS 2 message (this will disconnect after sending PUBREL)
          begin
            test_client.publish(test_topic, payload, qos: 2)
          rescue => e
            # Expect a disconnect error
            _(e.message).must_match(/disconnect|connection|closed/i)
          end
          
          # Reconnect the client
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Verify the message was received by the witness
          received = witness.verify_received(payload, timeout: 10)
          _(received).must_equal true
          
          # Verify the message was received exactly once (no duplicates)
          count = witness.message_count_for_payload(payload)
          _(count).must_equal 1
        end
      end
      
      describe 'QoS 2 with Session Persistence' do
        it 'persists QoS 2 messages across client restarts with file store' do
          # Create a unique client ID for this test
          client_id = "qos2-persistence-#{SecureRandom.hex(4)}"
          
          # Create test client with file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "qos2-persistence-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after sending PUBLISH
          network_controller.disconnect_at_stage(test_client, :before_pubrec)
          
          # Publish a QoS 2 message (this will disconnect after sending)
          begin
            test_client.publish(test_topic, payload, qos: 2)
          rescue => e
            # Expect a disconnect error
            _(e.message).must_match(/disconnect|connection|closed/i)
          end
          
          # Reconnect the client with the same client ID and file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Verify the message was received by the witness
          received = witness.verify_received(payload, timeout: 10)
          _(received).must_equal true
          
          # Verify the message was received exactly once (no duplicates)
          count = witness.message_count_for_payload(payload)
          _(count).must_equal 1
        end
      end
      
      describe 'QoS 2 with Multiple Messages' do
        it 'handles burst of QoS 2 messages reliably' do
          # Create test client with memory store
          test_client = @client_setup.create_test_client(:memory)
          ensure_broker_ready(test_client)
          
          # Create witness client to verify message delivery
          witness_client = @client_setup.create_witness_client
          ensure_broker_ready(witness_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe witness to the test topic
          witness = PacketWitness.new(witness_client)
          witness.subscribe_to(test_topic, qos: 2)
          
          # Create message generator
          generator = MessageGenerator.new(test_client)
          
          # Generate a burst of 5 QoS 2 messages
          message_count = 5
          message_ids = generator.generate_burst(test_topic, message_count, qos: 2)
          
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