# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PINGRESP packet
      #
      # Sent by broker in response to a PINGREQ packet.
      #
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901200 MQTT 5.0 Spec §3.13
      class PingResp
        include Packet

        fixed(13)
      end
    end
  end
end
