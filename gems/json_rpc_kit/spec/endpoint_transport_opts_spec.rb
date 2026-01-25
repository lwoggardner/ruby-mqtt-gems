# frozen_string_literal: true

require_relative 'spec_helper'

describe 'JsonRpcKit::Endpoint transport_opts' do
  describe '#with - basic behavior' do
    it 'creates new endpoint (immutability)' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(&transport)
      
      new_endpoint = endpoint.with(timeout: 30)
      
      _(new_endpoint).wont_be_same_as endpoint
      _(new_endpoint).must_be_instance_of JsonRpcKit::Endpoint
    end

    it 'merges scalar options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(&transport)
      
      endpoint.with(timeout: 30, async: true).test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
      _(transport.last_call[:opts][:async]).must_equal true
    end

    it 'passes merged options to transport' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(custom: 'base', &transport)
      
      endpoint.with(timeout: 30).test_method
      
      _(transport.last_call[:opts][:custom]).must_equal 'base'
      _(transport.last_call[:opts][:timeout]).must_equal 30
    end

    it 'chains multiple with calls' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(&transport)
      
      endpoint.with(timeout: 30).with(async: true).with(retries: 3).test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
      _(transport.last_call[:opts][:async]).must_equal true
      _(transport.last_call[:opts][:retries]).must_equal 3
    end
  end

  describe '#with - DEFAULT_MERGE behavior' do
    it 'merges Hash options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(headers: { 'X-Auth' => 'token' }, &transport)
      
      endpoint.with(headers: { 'X-Request-ID' => '123' }).test_method
      
      _(transport.last_call[:opts][:headers]).must_equal({ 'X-Auth' => 'token', 'X-Request-ID' => '123' })
    end

    it 'concatenates Array options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(tags: ['api', 'v1'], &transport)
      
      endpoint.with(tags: ['user']).test_method
      
      _(transport.last_call[:opts][:tags]).must_equal ['api', 'v1', 'user']
    end

    it 'replaces scalar options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(timeout: 10, &transport)
      
      endpoint.with(timeout: 30).test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
    end

    it 'merges Set options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(flags: Set[:a, :b], &transport)
      
      endpoint.with(flags: Set[:c]).test_method
      
      _(transport.last_call[:opts][:flags]).must_equal Set[:a, :b, :c]
    end

    it 'always replaces :converter (reserved key)' do
      transport = MockTransport.new
      converter1 = ->(**, &result) { "conv1:#{result.call}" }
      converter2 = ->(**, &result) { "conv2:#{result.call}" }
      
      endpoint = JsonRpcKit::Endpoint.new(converter: converter1, &transport)
      result = endpoint.with(converter: converter2).test_method
      
      _(result).must_equal 'conv2:default_result'
    end
  end

  describe '#with_conversion' do
    it 'sets converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      endpoint = JsonRpcKit::Endpoint.new(&transport)
      
      result = endpoint.with_conversion { |**, &res| "converted:#{res.call}" }.test_method
      
      _(result).must_equal 'converted:raw'
    end

    it 'replace: true replaces existing converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "first:#{res.call}" }
        .with_conversion(replace: true) { |**, &res| "second:#{res.call}" }
      
      result = endpoint.test_method
      
      _(result).must_equal 'second:raw'
    end

    it 'replace: false wraps existing converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "first:#{res.call}" }
        .with_conversion(replace: false) { |**, &res| "second:#{res.call}" }
      
      result = endpoint.test_method
      
      _(result).must_equal 'second:first:raw'
    end

    it 'converter receives response_opts' do
      transport = MockTransport.new
      captured_opts = nil
      
      endpoint = JsonRpcKit::Endpoint.new do |id, json, **opts, &resp|
        resp.call(custom: 'value') { { jsonrpc: '2.0', result: 'ok', id: id }.to_json }
      end.with_conversion { |**opts, &res| captured_opts = opts; res.call }
      
      endpoint.test_method
      
      _(captured_opts[:custom]).must_equal 'value'
    end

    it 'converter can transform results' do
      transport = MockTransport.new
      transport.set_response(result: { name: 'Alice' })
      
      result = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| res.call[:name].upcase }
        .test_method
      
      _(result).must_equal 'ALICE'
    end

    it 'converter can transform errors' do
      transport = MockTransport.new
      transport.set_error(code: -32001, message: 'Not found')
      
      error = assert_raises(RuntimeError) do
        JsonRpcKit::Endpoint.new(&transport)
          .with_conversion do |**, &res|
            res.call
          rescue JsonRpcKit::Error => e
            raise "Custom: #{e.message}"
          end
          .test_method
      end
      
      _(error.message).must_include 'Custom:'
    end

    it 'per-call converter wraps context converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "context:#{res.call}" }
      
      result = endpoint.test_method { |**, &res| "call:#{res.call}" }
      
      _(result).must_equal 'call:context:raw'
    end
  end

  describe '#with and #with_conversion interaction' do
    it 'with then with_conversion preserves options' do
      transport = MockTransport.new
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with(timeout: 30)
        .with_conversion { |**, &res| res.call }
      
      endpoint.test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
    end

    it 'with_conversion then with preserves converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      result = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "converted:#{res.call}" }
        .with(timeout: 30)
        .test_method
      
      _(result).must_equal 'converted:raw'
    end

    it 'chains multiple of each' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with(timeout: 10)
        .with_conversion { |**, &res| "a:#{res.call}" }
        .with(retries: 3)
        .with_conversion(replace: false) { |**, &res| "b:#{res.call}" }
      
      result = endpoint.test_method
      
      _(result).must_equal 'b:a:raw'
      _(transport.last_call[:opts][:timeout]).must_equal 10
      _(transport.last_call[:opts][:retries]).must_equal 3
    end

    it 'per-call transport_opts merge with context opts' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(base: 'value', &transport)
        .with(timeout: 30, retries: 3)
      
      endpoint.json_rpc_invoke(:next_id, :test_method)
      
      _(transport.last_call[:opts][:base]).must_equal 'value'
      _(transport.last_call[:opts][:timeout]).must_equal 30
      _(transport.last_call[:opts][:retries]).must_equal 3
    end

    it 'per-call converter wraps context converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "ctx:#{res.call}" }
      
      result = endpoint.json_rpc_invoke(:next_id, :test) { |**, &res| "call:#{res.call}" }
      
      _(result).must_equal 'call:ctx:raw'
    end
  end
end
