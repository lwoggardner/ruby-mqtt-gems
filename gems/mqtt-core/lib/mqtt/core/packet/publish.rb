# frozen_string_literal: true

module MQTT
  module Core
    module Packet
      # Common processing of PUBLISH packets between MQTT versions
      module Publish
        # Deconstruct message for subscription enumeration
        # @yield [topic, payload, attributes] optional block to yield deconstructed values
        # @return [Array<String, String, Hash>] topic, payload, attributes when no block given
        # @return [Object] block result when block given
        def deconstruct_message(&)
          block_given? ? yield(topic, payload, **to_h) : [topic, payload, to_h]
        end

        def to_s
          "#{super}(#{topic})"
        end

        # @!visibility private
        def success!(ack)
          return true if qos.zero?

          ack&.success! || raise(ProtocolError, 'No ACK')
        end

        # @!visibility private
        def topic_alias
          nil
        end

        # @!visibility private
        def defaults
          super.merge!(qos: 0)
        end

        # @!visibility private
        def validate
          raise ArgumentError, 'QoS must be 0, 1, or 2' unless (0..2).include?(qos)
          raise ArgumentError, 'Topic name cannot be empty' if !topic_alias && topic_name.to_s.empty?
          raise ArgumentError, 'Topic name cannot contain wildcards' if topic_name.to_s.match?(/[#+]/)

          return unless qos.zero? && (packet_identifier || 0).positive?

          raise MQTT::ProtocolError, 'Must not have packet id for QOS 0'
        end
      end
    end
  end
end
