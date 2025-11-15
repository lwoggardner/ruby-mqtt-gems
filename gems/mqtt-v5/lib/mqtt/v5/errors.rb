# frozen_string_literal: true

module MQTT
  module V5
    # V5 response error - with reason code
    class ResponseError < MQTT::ResponseError
      class << self
        attr_reader :code
      end

      def initialize(message = nil)
        code = self.class.code || 0xff
        super(format '(0x%02<code>x) %<message>s', code:, message:)
      end
    end

    class UnknownReasonCode < ResponseError; end
  end
end
