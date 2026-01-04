# frozen_string_literal: true

require_relative '../../../spec/spec_helper'

module MQTT
  module V5
    module SpecHelper
      class << self
        include MQTT::SpecHelper::ClassMethods
        def with_client_classes(&block)
          [
            { protocol: 5, async: false, class_name: 'MQTT::V5::Client', skip: false },
            { protocol: 5, async: true, class_name: 'MQTT::V5::Async::Client', skip: false },
          ].reject { |opts| opts[:skip] }
           .kw_each do |class_name:, protocol:, async:, **|
            require "mqtt/v#{protocol}"
            require "mqtt/v#{protocol}/async/client" if async
            describe class_name do
              let(:retry_strategy) { nil }
              let(:client_class) { Object.const_get(class_name) }
              let(:monitor_class) { Object.const_get("#{async ? 'Async' : 'Thread'}::Monitor") }
              let(:client_class_opts) { { protocol_version: protocol, retry_strategy:,  async:, session_store: } }
              instance_eval(&block)
            end
          end
        end
      end
    end
  end
end
