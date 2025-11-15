# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V3
    module Packet
      class SubscriptionFailed < MQTT::V3::ResponseError; end

      # MQTT 3.1.1 SUBACK packet
      #
      # Subscription acknowledgement sent by broker in response to a SUBSCRIBE packet.
      #
      # @see Core::Client#subscribe
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718068 MQTT 3.1.1 Spec §3.9
      class SubAck
        include Packet

        fixed(9)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the SUBSCRIBE packet (receive only)

        # @!attribute [r] return_codes
        #   @return [Array<Integer>]
        #   return code for each subscription:
        #
        #   - `0x00` Granted QoS 0
        #   - `0x01` Granted QoS 1
        #   - `0x02` Granted QoS 2
        #   - `0x80` Failure

        variable(packet_identifier: :int16)
        payload(return_codes: list(:int8))

        RETURN_CODES = {
          0x00 => 'Granted QoS 0',
          0x01 => 'Granted QoS 1',
          0x02 => 'Granted QoS 2',
          0x80 => 'Failure'
        }.freeze
      end
    end
  end
end
