# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PINGRESP packet
      #
      # Sent by broker in response to a PINGREQ packet.
      #
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718086 MQTT 3.1.1 Spec §3.13
      class PingResp
        include Packet

        fixed(13)
      end
    end
  end
end
