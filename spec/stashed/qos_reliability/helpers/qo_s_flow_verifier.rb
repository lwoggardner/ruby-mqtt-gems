# frozen_string_literal: true

require 'timeout'

module MQTT
  module QoSReliability
    # QoS Flow Verifier - Validates QoS guarantees and flow completion
    class QoSFlowVerifier
      attr_reader :outgoing_messages, :incoming_messages, :completed_messages

      def initialize
        @outgoing_messages = {}
        @incoming_messages = {}
        @completed_messages = {}
        @received_payloads = Hash.new(0)
        @mutex = Mutex.new
      end

      # Track outgoing message for verification
      def track_outgoing_message(message_id, payload, qos)
        @mutex.synchronize do
          @outgoing_messages[message_id] = {
            payload: payload,
            qos: qos,
            timestamp: Time.now,
            state: :sent
          }
        end
      end

      # Track incoming message for verification
      def track_incoming_message(packet)
        return unless packet&.packet_name == :publish

        @mutex.synchronize do
          payload = packet.payload
          @received_payloads[payload] += 1
          
          if packet.qos > 0
            message_id = packet.packet_identifier
            @incoming_messages[message_id] = {
              payload: payload,
              qos: packet.qos,
              timestamp: Time.now,
              state: :received
            }
          end
        end
      end

      # Verify QoS 1 flow completion
      # Returns true if the message was acknowledged within timeout
      def verify_qos1_completion(message_id, timeout: 5)
        start_time = Time.now
        
        while (Time.now - start_time) < timeout
          @mutex.synchronize do
            if @outgoing_messages[message_id]&.dig(:state) == :completed
              return true
            end
          end
          sleep 0.1
        end
        
        false
      end

      # Verify QoS 2 flow completion
      # Returns true if the message completed the QoS 2 flow within timeout
      def verify_qos2_completion(message_id, timeout: 10)
        start_time = Time.now
        
        while (Time.now - start_time) < timeout
          @mutex.synchronize do
            if @outgoing_messages[message_id]&.dig(:state) == :completed
              return true
            end
          end
          sleep 0.1
        end
        
        false
      end

      # Verify exactly once delivery (QoS 2)
      # Returns true if the payload was received exactly once
      def verify_exactly_once_delivery(payload)
        @mutex.synchronize do
          @received_payloads[payload] == 1
        end
      end

      # Verify at least once delivery (QoS 1)
      # Returns true if the payload was received at least once
      def verify_at_least_once_delivery(payload)
        @mutex.synchronize do
          @received_payloads[payload] >= 1
        end
      end

      # Verify no duplicates for a specific payload
      # Returns true if the payload was received at most once
      def verify_no_duplicates(payload)
        @mutex.synchronize do
          @received_payloads[payload] <= 1
        end
      end

      # Returns the number of times the application received a specific payload
      def application_received_count(payload)
        @mutex.synchronize do
          @received_payloads[payload]
        end
      end

      # Returns true if the message flow is completed
      def message_completed?(message_id)
        @mutex.synchronize do
          @outgoing_messages[message_id]&.dig(:state) == :completed
        end
      end

      # Mark a message as completed (for internal use)
      def mark_message_completed(message_id)
        @mutex.synchronize do
          if @outgoing_messages[message_id]
            @outgoing_messages[message_id][:state] = :completed
            @completed_messages[message_id] = @outgoing_messages[message_id]
          end
        end
      end
    end
  end
end