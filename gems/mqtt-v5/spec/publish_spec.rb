# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packet/publish'

describe 'MQTT::V5::Packet::Publish' do
  let(:packet_class) { MQTT::V5::Packet::Publish }
  it 'serialises PUBLISH' do
    # https://www.emqx.com/en/blog/mqtt-5-0-control-packets-02-publish-puback
    data = {
      message_expiry_interval: 300,
      qos: 0,
      retain: false,
      topic_name: 'request',
      response_topic: 'response',
      payload: 'This is a QoS 0 message'
    }
    packet = packet_class.new(**data)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('30 31 00 07 72 65 71 75 65 73 74 10 02 00 00 01 2c 08 00 08 72 65 73 70 6f 6e 73 65 54 68 69 73 20 69 73 20 61 20 51 6f 53 20 30 20 6d 65 73 73 61 67 65'.b)
  end

  it 'serialises PUBLISH with correlation_data' do
    data = {
      qos: 0,
      topic_name: 'test/topic',
      correlation_data: 'my-correlation-id',
      payload: 'test payload'
    }
    packet = packet_class.new(**data)
    _(packet.correlation_data).must_equal('my-correlation-id')
    
    io = StringIO.new
    packet.serialize(io)
    io.rewind
    
    deserialized = MQTT::V5::Packet.deserialize(io)
    _(deserialized.correlation_data).must_equal('my-correlation-id')
    _(deserialized.payload).must_equal('test payload')
  end

  describe 'MQTT 5.0 Compliance' do
    it 'MQTT-2.2.1-2: QoS 0 PUBLISH MUST NOT contain Packet Identifier' do
      packet = packet_class.new(topic_name: 'test', qos: 0)
      io = StringIO.new
      packet.serialize(io)
      io.rewind
      deserialized = MQTT::V5::Packet.deserialize(io)
      _(deserialized.packet_identifier).must_equal(0)
    end

    it 'MQTT-3.3.1-4: MUST NOT have both QoS bits set to 1' do
      _(-> { packet_class.new(topic_name: 'test', qos: 3) }).must_raise ArgumentError
    end

    it 'MQTT-3.3.2-1: Topic Name MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(topic_name: "test\u0000", qos: 0) }).must_raise EncodingError
    end

    it 'MQTT-3.3.2-2: Topic Name MUST NOT contain wildcards' do
      _(-> { packet_class.new(topic_name: 'test/#', qos: 0) }).must_raise ArgumentError
      _(-> { packet_class.new(topic_name: 'test/+/topic', qos: 0) }).must_raise ArgumentError
    end

    it 'MQTT-3.3.2-8: MUST NOT send Topic Alias with value 0' do
      skip 'Topic aliases not yet implemented'
      _(-> { packet_class.new(topic_name: 'test', qos: 0, topic_alias: 0) }).must_raise ArgumentError
    end

    it 'MQTT-3.3.2-13: Response Topic MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(topic_name: 'test', qos: 0, response_topic: "resp\u0000") }).must_raise EncodingError
    end

    it 'MQTT-3.3.2-14: Response Topic MUST NOT contain wildcards' do
      _(-> { packet_class.new(topic_name: 'test', qos: 0, response_topic: 'resp/#') }).must_raise ArgumentError
      _(-> { packet_class.new(topic_name: 'test', qos: 0, response_topic: 'resp/+') }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Topic Name MUST be at least one character' do
      _(-> { packet_class.new(topic_name: '', qos: 0) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-2: Topic Name MUST NOT include null character' do
      _(-> { packet_class.new(topic_name: "test\u0000topic", qos: 0) }).must_raise EncodingError
    end
  end

  describe 'Topic Alias Interface' do
    it 'stores assign_alias flag from constructor' do
      packet = packet_class.new(topic_name: 'test', qos: 0, assign_alias: true)
      _(packet.assign_alias?).must_equal true

      packet = packet_class.new(topic_name: 'test', qos: 0, assign_alias: false)
      _(packet.assign_alias?).must_equal false

      packet = packet_class.new(topic_name: 'test', qos: 0)
      _(packet.assign_alias?).must_be_nil
    end

    it 'applies alias with both alias and name' do
      packet = packet_class.new(topic_name: 'original/topic', qos: 0)
      packet.apply_alias(alias: 5, name: 'original/topic')
      
      _(packet.topic_alias).must_equal 5
      _(packet.topic_name).must_equal 'original/topic'
    end

    it 'applies alias with empty name for reuse' do
      packet = packet_class.new(topic_name: 'original/topic', qos: 0)
      packet.apply_alias(alias: 5, name: '')
      
      _(packet.topic_alias).must_equal 5
      _(packet.topic_name).must_equal ''
    end

    it 'applies alias to resolve incoming alias-only packet' do
      packet = packet_class.new(topic_name: '', topic_alias: 3, qos: 0)
      packet.apply_alias(name: 'resolved/topic')
      
      _(packet.topic_name).must_equal 'resolved/topic'
      _(packet.topic_alias).must_equal 3
    end

    it 'overrides original topic_alias from properties' do
      packet = packet_class.new(topic_name: 'test', topic_alias: 99, qos: 0)
      packet.apply_alias(alias: 5)
      
      _(packet.topic_alias).must_equal 5
    end
  end

  describe 'response_topic serialization' do
    it 'serializes and deserializes response_topic property' do
      packet = packet_class.new(topic_name: 'test', qos: 0, response_topic: 'resp', payload: 'test')
      io = StringIO.new
      packet.serialize(io)
      
      io.rewind
      deserialized = MQTT::V5::Packet.deserialize(io)
      _(deserialized.response_topic).must_equal 'resp'
    end
  end
end
