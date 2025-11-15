# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/unsubscribe'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 UNSUBSCRIBE packet
      #
      # Sent by client to unsubscribe from one or more topic filters.
      #
      # @see Core::Client::Subscription#unsubscribe
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901179 MQTT 5.0 Spec §3.10
      class Unsubscribe
        include Packet
        include Core::Packet::Unsubscribe

        fixed(10, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for matching with UNSUBACK (managed automatically by session)

        # @!group Properties

        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        # @!attribute [r] topic_filters
        #   @return [Array<String<UTF8>>] list of topic filters to unsubscribe from

        variable(
          packet_identifier: :int16,
          properties:
        )
        payload(
          topic_filters: list(:utf8string)
        )

        def apply_data(data)
          @ignore_failed = data.delete(:ignore_failed) { false }
          @ignore_no_subscription = data.delete(:ignore_no_subscription) { true }
          super
        end

        # @return [Hash<String,Symbol>]
        #   Map of topic_filter to ack status
        #   * :success - subscription existed and was unsubscribed from the server
        #   * :no_subscription - subscription did not exist on the server
        #   * :failed - subscription failed to unsubscribe
        def filter_status(unsuback)
          topic_filters.zip(unsuback.reason_codes).to_h { |tf, rc| [tf, classify(rc)] }
        end

        # @return [Array<String>]
        def unsubscribed_topic_filters(unsuback = nil)
          return topic_filters unless unsuback

          topic_filters.zip(unsuback.reason_codes).filter_map { |tf, rc| tf unless failed?(rc) }
        end

        # Version dependent partition topic_filters into success and failures
        #
        # Attributes @ignore_no_subscription and @ignore_failed can control whether these statuses are considered
        # successful or not.
        # @return [Array<Hash<String,Symbol>>] pair of Maps as per #filter_status
        def partition_success(unsuback)
          filter_status(unsuback).partition { |(_tf, ack_status)| ack_success?(ack_status) }.map(&:to_h)
        end

        def success!(unsuback)
          _, failed = partition_success(unsuback)

          raise UnsubscribeError, failed unless failed.empty?

          self
        end

        private

        def failed?(reason_code)
          ReasonCode.failed?(reason_code)
        end

        def classify(reason_code)
          if failed?(reason_code)
            :failed
          elsif reason_code == 0x17
            :no_subscription
          else
            :success
          end
        end

        def ack_success?(ack_status)
          case ack_status
          when :success
            true
          when :no_subscription
            @ignore_no_subscription
          when :failed
            @ignore_failed
          else
            false
          end
        end
      end
    end
  end
end
