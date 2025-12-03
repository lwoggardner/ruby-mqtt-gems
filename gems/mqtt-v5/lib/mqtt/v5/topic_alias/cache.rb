# frozen_string_literal: true

module MQTT
  module V5
    module TopicAlias
      # Bidirectional topic<->alias storage
      # @!visibility private
      class Cache
        # @!visibility private
        attr_reader :max_assigned

        # @return [Integer] maximum number of topic aliases this cache can hold
        attr_reader :max

        # @return [Integer] the total size of topic_names held in this cache
        attr_reader :cached_bytes

        def self.create(max)
          max&.positive? ? new(max: max) : nil
        end

        def initialize(max:)
          @max = max
          @aliases = {} # String keys: topic => alias, Integer keys: alias => topic
          @max_assigned = 0
          @cached_bytes = 0
          @available = []
        end

        # Resolve topic to alias or alias to topic
        # @param topic_or_alias [String, Integer]
        # @return [Integer, String, nil]
        def resolve(topic_or_alias)
          @aliases[topic_or_alias]
        end

        # @!visibility private
        def assign
          return false if full?

          @available.pop || (@max_assigned += 1)
        end

        # @return [Boolean] true if there are {#max} entries in the map
        def full?
          @available.empty? && max_assigned >= max
        end

        # @return [Integer] number of entries in the map
        def size
          @max_assigned - @available.size
        end

        # @!visibility private
        # Add bidirectional mapping
        # @param alias_id [Integer]
        # @param topic [String]
        def add(alias_id, topic)
          raise ProtocolError, "AliasId (#{alias_id}) must be between 1 and #{max}" unless alias_id.between?(1, max)

          @max_assigned = alias_id if alias_id > @max_assigned
          @cached_bytes += topic.bytesize - (@aliases[alias_id]&.bytesize || 0)
          @aliases[alias_id] = topic
          @aliases[topic] = alias_id
        end

        # @!visibility private
        # Explicitly Remove a topic (a previously aliased topic later explicitly set to use alias false)
        # @param topic [String]
        # rubocop:disable Naming/PredicateMethod
        def remove(topic)
          alias_id = @aliases.delete(topic)
          return false unless alias_id

          @available.push(alias_id)
          @cached_bytes -= @aliases.delete(alias_id)&.bytesize || 0
          true
        end
        # rubocop:enable Naming/PredicateMethod

        def topics
          @aliases.keys.select { |k| k.is_a?(String) }
        end
      end
    end
  end
end
