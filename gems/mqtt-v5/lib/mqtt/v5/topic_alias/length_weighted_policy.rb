# frozen_string_literal: true

require_relative 'weighted_policy'

module MQTT
  module V5
    module TopicAlias
      # Minimum length policy - only aliases topics above a minimum size, evicts shortest
      class LengthWeightedPolicy
        include WeightedPolicy

        private

        def topic_score(topic, **)
          topic.bytesize
        end
      end
    end
  end
end
