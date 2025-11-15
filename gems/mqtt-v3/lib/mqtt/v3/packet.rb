# frozen_string_literal: true

require 'mqtt/core/packet'
require_relative 'version'
require_relative 'errors'

module MQTT
  module V3
    # MQTT 5.0 base packet definition
    #
    # Inherited constants (referenced via self:: in {MQTT::Core::Packet}
    module Packet
      VALUE_TYPES = {
        utf8string: MQTT::Core::Type::UTF8String,
        binary: MQTT::Core::Type::Binary,
        remaining: MQTT::Core::Type::Remaining,
        int8: MQTT::Core::Type::Int8,
        int16: MQTT::Core::Type::Int16,
        int32: MQTT::Core::Type::Int32,
        intvar: MQTT::Core::Type::VarInt,
        varint: MQTT::Core::Type::VarInt,
        boolean: MQTT::Core::Type::BooleanByte
      }.freeze

      PROPERTY_TYPES = [].freeze

      # rubocop:disable Style/MutableConstant
      PACKET_TYPES = {}
      # rubocop:enable Style/MutableConstant

      extend MQTT::Core::Packet::ModuleMethods

      def self.included(mod)
        mod.include(MQTT::Core::Packet)
      end
    end
  end
end
