# frozen_string_literal: true

require_relative 'spec_helper'

describe 'JsonRpcKit::Endpoint::Batch transport_opts' do
  describe 'batch created from endpoint' do
    it 'inherits options from endpoint' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(timeout: 30, custom: 'value', &transport)
      
      batch = endpoint.json_rpc_batch
      batch.test_method
      results = batch.json_rpc_invoke
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
      _(transport.last_call[:opts][:custom]).must_equal 'value'
    end

    it 'inherits converter from endpoint' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "converted:#{res.call}" }
      
      batch = endpoint.json_rpc_batch
      id = batch.test_method
      results = batch.json_rpc_invoke
      
      _(results[id].call).must_equal 'converted:raw'
    end

    it 'inherits merge proc from endpoint' do
      transport = MockTransport.new
      custom_merge = proc { |_key, _old, new| new }
      options_config = JsonRpcKit::TransportOptions.new(merge: custom_merge)
      
      endpoint = JsonRpcKit::Endpoint.new(options_config:, tags: ['a'], &transport)
      batch = endpoint.json_rpc_batch(tags: ['b'])
      batch.test_method
      batch.json_rpc_invoke
      
      _(transport.last_call[:opts][:tags]).must_equal ['b']
    end
  end

  describe 'batch options are immutable' do
    it 'batch options set at creation' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(base: 'value', &transport)
      
      batch = endpoint.json_rpc_batch(timeout: 30)
      batch.test_method
      batch.json_rpc_invoke
      
      _(transport.last_call[:opts][:base]).must_equal 'value'
      _(transport.last_call[:opts][:timeout]).must_equal 30
    end

    it 'uses DEFAULT_MERGE for Hash options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(headers: { 'X-Auth' => 'token' }, &transport)
      
      batch = endpoint.json_rpc_batch(headers: { 'X-Session' => 'abc' })
      batch.test_method
      batch.json_rpc_invoke
      
      expected = { 'X-Auth' => 'token', 'X-Session' => 'abc' }
      _(transport.last_call[:opts][:headers]).must_equal expected
    end

    it 'uses DEFAULT_MERGE for Array options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(tags: ['a'], &transport)
      
      batch = endpoint.json_rpc_batch(tags: ['b'])
      batch.test_method
      batch.json_rpc_invoke
      
      _(transport.last_call[:opts][:tags]).must_equal ['a', 'b']
    end

    it 'replaces scalar options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(timeout: 10, &transport)
      
      batch = endpoint.json_rpc_batch(timeout: 20)
      batch.test_method
      batch.json_rpc_invoke
      
      _(transport.last_call[:opts][:timeout]).must_equal 20
    end
  end

  describe 'per-request converters' do
    it 'per-request converter works' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      batch = JsonRpcKit::Endpoint.new(&transport).json_rpc_batch
      id = batch.json_rpc_request(:next_id, :test) { |**, &res| "converted:#{res.call}" }
      results = batch.json_rpc_invoke
      
      _(results[id].call).must_equal 'converted:raw'
    end

    it 'batch context converter wraps per-request converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "ctx:#{res.call}" }
      
      batch = endpoint.json_rpc_batch
      id = batch.json_rpc_request(:next_id, :test) { |**, &res| "req:#{res.call}" }
      results = batch.json_rpc_invoke
      
      _(results[id].call).must_equal 'req:ctx:raw'
    end

    it 'different converters for different requests' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      batch = JsonRpcKit::Endpoint.new(&transport).json_rpc_batch
      id1 = batch.json_rpc_request(:next_id, :test1) { |**, &res| "a:#{res.call}" }
      id2 = batch.json_rpc_request(:next_id, :test2) { |**, &res| "b:#{res.call}" }
      results = batch.json_rpc_invoke
      
      _(results[id1].call).must_equal 'a:raw'
      _(results[id2].call).must_equal 'b:raw'
    end
  end

  describe '#json_rpc_endpoint' do
    it 'creates Endpoint with same config' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(timeout: 30, custom: 'value', &transport)
      
      batch = endpoint.json_rpc_batch
      new_endpoint = batch.json_rpc_endpoint
      
      new_endpoint.test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 30
      _(transport.last_call[:opts][:custom]).must_equal 'value'
    end

    it 'creates Endpoint with overridden options' do
      transport = MockTransport.new
      endpoint = JsonRpcKit::Endpoint.new(timeout: 30, &transport)
      
      batch = endpoint.json_rpc_batch
      new_endpoint = batch.json_rpc_endpoint(timeout: 60, retries: 3)
      
      new_endpoint.test_method
      
      _(transport.last_call[:opts][:timeout]).must_equal 60
      _(transport.last_call[:opts][:retries]).must_equal 3
    end

    it 'preserves converter' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      endpoint = JsonRpcKit::Endpoint.new(&transport)
        .with_conversion { |**, &res| "converted:#{res.call}" }
      
      batch = endpoint.json_rpc_batch
      new_endpoint = batch.json_rpc_endpoint
      
      result = new_endpoint.test_method
      
      _(result).must_equal 'converted:raw'
    end

    it 'preserves merge proc' do
      transport = MockTransport.new
      custom_merge = proc { |_key, _old, new| new }
      options_config = JsonRpcKit::TransportOptions.new(merge: custom_merge)
      
      endpoint = JsonRpcKit::Endpoint.new(options_config:, tags: ['a'], &transport)
      batch = endpoint.json_rpc_batch
      new_endpoint = batch.json_rpc_endpoint(tags: ['b'])
      
      new_endpoint.test_method
      
      _(transport.last_call[:opts][:tags]).must_equal ['b']
    end
  end

  describe 'batch consistency with Endpoint' do
    it 'batch and endpoint use same merge for options' do
      transport = MockTransport.new
      base_opts = { headers: { 'X-Auth' => 'token' }, tags: ['api'] }
      
      # Test with Endpoint
      endpoint = JsonRpcKit::Endpoint.new(**base_opts, &transport)
        .with(headers: { 'X-ID' => '1' }, tags: ['v1'])
      endpoint.test_method
      endpoint_opts = transport.last_call[:opts]
      
      transport.reset
      
      # Test with Batch - options set at creation
      batch = JsonRpcKit::Endpoint.new(**base_opts, &transport)
        .json_rpc_batch(headers: { 'X-ID' => '1' }, tags: ['v1'])
      batch.test_method
      batch.json_rpc_invoke
      batch_opts = transport.last_call[:opts]
      
      _(batch_opts[:headers]).must_equal endpoint_opts[:headers]
      _(batch_opts[:tags]).must_equal endpoint_opts[:tags]
    end

    it 'batch and endpoint handle converters consistently' do
      transport = MockTransport.new
      transport.set_response(result: 'raw')
      
      converter = ->(**, &res) { "converted:#{res.call}" }
      
      # Test with Endpoint
      endpoint = JsonRpcKit::Endpoint.new(&transport).with_conversion(&converter)
      endpoint_result = endpoint.test_method
      
      # Test with Batch
      batch = JsonRpcKit::Endpoint.new(&transport).with_conversion(&converter).json_rpc_batch
      id = batch.test_method
      batch_results = batch.json_rpc_invoke
      batch_result = batch_results[id].call
      
      _(batch_result).must_equal endpoint_result
    end
  end
end
