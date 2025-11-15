# frozen_string_literal: true

require_relative '../packet'
require_relative 'ack_success'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PUBREL packet
      #
      # QoS 2 publish release (part 2) sent by client in response to a PUBREC packet.
      #
      # @see Core::Client#publish
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718053 MQTT 3.1.1 Spec §3.6
      class PubRel
        include Packet

        fixed(6, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBREC packet (receive only)

        variable(packet_identifier: :int16)

        include AckSuccess
      end
    end
  end
end
