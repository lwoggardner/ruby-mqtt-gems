# frozen_string_literal: true

require_relative 'spec_helper'

describe JsonRpcKit do
  it 'has a version number' do
    _(JsonRpcKit::VERSION).wont_be_nil
  end

  it 'has the correct content type' do
    _(JsonRpcKit::CONTENT_TYPE).must_equal 'application/json'
  end
end

describe JsonRpcKit::Service do
  describe '.transport' do
    it 'handles valid JSON-RPC request with block' do
      request = { jsonrpc: '2.0', method: 'add', params: [1, 2], id: '123' }.to_json
      
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method, *args, **kwargs|
        case method
        when 'add' then args.sum
        else raise NoMethodError, "Unknown method: #{method}"
        end
      end
      
      response_json = nil
      handler.call(request) { |json, opts| response_json = json }
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response[:id]).must_equal '123'
      _(response[:result]).must_equal 3
    end

    it 'handles JSON-RPC notification (no id)' do
      request = { jsonrpc: '2.0', method: 'notify', params: ['hello'] }.to_json
      
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method, *args, **kwargs|
        # Notification handler
        nil
      end
      
      response_json = :not_called
      handler.call(request) { |json, opts| response_json = json }
      
      # Notifications should not return a response
      _(response_json).must_be_nil
    end

    it 'handles errors in service method' do
      request = { jsonrpc: '2.0', method: 'error', id: '123' }.to_json
      
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method, *args, **kwargs|
        raise StandardError, "Something went wrong"
      end
      
      response_json = nil
      handler.call(request) { |json, opts| response_json = json }
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response[:id]).must_equal '123'
      _(response[:error]).wont_be_nil
      _(response[:error][:code]).must_equal(-32603) # Internal error
      _(response[:error][:message]).must_equal "Something went wrong"
    end

    it 'handles custom JsonRpcKit::Error' do
      request = { jsonrpc: '2.0', method: 'custom_error', id: '123' }.to_json
      
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method, *args, **kwargs|
        raise JsonRpcKit::Error.new("Custom error", code: -1000, extra: 'info')
      end
      
      response_json = nil
      handler.call(request) { |json, opts| response_json = json }
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response[:id]).must_equal '123'
      _(response[:error]).wont_be_nil
      _(response[:error][:code]).must_equal(-1000) # Custom error code
      _(response[:error][:message]).must_equal "Custom error"
      _(response[:error][:data][:extra]).must_equal 'info'
    end
  end
end

describe JsonRpcKit::Endpoint do
  it 'can be created with a transport block' do
    endpoint = JsonRpcKit::Endpoint.new do |id, request_json, **opts, &response|
      # Simple mock that doesn't need to handle response
    end
    
    _(endpoint).must_be_instance_of JsonRpcKit::Endpoint
  end

  it 'converts ruby method names to JSON-RPC format' do
    captured_request = nil
    
    endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
      captured_request = JSON.parse(request_json, symbolize_names: true)
    end

    # This will fail because no response, but we can capture the request
    begin
      endpoint.get_user_info
    rescue
      # Ignore the error, we just want to capture the request
    end
    
    _(captured_request[:method]).must_equal 'getUserInfo'  # Converted from get_user_info
  end

  it 'handles namespaces in method conversion' do
    captured_request = nil
    
    endpoint = JsonRpcKit.endpoint(namespace: 'api') do |id, request_json, **opts, &response|
      captured_request = JSON.parse(request_json, symbolize_names: true)
      # Don't call response to avoid callback complexity in test
    end
    
    # This will fail because no response, but we can capture the request
    begin
      endpoint.get_user
    rescue
      # Ignore the error, we just want to capture the request
    end
    
    _(captured_request[:method]).must_equal 'api.getUser'  # Namespace + converted method
  end

  describe 'error mapping' do
    it 'raises NoMethodError when receiving -32601 error code' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        error_response = { jsonrpc: '2.0', id: id, error: { code: -32601, message: 'Method not found' } }.to_json
        response.call { error_response }
      end

      error = _(proc { endpoint.unknown_method }).must_raise(NoMethodError)
      _(error.message).must_equal 'Method not found'
    end

    it 'raises ArgumentError when receiving -32602 error code' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        error_response = { jsonrpc: '2.0', id: id, error: { code: -32602, message: 'Invalid params' } }.to_json
        response.call { error_response }
      end

      error = _(proc { endpoint.test_method }).must_raise(ArgumentError)
      _(error.message).must_equal 'Invalid params'
    end

    it 'raises JSON::ParserError when receiving -32700 error code' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        error_response = { jsonrpc: '2.0', id: id, error: { code: -32700, message: 'Parse error' } }.to_json
        response.call { error_response }
      end

      error = _(proc { endpoint.test_method }).must_raise(JSON::ParserError)
      _(error.message).must_equal 'Parse error'
    end

    it 'raises JsonRpcKit::Error for custom error codes' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        error_response = { jsonrpc: '2.0', id: id, error: { code: -1000, message: 'Custom error', data: { extra: 'info' } } }.to_json
        response.call { error_response }
      end

      error = _(proc { endpoint.test_method }).must_raise(JsonRpcKit::Error)
      _(error.message).must_equal 'Custom error'
      _(error.code).must_equal(-1000)
      _(error.data).must_equal({ extra: 'info' })
    end

    it 'raises InvalidResponse for non-JSON response' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        response.call { 'not valid json{' }
      end

      _(proc { endpoint.test_method }).must_raise(JsonRpcKit::InvalidResponse)
    end

    it 'raises InvalidResponse for response missing jsonrpc field' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        invalid_response = { id: id, result: 'test' }.to_json
        response.call { invalid_response }
      end

      error = _(proc { endpoint.test_method }).must_raise(JsonRpcKit::InvalidResponse)
      _(error.message).must_include 'JSON-RPC'
    end

    it 'raises InvalidResponse for error without code' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        invalid_error = { jsonrpc: '2.0', id: id, error: { message: 'Error without code' } }.to_json
        response.call { invalid_error }
      end

      error = _(proc { endpoint.test_method }).must_raise(JsonRpcKit::InvalidResponse)
      _(error.message).must_include 'code'
    end

    it 'raises InvalidResponse for error without message' do
      endpoint = JsonRpcKit.endpoint do |id, request_json, **opts, &response|
        invalid_error = { jsonrpc: '2.0', id: id, error: { code: -32000 } }.to_json
        response.call { invalid_error }
      end

      error = _(proc { endpoint.test_method }).must_raise(JsonRpcKit::InvalidResponse)
      _(error.message).must_include 'message'
    end
  end
end
