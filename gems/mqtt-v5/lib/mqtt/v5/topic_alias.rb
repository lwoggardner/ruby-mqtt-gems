# frozen_string_literal: true

require_relative 'topic_alias/cache'
require_relative 'topic_alias/policy'
require_relative 'topic_alias/lru_policy'
require_relative 'topic_alias/frequency_weighted_policy'
require_relative 'topic_alias/length_weighted_policy'
require_relative 'topic_alias/manager'

module MQTT
  module V5
    # Topic Alias support for MQTT 5.0
    #
    # Provides bidirectional topic aliasing for Clients/Servers to reduce bandwidth usage by replacing
    # repetitive topic names with small integer identifiers.
    #
    # @example Basic usage with default LRUPolicy policy
    #   alias_manager = MQTT::V5::TopicAlias::Manager.new(send_maximum: 100)
    #
    # @example Custom policy
    #   policy = MQTT::V5::TopicAlias::FrequencyWeightedPolicy.new
    #   alias_manager = MQTT::V5::TopicAlias::Manager.new(send_maximum: 50, policy: policy )
    # @see Client#topic_aliases
    module TopicAlias
    end
  end
end
