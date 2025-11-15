# frozen_string_literal: true
require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packets'

describe 'MQTT 3.1.1 Specification Compliance' do
  describe 'PUBLISH Packet' do
    let(:packet_class) { MQTT::V3::Packet::Publish }

    it 'MQTT-2.3.1-7: QoS 0 PUBLISH MUST NOT contain Packet Identifier' do
      packet = packet_class.new(topic_name: 'test', qos: 0)
      io = StringIO.new
      packet.serialize(io)
      io.rewind
      deserialized = MQTT::V3::Packet.deserialize(io)
      _(deserialized.packet_identifier).must_equal(0)
    end

    it 'MQTT-3.3.1-4: QoS MUST NOT have both bits set to 1' do
      _(-> { packet_class.new(topic_name: 'test', qos: 3) }).must_raise ArgumentError
    end

    it 'MQTT-3.3.2-1: Topic Name MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(topic_name: "test\u0000", qos: 0) }).must_raise EncodingError
    end

    it 'MQTT-4.7.1-1: Topic Name MUST NOT contain wildcard characters' do
      _(-> { packet_class.new(topic_name: 'test/#', qos: 0) }).must_raise ArgumentError
      _(-> { packet_class.new(topic_name: 'test/+/topic', qos: 0) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Topic Name MUST be at least one character' do
      _(-> { packet_class.new(topic_name: '', qos: 0) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-2: Topic Name MUST NOT include null character' do
      _(-> { packet_class.new(topic_name: "test\u0000topic", qos: 0) }).must_raise EncodingError
    end
  end

  describe 'SUBSCRIBE Packet' do
    it 'MQTT-3.8.3-1: Topic Filters MUST be UTF-8 Encoded Strings' do
      _(-> { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ["test\u0000"]) }).must_raise EncodingError
    end

    it 'MQTT-3.8.3-1: SUBSCRIBE Payload MUST contain at least one Topic Filter' do
      _(-> { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: []) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Topic Filters MUST be at least one character' do
      _(-> { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['']) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-2: Topic Filters MUST NOT include null character' do
      _(-> { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ["test\u0000filter"]) }).must_raise EncodingError
    end
  end

  describe 'UNSUBSCRIBE Packet' do
    it 'MQTT-3.10.3-2: Topic Filters MUST be UTF-8 Encoded Strings' do
      _(-> { MQTT::V3::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: ["test\u0000"]) }).must_raise EncodingError
    end

    it 'MQTT-3.10.3-1: UNSUBSCRIBE Payload MUST contain at least one Topic Filter' do
      _(-> { MQTT::V3::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: []) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Topic Filters MUST be at least one character' do
      _(-> { MQTT::V3::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: ['']) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-2: Topic Filters MUST NOT include null character' do
      _(-> { MQTT::V3::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: ["test\u0000filter"]) }).must_raise EncodingError
    end
  end

  describe 'CONNECT Packet' do
    it 'MQTT-3.1.2-9: Will Topic and Will Payload MUST be present if Will Flag is set' do
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: nil, will_payload: 'payload') }).must_raise ArgumentError
      MQTT::V3::Packet::Connect.new(will_topic: 'topic', will_payload: nil) # empty payload is valid
    end

    it 'MQTT-3.1.3-3: ClientID MUST be UTF-8 Encoded String' do
      _(-> { MQTT::V3::Packet::Connect.new(client_id: "client\u0000id") }).must_raise EncodingError
    end

    it 'MQTT-3.1.3-9: Will Topic MUST be UTF-8 Encoded String' do
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: "will\u0000topic", will_payload: 'test') }).must_raise EncodingError
    end

    it 'MQTT-3.1.3-10: User Name MUST be UTF-8 Encoded String' do
      _(-> { MQTT::V3::Packet::Connect.new(username: "user\u0000name") }).must_raise EncodingError
    end

    it 'MQTT-4.7.1-1: Will Topic MUST NOT contain wildcard characters' do
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: 'will/#', will_payload: 'test') }).must_raise ArgumentError
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: 'will/+/topic', will_payload: 'test') }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Will Topic MUST be at least one character' do
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: '', will_payload: 'test') }).must_raise ArgumentError
    end

    it 'MQTT-3.1.2-11/17: Will Retain MUST be false if Will Flag is not set' do
      _(-> { MQTT::V3::Packet::Connect.new(will_retain: true) }).must_raise ArgumentError
    end

    it 'MQTT-3.1.2-13: Will QoS MUST be 0, 1, or 2' do
      _(-> { MQTT::V3::Packet::Connect.new(will_topic: 'topic', will_payload: 'test', will_qos: 3) }).must_raise ArgumentError
    end

    it 'MQTT-3.1.2-14: Will QoS MUST be 0 if Will Flag is not set' do
      _(-> { MQTT::V3::Packet::Connect.new(will_qos: 1) }).must_raise ArgumentError
    end
  end

  describe 'Reserved Flags' do
    {
      connect: 0b0000,
      connack: 0b0000,
      puback: 0b0000,
      pubrec: 0b0000,
      pubrel: 0b0010,
      pubcomp: 0b0000,
      subscribe: 0b0010,
      suback: 0b0000,
      unsubscribe: 0b0010,
      unsuback: 0b0000,
      pingreq: 0b0000,
      pingresp: 0b0000,
      disconnect: 0b0000
    }.each do |packet_name, reserved_value|
      it "MQTT-2.2.2-2: Reserved flag for #{packet_name.upcase} MUST be #{format('%04b', reserved_value)}" do
        packet = MQTT::V3::Packet.build_packet(packet_name)

        sio = StringIO.new.binmode
        packet.serialize(sio)
        sio.rewind
        header_byte = sio.readbyte
        expect(header_byte & 0b000_1111).must_equal(reserved_value)

        sio.ungetbyte(header_byte + 1)
        expect(-> { MQTT::V3::Packet.deserialize(sio) }).must_raise MQTT::Error
      end
    end
  end
end
