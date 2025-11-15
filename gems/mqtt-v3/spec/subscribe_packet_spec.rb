# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packet/subscribe'
require_relative '../lib/mqtt/v3/packet/sub_ack'
require_relative '../lib/mqtt/v3/packet/unsubscribe'
require_relative '../lib/mqtt/v3/packet/unsub_ack'
require_relative '../lib/mqtt/v3/packet/publish'

describe 'MQTT::V3::Packet::Subscribe' do
  it 'serialises SUBSCRIBE packet' do
    data = { packet_identifier: 1470, topic_filters: ['demo'] }
    packet = MQTT::V3::Packet::Subscribe.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first.topic_filter).must_equal('demo')
    _(packet.topic_filters.first.requested_qos).must_equal(0)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('82 09 05 be 00 04 64 65 6d 6f 00'.b)
    packet = MQTT::V3::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:subscribe)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first.topic_filter).must_equal('demo')
    _(packet.topic_filters.first.requested_qos).must_equal(0)
  end

  it 'serialises SUBACK packet' do
    # SUBACK 90 04 05 be 00 02
    data = { packet_identifier: 1470, return_codes: [2] }
    packet = MQTT::V3::Packet::SubAck.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.return_codes.size).must_equal(1)
    _(packet.return_codes.first).must_equal(2)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('90 03 05 be 02'.b)
    packet = MQTT::V3::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:suback)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.return_codes.size).must_equal(1)
    _(packet.return_codes.first).must_equal(2)
  end

  it 'serialises UNSUBSCRIBE packet' do
    data = { packet_identifier: 1470, topic_filters: ['demo'] }
    packet = MQTT::V3::Packet::Unsubscribe.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first).must_equal('demo')
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('a2 08 05 be 00 04 64 65 6d 6f'.b)
    packet = MQTT::V3::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:unsubscribe)
    _(packet.topic_filters.size).must_equal(1)
    _(packet.topic_filters.first).must_equal('demo')
  end

  it 'serialises UNSUBACK packet' do
    # SUBACK 90 04 05 be 00 02
    data = { packet_identifier: 1470 }
    packet = MQTT::V3::Packet::UnsubAck.new(**data)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.success?).must_equal(true)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('b0 02 05 be'.b)
    packet = MQTT::V3::Packet.deserialize(io.tap(&:rewind))
    _(packet.packet_name).must_equal(:unsuback)
    _(packet.packet_identifier).must_equal(1470)
    _(packet.success?).must_equal(true)
  end



  describe 'filter status' do
    let(:sub) { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b', 'c']) }

    it 'classifies successful subscriptions' do
      suback = MQTT::V3::Packet::SubAck.new(packet_identifier: 1, return_codes: [0, 1, 2])
      status = sub.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:success)
      _(status['c']).must_equal(:success)
    end

    it 'classifies failed subscriptions' do
      suback = MQTT::V3::Packet::SubAck.new(packet_identifier: 1, return_codes: [0, 0x80, 2])
      status = sub.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:failed)
      _(status['c']).must_equal(:success)
    end

    it 'classifies qos limited subscriptions' do
      sub_qos2 = MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b'], max_qos: 2)
      suback = MQTT::V3::Packet::SubAck.new(packet_identifier: 1, return_codes: [2, 1])
      status = sub_qos2.filter_status(suback)
      _(status['a']).must_equal(:success)
      _(status['b']).must_equal(:qos_limited)
    end
  end

  describe 'subscribed topic filters' do
    let(:sub) { MQTT::V3::Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['a', 'b', 'c']) }

    it 'returns all filters for successful suback' do
      suback = MQTT::V3::Packet::SubAck.new(packet_identifier: 1, return_codes: [0, 1, 2])
      _(sub.subscribed_topic_filters(suback)).must_equal(['a', 'b', 'c'])
    end

    it 'excludes failed filters' do
      suback = MQTT::V3::Packet::SubAck.new(packet_identifier: 1, return_codes: [0, 0x80, 2])
      _(sub.subscribed_topic_filters(suback)).must_equal(['a', 'c'])
    end
  end
end
