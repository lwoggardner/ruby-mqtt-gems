# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packet'
require_relative '../lib/mqtt/v5/packet/publish'
require_relative '../lib/mqtt/v5/topic_alias'

describe 'MQTT::V5::TopicAlias' do
  describe 'Cache' do
    let(:cache) { MQTT::V5::TopicAlias::Cache.new(max: 3) }

    it 'creates nil cache for zero or nil maximum' do
      _(MQTT::V5::TopicAlias::Cache.create(0)).must_be_nil
      _(MQTT::V5::TopicAlias::Cache.create(nil)).must_be_nil
      _(MQTT::V5::TopicAlias::Cache.create(5)).wont_be_nil
    end

    it 'assigns sequential alias ids' do
      _(cache.assign).must_equal 1
      _(cache.assign).must_equal 2
      _(cache.assign).must_equal 3
      _(cache.assign).must_equal false
    end

    it 'adds bidirectional mapping' do
      cache.add(1, 'topic/a')
      _(cache.resolve(1)).must_equal 'topic/a'
      _(cache.resolve('topic/a')).must_equal 1
    end

    it 'reuses freed alias ids' do
      cache.add(1, 'topic/a')
      cache.add(2, 'topic/b')
      cache.remove('topic/a')
      
      _(cache.assign).must_equal 1
    end

    it 'tracks size correctly' do
      _(cache.size).must_equal 0
      cache.add(1, 'topic/a')
      _(cache.size).must_equal 1
      cache.remove('topic/a')
      _(cache.size).must_equal 0
    end

    it 'reports full when all slots used' do
      _(cache.full?).must_equal false
      cache.assign
      cache.assign
      cache.assign
      _(cache.full?).must_equal true
    end

    it 'tracks cached bytes' do
      cache.add(1, 'short')
      _(cache.cached_bytes).must_equal 5
      cache.add(2, 'longer/topic')
      _(cache.cached_bytes).must_equal 17
      cache.remove('short')
      _(cache.cached_bytes).must_equal 12
    end

    it 'returns list of topics' do
      cache.add(1, 'topic/a')
      cache.add(2, 'topic/b')
      _(cache.topics).must_equal ['topic/a', 'topic/b']
    end
  end

  describe 'LRUPolicy' do
    let(:lru) { MQTT::V5::TopicAlias::LRUPolicy.new }

    it 'evicts least recently used topic' do
      lru.alias_hit('topic/a')
      lru.alias_hit('topic/b')
      lru.alias_hit('topic/c')
      lru.alias_hit('topic/a')
      
      evicted = lru.evict('topic/d') { ['topic/a', 'topic/b', 'topic/c'] }
      _(evicted).must_equal 'topic/b'
    end

    it 'updates access order on hit' do
      lru.alias_hit('topic/a')
      lru.alias_hit('topic/b')
      lru.alias_hit('topic/a')
      
      evicted = lru.evict('new') { ['topic/a', 'topic/b'] }
      _(evicted).must_equal 'topic/b'
    end

    it 'cleans up on eviction' do
      lru.alias_hit('topic/a')
      lru.alias_hit('topic/b')
      lru.alias_evicted('topic/a')
      
      evicted = lru.evict('new') { ['topic/b'] }
      _(evicted).must_equal 'topic/b'
    end
  end

  describe 'FrequencyWeightedPolicy' do
    let(:policy) { MQTT::V5::TopicAlias::FrequencyWeightedPolicy.new }

    it 'evicts topic with lowest frequency * bytesize score' do
      policy.alias_hit('ab')
      policy.alias_hit('ab')
      policy.alias_hit('xyz')
      
      evicted = policy.evict('new') { ['ab', 'xyz'] }
      _(evicted).must_equal 'xyz'
    end

    it 'tracks hit counts' do
      policy.alias_hit('topic/a')
      policy.alias_hit('topic/a')
      policy.alias_hit('topic/b')
      
      _(policy.hits['topic/a']).must_equal 2
      _(policy.hits['topic/b']).must_equal 1
    end

    it 'increments hit count even when eviction fails' do
      policy.alias_hit('longertopic')
      policy.alias_hit('longertopic')
      
      evicted = policy.evict('x') { ['longertopic'] }
      _(evicted).must_be_nil
      _(policy.hits['x']).must_equal 1
    end

    it 'cleans up hit counts' do
      policy.alias_hit('topic/a')
      policy.alias_hit('topic/b')
      policy.clean!('topic/a')
      
      _(policy.hits['topic/a']).must_equal 0
      _(policy.hits['topic/b']).must_equal 1
    end

    it 'rejects new topic with lower score' do
      policy.alias_hit('longertopic')
      policy.alias_hit('longertopic')
      
      evicted = policy.evict('x') { ['longertopic'] }
      _(evicted).must_be_nil
    end
  end

  describe 'LengthWeightedPolicy' do
    let(:policy) { MQTT::V5::TopicAlias::LengthWeightedPolicy.new }

    it 'evicts shortest topic' do
      policy.alias_hit('short')
      policy.alias_hit('verylongtopic')
      
      evicted = policy.evict('medium') { ['short', 'verylongtopic'] }
      _(evicted).must_equal 'short'
    end

    it 'rejects new topic shorter than minimum' do
      policy.alias_hit('longertopic')
      
      evicted = policy.evict('x') { ['longertopic'] }
      _(evicted).must_be_nil
    end

    it 'updates minimum score on alias hit' do
      policy.alias_hit('verylongtopic')
      policy.alias_hit('short')
      
      evicted = policy.evict('medium') { ['verylongtopic', 'short'] }
      _(evicted).must_equal 'short'
    end
  end

  describe 'Manager' do
    let(:manager) { MQTT::V5::TopicAlias::Manager.new(send_maximum: 3) }
    let(:connack) { Minitest::Mock.new }
    let(:connect) { Minitest::Mock.new }

    before do
      connack.expect(:topic_alias_maximum, 5)
      connect.expect(:topic_alias_maximum, 10)
    end

    it 'initializes without caches' do
      _(manager.incoming).must_be_nil
      _(manager.outgoing).must_be_nil
    end

    it 'defaults to LRUPolicy policy when maximum is positive' do
      _(manager.policy.must_be_instance_of MQTT::V5::TopicAlias::LRUPolicy)
    end

    it 'has no policy when maximum is zero' do
      mgr = MQTT::V5::TopicAlias::Manager.new(send_maximum: 0)
      _(mgr.policy).must_be_nil
    end

    it 'clears incoming cache from CONNECT packet' do
      manager.clear_incoming!(connect)
      _(manager.incoming).wont_be_nil
      _(manager.incoming.max).must_equal 10
    end

    it 'clears outgoing cache from CONNACK packet' do
      manager.clear_outgoing!(connack)
      _(manager.outgoing).wont_be_nil
      _(manager.outgoing.max).must_equal 3
    end

    it 'limits outgoing to minimum of configured and broker maximum' do
      connack2 = Minitest::Mock.new
      connack2.expect(:topic_alias_maximum, 2)
      manager.clear_outgoing!(connack2)
      _(manager.outgoing.max).must_equal 2
    end

    describe 'handle_outgoing' do
      before do
        manager.clear_outgoing!(connack)
      end

      it 'assigns alias on first publish' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', qos: 0, assign_alias: true)
        manager.handle_outgoing(packet)
        
        _(packet.topic_alias).must_equal 1
        _(packet.topic_name).must_equal 'test/topic'
      end

      it 'reuses alias on subsequent publish' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', qos: 0, assign_alias: true)
        manager.handle_outgoing(packet)
        _(packet.topic_alias).must_equal 1

        packet2 = MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', qos: 0, assign_alias: true)
        manager.handle_outgoing(packet2)
        _(packet2.topic_alias).must_equal 1
        _(packet2.topic_name).must_equal ''
      end

      it 'skips aliasing when assign_alias is false' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', qos: 0, assign_alias: false)
        manager.handle_outgoing(packet)
        _(packet.topic_alias).must_be_nil
      end

      it 'evicts when cache full' do
        3.times do |i|
          p = MQTT::V5::Packet::Publish.new(topic_name: "topic/#{i}", qos: 0, assign_alias: true)
          manager.handle_outgoing(p)
          _(p.topic_alias).must_equal i + 1
        end

        packet = MQTT::V5::Packet::Publish.new(topic_name: 'topic/new', qos: 0, assign_alias: true)
        manager.handle_outgoing(packet)
        _(packet.topic_alias).must_equal 1
      end
    end

    describe 'handle_incoming' do
      before do
        manager.clear_incoming!(connect)
      end

      it 'registers new alias mapping' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: 'test/topic', topic_alias: 1, qos: 0)
        manager.handle_incoming(packet)
        _(manager.incoming.resolve(1)).must_equal 'test/topic'
      end

      it 'resolves alias-only packet' do
        manager.incoming.add(5, 'existing/topic')
        
        packet = MQTT::V5::Packet::Publish.new(topic_name: '', topic_alias: 5, qos: 0)
        manager.handle_incoming(packet)
        _(packet.topic_name).must_equal 'existing/topic'
      end

      it 'raises on unknown alias' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: '', topic_alias: 99, qos: 0)
        _(-> { manager.handle_incoming(packet) }).must_raise MQTT::V5::TopicAliasInvalid
      end

      it 'raises on alias exceeding maximum' do
        packet = MQTT::V5::Packet::Publish.new(topic_name: '', topic_alias: 999, qos: 0)
        _(-> { manager.handle_incoming(packet) }).must_raise MQTT::V5::TopicAliasInvalid
      end
    end
  end
end
