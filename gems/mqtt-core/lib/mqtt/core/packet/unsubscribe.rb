# frozen_string_literal: true

module MQTT
  module Core
    module Packet
      # Common processing of UNSUBSCRIBE packets between MQTT versions
      module Unsubscribe
        # @!visibility private
        def validate
          return unless topic_filters

          raise ArgumentError, 'Must contain at least one topic filter' if topic_filters.empty?

          topic_filters.each do |tf|
            raise ArgumentError, 'Topic filter cannot be empty' if tf.to_s.empty?
          end
        end
      end
    end
  end
end
