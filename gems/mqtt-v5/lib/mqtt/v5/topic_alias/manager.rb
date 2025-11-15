# frozen_string_literal: true

require_relative 'cache'
require_relative 'lru_policy'

module MQTT
  module V5
    module TopicAlias
      # Manages topic aliases for a connection
      class Manager
        # maximum size of alias caches
        MAXIMUM_ALIAS_ID = 65_535

        # @return [Cache|nil] the incoming Cache
        attr_reader :incoming

        # @return [Cache|nil] the outgoing Cache
        attr_reader :outgoing

        # @return [Policy] the policy used to manage the outgoing Cache
        attr_reader :policy

        # Topic Alias Management
        #
        # Outgoing aliasing upper limit and replacement policy is configured by properties to {#initialize}
        #
        # For a Client...
        #   - Outgoing limit is further restricted by the CONNACK response from the Server.
        #   - Incoming limit is configured in the CONNECT packet. Records alias information as received from Server.
        #
        # For a Server...
        #   - Outgoing limit is further restricted by the CONNECT packet received from the Client.
        #   - Incoming limit is configured in the CONNACK packet. Records alias information as received from Client.
        #
        # @param [Integer|nil] send_maximum
        #   maximum number of topic aliases to hold for outgoing PUBLISH packets
        #
        #  - `nil` will mean the value is determined only by the response from the other side
        #  - `0` (default) disables outgoing aliasing regardless of what the other side will accept
        #
        # @param  [Policy|nil] policy replacement policy for evicting topics from the outgoing cache when
        #     it is full.
        #
        #  - `nil` will use {LRUPolicy} as the default policy
        #
        # @return [Manager]
        def initialize(send_maximum: 0, policy: nil)
          @configured_outgoing_maximum = send_maximum || MAXIMUM_ALIAS_ID
          @policy = policy
          @policy ||= LRUPolicy.new if @configured_outgoing_maximum.positive?
        end

        # @visibility private
        # Clear incoming alias cache
        #   - called from Client with CONNECT packet it will send to Server
        #   - called from Server with CONNACK packet it will send to Client
        def clear_incoming!(packet)
          @incoming = Cache.create(packet.topic_alias_maximum)
        end

        # @visibility private
        # Clear outgoing alias cache
        #    - called from Client with CONNACK packet received from Server
        #    - called from Server with CONNECT packet received from Client
        def clear_outgoing!(packet)
          max = [@configured_outgoing_maximum, packet.topic_alias_maximum || 0].min
          @outgoing = Cache.create(max)
        end

        # @visibility private
        # Process incoming PUBLISH packet - resolve alias and update packet
        # @param packet [Packet::Publish] incoming PUBLISH packet
        # @raise [ProtocolError] if alias exceeds the maximum or cannot be resolved
        def handle_incoming(packet)
          return unless packet.topic_alias&.positive?

          if (max = incoming&.max || 0) < packet.topic_alias
            raise TopicAliasInvalid, "#{packet.topic_alias} exceeds maximum #{max}"
          end

          if packet.topic_name.empty?
            resolved_topic = @incoming.resolve(packet.topic_alias)
            raise TopicAliasInvalid, "Unknown topic alias #{packet.topic_alias}" unless resolved_topic

            # override the empty topic name with the resolved topic
            packet.apply_alias(name: resolved_topic)
          else
            @incoming.add(packet.topic_alias, packet.topic_name)
          end
        end

        # Force removal of an outgoing topic from the alias cache. eg. because it is not going to be used any more.
        # @param [Array<String>] topics the topics to remove
        # @return [void]
        # @note Prefer sending `topic_alias: false` to {Client#publish} to indicate topics that should not be aliased
        def evict!(*topics)
          topics.each do |topic|
            @outgoing&.remove(topic) && @policy.alias_evicted(topic)
          end
        end

        # @visibility private
        # Get outgoing alias for topic (policy decides whether to alias and what to evict)
        def handle_outgoing(packet)
          return unless @outgoing && @policy&.aliasable?(packet)

          if (alias_id = @outgoing.resolve(packet.topic_name))
            return outgoing_alias_hit(alias_id, packet)
          end

          outgoing_alias_miss(packet)
        end

        private

        def outgoing_alias_hit(alias_id, packet)
          # We had one already, but we don't want to keep it any more (might as well use it now though)
          evict!(packet.topic_name) unless packet.assign_alias?

          @policy.alias_hit(packet.topic_name)
          # We've seen and sent this one before, just send the alias_id and an empty topic name
          packet.apply_alias(alias: alias_id, name: '')
        end

        def outgoing_alias_miss(packet)
          return unless packet.assign_alias? # We don't want to alias this topic

          alias_id = @outgoing.assign
          unless alias_id
            (evict = @policy.evict(packet.topic_name) { @outgoing.topics }) && evict!(evict)
            alias_id = @outgoing.assign
          end

          return unless alias_id # evicting did not result in an available alias

          @policy.alias_hit(packet.topic_name)
          @outgoing.add(alias_id, packet.topic_name)
          packet.apply_alias(alias: alias_id)
        end
      end
    end
  end
end
