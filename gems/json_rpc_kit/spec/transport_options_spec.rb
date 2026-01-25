# frozen_string_literal: true

require_relative 'spec_helper'

describe 'JsonRpcKit::TransportOptions' do
  describe 'prefix and filter' do
    it 'prefixes keys for user space' do
      opts_config = JsonRpcKit::TransportOptions.new(prefix: 'mqtt_')
      
      transport_opts = { qos: 1, user_properties: [] }
      user_opts = opts_config.to_user_space(transport_opts)
      
      _(user_opts).must_equal({ mqtt_qos: 1, mqtt_user_properties: [] })
    end

    it 'de-prefixes keys for transport space' do
      opts_config = JsonRpcKit::TransportOptions.new(prefix: 'mqtt_')
      
      user_opts = { mqtt_qos: 1, mqtt_user_properties: [] }
      transport_opts = opts_config.to_transport_space(user_opts)
      
      _(transport_opts).must_equal({ qos: 1, user_properties: [] })
    end

    it 'filters with Array' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: [:qos, :user_properties]
      )
      
      user_opts = { mqtt_qos: 1, mqtt_user_properties: [], mqtt_invalid: 'bad' }
      
      error = assert_raises(ArgumentError) do
        opts_config.filter_opts(user_opts)
      end
      
      _(error.message).must_include 'Unsupported options'
      _(error.message).must_include 'mqtt_invalid'
    end

    it 'filters with Proc' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: ->(k, _v) { [:qos, :user_properties].include?(k) }  # Filter receives de-prefixed keys
      )
      
      user_opts = { mqtt_qos: 1, mqtt_user_properties: [], mqtt_invalid: 'bad' }
      filtered = opts_config.filter_opts(user_opts)
      
      _(filtered).must_equal({ mqtt_qos: 1, mqtt_user_properties: [] })
    end

    it 'ignores other prefixes' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: [:qos],
        ignore: ['http_']
      )
      
      user_opts = { mqtt_qos: 1, http_timeout: 30 }
      filtered = opts_config.filter_opts(user_opts)
      
      _(filtered).must_equal({ mqtt_qos: 1 })
    end

    it 'respects RESERVED_OPTIONS' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: [:qos]
      )
      
      user_opts = { mqtt_qos: 1, async: true, timeout: 30, converter: -> {} }
      filtered = opts_config.filter_opts(user_opts)
      
      # Reserved options pass through without prefix
      _(filtered[:async]).must_equal true
      _(filtered[:timeout]).must_equal 30
      _(filtered[:converter]).must_be_kind_of Proc
      _(filtered[:mqtt_qos]).must_equal 1
    end
  end

  describe 'ignore' do
    it 'ignores specified prefixes' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: [:qos],
        ignore: ['http_', 'kafka_']
      )
      
      user_opts = { mqtt_qos: 1, http_timeout: 30, kafka_partition: 2 }
      filtered = opts_config.filter_opts(user_opts)
      
      _(filtered).must_equal({ mqtt_qos: 1 })
    end

    it 'never ignores RESERVED_OPTIONS' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        ignore: ['http_', 'async', 'timeout']  # Try to ignore reserved options
      )
      
      user_opts = { mqtt_qos: 1, http_timeout: 30, async: true, timeout: 10, converter: -> {} }
      filtered = opts_config.filter_opts(user_opts)
      
      # RESERVED_OPTIONS are never ignored
      _(filtered[:async]).must_equal true
      _(filtered[:timeout]).must_equal 10
      _(filtered[:converter]).must_be_kind_of Proc
      _(filtered[:mqtt_qos]).must_equal 1
      _(filtered[:http_timeout]).must_be_nil
    end

    it 'works with Proc' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        ignore: ->(k, _v) { k.to_s.start_with?('http_') }
      )
      
      user_opts = { mqtt_qos: 1, http_timeout: 30, http_retries: 3 }
      filtered = opts_config.filter_opts(user_opts)
      
      _(filtered).must_equal({ mqtt_qos: 1 })
    end

    it 'raises for non-RESERVED options when merge: nil and no ignore' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        merge: nil
      )
      
      user_opts = { mqtt_qos: 1, async: true, converter: -> {} }
      
      error = assert_raises(ArgumentError) do
        opts_config.filter_opts(user_opts)
      end
      
      _(error.message).must_include 'Unsupported options'
      _(error.message).must_include 'mqtt_qos'
    end

    it 'respects ignore when merge: nil' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        merge: nil,
        ignore: ['mqtt_']
      )
      
      user_opts = { mqtt_qos: 1, mqtt_timeout: 30, async: true, converter: -> {} }
      filtered = opts_config.filter_opts(user_opts)
      
      # Custom options ignored, RESERVED_OPTIONS pass through
      _(filtered[:mqtt_qos]).must_be_nil
      _(filtered[:mqtt_timeout]).must_be_nil
      _(filtered[:async]).must_equal true
      _(filtered[:converter]).must_be_kind_of Proc
    end
  end

  describe 'merge' do
    it 'merges with DEFAULT_MERGE' do
      opts_config = JsonRpcKit::TransportOptions.new
      
      old_opts = { tags: ['a'], headers: { 'X-Auth' => 'token' } }
      new_opts = { tags: ['b'], headers: { 'X-ID' => '123' } }
      
      merged = opts_config.merge_opts(old_opts, new_opts, filtered: true)
      
      _(merged[:tags]).must_equal ['a', 'b']
      _(merged[:headers]).must_equal({ 'X-Auth' => 'token', 'X-ID' => '123' })
    end

    it 'merges with custom merge' do
      opts_config = JsonRpcKit::TransportOptions.new(
        merge: ->(k, old, new) { k == :tags ? old + new : new }
      )
      
      old_opts = { tags: ['a'], timeout: 10 }
      new_opts = { tags: ['b'], timeout: 20 }
      
      merged = opts_config.merge_opts(old_opts, new_opts, filtered: true)
      
      _(merged[:tags]).must_equal ['a', 'b']
      _(merged[:timeout]).must_equal 20
    end

    it 'filters before merging when filtered: false' do
      opts_config = JsonRpcKit::TransportOptions.new(
        prefix: 'mqtt_',
        filter: [:qos]
      )
      
      old_opts = { mqtt_qos: 1 }
      new_opts = { mqtt_qos: 2, mqtt_invalid: 'bad' }
      
      error = assert_raises(ArgumentError) do
        opts_config.merge_opts(old_opts, new_opts, filtered: false)
      end
      
      _(error.message).must_include 'Unsupported options'
    end
  end

  describe 'create_from_opts' do
    it 'extracts config and mutates opts' do
      opts = { prefix: 'mqtt_', filter: [:qos], mqtt_qos: 1, timeout: 30 }
      
      opts_config = JsonRpcKit::TransportOptions.create_from_opts(opts)
      
      _(opts_config.prefix).must_equal 'mqtt_'
      _(opts_config.filter).must_equal [:mqtt_qos]
      _(opts).must_equal({ mqtt_qos: 1, timeout: 30 })
    end

    it 'returns existing options_config' do
      existing_config = JsonRpcKit::TransportOptions.new(prefix: 'mqtt_')
      opts = { options_config: existing_config, mqtt_qos: 1 }
      
      opts_config = JsonRpcKit::TransportOptions.create_from_opts(opts)
      
      _(opts_config).must_be_same_as existing_config
      _(opts).must_equal({ mqtt_qos: 1 })
    end
  end
end
