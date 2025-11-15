# frozen_string_literal: true

module MQTT
  module V5
    module TopicAlias
      # Base module for evicting {Policy} based on a minimum topic score
      module WeightedPolicy
        def initialize
          @min_topic_score = 0
        end

        # Aliases everything
        def aliasable?(_packet)
          true
        end

        # Evict the topic with the lowest score, unless the new_topic is even lower.
        def evict(new_topic, &topics)
          new_topic_score = topic_score(new_topic, new: true)

          return nil unless new_topic_score >= @min_topic_score

          victim = topics.call.min_by { |t| topic_score(t) }
          @min_topic_score = topic_score(victim)
          return victim if new_topic_score >= @min_topic_score

          nil
        end

        # Record a hit for topic, check if lower than minimum score.
        def alias_hit(topic)
          @min_topic_score = [topic_score(topic), @min_topic_score].min
        end

        # Does nothing on eviction.
        def alias_evicted(_topic)
          # does not change scores
        end

        # @!method topic_score(topic, new: false)
        # @abstract
        # @param topic [String]
        # @param new [Boolean] whether the topic is new (ie has not been aliased before)
        # @return [Integer] the score of the topic
      end
    end
  end
end
