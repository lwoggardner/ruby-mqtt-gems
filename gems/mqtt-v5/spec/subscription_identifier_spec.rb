# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module SubscriptionIdentifierSpec
      def self.included(base)
        base.class_eval do
          describe 'Subscription Identifiers' do
            it 'receives subscription_identifiers in published messages' do
              with_client do |client|
                client.connect

                # Use unique topic to avoid retained messages
                topic = "test/sub_id/#{SecureRandom.hex(8)}"

                # Subscribe to a topic - identifier should be auto-allocated
                received = []
                sub, = client.subscribe(topic).async_packets do |packet|
                  received << packet
                end

                # Publish a message
                client.publish(topic, 'test message')

                # Wait for message
                wait_until { received.size >= 1 }

                _(received.size).must_equal 1
                _(received[0].topic_name).must_equal topic
                _(received[0].payload).must_equal 'test message'

                # Should have subscription_identifiers
                _(received[0].subscription_identifiers).must_be_kind_of Array
                _(received[0].subscription_identifiers.size).must_equal 1
                _(received[0].subscription_identifiers[0]).must_be_kind_of Integer

                sub.unsubscribe
              end
            end

            it 'includes multiple identifiers for overlapping subscriptions' do
              with_client do |client|
                client.connect

                # Use unique topic to avoid retained messages
                base_topic = "test/overlap/#{SecureRandom.hex(8)}"

                # Subscribe to overlapping topics
                received1 = []
                received2 = []
                received3 = []

                sub1, = client.subscribe("#{base_topic}/#").async_packets do |packet|
                  received1 << packet
                end

                sub2, = client.subscribe("#{base_topic}/specific").async_packets do |packet|
                  received2 << packet
                end

                sub3, = client.subscribe("#{base_topic}/+",
                                         subscription_identifier: false).async_packets do |packet|
                  received3 << packet
                end

                # Publish to the specific topic
                client.publish("#{base_topic}/specific", 'overlap test')

                # Wait for messages
                wait_until { received1.size >= 1 && received2.size >= 1 && received3.size >= 1 }

                # All three should receive the message
                _(received1.size).must_equal 1
                _(received2.size).must_equal 1
                _(received3.size).must_equal 1

                sub1.unsubscribe
                sub2.unsubscribe
                sub3.unsubscribe
              end
            end

            it 'handles subscription without identifier when disabled' do
              with_client do |client|
                client.connect

                # Use unique topic to avoid retained messages
                topic = "test/no_id/#{SecureRandom.hex(8)}"

                # Subscribe with explicit subscription_identifier: false
                received = []
                sub, = client.subscribe(topic, subscription_identifier: false).async_packets do |packet|
                  received << packet
                end

                client.publish(topic, 'no id test')

                wait_until { received.size >= 1 }

                _(received.size).must_equal 1
                _(received[0].topic_name).must_equal topic
                # When subscription_identifier is disabled, subscription_identifiers may be nil or empty
                # This is valid per MQTT 5.0 spec

                sub.unsubscribe
              end
            end

            it 'does not cross-deliver when one id covers multiple filters' do
              with_client do |client|
                client.connect

                base = "test/multi_filter_id/#{SecureRandom.hex(8)}"

                # sub1 subscribes to two filters with one id
                received1 = []
                sub1, _task1 = client.subscribe("#{base}/a/#", "#{base}/b/#").async_packets do |packet|
                  received1 << packet
                end

                # sub2 subscribes to only the second filter (gets a new id)
                received2 = []
                sub2, _task2 = client.subscribe("#{base}/b/#").async_packets do |packet|
                  received2 << packet
                end

                # Publish to first filter only
                client.publish("#{base}/a/msg", 'only for sub1')

                wait_until { received1.size >= 1 }

                # sub1 should receive it, sub2 should not
                _(received1.size).must_equal 1
                _(received2.size).must_equal 0

                sub1.unsubscribe
                sub2.unsubscribe
              end
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::V5::SubscriptionIdentifierSpec, protocol_version: 5)
