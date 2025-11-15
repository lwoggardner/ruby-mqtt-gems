# frozen_string_literal: true

require 'async'
require_relative '../client'

module MQTT
  module V3
    module Async
      # An Async {MQTT::Core::Client} for MQTT 5.0
      class Client < MQTT::V3::Client
        class << self
          # Create a new {Client}
          def open(*io_args, **run_args, &)
            unless block_given? || ::Async::Task.current?
              raise MQTT::Error, 'async open requires a block or to be running within the async reactor'
            end

            super
          end

          def mqtt_monitor
            async_monitor
          end
        end
      end
    end
  end
end
