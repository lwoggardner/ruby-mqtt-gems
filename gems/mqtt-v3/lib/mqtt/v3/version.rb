# frozen_string_literal: true

require 'mqtt/version'

module MQTT
  module V3
    VERSION = MQTT::VERSION
    MQTT_VERSION = Gem::Version.new('3.1.1')
    PROTOCOL_VERSION = 0x04
  end
end
