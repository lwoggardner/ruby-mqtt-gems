# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packet/subscribe'
require_relative '../lib/mqtt/v5/packet/sub_ack'
require_relative '../lib/mqtt/v5/packet/unsubscribe'
require_relative '../lib/mqtt/v5/packet/unsub_ack'
require_relative '../lib/mqtt/v5/packet/publish'

# https://www.emqx.com/en/blog/mqtt-5-0-control-packets-03-subscribe-unsubscribe
#  mqttx sub --hostname broker.emqx.io --mqtt-version 5 --topic demo --qos 2
describe 'MQTT::V5::Packet::Subscribe' do
  it 'serialises SUBSCRIBE packet' do
    data = { packet_identifier: 1470, topic_filters: ['demo'], max_qos: 2 }
    packet = MQTT::V5::Packet::Subscribe.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first.topic_filter).must_equal('demo')
    _(packet.topic_filters.first.max_qos).must_equal(2)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    # SUBSCRIBE 82 0a 05 be 00 00 04 64 65 6d 6f 02
    _(s).must_equal('82 0a 05 be 00 00 04 64 65 6d 6f 02'.b)
    packet = MQTT::V5::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:subscribe)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first.topic_filter).must_equal('demo')
    _(packet.topic_filters.first.max_qos).must_equal(2)
  end

  it 'serialises SUBACK packet' do
    # SUBACK 90 04 05 be 00 02
    data = { packet_identifier: 1470, reason_codes: [2] }
    packet = MQTT::V5::Packet::SubAck.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.reason_codes.size).must_equal(1)
    _(packet.reason_codes.first).must_equal(2)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('90 04 05 be 00 02'.b)
    packet = MQTT::V5::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:suback)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.reason_codes.size).must_equal(1)
    _(packet.reason_codes.first).must_equal(2)
  end

  it 'serialises UNSUBSCRIBE packet' do
    data = { packet_identifier: 1470, topic_filters: ['demo'] }
    packet = MQTT::V5::Packet::Unsubscribe.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first).must_equal('demo')
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('a2 09 05 be 00 00 04 64 65 6d 6f'.b)
    packet = MQTT::V5::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:unsubscribe)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first).must_equal('demo')
  end

  it 'serialises UNSUBACK packet' do
    # SUBACK 90 04 05 be 00 02
    data = { packet_identifier: 1470, reason_codes: [17] }
    packet = MQTT::V5::Packet::UnsubAck.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.reason_codes.size).must_equal(1)
    _(packet.reason_codes.first).must_equal(17)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('b0 04 05 be 00 11'.b)
    packet = MQTT::V5::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:unsuback)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.reason_codes.size).must_equal(1)
    _(packet.reason_codes.first).must_equal(17)
  end



  describe 'filter status' do
    let(:sub) { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b', 'c']) }

    it 'classifies successful subscriptions' do
      suback = MQTT::V5::Packet::SubAck.new(packet_identifier: 1, reason_codes: [0, 1, 2])
      status = sub.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:success)
      _(status['c']).must_equal(:success)
    end

    it 'classifies failed subscriptions' do
      suback = MQTT::V5::Packet::SubAck.new(packet_identifier: 1, reason_codes: [0, 0x80, 2])
      status = sub.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:failed)
      _(status['c']).must_equal(:success)
    end

    it 'classifies qos limited subscriptions' do
      sub_qos2 = MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b'], max_qos: 2)
      suback = MQTT::V5::Packet::SubAck.new(packet_identifier: 1, reason_codes: [2, 1])
      status = sub_qos2.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:qos_limited)
    end
  end

  describe 'subscribed topic filters' do
    let(:sub) { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b', 'c']) }

    it 'returns all filters for successful suback' do
      suback = MQTT::V5::Packet::SubAck.new(packet_identifier: 1, reason_codes: [0, 1, 2])
      _(sub.subscribed_topic_filters(suback)).must_equal(['a', 'b', 'c'])
    end

    it 'excludes failed filters' do
      suback = MQTT::V5::Packet::SubAck.new(packet_identifier: 1, reason_codes: [0, 0x80, 2])
      _(sub.subscribed_topic_filters(suback)).must_equal(['a', 'c'])
    end
  end

  describe 'MQTT 5.0 Compliance' do
    it 'MQTT-3.8.3-1: Topic Filters MUST be UTF-8 Encoded Strings' do
      _(-> { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ["test\u0000"]) }).must_raise EncodingError
    end

    it 'MQTT-3.8.3-2: MUST contain at least one Topic Filter' do
      _(-> { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: []) }).must_raise ArgumentError
    end

    it 'MQTT-3.10.3-1: UNSUBSCRIBE Topic Filters MUST be UTF-8 Encoded Strings' do
      _(-> { MQTT::V5::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: ["test\u0000"]) }).must_raise EncodingError
    end

    it 'MQTT-3.10.3-2: UNSUBSCRIBE MUST contain at least one Topic Filter' do
      _(-> { MQTT::V5::Packet::Unsubscribe.new(packet_identifier: 1, topic_filters: []) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Topic Filters MUST be at least one character' do
      _(-> { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['']) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-2: Topic Filters MUST NOT include null character' do
      _(-> { MQTT::V5::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ["test\u0000filter"]) }).must_raise EncodingError
    end
  end

end
