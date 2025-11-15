# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PINGREQ packet
      #
      # Sent by client to keep the connection alive.
      #
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901195 MQTT 5.0 Spec §3.12
      class PingReq
        include Packet

        fixed(12)
      end
    end
  end
end
