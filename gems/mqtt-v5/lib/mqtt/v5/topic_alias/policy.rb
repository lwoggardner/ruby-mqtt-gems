# frozen_string_literal: true

module MQTT
  module V5
    module TopicAlias
      # Defaults the policy interface for evicting topics from a full Cache
      # @abstract
      module Policy
        # @!method aliasable?(packet)
        # @abstract
        # @param [Packet::Publish] packet
        # @return [Boolean] whether the packet is eligible for aliasing

        # @method alias_evicted(topic)
        # Called when an alias is evicted
        # @param [String] topic The topic that was evicted.
        # @return [void]

        # @!method alias_hit(topic)
        # Called when an alias is used (including the first time a topic is aliased)
        # @param [String] topic
        # @return [void]

        # @!method evict(topic)
        # Choose a topic to evict
        # @param [String] topic The new topic that is looking for an alias
        # @yield()
        # @yieldreturn [Array<String>] the list of topics currently in the cache
        # @return [String, nil] topic to evict
        # @return [nil] evict nothing (ie do not alias the topic)
      end
    end
  end
end
