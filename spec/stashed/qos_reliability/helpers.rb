# frozen_string_literal: true

require_relative 'helpers/triple_client_setup'
require_relative 'helpers/message_generator'
require_relative 'helpers/packet_witness'
require_relative 'helpers/network_controller'
require_relative 'helpers/crash_simulator'
require_relative 'helpers/qo_s_flow_verifier'
require_relative 'helpers/session_state_inspector'

module MQTT
  module QoSReliability
    module TestHelpers
      # Helper method to create a unique topic for testing
      def create_test_topic(prefix = 'ruby_mqtt_qos_test')
        "#{prefix}/#{SecureRandom.hex(8)}"
      end

      # Helper method to wait for a condition with timeout
      def wait_for_condition(timeout: 5, delay: 0.1, &condition)
        start_time = Time.now
        
        while (Time.now - start_time) < timeout
          return true if condition.call
          sleep delay
        end
        
        false
      end

      # Helper method to ensure the broker is ready
      def ensure_broker_ready(client, timeout: 5)
        wait_for_condition(timeout: timeout) do
          client.connected?
        end
      end
    end
  end
end