# frozen_string_literal: true

module MQTT
  module Core
    module Packet
      # Common processing of CONNECT packets between MQTT versions
      module Connect
        # @!visibility private
        def apply_overrides(data)
          super
          data[:connect_flags] ||= {}
          data[:connect_flags][:will_flag] = !(will_topic || '').empty?
          data[:connect_flags][:username_flag] = !username.nil?
          data[:connect_flags][:password_flag] = !password.nil?
        end

        # @!visibility private
        def validate
          will_flag ? validate_will_set : validate_will_not_set
        end

        # @!visibility private
        def validate_will_set
          raise ArgumentError, 'Will (flag:true) topic must be set' if (will_topic || '').empty?
          raise ArgumentError, 'Will (flag:true) topic must not contain wildcards' if will_topic.match?(/[#+]/)
          raise ArgumentError, 'Will (flag:true) QoS must be 0, 1, or 2' unless (0..2).include?(will_qos)
        end

        # @!visibility private
        def validate_will_not_set
          raise ArgumentError, 'Will (flag:false) topic must not be set' unless (will_topic || '').empty?
          raise ArgumentError, 'Will (flag:false) payload must not be set' unless (will_payload || '').empty?
          raise ArgumentError, 'Will (flag:false) QoS must be 0' unless (will_qos || 0).zero?
          raise ArgumentError, 'Will (flag:false) retain must be false' if will_retain
        end
      end
    end
  end
end
