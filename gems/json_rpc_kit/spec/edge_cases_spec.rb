# frozen_string_literal: true

require_relative 'spec_helper'

describe 'JsonRpcKit Edge Cases' do
  # Helper to call service handler and return response JSON
  def call_service(request_json, **opts, &block)
    handler = JsonRpcKit::Service.transport(merge: nil, **opts, &block)
    response_json = nil
    handler.call(request_json) { |json, _opts| response_json = json }
    response_json
  end

  describe 'Parameter Passing Edge Cases' do
    it 'handles empty parameters vs null vs missing' do
      # Empty array
      request1 = { jsonrpc: '2.0', method: 'test', params: [], id: '1' }.to_json
      response1 = call_service(request1) { |request_opts, response_opts, id, method, *args, **kwargs| args.length }
      result1 = JSON.parse(response1, symbolize_names: true)
      _(result1[:result]).must_equal 0

      # Null params
      request2 = { jsonrpc: '2.0', method: 'test', params: nil, id: '2' }.to_json
      response2 = call_service(request2) { |request_opts, response_opts, id, method, *args, **kwargs| args.length }
      result2 = JSON.parse(response2, symbolize_names: true)
      _(result2[:result]).must_equal 0

      # Missing params
      request3 = { jsonrpc: '2.0', method: 'test', id: '3' }.to_json
      response3 = call_service(request3) { |request_opts, response_opts, id, method, *args, **kwargs| args.length }
      result3 = JSON.parse(response3, symbolize_names: true)
      _(result3[:result]).must_equal 0
    end

    it 'handles unicode and special characters in parameters' do
      unicode_text = '🚀 Hello 世界 café'
      request = { jsonrpc: '2.0', method: 'echo', params: [unicode_text], id: '1' }.to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method, text| text }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:result]).must_equal unicode_text
    end
  end

  describe 'JSON-RPC Error Code Coverage' do
    it 'handles parse errors (-32700)' do
      invalid_json = '{"jsonrpc": "2.0", "method": "test", "id": 1'  # Missing closing brace
      
      response_json = call_service(invalid_json) { |request_opts, response_opts, id, method| 'should not reach' }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:error][:code]).must_equal(-32700)
    end

    it 'handles method not found (-32601)' do
      request = { jsonrpc: '2.0', method: 'nonexistent', id: '1' }.to_json
      
      response_json = call_service(request) do |request_opts, response_opts, id, method|
        raise NoMethodError, "Unknown method: #{method}"
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:error][:code]).must_equal(-32601)
    end

    it 'handles invalid params (-32602)' do
      request = { jsonrpc: '2.0', method: 'test', params: [1, 2], id: '1' }.to_json
      
      response_json = call_service(request) do |request_opts, response_opts, id, method, arg1|
        raise ArgumentError, "wrong number of arguments"
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:error][:code]).must_equal(-32602)
    end

    it 'handles internal errors (-32603)' do
      request = { jsonrpc: '2.0', method: 'error', id: '1' }.to_json
      
      response_json = call_service(request) do |request_opts, response_opts, id, method|
        raise StandardError, "Internal server error"
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:error][:code]).must_equal(-32603)
    end

    it 'handles custom error codes and data' do
      request = { jsonrpc: '2.0', method: 'custom_error', id: '1' }.to_json
      
      response_json = call_service(request) do |request_opts, response_opts, id, method|
        raise JsonRpcKit::Error.new("Custom error", code: -1000, data: { extra_data: 'test' })
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response[:error][:code]).must_equal(-1000)
      _(response[:error][:data][:extra_data]).must_equal 'test'
    end
  end

  describe 'Request Validation Edge Cases' do
    it 'rejects missing jsonrpc field' do
      request = { method: 'test', id: '1' }.to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method| 'should not reach' }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:error][:code]).must_equal(-32600)
      _(response[:error][:message]).must_include 'Invalid'
    end
  end

  describe 'Batch Request Edge Cases' do
    it 'handles empty batch' do
      request = [].to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method| 'should not reach' }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:error][:code]).must_equal(-32600)
    end

    it 'handles single-item batch' do
      request = [{ jsonrpc: '2.0', method: 'test', id: '1' }].to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method| 'result' }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response).must_be_kind_of Array
      _(response.length).must_equal 1
      _(response[0][:result]).must_equal 'result'
    end

    it 'handles mixed notifications and requests in batch' do
      request = [
        { jsonrpc: '2.0', method: 'notify' },  # notification
        { jsonrpc: '2.0', method: 'request', id: '1' }  # request
      ].to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method| "#{method}_result" }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response).must_be_kind_of Array
      _(response.length).must_equal 1  # Only request should have response
      _(response[0][:result]).must_equal 'request_result'
    end

    it 'handles batch with some errors' do
      request = [
        { jsonrpc: '2.0', method: 'success', id: '1' },
        { jsonrpc: '2.0', method: 'error', id: '2' }
      ].to_json
      
      response_json = call_service(request) do |request_opts, response_opts, id, method|
        case method
        when 'success' then 'ok'
        when 'error' then raise StandardError, 'failed'
        end
      end
      
      response = JSON.parse(response_json, symbolize_names: true)
      _(response).must_be_kind_of Array
      _(response.length).must_equal 2
      _(response[0][:result]).must_equal 'ok'
      _(response[1][:error]).wont_be_nil
    end

    it 'returns nil for all-notification batch' do
      request = [
        { jsonrpc: '2.0', method: 'notify1' },
        { jsonrpc: '2.0', method: 'notify2' }
      ].to_json
      
      response_json = call_service(request) { |request_opts, response_opts, id, method| "#{method}_result" }
      _(response_json).must_be_nil
    end
  end

  describe 'Transport and Content-Type Edge Cases' do
    it 'rejects invalid content type' do
      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method|
        'should not reach'
      end
      response_json = nil
      handler.call(request, content_type: 'text/plain') { |json, _opts| response_json = json }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:error][:code]).must_equal(-32700)
    end

    it 'accepts valid content type' do
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method|
        'success'
      end
      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      response_json = nil
      handler.call(request, content_type: 'application/json') { |json, _opts| response_json = json }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:result]).must_equal 'success'
    end

    it 'accepts content type with charset' do
      handler = JsonRpcKit::Service.transport(merge: nil) do |request_opts, response_opts, id, method|
        'success'
      end
      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      response_json = nil
      handler.call(request, content_type: 'application/json; charset=utf-8') { |json, _opts| response_json = json }
      response = JSON.parse(response_json, symbolize_names: true)
      
      _(response[:result]).must_equal 'success'
    end
  end
end
