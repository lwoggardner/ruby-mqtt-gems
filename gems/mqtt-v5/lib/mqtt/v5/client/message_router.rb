# frozen_string_literal: true

module MQTT
  module V5
    class Client < Core::Client
      # Routes via subscription identifiers when available
      #
      # Subscription Identifiers are generally automatically allocated, and used for all subscriptions. Where
      # an identifier is not available, or explicitly not used, falls back to populating the
      # {Core::Client::MessageRouter::Trie}
      class MessageRouter < Core::Client::MessageRouter
        # Manages subscription identifiers for MQTT 5.0 clients
        class SubscriptionIds
          # Maximum subscription identifier value per MQTT 5.0 spec
          MAX_IDENTIFIER = 268_435_455 # 0xFFFFFFF

          # The full range available for id allocation
          FULL_RANGE = 1..MAX_IDENTIFIER

          # @!visibility private
          attr_reader :user_range, :strict

          # @overload initialize(range: FULL_RANGE, strict: false)
          #  @param range [Range|nil] the range for auto identifier allocation with {RangeSet} used to track
          #   free / available ids.
          #
          #   - Entries between 1 and the beginning of this range can be used for manual identifier assignment, or
          #     a nil range means the {FULL_RANGE} can be used for manual assignment
          # @overload initialize(allocator: RangeSet.new(FULL_RANGE), strict: false)
          #  @param allocator [RangeAllocator] a custom range allocator
          # @param strict [Boolean] (false) Controls message delivery for subscriptions that do NOT have an identifier
          #   - false: All messages matching the topic are sent to these subscriptions, regardless of whether the
          #     message from the broker contains subscription identifiers
          #   - true: Only messages that do not contain any identifiers are sent on to these subscriptions
          def initialize(range: FULL_RANGE, allocator: nil, strict: false)
            @allocator = allocator
            @allocator ||= RangeSet.new(range, within: FULL_RANGE) if range
            @allocator&.validate!(within: FULL_RANGE)
            @user_range = allocator ? 1...allocator.range.begin : FULL_RANGE
            @strict = strict
            @filters_by_id = {} # id → Set<filter>
            @ids_by_filter = {} # filter → Array<id|nil> (ordered, last = current)
          end

          # @!visibility private

          # Allocate a subscription identifier
          # @return [Integer, nil] allocated identifier, or nil if exhausted
          def allocate_identifier
            @allocator&.next
          end

          def reset
            @allocator&.reset
            @filters_by_id.clear
            @ids_by_filter.clear
          end

          # Track identifier → filters mapping
          # @param id [Integer] subscription identifier
          # @param filters [Array<String>] topic filters for this identifier
          def track_identifier(id, *filters)
            raise Error, "Subscription Identifier(#{id}) already in use!" if @filters_by_id.include?(id)

            @filters_by_id[id] = Set.new(filters)
            filters.each { |f| (@ids_by_filter[f] ||= []) << id }
          end

          # @return [Array<String>] filters for the given ids, used for routing
          def filters_for_ids(ids)
            ids.flat_map { |id| @filters_by_id.fetch(id, []).to_a }
          end

          def strict?
            @strict
          end

          # @return [Boolean] true if the filter's current (last) entry is an id (not nil)
          def tracked?(filter)
            (ids = @ids_by_filter[filter]) && !ids.last.nil?
          end

          # Track that a filter was subscribed without an id
          def track_no_id(*filters)
            filters.each { |f| (@ids_by_filter[f] ||= []) << nil }
          end

          # Flush stale id→filter mappings when a message confirms the current id for a filter
          def flush_stale(ids, matched_filters)
            matched_filters.each do |f|
              entries = @ids_by_filter[f]
              next unless entries && entries.size > 1 && ids.include?(entries.last)

              stale = entries.shift(entries.size - 1)
              stale.compact.each do |old_id|
                @filters_by_id[old_id]&.delete(f)
                free_id(old_id) if @filters_by_id[old_id] && @filters_by_id[old_id].empty?
              end
            end
          end

          # Release filters from their ids, freeing ids that have no remaining filters
          def release_filters(*filters)
            ids_to_check = Set.new
            filters.each do |f|
              ids = @ids_by_filter.delete(f)
              next unless ids

              ids.compact.each do |id|
                @filters_by_id[id]&.delete(f)
                ids_to_check << id
              end
            end
            ids_to_check.each do |id|
              free_id(id) if @filters_by_id[id] && @filters_by_id[id].empty?
            end
          end

          private

          def free_id(id)
            @filters_by_id.delete(id)
            @allocator&.free(id) unless @user_range.cover?(id)
          end
        end

        # @!attribute [r] subscription_ids
        #  @return [SubscriptionIds]
        attr_accessor :subscription_ids

        # @!visibility private
        def allocate_identifier(required: false)
          id = synchronize { subscription_ids&.allocate_identifier }
          return id unless required && !id

          raise Error, 'Subscription identifier not available'
        end

        # @!visibility private
        def validate_user_identifier(id)
          raise Error, 'Subscription identifiers not configured' unless subscription_ids

          return if subscription_ids.user_range.cover?(id)

          raise Error,
                "Subscription identifier(#{id}) out of range: #{subscription_ids.user_range}"
        end

        # @!visibility private
        def connected!(connack)
          self.subscription_ids = nil unless connack.subscription_identifiers_available?
        end

        # Route packet to matching subscriptions — override to use identifier-based routing
        def route(packet)
          if subscription_ids && (ids = packet.subscription_identifiers)&.any?
            id_subs = route_with_ids(ids, packet)
            subscription_ids.strict? ? id_subs : (id_subs + super).uniq
          elsif subscription_ids&.strict?
            synchronize { subs_for(matching_filters(packet).reject { |f| subscription_ids.tracked?(f) }) }
          else
            super
          end
        end

        private

        def route_with_ids(ids, packet)
          id_filters = subscription_ids.filters_for_ids(ids)
          if id_filters.size > 1
            id_filters.select! { |f| Core::Client::Subscription::Filters.match_topic?(packet.topic_name, [f]) }
          end
          synchronize { subs_for(id_filters).tap { subscription_ids.flush_stale(ids, id_filters) } }
        end

        def reset
          super
          subscription_ids&.reset
        end

        def register_sync(subscription:, subscribe:)
          id = subscribe.respond_to?(:subscription_identifier) ? subscribe.subscription_identifier : nil
          filters = subscribe.subscribed_topic_filters
          # When there IS an id, don't populate the trie (broker routes by id)
          super(subscription:, subscribe:, use_trie: !id)
          subscription_ids&.track_identifier(id, *filters) if id
          subscription_ids&.track_no_id(*filters) unless id
        end

        # Override to also release identifier mappings for deregistered filters
        def deregister_filters(subscription, filters)
          inactive = super
          subscription_ids&.release_filters(*inactive)
          inactive
        end
      end
    end
  end
end
