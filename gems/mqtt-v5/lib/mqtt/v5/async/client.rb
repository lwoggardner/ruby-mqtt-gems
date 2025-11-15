# frozen_string_literal: true

require 'async'
require_relative '../client'

module MQTT
  module V5
    module Async
      # An Async {MQTT::Core::Client} for MQTT 5.0
      class Client < MQTT::V5::Client
        class << self
          # Create a new {Client}
          def open(*io_args, **run_args, &)
            raise FiberError, 'No async reactor' unless block_given? || ::Async::Task.current?

            super
          end

          # @!visibility private
          def mqtt_monitor
            async_monitor
          end
        end
      end
    end
  end
end
