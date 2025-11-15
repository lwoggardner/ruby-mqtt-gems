# frozen_string_literal: true

require_relative 'weighted_policy'

module MQTT
  module V5
    module TopicAlias
      # Scores topics by `hits * bytesize. Tracks hit counts for all topics
      class FrequencyWeightedPolicy
        include WeightedPolicy

        # The minimum topic size for a new topic to avoid O(n) scan of the topic list for each eviction
        attr_reader :min_topic_score

        def initialize
          super
          @hits = Hash.new(0)
        end

        # @!attribute [r] hits
        # @return [Hash<String,Integer>] (frozen) topics by the number of times they have been published to.
        def hits
          @hits.dup.freeze
        end

        # Delete topics from the map (ie because they won't be used again) and recalculate the minimum topic score.
        def clean!(*topics)
          topics.each { |t| @hits.delete(t) }
        end

        # Evict the topic with the lowest score, unless the new_topic is even lower.
        def evict(new_topic, &)
          super.tap { |victim| @hits[new_topic] += 1 unless victim }
        end

        # Record a hit for topic, check if lower than minimum score.
        def alias_hit(topic)
          @hits[topic] += 1
          super
        end

        private

        def topic_score(topic, new: false)
          (@hits[topic] + (new ? 1 : 0)) * topic.bytesize
        end
      end
    end
  end
end
