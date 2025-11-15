# frozen_string_literal: true

module MQTT
  module V5
    module TopicAlias
      # Least Recently Used replacement policy
      class LRUPolicy
        def initialize
          @topics = Set.new
        end

        # Alias any topic
        def aliasable?(_packet)
          true
        end

        # Evict the first entry in the Set (ie the least recently used)
        def evict(_topic, &)
          @topics.first
        end

        # Move the topic to the end of the Set (ie make it the most recently used)
        def alias_hit(topic)
          # Move the topic to the end of the set (relies on Set being ordered)
          @topics.delete(topic)
          @topics << topic
        end

        # Delete the evicted topic from the Set
        def alias_evicted(topic)
          @topics.delete(topic)
        end
      end
    end
  end
end
