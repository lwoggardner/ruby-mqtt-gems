# frozen_string_literal: true

require_relative 'spec_helper'

# Test coverage for Service async spawning behavior
#
# Key parameters:
# - async: (passed to .transport) - The spawner object (#async or #call interface)
# - async_policy: (passed to .transport) - Determines which requests should spawn async
# - transport_callback: (passed to handler.call) - Presence indicates async transport
#
# Spawning behavior:
# - If async: implements #call -> full control spawner (always called)
# - If async: implements #async -> simple spawner (called based on simple_async? logic)
# - simple_async? returns true when:
#   - transport_callback present AND (async: true OR async_count > 0)
#   - OR transport_callback absent AND async: true AND batch: true
#
describe 'JsonRpcKit::Service async spawning' do
  def mock_spawner_simple
    calls = []
    spawner = Object.new
    spawner.define_singleton_method(:async) do |&block|
      result = JsonRpcKit::Service::SyncTask.async(&block)
      calls << :async unless result.value == :validate
      result
    end
    spawner.define_singleton_method(:calls) { calls }
    spawner
  end

  def mock_spawner_full
    calls = []
    spawner = Object.new
    spawner.define_singleton_method(:call) do |task_type, request_opts, **context, &block|
      result = JsonRpcKit::Service::SyncTask.async(&block)
      calls << { type: task_type, context: context } unless result.value == :validate
      result
    end
    spawner.define_singleton_method(:calls) { calls }
    spawner
  end

  describe 'simple spawner (#async interface)' do
    it 'does not use spawner for requests when async_policy: false and no callback' do
      spawner = mock_spawner_simple
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: false) do |req_opts, resp_opts, id, method|
        "result"
      end


      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      result = handler.call(request, {})  # Synchronous call (no callback)

      # simple_async?(false, async: false, batch: false) = false, so spawner not used
      _(spawner.calls).must_be_empty
      _(result[0]).must_be_kind_of String  # JSON response
    end

    it 'does not use spawner for requests when async_policy: false with callback' do
      spawner = mock_spawner_simple
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: false) do |req_opts, resp_opts, id, method|
        "result"
      end


      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      handler.call(request, {}) { |json, opts| }  # Async transport (with callback)

      # With callback but async_policy: false, async_count = 0
      # simple_async?(true, async: false, async_count: 0) = (false || false) = false
      _(spawner.calls).must_be_empty
    end

    it 'uses spawner for batch with async_policy: true and callback' do
      spawner = mock_spawner_simple
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: true) do |req_opts, resp_opts, id, method|
        "result_#{id}"
      end


      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },
        { jsonrpc: '2.0', method: 'm2', id: '2' }
      ].to_json
      handler.call(request, {}) { |json, opts| }

      # With callback + async_policy: true -> async_count = 2
      # Batch: simple_async?(true, async_count: 2) = (nil || true) = true -> spawns
      # Requests: simple_async?(true, async: true, batch: true) = (true || false) = true -> spawns
      # Total: 1 batch + 2 requests = 3
      _(spawner.calls.size).must_equal 3
    end

    it 'uses spawner for batch requests when async_policy: true but no callback' do
      spawner = mock_spawner_simple
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: true) do |req_opts, resp_opts, id, method|
        "result_#{id}"
      end


      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },
        { jsonrpc: '2.0', method: 'm2', id: '2' }
      ].to_json
      result = handler.call(request, {})  # Synchronous

      # Without callback (async_transport = false):
      # Batch: simple_async?(false, async_count: 2, batch: true) = (nil && true) = nil -> no spawn
      # Requests: simple_async?(false, async: true, batch: true) = (true && true) = true -> spawns
      # Total: 0 batch + 2 requests = 2
      _(spawner.calls.size).must_equal 2
      _(result[0]).must_be_kind_of String
    end
  end

  describe 'full control spawner (#call interface)' do
    it 'always gets called for single request' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: false) do |req_opts, resp_opts, id, method|
        "result"
      end

      request = { jsonrpc: '2.0', method: 'test', id: '1' }.to_json
      result = handler.call(request, {})

      _(spawner.calls.size).must_equal 1
      _(spawner.calls[0][:type]).must_equal :request
      _(spawner.calls[0][:context][:method]).must_equal 'test'
    end

    it 'gets called for batch wrapper and each request' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: true) do |req_opts, resp_opts, id, method|
        "result_#{id}"
      end

      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },
        { jsonrpc: '2.0', method: 'm2', id: '2' }
      ].to_json
      result = handler.call(request, {})

      _(spawner.calls.size).must_equal 3
      
      # Check we have 1 batch and 2 requests (order may vary due to nesting)
      batch_calls = spawner.calls.select { |c| c[:type] == :batch }
      request_calls = spawner.calls.select { |c| c[:type] == :request }
      
      _(batch_calls.size).must_equal 1
      _(batch_calls[0][:context][:count]).must_equal 2
      _(batch_calls[0][:context][:async_count]).must_equal 2
      _(request_calls.size).must_equal 2
    end

    it 'receives async_count based on async_policy' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: ->(req_opts, id:, method:) { method == 'm1' }) do |req_opts, resp_opts, id, method|
        "result_#{id}"
      end

      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },  # async: true
        { jsonrpc: '2.0', method: 'm2', id: '2' }   # async: false
      ].to_json
      result = handler.call(request, {})

      batch_call = spawner.calls.find { |c| c[:type] == :batch }
      _(batch_call[:context][:async_count]).must_equal 1  # Only m1 is async
    end
  end

  describe 'async_policy variations' do
    it 'boolean true makes all requests async' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: true) do |req_opts, resp_opts, id, method|
        "result"
      end

      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },
        { jsonrpc: '2.0', method: 'm2', id: '2' }
      ].to_json
      handler.call(request, {})

      batch_call = spawner.calls.find { |c| c[:type] == :batch }
      _(batch_call[:context][:async_count]).must_equal 2
    end

    it 'boolean false makes no requests async' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: false) do |req_opts, resp_opts, id, method|
        "result"
      end

      request = [
        { jsonrpc: '2.0', method: 'm1', id: '1' },
        { jsonrpc: '2.0', method: 'm2', id: '2' }
      ].to_json
      handler.call(request, {})

      batch_call = spawner.calls.find { |c| c[:type] == :batch }
      _(batch_call[:context][:async_count]).must_equal 0
    end

    it 'proc can selectively mark requests async' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(
        merge: nil,
        async: spawner,
        async_policy: ->(req_opts, id:, method:) { method.start_with?('slow_') }
      ) do |req_opts, resp_opts, id, method|
        "result"
      end

      request = [
        { jsonrpc: '2.0', method: 'slow_operation', id: '1' },
        { jsonrpc: '2.0', method: 'fast_operation', id: '2' },
        { jsonrpc: '2.0', method: 'slow_query', id: '3' }
      ].to_json
      handler.call(request, {})

      batch_call = spawner.calls.find { |c| c[:type] == :batch }
      _(batch_call[:context][:async_count]).must_equal 2  # slow_operation and slow_query
    end
  end

  describe 'notifications' do
    it 'notifications are included in batch processing' do
      spawner = mock_spawner_full
      handler = JsonRpcKit::Service.transport(merge: nil, async: spawner, async_policy: true) do |req_opts, resp_opts, id, method|
        "result_#{id}"
      end

      request = [
        { jsonrpc: '2.0', method: 'notify' },  # notification (no id)
        { jsonrpc: '2.0', method: 'request', id: '1' }
      ].to_json
      result = handler.call(request, {})

      # Batch wrapper + 2 requests (including notification)
      _(spawner.calls.size).must_equal 3
      _(result[0]).must_be_kind_of String
      response = JSON.parse(result[0])
      _(response.size).must_equal 1  # Only request has response, not notification
    end
  end
end
