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
  describe '.serve' do
    it 'handles valid JSON-RPC request with block' do
      request = { jsonrpc: '2.0', method: 'add', params: [1, 2], id: '123' }.to_json
      
      response_json = JsonRpcKit::Service.serve(request) do |method, *args|
        case method
        when 'add' then args.sum
        else raise NoMethodError, "Unknown method: #{method}"
        end
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response[:id]).must_equal '123'
      _(response[:result]).must_equal 3
    end

    it 'handles JSON-RPC notification (no id)' do
      request = { jsonrpc: '2.0', method: 'notify', params: ['hello'] }.to_json
      
      response_json = JsonRpcKit::Service.serve(request) do |method, *args|
        # Notification handler
        nil
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response.key?(:id)).must_equal false
      _(response[:result]).must_be_nil
    end

    it 'handles errors in service method' do
      request = { jsonrpc: '2.0', method: 'error', id: '123' }.to_json
      
      response_json = JsonRpcKit::Service.serve(request) do |method|
        raise StandardError, "Something went wrong"
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:jsonrpc]).must_equal '2.0'
      _(response[:id]).must_equal '123'
      _(response[:error]).wont_be_nil
      _(response[:error][:code]).must_equal(-32603) # Internal error
      _(response[:error][:message]).must_equal "Something went wrong"
    end

    it 'handles custom JsonRpcKit::Error' do
      request = { jsonrpc: '2.0', method: 'custom_error', id: '123' }.to_json
      
      response_json = JsonRpcKit::Service.serve(request) do |method|
        raise JsonRpcKit::Error.new("Custom error", code: -1000, extra: 'info')
      end
      
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
end
