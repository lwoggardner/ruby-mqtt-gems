# frozen_string_literal: true

# Load shared spec_helper but handle MQTT dependency gracefully
require_relative '../../../spec/spec_helper'
require 'json_rpc_kit'

# Mock transport helper for testing
class MockTransport
  attr_reader :calls, :response, :error

  def initialize
    @calls = []
    @response = { jsonrpc: '2.0', result: 'default_result', id: '1' }
    @error = nil
  end

  def set_response(result:, id: '1')
    @response = { jsonrpc: '2.0', result: result, id: id }
  end

  def set_error(code:, message:, data: nil)
    @error = { jsonrpc: '2.0', error: { code: code, message: message, data: data }.compact }
  end

  def call(id, request_json, **transport_opts, &response_block)
    request = JSON.parse(request_json, symbolize_names: true)
    is_batch = request.is_a?(Array)
    
    @calls << { id: id, request: request, opts: transport_opts }

    return nil unless id # notification

    response_block.call do
      if is_batch
        # Return array of responses for batch
        request.map do |req|
          response = @error || @response
          response.merge(id: req[:id])
        end.to_json
      else
        response = @error || @response
        response = response.merge(id: id) if response.is_a?(Hash)
        response.to_json
      end
    end
  end

  def to_proc
    method(:call).to_proc
  end

  def last_call
    @calls.last
  end

  def reset
    @calls.clear
  end
end
