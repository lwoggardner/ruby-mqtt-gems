# frozen_string_literal: true

require 'mqtt/version'

module MQTT
  module V5
    VERSION = MQTT::VERSION
    MQTT_VERSION = Gem::Version.new('5.0')
    PROTOCOL_VERSION = 0x05
  end
end
