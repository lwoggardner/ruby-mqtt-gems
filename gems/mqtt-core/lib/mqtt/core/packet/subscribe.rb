# frozen_string_literal: true

module MQTT
  module Core
    module Packet
      # Common processing of SUBSCRIBE packets between MQTT versions
      module Subscribe
        # @!attribute [r] ignore_qos_limited
        #   @return [Boolean] treat qos_limited topic_filters as successful - default (true)

        # @!attribute [r] ignore_failed
        #   @return [Boolean] treat failed topic_filters as successful - default (false)

        def defaults
          { ignore_failed: false, ignore_qos_limited: false }
        end

        def apply_data(data)
          @ignore_failed = data.delete(:ignore_failed) if data.include?(:ignore_failed)
          @ignore_qos_limited = data.delete(:ignore_qos_limited) if data.include?(:ignore_qos_limited)

          if data.include?(:topic_filters)
            tf_defaults = self.class::TOPIC_FILTER_OPTIONS.each_with_object({}) do |k, d|
              d[k] = data.delete(k) if data.include?(k)
            end
            max_qos = data.delete(:max_qos) || data.delete(:requested_qos) || 0
            map_topic_filters(data[:topic_filters], max_qos, **tf_defaults)
          end

          super
        end

        # @!visibility private
        def validate
          return unless topic_filters

          raise ArgumentError, 'Must contain at least one topic filter' if topic_filters.empty?

          topic_filters.each do |tf|
            filter = case tf
                     when String then tf
                     when Hash then tf[:topic_filter]
                     else tf.topic_filter
                     end
            raise ArgumentError, 'Topic filter cannot be empty' if filter.to_s.empty?
          end
        end

        def apply_overrides(data)
          super
          topic_filters = data.fetch(:topic_filters, [])
          @wildcard_topics, @fully_qualified_topics = topic_filters.map(&:topic_filter).partition do |t|
            contains_wildcard?(t)
          end
          @max_qos = topic_filters.map(&:max_qos).max
        end

        attr_reader :fully_qualified_topics, :wildcard_topics, :max_qos

        def match?(publish_packet)
          match_topic?(publish_packet.topic_name)
        end

        def ===(other)
          case other
          when Packet
            match?(other)
          when String
            match_topic?(other)
          else
            false
          end
        end

        def match_topic?(topic_name)
          match_fully_qualified_topic?(topic_name) || match_wildcard_topic?(topic_name)
        end

        def match_fully_qualified_topic?(topic_name)
          fully_qualified_topics.include?(topic_name)
        end

        def match_wildcard_topic?(topic_name)
          wildcard_topics.any? { |wt| wc_match?(topic_name, wt) }
        end

        def contains_wildcard?(topic)
          topic =~ /[#+]/
        end

        def wc_match?(topic, wc_topic)
          wc_parts = wc_topic.split('/')
          topic_parts = topic.split('/')

          wc_parts.zip(topic_parts).all? do |(wc, t)|
            return true if wc == '#'
            return false if t.nil?

            wc == '+' || t == wc
          end && (wc_parts.last == '#' || topic_parts.size == wc_parts.size)
        end

        # Map filter expressions to suback status
        #
        #   * :`success` - subscription successful with requested QOS
        #   * :`qos_limited` - subscription accepted but acknowledged QOS is less than the requested QOS
        #   * :`failed` - subscription failed
        # @param [Packet] suback the SUBACK packet
        # @return [Hash<String,Symbol>] map of topic filter to status
        def filter_status(suback)
          topic_filters.zip(suback.return_codes).to_h { |tf, rc| [tf.topic_filter, classify(tf, rc)] }
        end

        # Version dependent partition topic_filters into success and failures
        #
        # Attributes {#ignore_qos_limited} and {#ignore_failed} can control whether these statuses are considered
        # successful or not.
        # @return <Array<Hash<String,Symbol>> pair of Maps as per #filter_status
        def partition_success(suback)
          filter_status(suback).partition { |(_tf, ack_status)| ack_success?(ack_status) }.map(&:to_h)
        end

        def success!(suback)
          success, failed = partition_success(suback)

          raise SubscribeError, failed unless failed.empty?

          success
        end

        # @return [Array<TopicFilter>]
        def subscribed_topic_filter_requests(suback = nil)
          return topic_filters unless suback

          topic_filters.zip(suback.return_codes).filter_map { |tf, rc| tf unless failed?(rc) }
        end

        alias resubscribe_topic_filters subscribed_topic_filter_requests
        alias unsubscribe_topic_filters subscribed_topic_filter_requests

        # @return [Array<String>]
        def subscribed_topic_filters(suback = nil)
          subscribed_topic_filter_requests(suback).map(&:topic_filter)
        end

        def unsubscribe_params(suback = nil)
          { topic_filters: subscribed_topic_filters(suback) }
        end

        private

        def map_topic_filters(topic_filters, max_qos, **defaults)
          topic_filters.map! do |tf|
            (tf.is_a?(String) ? { topic_filter: tf } : tf).tap do |tf_hash|
              raise ArgumentError, 'topic filter must be a String or Hash<Symbol>' unless tf_hash.is_a?(Hash)

              tf_hash[self.class::MAX_QOS_FIELD] ||= max_qos
              tf_hash.merge!(defaults) { |_k, from, _default| from }
              tf_hash.compact!
            end
          end
        end

        def failed?(return_code)
          return_code >= 0x80
        end

        def ack_success?(ack_status)
          case ack_status
          when :success
            true
          when :qos_limited
            @ignore_qos_limited
          when :failed
            @ignore_failed
          else
            false
          end
        end

        def classify(topic_filter, return_code)
          if failed?(return_code)
            :failed
          elsif return_code < topic_filter.requested_qos
            :qos_limited
          else
            :success
          end
        end
      end
    end
  end
end
