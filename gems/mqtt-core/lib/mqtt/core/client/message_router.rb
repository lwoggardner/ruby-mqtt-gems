# frozen_string_literal: true

require 'forwardable'

module MQTT
  module Core
    class Client
      # Routes incoming PUBLISH packets to matching subscriptions
      #
      # The core implementation tracks subscriptions by topic_filter. A {Trie} is used for matching wildcard filters
      # to topics.
      class MessageRouter
        # A trie (prefix tree) for efficiently matching MQTT topics against wildcard patterns.
        #
        # - '+' matches exactly one level (segment between '/')
        # - '#' matches zero or more remaining levels (must be last)
        class Trie
          # @!visibility private
          Node = Data.define(:children, :filter) do
            extend Forwardable

            # the filters set only ever has one entry, but it is possible that a level is created as an intermediate
            # entry
            def initialize(children: {}, filter: nil)
              super
            end

            def redundant?
              empty? && filter.nil?
            end

            def_delegators :children, :empty?, :[], :[]=, :delete, :include?
          end

          def initialize
            @root = Node.new
          end

          # @!visibility private

          # Add a topic filter to the trie
          # @param filter [String] MQTT topic filter (may contain '+' or '#')
          # @return [self]
          def add(filter)
            *parents, leaf = filter.split('/')
            parent_node = parents.reduce(@root) do |current, level|
              current[level] ||= Node.new
            end

            leaf_node = parent_node[leaf] ||= Node.new(filter: filter)
            parent_node[leaf] = Node.new(children: leaf_node.children, filter: filter) unless leaf_node.filter
            self
          end

          # Remove a topic filter from the trie
          # @param filter [String] MQTT topic filter to remove
          # @return [self]
          def remove(filter)
            levels = filter.split('/')
            remove_recursive(@root, levels, filter, 0)
            self
          end

          # Find all topic filters that match a given topic name
          # @param topic [String] fully-qualified MQTT topic name (no wildcards)
          # @return [Array<String>] matching topic filters
          def match(topic)
            [].tap { |filters| match_recursive(@root, topic.split('/'), 0, filters) }
          end

          # Check if the trie is empty
          # @return [Boolean]
          def empty?
            @root.children.empty?
          end

          private

          def remove_recursive(node, levels, filter, depth)
            level = levels[depth]
            child = node[level]

            return unless child

            if depth == levels.size - 1
              if child.empty?
                node.delete(level)
              elsif child.filter
                # Remove the filter, keep the children
                node[level] = Node.new(children: child.children)
              end
              return
            end

            remove_recursive(child, levels, filter, depth + 1)
            node.children.delete(level) if child.redundant?
          end

          def match_recursive(node, levels, depth, filters)
            # If we've matched all levels, collect this filter if it has one
            return filters << node.filter if depth == levels.size && node.filter

            # Keep going
            level = levels[depth]
            match_recursive(node[level], levels, depth + 1, filters) if node.include?(level)

            # Also single level '+'
            match_recursive(node['+'], levels, depth + 1, filters) if node.include?('+')

            filters << node['#'].filter if node.include?('#')
          end
        end

        include Logger
        include ConcurrentMonitor
        extend Forwardable

        def initialize(monitor:)
          @monitor = monitor.new_monitor
          @subs = Hash.new { |h, k| h[k] = Set.new }
          @topic_trie = Trie.new
        end

        # @!visibility private

        # Register subscriptions for routing before SUBSCRIBE is sent
        def register(subscription:, subscribe:)
          synchronize do
            register_sync(subscription:, subscribe:)
            (subscribe.subscribed_topic_filters - subscription.topic_filters.to_a).tap do |new_filters|
              subscription.topic_filters.merge(new_filters) if new_filters.any?
            end
          end
        end

        # Deregister a subscription (or specific filters) from routing (before UNSUBSCRIBE is sent)
        # Removes the subscription from @subs for the given filters (default: all registered filters).
        # @return [Array<String>] filters that are now inactive (no remaining subscriptions) and safe to UNSUBSCRIBE
        def deregister(*filters, subscription:)
          synchronize do
            filters = subscription.topic_filters.to_a if filters.empty?
            subscription.topic_filters.subtract(filters)
            deregister_filters(subscription, filters)
          end
        end

        # Route packet to matching subscriptions
        def route(packet)
          synchronize { subs_for(matching_filters(packet)) }
        end

        # return all subscriptions, then clear them
        def clear
          synchronize { all_subscriptions.tap { reset } }
        end

        private

        def reset
          @subs.clear
          @topic_trie = Trie.new
        end

        def subs_for(filters)
          filters.flat_map { |f| @subs.fetch(f, []).to_a }.uniq
        end

        # TODO: we used to check for duplicate filters which we don't need, but also warn about duplicated retained
        #    messages which is still a thing for OVERLAPPING filters.
        #    We might still need to warn about that or handled that in Subscription put
        #    (to skip messages with retain flag after seeing one without, OR warn here if RAP or RH is set and
        #    there are overlapping filters

        def register_sync(subscription:, subscribe:, use_trie: true)
          filters = subscribe.subscribed_topic_filters

          filters.each do |filter|
            @subs[filter] << subscription
            @topic_trie.add(filter) if use_trie && Subscription::Filters.wildcard_filter?(filter)
          end
        end

        # Remove subscription from given filters, clean up empty filters
        # @return [Array<String>] filters that are now inactive (no remaining subscriptions)
        def deregister_filters(subscription, filters)
          filters.each_with_object([]) do |filter, inactive|
            next unless (subs_set = @subs[filter])

            subs_set.delete(subscription)
            next unless subs_set.empty?

            remove_filter(filter)
            inactive << filter
          end
        end

        # called by: deregister when there sre no remaining subscriptions for a filter
        # called by: unsubscribe when successfully unsubscribed
        def remove_filter(filter)
          @subs.delete(filter)
          @topic_trie.remove(filter) if Client::Subscription::Filters.wildcard_filter?(filter)
        end

        def matching_filters(pkt)
          topic = pkt.topic_name
          [topic, *@topic_trie.match(topic)]
        end

        def all_subscriptions
          @subs.values.flat_map(&:to_a).uniq
        end
      end
    end
  end
end
