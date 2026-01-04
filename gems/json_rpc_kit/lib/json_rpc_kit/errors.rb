# frozen_string_literal: true

require 'json'

module JsonRpcKit
  # JSON-RPC Error handling
  class Error < StandardError
    attr_reader :code, :data

    class << self
      # @!visibility private
      def raise_error(json_error)
        code, message, data = json_error.values_at(:code, :message, :data)

        error_class = ERROR_CODES.fetch(code, JsonRpcKit::Error)
        raise error_class.new(message, code: code, **data) if error_class <= JsonRpcKit::Error

        raise error_class, message
      end

      # @!visibility private
      def rescue_error(id, error)
        code = error.code if error.respond_to?(:code)
        code, = ERROR_CODES.detect { |_code, error_class| error.is_a?(error_class) } unless code.is_a?(Integer)
        data = error.data if error.respond_to?(:data)

        # If we did not find a code then this is some other kind of error, record it with Internal error code
        # and pass class name in the data.
        data ||= { class_name: error.class.name } unless code
        code ||= -32_603

        { jsonrpc: '2.0', id: id, error: { code: code, message: error.message, data: data }.compact }.compact.to_json
      end
    end

    # Create
    def initialize(message, code:, **data)
      super(message)
      @code = code
      @data = data
    end
  end

  # Invalid Request
  class InvalidRequest < Error
    CODE = -32_600
    def initialize(message, code: CODE, **data)
      super
    end
  end

  # Internal Error
  class InternalError < Error
    CODE = -32_603
    def initialize(message, code: CODE, **data)
      super
    end
  end

  # Invalid Response
  class InvalidResponse < InternalError; end

  # Default timeout error for JSON-RPC requests
  class TimeoutError < Error
    CODE = -32_070
    def initialize(message, code: CODE, data: nil)
      super
    end
  end

  # Mapping of JSON-RPC error codes to Ruby error classes
  ERROR_CODES = {
    -32_700 => ::JSON::ParserError,
    -32_601 => ::NoMethodError,
    -32_602 => ::ArgumentError,
    InvalidRequest::CODE => InvalidRequest,
    InternalError::CODE => InternalError,
    TimeoutError::CODE => TimeoutError
  }.freeze
end
