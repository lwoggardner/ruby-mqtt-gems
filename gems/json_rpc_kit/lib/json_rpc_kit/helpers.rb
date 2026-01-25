# frozen_string_literal: true

module JsonRpcKit
  # Helper functions
  module Helpers
    # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    # @!visibility private
    def parse(json, content_type: nil, response: false, &)
      raise JSON::ParserError unless !content_type || content_type.start_with?(CONTENT_TYPE)

      # TODO: Need more unit tests on parsing

      JSON.parse(json, symbolize_names: true).tap do |rpc|
        error_class = response ? JsonRpcKit::InvalidResponse : JsonRpcKit::InvalidRequest

        case rpc
        when Hash
          raise error_class, 'Invalid JSON-RPC' unless rpc.key?(:jsonrpc)

          yield false, **rpc
        when Array
          raise error_class, 'Invalid JSON-RPC batch' unless rpc.size.positive?

          rpc.each do |item|
            raise error_class, 'Invalid JSON-RPC batch_item' unless item.is_a?(Hash) && item.key?(:jsonrpc)

            yield true, **item
          end
        else
          raise error_class, "Invalid JSON-RPC - expected List or Object, got #{rpc.class.name}"
        end
      end
    end

    def parse_request(json, content_type: CONTENT_TYPE)
      parse(json, content_type:) do |_batch_item, id: nil, params: nil, method: nil, **_|
        raise InvalidRequest, 'Invalid method' unless method.is_a?(String)
        raise InvalidRequest, 'Invalid params' unless params.nil? || params.is_a?(Hash) || params.is_a?(Array)
        raise InvalidRequest, 'Invalid id' unless id.nil? || id.is_a?(String) || id.is_a?(Integer)
      end
    end

    def parse_response(json, content_type: CONTENT_TYPE, batch: false)
      parse(json, content_type:, response: true) do |batch_item, id: nil, error: nil, **optional|
        raise InvalidResponse, 'JSON-RPC response missing :id' unless id || (batch && !batch_item && error)

        if error
          unless %i[code message].all? { |k| error.include?(k) }
            raise InvalidResponse, 'JSON-RPC response needs :code and :message'
          end
        else
          raise InvalidResponse, 'JSON-RPC response missing :error or :result' unless optional.include?(:result)
        end

        if batch_item
          # A batch item, but not expecting a batch response
          raise InvalidResponse, 'Expected JSON-RPC Object response got List' unless batch
        elsif batch
          # Not a batch item, but expecting a batch. Can be a single error, which is raised immediately
          # because the individual requests have not been fulfilled.
          Errors.raise_error(**error) if error
          raise InvalidResponse, 'Expected JSON-RPC List response or Error'
        end
      end
    rescue JSON::ParserError
      # Client-side parse error - the response from server is not valid JSON
      raise InvalidResponse, 'Unable to parse JSON-RPC response'
    end

    # rubocop:enable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity

    # Helper to convert ruby `method_name` to JSON-RPC `<namespace>.methodName`
    # @param method [Symbol]
    # @param namespace [String]
    # @param camelize [Boolean]
    def ruby_to_json_rpc(method, namespace: nil, camelize: true)
      name = camelize ? method.to_s.gsub(/_([a-z])/) { it[1].upcase } : method.to_s
      namespace ? "#{namespace}.#{name}" : name
    end
  end
end
