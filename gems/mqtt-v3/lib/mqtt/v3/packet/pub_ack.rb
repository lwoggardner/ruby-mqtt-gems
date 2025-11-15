# frozen_string_literal: true

require_relative '../packet'
require_relative 'ack_success'
module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PUBACK packet
      #
      # QoS 1 acknowledgement sent by broker in response to a PUBLISH packet.
      #
      # @see Core::Client#publish
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718043 MQTT 3.1.1 Spec §3.4
      class PubAck
        include Packet

        fixed(4)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBLISH packet (receive only)

        variable(packet_identifier: :int16)

        include AckSuccess
      end
    end
  end
end
