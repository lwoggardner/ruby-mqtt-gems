# frozen_string_literal: true

module JsonRpcKit
  # Helper functions
  module Helpers
    # @!visibility private
    def parse(json, error_class:, content_type: CONTENT_TYPE)
      raise JSON::ParserError unless content_type == CONTENT_TYPE

      JSON.parse(json, symbolize_names: true).tap do |rpc|
        raise error_class, 'Invalid request' unless rpc.is_a?(Hash) && rpc.key?(:jsonrpc)
      end
    end

    # lock free next id.
    def next_id
      @next_id ||= 0
      "#{Fiber.current.object_id}-#{@next_id += 1}"
    end

    # Helper to convert ruby `method_name` to JSON-RPC `<namespace>.methodName`
    # @param method [Symbol]
    # @param namespace [String]
    # @param camelize [Boolean]
    def ruby_to_json_rpc(method, namespace: nil, camelize: true)
      name = camelize ? method.to_s.gsub(/_([a-z])/) { it[1].upcase } : method.to_s
      namespace ? "#{namespace}.#{name}" : name
    end

    # Separate `'rpc_' `prefixed arguments from keyword arguments
    # @param kwargs [Hash] keyword arguments
    # @param strip_prefix [Boolean] if set the result has the `rpc_` prefixed removed from keys
    # @return [Hash]
    def extract_rpc_options(kwargs, strip_prefix: true)
      {}.tap do |result|
        kwargs.delete_if do |k, v|
          k.start_with?('rpc_').tap { |rpc_arg| result[strip_prefix ? k.to_s[4..].to_sym : k] = v if rpc_arg }
        end
      end
    end
  end
end
