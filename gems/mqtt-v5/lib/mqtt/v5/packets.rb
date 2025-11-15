# frozen_string_literal: true

# MQTT 5.0
module MQTT
  # MQTT 5.0 protocol implementation
  module V5
    require_relative 'packet/connect'
    require_relative 'packet/connack'
    require_relative 'packet/disconnect'
    require_relative 'packet/ping_req'
    require_relative 'packet/ping_resp'
    require_relative 'packet/publish'
    require_relative 'packet/pub_ack'
    require_relative 'packet/pub_rec'
    require_relative 'packet/pub_rel'
    require_relative 'packet/pub_comp'
    require_relative 'packet/subscribe'
    require_relative 'packet/sub_ack'
    require_relative 'packet/unsubscribe'
    require_relative 'packet/unsub_ack'
    require_relative 'packet/auth'

    MQTT::V5::Packet::PACKET_TYPES.freeze
  end
end
