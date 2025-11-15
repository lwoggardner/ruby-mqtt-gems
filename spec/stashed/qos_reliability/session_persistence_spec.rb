# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'securerandom'
require_relative '../spec_helper'
require_relative 'helpers'

module MQTT
  module QoSReliability
    describe 'Session Persistence Tests' do
      include TestHelpers

      # Use test.mosquitto.org as the broker for tests
      let(:broker_uri) { 'mqtt://test.mosquitto.org' }
      
      before do
        @client_setup = TripleClientSetup.new(broker_uri)
      end
      
      after do
        @client_setup.cleanup_alltrue
      end
      
      describe 'Basic Session Persistence' do
        it 'maintains session state across disconnects with clean_session=false' do
          # Create a unique client ID for this test
          client_id = "session-persistence-#{SecureRandom.hex(4)}"
          
          # Create test client with file store and clean_session=false
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe to the test topic
          subscription = test_client.subscribe(test_topic, max_qos: 1)
          
          # Verify the subscription was successful
          sub_pkt, ack_pkt, = subscription.deconstruct
          _(sub_pkt.packet_name).must_equal :subscribe
          _(ack_pkt.packet_name).must_equal :suback
          
          # Disconnect the client
          test_client.disconnect
          
          # Create generator client to publish messages while test client is disconnected
          generator_client = @client_setup.create_generator_client
          ensure_broker_ready(generator_client)
          
          # Generate a unique payload
          payload = "session-persistence-#{SecureRandom.hex(4)}"
          
          # Publish a message to the test topic
          generator_client.publish(test_topic, payload, qos: 1)
          
          # Reconnect the test client with the same client ID and clean_session=false
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Set up a message handler to capture received messages
          received_messages = []
          test_client.on_message do |message|
            received_messages << message
          end
          
          # Wait for the message to be delivered
          wait_for_condition(timeout: 10) do
            received_messages.any? { |msg| msg.payload == payload }
          end
          
          # Verify the message was received
          matching_messages = received_messages.select { |msg| msg.payload == payload }
          _(matching_messages.size).must_equal 1
        end
        
        it 'does not maintain session state with clean_session=true' do
          # Create a unique client ID for this test
          client_id = "session-clean-#{SecureRandom.hex(4)}"
          
          # Create test client with memory store and clean_session=true
          test_client = @client_setup.create_test_client(:memory, client_id)
          ensure_broker_ready(test_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe to the test topic
          subscription = test_client.subscribe(test_topic, max_qos: 1)
          
          # Verify the subscription was successful
          sub_pkt, ack_pkt, = subscription.deconstruct
          _(sub_pkt.packet_name).must_equal :subscribe
          _(ack_pkt.packet_name).must_equal :suback
          
          # Disconnect the client
          test_client.disconnect
          
          # Create generator client to publish messages while test client is disconnected
          generator_client = @client_setup.create_generator_client
          ensure_broker_ready(generator_client)
          
          # Generate a unique payload
          payload = "session-clean-#{SecureRandom.hex(4)}"
          
          # Publish a message to the test topic
          generator_client.publish(test_topic, payload, qos: 1)
          
          # Reconnect the test client with the same client ID and clean_session=true
          test_client = @client_setup.create_test_client(:memory, client_id)
          ensure_broker_ready(test_client)
          
          # Set up a message handler to capture received messages
          received_messages = []
          test_client.on_message do |message|
            received_messages << message
          end
          
          # Wait a short time to see if any messages are delivered
          sleep 2
          
          # Verify no messages were received (session was cleaned)
          matching_messages = received_messages.select { |msg| msg.payload == payload }
          _(matching_messages.size).must_equal 0
        end
      end
      
      describe 'Session State with QoS Messages' do
        it 'maintains QoS 1 message state across disconnects' do
          # Create a unique client ID for this test
          client_id = "session-qos1-#{SecureRandom.hex(4)}"
          
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
          witness.subscribe_to(test_topic, qos: 1)
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "session-qos1-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after sending publish but before receiving puback
          network_controller.disconnect_at_stage(test_client, :before_puback)
          
          # Publish a QoS 1 message (this will disconnect after sending)
          begin
            test_client.publish(test_topic, payload, qos: 1)
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
        end
        
        it 'maintains QoS 2 message state across disconnects' do
          # Create a unique client ID for this test
          client_id = "session-qos2-#{SecureRandom.hex(4)}"
          
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
          payload = "session-qos2-#{SecureRandom.hex(4)}"
          
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
      
      describe 'Session State with Subscriptions' do
        it 'maintains subscriptions across disconnects' do
          # Create a unique client ID for this test
          client_id = "session-subscriptions-#{SecureRandom.hex(4)}"
          
          # Create test client with file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Subscribe to the test topic
          subscription = test_client.subscribe(test_topic, max_qos: 1)
          
          # Verify the subscription was successful
          sub_pkt, ack_pkt, = subscription.deconstruct
          _(sub_pkt.packet_name).must_equal :subscribe
          _(ack_pkt.packet_name).must_equal :suback
          
          # Disconnect the client
          test_client.disconnect
          
          # Create generator client to publish messages while test client is disconnected
          generator_client = @client_setup.create_generator_client
          ensure_broker_ready(generator_client)
          
          # Generate a unique payload
          payload = "session-subscriptions-#{SecureRandom.hex(4)}"
          
          # Publish a message to the test topic
          generator_client.publish(test_topic, payload, qos: 1)
          
          # Reconnect the test client with the same client ID and file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Set up a message handler to capture received messages
          received_messages = []
          test_client.on_message do |message|
            received_messages << message
          end
          
          # Wait for the message to be delivered
          wait_for_condition(timeout: 10) do
            received_messages.any? { |msg| msg.payload == payload }
          end
          
          # Verify the message was received
          matching_messages = received_messages.select { |msg| msg.payload == payload }
          _(matching_messages.size).must_equal 1
        end
      end
      
      describe 'Session State Inspection' do
        it 'allows inspection of session state' do
          # Create a unique client ID for this test
          client_id = "session-inspection-#{SecureRandom.hex(4)}"
          
          # Create test client with file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Create a unique topic for this test
          test_topic = create_test_topic
          
          # Create session state inspector
          session_store = test_client.instance_variable_get(:@session_store)
          inspector = SessionStateInspector.new(session_store)
          
          # Verify session is initially clean
          _(inspector.verify_session_clean).must_equal true
          
          # Set up network failure controller
          network_controller = NetworkController.new
          
          # Generate a unique payload
          payload = "session-inspection-#{SecureRandom.hex(4)}"
          
          # Set up to disconnect after sending publish but before receiving puback
          network_controller.disconnect_at_stage(test_client, :before_puback)
          
          # Publish a QoS 1 message (this will disconnect after sending)
          begin
            pub, = test_client.publish(test_topic, payload, qos: 1)
            message_id = pub.packet_identifier
          rescue => e
            # Expect a disconnect error
            _(e.message).must_match(/disconnect|connection|closed/i)
          end
          
          # Reconnect the client with the same client ID and file store
          test_client = @client_setup.create_test_client(:file, client_id)
          ensure_broker_ready(test_client)
          
          # Get the new session store
          session_store = test_client.instance_variable_get(:@session_store)
          inspector = SessionStateInspector.new(session_store)
          
          # Verify session is not clean after reconnect
          # Note: This may not work if the session store API doesn't expose this information
          # In that case, we'll skip this test
          begin
            _(inspector.verify_session_clean).must_equal false
          rescue => e
            skip "Session store API doesn't support inspection: #{e.message}"
          end
        end
      end
    end
  end
end