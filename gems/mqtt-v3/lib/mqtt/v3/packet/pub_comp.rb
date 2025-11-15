# frozen_string_literal: true

require_relative '../packet'
require_relative 'ack_success'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PUBCOMP packet
      #
      # QoS 2 publish complete (part 3) sent by broker in response to a PUBREL packet.
      #
      # @see Core::Client#publish
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718058 MQTT 3.1.1 Spec §3.7
      class PubComp
        include Packet

        fixed(7)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBREL packet (receive only)

        variable(packet_identifier: :int16)

        include AckSuccess
      end
    end
  end
end
