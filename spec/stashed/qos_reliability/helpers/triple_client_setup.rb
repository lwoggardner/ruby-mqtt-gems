# frozen_string_literal: true

require 'mqtt/core'
require 'securerandom'

module MQTT
  module QoSReliability
    # Triple Client Test Setup
    # Creates and manages the three clients needed for comprehensive testing
    class TripleClientSetup
      attr_reader :broker_uri, :test_client, :generator_client, :witness_client

      def initialize(broker_uri)
        @broker_uri = broker_uri
        @clients = []
      end

      def create_test_client(store_type, client_id = nil)
        client_id ||= "test_client_#{SecureRandom.hex(4)}"
        
        session_store = case store_type
                        when :memory
                          MQTT::Core::Client.memory_store
                        when :file
                          tmp_dir = Dir.mktmpdir
                          MQTT::Core::Client.file_store(tmp_dir, expiry_interval: nil, client_id: client_id)
                        when :qos0
                          MQTT::Core::Client.qos0_store
                        else
                          raise ArgumentError, "Unknown store type: #{store_type}"
                        end
        
        @test_client = MQTT.open(
          broker_uri,
          client_id: client_id,
          session_store: session_store,
          connect_timeout: 5
        )
        
        @clients << @test_client
        @test_client
      end

      def create_generator_client
        client_id = "generator_client_#{SecureRandom.hex(4)}"
        
        @generator_client = MQTT.open(
          broker_uri,
          client_id: client_id,
          session_store: MQTT::Core::Client.memory_store,
          connect_timeout: 5
        )
        
        @clients << @generator_client
        @generator_client
      end

      def create_witness_client
        client_id = "witness_client_#{SecureRandom.hex(4)}"
        
        @witness_client = MQTT.open(
          broker_uri,
          client_id: client_id,
          session_store: MQTT::Core::Client.memory_store,
          connect_timeout: 5
        )
        
        @clients << @witness_client
        @witness_client
      end

      def cleanup_all
        @clients.each do |client|
          begin
            client.disconnect if client.connected?
          rescue => e
            puts "Error disconnecting client: #{e.message}"
          end
        end
        @clients = []
      end
    end
  end
end